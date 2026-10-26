import XCTest
@testable import FinderBridge

final class LocalNavigationTests: XCTestCase {
    private func item(_ id: Int, x: Double, y: Double) -> VisibleItem {
        VisibleItem(url: URL(fileURLWithPath: "/fixture/\(id)"), frame: CGRect(x: x, y: y, width: 30, height: 30))
    }
    private var icons: [VisibleItem] {
        [item(1, x: 10, y: 10), item(2, x: 70, y: 10), item(3, x: 10, y: 80), item(4, x: 70, y: 80)]
    }
    private func layout(_ sections: [VisibleSection], fullWidth: Bool = true) -> VisibleLayout {
        VisibleLayout(sections: sections, viewport: CGRect(x: 0, y: 0, width: 200, height: 200), coversFullWidth: fullWidth)
    }
    private func decide(_ layout: VisibleLayout, _ id: Int = 2, _ direction: HorizontalDirection = .right) -> LocalDecision {
        LocalNavigation().decide(layout: layout, selection: .single(URL(fileURLWithPath: "/fixture/\(id)")), direction: direction)
    }
    func testBothDirectionsWrapAdjacentRows() {
        let l = layout([VisibleSection(items: icons)])
        XCTAssertEqual(decide(l), .wrap(from: icons[1].url, to: icons[2].url))
        XCTAssertEqual(decide(l, 3, .left), .wrap(from: icons[2].url, to: icons[1].url))
    }
    func testWithinRowAndDocumentEndsPreserveNativeBehavior() {
        let l = layout([VisibleSection(items: icons, startsAtFirstItem: true, endsAtLastItem: true)])
        for (id, direction) in [(1, HorizontalDirection.right), (2, .left), (1, .left), (4, .right)] {
            XCTAssertEqual(decide(l, id, direction), .native)
        }
    }
    func testAnUnrelatedUnreadableSectionDoesNotDisableValidBoundary() {
        let l = layout([VisibleSection(items: icons), VisibleSection(items: [], coverageKnown: false)])
        XCTAssertEqual(decide(l), .wrap(from: icons[1].url, to: icons[2].url))
        XCTAssertEqual(decide(l, 4), .native)
    }
    func testKnownGapOnlyBlocksItsOwnCorridor() {
        let outside = CGRect(x: 120, y: 160, width: 30, height: 30)
        let inside = CGRect(x: 120, y: 50, width: 30, height: 30)
        XCTAssertEqual(decide(layout([VisibleSection(items: icons, gaps: [outside])])), .wrap(from: icons[1].url, to: icons[2].url))
        XCTAssertEqual(decide(layout([VisibleSection(items: icons, gaps: [inside])])), .native)
    }
    func testUnknownGeometryDoesNotPretendToBeDistant() {
        XCTAssertEqual(decide(layout([VisibleSection(items: icons, coverageKnown: false)])), .native)
    }
    func testFoldedGroupDoesNotSkipHiddenItems() {
        let l = layout([VisibleSection(items: Array(icons.prefix(2)), endsAtLastItem: false),
                        VisibleSection(items: Array(icons.suffix(2)), startsAtFirstItem: true)])
        XCTAssertEqual(decide(l), .native)
    }
    func testProvenConsecutiveGroupEdgesCanWrap() {
        let l = layout([VisibleSection(items: Array(icons.prefix(2)), startsAtFirstItem: true, endsAtLastItem: true),
                        VisibleSection(items: Array(icons.suffix(2)), startsAtFirstItem: true, endsAtLastItem: true)])
        XCTAssertEqual(decide(l), .wrap(from: icons[1].url, to: icons[2].url))
        XCTAssertEqual(decide(l, 3, .left), .wrap(from: icons[2].url, to: icons[1].url))
    }
    func testUnreadableMiddleGroupCannotBeSkipped() {
        let l = layout([VisibleSection(items: Array(icons.prefix(2)), endsAtLastItem: true),
                        VisibleSection(items: [], coverageKnown: false),
                        VisibleSection(items: Array(icons.suffix(2)), startsAtFirstItem: true)])
        XCTAssertEqual(decide(l), .native)
    }
    func testIncompleteRowsAndHorizontalScrollingStayNative() {
        XCTAssertEqual(decide(layout([VisibleSection(items: icons)], fullWidth: false)), .native)
        let clipped = VisibleLayout(sections: [VisibleSection(items: icons)], viewport: CGRect(x: 0, y: 0, width: 200, height: 90), coversFullWidth: true)
        XCTAssertEqual(decide(clipped), .native)
    }
    func testMultiSelectionAndEmptyStayNative() {
        let l = layout([VisibleSection(items: icons)])
        for selected in [FinderSelectionReader.Selection.empty, .multiple(2), .multiple(36), .multiple(10000)] {
            XCTAssertEqual(LocalNavigation().decide(layout: l, selection: selected, direction: .right), .native)
        }
    }
    func testOverlappingAndDuplicatedItemsStayNative() {
        let overlap = icons + [item(5, x: 15, y: 15)]
        XCTAssertEqual(decide(layout([VisibleSection(items: overlap)])), .native)
        XCTAssertEqual(decide(layout([VisibleSection(items: icons + [icons[1]])])), .native)
    }
    func testGeometryDoesNotUseFolderCountAsSupportLimit() {
        // Represents the visible local window inside a 10,000-item folder. The
        // API deliberately has no global count precondition or hidden prefix.
        let local = [item(9997, x: 10, y: 10), item(9998, x: 70, y: 10), item(9999, x: 10, y: 80), item(10000, x: 70, y: 80)]
        XCTAssertEqual(decide(layout([VisibleSection(items: local)]), 9998), .wrap(from: local[1].url, to: local[2].url))
    }

    func testDistantOverlappingRowDoesNotDisableValidLocalBoundary() {
        let distant = [item(5, x: 10, y: 160), item(6, x: 15, y: 160)]
        let l = layout([VisibleSection(items: icons + distant)])
        XCTAssertEqual(decide(l), .wrap(from: icons[1].url, to: icons[2].url))
        XCTAssertEqual(decide(l, 4), .native)
    }
}
