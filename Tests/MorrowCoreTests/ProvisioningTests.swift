import XCTest
import MorrowCore
import Darwin

private final class ProvisionRunner: CommandRunning, @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [[String]] = []
    var calls: [[String]] { lock.lock(); defer { lock.unlock() }; return recorded }
    func run(_ executable: String, _ arguments: [String], environment: [String: String]) throws -> CommandResult {
        lock.lock(); recorded.append([executable] + arguments); lock.unlock()
        if executable == "/bin/launchctl" { return CommandResult(status: 1, output: "") }
        if executable.hasSuffix("/mongod") { return CommandResult(status: 0, output: "db version v8.0.13\n") }
        if executable.hasSuffix("/postgres") { return CommandResult(status: 0, output: "postgres (PostgreSQL) 17.11\n") }
        return CommandResult(status: 1, output: "Unexpected installer invocation")
    }
}

private struct MariaAliasRunner: CommandRunning {
    func run(_ executable: String, _ arguments: [String], environment: [String: String]) throws -> CommandResult {
        CommandResult(status: 0, output: "mariadbd Ver 11.8.9-MariaDB")
    }
}

final class ProvisioningTests: XCTestCase {
    private var root: URL!
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("MorrowProvision-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }
    private func server(_ engine: DatabaseEngine) throws -> Installation {
        let prefix = root.appendingPathComponent(engine.rawValue)
        let bin = prefix.appendingPathComponent("bin")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        let file = bin.appendingPathComponent(engine.binary)
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: file)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file.path)
        return Installation(engine: engine, formula: "external", version: engine == .mongodb ? "8.0.13" : "17.11", prefix: prefix.path)
    }
    func testExistingServerIsReusedWithoutInstallerCommands() throws {
        let runner = ProvisionRunner()
        let manager = DatabaseManager(store: StateStore(root: root), runner: runner)
        let installed = try server(.mongodb)
        let port = try manager.suggestedPort(engine: .mongodb)
        let result = try manager.provision(engine: .mongodb, name: "existing", port: port, installation: installed)
        XCTAssertEqual(result.installation.prefix, installed.prefix)
        XCTAssertFalse(runner.calls.contains { $0.contains("install") || $0.contains("tap") })
        XCTAssertEqual(try manager.store.load().instances.count, 1)
        try manager.remove(result.id, deleteData: true)
    }
    func testInvalidPortFailsBeforeAnyServerOrInstallerCommand() throws {
        let runner = ProvisionRunner()
        let manager = DatabaseManager(store: StateStore(root: root), runner: runner)
        XCTAssertThrowsError(try manager.provision(engine: .mysql, name: "invalid", port: 65536))
        XCTAssertTrue(runner.calls.isEmpty)
        XCTAssertTrue(try manager.store.load().instances.isEmpty)
    }
    func testOccupiedPortFailsBeforeAnyInstall() throws {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        XCTAssertGreaterThanOrEqual(fd, 0)
        defer { Darwin.close(fd) }
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        let bound = withUnsafePointer(to: &address) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) } }
        XCTAssertEqual(bound, 0)
        XCTAssertEqual(listen(fd, 1), 0)
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let named = withUnsafeMutablePointer(to: &address) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(fd, $0, &length) } }
        XCTAssertEqual(named, 0)
        let port = Int(UInt16(bigEndian: address.sin_port))
        let runner = ProvisionRunner()
        let manager = DatabaseManager(store: StateStore(root: root), runner: runner)
        XCTAssertThrowsError(try manager.provision(engine: .mysql, name: "occupied", port: port))
        XCTAssertTrue(runner.calls.isEmpty)
    }
    func testExistingNamedInstanceAndPortAreReservedEvenWhenStopped() throws {
        let runner = ProvisionRunner()
        let manager = DatabaseManager(store: StateStore(root: root), runner: runner)
        let installed = try server(.mongodb)
        let port = try manager.suggestedPort(engine: .mongodb)
        let original = try manager.provision(engine: .mongodb, name: "reserved", port: port, installation: installed)
        XCTAssertThrowsError(try manager.preflight(name: "RESERVED", engine: .mysql, port: port + 1))
        XCTAssertThrowsError(try manager.validatePort(port))
        try manager.remove(original.id, deleteData: true)
    }
    func testPATHServerIsDetectedAndMissingHelpersAreReported() throws {
        let runner = ProvisionRunner()
        let installed = try server(.postgresql)
        let detector = NativeInstallationDetector(runner: runner)
        let found = detector.discover(existing: [], directories: [installed.prefix + "/bin"])
        XCTAssertEqual(found.first?.version, "17.11")
        XCTAssertThrowsError(try detector.validate(found[0]))
    }
    func testVersionMatchingDoesNotConfuseEnginesOrReleaseSeries() {
        let mysql = Installation(engine: .mysql, formula: "mysql@8.4", version: "8.4.11_1", prefix: "/unused")
        XCTAssertTrue(HomebrewInstaller.matches(mysql, request: "8.4"))
        XCTAssertFalse(HomebrewInstaller.matches(mysql, request: "9.7"))
        XCTAssertFalse(HomebrewInstaller.matches(mysql, request: "mysql@9.7"))
        XCTAssertNil(NativeInstallationDetector.version(from: "mysqld Ver 11.8.6-MariaDB", engine: .mysql))
        XCTAssertEqual(NativeInstallationDetector.version(from: "mysqld Ver 11.8.6-MariaDB", engine: .mariadb), "11.8.6")
    }
    func testMySQLAliasDoesNotHideAMariaDBInstallation() throws {
        let installed = try server(.mariadb)
        try FileManager.default.createSymbolicLink(atPath: installed.prefix + "/bin/mysqld", withDestinationPath: "mariadbd")
        let found = NativeInstallationDetector(runner: MariaAliasRunner()).discover(existing: [], directories: [installed.prefix + "/bin"])
        XCTAssertEqual(found.map(\.engine), [.mariadb])
    }
}
