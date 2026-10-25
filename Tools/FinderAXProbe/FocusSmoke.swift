import ApplicationServices
import Foundation

/// Native adapter test scoped to the synthetic folder. No keyboard events.
@main
struct FocusSmoke {
    static func main() throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let folder = root.appendingPathComponent("Tests/Fixtures/Synthetic").resolvingSymlinksInPath().standardizedFileURL
        guard (try? String(contentsOf: folder.appendingPathComponent("Item-001.txt"), encoding: .utf8)) ==
                "FinderWrap synthetic fixture 001\nNo user data.\n", AXIsProcessTrusted() else { exit(2) }
        let allowed = Set([folder.path])
        AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), 0.01)
        let adapter = FinderAccessibility()
        var captured: FinderContext?
        for _ in 0..<3 {
            captured = adapter.capture(allowedDirectories: allowed)
            if captured != nil { break }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        guard let context = captured else { print("capture-unavailable; no-write"); exit(3) }
        func access() -> AXAccess { AXAccess(deadline: ProcessInfo.processInfo.systemUptime + 0.15) }
        // AXSelectedChildren can omit offscreen selections. Require the product's
        // full per-item single-selection check before preparing or restoring.
        guard let originalSelection = adapter.liveSelection(in: context, ax: access()),
              originalSelection.count == 1, let originalID = originalSelection.first,
              let original = context.items.first(where: { $0.model.id == originalID }) else { exit(4) }
        var pair: (BoundItem, BoundItem)?
        for source in context.items where source.model.fullyVisible {
            let snapshot = LayoutSnapshot(generation: context.generation, mode: context.mode, groups: context.groups,
                                          selected: [source.model.id], complete: true)
            if case let .selectTarget(id) = NavigationEngine().decide(snapshot: snapshot, direction: .right),
               let target = context.items.first(where: { $0.model.id == id }) { pair = (source, target); break }
        }
        guard let (source, target) = pair else { print("no-visible-row-boundary; no-write"); exit(5) }
        func same(_ a: [AXUIElement], _ b: [AXUIElement]) -> Bool {
            a.count == b.count && zip(a, b).allSatisfy { CFEqual($0, $1) }
        }
        func scoped() -> Bool {
            let ax = access()
            guard FinderSession.activePID == context.pid,
                  let focused = adapter.focusedIcons(application: context.application, ax: ax),
                  CFEqual(focused.collection, context.collection), CFEqual(focused.window, context.window) else { return false }
            return context.items.allSatisfy { ax.isInside($0.image, directories: allowed) }
        }
        guard scoped(), adapter.liveSelection(in: context, ax: access()) == originalSelection else { exit(6) }
        let prepare = AXUIElementSetAttributeValue(context.collection, kAXSelectedChildrenAttribute as CFString, [source.wrapper] as CFArray)
        var ownsSelection = false
        var restored = false
        var forward = false, backward = false
        if let prepared = access().elements(context.collection, kAXSelectedChildrenAttribute, limit: 2), same(prepared, [source.wrapper]) {
            ownsSelection = prepare == .success
            if prepare == .success, scoped(), adapter.liveSelection(in: context, ax: access()) == [source.model.id] {
                let forwardResult = adapter.commit(target: target, original: source, in: context)
                forward = forwardResult == .committed
                if forwardResult == .indeterminate { ownsSelection = false }
                if forward, scoped(), adapter.liveSelection(in: context, ax: access()) == [target.model.id] {
                    let backwardResult = adapter.commit(target: source, original: target, in: context)
                    backward = backwardResult == .committed
                    if backwardResult == .indeterminate { ownsSelection = false }
                }
            }
        }
        // Restore only a selection that still belongs to this experiment, in the same fixture.
        if ownsSelection, scoped(), let current = adapter.liveSelection(in: context, ax: access()),
           current == [source.model.id] || current == [target.model.id] {
            let result = AXUIElementSetAttributeValue(context.collection, kAXSelectedChildrenAttribute as CFString, [original.wrapper] as CFArray)
            restored = result == .success && adapter.liveSelection(in: context, ax: access()) == originalSelection
        }
        let report: [String: Any] = ["tier": "native-AX-adapter-no-keyboard-events", "fixtureMatched": true,
            "forwardWrapConfirmed": forward, "backwardWrapConfirmed": backward, "originalSelectionRestored": restored,
            "sourceID": source.model.id.rawValue, "targetID": target.model.id.rawValue]
        print(String(data: try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]), encoding: .utf8)!)
        exit(forward && backward && restored ? 0 : 7)
    }
}
