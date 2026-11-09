import XCTest
@testable import MorrowCore

final class ProjectWorkersTests: XCTestCase {
    private var root: URL!
    private var store: StateStore!
    private let launcher = URL(fileURLWithPath: "/Applications/Morrow.app/Contents/MacOS/morrow")
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("Morrow workers \(UUID())").resolvingSymlinksInPath()
        store = StateStore(root: root)
        try FileManager.default.createDirectory(at: store.loginAgentURL(label: "unused").deletingLastPathComponent(), withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }
    private func job(_ label: String = "example.project.queue", extra: [String: Any] = [:]) throws -> URL {
        var values: [String: Any] = ["Label": label, "ProgramArguments": ["/bin/sleep", "60"], "WorkingDirectory": root.path,
                                     "KeepAlive": true, "RunAtLoad": true, "EnvironmentVariables": ["PROJECT_MODE": "test"],
                                     "StandardOutPath": root.appendingPathComponent("worker.log").path,
                                     "StandardErrorPath": root.appendingPathComponent("worker.log").path]
        values.merge(extra) { _, new in new }
        let file = store.loginAgentURL(label: label)
        try PropertyListSerialization.data(fromPropertyList: values, format: .xml, options: 0).write(to: file)
        try FileManager.default.setAttributes([.posixPermissions: 0o640], ofItemAtPath: file.path)
        return file
    }
    private func plist(_ file: URL) throws -> NSDictionary {
        try XCTUnwrap(PropertyListSerialization.propertyList(from: Data(contentsOf: file), format: nil) as? NSDictionary)
    }
    func testImportPreservesConfigurationAndRunningProcessAndRestoresOriginalBytes() throws {
        let file = try job(extra: ["Program": "/bin/sleep"]), original = try Data(contentsOf: file)
        let expected = try XCTUnwrap(plist(file).mutableCopy() as? NSMutableDictionary)
        expected.removeObject(forKey: "Program")
        expected["ProgramArguments"] = [launcher.path, "service-runner", "--", "/bin/sleep", "60"]
        expected["AssociatedBundleIdentifiers"] = ["dev.morrow.app"]
        let process = Process(); process.executableURL = URL(fileURLWithPath: "/bin/sleep"); process.arguments = ["60"]
        try process.run(); defer { process.terminate(); process.waitUntilExit() }
        let pid = process.processIdentifier
        let workers = ProjectWorkers(store: store)
        _ = try workers.adoptVerified(file, launcher: launcher)
        XCTAssertEqual(try plist(file), expected)
        XCTAssertTrue(process.isRunning); XCTAssertEqual(process.processIdentifier, pid)
        XCTAssertEqual(try workers.workers().map(\.label), ["example.project.queue"])
        XCTAssertEqual(try workers.managedFiles(), [file])
        XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: root.appendingPathComponent("project-workers.json").path)[.posixPermissions] as? Int, 0o600)
        try workers.restore("example.project.queue")
        XCTAssertEqual(try Data(contentsOf: file), original)
        XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? Int, 0o640)
        XCTAssertTrue(try workers.workers().isEmpty)
        XCTAssertTrue(process.isRunning)
    }
    func testRepeatedImportDoesNotNestWrappersAndCanUpdateLauncher() throws {
        let file = try job(), workers = ProjectWorkers(store: store)
        _ = try workers.adoptVerified(file, launcher: launcher)
        let first = try Data(contentsOf: file)
        _ = try workers.adoptVerified(file, launcher: launcher)
        XCTAssertEqual(try Data(contentsOf: file), first)
        let next = URL(fileURLWithPath: "/updated/Morrow.app/Contents/MacOS/morrow")
        _ = try workers.adoptVerified(file, launcher: next)
        XCTAssertEqual(try plist(file)["ProgramArguments"] as? [String], [next.path, "service-runner", "--", "/bin/sleep", "60"])
        XCTAssertEqual(try workers.workers().count, 1)
    }
    func testExternalChangesArePreservedAndNotReportedAsOwned() throws {
        let file = try job(), workers = ProjectWorkers(store: store)
        _ = try workers.adoptVerified(file, launcher: launcher)
        let altered = try XCTUnwrap(plist(file).mutableCopy() as? NSMutableDictionary)
        altered["RunAtLoad"] = false
        let data = try PropertyListSerialization.data(fromPropertyList: altered, format: .xml, options: 0)
        try data.write(to: file)
        XCTAssertThrowsError(try workers.adoptVerified(file, launcher: launcher))
        XCTAssertThrowsError(try workers.restore("example.project.queue"))
        XCTAssertEqual(try Data(contentsOf: file), data)
        XCTAssertTrue(try workers.managedFiles().isEmpty)
    }
    func testInterruptedImportCanBeRetriedOrRestored() throws {
        let file = try job(), original = try Data(contentsOf: file), workers = ProjectWorkers(store: store)
        _ = try workers.adoptVerified(file, launcher: launcher)
        try original.write(to: file) // Registry was persisted but plist write did not complete.
        XCTAssertTrue(try workers.managedFiles().isEmpty)
        _ = try workers.adoptVerified(file, launcher: launcher)
        XCTAssertEqual(try workers.managedFiles(), [file])
        try original.write(to: file)
        try workers.restore("example.project.queue")
        XCTAssertTrue(try workers.workers().isEmpty)
        XCTAssertEqual(try Data(contentsOf: file), original)
    }
    func testUnsignedLauncherAndUnsupportedRegistrationsLeaveFilesIntact() throws {
        let workers = ProjectWorkers(store: store), file = try job(), original = try Data(contentsOf: file)
        XCTAssertThrowsError(try workers.adopt(file, launcher: URL(fileURLWithPath: "/bin/echo")))
        XCTAssertEqual(try Data(contentsOf: file), original)
        for extra: [String: Any] in [["Program": "/bin/echo"], ["AssociatedBundleIdentifiers": ["other.app"]], ["UserName": "root"], ["WorkingDirectory": "/missing/project"], ["ProgramArguments": ["/missing/php"]]] {
            let unsupported = try job(extra: extra), before = try Data(contentsOf: unsupported)
            XCTAssertThrowsError(try workers.adoptVerified(unsupported, launcher: launcher))
            XCTAssertEqual(try Data(contentsOf: unsupported), before)
        }
        XCTAssertTrue(try workers.workers().isEmpty)
    }
    func testOutsideFilesAndSymlinksCannotBeImported() throws {
        let workers = ProjectWorkers(store: store), file = try job()
        let outside = root.appendingPathComponent(file.lastPathComponent)
        try FileManager.default.copyItem(at: file, to: outside)
        XCTAssertThrowsError(try workers.adoptVerified(outside, launcher: launcher))
        try FileManager.default.removeItem(at: file)
        try FileManager.default.createSymbolicLink(at: file, withDestinationURL: outside)
        XCTAssertThrowsError(try workers.adoptVerified(file, launcher: launcher))
        XCTAssertTrue(try workers.workers().isEmpty)
    }
    func testCleanupRetainsImportedStoppedWorkersAndIncludesTheirPermissions() throws {
        let file = try job(), workers = ProjectWorkers(store: store)
        _ = try workers.adoptVerified(file, launcher: launcher)
        let data = try Data(contentsOf: file)
        let cli = root.appendingPathComponent("morrow")
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: cli)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: cli.path)
        let registrations = BackgroundRegistrations(store: store, runner: NoWorkerCommands())
        XCTAssertTrue(registrations.permissionFiles().contains(file))
        _ = try registrations.clean(cli: cli)
        XCTAssertEqual(try Data(contentsOf: file), data)
        XCTAssertEqual(try workers.workers().count, 1)
    }
}

private struct NoWorkerCommands: CommandRunning {
    func run(_ executable: String, _ arguments: [String], environment: [String: String]) throws -> CommandResult {
        XCTFail("Import cleanup must not execute service commands: \(executable)")
        return CommandResult(status: 1, output: "")
    }
}
