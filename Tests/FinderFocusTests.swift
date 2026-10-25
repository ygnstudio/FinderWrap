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
