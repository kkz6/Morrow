import AppKit
import SwiftUI
import XCTest
@testable import MorrowApp

final class SettingsWindowTests: XCTestCase {
    @MainActor func testNativeControlsStayInTheTitlebarWithoutResizingTheWindow() throws {
        let controller = SettingsWindowController(configuration: SettingsWindowConfiguration(
            identifier: NSUserInterfaceItemIdentifier("morrow.settings.test"), title: "Settings",
            size: SettingsLayout.windowSize, trafficLightLeading: SettingsLayout.trafficLightLeading,
            trafficLightCenterFromTop: SettingsLayout.titlebarControlCenterFromTop))
        let window = controller.prepareWindow(Color.clear.frame(width: 720, height: 620))
        defer { controller.close() }
        let content = try XCTUnwrap(window.contentView)
        XCTAssertEqual(window.frame.size, SettingsLayout.windowSize)
        XCTAssertEqual(content.frame.size, SettingsLayout.windowSize)
        XCTAssertEqual(window.minSize, SettingsLayout.windowSize)
        XCTAssertEqual(window.maxSize, SettingsLayout.windowSize)
        XCTAssertFalse(window.styleMask.contains(.resizable))
        let types: [NSWindow.ButtonType] = [.closeButton, .miniaturizeButton, .zoomButton]
        for (index, type) in types.enumerated() {
            let button = try XCTUnwrap(window.standardWindowButton(type))
            let parent = try XCTUnwrap(button.superview)
            XCTAssertFalse(button.isHidden)
            XCTAssertEqual(button.isEnabled, type == .closeButton)
            XCTAssertTrue(parent !== content)
            XCTAssertTrue(parent.bounds.contains(button.frame))
            let frame = content.convert(button.frame, from: parent)
            XCTAssertEqual(frame.minX, SettingsLayout.trafficLightLeading + CGFloat(index) * 23)
            XCTAssertEqual(content.bounds.height - frame.midY, SettingsLayout.titlebarControlCenterFromTop)
        }
        XCTAssertTrue(controller.prepareWindow(Color.red) === window)
    }
}
