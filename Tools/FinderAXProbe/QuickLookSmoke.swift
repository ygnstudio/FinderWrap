import ApplicationServices
import Foundation

/// Approved test sequence only: Space, Right, Left, Space in the two synthetic roots.
@main
struct QuickLookSmoke {
    static func main() throws {
        guard AXIsProcessTrusted(), CGPreflightPostEventAccess() else { exit(2) }
        AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), 0.03)
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let roots = Set(["Tests/Fixtures/Synthetic", "build/Fixtures/Large"].map {
            root.appendingPathComponent($0).resolvingSymlinksInPath().standardizedFileURL.path
        })
        var captured: FinderContext?
        for _ in 0..<3 {
            captured = FinderAccessibility().capture(allowedDirectories: roots)
            if captured != nil { break }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        guard let context = captured else { exit(3) }
        func scoped() -> Bool {
            let ax = AXAccess(deadline: ProcessInfo.processInfo.systemUptime + 0.15)
            guard FinderSession.activePID == context.pid,
                  let main = ax.element(context.application, kAXMainWindowAttribute), CFEqual(main, context.window) else { return false }
            return context.items.allSatisfy { ax.isInside($0.image, directories: roots) }
        }
        func send(_ code: CGKeyCode) -> Bool {
            guard scoped(), let source = CGEventSource(stateID: .hidSystemState),
                  let down = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: true),
                  let up = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: false) else { return false }
            // Match hardware navigation-key metadata; an empty flag set hid a regression.
            down.flags = code == 49 ? [] : [.maskNumericPad, .maskSecondaryFn]
            up.flags = down.flags
            down.post(tap: .cghidEventTap); up.post(tap: .cghidEventTap)
            RunLoop.current.run(until: Date().addingTimeInterval(0.35))
            return true
        }
        guard send(49) else { exit(4) }
        let ax = AXAccess(deadline: ProcessInfo.processInfo.systemUptime + 0.15)
        guard let preview = ax.element(context.application, kAXFocusedWindowAttribute), !CFEqual(preview, context.window) else { exit(5) }
        var steps: [[String: Any]] = []
        for code: CGKeyCode in [124, 123, 49] {
            let check = AXAccess(deadline: ProcessInfo.processInfo.systemUptime + 0.15)
            guard let focus = check.element(context.application, kAXFocusedWindowAttribute), CFEqual(focus, preview), send(code) else { exit(6) }
            let readback = AXAccess(deadline: ProcessInfo.processInfo.systemUptime + 0.15)
            let selected = context.items.enumerated().compactMap { index, item -> Int? in
                readback.read(item.image, kAXSelectedAttribute) as? Bool == true ? index : nil
            }
            let focused = readback.element(context.application, kAXFocusedWindowAttribute)
            steps.append(["keyCode": code, "selectedIndices": selected,
                          "finderWindowFocused": focused.map { CFEqual($0, context.window) } ?? false])
        }
        let data = try JSONSerialization.data(withJSONObject: ["previewFocusVerified": true, "steps": steps], options: [.prettyPrinted, .sortedKeys])
        FileHandle.standardOutput.write(data)
    }
}
