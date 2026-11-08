import XCTest
import SwiftUI
@testable import MorrowApp

final class CardContextTests: XCTestCase {
    func testGroupedActionsKeepSoftCornersAndFollowCardEdges() {
        let size = CGSize(width: 300, height: 133)
        XCTAssertEqual(ActionCorners.resolve(button: CGRect(x: 4, y: 4, width: 292, height: 32), card: size), ActionCorners(top: 11, bottom: 3))
        XCTAssertEqual(ActionCorners.resolve(button: CGRect(x: 4, y: 50, width: 292, height: 32), card: size), ActionCorners(top: 3, bottom: 3))
        XCTAssertEqual(ActionCorners.resolve(button: CGRect(x: 4, y: 97, width: 292, height: 32), card: size), ActionCorners(top: 3, bottom: 11))
    }
    func testSingleActionAndCompactControlsKeepCorrectCorners() {
        XCTAssertEqual(ActionCorners.resolve(button: CGRect(x: 4, y: 4, width: 292, height: 32), card: CGSize(width: 300, height: 40)), ActionCorners(top: 11, bottom: 11))
        XCTAssertEqual(ActionCorners.resolve(button: CGRect(x: 210, y: 6, width: 80, height: 32), card: CGSize(width: 300, height: 40)), ActionCorners(top: 5, bottom: 5))
        XCTAssertEqual(ActionCorners.resolve(button: CGRect(x: 0, y: 0, width: 80, height: 32), card: nil), ActionCorners(top: 5, bottom: 5))
    }
}
