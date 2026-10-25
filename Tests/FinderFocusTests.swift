import XCTest
import ApplicationServices

/// AX responses are injected, not labelled as observations from macOS 15.
final class FinderFocusTests: XCTestCase {
    private final class Fixture {
        let app = AXUIElementCreateApplication(10001)
        let window = AXUIElementCreateApplication(10002)
        let collection = AXUIElementCreateApplication(10003)
        let viewport = AXUIElementCreateApplication(10004)
        let other = AXUIElementCreateApplication(10005)
        let system = AXUIElementCreateSystemWide()
        var values: [String: (AXError, CFTypeRef?)] = [:]
        var reads: [String] = []

        func name(_ element: AXUIElement) -> String {
            for (name, node) in [("app", app), ("window", window), ("collection", collection),
                                 ("viewport", viewport), ("other", other), ("system", system)] {
                if CFEqual(node, element) { return name }
            }
            return "unknown"
        }
        func set(_ node: String, _ attribute: String, _ value: CFTypeRef?, error: AXError = .success) {
            values[node + ":" + attribute] = (error, value)
        }
        init() {
            set("app", kAXMainWindowAttribute, window)
            set("app", kAXFocusedWindowAttribute, window)
            set("app", kAXFocusedUIElementAttribute, collection)
            set("system", kAXFocusedUIElementAttribute, collection)
            set("window", kAXRoleAttribute, "AXWindow" as CFString)
            set("window", kAXSubroleAttribute, "AXStandardWindow" as CFString)
            set("collection", kAXRoleAttribute, "AXList" as CFString)
            set("collection", kAXSubroleAttribute, "AXCollectionList" as CFString)
            set("collection", kAXIdentifierAttribute, "IconView" as CFString)
            set("collection", kAXWindowAttribute, window)
            set("collection", kAXParentAttribute, viewport)
            set("viewport", kAXRoleAttribute, "AXScrollArea" as CFString)
        }
        var access: AXAccess {
            AXAccess(deadline: ProcessInfo.processInfo.systemUptime + 1, copyAttribute: { node, attr in
                let key = self.name(node) + ":" + attr
                self.reads.append(key)
                return self.values[key] ?? (.attributeUnsupported, nil)
            })
        }
        func resolve() -> FinderAccessibility.FocusedIcons? {
            FinderAccessibility().focusedIcons(application: app, ax: access)
        }
    }

    func testStandardFocusedIconsRemainSupported() { XCTAssertNotNil(Fixture().resolve()) }

    func testMainWindowFailureDoesNotDiscardVerifiedFocusedIcons() {
        let f = Fixture()
        f.set("app", kAXMainWindowAttribute, nil, error: .cannotComplete)
        XCTAssertNotNil(f.resolve())
    }

    func testDifferentMainWindowDoesNotOverrideKeyboardFocus() {
        let f = Fixture()
        f.set("app", kAXMainWindowAttribute, f.other)
        XCTAssertNotNil(f.resolve())
    }

    func testOptionalWindowSubroleUsesPositiveIconOwnershipEvidence() {
        for error: AXError in [.attributeUnsupported, .noValue] {
            let f = Fixture()
            f.set("window", kAXSubroleAttribute, nil, error: error)
            XCTAssertNotNil(f.resolve())
        }
        let f = Fixture()
        f.set("window", kAXSubroleAttribute, "AXUnknown" as CFString)
        XCTAssertNotNil(f.resolve())
    }

    func testMissingFocusedWindowRequiresMatchingSystemFocus() {
        for error: AXError in [.attributeUnsupported, .noValue] {
            let f = Fixture()
            f.set("app", kAXFocusedWindowAttribute, nil, error: error)
            XCTAssertNotNil(f.resolve())
            f.set("system", kAXFocusedUIElementAttribute, f.other)
            XCTAssertNil(f.resolve())
            f.set("system", kAXFocusedUIElementAttribute, nil, error: .cannotComplete)
            XCTAssertNil(f.resolve())
        }
    }

    func testReadFailuresAreNeverTreatedAsOptionalAttributes() {
        for attr in [kAXFocusedWindowAttribute, kAXSubroleAttribute] {
            let f = Fixture()
            f.set(attr == kAXSubroleAttribute ? "window" : "app", attr, nil, error: .cannotComplete)
            XCTAssertNil(f.resolve())
        }
    }

    func testQuickLookOrAnotherFocusedWindowRejectsBackgroundIcons() {
        let f = Fixture()
        f.set("app", kAXFocusedWindowAttribute, f.other)
        XCTAssertNil(f.resolve())
    }

    func testEditingSidebarListColumnAndDesktopFocusRemainNative() {
        for role in ["AXTextField", "AXTextArea", "AXOutline", "AXBrowser", "AXScrollArea"] {
            let f = Fixture()
            f.set("collection", kAXRoleAttribute, role as CFString)
            XCTAssertNil(f.resolve())
        }
        for id in ["ListView", "ColumnView", "Desktop", "Sidebar"] {
            let f = Fixture()
            f.set("collection", kAXIdentifierAttribute, id as CFString)
            XCTAssertNil(f.resolve())
        }
    }

    func testDialogAndNonWindowOwnerRemainNative() {
        for subrole in ["AXDialog", "AXSystemDialog", "AXFloatingWindow", "unexpected-private-value"] {
            let f = Fixture()
            f.set("window", kAXSubroleAttribute, subrole as CFString)
            XCTAssertNil(f.resolve())
        }
        let f = Fixture()
        f.set("window", kAXRoleAttribute, "AXSheet" as CFString)
        XCTAssertNil(f.resolve())
    }

    func testMalformedWindowAndFocusReferencesRemainNative() {
        let f = Fixture()
        f.set("app", kAXFocusedWindowAttribute, "not-an-element" as CFString)
        XCTAssertNil(f.resolve())
        f.set("app", kAXFocusedWindowAttribute, nil, error: .noValue)
        f.set("system", kAXFocusedUIElementAttribute, "not-an-element" as CFString)
        XCTAssertNil(f.resolve())
    }
}

/// Synthetic API contracts, not a claim about the reporter's macOS hierarchy.
final class FinderSectionTests: XCTestCase {
    private final class Fixture {
        let section = AXUIElementCreateApplication(11001)
        let wrappers: [AXUIElement]
        let images: [AXUIElement]
        var extraNodes: [String: AXUIElement] = [:]
        var attributes: [String: (AXError, CFTypeRef?)] = [:]
        var children: [String: [AXUIElement]] = [:]
        var diagnostics: [String] = []
        var countError: AXError = .success
        var pageError: AXError = .success
        var countOverride: Int?
        var pageOverride: CFArray?
        var mutateCountAfterPage = false
        var fetchedPage = false

        func name(_ node: AXUIElement) -> String {
            if CFEqual(node, section) { return "section" }
            for (name, extra) in extraNodes where CFEqual(node, extra) { return name }
            for index in wrappers.indices {
                if CFEqual(node, wrappers[index]) { return "wrapper-\(index)" }
                if CFEqual(node, images[index]) { return "image-\(index)" }
            }
            return "unknown"
        }
        func set(_ node: AXUIElement, _ attribute: String, _ value: CFTypeRef?, error: AXError = .success) {
            attributes[name(node) + ":" + attribute] = (error, value)
        }
        init(itemCount: Int = 3) {
            wrappers = (0..<itemCount).map { AXUIElementCreateApplication(pid_t(12000 + $0)) }
            images = (0..<itemCount).map { AXUIElementCreateApplication(pid_t(13000 + $0)) }
            set(section, kAXRoleAttribute, "AXList" as CFString)
            set(section, kAXSubroleAttribute, "AXSectionList" as CFString)
            children["section"] = wrappers
            for i in wrappers.indices {
                set(wrappers[i], kAXRoleAttribute, "AXGroup" as CFString)
                children["wrapper-\(i)"] = [images[i]]
                set(images[i], kAXRoleAttribute, "AXImage" as CFString)
                set(images[i], kAXSelectedAttribute, kCFBooleanFalse)
                var point = CGPoint(x: (i % 2) * 50, y: (i / 2) * 50)
                var size = CGSize(width: 40, height: 40)
                set(images[i], kAXPositionAttribute, AXValueCreate(.cgPoint, &point))
                set(images[i], kAXSizeAttribute, AXValueCreate(.cgSize, &size))
            }
        }
        var access: AXAccess {
            AXAccess(deadline: ProcessInfo.processInfo.systemUptime + 1,
                     diagnostic: { self.diagnostics.append($0) },
                     copyAttribute: { node, attr in self.attributes[self.name(node) + ":" + attr] ?? (.attributeUnsupported, nil) },
                     countAttribute: { node, _ in
                let count = self.countOverride ?? (self.children[self.name(node)] ?? []).count
                return (self.countError, count + ((self.mutateCountAfterPage && self.fetchedPage) ? 1 : 0))
            }, copyElements: { node, _, offset, count in
                self.fetchedPage = true
                let list = self.children[self.name(node)] ?? []
                let page = Array(list.dropFirst(offset).prefix(count)) as CFArray
                return (self.pageError, self.pageOverride ?? page)
            })
        }
        func parse() -> FinderAccessibility.ParsedLayout? {
            FinderAccessibility().readLayout(sections: [section], viewportFrame: CGRect(x: 0, y: 0, width: 200, height: 200),
                                             ax: access, diagnostic: { self.diagnostics.append($0) })
        }
    }

    func testKnownSectionStillProducesARealNavigationTarget() throws {
        let layout = try XCTUnwrap(Fixture().parse())
        XCTAssertEqual(layout.items.count, 3)
        let snapshot = LayoutSnapshot(generation: UUID(), mode: layout.mode, groups: layout.groups,
                                      selected: [ItemID(rawValue: "item-1")], complete: true)
        XCTAssertEqual(NavigationEngine().decide(snapshot: snapshot, direction: .right), .selectTarget(ItemID(rawValue: "item-2")))
    }

    func testOptionalSectionSubroleDoesNotDiscardVerifiedImages() {
        for error: AXError in [.attributeUnsupported, .noValue] {
            let f = Fixture()
            f.set(f.section, kAXSubroleAttribute, nil, error: error)
            XCTAssertEqual(f.parse()?.items.count, 3, "optional subrole: \(error)")
        }
        let f = Fixture()
        f.set(f.section, kAXSubroleAttribute, "AXUnknown" as CFString)
        XCTAssertEqual(f.parse()?.items.count, 3)
    }

    func testSectionBasicRoleIsRequiredEvenWithKnownSubrole() {
        let f = Fixture()
        XCTAssertNotNil(f.parse())
        f.set(f.section, kAXRoleAttribute, "AXButton" as CFString)
        XCTAssertNil(f.parse())
    }

    func testSectionErrorsExplicitOtherSubrolesAndInvalidTypesStayRejected() {
        for error: AXError in [.cannotComplete, .invalidUIElement, .failure] {
            let f = Fixture()
            f.set(f.section, kAXSubroleAttribute, nil, error: error)
            XCTAssertNil(f.parse())
        }
        for value: CFTypeRef? in ["AXOutline" as CFString, kCFBooleanTrue, nil] {
            let f = Fixture()
            f.set(f.section, kAXSubroleAttribute, value)
            XCTAssertNil(f.parse())
        }
    }

    func testOptionalMetadataNeverSkipsImageAndGeometryValidation() {
        let f = Fixture()
        f.set(f.section, kAXSubroleAttribute, nil, error: .noValue)
        XCTAssertEqual(f.parse()?.items.count, 3)
        f.set(f.images[0], kAXRoleAttribute, "AXTextField" as CFString)
        XCTAssertNil(f.parse())
        f.set(f.images[0], kAXRoleAttribute, "AXImage" as CFString)
        f.set(f.images[0], kAXPositionAttribute, nil, error: .cannotComplete)
        XCTAssertNil(f.parse())
    }

    func testEmptyDecoratorsAndUnexpectedWrapperContentsStayRejected() {
        let f = Fixture()
        XCTAssertNotNil(f.parse())
        f.children["wrapper-0"] = []
        XCTAssertNil(f.parse())
        f.children["wrapper-0"] = [f.images[0], f.images[1]]
        XCTAssertNil(f.parse())
        f.children["section"] = []
        XCTAssertNil(f.parse())
    }

    func testOptionalSectionStillRequiresConcreteGroupHeaderShape() throws {
        let f = Fixture()
        let header = AXUIElementCreateApplication(14001)
        let label = AXUIElementCreateApplication(14002)
        let button = AXUIElementCreateApplication(14003)
        f.extraNodes = ["header": header, "label": label, "button": button]
        f.set(f.section, kAXSubroleAttribute, nil, error: .noValue)
        f.set(header, kAXRoleAttribute, "AXGroup" as CFString)
        f.set(label, kAXRoleAttribute, "AXStaticText" as CFString)
        f.set(button, kAXRoleAttribute, "AXButton" as CFString)
        f.children["section"] = [header] + f.wrappers
        f.children["header"] = [label, button]
        let layout = try XCTUnwrap(f.parse())
        XCTAssertEqual(layout.mode, .grouped)
        XCTAssertEqual(layout.items.count, 3)
        f.set(button, kAXRoleAttribute, "AXTextField" as CFString)
        XCTAssertNil(f.parse())
    }

    func testItemAndSectionChildLimitsRemainDistinct() {
        XCTAssertEqual(Fixture(itemCount: 160).parse()?.items.count, 160)
        let overItem = Fixture(itemCount: 161)
        XCTAssertNil(overItem.parse())
        XCTAssertTrue(overItem.diagnostics.contains("item-count-over-limit=160"))
        let overChildren = Fixture(itemCount: 165)
        XCTAssertNil(overChildren.parse())
        XCTAssertTrue(overChildren.diagnostics.contains { $0.contains("count-over-limit=165; limit=164") })
    }

    func testArrayFailuresHaveActionableCodesWithoutPayloads() {
        let f = Fixture()
        f.countOverride = 165
        XCTAssertNil(f.parse())
        XCTAssertTrue(f.diagnostics.contains { $0.contains("count-over-limit=165; limit=164") })
        f.countOverride = nil
        f.countError = .cannotComplete
        XCTAssertNil(f.parse())
        XCTAssertTrue(f.diagnostics.contains { $0.contains("count:AXChildren; AXError=-25204") })
        f.countError = .success
        f.pageError = .invalidUIElement
        XCTAssertNil(f.parse())
        XCTAssertTrue(f.diagnostics.contains { $0.contains("page:AXChildren; AXError=-25202") })
    }

    func testMalformedChangingAndDuplicateArraysStayRejectedWithReasons() {
        let f = Fixture()
        f.pageOverride = ["private-file-name"] as CFArray
        XCTAssertNil(f.parse())
        XCTAssertTrue(f.diagnostics.contains { $0.contains("child-not-element") })
        XCTAssertFalse(f.diagnostics.joined().contains("private-file-name"))
        f.pageOverride = [f.wrappers[0], f.wrappers[0]] as CFArray
        XCTAssertNil(f.parse())
        XCTAssertTrue(f.diagnostics.contains { $0.contains("duplicate-child") })
        f.pageOverride = nil
        f.mutateCountAfterPage = true
        f.fetchedPage = false
        XCTAssertNil(f.parse())
        XCTAssertTrue(f.diagnostics.contains { $0.contains("count-changed") })
    }
}
