import AppKit
import Foundation

enum DiagnosticService {
    static func summary(status: MonitorStatus, permissions: PermissionStatus) -> String {
        """
        FinderWrap \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "development")
        \(ProcessInfo.processInfo.operatingSystemVersionString)
        Accessibility: \(permissions.accessibility)
        Input monitoring: \(permissions.inputMonitoring)
        Running: \(status.running)
        Cache ready: \(status.cacheReady)
        Capture: \(status.captureDiagnostic)
        Last Finder capture: \(status.lastFinderCapture)
        Horizontal key events: \(status.arrowEvents)
        Last horizontal key flags: 0x\(String(status.lastArrowFlags, radix: 16))
        Fn key down on last horizontal key: \(status.lastArrowFnDown)
        Last decision: \(status.lastDecision)
        Confirmed wraps: \(status.committed)
        Unchanged writes: \(status.unchanged)
        Indeterminate writes: \(status.indeterminate)
        Maximum callback (ms): \(String(format: "%.2f", status.maximumCallbackMS))
        No filenames, paths, selected text or keyboard contents included.
        """
    }

    @MainActor static func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
