import AppKit
import ApplicationServices
import SwiftUI

@MainActor
final class CandidateAppState: ObservableObject {
    @Published var enabled = false
    @Published var status = FinderWrapMonitor.Status()
    @Published var accessibility = AXIsProcessTrusted()
    @Published var inputMonitoring = CGPreflightListenEventAccess()
    @Published var copied = false
    @Published var launchIssue: String?
    @Published var listWrap = UserDefaults.standard.bool(forKey: "listWrapEnabled")
    @Published var galleryCycle = (UserDefaults.standard.object(forKey: "galleryCycleEnabled") as? Bool) ?? true
    private let monitor = FinderWrapMonitor()
    private var timer: Timer?

    init() {
        monitor.setListWrap(listWrap)
        monitor.setGalleryCycle(galleryCycle)
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refresh() }
        }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.refresh()
            if UserDefaults.standard.bool(forKey: "navigationEnabled"), self.permissionsReady {
                self.enabled = self.setEnabled(true)
            }
        }
    }

    var permissionsReady: Bool { accessibility && inputMonitoring }

    var message: String {
        if let launchIssue { return launchIssue }
        switch status.state {
        case .paused: return "已暂停"
        case .starting: return "正在准备图标布局"
        case .ready: return status.message
        case .native: return status.message
        case .recovering: return "读取暂时失败，正在重新检查"
        case .permissionRequired: return "等待系统权限"
        case .listenerUnavailable: return "监听不可用，请暂停后重新启用"
        }
    }

    @discardableResult
    func setEnabled(_ value: Bool) -> Bool {
        launchIssue = nil
        if value, NSRunningApplication.runningApplications(withBundleIdentifier: "dev.finderwrap.finderwrap")
            .contains(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }) {
            enabled = false
            launchIssue = "另一个 FinderWrap 正在运行。请先退出它，避免两个版本同时处理按键。"
            return false
        }
        let started = monitor.setEnabled(value)
        enabled = value && started
        UserDefaults.standard.set(enabled, forKey: "navigationEnabled")
        refresh()
        return enabled
    }

    func refresh() {
        accessibility = AXIsProcessTrusted()
        inputMonitoring = CGPreflightListenEventAccess()
        status = monitor.status
        if enabled && !permissionsReady { _ = setEnabled(false) }
    }

    func setListWrap(_ value: Bool) {
        listWrap = value
        UserDefaults.standard.set(value, forKey: "listWrapEnabled")
        monitor.setListWrap(value)
    }

    func setGalleryCycle(_ value: Bool) {
        galleryCycle = value
        UserDefaults.standard.set(value, forKey: "galleryCycleEnabled")
        monitor.setGalleryCycle(value)
    }

    func settings(_ suffix: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?" + suffix) {
            NSWorkspace.shared.open(url)
        }
    }

    func copyDiagnostics() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(monitor.diagnostics(), forType: .string)
        copied = true
    }

    func quit() {
        monitor.stop()
        NSApplication.shared.terminate(nil)
    }
}

@main
struct FinderWrapCandidateApp: App {
    @StateObject private var state = CandidateAppState()

    var body: some Scene {
        MenuBarExtra {
            CandidateMenuPanel(state: state)
        } label: {
            Image(systemName: "arrow.turn.down.right")
        }
        .menuBarExtraStyle(.window)
    }
}

/// Everything lives in the menu bar panel; the app has no ordinary window.
private struct CandidateMenuPanel: View {
    @ObservedObject var state: CandidateAppState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.turn.down.right").font(.title3)
                VStack(alignment: .leading, spacing: 1) {
                    Text("FinderWrap").font(.headline)
                    Text("1.0.6").font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
            }
            Toggle("左右键自动换行", isOn: Binding(get: { state.enabled }, set: { _ = state.setEnabled($0) }))
                .toggleStyle(.switch)
                .disabled(!state.enabled && !state.permissionsReady)
            Text(state.message).font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Divider()
            permissionRow("辅助功能", allowed: state.accessibility) { state.settings("Privacy_Accessibility") }
            permissionRow("输入监控", allowed: state.inputMonitoring) { state.settings("Privacy_ListenEvent") }
            Divider()
            Toggle("列表左右键切项", isOn: Binding(get: { state.listWrap }, set: { state.setListWrap($0) }))
                .toggleStyle(.switch)
            Toggle("画廊到头循环", isOn: Binding(get: { state.galleryCycle }, set: { state.setGalleryCycle($0) }))
                .toggleStyle(.switch)
            Divider()
            HStack {
                Button(state.copied ? "已复制" : "复制诊断信息", action: state.copyDiagnostics)
                Spacer()
                Button("退出", action: state.quit)
            }
        }
        .font(.callout)
        .padding(14)
        .frame(width: 300)
    }

    private func permissionRow(_ title: String, allowed: Bool, action: @escaping () -> Void) -> some View {
        HStack {
            Text(title)
            Spacer()
            if allowed {
                Label("已允许", systemImage: "checkmark.circle.fill")
                    .labelStyle(.titleAndIcon)
                    .foregroundStyle(.green)
            } else {
                Button("前往授权", action: action).controlSize(.small)
            }
        }
        .font(.caption)
    }
}
