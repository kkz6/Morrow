import XCTest
import AppKit
@testable import MorrowApp

final class FloatingHeaderTests: XCTestCase {
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
        let image = SettingsEdgeEffectView.makeMask(edge: .top)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: try XCTUnwrap(image.tiffRepresentation)))
        XCTAssertEqual(try XCTUnwrap(bitmap.colorAt(x: 0, y: 0)).alphaComponent, 1, accuracy: 0.01)
        XCTAssertEqual(try XCTUnwrap(bitmap.colorAt(x: 0, y: bitmap.pixelsHigh - 1)).alphaComponent, 0, accuracy: 0.01)
        XCTAssertGreaterThan(try XCTUnwrap(bitmap.colorAt(x: 0, y: bitmap.pixelsHigh / 2)).alphaComponent, 0.95)
    }
    @MainActor func testBothEdgesAreVisibleImmediatelyInEitherAppearance() {
        for edge in [SettingsScrollEdge.top, .bottom] {
            let view = SettingsEdgeEffectView(edge: edge)
            XCTAssertEqual(view.material, .underWindowBackground)
            XCTAssertEqual(view.blendingMode, .withinWindow)
            for appearance in [NSAppearance.Name.aqua, .darkAqua] {
                view.appearance = NSAppearance(named: appearance)
                XCTAssertEqual(view.alphaValue, 1)
                XCTAssertNotNil(view.maskImage)
            }
        }
    }
    @MainActor func testFooterFadesIntoBottomPaddingWithoutCoveringLastRow() throws {
        let edge = SettingsScrollEdge.bottom
        XCTAssertEqual(edge.height, SettingsLayout.detailBottomInset)
        let image = SettingsEdgeEffectView.makeMask(edge: edge)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: try XCTUnwrap(image.tiffRepresentation)))
        XCTAssertEqual(try XCTUnwrap(bitmap.colorAt(x: 0, y: 0)).alphaComponent, 0, accuracy: 0.01)
        XCTAssertEqual(try XCTUnwrap(bitmap.colorAt(x: 0, y: bitmap.pixelsHigh - 1)).alphaComponent, 1, accuracy: 0.01)
        var previous: CGFloat = 0
        for y in stride(from: CGFloat(0), through: edge.height, by: 1) {
            let alpha = edge.maskAlpha(at: y)
            XCTAssertGreaterThanOrEqual(alpha, previous)
            XCTAssertLessThanOrEqual(alpha, 1)
            previous = alpha
        }
    }
    func testOriginalWindowAndContentInsetsArePreserved() {
        XCTAssertEqual(SettingsLayout.windowSize, CGSize(width: 720, height: 620))
        XCTAssertEqual(SettingsLayout.detailHorizontalInset, 16)
        XCTAssertEqual(FloatingHeaderMetrics.height,
            SettingsLayout.detailTopInset + SettingsLayout.detailHeaderHeight + SettingsLayout.detailSectionSpacing)
    }
}
