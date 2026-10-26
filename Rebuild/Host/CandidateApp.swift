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
            Self.applyStoredAppearance()
            self.refresh()
            if UserDefaults.standard.bool(forKey: "navigationEnabled"), self.permissionsReady {
                self.enabled = self.setEnabled(true)
            }
        }
    }

    var permissionsReady: Bool { accessibility && inputMonitoring }

    /// Localized runtime message; recomputed on every body evaluation so a
    /// language switch applies immediately.
    var message: String {
        let l = L10n.current
        if let launchIssue { return launchIssue }
        switch status.state {
        case .paused:
            return l.t("已暂停", "Paused")
        case .starting:
            return l.t("正在准备图标布局", "Preparing the Finder layout")
        case .ready:
            let detail = l.t("\(status.rowCount) 行 · \(status.itemCount) 个图标",
                             "\(status.rowCount) rows · \(status.itemCount) icons")
            if status.quickLook {
                return l.t("Quick Look：", "Quick Look: ") + detail
            }
            return l.t("已就绪：", "Ready: ") + detail
        case .native:
            switch status.reason {
            case "not-icon-view":
                return l.t("当前不是可换行的图标视图", "No wrappable icon grid in this view")
            case "finder-not-active":
                return l.t("Finder 不在前台", "Finder is not frontmost")
            default:
                return l.t("当前场景保持原生操作", "Keeping native behaviour in this view")
            }
        case .recovering:
            return l.t("读取暂时失败，正在重新检查", "Temporary read failure, retrying")
        case .permissionRequired:
            return l.t("等待系统权限", "Waiting for system permissions")
        case .listenerUnavailable:
            return l.t("监听不可用，请暂停后重新启用", "Listener unavailable; pause and re-enable")
        }
    }

    @discardableResult
    func setEnabled(_ value: Bool) -> Bool {
        launchIssue = nil
        if value, NSRunningApplication.runningApplications(withBundleIdentifier: "dev.finderwrap.finderwrap")
            .contains(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }) {
            enabled = false
            launchIssue = L10n.current.t(
                "另一个 FinderWrap 正在运行。请先退出它，避免两个版本同时处理按键。",
                "Another FinderWrap is already running. Quit it first so two versions do not handle keys at once.")
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
        NSPasteboard.general.setString(monitor.diagnostics(chinese: L10n.current.chinese), forType: .string)
        copied = true
    }

    func quit() {
        monitor.stop()
        NSApplication.shared.terminate(nil)
    }

    /// AppKit-level appearance so the menu-bar panel (and its context menus)
    /// follow the stored choice immediately, not only after a relaunch.
    static func applyStoredAppearance() {
        let raw = UserDefaults.standard.string(forKey: AppAppearance.storageKey) ?? AppAppearance.system.rawValue
        switch AppAppearance.resolved(raw) {
        case .system:
            NSApplication.shared.appearance = nil
        case .light:
            NSApplication.shared.appearance = NSAppearance(named: .aqua)
        case .dark:
            NSApplication.shared.appearance = NSAppearance(named: .darkAqua)
        }
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
    @AppStorage(AppLanguage.storageKey) private var languageRaw = AppLanguage.system.rawValue
    @AppStorage(AppAppearance.storageKey) private var appearanceRaw = AppAppearance.system.rawValue

    private var l10n: L10n { L10n(chinese: AppLanguage.resolved(languageRaw).isChinese) }
    private var colorScheme: ColorScheme? {
        guard let forcedDark = AppAppearance.resolved(appearanceRaw).forcedDark else { return nil }
        return forcedDark ? .dark : .light
    }

    var body: some View {
        let l = l10n
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.turn.down.right").font(.title3)
                VStack(alignment: .leading, spacing: 1) {
                    Text("FinderWrap").font(.headline)
                    Text("1.0.7").font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
            }
            Toggle(l.t("左右键自动换行", "Wrap left/right arrows"),
                   isOn: Binding(get: { state.enabled }, set: { _ = state.setEnabled($0) }))
                .toggleStyle(.switch)
                .disabled(!state.enabled && !state.permissionsReady)
            Text(state.message).font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Divider()
            permissionRow(l.t("辅助功能", "Accessibility"), allowed: state.accessibility) {
                state.settings("Privacy_Accessibility")
            }
            permissionRow(l.t("输入监控", "Input Monitoring"), allowed: state.inputMonitoring) {
                state.settings("Privacy_ListenEvent")
            }
            Divider()
            Toggle(l.t("列表左右键切项", "List: left/right steps"),
                   isOn: Binding(get: { state.listWrap }, set: { state.setListWrap($0) }))
                .toggleStyle(.switch)
            Toggle(l.t("画廊到头循环", "Gallery: cycle at ends"),
                   isOn: Binding(get: { state.galleryCycle }, set: { state.setGalleryCycle($0) }))
                .toggleStyle(.switch)
            Divider()
            optionRow(l.t("语言", "Language"), selection: $languageRaw) {
                Text(l.t("跟随系统", "System")).tag(AppLanguage.system.rawValue)
                Text("中文").tag(AppLanguage.chinese.rawValue)
                Text("English").tag(AppLanguage.english.rawValue)
            }
            optionRow(l.t("外观", "Appearance"), selection: $appearanceRaw) {
                Text(l.t("跟随系统", "System")).tag(AppAppearance.system.rawValue)
                Text(l.t("浅色", "Light")).tag(AppAppearance.light.rawValue)
                Text(l.t("深色", "Dark")).tag(AppAppearance.dark.rawValue)
            }
            Divider()
            HStack {
                Button(state.copied ? l.t("已复制", "Copied") : l.t("复制诊断信息", "Copy diagnostics"),
                       action: state.copyDiagnostics)
                Spacer()
                Button(l.t("退出", "Quit"), action: state.quit)
            }
        }
        .font(.callout)
        .padding(14)
        .frame(width: 320)
        .preferredColorScheme(colorScheme)
        .onChange(of: appearanceRaw) { _ in CandidateAppState.applyStoredAppearance() }
    }

    private func permissionRow(_ title: String, allowed: Bool, action: @escaping () -> Void) -> some View {
        HStack {
            Text(title)
            Spacer()
            if allowed {
                Label(l10n.t("已允许", "Allowed"), systemImage: "checkmark.circle.fill")
                    .labelStyle(.titleAndIcon)
                    .foregroundStyle(.green)
            } else {
                Button(l10n.t("前往授权", "Grant"), action: action).controlSize(.small)
            }
        }
        .font(.caption)
    }

    private func optionRow<Content: View>(_ title: String, selection: Binding<String>,
                                          @ViewBuilder content: () -> Content) -> some View {
        HStack {
            Text(title)
            Spacer()
            Picker("", selection: selection) { content() }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(width: 130)
        }
        .font(.caption)
    }
}
