import AppKit
import ApplicationServices
import Foundation

/// One captured icon cell and the AX elements needed to write a selection back.
struct BoundGridCell {
    let url: URL
    let frame: CGRect
    let wrapper: AXUIElement
    let image: AXUIElement
}

/// Immutable snapshot of one Finder icon surface. Handed to the event-tap thread
/// and replaced atomically by the refresh queue.
struct GridSnapshot {
    let pid: pid_t
    let application: AXUIElement
    let window: AXUIElement
    let grid: AXUIElement
    let viewport: AXUIElement
    let windowFrame: CGRect
    let viewportFrame: CGRect
    let gridRole: String
    let gridSubrole: String
    let gridIdentifier: String
    let selectedChildrenSupported: Bool
    /// True when the key presses are being made inside Quick Look. The icon
    /// grid underneath is still the real layout; Quick Look owns the focus ring.
    let quickLook: Bool
    let cells: [BoundGridCell]
    let layout: GridLayout
    let capturedAt: TimeInterval
}

/// Reads the frontmost Finder icon view. Runs only on the background refresh
/// queue; the tap thread never performs a full traversal.
struct GridFailure: Error {
    let stage: String
    let detail: String
}

struct GridReader {

    private let itemAttributes = [kAXRoleAttribute, kAXURLAttribute, kAXPositionAttribute, kAXSizeAttribute]

    func capture(pid: pid_t) throws -> GridSnapshot {
        let application = AXUIElementCreateApplication(pid)
        AX.setTimeout(application, 0.05)

        let focusedElement = AX.element(application, kAXFocusedUIElementAttribute)
        let focusedWindow = AX.element(application, kAXFocusedWindowAttribute)
        let quickLookWindow = focusedWindow.flatMap { Self.isQuickLookWindow($0) ? $0 : nil }

        var grid: AXUIElement?
        var window: AXUIElement?

        if quickLookWindow == nil {
            if let focusedElement { grid = gridAncestor(of: focusedElement) }
            if grid == nil, let focusedWindow { grid = searchGrid(from: focusedWindow, depth: 6) }
            if grid == nil, let focusedElement { grid = focusSurface(from: focusedElement) }
            if grid != nil { window = focusedWindow }
        } else {
            // Quick Look is a Finder-owned window in the focus ring. AXWindows is
            // ordered front to back, so the first non-Quick-Look window with an
            // icon grid is the window Quick Look is previewing from.
            for candidate in AX.children(application, kAXWindowsAttribute, limit: 12)
            where !Self.isQuickLookWindow(candidate) {
                if let found = searchGrid(from: candidate, depth: 6) {
                    grid = found
                    window = candidate
                    break
                }
            }
        }

        if grid == nil {
            for candidate in AX.children(application, kAXWindowsAttribute, limit: 12) {
                if let found = searchGrid(from: candidate, depth: 6) {
                    grid = found
                    if window == nil { window = candidate }
                    break
                }
            }
        }
        guard let grid else { throw GridFailure(stage: "grid", detail: describe(application)) }
        let windowElement = window ?? ancestor(of: grid) { AX.role($0) == "AXWindow" } ?? application

        let viewport = ancestor(of: grid) { AX.role($0) == "AXScrollArea" } ?? grid
        let windowFrame = AX.frame(windowElement) ?? AX.frame(grid) ?? .zero
        let viewportFrame = AX.frame(viewport) ?? AX.frame(grid) ?? .zero
        AX.setTimeout(grid, 0.05)
        AX.setTimeout(viewport, 0.05)

        var cells: [BoundGridCell] = []
        var seen = Set<AX.Identity>()
        let top = visibleChildren(of: grid)
        for child in top {
            collect(child, depth: 0, into: &cells, seen: &seen)
        }
        guard !cells.isEmpty else { throw GridFailure(stage: "empty", detail: describe(application)) }

        let layout = GridLayout(cells: cells.map { GridCell(url: $0.url, frame: $0.frame) })
        guard !layout.cells.isEmpty else { throw GridFailure(stage: "empty-layout", detail: describe(application)) }
        return GridSnapshot(pid: pid, application: application, window: windowElement, grid: grid, viewport: viewport,
                            windowFrame: windowFrame, viewportFrame: viewportFrame,
                            gridRole: AX.role(grid) ?? "?",
                            gridSubrole: AX.string(grid, kAXSubroleAttribute) ?? "-",
                            gridIdentifier: AX.string(grid, kAXIdentifierAttribute) ?? "-",
                            selectedChildrenSupported: AX.count(grid, kAXSelectedChildrenAttribute) != nil,
                            quickLook: quickLookWindow != nil,
                            cells: cells, layout: layout,
                            capturedAt: ProcessInfo.processInfo.systemUptime)
    }

    static func isQuickLookWindow(_ element: AXUIElement) -> Bool {
        AX.string(element, kAXSubroleAttribute) == "Quick Look"
    }

    private func visibleChildren(of grid: AXUIElement) -> [AXUIElement] {
        let visible = AX.children(grid, kAXVisibleChildrenAttribute)
        if !visible.isEmpty { return visible }
        return AX.children(grid)
    }

    private func gridAncestor(of element: AXUIElement) -> AXUIElement? {
        var node: AXUIElement? = element
        for _ in 0..<24 {
            guard let current = node else { return nil }
            if isGrid(current) { return current }
            node = AX.parent(current)
        }
        return nil
    }

    private func ancestor(of element: AXUIElement, matching predicate: (AXUIElement) -> Bool) -> AXUIElement? {
        var node: AXUIElement? = element
        for _ in 0..<24 {
            guard let current = node else { return nil }
            if predicate(current) { return current }
            node = AX.parent(current)
        }
        return nil
    }

    private func isGrid(_ element: AXUIElement) -> Bool {
        let fields = AX.fields(element, [kAXRoleAttribute, kAXSubroleAttribute, kAXIdentifierAttribute])
        let role = fields[kAXRoleAttribute] as? String
        if role == "AXGrid" { return true }
        if role == "AXList" {
            let subrole = fields[kAXSubroleAttribute] as? String
            let identifier = fields[kAXIdentifierAttribute] as? String
            return subrole == "AXCollectionList" || identifier == "IconView"
        }
        return false
    }

    private func searchGrid(from root: AXUIElement, depth: Int) -> AXUIElement? {
        var queue: [(AXUIElement, Int)] = [(root, 0)]
        var visited = 0
        while !queue.isEmpty, visited < 400 {
            let (node, level) = queue.removeFirst()
            visited += 1
            if level > 0, isGrid(node) { return node }
            if level >= depth { continue }
            for child in AX.children(node, kAXChildrenAttribute, limit: 120) {
                queue.append((child, level + 1))
            }
        }
        return nil
    }

    /// Returns the focused element or one of its ancestors when that node
    /// directly exposes readable icon cells. This is how the desktop icon
    /// surface is discovered: it is an AXGroup under an AXScrollArea, not a
    /// collection with an IconView identifier.
    private func focusSurface(from focused: AXUIElement) -> AXUIElement? {
        var node: AXUIElement? = focused
        for _ in 0..<4 {
            guard let current = node else { return nil }
            let role = AX.role(current) ?? ""
            if role == "AXApplication" { return nil }
            var cells: [BoundGridCell] = []
            var seen = Set<AX.Identity>()
            for child in AX.children(current, kAXChildrenAttribute, limit: 256) {
                collect(child, depth: 0, into: &cells, seen: &seen)
            }
            if !cells.isEmpty {
                guard let frame = AX.frame(current), frame.width > 1, frame.height > 1 else { return nil }
                if cells.contains(where: { frame.intersects($0.frame) }) { return current }
            }
            if role == "AXScrollArea" { return nil }
            node = AX.parent(current)
        }
        return nil
    }

    private func collect(_ node: AXUIElement, depth: Int, into cells: inout [BoundGridCell], seen: inout Set<AX.Identity>) {
        guard seen.insert(AX.identity(node)).inserted else { return }
        let role = AX.role(node) ?? ""
        if role == "AXImage" || role == "AXGroup" {
            if let cell = resolve(node) {
                cells.append(cell)
                return
            }
        }
        guard depth < 4, ["AXGroup", "AXList", "AXRow", "AXGrid", "AXScrollArea"].contains(role) else { return }
        for child in AX.children(node, kAXChildrenAttribute, limit: 200) {
            collect(child, depth: depth + 1, into: &cells, seen: &seen)
        }
    }

    /// Resolve a wrapper (the element Finder would report in AXSelectedChildren)
    /// and the image inside it to one cell. Returns nil for containers whose
    /// children are several items, so the caller descends instead.
    private func resolve(_ wrapper: AXUIElement) -> BoundGridCell? {
        let wrapperFields = AX.fields(wrapper, itemAttributes)
        let wrapperRole = wrapperFields[kAXRoleAttribute] as? String
        let wrapperURL = AX.fieldsURL(wrapperFields)
        let wrapperFrame = AX.fieldsFrame(wrapperFields)

        if wrapperRole == "AXImage" {
            guard let url = wrapperURL, let frame = wrapperFrame else { return nil }
            return BoundGridCell(url: url, frame: frame, wrapper: wrapper, image: wrapper)
        }

        let children = AX.children(wrapper, kAXChildrenAttribute, limit: 32)
        var images: [(AXUIElement, URL, CGRect)] = []
        for child in children {
            let fields = AX.fields(child, itemAttributes)
            guard (fields[kAXRoleAttribute] as? String) == "AXImage" else { continue }
            if let url = AX.fieldsURL(fields) ?? wrapperURL, let frame = AX.fieldsFrame(fields) {
                images.append((child, url, frame))
            }
        }
        guard images.count == 1 else { return nil }
        let (image, url, frame) = images[0]
        return BoundGridCell(url: url, frame: frame, wrapper: wrapper, image: image)
    }

    /// Current selection as URLs. Returns nil when the grid does not expose
    /// AXSelectedChildren, which keeps the key native.
    func selection(for snapshot: GridSnapshot, limit: Int = 128) -> GridSelection? {
        if snapshot.selectedChildrenSupported {
            return mapSelection(AX.children(snapshot.grid, kAXSelectedChildrenAttribute, limit: limit), in: snapshot)
        }
        // Desktops and other providers expose selection per item instead of a
        // selected-children collection. Scan the (visible) cells; this is only
        // used when the collection attribute is unavailable.
        var urls: [URL] = []
        for cell in snapshot.cells.prefix(limit) {
            let wrapperSelected = (AX.value(cell.wrapper, kAXSelectedAttribute) as? Bool) == true
            let imageSelected = CFEqual(cell.wrapper, cell.image)
                ? wrapperSelected
                : (AX.value(cell.image, kAXSelectedAttribute) as? Bool) == true
            if wrapperSelected || imageSelected { urls.append(cell.url) }
        }
        if urls.isEmpty { return .empty }
        if urls.count == 1 { return .single(urls[0]) }
        return .multiple(urls)
    }

    private func mapSelection(_ selected: [AXUIElement], in snapshot: GridSnapshot) -> GridSelection {
        if selected.isEmpty { return .empty }
        var lookup: [AX.Identity: URL] = [:]
        for cell in snapshot.cells {
            lookup[AX.identity(cell.wrapper)] = cell.url
            lookup[AX.identity(cell.image)] = cell.url
        }
        var urls: [URL] = []
        for element in selected {
            if let url = lookup[AX.identity(element)], !urls.contains(url) {
                urls.append(url)
            }
        }
        if urls.isEmpty { return .empty }
        if urls.count == 1 { return .single(urls[0]) }
        return .multiple(urls)
    }

    /// Full role/geometry-only dump of the Finder application tree. Used by the
    /// diagnostics button while another app is frontmost; it can still query
    /// Finder's windows. Never includes titles, names, URLs or paths.
    func describeFinder(pid: pid_t) -> String {
        let application = AXUIElementCreateApplication(pid)
        AX.setTimeout(application, 0.05)
        var lines: [String] = []
        if let focused = AX.element(application, kAXFocusedUIElementAttribute) {
            lines.append("focusedElement: \(summary(focused))")
            var chain: [String] = []
            var node: AXUIElement? = AX.parent(focused)
            for _ in 0..<8 {
                guard let current = node else { break }
                chain.append(summary(current))
                node = AX.parent(current)
            }
            lines.append("focusAncestors: " + chain.joined(separator: " > "))
        } else {
            lines.append("focusedElement: nil")
        }
        if let focused = AX.element(application, kAXFocusedUIElementAttribute),
           AX.role(focused) == "AXOutline" {
            lines.append(contentsOf: outlineDiagnostics(focused))
        }
        if let window = AX.element(application, kAXFocusedWindowAttribute) {
            lines.append("focusedWindow: \(summary(window))")
        } else {
            lines.append("focusedWindow: nil")
        }
        let windows = AX.children(application, kAXWindowsAttribute, limit: 10)
        lines.append("windows: \(windows.count)")
        for (index, window) in windows.enumerated() {
            let main = (AX.value(window, kAXMainAttribute) as? Bool) ?? false
            let focused = (AX.value(window, kAXFocusedAttribute) as? Bool) ?? false
            lines.append("  w\(index) \(summary(window)) main=\(main) focused=\(focused)")
            let children = AX.children(window, kAXChildrenAttribute, limit: 10)
            lines.append("    children: " + children.map { summary($0) }.joined(separator: " | "))
            if let grid = searchGrid(from: window, depth: 6) {
                lines.append("    grid: \(summary(grid))")
                let tops = AX.children(grid, kAXChildrenAttribute, limit: 6)
                lines.append("    gridChildren: " + tops.map { summary($0) }.joined(separator: " | "))
            } else {
                lines.append("    grid: none")
                var visited = Set<AX.Identity>()
                var treeLines: [String] = []
                tree(window, depth: 0, maxDepth: 4, visited: &visited, lines: &treeLines)
                lines.append(contentsOf: treeLines.map { "    " + $0 })
            }
        }
        return lines.joined(separator: "\n")
    }

    /// Attribute inventory for the Finder list outline. Names and value shapes
    /// only, never item titles or paths.
    private func outlineDiagnostics(_ outline: AXUIElement) -> [String] {
        var lines: [String] = ["outlineDiagnostics:"]
        var rawNames: CFArray?
        if AXUIElementCopyAttributeNames(outline, &rawNames) == .success, let names = rawNames as? [String] {
            lines.append("  attributes: " + names.sorted().joined(separator: ","))
        } else {
            lines.append("  attributes: unavailable")
        }
        let rows = AX.children(outline, kAXChildrenAttribute, limit: 6)
        if let first = rows.first {
            var rowNames: CFArray?
            if AXUIElementCopyAttributeNames(first, &rowNames) == .success, let names = rowNames as? [String] {
                lines.append("  rowAttributes: " + names.sorted().joined(separator: ","))
            }
            let children = AX.children(first, kAXChildrenAttribute, limit: 6)
            lines.append("  rowChildren: " + children.map { summary($0) }.joined(separator: " | "))
            if let cell = children.first {
                var cellNames: CFArray?
                if AXUIElementCopyAttributeNames(cell, &cellNames) == .success, let names = cellNames as? [String] {
                    lines.append("  cellAttributes: " + names.sorted().joined(separator: ","))
                }
            }
        }
        for attribute in [kAXSelectedRowsAttribute, kAXSelectedChildrenAttribute,
                          kAXFocusedAttribute, kAXValueAttribute, kAXChildrenAttribute] {
            lines.append("  \(attribute)=\(describeValue(AX.value(outline, attribute)))")
        }
        return lines
    }

    private func describeValue(_ raw: CFTypeRef?) -> String {
        guard let raw else { return "nil" }
        let type = CFGetTypeID(raw)
        if type == CFArrayGetTypeID() { return "array(\(CFArrayGetCount(raw as! CFArray)))" }
        if type == AXUIElementGetTypeID() { return "element" }
        if type == CFBooleanGetTypeID() { return "boolean" }
        if type == CFStringGetTypeID() { return "string" }
        if type == CFNumberGetTypeID() { return "number" }
        return "type=\(type)"
    }

    /// Role/geometry-only tree for views that are not icon grids (list, column,
    /// gallery). Bounded so a diagnostic stays readable.
    private func tree(_ element: AXUIElement, depth: Int, maxDepth: Int,
                      visited: inout Set<AX.Identity>, lines: inout [String]) {
        guard depth <= maxDepth, lines.count < 60 else { return }
        guard visited.insert(AX.identity(element)).inserted else { return }
        let children = AX.children(element, kAXChildrenAttribute, limit: 20)
        let indent = String(repeating: "  ", count: depth)
        lines.append(indent + summary(element) + " children=\(children.count)")
        guard depth < maxDepth else { return }
        for child in children.prefix(10) {
            tree(child, depth: depth + 1, maxDepth: maxDepth, visited: &visited, lines: &lines)
        }
    }

    /// Role/geometry-only description used by diagnostics. No titles, names or
    /// paths, so a pasted diagnostic never leaks private filenames.
    private func describe(_ application: AXUIElement) -> String {
        var parts: [String] = []
        if let window = AX.element(application, kAXFocusedWindowAttribute) {
            parts.append("focusedWindow=" + summary(window))
        } else {
            parts.append("focusedWindow=nil")
        }
        if let focused = AX.element(application, kAXFocusedUIElementAttribute) {
            var ancestors: [String] = []
            var node: AXUIElement? = focused
            for _ in 0..<10 {
                guard let current = node else { break }
                ancestors.append(summary(current))
                node = AX.parent(current)
            }
            parts.append("focused=" + summary(focused))
            parts.append("focusAncestors=" + ancestors.joined(separator: " > "))
        } else {
            parts.append("focused=nil")
        }
        let windows = AX.children(application, kAXWindowsAttribute, limit: 8)
        parts.append("windows=[" + windows.map { summary($0) }.joined(separator: " | ") + "]")
        return parts.joined(separator: "; ")
    }

    private func summary(_ element: AXUIElement) -> String {
        let fields = AX.fields(element, [kAXRoleAttribute, kAXSubroleAttribute, kAXIdentifierAttribute,
                                         kAXPositionAttribute, kAXSizeAttribute])
        let role = fields[kAXRoleAttribute] as? String ?? "?"
        let subrole = fields[kAXSubroleAttribute] as? String ?? "-"
        let identifier = fields[kAXIdentifierAttribute] as? String ?? "-"
        let frame = AX.fieldsFrame(fields).map { String(format: "%.0f,%.0f,%.0fx%.0f", $0.minX, $0.minY, $0.width, $0.height) } ?? "?"
        return "\(role)/\(subrole)/\(identifier)/\(frame)"
    }
}
