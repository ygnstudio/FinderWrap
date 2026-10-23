import AppKit
import ApplicationServices
import Foundation

/// Independent feasibility experiment, not part of the app or read-only probe.
/// It can write selection only inside the project's exact synthetic fixture folder.
@main
struct SelectionCheck {
    struct Failure: Error { let reason: String }
    struct Call: Encodable { let operation: String; let code: Int32; let elapsedMS: Double }
    struct Report: Encodable {
        var schemaVersion = 1
        var timestamp = ISO8601DateFormatter().string(from: Date())
        var status = "not-started"
        var calls: [Call] = []
        var fixtureMatched = false
        var selectedCountBefore = 0
        var targetReadbackMatched = false
        var restoredOriginalSelection = false
        var writeAttempted = false
        var error: String?
    }

    static func main() {
        var report = Report()
        func measure(_ label: String, _ body: () -> AXError) -> AXError {
            let start = ProcessInfo.processInfo.systemUptime
            let result = body()
            report.calls.append(Call(operation: label, code: result.rawValue,
                                     elapsedMS: (ProcessInfo.processInfo.systemUptime - start) * 1000))
            return result
        }
        func read(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
            var value: CFTypeRef?
            return measure("read:\(name)", { AXUIElementCopyAttributeValue(element, name as CFString, &value) }) == .success ? value : nil
        }
        func element(_ value: CFTypeRef?) -> AXUIElement? {
            guard let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
            return (value as! AXUIElement)
        }
        func array(_ parent: AXUIElement, _ attribute: String) -> [AXUIElement]? {
            guard let values = read(parent, attribute) as? [AnyObject], values.count <= 500 else { return nil }
            var result: [AXUIElement] = []
            for value in values {
                guard let child = element(value) else { return nil }
                result.append(child)
            }
            return result
        }
        func same(_ lhs: [AXUIElement], _ rhs: [AXUIElement]) -> Bool {
            lhs.count == rhs.count && zip(lhs, rhs).allSatisfy { CFEqual($0, $1) }
        }
        func fileURL(_ image: AXUIElement) -> URL? {
            let raw = read(image, kAXURLAttribute)
            if let url = raw as? URL, url.isFileURL { return url }
            if let string = raw as? String, let url = URL(string: string), url.isFileURL { return url }
            if let path = read(image, kAXFilenameAttribute) as? String, path.hasPrefix("/") {
                return URL(fileURLWithPath: path)
            }
            return nil
        }
        func fail(_ reason: String) throws -> Never { throw Failure(reason: reason) }

        do {
            guard CommandLine.arguments.count == 1 else { try fail("No arguments accepted; run from project root.") }
            guard AXIsProcessTrusted() else { try fail("accessibility-not-trusted") }
            guard let finder = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").first,
                  NSWorkspace.shared.frontmostApplication?.processIdentifier == finder.processIdentifier else {
                try fail("finder-not-frontmost")
            }
            _ = measure("setMessagingTimeout") { AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), 0.15) }
            let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("Tests/Fixtures/Synthetic", isDirectory: true).resolvingSymlinksInPath().standardizedFileURL
            guard (try? String(contentsOf: root.appendingPathComponent("Item-001.txt"), encoding: .utf8)) ==
                    "FinderWrap synthetic fixture 001\nNo user data.\n" else { try fail("fixture-marker-missing") }
            let app = AXUIElementCreateApplication(finder.processIdentifier)
            guard let window = element(read(app, kAXMainWindowAttribute)),
                  read(window, kAXTitleAttribute) as? String == root.lastPathComponent else { try fail("fixture-window-mismatch") }
            guard let collection = element(read(app, kAXFocusedUIElementAttribute)),
                  read(collection, kAXRoleAttribute) as? String == "AXList",
                  read(collection, kAXSubroleAttribute) as? String == "AXCollectionList",
                  read(collection, kAXIdentifierAttribute) as? String == "IconView",
                  let collectionWindow = element(read(collection, kAXWindowAttribute)), CFEqual(collectionWindow, window) else {
                try fail("observed-icon-view-signature-mismatch")
            }
            var writable = DarwinBoolean(false)
            guard measure("settable:AXSelectedChildren", {
                AXUIElementIsAttributeSettable(collection, kAXSelectedChildrenAttribute as CFString, &writable)
            }) == .success, writable.boolValue else { try fail("collection-selection-not-settable") }
            guard let original = array(collection, kAXSelectedChildrenAttribute), original.count == 1 else { try fail("requires-exactly-one-selected-fixture") }
            report.selectedCountBefore = original.count
            guard let sections = array(collection, kAXVisibleChildrenAttribute), sections.count == 1,
                  read(sections[0], kAXSubroleAttribute) as? String == "AXSectionList",
                  let visible = array(sections[0], kAXVisibleChildrenAttribute),
                  let target = visible.first(where: { !CFEqual($0, original[0]) }),
                  read(target, kAXRoleAttribute) as? String == "AXGroup",
                  visible.contains(where: { CFEqual($0, original[0]) }) else {
                try fail("no-verified-visible-fixture-target")
            }
            // AXDocument was advertised but returned noValue on the observed Finder.
            // Validate every visible item's URL in memory instead; never export it.
            for group in visible {
                guard let images = array(group, kAXChildrenAttribute), images.count == 1,
                      let url = fileURL(images[0]),
                      url.deletingLastPathComponent().resolvingSymlinksInPath().standardizedFileURL.path == root.path,
                      url.lastPathComponent.range(of: "^Item-[0-9]{3}\\.txt$", options: .regularExpression) != nil else {
                    try fail("fixture-item-url-mismatch")
                }
            }
            report.fixtureMatched = true
            // Recheck focus and selection immediately before writing; do not overwrite user interaction.
            guard NSWorkspace.shared.frontmostApplication?.processIdentifier == finder.processIdentifier,
                  let currentFocus = element(read(app, kAXFocusedUIElementAttribute)), CFEqual(currentFocus, collection),
                  let current = array(collection, kAXSelectedChildrenAttribute), same(current, original) else { try fail("context-changed") }
            report.writeAttempted = true
            let result = measure("write-target:AXSelectedChildren") {
                AXUIElementSetAttributeValue(collection, kAXSelectedChildrenAttribute as CFString, [target] as CFArray)
            }
            let after = array(collection, kAXSelectedChildrenAttribute)
            report.targetReadbackMatched = after.map { same($0, [target]) } ?? false
            if report.targetReadbackMatched {
                // Restore only the selection this experiment actually observed itself setting.
                let restore = measure("restore-original:AXSelectedChildren") {
                    AXUIElementSetAttributeValue(collection, kAXSelectedChildrenAttribute as CFString, original as CFArray)
                }
                report.restoredOriginalSelection = restore == .success && (array(collection, kAXSelectedChildrenAttribute).map { same($0, original) } ?? false)
            } else {
                report.restoredOriginalSelection = after.map { same($0, original) } ?? false
            }
            report.status = result == .success && report.targetReadbackMatched && report.restoredOriginalSelection ? "verified-round-trip" : "selection-write-not-verified"
        } catch let failure as Failure {
            report.status = "blocked-precondition"
            report.error = failure.reason
        } catch {
            report.status = "blocked-precondition"
            report.error = "unexpected-error"
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(report) {
            FileHandle.standardOutput.write(data)
            FileHandle.standardOutput.write(Data("\n".utf8))
        }
        exit(report.status == "verified-round-trip" ? 0 : 5)
    }
}
