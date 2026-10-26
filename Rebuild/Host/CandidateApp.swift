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
    @Published var shiftWrap = (UserDefaults.standard.object(forKey: "shiftWrapEnabled") as? Bool) ?? true
    private let monitor = FinderWrapMonitor()
    private var timer: Timer?

    init() {
        monitor.setListWrap(listWrap)
        monitor.setGalleryCycle(galleryCycle)
        monitor.setShiftWrap(shiftWrap)
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

    /// Colour for the compact state dot next to the master toggle.
    var statusTint: Color {
        if launchIssue != nil { return .red }
        if !permissionsReady { return .orange }
        switch status.state {
        case .ready:
            return enabled ? .green : Color(nsColor: .secondaryLabelColor)
        case .starting, .recovering, .permissionRequired, .listenerUnavailable:
            return .orange
        case .paused, .native:
            return Color(nsColor: .secondaryLabelColor)
        }
    }

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
                return l.t("已生效 · Quick Look：", "Active · Quick Look: ") + detail
            }
            return l.t("已生效：", "Active: ") + detail
        case .native:
            switch status.reason {
            case "not-icon-view":
                return l.t("已开启 · 当前视图保持原生", "On · native in this view")
            case "finder-not-active":
                return l.t("已开启 · Finder 不在前台", "On · Finder is not frontmost")
            default:
                return l.t("已开启 · 当前场景保持原生", "On · native behaviour")
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

    func setShiftWrap(_ value: Bool) {
        shiftWrap = value
        UserDefaults.standard.set(value, forKey: "shiftWrapEnabled")
        monitor.setShiftWrap(value)
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
        VStack(alignment: .leading, spacing: 16) {
            header(l)
            Divider()
            mainControl(l)
            section(l.t("权限", "Permissions")) {
                permissionRow(l.t("辅助功能", "Accessibility"), icon: "hand.raised",
                              allowed: state.accessibility) {
                    state.settings("Privacy_Accessibility")
                }
                permissionRow(l.t("输入监控", "Input Monitoring"), icon: "keyboard",
                              allowed: state.inputMonitoring) {
                    state.settings("Privacy_ListenEvent")
                }
            }
            section(l.t("视图", "Views")) {
                toggleRow(l.t("列表左右键切项", "List: left/right steps"),
                          icon: "list.bullet.rectangle",
                          isOn: Binding(get: { state.listWrap }, set: { state.setListWrap($0) }),
                          help: l.t("左右键在列表视图里切换上一项/下一项；到首尾不循环，也不会展开或折叠文件夹。",
                                    "Left/right steps through list rows. It stops at the first and last row and never expands or collapses folders."))
                toggleRow(l.t("画廊到头循环", "Gallery: cycle at ends"),
                          icon: "rectangle.on.rectangle",
                          isOn: Binding(get: { state.galleryCycle }, set: { state.setGalleryCycle($0) }),
                          help: l.t("画廊视图里从第一张继续左键会回到最后一张，从最后一张继续右键会回到第一张。",
                                    "In Gallery view, left at the first item wraps to the last; right at the last item wraps to the first."))
                toggleRow(l.t("Shift 跨行扩选", "Shift: extend across rows"),
                          icon: "shift",
                          isOn: Binding(get: { state.shiftWrap }, set: { state.setShiftWrap($0) }),
                          help: l.t("按住 Shift 扩选时，到行尾/行首继续跨到相邻行；关闭后保持 Finder 原生，到行尾就停住。",
                                    "Hold Shift and extend across row boundaries; when off, Finder keeps its native behaviour and stops at the row edge."))
            }
            section(l.t("界面", "Interface")) {
                optionRow(l.t("语言", "Language"), icon: "globe", selection: $languageRaw) {
                    Text(l.t("跟随系统", "System")).tag(AppLanguage.system.rawValue)
                    Text("中文").tag(AppLanguage.chinese.rawValue)
                    Text("English").tag(AppLanguage.english.rawValue)
                }
                optionRow(l.t("外观", "Appearance"), icon: "circle.lefthalf.filled", selection: $appearanceRaw) {
                    Text(l.t("跟随系统", "System")).tag(AppAppearance.system.rawValue)
                    Text(l.t("浅色", "Light")).tag(AppAppearance.light.rawValue)
                    Text(l.t("深色", "Dark")).tag(AppAppearance.dark.rawValue)
                }
            }
            Divider()
            footer(l)
        }
        .padding(16)
        .frame(width: 336)
        .preferredColorScheme(colorScheme)
        .onChange(of: appearanceRaw) { _ in CandidateAppState.applyStoredAppearance() }
    }

    private func header(_ l: L10n) -> some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.accentColor.opacity(0.14))
                .frame(width: 30, height: 30)
                .overlay {
                    Image(systemName: "arrow.turn.down.right")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.tint)
                }
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("FinderWrap").font(.system(size: 13, weight: .semibold))
                Text("1.0.11").font(.caption2).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
    }

    private func mainControl(_ l: L10n) -> some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: "arrow.left.arrow.right")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(width: 16)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(l.t("左右键自动换行", "Wrap left/right arrows"))
                    .font(.system(size: 13, weight: .medium))
                statusLine(l)
            }
            Spacer(minLength: 8)
            Toggle("", isOn: Binding(get: { state.enabled }, set: { _ = state.setEnabled($0) }))
                .toggleStyle(.switch)
                .labelsHidden()
                .disabled(!state.enabled && !state.permissionsReady)
                .accessibilityLabel(l.t("左右键自动换行", "Wrap left/right arrows"))
                .help(l.t("开启后，左右键在图标视图的行尾会换到下一行；关闭时完全保持 Finder 原生行为。",
                          "When on, arrow keys wrap at row ends in icon views. When off, Finder keeps its native behaviour."))
        }
    }

    private func statusLine(_ l: L10n) -> some View {
        HStack(spacing: 5) {
            Circle().fill(state.statusTint).frame(width: 5, height: 5)
                .accessibilityHidden(true)
            Text(state.message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            content()
        }
    }

    private func permissionRow(_ title: String, icon: String, allowed: Bool,
                               action: @escaping () -> Void) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(width: 16)
                .accessibilityHidden(true)
            Text(title)
            Spacer(minLength: 8)
            if allowed {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill").font(.system(size: 11))
                    Text(l10n.t("已允许", "Allowed")).font(.caption)
                }
                .foregroundStyle(.green)
                .accessibilityElement(children: .combine)
            } else {
                Button(action: action) {
                    HStack(spacing: 3) {
                        Text(l10n.t("前往授权", "Grant"))
                        Image(systemName: "arrow.up.right").font(.system(size: 9, weight: .semibold))
                    }
                }
                .buttonStyle(.borderless)
                .font(.caption)
                .foregroundStyle(.orange)
                .help(l10n.t("打开系统设置里对应的权限页面。授权后回到这里即可开启换行。",
                             "Opens the matching System Settings privacy pane. Come back here to turn wrapping on."))
            }
        }
        .font(.callout)
        .frame(minHeight: 22)
    }

    private func toggleRow(_ title: String, icon: String, isOn: Binding<Bool>, help: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(width: 16)
                .accessibilityHidden(true)
            Text(title).font(.callout)
            Spacer(minLength: 8)
            Toggle("", isOn: isOn)
                .toggleStyle(.switch)
                .labelsHidden()
                .accessibilityLabel(Text(title))
                .help(help)
        }
        .frame(minHeight: 22)
    }

    private func optionRow<Content: View>(_ title: String, icon: String, selection: Binding<String>,
                                          @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(width: 16)
                .accessibilityHidden(true)
            Text(title).font(.callout)
            Spacer(minLength: 8)
            Picker("", selection: selection) { content() }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(width: 124)
                .accessibilityLabel(Text(title))
        }
        .frame(minHeight: 24)
    }

    private func footer(_ l: L10n) -> some View {
        HStack {
            Button(action: state.copyDiagnostics) {
                Label(state.copied ? l.t("已复制", "Copied") : l.t("复制诊断信息", "Copy diagnostics"),
                      systemImage: state.copied ? "checkmark" : "doc.on.doc")
                    .font(.caption)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            Spacer()
            Button(l.t("退出", "Quit"), action: state.quit)
                .buttonStyle(.bordered)
                .controlSize(.small)
                .keyboardShortcut("q", modifiers: .command)
        }
    }
}
