import XCTest

final class NavigationEngineTests: XCTestCase {
    private let engine = NavigationEngine()
    private func id(_ value: String) -> ItemID { ItemID(rawValue: value) }
    private func item(_ name: String, _ x: Double, _ y: Double, visible: Bool = true) -> NavigationItem {
        NavigationItem(id: id(name), frame: CGRect(x: x, y: y, width: 50, height: 50), fullyVisible: visible)
    }
    private var grid: [NavigationItem] {
        [item("a", 0, 0), item("b", 100, 0), item("c", 200, 0), item("d", 0, 100), item("e", 100, 100)]
    }
    private func snapshot(_ selected: [String], items: [NavigationItem]? = nil,
                          mode: LayoutMode = .ordered, complete: Bool = true) -> LayoutSnapshot {
        LayoutSnapshot(generation: UUID(), mode: mode,
                       groups: [NavigationGroup(id: GroupID(rawValue: "g"), items: items ?? grid)],
                       selected: Set(selected.map(id)), complete: complete)
    }

    func testRightEdgeWrapsToNextRowStart() {
        XCTAssertEqual(engine.decide(snapshot: snapshot(["c"]), direction: .right), .selectTarget(id("d")))
    }
    func testLeftEdgeWrapsToPreviousRowEnd() {
        XCTAssertEqual(engine.decide(snapshot: snapshot(["d"]), direction: .left), .selectTarget(id("c")))
    }
    func testInteriorKeepsNativeBehaviorInBothDirections() {
        for direction in [NavigationDirection.left, .right] {
            XCTAssertEqual(engine.decide(snapshot: snapshot(["b"]), direction: direction), .passThrough)
        }
    }
    func testEndpointsNeverCycle() {
        XCTAssertEqual(engine.decide(snapshot: snapshot(["a"]), direction: .left), .passThrough)
        XCTAssertEqual(engine.decide(snapshot: snapshot(["e"]), direction: .right), .passThrough)
    }
    func testMultipleOrMissingSelectionPassesThrough() {
        for selected in [[], ["c", "d"], ["missing"]] {
            XCTAssertEqual(engine.decide(snapshot: snapshot(selected), direction: .right), .passThrough)
        }
    }
    func testSourceOrderDoesNotDefineVisualOrder() {
        XCTAssertEqual(engine.decide(snapshot: snapshot(["c"], items: Array(grid.reversed())), direction: .right), .selectTarget(id("d")))
    }
    func testFreeArrangementAlsoHandlesInteriorNeighbors() {
        XCTAssertEqual(engine.decide(snapshot: snapshot(["b"], mode: .freeArrangement), direction: .right), .selectTarget(id("c")))
        XCTAssertEqual(engine.decide(snapshot: snapshot(["b"], mode: .freeArrangement), direction: .left), .selectTarget(id("a")))
    }
    func testFreeArrangementEndpointsNeverCycle() {
        XCTAssertEqual(engine.decide(snapshot: snapshot(["e"], mode: .freeArrangement), direction: .right), .passThrough)
    }
    func testOverlappingIconsPassThrough() {
        let items = [item("a", 0, 0), item("b", 20, 0), item("c", 0, 100)]
        XCTAssertEqual(engine.decide(snapshot: snapshot(["b"], items: items), direction: .right), .passThrough)
    }
    func testAmbiguousDiagonalRowsPassThrough() {
        let items = [item("a", 0, 0), item("b", 100, 30), item("c", 0, 100)]
        XCTAssertEqual(engine.decide(snapshot: snapshot(["b"], items: items), direction: .right), .passThrough)
    }
    func testSmallVerticalJitterCanStillFormARow() {
        let items = [item("a", 0, 0), item("b", 100, 4), item("c", 0, 100)]
        XCTAssertEqual(engine.decide(snapshot: snapshot(["b"], items: items), direction: .right), .selectTarget(id("c")))
    }
    func testIncompleteAndUnsupportedLayoutsPassThrough() {
        XCTAssertEqual(engine.decide(snapshot: snapshot(["c"], complete: false), direction: .right), .passThrough)
        XCTAssertEqual(engine.decide(snapshot: snapshot(["c"], mode: .unsupported), direction: .right), .passThrough)
    }
    func testDuplicateIdentitiesPassThrough() {
        XCTAssertEqual(engine.decide(snapshot: snapshot(["a"], items: [item("a", 0, 0), item("a", 0, 100)]), direction: .right), .passThrough)
    }
    func testNonFiniteOrZeroGeometryPassesThrough() {
        for frame in [CGRect(x: CGFloat.infinity, y: 0, width: 50, height: 50), CGRect.zero] {
            let invalid = NavigationItem(id: id("x"), frame: frame, fullyVisible: true)
            XCTAssertEqual(engine.decide(snapshot: snapshot(["c"], items: grid + [invalid]), direction: .right), .passThrough)
        }
    }
    func testOffscreenTargetPassesThroughWithoutGuessing() {
        let items = [item("a", 0, 0), item("b", 0, 100, visible: false)]
        XCTAssertEqual(engine.decide(snapshot: snapshot(["a"], items: items), direction: .right), .passThrough)
    }
    func testGroupsFollowVerticalGeometryAndCrossInBothDirections() {
        let groups = [NavigationGroup(id: GroupID(rawValue: "lower"), items: [item("c", 0, 200)]),
                      NavigationGroup(id: GroupID(rawValue: "upper"), items: [item("a", 0, 0), item("b", 100, 0)])]
        for (selected, direction, target) in [("b", NavigationDirection.right, "c"), ("c", .left, "b")] {
            let layout = LayoutSnapshot(generation: UUID(), mode: .grouped, groups: groups, selected: [id(selected)], complete: true)
            XCTAssertEqual(engine.decide(snapshot: layout, direction: direction), .selectTarget(id(target)))
        }
    }
    func testOverlappingGroupsAndUnverifiedGroupModePassThrough() {
        let groups = [NavigationGroup(id: GroupID(rawValue: "one"), items: [item("a", 0, 0)]),
                      NavigationGroup(id: GroupID(rawValue: "two"), items: [item("b", 100, 20)])]
        for mode in [LayoutMode.grouped, .ordered] {
            let layout = LayoutSnapshot(generation: UUID(), mode: mode, groups: groups, selected: [id("a")], complete: true)
            XCTAssertEqual(engine.decide(snapshot: layout, direction: .right), .passThrough)
        }
    }

    func testObservedMacOS26GeometryHasEightColumnRowBoundary() throws {
        struct Fixture: Decodable {
            struct Item: Decodable { let id: String; let x: Double; let y: Double; let width: Double; let height: Double }
            let items: [Item]
        }
        let file = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("Fixtures/macOS26/fully-visible.json")
        let fixture = try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: file))
        var items: [NavigationItem] = []
        for recorded in fixture.items {
            let frame = CGRect(x: recorded.x, y: recorded.y, width: recorded.width, height: recorded.height)
            items.append(NavigationItem(id: id(recorded.id), frame: frame, fullyVisible: true))
        }
        items.sort { left, right in
            if left.frame.minY == right.frame.minY { return left.frame.minX < right.frame.minX }
            return left.frame.minY < right.frame.minY
        }
        XCTAssertEqual(items.count, 36)
        guard items.count == 36 else { return }
        // The recorded coordinates are real; these selected IDs are test inputs.
        let layout = snapshot([items[7].id.rawValue], items: items)
        XCTAssertEqual(engine.decide(snapshot: layout, direction: .right), .selectTarget(items[8].id))
    }
}
