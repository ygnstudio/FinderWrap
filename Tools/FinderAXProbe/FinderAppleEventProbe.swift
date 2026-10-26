import AppKit
import Foundation

/// Scope is checked by a read-only script before the new raw Apple Event reader
/// runs. This executable is separate from the product and never changes selection.
@main
struct FinderAppleEventProbe {
    static func main() {
        var report: [String: Any] = ["schemaVersion": 1, "readOnly": true]
        let reader = FinderSelectionReader()
        report["automationPermissionStatus"] = reader.permissionStatus()
        if reader.permissionStatus() == 0 {
            var error: NSDictionary?
            let scope = NSAppleScript(source: """
                tell application "Finder"
                    if (count of Finder windows) is 0 then return ""
                    return POSIX path of (target of front Finder window as alias)
                end tell
                """)?.executeAndReturnError(&error).stringValue
            let allowed = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("Tests/Fixtures/Synthetic").standardizedFileURL
            let inScope = error == nil && scope.map { URL(fileURLWithPath: $0).standardizedFileURL } == allowed
            report["fixtureWindowConfirmed"] = inScope
            if inScope {
                var samples: [[String: Any]] = []
                for _ in 0..<5 {
                    error = nil
                    let currentScope = NSAppleScript(source: "tell application \"Finder\" to get POSIX path of (target of front Finder window as alias)")?
                        .executeAndReturnError(&error).stringValue
                    guard error == nil,
                          currentScope.map({ URL(fileURLWithPath: $0).standardizedFileURL }) == allowed else {
                        samples.append(["operation": "scope-changed"])
                        break
                    }
                    let start = ProcessInfo.processInfo.systemUptime
                    var sample: [String: Any] = [:]
                    do {
                        switch try reader.read() {
                        case .empty: sample["selectedCount"] = 0
                        case .multiple(let count): sample["selectedCount"] = count
                        case .single(let url):
                            let scoped = url.deletingLastPathComponent().standardizedFileURL == allowed
                            sample["selectionInsideFixture"] = scoped
                            if scoped { sample["selectedCount"] = 1 }
                        }
                    } catch let error as FinderSelectionReader.Failure {
                        sample["errorCode"] = error.code; sample["operation"] = error.operation
                    } catch { sample["operation"] = "unexpected-error" }
                    sample["durationMS"] = (ProcessInfo.processInfo.systemUptime - start) * 1000
                    samples.append(sample)
                }
                report["samples"] = samples
            }
        }
        if let data = try? JSONSerialization.data(withJSONObject: report, options: [.sortedKeys, .prettyPrinted]) {
            FileHandle.standardOutput.write(data)
        }
    }
}
