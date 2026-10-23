import ApplicationServices
import Foundation

@main
struct LayoutCheck {
    static func main() throws {
        AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), 0.03)
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let roots = Set(["Tests/Fixtures/Synthetic", "build/Fixtures/Large"].map {
            root.appendingPathComponent($0).resolvingSymlinksInPath().standardizedFileURL.path
        })
        guard let context = FinderAccessibility().capture(allowedDirectories: roots, diagnostic: { print($0) }) else { exit(2) }
        let ax = AXAccess(deadline: ProcessInfo.processInfo.systemUptime + 0.15)
        guard let selected = FinderAccessibility().liveSelection(in: context, ax: ax) else { exit(3) }
        let snapshot = LayoutSnapshot(generation: context.generation, mode: context.mode, groups: context.groups, selected: selected, complete: true)
        print("mode", context.mode, "viewport", context.viewportFrame, "selection", selected)
        print("left", NavigationEngine().decide(snapshot: snapshot, direction: .left))
        print("right", NavigationEngine().decide(snapshot: snapshot, direction: .right))
        for item in context.items { print(item.model.id.rawValue, item.model.frame, item.model.fullyVisible) }
    }
}
