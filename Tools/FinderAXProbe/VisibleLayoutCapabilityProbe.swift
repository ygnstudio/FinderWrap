import AppKit
import ApplicationServices
import Foundation

/// Read-only and fixture-scoped. Reports protocol capabilities, not item content.
@main
struct VisibleLayoutCapabilityProbe {
    static func main() {
        var report: [String: Any] = ["schemaVersion": 1, "readOnly": true]
        let allowed = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Tests/Fixtures/Synthetic").standardizedFileURL
        var error: NSDictionary?
        let scope = NSAppleScript(source: "tell application \"Finder\" to get POSIX path of (target of front Finder window as alias)")?
            .executeAndReturnError(&error).stringValue
        guard error == nil, scope.map({ URL(fileURLWithPath: $0).standardizedFileURL }) == allowed,
              AXIsProcessTrusted(), let finder = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").first
        else { report["scopeOrPermissionUnavailable"] = true; emit(report); return }
        let app = AXUIElementCreateApplication(finder.processIdentifier)
        AXUIElementSetMessagingTimeout(app, 0.05)
        func read(_ e: AXUIElement, _ name: String) -> CFTypeRef? {
            var value: CFTypeRef?
            return AXUIElementCopyAttributeValue(e, name as CFString, &value) == .success ? value : nil
        }
        guard let raw = read(app, kAXMainWindowAttribute), CFGetTypeID(raw) == AXUIElementGetTypeID() else {
            report["windowUnavailable"] = true; emit(report); return
        }
        var pending: [(AXUIElement, Int)] = [(raw as! AXUIElement, 0)]
        var nodes: [[String: Any]] = []
        var visited: [AXUIElement] = []
        while !pending.isEmpty, visited.count < 180 {
            let (element, depth) = pending.removeFirst()
            if visited.contains(where: { CFEqual($0, element) }) { continue }
            visited.append(element)
            let names = [kAXRoleAttribute, kAXSubroleAttribute, kAXPositionAttribute, kAXSizeAttribute,
                         kAXURLAttribute, kAXSelectedAttribute]
            var values: CFArray?
            let result = AXUIElementCopyMultipleAttributeValues(element, names as CFArray, [], &values)
            var row: [String: Any] = ["depth": depth, "batchResult": result.rawValue]
            let array = (values as? [AnyObject]) ?? []
            let role = array.first as? String ?? "unknown"
            row["role"] = role
            for (name, value) in zip(names, array) {
                if CFGetTypeID(value) == AXValueGetTypeID(), AXValueGetType(value as! AXValue) == .axError {
                    var e = AXError.success
                    AXValueGetValue(value as! AXValue, .axError, &e)
                    row[name] = ["error": e.rawValue]
                } else { row[name] = ["present": CFGetTypeID(value) != CFNullGetTypeID()] }
            }
            for name in [kAXChildrenAttribute, kAXVisibleChildrenAttribute, kAXSelectedChildrenAttribute] {
                var count = 0
                let status = AXUIElementGetAttributeValueCount(element, name as CFString, &count)
                row[name] = ["status": status.rawValue, "count": count]
            }
            nodes.append(row)
            if role == "AXImage" || depth >= 8 { continue }
            if let children = read(element, kAXChildrenAttribute) as? [AXUIElement] {
                pending.append(contentsOf: children.prefix(80).map { ($0, depth + 1) })
            }
        }
        report["nodes"] = nodes
        report["fixtureWindowConfirmed"] = true
        emit(report)
    }

    static func emit(_ value: [String: Any]) {
        if let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .prettyPrinted]) {
            FileHandle.standardOutput.write(data)
        }
    }
}
