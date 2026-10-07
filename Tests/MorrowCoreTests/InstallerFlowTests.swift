import XCTest
import MorrowCore

private final class InstallerFixture: CommandRunning, @unchecked Sendable {
    let prefix: URL
    private(set) var installCount = 0
    init(prefix: URL) { self.prefix = prefix }
    func run(_ executable: String, _ arguments: [String], environment: [String: String]) throws -> CommandResult {
        if executable == prefix.appendingPathComponent("bin/brew").path {
            if arguments.first == "tap" { return CommandResult(status: 0, output: "") }
            if arguments.first == "info" {
                return CommandResult(status: 0, output: "{\"formulae\":[{\"name\":\"mongodb-community@8.0\",\"disabled\":false,\"versions\":{\"stable\":\"8.0.13\"}}]}")
            }
            if arguments.first == "install" {
                installCount += 1
                let bin = prefix.appendingPathComponent("Cellar/mongodb-community@8.0/8.0.13/bin")
                try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
                let server = bin.appendingPathComponent("mongod")
                try Data("#!/bin/sh\nexit 0\n".utf8).write(to: server)
                try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: server.path)
                return CommandResult(status: 0, output: "Installed fixture")
            }
        }
        let resolved = URL(fileURLWithPath: executable).resolvingSymlinksInPath().path
        if resolved.hasPrefix(prefix.resolvingSymlinksInPath().path) && executable.hasSuffix("/mongod") { return CommandResult(status: 0, output: "db version v8.0.13\n") }
        return CommandResult(status: 1, output: "Unhandled fixture command: \(executable) \(arguments)")
    }
}

final class InstallerFlowTests: XCTestCase {
    func testMissingReleaseIsInstalledOnceAndReusedForTheNextInstance() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("MorrowInstallFlow-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let prefix = root.appendingPathComponent("brew")
        try FileManager.default.createDirectory(at: prefix.appendingPathComponent("bin"), withIntermediateDirectories: true)
        let brew = prefix.appendingPathComponent("bin/brew")
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: brew)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: brew.path)
        let runner = InstallerFixture(prefix: prefix)
        let store = StateStore(root: root.appendingPathComponent("state"))
        try store.update { $0.preferences.homebrewPath = brew.path }
        let manager = DatabaseManager(store: store, runner: runner)
        let first = try manager.provision(engine: .mongodb, version: "8.0", name: "first", port: manager.suggestedPort(engine: .mongodb))
        XCTAssertEqual(runner.installCount, 1)
        XCTAssertEqual(first.installation.version, "8.0.13")
        let second = try manager.provision(engine: .mongodb, version: "8.0", name: "second", port: manager.suggestedPort(engine: .mongodb))
        XCTAssertEqual(runner.installCount, 1)
        XCTAssertEqual(first.installation, second.installation)
        XCTAssertNotEqual(first.port, second.port)
        try manager.remove(first.id, deleteData: true)
        try manager.remove(second.id, deleteData: true)
    }
}
