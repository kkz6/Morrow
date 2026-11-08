import XCTest
import MorrowCore
import CryptoKit

private final class InstallerFixture: CommandRunning, @unchecked Sendable {
    let prefix: URL
    private(set) var installCount = 0
    init(prefix: URL) { self.prefix = prefix }
    let server = Data("#!/bin/sh\nexit 0\n".utf8)
    func run(_ executable: String, _ arguments: [String], environment: [String: String]) throws -> CommandResult {
        if executable == "/usr/bin/curl", arguments.last == "https://fixtures.invalid/catalog.json" {
            let release: [String: Any] = [
                "package": "mongodb", "version": "8.0.13", "architecture": ManagedBinaryStore.architecture,
                "minimumMacOS": "14.0", "url": "https://fixtures.invalid/mongod",
                "sha256": SHA256.hash(data: server).map { String(format: "%02x", $0) }.joined(),
                "archive": "binary", "rootDirectory": "", "executables": ["bin/mongod"]
            ]
            let data = try JSONSerialization.data(withJSONObject: ["schemaVersion": 1, "releases": [release]])
            return CommandResult(status: 0, output: String(decoding: data, as: UTF8.self))
        }
        if executable == "/usr/bin/curl", arguments.last == "https://fixtures.invalid/mongod",
           let output = arguments.firstIndex(of: "--output"), output + 1 < arguments.count {
            installCount += 1
            try server.write(to: URL(fileURLWithPath: arguments[output + 1]))
            return CommandResult(status: 0, output: "")
        }
        // No fixture command can fall through to Homebrew or the network.
        XCTAssertFalse(executable.hasSuffix("/brew"))
        let resolved = URL(fileURLWithPath: executable).resolvingSymlinksInPath().path
        if resolved.hasPrefix(prefix.resolvingSymlinksInPath().path) && executable.hasSuffix("/mongod") {
            return CommandResult(status: 0, output: "db version v8.0.13\n")
        }
        return CommandResult(status: 1, output: "Unhandled fixture command: \(executable) \(arguments)")
    }
}

final class InstallerFlowTests: XCTestCase {
    func testMissingReleaseIsInstalledOnceAndReusedForTheNextInstance() throws {
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("MorrowInstallFlow-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let runner = InstallerFixture(prefix: root)
        let store = StateStore(root: root.appendingPathComponent("state"))
        try store.update {
            $0.preferences.homebrewPath = root.appendingPathComponent("unused-brew").path
            $0.preferences.binaryCatalogURL = "https://fixtures.invalid/catalog.json"
        }
        let manager = DatabaseManager(store: store, runner: runner)
        let first = try manager.provision(engine: .mongodb, version: "8.0", name: "first", port: manager.suggestedPort(engine: .mongodb))
        XCTAssertEqual(runner.installCount, 1)
        XCTAssertEqual(first.installation.version, "8.0.13")
        let second = try manager.provision(engine: .mongodb, version: "8.0", name: "second", port: manager.suggestedPort(engine: .mongodb))
        XCTAssertEqual(runner.installCount, 1)
        XCTAssertEqual(first.installation.engine, second.installation.engine)
        XCTAssertEqual(first.installation.formula, second.installation.formula)
        XCTAssertEqual(first.installation.version, second.installation.version)
        XCTAssertEqual(URL(fileURLWithPath: first.installation.prefix).resolvingSymlinksInPath(),
                       URL(fileURLWithPath: second.installation.prefix).resolvingSymlinksInPath())
        XCTAssertNotEqual(first.port, second.port)
        try manager.remove(first.id, deleteData: true)
        try manager.remove(second.id, deleteData: true)
    }
}
