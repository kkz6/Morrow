import XCTest
import MorrowCore

final class CLIInstallerTests: XCTestCase {
    func testInstallerIsIdempotentAndPreservesAnotherCommand() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("MorrowCLIInstall-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let source = root.appendingPathComponent("bundled-morrow")
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: source)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: source.path)
        let destination = root.appendingPathComponent("bin/morrow")
        try CLIInstaller.install(source: source, destination: destination)
        try CLIInstaller.install(source: source, destination: destination)
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: destination.path), source.path)
        try FileManager.default.removeItem(at: destination)
        let other = Data("another command".utf8)
        try other.write(to: destination)
        XCTAssertThrowsError(try CLIInstaller.install(source: source, destination: destination))
        XCTAssertEqual(try Data(contentsOf: destination), other)
    }
}
