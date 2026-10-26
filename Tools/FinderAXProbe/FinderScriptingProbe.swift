import AppKit
import CoreServices
import Foundation

/// Read-only route evaluation. Requests consent only with --request-consent;
/// never changes Finder selection or files.
/// Data is inspected in memory only inside the existing synthetic fixture.
@main
struct FinderScriptingProbe {
    static func main() {
        let request = Array(CommandLine.arguments.dropFirst()) == ["--request-consent"]
        guard CommandLine.arguments.count == 1 || request else { exit(2) }
        var report: [String: Any] = ["schemaVersion": 2, "readOnly": true, "consentRequested": request]
        let target = NSAppleEventDescriptor(bundleIdentifier: "com.apple.finder")
        let permission = AEDeterminePermissionToAutomateTarget(target.aeDesc, typeWildCard, typeWildCard, request)
        report["automationPermissionStatus"] = permission
        if permission == noErr {
            var error: NSDictionary?
            let script = NSAppleScript(source: """
                tell application "Finder"
                    if (count of Finder windows) is 0 then return ""
                    return POSIX path of (target of front Finder window as alias)
                end tell
                """)
            let result = script?.executeAndReturnError(&error)
            let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("Tests/Fixtures/Synthetic").resolvingSymlinksInPath().standardizedFileURL
            let path = result?.stringValue.map { URL(fileURLWithPath: $0).resolvingSymlinksInPath().standardizedFileURL }
            report["fixtureWindowConfirmed"] = error == nil && path == root
            if error == nil && path == root {
                let literal = root.path.replacingOccurrences(of: "\\", with: "\\\\")
                    .replacingOccurrences(of: "\"", with: "\\\"") + "/"
                let started = ProcessInfo.processInfo.systemUptime
                let selectionScript = NSAppleScript(source: """
                    tell application "Finder"
                        if (POSIX path of (target of front Finder window as alias)) is not "\(literal)" then error number -128
                        set chosen to selection
                        set resultURLs to {}
                        repeat with chosenItem in chosen
                            set end of resultURLs to URL of chosenItem
                        end repeat
                        return resultURLs
                    end tell
                    """)
                let selected = selectionScript?.executeAndReturnError(&error)
                report["selectionReadMS"] = (ProcessInfo.processInfo.systemUptime - started) * 1000
                if error == nil, let selected {
                    let urls = (1...max(1, selected.numberOfItems)).prefix(selected.numberOfItems).compactMap {
                        selected.atIndex($0)?.stringValue.flatMap(URL.init(string:))
                    }
                    let scoped = urls.count == selected.numberOfItems && urls.allSatisfy {
                        $0.isFileURL && $0.deletingLastPathComponent().resolvingSymlinksInPath().standardizedFileURL == root
                    }
                    report["selectionInsideFixture"] = scoped
                    if scoped { report["selectedCount"] = urls.count }
                }
                let layoutScript = NSAppleScript(source: """
                    tell application "Finder"
                        if (POSIX path of (target of front Finder window as alias)) is not "\(literal)" then error number -128
                        set sourceFolder to target of front Finder window
                        set shownView to current view of front Finder window
                        set sourceItems to items of sourceFolder
                        if (count sourceItems) > 200 then error number -128
                        set itemPositions to {}
                        repeat with sourceItem in sourceItems
                            try
                                set end of itemPositions to position of sourceItem
                            on error
                                set end of itemPositions to {}
                            end try
                        end repeat
                        return {shownView, itemPositions}
                    end tell
                    """)
                let layoutStart = ProcessInfo.processInfo.systemUptime
                let layout = layoutScript?.executeAndReturnError(&error)
                report["layoutReadMS"] = (ProcessInfo.processInfo.systemUptime - layoutStart) * 1000
                if error == nil, let layout, let positions = layout.atIndex(2) {
                    report["viewCode"] = String(format: "0x%08x", layout.atIndex(1)?.enumCodeValue ?? 0)
                    var unique = Set<String>(), usable = 0
                    for index in 1...max(1, positions.numberOfItems) where index <= positions.numberOfItems {
                        guard let point = positions.atIndex(index), point.numberOfItems == 2,
                              let x = point.atIndex(1)?.int32Value, let y = point.atIndex(2)?.int32Value,
                              x >= 0, y >= 0 else { continue }
                        usable += 1; unique.insert("\(x),\(y)")
                    }
                    report["itemCount"] = positions.numberOfItems
                    report["usablePositions"] = usable
                    report["distinctPositions"] = unique.count
                }
            }
            if let error { report["scriptErrorCode"] = error[NSAppleScript.errorNumber] }
        }
        if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
            FileHandle.standardOutput.write(data)
        }
    }
}
