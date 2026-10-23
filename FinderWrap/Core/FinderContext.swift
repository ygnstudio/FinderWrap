import AppKit
import ApplicationServices
import Foundation

struct BoundItem {
    let model: NavigationItem
    let wrapper: AXUIElement
    let image: AXUIElement
}

/// Immutable references scoped to one Finder PID, window and snapshot generation.
final class FinderContext: @unchecked Sendable {
    let createdAt: TimeInterval
    let pid: pid_t
    let application: AXUIElement
    let window: AXUIElement
    let collection: AXUIElement
    let viewport: AXUIElement
    let windowFrame: CGRect
    let viewportFrame: CGRect
    let groups: [NavigationGroup]
    let items: [BoundItem]
    let sectionCounts: [(AXUIElement, Int)]
    let generation = UUID()
    let mode: LayoutMode
    let allowedDirectories: Set<String>?

    init(pid: pid_t, application: AXUIElement, window: AXUIElement, collection: AXUIElement,
         viewport: AXUIElement, windowFrame: CGRect, viewportFrame: CGRect,
         groups: [NavigationGroup], items: [BoundItem], sectionCounts: [(AXUIElement, Int)], mode: LayoutMode,
         allowedDirectories: Set<String>?, createdAt: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        self.createdAt = createdAt
        self.pid = pid; self.application = application; self.window = window; self.collection = collection
        self.viewport = viewport; self.windowFrame = windowFrame; self.viewportFrame = viewportFrame
        self.groups = groups; self.items = items; self.sectionCounts = sectionCounts; self.mode = mode
        self.allowedDirectories = allowedDirectories
    }
}

/// Deadline checked before every AX call; system messaging timeout bounds each in-flight call.
struct AXAccess {
    let deadline: TimeInterval
    var diagnostic: ((String) -> Void)? = nil
    var withinBudget: Bool { ProcessInfo.processInfo.systemUptime < deadline }

    func read(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        guard withinBudget else { return nil }
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard result == .success else { diagnostic?("read:\(attribute); AXError=\(result.rawValue)"); return nil }
        return value
    }
    func element(_ parent: AXUIElement, _ attribute: String) -> AXUIElement? {
        guard let value = read(parent, attribute), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }
    func count(_ element: AXUIElement, _ attribute: String) -> Int? {
        guard withinBudget else { return nil }
        var count: CFIndex = 0
        return AXUIElementGetAttributeValueCount(element, attribute as CFString, &count) == .success ? count : nil
    }
    func elements(_ parent: AXUIElement, _ attribute: String, limit: Int) -> [AXUIElement]? {
        guard let total = count(parent, attribute), total >= 0, total <= limit else { return nil }
        var result: [AXUIElement] = []
        while result.count < total {
            guard withinBudget else { return nil }
            var raw: CFArray?
            guard AXUIElementCopyAttributeValues(parent, attribute as CFString, result.count, min(20, total - result.count), &raw) == .success,
                  let raw else { return nil }
            let values = raw as [AnyObject]
            guard !values.isEmpty, values.count <= total - result.count else { return nil }
            for value in values {
                guard CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
                let child = value as! AXUIElement
                guard !result.contains(where: { CFEqual($0, child) }) else { return nil }
                result.append(child)
            }
        }
        guard count(parent, attribute) == total else { return nil }
        return result
    }
    func frame(_ element: AXUIElement) -> CGRect? {
        guard let position = read(element, kAXPositionAttribute), CFGetTypeID(position) == AXValueGetTypeID(),
              let size = read(element, kAXSizeAttribute), CFGetTypeID(size) == AXValueGetTypeID() else { return nil }
        let p = position as! AXValue, s = size as! AXValue
        var point = CGPoint.zero, dimensions = CGSize.zero
        guard AXValueGetType(p) == .cgPoint, AXValueGetType(s) == .cgSize,
              AXValueGetValue(p, .cgPoint, &point), AXValueGetValue(s, .cgSize, &dimensions),
              [point.x, point.y, dimensions.width, dimensions.height].allSatisfy(\.isFinite),
              dimensions.width > 0, dimensions.height > 0 else { return nil }
        return CGRect(origin: point, size: dimensions)
    }
    func isInside(_ image: AXUIElement, directories: Set<String>?) -> Bool {
        guard let directories else { return true }
        let raw = read(image, kAXURLAttribute)
        let url: URL?
        if let value = raw as? URL { url = value }
        else if let value = raw as? String { url = URL(string: value) }
        else { url = nil }
        guard let url, url.isFileURL else { return false }
        return directories.contains(url.deletingLastPathComponent().resolvingSymlinksInPath().standardizedFileURL.path)
    }
}

enum FinderSession {
    static var diagnostic: String {
        let session = CGSessionCopyCurrentDictionary() as? [String: Any]
        let onConsole = session?[kCGSessionOnConsoleKey as String] as? Bool
        let frontIsFinder = NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.finder"
        return "sessionExists=\(session != nil); onConsole=\(String(describing: onConsole)); frontIsFinder=\(frontIsFinder)"
    }
    static var activePID: pid_t? {
        guard let session = CGSessionCopyCurrentDictionary() as? [String: Any],
              session[kCGSessionOnConsoleKey as String] as? Bool == true,
              let front = NSWorkspace.shared.frontmostApplication,
              front.bundleIdentifier == "com.apple.finder" else { return nil }
        return front.processIdentifier
    }
}
