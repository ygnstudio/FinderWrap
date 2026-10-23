import AppKit
import ApplicationServices

struct PermissionStatus {
    let accessibility: Bool
    let inputMonitoring: Bool
    var ready: Bool { accessibility && inputMonitoring }
}

enum PermissionService {
    static func read() -> PermissionStatus {
        PermissionStatus(accessibility: AXIsProcessTrusted(), inputMonitoring: CGPreflightListenEventAccess())
    }

    @MainActor static func openAccessibilitySettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    }
    @MainActor static func openInputSettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")
    }
    @MainActor private static func open(_ path: String) {
        guard let url = URL(string: path) else { return }
        NSWorkspace.shared.open(url)
    }
}
