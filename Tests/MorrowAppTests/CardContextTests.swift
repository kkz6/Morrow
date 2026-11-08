import XCTest
import SwiftUI
@testable import MorrowApp

final class CardContextTests: XCTestCase {
    func testGroupedActionsKeepSoftCornersAndFollowCardEdges() {
        let size = CGSize(width: 300, height: 133)
        XCTAssertEqual(ActionCorners.resolve(button: CGRect(x: 4, y: 4, width: 292, height: 32), card: size), ActionCorners(top: 13, bottom: 3))
        XCTAssertEqual(ActionCorners.resolve(button: CGRect(x: 4, y: 50, width: 292, height: 32), card: size), ActionCorners(top: 3, bottom: 3))
        XCTAssertEqual(ActionCorners.resolve(button: CGRect(x: 4, y: 97, width: 292, height: 32), card: size), ActionCorners(top: 3, bottom: 13))
    }
    func testSingleActionAndCompactControlsKeepCorrectCorners() {
        XCTAssertEqual(ActionCorners.resolve(button: CGRect(x: 4, y: 4, width: 292, height: 32), card: CGSize(width: 300, height: 40)), ActionCorners(top: 13, bottom: 13))
        XCTAssertEqual(ActionCorners.resolve(button: CGRect(x: 210, y: 6, width: 80, height: 32), card: CGSize(width: 300, height: 40)), ActionCorners(top: 6, bottom: 6))
        XCTAssertEqual(ActionCorners.resolve(button: CGRect(x: 0, y: 0, width: 80, height: 32), card: nil), ActionCorners(top: 6, bottom: 6))
    }
    func testPairedActionsFollowOnlyTheirOutsideCorners() {
        let card = CGSize(width: 300, height: 84)
        XCTAssertEqual(ActionCorners.resolve(button: CGRect(x: 4, y: 48, width: 143, height: 32), card: card, grouped: true),
                       ActionCorners(topLeading: 3, topTrailing: 3, bottomLeading: 13, bottomTrailing: 3))
        XCTAssertEqual(ActionCorners.resolve(button: CGRect(x: 153, y: 48, width: 143, height: 32), card: card, grouped: true),
                       ActionCorners(topLeading: 3, topTrailing: 3, bottomLeading: 3, bottomTrailing: 13))
    }
    func testCornerCentersStayAlignedWhenTheInsetChanges() {
        for inset: CGFloat in [3, 4, 6, 8] {
            let corners = ActionCorners.resolve(button: CGRect(x: inset, y: inset, width: 300 - inset * 2, height: 40),
                                                card: CGSize(width: 300, height: 40 + inset * 2), inset: inset)
            XCTAssertEqual(corners.topLeading + inset, DS.Radius.card)
            XCTAssertEqual(corners.bottomTrailing + inset, DS.Radius.card)
        }
    }
}
