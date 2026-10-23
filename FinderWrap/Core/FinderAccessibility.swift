import ApplicationServices
import Foundation

struct FinderAccessibility {
    static let maximumItems = 160

    func capture(allowedDirectories: Set<String>? = nil, diagnostic: ((String) -> Void)? = nil) -> FinderContext? {
        guard AXIsProcessTrusted(), let pid = FinderSession.activePID else { diagnostic?("inactive-or-untrusted"); return nil }
        let ax = AXAccess(deadline: ProcessInfo.processInfo.systemUptime + 0.15, diagnostic: diagnostic)
        var stage = "window-and-focus"
        var complete = false
        defer { diagnostic?(complete ? "ready" : "\(stage); budgetExpired=\(!ax.withinBudget)") }
        let app = AXUIElementCreateApplication(pid)
        guard let window = ax.element(app, kAXMainWindowAttribute) else { return nil }
        stage = "focused-standard-window"
        guard let focusedWindow = ax.element(app, kAXFocusedWindowAttribute), CFEqual(window, focusedWindow),
              ax.read(window, kAXSubroleAttribute) as? String == "AXStandardWindow" else { return nil }
        stage = "focused-icon-collection"
        guard let collection = ax.element(app, kAXFocusedUIElementAttribute),
              ax.read(collection, kAXRoleAttribute) as? String == "AXList",
              ax.read(collection, kAXSubroleAttribute) as? String == "AXCollectionList",
              ax.read(collection, kAXIdentifierAttribute) as? String == "IconView" else { return nil }
        stage = "collection-window-owner"
        guard let owner = ax.element(collection, kAXWindowAttribute), CFEqual(owner, window) else { return nil }
        stage = "scroll-parent"
        guard let viewport = ax.element(collection, kAXParentAttribute),
              ax.read(viewport, kAXRoleAttribute) as? String == "AXScrollArea" else { return nil }
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
              let focusedWindow = ax.element(context.application, kAXFocusedWindowAttribute), CFEqual(focusedWindow, context.window),
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
        let writeResult = AXUIElementSetAttributeValue(context.collection, kAXSelectedChildrenAttribute as CFString, [target.wrapper] as CFArray)
        let ax = AXAccess(deadline: ProcessInfo.processInfo.systemUptime + 0.015)
        let observed: SelectionObservation
        if let readback = ax.elements(context.collection, kAXSelectedChildrenAttribute, limit: 2), readback.count == 1 {
            if CFEqual(readback[0], target.wrapper) { observed = .target }
            else if CFEqual(readback[0], original.wrapper) { observed = .original }
            else { observed = .other }
        } else { observed = .unavailable }
        return SelectionCommitResult.resolve(writeSucceeded: writeResult == .success, observation: observed)
    }
}
