import CoreGraphics
import XCTest
@testable import FinderBridge

final class WrapEngineTests: XCTestCase {
    private func cell(_ id: Int, x: CGFloat, y: CGFloat, size: CGFloat = 30) -> GridCell {
        GridCell(url: URL(fileURLWithPath: "/fixture/\(id)"),
                 frame: CGRect(x: x, y: y, width: size, height: size))
    }

    private var grid: [GridCell] {
        [cell(1, x: 10, y: 10), cell(2, x: 70, y: 10), cell(3, x: 10, y: 80), cell(4, x: 70, y: 80)]
    }

    private func layout(_ cells: [GridCell]) -> GridLayout { GridLayout(cells: cells) }

    private func decide(_ cells: [GridCell], _ id: Int, _ direction: HorizontalDirection) -> WrapDecision {
        WrapEngine().decide(layout: layout(cells),
                            selection: .single(URL(fileURLWithPath: "/fixture/\(id)")),
                            direction: direction)
    }

    func testWrapBothDirectionsAtRowEdges() {
        XCTAssertEqual(decide(grid, 2, .right), .wrap(from: grid[1].url, to: grid[2].url))
        XCTAssertEqual(decide(grid, 3, .left), .wrap(from: grid[2].url, to: grid[1].url))
    }

    func testInRowMovementStaysNative() {
        XCTAssertEqual(decide(grid, 1, .right), .native)
        XCTAssertEqual(decide(grid, 2, .left), .native)
    }

    func testDocumentEndsCycle() {
        XCTAssertEqual(decide(grid, 4, .right), .wrap(from: grid[3].url, to: grid[0].url))
        XCTAssertEqual(decide(grid, 1, .left), .wrap(from: grid[0].url, to: grid[3].url))
    }

    func testClippedBottomRowStillWraps() {
        // The second row extends past the viewport bottom; a partially visible
        // row must still be a valid wrap target.
        let cells = [cell(1, x: 10, y: 10), cell(2, x: 70, y: 10), cell(3, x: 10, y: 120), cell(4, x: 70, y: 120)]
        XCTAssertEqual(decide(cells, 2, .right), .wrap(from: cells[1].url, to: cells[2].url))
    }

    func testGroupedSectionsAreJustRows() {
        // A group header is not a cell; rows from different groups still chain.
        let cells = [cell(1, x: 10, y: 10), cell(2, x: 70, y: 10),
                     cell(3, x: 10, y: 200), cell(4, x: 70, y: 200)]
        XCTAssertEqual(decide(cells, 2, .right), .wrap(from: cells[1].url, to: cells[2].url))
        XCTAssertEqual(decide(cells, 3, .left), .wrap(from: cells[2].url, to: cells[1].url))
    }

    func testRaggedLastRowWrapsToItsFirstItem() {
        let cells = [cell(1, x: 10, y: 10), cell(2, x: 70, y: 10), cell(3, x: 130, y: 10),
                     cell(4, x: 10, y: 80)]
        XCTAssertEqual(decide(cells, 3, .right), .wrap(from: cells[2].url, to: cells[3].url))
    }

    func testSingleItemRowWraps() {
        let cells = [cell(1, x: 10, y: 10), cell(2, x: 10, y: 80)]
        XCTAssertEqual(decide(cells, 1, .right), .wrap(from: cells[0].url, to: cells[1].url))
        XCTAssertEqual(decide(cells, 2, .left), .wrap(from: cells[1].url, to: cells[0].url))
    }

    func testMultipleSelectionAnchorsOnOutermostItem() {
        let layout = GridLayout(cells: grid)
        let selection = GridSelection.multiple([URL(fileURLWithPath: "/fixture/1"),
                                                URL(fileURLWithPath: "/fixture/2")])
        XCTAssertEqual(WrapEngine().decide(layout: layout, selection: selection, direction: .right),
                       .wrap(from: grid[1].url, to: grid[2].url))
        let leftSelection = GridSelection.multiple([URL(fileURLWithPath: "/fixture/3"),
                                                    URL(fileURLWithPath: "/fixture/4")])
        XCTAssertEqual(WrapEngine().decide(layout: layout, selection: leftSelection, direction: .left),
                       .wrap(from: grid[2].url, to: grid[1].url))
    }

    func testMultipleSelectionInsideRowStaysNative() {
        let layout = GridLayout(cells: grid)
        let selection = GridSelection.multiple([URL(fileURLWithPath: "/fixture/1")])
        XCTAssertEqual(WrapEngine().decide(layout: layout, selection: selection, direction: .right), .native)
    }

    func testEmptyOrUnknownSelectionStaysNative() {
        let layout = GridLayout(cells: grid)
        XCTAssertEqual(WrapEngine().decide(layout: layout, selection: .empty, direction: .right), .native)
        XCTAssertEqual(WrapEngine().decide(layout: layout,
                                           selection: .single(URL(fileURLWithPath: "/fixture/99")),
                                           direction: .right), .native)
    }

    func testDuplicateURLCannotPickATarget() {
        let cells = grid + [cell(2, x: 130, y: 10)]
        XCTAssertEqual(decide(cells, 2, .right), .native)
    }

    func testRowsClusterByVerticalCenterAndSortByX() {
        let cells = [cell(2, x: 70, y: 12), cell(1, x: 10, y: 10), cell(3, x: 10, y: 80)]
        let layout = GridLayout(cells: cells)
        XCTAssertEqual(layout.rows.count, 2)
        XCTAssertEqual(layout.rows[0].map(\.url.lastPathComponent), ["1", "2"])
        XCTAssertEqual(layout.rows[1].map(\.url.lastPathComponent), ["3"])
    }

    func testInvalidGeometryIsIgnored() {
        let invalid = GridCell(url: URL(fileURLWithPath: "/fixture/9"),
                               frame: CGRect(x: 0, y: 0, width: 0, height: 30))
        let layout = GridLayout(cells: grid + [invalid])
        XCTAssertEqual(layout.cells.count, grid.count)
        XCTAssertEqual(decide(grid + [invalid], 2, .right), .wrap(from: grid[1].url, to: grid[2].url))
    }

    func testGalleryCyclesAtBothEnds() {
        let strip = [cell(1, x: 10, y: 10), cell(2, x: 70, y: 10), cell(3, x: 130, y: 10)]
        let layout = GridLayout(cells: strip)
        XCTAssertEqual(WrapEngine().cycleWithinRow(layout: layout,
                                                   selection: .single(strip[2].url), direction: .right),
                       .wrap(from: strip[2].url, to: strip[0].url))
        XCTAssertEqual(WrapEngine().cycleWithinRow(layout: layout,
                                                   selection: .single(strip[0].url), direction: .left),
                       .wrap(from: strip[0].url, to: strip[2].url))
    }

    func testGalleryStaysNativeInsideTheStripAndForMultipleRows() {
        let strip = [cell(1, x: 10, y: 10), cell(2, x: 70, y: 10), cell(3, x: 130, y: 10)]
        XCTAssertEqual(WrapEngine().cycleWithinRow(layout: GridLayout(cells: strip),
                                                   selection: .single(strip[1].url), direction: .right), .native)
        XCTAssertEqual(WrapEngine().cycleWithinRow(layout: GridLayout(cells: grid),
                                                   selection: .single(grid[1].url), direction: .right), .native)
        XCTAssertEqual(WrapEngine().cycleWithinRow(layout: GridLayout(cells: strip),
                                                   selection: .multiple([strip[0].url]), direction: .right), .native)
    }

}
