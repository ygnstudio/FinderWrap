import Foundation

/// Temporary event-tap test host. Only generated fixtures can be modified.
@main
struct RuntimeHarness {
    static func main() throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let roots = ["Tests/Fixtures/Synthetic", "build/Fixtures/Large"].map {
            root.appendingPathComponent($0).resolvingSymlinksInPath().standardizedFileURL.path
        }
        guard (try? String(contentsOf: root.appendingPathComponent("Tests/Fixtures/Synthetic/Item-001.txt"), encoding: .utf8)) ==
                "FinderWrap synthetic fixture 001\nNo user data.\n" else { exit(2) }
        let monitor = KeyboardMonitor(allowedDirectories: Set(roots))
        monitor.start()
        let statusURL = root.appendingPathComponent("build/runtime-status.json")
        let started = ProcessInfo.processInfo.systemUptime
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        while ProcessInfo.processInfo.systemUptime - started < 120 {
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
            try encoder.encode(monitor.status).write(to: statusURL, options: .atomic)
        }
        monitor.stop()
        try encoder.encode(monitor.status).write(to: statusURL, options: .atomic)
    }
}
