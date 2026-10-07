import XCTest
import MorrowCore
@testable import MorrowApp

final class LogViewerTests: XCTestCase {
    @MainActor func testSearchMatchesLinesWithoutChangingTheLogBuffer() {
        let viewer = LogViewerModel()
        viewer.output = "LOG: ready\nERROR: refused\nLOG: connected\n"
        viewer.query = "error"
        XCTAssertEqual(viewer.visibleOutput, "ERROR: refused")
        viewer.query = "absent"
        XCTAssertTrue(viewer.visibleOutput.isEmpty)
        viewer.query = ""
        XCTAssertEqual(viewer.visibleOutput, viewer.output)
    }
    @MainActor func testChangingInstancesResetsDisplayedOutput() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("MorrowLogViewer-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let first = root.appendingPathComponent("first.log"), second = root.appendingPathComponent("second.log")
        try Data("first server\n".utf8).write(to: first)
        try Data("second server\n".utf8).write(to: second)
        let viewer = LogViewerModel()
        viewer.configure(url: first)
        await viewer.refresh()
        XCTAssertEqual(viewer.output, "first server\n")
        viewer.configure(url: second)
        XCTAssertTrue(viewer.output.isEmpty)
        await viewer.refresh()
        XCTAssertEqual(viewer.output, "second server\n")
        XCTAssertNil(viewer.error)
    }
    @MainActor func testLogsActionOpensTheSelectedInstanceInsideSettings() {
        let model = AppModel(preview: true)
        let instance = model.instances[1]
        model.creationRequest = InstanceCreationRequest(installation: model.installations[0])
        model.showLogs(for: instance)
        XCTAssertEqual(model.selection, .logs)
        XCTAssertEqual(model.logInstanceID, instance.id)
        XCTAssertNil(model.creationRequest)
    }
}
