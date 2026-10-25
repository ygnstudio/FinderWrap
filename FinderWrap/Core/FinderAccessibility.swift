import ApplicationServices
import Foundation

struct FinderAccessibility {
    static let maximumItems = 160

    struct FocusedIcons {
        let window: AXUIElement
        let collection: AXUIElement
        let viewport: AXUIElement
    }

    func focusedIcons(application app: AXUIElement, ax: AXAccess,
                      diagnostic: ((String) -> Void)? = nil) -> FocusedIcons? {
        guard let collection = ax.element(app, kAXFocusedUIElementAttribute) else {
            diagnostic?("focused-element-unavailable"); return nil
        }
        guard ax.read(collection, kAXRoleAttribute) as? String == "AXList" else {
            diagnostic?("focused-element-not-list"); return nil
        }
        guard ax.read(collection, kAXSubroleAttribute) as? String == "AXCollectionList" else {
            diagnostic?("focused-element-not-icon-collection"); return nil
        }
        guard ax.read(collection, kAXIdentifierAttribute) as? String == "IconView" else {
            diagnostic?("focused-element-not-icon-view"); return nil
        }
        // Keyboard focus and its owning window are authoritative. AXMainWindow can
        // be different or unavailable while these references remain consistent.
        guard let window = ax.element(collection, kAXWindowAttribute) else {
            diagnostic?("collection-window-unavailable"); return nil
        }
        guard ax.read(window, kAXRoleAttribute) as? String == "AXWindow" else {
            diagnostic?("collection-owner-not-window"); return nil
        }
        guard focusedWindowMatches(application: app, collection: collection, window: window,
                                   ax: ax, diagnostic: diagnostic) else { return nil }
        let subrole = ax.readResult(window, kAXSubroleAttribute)
        switch subrole.error {
        case .success:
            guard let value = subrole.value as? String,
                  ["AXStandardWindow", "AXUnknown"].contains(value) else {
                diagnostic?("window-subrole-unsupported"); return nil
            }
        case .attributeUnsupported, .noValue:
            // AXSubrole is optional. The verified IconView + window ownership is
            // the positive evidence here; dialogs with explicit subroles fail above.
            break
        default:
            diagnostic?("window-subrole-read-failed"); return nil
        }
        guard let viewport = ax.element(collection, kAXParentAttribute),
              ax.read(viewport, kAXRoleAttribute) as? String == "AXScrollArea" else {
            diagnostic?("icon-scroll-parent-unavailable-or-unsupported"); return nil
        }
        return FocusedIcons(window: window, collection: collection, viewport: viewport)
    }

    /// Used both when capturing and immediately before writing. Missing optional
    /// app attributes require independent system focus; transport errors never do.
    func focusedWindowMatches(application app: AXUIElement, collection: AXUIElement,
                              window: AXUIElement, ax: AXAccess,
                              diagnostic: ((String) -> Void)? = nil) -> Bool {
        let focused = ax.readResult(app, kAXFocusedWindowAttribute)
        switch focused.error {
        case .success:
            guard let value = focused.value, CFGetTypeID(value) == AXUIElementGetTypeID(),
                  CFEqual(value, window) else {
                diagnostic?("focused-window-owner-mismatch-or-invalid"); return false
            }
            return true
        case .attributeUnsupported, .noValue:
            guard let systemFocus = ax.element(AXUIElementCreateSystemWide(), kAXFocusedUIElementAttribute),
                  CFEqual(systemFocus, collection) else {
                diagnostic?("focused-window-missing-system-focus-unconfirmed"); return false
            }
            return true
        default:
            diagnostic?("focused-window-read-failed"); return false
        }
    }

    func capture(allowedDirectories: Set<String>? = nil, diagnostic: ((String) -> Void)? = nil) -> FinderContext? {
        guard AXIsProcessTrusted(), let pid = FinderSession.activePID else { diagnostic?("inactive-or-untrusted"); return nil }
        var lastReadIssue: String?
        let ax = AXAccess(deadline: ProcessInfo.processInfo.systemUptime + 0.15,
                          diagnostic: { lastReadIssue = $0 })
        var stage = "window-and-focus"
        var complete = false
        defer {
            var result = complete ? "ready" : "\(stage); budgetExpired=\(!ax.withinBudget)"
            if !complete, let lastReadIssue { result += "; lastAXReadIssue=\(lastReadIssue)" }
            diagnostic?(result)
        }
        let app = AXUIElementCreateApplication(pid)
        guard let focus = focusedIcons(application: app, ax: ax, diagnostic: { stage = $0 }) else { return nil }
        let window = focus.window, collection = focus.collection, viewport = focus.viewport
        stage = "window-and-viewport-geometry"
        guard let windowFrame = ax.frame(window), let viewportFrame = ax.frame(viewport) else { return nil }
        stage = "collection-sections"
        guard let sections = ax.elements(collection, kAXChildrenAttribute, limit: 24), !sections.isEmpty else { return nil }
        var settable = DarwinBoolean(false)
        stage = "selection-writability"
        guard ax.withinBudget,
              AXUIElementIsAttributeSettable(collection, kAXSelectedChildrenAttribute as CFString, &settable) == .success,
              settable.boolValue else { return nil }

        var bound: [BoundItem] = []
        var groups: [NavigationGroup] = []
        var sectionCounts: [(AXUIElement, Int)] = []
        var sectionHeaderCounts: [Int] = []
        for (sectionIndex, section) in sections.enumerated() {
            stage = "section-\(sectionIndex)"
            guard ax.read(section, kAXSubroleAttribute) as? String == "AXSectionList",
                  let children = ax.elements(section, kAXChildrenAttribute, limit: Self.maximumItems + 4) else { return nil }
            sectionCounts.append((section, children.count))
            var items: [NavigationItem] = []
            var headerCount = 0
            for (childIndex, child) in children.enumerated() {
                stage = "item-\(bound.count)"
                guard let role = ax.read(child, kAXRoleAttribute) as? String else { return nil }
                guard role == "AXGroup", let contents = ax.elements(child, kAXChildrenAttribute, limit: 4) else { return nil }
                // Observed date-group header: first wrapper contains text + button.
                // Require that concrete signature, not merely multiple containers.
                if childIndex == 0, contents.count == 2,
                   ax.read(contents[0], kAXRoleAttribute) as? String == "AXStaticText",
                   ax.read(contents[1], kAXRoleAttribute) as? String == "AXButton" {
                    headerCount += 1
                    continue
                }
                // The two empty, full-section decorators observed in free arrangement are
                // not a reliable public view-mode flag. Degrade instead of guessing the mode.
                guard contents.count == 1 else { return nil }
                guard let innerRole = ax.read(contents[0], kAXRoleAttribute) as? String else { return nil }
                guard innerRole == "AXImage", let frame = ax.frame(contents[0]),
                      ax.isInside(contents[0], directories: allowedDirectories),
                      ax.read(contents[0], kAXSelectedAttribute) as? Bool != nil,
                      bound.count < Self.maximumItems else { return nil }
                let model = NavigationItem(id: ItemID(rawValue: "item-\(bound.count)"), frame: frame,
                                           fullyVisible: viewportFrame.contains(frame))
                bound.append(BoundItem(model: model, wrapper: child, image: contents[0]))
                items.append(model)
            }
            guard !items.isEmpty else { return nil }
            sectionHeaderCounts.append(headerCount)
            groups.append(NavigationGroup(id: GroupID(rawValue: "section-\(sectionIndex)"), items: items))
        }
        guard !bound.isEmpty, ax.withinBudget, FinderSession.activePID == pid else { return nil }
        let grouped = sectionHeaderCounts.allSatisfy { $0 == 1 }
        guard grouped || (groups.count == 1 && sectionHeaderCounts == [0]) else { return nil }
        complete = true
        return FinderContext(pid: pid, application: app, window: window, collection: collection,
                             viewport: viewport, windowFrame: windowFrame, viewportFrame: viewportFrame,
                             groups: groups, items: bound, sectionCounts: sectionCounts,
                             mode: grouped ? .grouped : .ordered, allowedDirectories: allowedDirectories)
    }

    /// Revalidate every known item's selection and geometry before any write. In particular,
    /// collection.selectedChildren alone misses offscreen multi-selection on the observed OS.
    func liveSelection(in context: FinderContext, ax: AXAccess) -> Set<ItemID>? {
        guard FinderSession.activePID == context.pid,
              let focus = ax.element(context.application, kAXFocusedUIElementAttribute), CFEqual(focus, context.collection),
              let owner = ax.element(focus, kAXWindowAttribute), CFEqual(owner, context.window),
              focusedWindowMatches(application: context.application, collection: focus,
                                   window: context.window, ax: ax),
              ax.frame(context.window) == context.windowFrame,
              ax.frame(context.viewport) == context.viewportFrame,
              ax.count(context.collection, kAXChildrenAttribute) == context.groups.count else { return nil }
        for (section, count) in context.sectionCounts {
            guard ax.count(section, kAXChildrenAttribute) == count else { return nil }
        }
        var selected: Set<ItemID> = []
        for item in context.items {
            guard ax.frame(item.image) == item.model.frame,
                  ax.isInside(item.image, directories: context.allowedDirectories),
                  let isSelected = ax.read(item.image, kAXSelectedAttribute) as? Bool else { return nil }
            if isSelected { selected.insert(item.model.id) }
            if selected.count > 1 { return selected }
        }
        guard selected.count == 1, let id = selected.first,
              let original = context.items.first(where: { $0.model.id == id }),
              let collectionSelection = ax.elements(context.collection, kAXSelectedChildrenAttribute, limit: 2),
              collectionSelection.count == 1, CFEqual(collectionSelection[0], original.wrapper) else { return nil }
        return selected
    }

    func commit(target: BoundItem, original: BoundItem, in context: FinderContext) -> SelectionCommitResult {
        // Synchronous call on the tap thread, never fire-and-forget. No injected replay.
        SelectionCommitResult.perform(write: {
            AXUIElementSetAttributeValue(context.collection, kAXSelectedChildrenAttribute as CFString, [target.wrapper] as CFArray)
        }, readback: {
        let ax = AXAccess(deadline: ProcessInfo.processInfo.systemUptime + 0.015)
        if let readback = ax.elements(context.collection, kAXSelectedChildrenAttribute, limit: 2), readback.count == 1 {
            if CFEqual(readback[0], target.wrapper) { return .target }
            if CFEqual(readback[0], original.wrapper) { return .original }
            return .other
        }
        return .unavailable
        })
    }
}
