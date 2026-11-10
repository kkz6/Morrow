import AppKit
import SwiftUI
import XCTest
@testable import MorrowApp

final class MailWindowTests: XCTestCase {
    @MainActor func testMailHasItsOwnResizableWindowAndReusesIt() throws {
        let controller = MailWindowController(id: UUID(), title: "Test Mail")
        let window = controller.prepareWindow(Color.clear.frame(maxWidth: .infinity, maxHeight: .infinity))
        defer { controller.close() }
        XCTAssertTrue(window.styleMask.contains(.resizable))
        XCTAssertTrue(window.styleMask.contains(.miniaturizable))
        XCTAssertEqual(window.contentMinSize, MailWindowController.minimumSize)
        XCTAssertTrue(window.standardWindowButton(.zoomButton)?.isEnabled == true)
        XCTAssertTrue(controller.prepareWindow(Color.red) === window)
        let larger = CGSize(width: 1200, height: 820)
        window.setContentSize(larger)
        XCTAssertEqual(try XCTUnwrap(window.contentView).frame.size, larger)
        XCTAssertGreaterThan(window.contentView!.frame.width, 680)
        XCTAssertGreaterThan(window.contentView!.frame.height, 560)
    }

    @MainActor func testClosingMailReleasesTheReaderAndItsPollingTasks() {
        var closed = false
        let controller = MailWindowController(id: UUID(), title: "Test Mail") { closed = true }
        let window = controller.prepareWindow(Color.clear)
        controller.close()
        XCTAssertTrue(closed)
        XCTAssertNil(window.contentViewController)
    }
}
