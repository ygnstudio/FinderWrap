import ApplicationServices
import Foundation

/// Explicitly authorized, bounded stress test. Not linked into the app or read-only probe.
@main
struct KeyBurst {
    static func main() throws {
        guard AXIsProcessTrusted(), CGPreflightPostEventAccess() else {
            FileHandle.standardError.write(Data("missing-test-host-permission\n".utf8)); exit(2)
        }
        AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), 0.03)
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let roots = Set(["Tests/Fixtures/Synthetic", "build/Fixtures/Large"].map {
            root.appendingPathComponent($0).resolvingSymlinksInPath().standardizedFileURL.path
        })
        var steps: [[String: Any]] = []
        let started = ProcessInfo.processInfo.systemUptime
        for index in 0..<12 {
            var captured: FinderContext?
            for _ in 0..<3 {
                captured = FinderAccessibility().capture(allowedDirectories: roots, diagnostic: { reason in
                    if reason != "ready" { FileHandle.standardError.write(Data((reason + "\n").utf8)) }
                })
                if captured != nil { break }
                RunLoop.current.run(until: Date().addingTimeInterval(0.03))
            }
            guard let context = captured,
                  FinderSession.activePID == context.pid,
                  let source = CGEventSource(stateID: .hidSystemState) else { exit(3) }
            let code: CGKeyCode = index.isMultiple(of: 2) ? 123 : 124
            guard let down = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: true),
                  let up = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: false) else { exit(4) }
            down.flags = []; up.flags = []
            down.setIntegerValueField(.eventSourceUserData, value: 0x4657524150)
            up.setIntegerValueField(.eventSourceUserData, value: 0x4657524150)
            let posted = ProcessInfo.processInfo.systemUptime
            down.post(tap: .cghidEventTap); up.post(tap: .cghidEventTap)
            RunLoop.current.run(until: Date().addingTimeInterval(0.07))
            let ax = AXAccess(deadline: ProcessInfo.processInfo.systemUptime + 0.05)
            let selected = ax.elements(context.collection, kAXSelectedChildrenAttribute, limit: 2) ?? []
            steps.append(["index": index, "keyCode": code, "postedMS": (posted - started) * 1000,
                          "selectionCount": selected.count,
                          "frames": selected.compactMap(ax.frame).map { ["x": $0.minX, "y": $0.minY] }])
        }
        let data = try JSONSerialization.data(withJSONObject: ["steps": steps], options: [.prettyPrinted, .sortedKeys])
        FileHandle.standardOutput.write(data)
    }
}
