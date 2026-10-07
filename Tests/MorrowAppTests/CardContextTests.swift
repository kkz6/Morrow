import XCTest
import SwiftUI
@testable import MorrowApp

final class CardContextTests: XCTestCase {
    func testGroupedActionsRoundOnlyCardEdges() {
        let size = CGSize(width: 300, height: 133)
        XCTAssertEqual(ActionCorners.resolve(button: CGRect(x: 6, y: 6, width: 288, height: 32), card: size), ActionCorners(top: 11, bottom: 0))
        XCTAssertEqual(ActionCorners.resolve(button: CGRect(x: 6, y: 50, width: 288, height: 32), card: size), ActionCorners(top: 0, bottom: 0))
        XCTAssertEqual(ActionCorners.resolve(button: CGRect(x: 6, y: 95, width: 288, height: 32), card: size), ActionCorners(top: 0, bottom: 11))
    }
    func testSingleActionAndCompactControlsKeepCorrectCorners() {
        XCTAssertEqual(ActionCorners.resolve(button: CGRect(x: 6, y: 6, width: 288, height: 32), card: CGSize(width: 300, height: 44)), ActionCorners(top: 11, bottom: 11))
        XCTAssertEqual(ActionCorners.resolve(button: CGRect(x: 210, y: 6, width: 80, height: 32), card: CGSize(width: 300, height: 44)), ActionCorners(top: 8, bottom: 8))
        XCTAssertEqual(ActionCorners.resolve(button: CGRect(x: 0, y: 0, width: 80, height: 32), card: nil), ActionCorners(top: 8, bottom: 8))
    }
}
