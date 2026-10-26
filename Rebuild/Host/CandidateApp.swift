import AppKit
import ApplicationServices
import CoreServices
import SwiftUI

@MainActor
final class CandidateAppState: ObservableObject {
    @Published var enabled = false
    @Published var status = CandidateMonitor.Status()
    @Published var accessibility = AXIsProcessTrusted()
    @Published var inputMonitoring = CGPreflightListenEventAccess()
    @Published var automation = FinderSelectionReader().permissionStatus() == 0
    @Published var copied = false
    @Published var launchIssue: String?
    let directory: URL?
    private let invalidArguments: Bool
    private var monitor: CandidateMonitor?
    private var timer: Timer?

    init() {
        let args = ProcessInfo.processInfo.arguments
        if let index = args.firstIndex(of: "--synthetic-directory"), index + 1 < args.count {
            let url = URL(fileURLWithPath: args[index + 1]).resolvingSymlinksInPath().standardizedFileURL
            directory = url.path.hasSuffix("/Tests/Fixtures/Synthetic") && FileManager.default.fileExists(atPath: url.path) ? url : nil
            invalidArguments = directory == nil
        } else { directory = nil; invalidArguments = args.contains("--synthetic-directory") }
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refresh() }
        }
    }

    var permissionsReady: Bool { accessibility && inputMonitoring && automation }
    var message: String {
        if let launchIssue { return launchIssue }
        guard !invalidArguments else { return "测试目录参数无效，请重新正常打开应用" }
        switch status.state {
        case .paused: return "已暂停"
        case .preparing: return "正在准备 Finder 布局"
        case .ready: return "Finder 布局已就绪"
        case .native: return "当前场景保持 Finder 原生操作"
        case .recovering: return "读取暂时失败，正在重新检查"
        case .permissionRequired: return "等待系统权限"
        case .listenerUnavailable: return "监听不可用，请暂停后重新启用"
        case .uncertainCommit: return "选择结果未确认，请核对后暂停并重新启用"
        }
    }

    func setEnabled(_ value: Bool) {
        refresh()
        monitor?.stop(); monitor = nil
        launchIssue = nil
        if value, NSRunningApplication.runningApplications(withBundleIdentifier: "dev.finderwrap.finderwrap")
            .contains(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }) {
            enabled = false; status = CandidateMonitor.Status()
            launchIssue = "另一个 FinderWrap 正在运行。请先退出它，避免两个版本同时处理按键。"
            return
        }
        enabled = value && permissionsReady && !invalidArguments
        if enabled {
            let candidate = CandidateMonitor(syntheticDirectory: directory)
            monitor = candidate; candidate.start()
        } else { status = CandidateMonitor.Status() }
        // No legacy navigationEnabled preference, login item, or installed app
        // configuration is read or modified by the candidate.
    }
    func refresh() {
        accessibility = AXIsProcessTrusted(); inputMonitoring = CGPreflightListenEventAccess()
        automation = FinderSelectionReader().permissionStatus() == 0
        if let monitor { monitor.updatePermissions(ready: permissionsReady); status = monitor.status }
    }
    func requestFinderPermission() {
        let target = NSAppleEventDescriptor(bundleIdentifier: "com.apple.finder")
        _ = AEDeterminePermissionToAutomateTarget(target.aeDesc, typeWildCard, typeWildCard, true)
        refresh()
    }
    func settings(_ suffix: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?" + suffix) { NSWorkspace.shared.open(url) }
    }
    func copyDiagnostics() {
        let text = """
        FinderWrap 2.0.0 Preview 1 (200002)
        \(ProcessInfo.processInfo.operatingSystemVersionString)
        Accessibility: \(accessibility)
        Input monitoring: \(inputMonitoring)
        Finder automation: \(automation)
        Requested enabled: \(enabled)
        Runtime state: \(status.state)
        Reason: \(status.reason)
        Confirmed: \(status.confirmed)
        Uncertain: \(status.uncertain)
        Maximum callback ms: \(String(format: "%.2f", status.maximumCallbackMS))
        Last layout capture ms: \(String(format: "%.2f", status.captureMS))
        Notification registrations: \(status.registeredNotifications)
        Test directory only: \(directory != nil)
        No filenames, paths, selected text or keyboard contents included.
        """
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string); copied = true
    }
    func quit() { monitor?.stop(); NSApplication.shared.terminate(nil) }
}

@main
struct FinderWrapCandidateApp: App {
    @StateObject private var state = CandidateAppState()
    var body: some Scene {
        WindowGroup("FinderWrap", id: "main") {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Image(systemName: "arrow.turn.down.right").font(.largeTitle)
                    VStack(alignment: .leading) {
                        Text("FinderWrap").font(.title2.bold())
                        Text("2.0.0 · 预览版 1").foregroundStyle(.secondary)
                    }
                }
                Toggle("左右键自动换行", isOn: Binding(get: { state.enabled }, set: state.setEnabled))
                    .toggleStyle(.switch).disabled(!state.enabled && !state.permissionsReady)
                Text(state.message).font(.callout).fixedSize(horizontal: false, vertical: true)
                Divider()
                permissionRow("辅助功能", allowed: state.accessibility) { state.settings("Privacy_Accessibility") }
                permissionRow("输入监控", allowed: state.inputMonitoring) { state.settings("Privacy_ListenEvent") }
                permissionRow("自动化 Finder", allowed: state.automation, action: state.requestFinderPermission)
                Text("支持普通文件夹图标视图中可确认的可见跨行。Quick Look、桌面和屏外目标暂时保持原生操作。预览版仍在验证兼容性。")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button(state.copied ? "已复制" : "复制诊断信息", action: state.copyDiagnostics)
                    Spacer()
                    Button("退出", action: state.quit)
                }
            }
            .padding(24).frame(width: 400)
        }
        .windowResizability(.contentSize)
        MenuBarExtra("FinderWrap", systemImage: "arrow.turn.down.right") {
            CandidateStatusMenu(state: state)
        }
    }

    private func permissionRow(_ title: String, allowed: Bool, action: @escaping () -> Void) -> some View {
        HStack {
            Text(title); Spacer()
            if allowed { Label("已允许", systemImage: "checkmark.circle.fill").foregroundStyle(.green) }
            else { Button("前往授权", action: action) }
        }.font(.callout)
    }
}

private struct CandidateStatusMenu: View {
    @ObservedObject var state: CandidateAppState
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Text(state.message)
        Toggle("左右键自动换行", isOn: Binding(get: { state.enabled }, set: state.setEnabled))
            .disabled(!state.enabled && !state.permissionsReady)
        Button("打开 FinderWrap") {
            openWindow(id: "main")
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
        Divider()
        Button("退出", action: state.quit)
    }
}
