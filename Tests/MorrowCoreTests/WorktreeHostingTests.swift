import XCTest
@testable import MorrowCore

final class WorktreeHostingTests: XCTestCase {
    private func fixture() throws -> (URL, URL, URL, SiteManager) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let projects = root.appendingPathComponent("projects")
        let main = projects.appendingPathComponent("main")
        let worktree = projects.appendingPathComponent("feature")
        let runner = CommandRunner()
        try runner.run("/usr/bin/git", ["init", "-q", main.path], environment: [:]).checked()
        try runner.run("/usr/bin/git", ["-C", main.path, "-c", "user.name=kkz6", "-c", "user.email=karthickk1996@hotmail.com", "-c", "commit.gpgsign=false", "-c", "core.hooksPath=/dev/null", "commit", "--allow-empty", "-qm", "Test fixture"], environment: [:]).checked()
        try runner.run("/usr/bin/git", ["-C", main.path, "-c", "core.hooksPath=/dev/null", "worktree", "add", "-q", "--detach", worktree.path], environment: [:]).checked()
        let manager = SiteManager(store: StateStore(root: root.appendingPathComponent("state")))
        try manager.park(projects.path)
        return (projects, main, worktree, manager)
    }

    func testLegacyStateKeepsExistingWorktreesHosted() throws {
        let directory = ProjectDirectory(path: "/projects")
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(directory)) as? [String: Any])
        json.removeValue(forKey: "includeWorktrees")
        let decoded = try JSONDecoder().decode(ProjectDirectory.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertTrue(decoded.includeWorktrees)
        var siteJSON = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(LocalSite(domain: "site.test", path: "/site", documentRoot: "/site", mode: .files))) as? [String: Any])
        siteJSON.removeValue(forKey: "worktreeExcluded")
        let site = try JSONDecoder().decode(LocalSite.self, from: JSONSerialization.data(withJSONObject: siteJSON))
        XCTAssertFalse(site.isIgnoredForHosting)
    }

    func testWorktreePolicyRemovesRoutesAndRestoresSavedConfiguration() throws {
        let (_, main, worktree, manager) = try fixture()
        let directory = try XCTUnwrap(manager.store.load().web.directories.first)
        var site = try manager.resolve("feature.test")
        site.domain = "custom.test"; site.https = true
        try manager.update(site)
        try manager.setDirectory(directory.id, includeWorktrees: false)
        try manager.refreshProjects()
        let web = try manager.store.load().web
        let excluded = try manager.resolve("custom.test")
        XCTAssertEqual(excluded.id, site.id)
        XCTAssertTrue(excluded.worktreeExcluded)
        XCTAssertTrue(excluded.https)
        XCTAssertFalse(excluded.ignored)
        XCTAssertFalse(try manager.caddyConfiguration(web).contains("custom.test"))
        XCTAssertTrue(try manager.caddyConfiguration(web).contains("main.test"))
        XCTAssertTrue(manager.secureSites(web).isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: worktree.appendingPathComponent(".git").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: main.appendingPathComponent(".git").path))
        XCTAssertFalse(try manager.store.load().web.directories[0].includeWorktrees)

        try manager.setDirectory(directory.id, includeWorktrees: true)
        let restored = try manager.resolve("custom.test")
        XCTAssertFalse(restored.worktreeExcluded)
        XCTAssertEqual(restored.id, site.id)
        XCTAssertTrue(restored.https)
        XCTAssertTrue(try manager.caddyConfiguration(manager.store.load().web).contains("https://custom.test"))
    }

    func testExplicitLinksAndIndividualIgnoreRemainIndependent() throws {
        let (_, _, worktree, manager) = try fixture()
        let directory = try XCTUnwrap(manager.store.load().web.directories.first)
        let site = try manager.resolve("feature.test")
        try manager.ignore(site.id, ignored: true)
        try manager.setDirectory(directory.id, includeWorktrees: false)
        try manager.setDirectory(directory.id, includeWorktrees: true)
        XCTAssertTrue(try manager.resolve("feature.test").ignored)
        try manager.setDirectory(directory.id, includeWorktrees: false)
        let explicit = try manager.link(path: worktree.path, https: true)
        try manager.refreshProjects()
        let linked = try manager.resolve(explicit.domain)
        XCTAssertNil(linked.directoryID)
        XCTAssertFalse(linked.isIgnoredForHosting)
        XCTAssertTrue(try manager.caddyConfiguration(manager.store.load().web).contains("https://feature.test"))
    }

    func testDetectionHandlesRelativeGitfilesWithoutExcludingSubmodules() throws {
        let (projects, main, worktree, manager) = try fixture()
        XCTAssertTrue(GitWorktree.isLinked(at: worktree))
        XCTAssertFalse(GitWorktree.isLinked(at: main))
        try "gitdir: ../main/.git/worktrees/feature\n".write(to: worktree.appendingPathComponent(".git"), atomically: true, encoding: .utf8)
        XCTAssertTrue(GitWorktree.isLinked(at: worktree))
        let submodule = projects.appendingPathComponent("submodule")
        let metadata = main.appendingPathComponent(".git/modules/submodule")
        try FileManager.default.createDirectory(at: submodule, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: metadata, withIntermediateDirectories: true)
        try "gitdir: \(metadata.path)\n".write(to: submodule.appendingPathComponent(".git"), atomically: true, encoding: .utf8)
        XCTAssertFalse(GitWorktree.isLinked(at: submodule))
        let directory = try XCTUnwrap(manager.store.load().web.directories.first)
        try manager.setDirectory(directory.id, includeWorktrees: false)
        XCTAssertFalse(try manager.resolve("submodule.test").isIgnoredForHosting)

        let newWorktree = projects.appendingPathComponent("next")
        try CommandRunner().run("/usr/bin/git", ["-C", main.path, "-c", "core.hooksPath=/dev/null", "worktree", "add", "-q", "--detach", newWorktree.path], environment: [:]).checked()
        try manager.refreshProjects()
        XCTAssertTrue(try manager.resolve("next.test").worktreeExcluded)
    }

    func testFailedRouteValidationKeepsSavedPolicyAndRestoresOnlyDirectoryMonitor() throws {
        let (_, _, _, original) = try fixture()
        let directory = try XCTUnwrap(original.store.load().web.directories.first)
        try original.store.update {
            $0.web.enabled = true; $0.web.caddyPath = "/fixture/caddy"; $0.web.dnsmasqPath = "/fixture/dnsmasq"
            $0.web.cliPath = "/previous/morrow"
        }
        let runner = RejectConfigurationRunner()
        let manager = SiteManager(store: original.store, runner: runner)
        XCTAssertThrowsError(try manager.setDirectory(directory.id, includeWorktrees: false, cli: URL(fileURLWithPath: "/usr/bin/true")))
        let web = try manager.store.load().web
        XCTAssertTrue(web.directories[0].includeWorktrees)
        XCTAssertFalse(try manager.resolve("feature.test").worktreeExcluded)
        let jobs = runner.calls.filter { $0.first == "/bin/launchctl" && ["bootout", "bootstrap"].contains($0.dropFirst().first ?? "") }
        XCTAssertFalse(jobs.isEmpty)
        XCTAssertTrue(jobs.allSatisfy { $0.joined(separator: " ").contains("watch") })
        let plist = try XCTUnwrap(PropertyListSerialization.propertyList(from: Data(contentsOf: manager.job("watch", web: web)), format: nil) as? [String: Any])
        XCTAssertTrue((plist["ProgramArguments"] as? [String])?.contains("/previous/morrow") == true)
    }

    func testGroupingKeepsWorktreesUnderTheirIgnoredMainWithoutChangingHosting() throws {
        let (_, _, _, manager) = try fixture()
        let main = try manager.resolve("main.test")
        try manager.ignore(main.id, ignored: true)
        let before = try manager.store.load().web
        let routes = try manager.caddyConfiguration(before)
        let groups = SiteProjectGroup.groups(for: before.sites)
        let group = try XCTUnwrap(groups.first)
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(group.project?.domain, "main.test")
        XCTAssertEqual(group.project?.ignored, true)
        XCTAssertEqual(group.worktrees.map(\.domain), ["feature.test"])
        XCTAssertFalse(group.worktrees[0].isIgnoredForHosting)
        XCTAssertEqual(try manager.store.load().web, before)
        XCTAssertEqual(try manager.caddyConfiguration(manager.store.load().web), routes)
    }

    func testGroupingSearchRevealsChildAndRetainsParentContext() throws {
        let (_, _, _, manager) = try fixture()
        let group = try XCTUnwrap(SiteProjectGroup.groups(for: manager.store.load().web.sites).first)
        let childMatch = try XCTUnwrap(group.matching("  FEATURE.TEST  "))
        XCTAssertEqual(childMatch.project?.domain, "main.test")
        XCTAssertEqual(childMatch.worktrees.map(\.domain), ["feature.test"])
        XCTAssertEqual(group.matching("main.test"), group)
        XCTAssertEqual(group.matching(" \n "), group)
        XCTAssertNil(group.matching("nonexistent"))
    }

    func testUnlinkedMainStillGroupsAllWorktreesAndPreservesExcludedChildren() throws {
        let (projects, main, _, manager) = try fixture()
        try CommandRunner().run("/usr/bin/git", ["-C", main.path, "-c", "core.hooksPath=/dev/null", "worktree", "add", "-q", "--detach", projects.appendingPathComponent("next").path], environment: [:]).checked()
        let directory = try XCTUnwrap(manager.store.load().web.directories.first)
        try manager.setDirectory(directory.id, includeWorktrees: false)
        let sites = try manager.store.load().web.sites.filter { $0.path != main.path }
        let groups = SiteProjectGroup.groups(for: sites.reversed())
        XCTAssertEqual(groups.count, 1)
        let group = try XCTUnwrap(groups.first)
        XCTAssertNil(group.project)
        XCTAssertEqual(group.name, "main")
        XCTAssertEqual(group.worktrees.map(\.domain), ["feature.test", "next.test"])
        XCTAssertTrue(group.worktrees.allSatisfy(\.worktreeExcluded))
        XCTAssertEqual(group.matching("next.test")?.worktrees.map(\.domain), ["next.test"])
        XCTAssertEqual(groups, SiteProjectGroup.groups(for: sites))
    }

    func testSimilarNamesAreNotGroupedAndBrokenBackPointersStayVisible() throws {
        let (projects, main, worktree, manager) = try fixture()
        let similar = projects.appendingPathComponent("main-checkpoint")
        try FileManager.default.createDirectory(at: similar, withIntermediateDirectories: true)
        try manager.refreshProjects()
        let sites = try manager.store.load().web.sites
        let groups = SiteProjectGroup.groups(for: sites)
        XCTAssertEqual(groups.count, 2)
        XCTAssertEqual(groups.first { $0.project?.path == similar.path }?.worktrees.count, 0)
        try "/not/the/linked/folder/.git\n".write(to: main.appendingPathComponent(".git/worktrees/feature/gitdir"), atomically: true, encoding: .utf8)
        let broken = SiteProjectGroup.groups(for: sites)
        XCTAssertEqual(broken.count, 3)
        XCTAssertNotNil(broken.first { $0.project?.path == worktree.path })
    }

    func testGroupingResolvesRelativeMetadataAndSeparateMainGitDirectory() throws {
        let (projects, main, worktree, manager) = try fixture()
        let separate = projects.appendingPathComponent("metadata.git")
        try FileManager.default.moveItem(at: main.appendingPathComponent(".git"), to: separate)
        try "gitdir: ../metadata.git\n".write(to: main.appendingPathComponent(".git"), atomically: true, encoding: .utf8)
        try "gitdir: ../metadata.git/worktrees/feature\n".write(to: worktree.appendingPathComponent(".git"), atomically: true, encoding: .utf8)
        let groups = SiteProjectGroup.groups(for: try manager.store.load().web.sites)
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].project?.path, main.path)
        XCTAssertEqual(groups[0].worktrees.map(\.path), [worktree.path])
    }
}

private final class RejectConfigurationRunner: CommandRunning, @unchecked Sendable {
    private let lock = NSLock()
    private var commands: [[String]] = []
    var calls: [[String]] { lock.withLock { commands } }
    func run(_ executable: String, _ arguments: [String], environment: [String: String]) throws -> CommandResult {
        lock.withLock { commands.append([executable] + arguments) }
        if executable == "/fixture/caddy" { return CommandResult(status: 1, output: "Invalid route configuration") }
        if executable == "/bin/launchctl", arguments.first == "print" { return CommandResult(status: 1, output: "") }
        return CommandResult(status: 0, output: "")
    }
}
