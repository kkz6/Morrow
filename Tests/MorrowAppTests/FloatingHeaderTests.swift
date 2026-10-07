import XCTest
import AppKit
@testable import MorrowApp

final class FloatingHeaderTests: XCTestCase {
    @MainActor func testNativeScrollStateTracksMovementAndReturnToTop() async throws {
        final class FlippedDocument: NSView { override var isFlipped: Bool { true } }
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 200, height: 100))
        let document = FlippedDocument(frame: NSRect(x: 0, y: 0, width: 200, height: 400))
        scroll.documentView = document
        let tracker = ScrollTrackingView(frame: .zero)
        document.addSubview(tracker)
        var observed: [Bool] = []
        tracker.changed = { observed.append($0) }
        tracker.attach()
        scroll.contentView.scroll(to: NSPoint(x: 0, y: 40))
        scroll.reflectScrolledClipView(scroll.contentView)
        try await Task.sleep(for: .milliseconds(30))
        XCTAssertEqual(observed.last, true)
        scroll.contentView.scroll(to: .zero)
        scroll.reflectScrolledClipView(scroll.contentView)
        try await Task.sleep(for: .milliseconds(30))
        XCTAssertEqual(observed.last, false)
    }
    func testMaskKeepsFullStrengthThroughTitleMidpointThenFades() {
        XCTAssertEqual(FloatingHeaderMetrics.fullStrengthEnd, 26)
        XCTAssertEqual(FloatingHeaderMetrics.height, 53)
        for y in stride(from: CGFloat(0), through: FloatingHeaderMetrics.fullStrengthEnd, by: 1) {
            XCTAssertEqual(FloatingHeaderMetrics.maskAlpha(at: y), 1)
        }
        var previous: CGFloat = 1
        for y in stride(from: FloatingHeaderMetrics.fullStrengthEnd, through: FloatingHeaderMetrics.height, by: 1) {
            let alpha = FloatingHeaderMetrics.maskAlpha(at: y)
            XCTAssertLessThanOrEqual(alpha, previous)
            XCTAssertGreaterThanOrEqual(alpha, 0)
            previous = alpha
        }
        XCTAssertEqual(FloatingHeaderMetrics.maskAlpha(at: FloatingHeaderMetrics.height), 0)
        XCTAssertEqual(FloatingHeaderMetrics.maskAlpha(at: FloatingHeaderMetrics.height + 20), 0)
    }
    @MainActor func testNativeMaskHasTransparentBottomAndOpaqueTop() throws {
        let image = HeaderEffectView.makeMask()
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: try XCTUnwrap(image.tiffRepresentation)))
        XCTAssertEqual(try XCTUnwrap(bitmap.colorAt(x: 0, y: 0)).alphaComponent, 1, accuracy: 0.01)
        XCTAssertEqual(try XCTUnwrap(bitmap.colorAt(x: 0, y: bitmap.pixelsHigh - 1)).alphaComponent, 0, accuracy: 0.01)
        XCTAssertGreaterThan(try XCTUnwrap(bitmap.colorAt(x: 0, y: bitmap.pixelsHigh / 2)).alphaComponent, 0.95)
    }
    @MainActor func testReduceMotionSetsVisibilityWithoutAnimation() {
        let view = HeaderEffectView()
        XCTAssertEqual(view.material, .underWindowBackground)
        XCTAssertEqual(view.blendingMode, .withinWindow)
        view.setVisible(true, animated: false)
        XCTAssertEqual(view.alphaValue, 1)
        view.setVisible(false, animated: false)
        XCTAssertEqual(view.alphaValue, 0)
        view.appearance = NSAppearance(named: .darkAqua)
        view.setVisible(true, animated: false)
        XCTAssertEqual(view.alphaValue, 1)
        XCTAssertNotNil(view.maskImage)
    }
    func testOriginalWindowAndContentInsetsArePreserved() {
        XCTAssertEqual(SettingsLayout.windowSize, CGSize(width: 720, height: 620))
        XCTAssertEqual(SettingsLayout.detailHorizontalInset, 16)
        XCTAssertEqual(FloatingHeaderMetrics.height,
            SettingsLayout.detailTopInset + SettingsLayout.detailHeaderHeight + SettingsLayout.detailSectionSpacing)
    }
}
