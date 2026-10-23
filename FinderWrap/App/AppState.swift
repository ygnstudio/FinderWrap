import AppKit
import Combine
import Foundation

@MainActor
final class AppState: ObservableObject {
    @Published private(set) var enabled = false
    @Published private(set) var permissions = PermissionService.read()
    @Published private(set) var status = MonitorStatus()
    @Published private(set) var loginEnabled = LaunchAtLoginService.enabled
    @Published private(set) var loginNeedsApproval = LaunchAtLoginService.needsApproval
    @Published private(set) var loginBusy = false
    @Published var loginError: String?
    @Published var copiedDiagnostics = false
    let testMode: Bool
    private let testDirectories: Set<String>?
    private var monitor: KeyboardMonitor
    private var timer: Timer?

    init() {
        let args = ProcessInfo.processInfo.arguments
        if let index = args.firstIndex(of: "--test-fixtures"), index + 1 < args.count {
            let root = URL(fileURLWithPath: args[index + 1])
            let directories = Set(["Tests/Fixtures/Synthetic", "build/Fixtures/Large"].map {
                root.appendingPathComponent($0).resolvingSymlinksInPath().standardizedFileURL.path
            })
            testDirectories = directories
            testMode = true
            monitor = KeyboardMonitor(allowedDirectories: directories)
        } else {
            testDirectories = nil
            testMode = false
            monitor = KeyboardMonitor()
        }
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refresh() }
        }
        if !testMode && UserDefaults.standard.bool(forKey: "navigationEnabled") && permissions.ready {
            setEnabled(true)
        }
    }

    func setEnabled(_ value: Bool) {
        permissions = PermissionService.read()
        if value && !permissions.ready { enabled = false; return }
        monitor.stop()
        enabled = value
        if !testMode { UserDefaults.standard.set(value, forKey: "navigationEnabled") }
        if value {
            monitor = KeyboardMonitor(allowedDirectories: testDirectories)
            monitor.start()
        }
        refresh()
    }

    func refresh() {
        permissions = PermissionService.read()
        if enabled && !permissions.ready { setEnabled(false); return }
        status = monitor.status
        if enabled && status.failure != nil {
            enabled = false
            monitor.stop()
            if !testMode { UserDefaults.standard.set(false, forKey: "navigationEnabled") }
        }
        loginEnabled = LaunchAtLoginService.enabled
        loginNeedsApproval = LaunchAtLoginService.needsApproval
    }

    func setLoginEnabled(_ value: Bool) {
        guard !loginBusy else { return }
        loginBusy = true; loginError = nil
        Task {
            defer { loginBusy = false; refresh() }
            do { try await LaunchAtLoginService.setEnabled(value) }
            catch { loginError = "未能更新登录启动。请将应用安装到“应用程序”后重试。" }
        }
    }

    func copyDiagnostics() {
        DiagnosticService.copy(DiagnosticService.summary(status: status, permissions: permissions))
        copiedDiagnostics = true
    }

    func quit() { monitor.stop(); NSApplication.shared.terminate(nil) }
}
