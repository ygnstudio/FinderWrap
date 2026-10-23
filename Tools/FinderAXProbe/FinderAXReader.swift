import AppKit
import ApplicationServices
import Foundation

/// Read-only sampler. This type contains no AX writes, event taps or permission prompts.
final class FinderAXReader {
    private let options: ProbeOptions
    private var snapshot: ProbeSnapshot
    private var elements: [AXUIElement] = []
    private var depths: [Int] = []
    private var started = ProcessInfo.processInfo.systemUptime

    init(options: ProbeOptions) {
        self.options = options
        snapshot = ProbeSnapshot(scenario: options.scenario)
        snapshot.measurements.budgetSeconds = options.budgetSeconds
    }

    func run() -> ProbeSnapshot {
        started = ProcessInfo.processInfo.systemUptime
        snapshot.accessibilityTrusted = AXIsProcessTrusted() // Never requests permission.
        let finder = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").first
        if let front = NSWorkspace.shared.frontmostApplication {
            snapshot.frontmostApplication = front.bundleIdentifier == "com.apple.finder" ? "finder" : "other"
            snapshot.frontmostPID = front.processIdentifier
        }
        snapshot.finderPID = finder?.processIdentifier
        if let bundleURL = finder?.bundleURL {
            snapshot.finderVersion = Bundle(url: bundleURL)?.infoDictionary?["CFBundleShortVersionString"] as? String
        }
        guard snapshot.accessibilityTrusted else {
            snapshot.status = "blocked-accessibility-permission"
            return finish()
        }
        guard let finder else {
            snapshot.status = "blocked-finder-not-running"
            return finish()
        }
        let system = AXUIElementCreateSystemWide()
        // A system-wide element sets the default for all AX calls in this process.
        _ = measured("system", "setMessagingTimeout") {
            AXUIElementSetMessagingTimeout(system, Float(snapshot.measurements.messagingTimeoutSeconds))
        }
        let app = AXUIElementCreateApplication(finder.processIdentifier)
        guard let appID = register(app, depth: 0) else { return finish() }
        snapshot.roots["finder"] = appID
        for (name, attribute) in [
            ("mainWindow", kAXMainWindowAttribute),
            ("finderFocusedWindow", kAXFocusedWindowAttribute),
            ("finderFocusedElement", kAXFocusedUIElementAttribute)
        ] {
            if let element = elementValue(app, node: appID, attribute: attribute),
               let id = register(element, depth: 1) { snapshot.roots[name] = id }
        }
        // Record system focus as a reference only; never traverse another application's tree.
        if let focus = elementValue(system, node: "system", attribute: kAXFocusedUIElementAttribute) {
            var pid: pid_t = 0
            let result = measured("system", "focusedElementPID") { AXUIElementGetPid(focus, &pid) }
            if result == .success, pid == finder.processIdentifier,
               let id = register(focus, depth: 1) { snapshot.roots["systemFocusedFinderElement"] = id }
        }
        let windows = readElements(app, node: appID, attribute: kAXWindowsAttribute)
        snapshot.windows = windows.elements.compactMap { register($0, depth: 1) }
        snapshot.nodes[0].relationCounts[kAXWindowsAttribute] = windows.count
        if windows.truncated { snapshot.nodes[0].truncatedRelations.append(kAXWindowsAttribute) }

        var index = 0
        while index < elements.count, hasBudget {
            inspect(index)
            index += 1
        }
        if index < elements.count { truncate("time-or-call-budget") }
        snapshot.status = snapshot.truncationReasons.isEmpty ? "sampled" : "sampled-partial"
        return finish()
    }

    private var hasBudget: Bool {
        ProcessInfo.processInfo.systemUptime - started < options.budgetSeconds && snapshot.measurements.calls.count < 20000
    }

    private func truncate(_ reason: String) {
        if !snapshot.truncationReasons.contains(reason) { snapshot.truncationReasons.append(reason) }
    }

    private func register(_ element: AXUIElement, depth: Int) -> String? {
        if let index = elements.firstIndex(where: { CFEqual($0, element) }) { return snapshot.nodes[index].id }
        guard depth <= options.maxDepth else { truncate("depth-limit"); return nil }
        guard elements.count < options.maxNodes else { truncate("node-limit"); return nil }
        let id = String(format: "n%04d", elements.count + 1)
        elements.append(element)
        depths.append(depth)
        snapshot.nodes.append(ProbeNode(id: id))
        return id
    }

    @discardableResult
    private func measured(_ node: String, _ operation: String, _ body: () -> AXError) -> AXError? {
        guard hasBudget else { truncate("time-or-call-budget"); return nil }
        let start = ProcessInfo.processInfo.systemUptime
        let result = body()
        let elapsed = (ProcessInfo.processInfo.systemUptime - start) * 1000
        snapshot.measurements.calls.append(ProbeCall(node: node, operation: operation, elapsedMS: elapsed, code: result.rawValue))
        if result != .success {
            snapshot.errors.append(ProbeError(node: node, operation: operation, code: result.rawValue, elapsedMS: elapsed))
        }
        return result
    }

    private func read(_ element: AXUIElement, node: String, attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        let result = measured(node, "read:\(attribute)") {
            AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        }
        return result == .success ? value : nil
    }

    private func elementValue(_ element: AXUIElement, node: String, attribute: String) -> AXUIElement? {
        guard let value = read(element, node: node, attribute: attribute), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    private func readElements(_ element: AXUIElement, node: String, attribute: String) -> (elements: [AXUIElement], count: Int?, truncated: Bool) {
        var count: CFIndex = 0
        guard measured(node, "count:\(attribute)", {
            AXUIElementGetAttributeValueCount(element, attribute as CFString, &count)
        }) == .success else { return ([], nil, false) }
        guard count > 0 else { return ([], count, false) }
        let limit = min(count, options.maxChildren)
        var array: [AXUIElement] = []
        // Finder can return fewer values than requested. Advance by the returned count.
        while array.count < limit, hasBudget {
            var values: CFArray?
            let result = measured(node, "readArray:\(attribute):\(array.count)") {
                AXUIElementCopyAttributeValues(element, attribute as CFString, array.count, min(20, limit - array.count), &values)
            }
            guard result == .success, let values else { break }
            let raw = values as [AnyObject]
            let page = raw.compactMap { value -> AXUIElement? in
                guard CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
                return (value as! AXUIElement)
            }
            guard !page.isEmpty, page.count == raw.count,
                  page.count <= limit - array.count else { break }
            array.append(contentsOf: page)
        }
        let truncated = count > limit || array.count != limit
        if truncated { truncate("partial-relation") }
        return (array, count, truncated)
    }

    private func isSettable(_ element: AXUIElement, node: String, attribute: String) -> Bool? {
        var writable = DarwinBoolean(false)
        guard measured(node, "settable:\(attribute)", {
            AXUIElementIsAttributeSettable(element, attribute as CFString, &writable)
        }) == .success else { return nil }
        return writable.boolValue
    }

    private func inspect(_ index: Int) {
        let element = elements[index]
        var node = snapshot.nodes[index]
        var names: CFArray?
        guard measured(node.id, "attributeNames", { AXUIElementCopyAttributeNames(element, &names) }) == .success else { return }
        let attributes = (names as? [String] ?? []).compactMap(ProbePrivacy.frameworkToken).sorted()
        node.attributes = attributes
        let supported = Set(attributes)
        func value(_ attribute: String) -> CFTypeRef? {
            supported.contains(attribute) ? read(element, node: node.id, attribute: attribute) : nil
        }
        node.role = (value(kAXRoleAttribute) as? String).flatMap(ProbePrivacy.frameworkToken)
        node.subrole = (value(kAXSubroleAttribute) as? String).flatMap(ProbePrivacy.frameworkToken)
        if let identifier = value(kAXIdentifierAttribute) as? String,
           ["IconView", "ListView", "ColumnView", "FinderWindow"].contains(identifier) {
            node.semanticIdentifier = identifier
        }
        node.selected = value(kAXSelectedAttribute) as? Bool
        node.focused = value(kAXFocusedAttribute) as? Bool
        if let position = value(kAXPositionAttribute), CFGetTypeID(position) == AXValueGetTypeID() {
            let axValue = position as! AXValue
            var point = CGPoint.zero
            if AXValueGetType(axValue) == .cgPoint, AXValueGetValue(axValue, .cgPoint, &point), point.x.isFinite, point.y.isFinite {
                node.position = ProbePoint(x: point.x, y: point.y)
            }
        }
        if let size = value(kAXSizeAttribute), CFGetTypeID(size) == AXValueGetTypeID() {
            let axValue = size as! AXValue
            var dimensions = CGSize.zero
            if AXValueGetType(axValue) == .cgSize, AXValueGetValue(axValue, .cgSize, &dimensions), dimensions.width.isFinite, dimensions.height.isFinite {
                node.size = ProbeSize(width: dimensions.width, height: dimensions.height)
            }
        }
        if supported.contains(kAXSelectedAttribute) { node.selectedSettable = isSettable(element, node: node.id, attribute: kAXSelectedAttribute) }
        if supported.contains(kAXSelectedChildrenAttribute) { node.selectedChildrenSettable = isSettable(element, node: node.id, attribute: kAXSelectedChildrenAttribute) }

        // Only descend into Finder windows, not its menus or unrelated application UI.
        if index != 0 {
            for attribute in [kAXChildrenAttribute, kAXSelectedChildrenAttribute, kAXVisibleChildrenAttribute] where supported.contains(attribute) {
                let relation = readElements(element, node: node.id, attribute: attribute)
                let ids = relation.elements.compactMap { register($0, depth: depths[index] + 1) }
                node.relationCounts[attribute] = relation.count
                if relation.truncated || ids.count != relation.elements.count { node.truncatedRelations.append(attribute) }
                switch attribute {
                case kAXChildrenAttribute: node.children = ids
                case kAXSelectedChildrenAttribute: node.selectedChildren = ids
                default: node.visibleChildren = ids
                }
            }
        }
        node.inspected = hasBudget
        snapshot.nodes[index] = node
    }

    private func finish() -> ProbeSnapshot {
        snapshot.attributes = Array(Set(snapshot.nodes.flatMap(\.attributes))).sorted()
        // These include all roles (e.g. sidebar selections); no icon-view classification is assumed.
        snapshot.selectedItems = Array(Set(snapshot.nodes.filter { $0.selected == true }.map(\.id) + snapshot.nodes.flatMap(\.selectedChildren))).sorted()
        snapshot.visibleItems = Array(Set(snapshot.nodes.flatMap(\.visibleChildren))).sorted()
        snapshot.measurements.elapsedMS = (ProcessInfo.processInfo.systemUptime - started) * 1000
        let durations = snapshot.measurements.calls.map(\.elapsedMS)
        snapshot.measurements.callCount = durations.count
        snapshot.measurements.maximumCallMS = durations.max() ?? 0
        snapshot.measurements.p95CallMS = ProbePrivacy.percentile95(durations)
        return snapshot
    }
}
