import XCTest
@testable import MorrowCore

final class DiagnosticsTests: XCTestCase {
    func testCapturedSitesUseAnIsolatedPHPPoolAndNormalRoutesStayUnchanged() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = StateStore(root: root), capture = Diagnostics(store: store), sites = SiteManager(store: store)
        let project = root.appendingPathComponent("project"), normal = root.appendingPathComponent("normal")
        let prefix = root.appendingPathComponent("php")
        for folder in [project, normal, prefix.appendingPathComponent("sbin")] { try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true) }
        let fpm = prefix.appendingPathComponent("sbin/php-fpm")
        try Data().write(to: fpm); try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fpm.path)
        let php = RuntimeInstallation(engine: .php, formula: "fixture", version: "8.4.0", prefix: prefix.path, executable: prefix.appendingPathComponent("bin/php").path, source: "external")
        var web = WebWorkspace(); web.php = [php]; web.defaultPHPID = php.id
        web.sites = [LocalSite(domain: "capture.test", path: project.path, documentRoot: project.path, mode: .php), LocalSite(domain: "normal.test", path: normal.path, documentRoot: normal.path, mode: .php)]
        try capture.installAgent(path: project.path)
        try JSONEncoder().encode([DiagnosticProject(path: project.path, enabled: true)]).write(to: capture.root.appendingPathComponent("projects.json"))
        let configuration = try sites.caddyConfiguration(web)
        let normalRoute = try XCTUnwrap(configuration.components(separatedBy: "http://normal.test").last)
        XCTAssertTrue(configuration.contains("unix/" + sites.phpSocket(php, web: web, capture: true)))
        XCTAssertFalse(normalRoute.contains("PHP_VALUE"))
        XCTAssertTrue(normalRoute.contains("unix/" + sites.phpSocket(php, web: web)))
        XCTAssertNotEqual(sites.phpSocket(php, web: web), sites.phpSocket(php, web: web, capture: true))
        XCTAssertLessThan(sites.phpSocket(php, web: web, capture: true).utf8.count, 104)
        XCTAssertTrue(sites.phpComponents(web).contains(sites.captureComponent(php)))
        try JSONEncoder().encode([DiagnosticProject(path: project.path, enabled: false)]).write(to: capture.root.appendingPathComponent("projects.json"))
        XCTAssertFalse(try sites.caddyConfiguration(web).contains("PHP_VALUE"))
    }
    func testExistingPrependAndFailedRouteReloadPreserveCaptureSettings() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let store = StateStore(root: root), capture = Diagnostics(store: store)
        let php = RuntimeInstallation(engine: .php, formula: "external", version: "8.4.0", prefix: "/fixture", executable: "/usr/bin/true", source: "external")
        try store.update { $0.tools = [php]; $0.toolDefaults["php"] = php.id }
        XCTAssertThrowsError(try capture.configure(path: root.path, enabled: true, runner: CaptureRunner(existingPrepend: "/project/bootstrap.php")))
        XCTAssertTrue(try capture.projects().isEmpty)
        try store.update { $0.web.enabled = true; $0.web.caddyPath = "/fixture/caddy" }
        XCTAssertThrowsError(try capture.configure(path: root.path, enabled: true, runner: CaptureRunner(existingPrepend: "")))
        XCTAssertTrue(try capture.projects().isEmpty)
        XCTAssertNil(try capture.prepend(for: root.path))
    }
    func testFolderAliasesSelectTheSameCaptureAndDoNotMatchSiblingFolders() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let project = root.appendingPathComponent("project"), alias = root.appendingPathComponent("alias")
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: project)
        let path = try ProjectRuntimeStore.directory(project.path)
        let capture = Diagnostics(store: StateStore(root: root))
        try capture.installAgent(path: path)
        try JSONEncoder().encode([DiagnosticProject(path: path, enabled: true)]).write(to: capture.root.appendingPathComponent("projects.json"))
        XCTAssertEqual(try capture.prepend(for: alias.path), try capture.prepend(for: project.path))
        XCTAssertNil(try capture.prepend(for: project.path + "-other"))
        try JSONEncoder().encode([DiagnosticProject(path: path, enabled: false)]).write(to: capture.root.appendingPathComponent("projects.json"))
        XCTAssertNil(try capture.prepend(for: alias.path))
    }
    func testRequestReaderPreservesValidEventsAndIgnoresPartialAndSymlinkFiles() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Morrow diagnostics \(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let capture = Diagnostics(store: StateStore(root: root)), project = root.appendingPathComponent("project").path
        try capture.installAgent(path: project)
        try JSONEncoder().encode([DiagnosticProject(path: project, enabled: true)]).write(to: capture.root.appendingPathComponent("projects.json"))
        let directory = capture.directory(project).appendingPathComponent("requests")
        let line = #"{"id":"one","kind":"dump","time":123,"title":"A dump","value":{"items":[1,true,null,"hello"]},"file":null,"line":null}"#
        try Data((line + "\n{\"unfinished\"").utf8).write(to: directory.appendingPathComponent("one.jsonl"))
        try FileManager.default.createSymbolicLink(at: directory.appendingPathComponent("linked.jsonl"), withDestinationURL: directory.appendingPathComponent("one.jsonl"))
        let requests = try capture.requests()
        XCTAssertEqual(requests.count, 1); XCTAssertEqual(requests.first?.events.count, 1)
        XCTAssertNotNil(try capture.prepend(for: project + "/src"))
        XCTAssertNil(try capture.prepend(for: project + "-other"))
        XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: capture.root.appendingPathComponent("agent.php").path)[.posixPermissions] as? Int, 0o600)
        try capture.clear(project: project)
        XCTAssertTrue(try capture.requests().isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: capture.directory(project).appendingPathComponent("prepend.php").path))
    }

    func testPHPBridgeCapturesStructuredValuesAndStopsAfterDisabling() throws {
        let php = ProcessInfo.processInfo.environment["MORROW_TEST_PHP"] ?? "/opt/homebrew/bin/php"
        guard FileManager.default.isExecutableFile(atPath: php) else { throw XCTSkip("Set MORROW_TEST_PHP to run the PHP bridge integration check.") }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Morrow PHP '\(UUID())").resolvingSymlinksInPath()
        defer { try? FileManager.default.removeItem(at: root) }
        let capture = Diagnostics(store: StateStore(root: root)), project = root.appendingPathComponent("project")
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        try capture.installAgent(path: project.path)
        let settings = capture.root.appendingPathComponent("projects.json")
        try JSONEncoder().encode([DiagnosticProject(path: project.path, enabled: true)]).write(to: settings)
        let script = project.appendingPathComponent("test.php")
        try Data(#"<?php \Morrow\Diagnostics\Recorder::event('dump', 'fixture', ['hello' => ['world', 42]]); echo 'normal output';"#.utf8).write(to: script)
        let result = try CommandRunner().run(php, ["-d", "auto_prepend_file=" + capture.prepend(for: project.path)!.path, script.path]).checked()
        XCTAssertEqual(result, "normal output")
        let requests = try capture.requests()
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests.first?.events.map(\.kind), ["request", "dump", "response"])
        XCTAssertEqual(requests.first?.events[1].file, script.path)
        try JSONEncoder().encode([DiagnosticProject(path: project.path, enabled: false)]).write(to: settings)
        _ = try CommandRunner().run(php, ["-d", "auto_prepend_file=" + capture.directory(project.path).appendingPathComponent("prepend.php").path, script.path]).checked()
        XCTAssertEqual(try capture.requests().count, 1)
    }
}

private struct CaptureRunner: CommandRunning {
    let existingPrepend: String
    func run(_ executable: String, _ arguments: [String], environment: [String: String]) throws -> CommandResult {
        if arguments == ["-n", "--version"] { return CommandResult(status: 0, output: "PHP 8.4.0") }
        if arguments.first == "-r" { return CommandResult(status: 0, output: existingPrepend) }
        if executable == "/fixture/caddy" { return CommandResult(status: 1, output: "Invalid configuration") }
        XCTFail("Capture must not restart services: \(executable) \(arguments)")
        return CommandResult(status: 1, output: "Unexpected command")
    }
}
