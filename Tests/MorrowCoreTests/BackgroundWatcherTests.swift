import XCTest
@testable import MorrowCore

final class BackgroundWatcherTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("Morrow watcher \(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }

    func testStaleWatcherMigrationPreservesHostingStateAndOnlyRestartsMonitor() throws {
        let store = StateStore(root: root)
        try store.update {
            $0.web.enabled = true
            $0.web.autoStart = true
            $0.web.cliPath = "/old-development/Morrow.app/Contents/MacOS/morrow"
            $0.web.sites = [LocalSite(domain: "example.test", path: "/projects/example", documentRoot: "/projects/example/public", mode: .php, https: true)]
        }
        let previous = try store.load()
        let runner = WatcherRunner()
        let manager = SiteManager(store: store, runner: runner)
        let cli = URL(fileURLWithPath: "/usr/bin/true")

        try manager.updateDirectoryWatcher(cli: cli, onlyIfChanged: true)

        var expected = previous
        expected.web.cliPath = cli.resolvingSymlinksInPath().path
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        XCTAssertEqual(try encoder.encode(store.load()), try encoder.encode(expected))
        let commands = runner.calls
        XCTAssertTrue(commands.contains { $0.contains("bootout") })
        XCTAssertTrue(commands.contains { $0.contains("bootstrap") })
        XCTAssertTrue(commands.allSatisfy { $0.first == "/bin/launchctl" && $0.last?.contains(".watch") == true })
        for file in [manager.job("watch", web: expected.web), store.loginAgentURL(label: manager.label("watch", web: expected.web))] {
            let job = try XCTUnwrap(PropertyListSerialization.propertyList(from: Data(contentsOf: file), format: nil) as? [String: Any])
            XCTAssertEqual(job["ProgramArguments"] as? [String], [expected.web.cliPath!, "site", "watch"])
            XCTAssertEqual(job["AssociatedBundleIdentifiers"] as? [String], ["dev.morrow.app"])
        }

        try manager.updateDirectoryWatcher(cli: cli, onlyIfChanged: true)
        XCTAssertEqual(runner.calls, commands, "Repeated cleanup must not restart the current monitor")
    }

    func testMissingLauncherDoesNotStopWatcherOrChangeSavedPath() throws {
        let store = StateStore(root: root)
        try store.update { $0.web.enabled = true; $0.web.cliPath = "/existing/morrow" }
        let runner = WatcherRunner()
        XCTAssertThrowsError(try SiteManager(store: store, runner: runner).updateDirectoryWatcher(cli: root.appendingPathComponent("missing"), onlyIfChanged: true))
        XCTAssertEqual(try store.load().web.cliPath, "/existing/morrow")
        XCTAssertTrue(runner.calls.isEmpty)
    }

    func testCleanupDoesNotEnableStoppedHosting() throws {
        let store = StateStore(root: root)
        try store.update { $0.web.enabled = false; $0.web.cliPath = "/previous/morrow" }
        let runner = WatcherRunner()
        try SiteManager(store: store, runner: runner).updateDirectoryWatcher(cli: URL(fileURLWithPath: "/usr/bin/true"), onlyIfChanged: true)
        XCTAssertFalse(try store.load().web.enabled)
        XCTAssertEqual(try store.load().web.cliPath, "/previous/morrow")
        XCTAssertTrue(runner.calls.isEmpty)
    }
}

private final class WatcherRunner: CommandRunning, @unchecked Sendable {
    private let lock = NSLock()
    private var commands: [[String]] = []
    private var loaded = true
    var calls: [[String]] { lock.withLock { commands } }

    func run(_ executable: String, _ arguments: [String], environment: [String: String]) throws -> CommandResult {
        lock.withLock {
            commands.append([executable] + arguments)
            if arguments.first == "print" { return CommandResult(status: loaded ? 0 : 1, output: "state = waiting") }
            if arguments.first == "bootout" { loaded = false }
            if arguments.first == "bootstrap" { loaded = true }
            return CommandResult(status: 0, output: "")
        }
    }
}
