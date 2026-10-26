import AppKit
import ApplicationServices
import Foundation

struct AXReadFailure: Error {
    let code: AXError
    let attribute: String
}

/// Public AX batching returns per-attribute AXError values inside an otherwise
/// successful reply. Optional unsupported attributes must not erase good data.
struct AXFields {
    let values: [String: Result<CFTypeRef, AXReadFailure>]
    func value(_ name: String) -> CFTypeRef? { try? values[name]?.get() }
    func string(_ name: String) -> String? { value(name) as? String }
    func element(_ name: String) -> AXUIElement? {
        guard let value = value(name), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }
    var frame: CGRect? {
        guard let p = value(kAXPositionAttribute), let s = value(kAXSizeAttribute),
              CFGetTypeID(p) == AXValueGetTypeID(), CFGetTypeID(s) == AXValueGetTypeID(),
              AXValueGetType(p as! AXValue) == .cgPoint, AXValueGetType(s as! AXValue) == .cgSize else { return nil }
        var point = CGPoint.zero, size = CGSize.zero
        guard AXValueGetValue(p as! AXValue, .cgPoint, &point), AXValueGetValue(s as! AXValue, .cgSize, &size),
              [point.x, point.y, size.width, size.height].allSatisfy(\.isFinite), size.width > 0, size.height > 0 else { return nil }
        return CGRect(origin: point, size: size)
    }
    var url: URL? {
        let raw = value(kAXURLAttribute)
        let url = raw as? URL ?? (raw as? String).flatMap(URL.init(string:))
        return url?.isFileURL == true ? url?.standardizedFileURL : nil
    }
}

struct AXBatchReader {
    var deadline: TimeInterval
    var withinBudget: Bool { ProcessInfo.processInfo.systemUptime < deadline }
    static let geometry = [kAXPositionAttribute, kAXSizeAttribute]
    static let itemFields = [kAXRoleAttribute, kAXSubroleAttribute, kAXURLAttribute, kAXSelectedAttribute] + geometry

    func fields(_ element: AXUIElement, _ names: [String]) throws -> AXFields {
        guard withinBudget else { throw AXReadFailure(code: .cannotComplete, attribute: "capture-budget") }
        var raw: CFArray?
        let error = AXUIElementCopyMultipleAttributeValues(element, names as CFArray, [], &raw)
        guard error == .success, let result = raw as? [AnyObject], result.count == names.count else {
            throw AXReadFailure(code: error == .success ? .failure : error, attribute: "batch:" + names.joined(separator: ","))
        }
        return Self.decode(names: names, values: result)
    }

    static func decode(names: [String], values: [AnyObject]) -> AXFields {
        var fields: [String: Result<CFTypeRef, AXReadFailure>] = [:]
        for (name, value) in zip(names, values) {
            if CFGetTypeID(value) == AXValueGetTypeID(), AXValueGetType(value as! AXValue) == .axError {
                var error = AXError.failure
                AXValueGetValue(value as! AXValue, .axError, &error)
                fields[name] = .failure(AXReadFailure(code: error, attribute: name))
            } else if CFGetTypeID(value) == CFNullGetTypeID() {
                fields[name] = .failure(AXReadFailure(code: .noValue, attribute: name))
            } else { fields[name] = .success(value) }
        }
        return AXFields(values: fields)
    }

    func count(_ element: AXUIElement, _ name: String) throws -> Int {
        guard withinBudget else { throw AXReadFailure(code: .cannotComplete, attribute: "capture-budget") }
        var count = 0
        let result = AXUIElementGetAttributeValueCount(element, name as CFString, &count)
        guard result == .success, count >= 0 else { throw AXReadFailure(code: result, attribute: name) }
        return count
    }

    func children(_ element: AXUIElement, attribute: String = kAXChildrenAttribute) throws -> [AXUIElement] {
        let total = try count(element, attribute)
        var children = [AXUIElement]()
        var seen = Set<AXIdentity>()
        while children.count < total {
            guard withinBudget else { throw AXReadFailure(code: .cannotComplete, attribute: "capture-budget") }
            var raw: CFArray?
            let requested = min(64, total - children.count)
            let error = AXUIElementCopyAttributeValues(element, attribute as CFString, children.count, requested, &raw)
            guard error == .success, let values = raw as? [AnyObject], !values.isEmpty, values.count <= requested else {
                throw AXReadFailure(code: error == .success ? .failure : error, attribute: attribute)
            }
            for value in values {
                guard CFGetTypeID(value) == AXUIElementGetTypeID(), seen.insert(AXIdentity(value as! AXUIElement)).inserted else {
                    throw AXReadFailure(code: .failure, attribute: attribute)
                }
                children.append(value as! AXUIElement)
            }
        }
        guard try count(element, attribute) == total else { throw AXReadFailure(code: .failure, attribute: "children-changed") }
        return children
    }

    struct AXIdentity: Hashable {
        let element: AXUIElement
        init(_ element: AXUIElement) { self.element = element }
        static func == (lhs: Self, rhs: Self) -> Bool { CFEqual(lhs.element, rhs.element) }
        func hash(into hasher: inout Hasher) { hasher.combine(CFHash(element)) }
    }
}

public final class VisibleAXContext {
    public let layout: VisibleLayout
    public let captureMS: Double
    public let usesVisibleChildren: Bool
    let application: AXUIElement
    let window: AXUIElement
    let collection: AXUIElement
    let viewport: AXUIElement
    let windowFrame: CGRect
    let viewportFrame: CGRect
    let bindings: [URL: BoundIcon]
    struct BoundIcon { let wrapper: AXUIElement; let image: AXUIElement; let frame: CGRect }
    init(layout: VisibleLayout, captureMS: Double, usesVisibleChildren: Bool,
         application: AXUIElement, window: AXUIElement, collection: AXUIElement, viewport: AXUIElement,
         windowFrame: CGRect, viewportFrame: CGRect, bindings: [URL: BoundIcon]) {
        self.layout = layout; self.captureMS = captureMS; self.usesVisibleChildren = usesVisibleChildren
        self.application = application; self.window = window; self.collection = collection; self.viewport = viewport
        self.windowFrame = windowFrame; self.viewportFrame = viewportFrame; self.bindings = bindings
    }
}

/// Captures a visible icon surface on a worker. No selection writes or key events.
/// An explicit current-view value from Finder disambiguates icon collections from
/// list/column/gallery views; editing focus still prevents an icon capture.
public struct VisibleAXReader {
    public enum NativeSurface: String { case notIconView, editingOrOtherFocus, previewOrDialog }
    public enum Failure: Error { case nativeSurface(NativeSurface), unavailable(String), outsideScope }
    public init() {}

    public func capture(pid: pid_t, officialWindow: FinderSelectionReader.Window,
                        allowedDirectory: URL? = nil, budget: TimeInterval = 0.5) throws -> VisibleAXContext {
        guard officialWindow.isIconView else { throw Failure.nativeSurface(.notIconView) }
        if let allowedDirectory, officialWindow.directory != allowedDirectory.standardizedFileURL { throw Failure.outsideScope }
        let started = ProcessInfo.processInfo.systemUptime
        let ax = AXBatchReader(deadline: started + budget)
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.04)
        let focusFields = try ax.fields(app, [kAXFocusedUIElementAttribute, kAXFocusedWindowAttribute])
        guard var node = focusFields.element(kAXFocusedUIElementAttribute),
              let focusedWindow = focusFields.element(kAXFocusedWindowAttribute) else { throw Failure.unavailable("focus") }
        var collection: AXUIElement?
        var visited = Set<AXBatchReader.AXIdentity>()
        for _ in 0..<16 {
            guard visited.insert(.init(node)).inserted else { break }
            let f = try ax.fields(node, [kAXRoleAttribute, kAXSubroleAttribute, kAXIdentifierAttribute, kAXParentAttribute])
            let role = f.string(kAXRoleAttribute)
            if role == "AXGrid" || (role == "AXList" && (f.string(kAXSubroleAttribute) == "AXCollectionList" || f.string(kAXIdentifierAttribute) == "IconView")) {
                collection = node; break
            }
            guard ["AXImage", "AXGroup", "AXList"].contains(role ?? ""), let parent = f.element(kAXParentAttribute) else { break }
            node = parent
        }
        guard let collection else { throw Failure.nativeSurface(.editingOrOtherFocus) }
        let owner = try ax.fields(collection, [kAXWindowAttribute, kAXParentAttribute] + AXBatchReader.geometry)
        guard let window = owner.element(kAXWindowAttribute), CFEqual(window, focusedWindow) else { throw Failure.unavailable("window-owner") }
        let windowFields = try ax.fields(window, [kAXRoleAttribute, kAXSubroleAttribute, kAXModalAttribute] + AXBatchReader.geometry)
        guard windowFields.string(kAXRoleAttribute) == "AXWindow",
              !["Quick Look", "AXDialog", "AXSystemDialog"].contains(windowFields.string(kAXSubroleAttribute) ?? ""),
              windowFields.value(kAXModalAttribute) as? Bool != true,
              let windowFrame = windowFields.frame else { throw Failure.nativeSurface(.previewOrDialog) }
        var viewport: AXUIElement?
        node = collection
        for _ in 0..<8 {
            let f = try ax.fields(node, [kAXParentAttribute])
            guard let parent = f.element(kAXParentAttribute) else { break }
            let p = try ax.fields(parent, [kAXRoleAttribute])
            if p.string(kAXRoleAttribute) == "AXScrollArea" { viewport = parent; break }
            guard p.string(kAXRoleAttribute) == "AXGroup" else { break }
            node = parent
        }
        guard let viewport, let viewportFrame = try ax.fields(viewport, AXBatchReader.geometry).frame,
              let collectionFrame = owner.frame else { throw Failure.unavailable("viewport") }

        var usedVisible = false
        func published(_ element: AXUIElement) throws -> (children: [AXUIElement], complete: Bool) {
            do {
                let visible = try ax.children(element, attribute: kAXVisibleChildrenAttribute)
                usedVisible = true
                return (visible, try ax.count(element, kAXChildrenAttribute) == visible.count)
            } catch let error as AXReadFailure where error.code == .attributeUnsupported || error.code == .notImplemented {
                // Older providers: enumerate on the worker within a time budget,
                // without turning a directory item count into a support limit.
                return (try ax.children(element), true)
            }
        }
        var bindings: [URL: VisibleAXContext.BoundIcon] = [:]
        func parse(_ element: AXUIElement) -> VisibleSection {
            var items = [VisibleItem](), gaps = [CGRect]()
            var coverageKnown = true
            var complete = false
            var allPublishedNodesResolved = true
            do {
                let publication = try published(element)
                complete = publication.complete
                for child in publication.children {
                    var bounds: CGRect?
                    do {
                        let wrapper = try ax.fields(child, AXBatchReader.itemFields)
                        bounds = wrapper.frame
                        // A failed offscreen image does not prevent a local wrap.
                        if let bounds, !bounds.intersects(viewportFrame) { allPublishedNodesResolved = false; continue }
                        let image: AXUIElement
                        let fields: AXFields
                        if wrapper.string(kAXRoleAttribute) == "AXImage" { image = child; fields = wrapper }
                        else {
                            let children = try ax.children(child)
                            let contents = try children.map { ($0, try ax.fields($0, AXBatchReader.itemFields)) }
                            if Set(contents.compactMap { $0.1.string(kAXRoleAttribute) }) == ["AXStaticText", "AXButton"] { continue }
                            let images = contents.filter { $0.1.string(kAXRoleAttribute) == "AXImage" }
                            guard images.count == 1,
                                  contents.allSatisfy({ ["AXImage", "AXStaticText"].contains($0.1.string(kAXRoleAttribute) ?? "") }) else {
                                if let bounds { gaps.append(bounds) } else { coverageKnown = false }
                                continue
                            }
                            (image, fields) = images[0]
                        }
                        guard let frame = fields.frame, let url = fields.url,
                              fields.value(kAXSelectedAttribute) as? Bool != nil else {
                            if let bounds { gaps.append(bounds) } else { coverageKnown = false }
                            continue
                        }
                        if let allowedDirectory, url.deletingLastPathComponent().standardizedFileURL != allowedDirectory.standardizedFileURL {
                            gaps.append(frame); continue
                        }
                        items.append(VisibleItem(url: url, frame: frame))
                        if bindings[url] != nil { coverageKnown = false }
                        bindings[url] = .init(wrapper: child, image: image, frame: frame)
                    } catch {
                        if let bounds { gaps.append(bounds) } else { coverageKnown = false }
                    }
                }
            } catch { coverageKnown = false }
            // Full publication alone doesn't make the first/last *visible* item
            // the first/last logical item if any items were offscreen or unreadable.
            let entireSectionVisible = (try? ax.fields(element, AXBatchReader.geometry).frame).flatMap { $0 }.map(viewportFrame.contains) ?? false
            let completeEnds = complete && entireSectionVisible && allPublishedNodesResolved && coverageKnown && gaps.isEmpty
            return VisibleSection(items: items, gaps: gaps, coverageKnown: coverageKnown,
                                  startsAtFirstItem: completeEnds, endsAtLastItem: completeEnds)
        }
        let root = try published(collection)
        var sections = [VisibleSection]()
        var sectionElements = [AXUIElement]()
        var flat = false
        for child in root.children {
            let role = try ax.fields(child, [kAXRoleAttribute]).string(kAXRoleAttribute)
            if role == "AXList" || role == "AXGrid" { sectionElements.append(child) }
            else { flat = true }
        }
        if flat && !sectionElements.isEmpty { throw Failure.unavailable("mixed-section-structure") }
        if sectionElements.isEmpty { sections = [parse(collection)] }
        else { sections = sectionElements.map(parse) }
        let layout = VisibleLayout(sections: sections, viewport: viewportFrame,
                                   coversFullWidth: collectionFrame.minX >= viewportFrame.minX && collectionFrame.maxX <= viewportFrame.maxX)
        return VisibleAXContext(layout: layout, captureMS: (ProcessInfo.processInfo.systemUptime - started) * 1000,
                                usesVisibleChildren: usedVisible, application: app, window: window,
                                collection: collection, viewport: viewport, windowFrame: windowFrame,
                                viewportFrame: viewportFrame, bindings: bindings)
    }
}
