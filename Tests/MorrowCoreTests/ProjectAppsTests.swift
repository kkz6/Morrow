import Foundation
import XCTest
@testable import MorrowCore

final class ProjectAppsTests: XCTestCase {
    func testRustProjectRequirementUsesLegacyPinAndCargoMinimum() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try "[package]\nrust-version = '1.96' # Minimum supported toolchain\n".write(
            to: root.appendingPathComponent("Cargo.toml"), atomically: true, encoding: .utf8)
        try "[toolchain]\nchannel = \"stable\"\n".write(
            to: root.appendingPathComponent("rust-toolchain.toml"), atomically: true, encoding: .utf8)
        try "1.97.1\n".write(to: root.appendingPathComponent("rust-toolchain"), atomically: true, encoding: .utf8)
        let pinned = try XCTUnwrap(RustProjectRequirement.read(at: root.path))
        XCTAssertEqual(pinned.source, "rust-toolchain")
        XCTAssertEqual(pinned.minimum, "1.96")
        XCTAssertTrue(pinned.matches("1.97.1"))
        XCTAssertFalse(pinned.matches("1.97.2"))
        try FileManager.default.removeItem(at: root.appendingPathComponent("rust-toolchain"))
        let stable = try XCTUnwrap(RustProjectRequirement.read(at: root.path))
        XCTAssertTrue(stable.matches("1.99.1"))
        XCTAssertFalse(stable.matches("1.95.0"))
        try "[toolchain]\nchannel = \"nightly-2026-10-15\"\ntargets = [\"wasm32-unknown-unknown\"]\n".write(
            to: root.appendingPathComponent("rust-toolchain.toml"), atomically: true, encoding: .utf8)
        let nightly = try XCTUnwrap(RustProjectRequirement.read(at: root.path))
        XCTAssertEqual(nightly.channel, "nightly-2026-10-15")
        XCTAssertFalse(nightly.canRecommend)
        XCTAssertFalse(nightly.matches("1.99.1"))
    }

    func testManagedAppPreservesArgumentsAndCannotMoveLivePort() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).resolvingSymlinksInPath()
        let folder = root.appendingPathComponent("demo")
        let prefix = root.appendingPathComponent("rust")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: prefix.appendingPathComponent("bin"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try "[package]\nname = \"demo\"\n".write(to: folder.appendingPathComponent("Cargo.toml"), atomically: true, encoding: .utf8)
        for name in ["rustc", "cargo"] {
            let file = prefix.appendingPathComponent("bin/" + name)
            try Data().write(to: file)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: file.path)
        }
        let rust = RuntimeInstallation(engine: .rust, formula: "rust", version: "1.99.1", prefix: prefix.path,
                                       executable: prefix.appendingPathComponent("bin/rustc").path, source: "external")
        let store = StateStore(root: root.appendingPathComponent("state"))
        try store.update { $0.tools = [rust] }
        let runner = ProjectAppFixtureRunner(compiler: rust.executable)
        let sites = SiteManager(store: store, runner: runner)
        let apps = ProjectApps(store: store, runner: runner)
        let site = try sites.link(path: folder.path)
        let toolchain = folder.appendingPathComponent("rust-toolchain.toml")
        try "[toolchain]\nchannel = \"1.98.0\"\n".write(to: toolchain, atomically: true, encoding: .utf8)
        let manager = RuntimeManager(store: store, runner: runner)
        let cli = URL(fileURLWithPath: "/usr/bin/true")
        XCTAssertThrowsError(try manager.useDetectedRust(rust.version, installed: rust, directory: folder.path, cli: cli))
        XCTAssertNil(try ProjectRuntimeStore(store: store).selection(.rust, directory: folder.path))
        try "[toolchain]\nchannel = \"1.99.1\"\n".write(to: toolchain, atomically: true, encoding: .utf8)
        XCTAssertEqual(try manager.useDetectedRust(rust.version, installed: rust, directory: folder.path, cli: cli), rust)
        XCTAssertNil(try store.load().toolDefaults["rust"])
        let command = ProjectAppCommand(runtime: .rust, executable: "cargo", arguments: ["run", "--", "two words"])
        XCTAssertThrowsError(try apps.configure(site.id, command: command, port: 80))
        XCTAssertNil(try apps.command(site.id))
        XCTAssertNil(try sites.resolve(site.domain).proxyPort)
        let port = try XCTUnwrap((49_152...65_535).first(where: DatabaseManager.portAvailable))
        try apps.configure(site.id, command: command, port: port)
        XCTAssertFalse(runner.loaded)
        try apps.start(site.id)
        let job = try XCTUnwrap(runner.job)
        XCTAssertEqual(job["ProgramArguments"] as? [String], [prefix.appendingPathComponent("bin/cargo").path, "run", "--", "two words"])
        XCTAssertEqual(job["WorkingDirectory"] as? String, folder.path)
        XCTAssertEqual((job["EnvironmentVariables"] as? [String: String])?["PORT"], String(port))
        XCTAssertEqual(apps.state(try sites.resolve(site.domain))?.status, .starting)
        XCTAssertThrowsError(try apps.configure(site.id, command: command, port: port - 1))
        try sites.unlink(site.id)
        XCTAssertFalse(runner.loaded)
        XCTAssertThrowsError(try sites.resolve(site.domain))
    }
}

private final class ProjectAppFixtureRunner: CommandRunning, @unchecked Sendable {
    let compiler: String
    var job: [String: Any]?
    var loaded = false
    init(compiler: String) { self.compiler = compiler }

    func run(_ executable: String, _ arguments: [String], environment: [String: String]) throws -> CommandResult {
        if executable == compiler {
            return CommandResult(status: 0, output: "host: aarch64-apple-darwin\nrelease: 1.99.1\n")
        }
        guard executable == "/bin/launchctl" else { return CommandResult(status: 1, output: "") }
        switch arguments.first {
        case "bootstrap":
            let data = try Data(contentsOf: URL(fileURLWithPath: arguments[2]))
            job = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
            loaded = true
        case "bootout": loaded = false
        case "print": return CommandResult(status: loaded ? 0 : 1, output: loaded ? "state = running" : "")
        default: return CommandResult(status: 1, output: "")
        }
        return CommandResult(status: 0, output: "")
    }
}
