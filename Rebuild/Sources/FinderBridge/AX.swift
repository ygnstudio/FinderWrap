import ApplicationServices
import Foundation

/// Small, allocation-light AX helpers. Every call is expected to be made on a
/// background queue or the event-tap thread with an explicit messaging timeout;
/// nothing here retries or blocks indefinitely.
enum AX {
    static func setTimeout(_ element: AXUIElement, _ seconds: Float) {
        AXUIElementSetMessagingTimeout(element, seconds)
    }

    static func value(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var raw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &raw) == .success else { return nil }
        return raw
    }

    static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        value(element, attribute) as? String
    }

    static func role(_ element: AXUIElement) -> String? {
        string(element, kAXRoleAttribute)
    }

    static func element(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        guard let raw = value(element, attribute), CFGetTypeID(raw) == AXUIElementGetTypeID() else { return nil }
        return (raw as! AXUIElement)
    }

    /// Direct attribute read for array attributes that do not implement
    /// AXUIElementGetAttributeValueCount (for example AXSelectedRows).
    static func elements(_ element: AXUIElement, _ attribute: String) -> [AXUIElement] {
        guard let raw = value(element, attribute) else { return [] }
        if CFGetTypeID(raw) == CFArrayGetTypeID() {
            let array = raw as! CFArray
            var result: [AXUIElement] = []
            for index in 0..<CFArrayGetCount(array) {
                guard let pointer = CFArrayGetValueAtIndex(array, index) else { continue }
                result.append(Unmanaged<AXUIElement>.fromOpaque(pointer).takeUnretainedValue())
            }
            return result
        }
        if CFGetTypeID(raw) == AXUIElementGetTypeID() {
            return [unsafeBitCast(raw, to: AXUIElement.self)]
        }
        return []
    }

    static func parent(_ element: AXUIElement) -> AXUIElement? {
        self.element(element, kAXParentAttribute)
    }

    static func fileURL(_ element: AXUIElement, _ attribute: String = kAXURLAttribute) -> URL? {
        fileURL(value: value(element, attribute))
    }

    static func fileURL(value raw: CFTypeRef?) -> URL? {
        guard let raw else { return nil }
        let url = raw as? URL ?? (raw as? String).flatMap(URL.init(string:))
        guard let url, url.isFileURL else { return nil }
        return url.standardizedFileURL
    }

    static func frame(_ element: AXUIElement) -> CGRect? {
        guard let p = value(element, kAXPositionAttribute), let s = value(element, kAXSizeAttribute) else { return nil }
        return frame(position: p, size: s)
    }

    static func frame(position rawPosition: CFTypeRef?, size rawSize: CFTypeRef?) -> CGRect? {
        guard let rawPosition, let rawSize,
              CFGetTypeID(rawPosition) == AXValueGetTypeID(), CFGetTypeID(rawSize) == AXValueGetTypeID() else { return nil }
        let position = rawPosition as! AXValue
        let size = rawSize as! AXValue
        guard AXValueGetType(position) == .cgPoint, AXValueGetType(size) == .cgSize else { return nil }
        var point = CGPoint.zero
        var extent = CGSize.zero
        guard AXValueGetValue(position, .cgPoint, &point), AXValueGetValue(size, .cgSize, &extent) else { return nil }
        guard point.x.isFinite, point.y.isFinite, extent.width.isFinite, extent.height.isFinite,
              extent.width > 0, extent.height > 0 else { return nil }
        return CGRect(origin: point, size: extent)
    }

    /// One round trip for several attributes. Missing or per-attribute errors are
    /// simply absent from the result, so optional attributes never erase usable
    /// data (role and geometry).
    static func fields(_ element: AXUIElement, _ names: [String]) -> [String: CFTypeRef] {
        var raw: CFArray?
        guard AXUIElementCopyMultipleAttributeValues(element, names as CFArray, [], &raw) == .success,
              let values = raw as? [AnyObject], values.count == names.count else { return [:] }
        var result: [String: CFTypeRef] = [:]
        for (name, value) in zip(names, values) {
            if CFGetTypeID(value) == AXValueGetTypeID(), AXValueGetType(value as! AXValue) == .axError { continue }
            if CFGetTypeID(value) == CFNullGetTypeID() { continue }
            result[name] = value
        }
        return result
    }

    static func fieldsFrame(_ fields: [String: CFTypeRef]) -> CGRect? {
        frame(position: fields[kAXPositionAttribute], size: fields[kAXSizeAttribute])
    }

    static func fieldsURL(_ fields: [String: CFTypeRef]) -> URL? {
        fileURL(value: fields[kAXURLAttribute])
    }

    static func isSettable(_ element: AXUIElement, _ attribute: String) -> Bool {
        var settable = DarwinBoolean(false)
        guard AXUIElementIsAttributeSettable(element, attribute as CFString, &settable) == .success else { return false }
        return settable.boolValue
    }

    static func count(_ element: AXUIElement, _ attribute: String) -> Int? {
        var count = 0
        guard AXUIElementGetAttributeValueCount(element, attribute as CFString, &count) == .success, count >= 0 else { return nil }
        return count
    }

    /// Bounded child enumeration. `limit` keeps a pathological provider from
    /// turning a refresh into an unbounded traversal.
    static func children(_ element: AXUIElement, _ attribute: String = kAXChildrenAttribute, limit: Int = 512) -> [AXUIElement] {
        guard let total = count(element, attribute), total > 0 else { return [] }
        var result: [AXUIElement] = []
        let capped = min(total, limit)
        while result.count < capped {
            var raw: CFArray?
            let request = min(64, capped - result.count)
            guard AXUIElementCopyAttributeValues(element, attribute as CFString, result.count, request, &raw) == .success,
                  let values = raw as? [AXUIElement], !values.isEmpty else { break }
            result.append(contentsOf: values)
        }
        return result
    }

    static func identity(_ element: AXUIElement) -> Identity {
        Identity(element)
    }

    struct Identity: Hashable {
        let element: AXUIElement
        init(_ element: AXUIElement) { self.element = element }
        static func == (lhs: Self, rhs: Self) -> Bool { CFEqual(lhs.element, rhs.element) }
        func hash(into hasher: inout Hasher) { hasher.combine(CFHash(element)) }
    }
}
