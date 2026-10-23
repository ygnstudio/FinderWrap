import ApplicationServices
import Foundation

/// User-authorized system input test. Never used by the application or the probe.
@main
struct KeySmoke {
    static func main() throws {
        guard (2...3).contains(CommandLine.arguments.count), let code = UInt16(CommandLine.arguments[1]),
              [123, 124, 125, 126, 49].contains(code), AXIsProcessTrusted(), CGPreflightPostEventAccess() else { exit(2) }
        AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), 0.01)
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let roots = Set(["Tests/Fixtures/Synthetic", "build/Fixtures/Large"].map {
            root.appendingPathComponent($0).resolvingSymlinksInPath().standardizedFileURL.path
        })
        FileHandle.standardError.write(Data((FinderSession.diagnostic + "\n").utf8))
        var captured: FinderContext?
        for _ in 0..<3 {
            captured = FinderAccessibility().capture(allowedDirectories: roots, diagnostic: { reason in
                FileHandle.standardError.write(Data((reason + "\n").utf8))
            })
            if captured != nil { break }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        guard let context = captured,
              FinderSession.activePID == context.pid,
              let source = CGEventSource(stateID: .hidSystemState),
              let down = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: false) else { exit(3) }
        let beforeAX = AXAccess(deadline: ProcessInfo.processInfo.systemUptime + 0.15)
        let before = context.items.enumerated().compactMap { index, item -> Int? in
            beforeAX.read(item.image, kAXSelectedAttribute) as? Bool == true ? index : nil
        }
        if CommandLine.arguments.count == 3 {
            guard let expected = Int(CommandLine.arguments[2]), before == [expected] else {
                FileHandle.standardError.write(Data("unexpected-start-selection; no-event-posted\n".utf8)); exit(6)
            }
        }
        down.flags = []; up.flags = []
        down.setIntegerValueField(.eventSourceUserData, value: 0x4657524150)
        up.setIntegerValueField(.eventSourceUserData, value: 0x4657524150)
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        let ax = AXAccess(deadline: ProcessInfo.processInfo.systemUptime + 0.15)
        let selected = ax.elements(context.collection, kAXSelectedChildrenAttribute, limit: 160) ?? []
        let frames = selected.compactMap(ax.frame).map { ["x": $0.minX, "y": $0.minY] }
        let after = context.items.enumerated().compactMap { index, item -> Int? in
            ax.read(item.image, kAXSelectedAttribute) as? Bool == true ? index : nil
        }
        let report: [String: Any] = ["keyCode": code, "selectedFramesAfter": frames,
                                   "selectionCountAfter": selected.count, "selectedIndicesBefore": before, "selectedIndicesAfter": after]
        let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data("\n".utf8))
    }
}
