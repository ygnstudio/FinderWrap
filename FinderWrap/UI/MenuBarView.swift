import SwiftUI
import ServiceManagement

struct MenuBarView: View {
    @ObservedObject var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("FinderWrap").font(.headline)
                Spacer()
                Text("预览版").font(.caption).foregroundStyle(.secondary)
            }
            Toggle("左右键自动换行", isOn: Binding(get: { state.enabled }, set: state.setEnabled))
                .toggleStyle(.switch)
                .disabled(!state.permissions.ready)
            Label(statusTitle, systemImage: state.status.running ? "checkmark.circle" : "pause.circle")
                .font(.callout)
                .foregroundStyle(state.status.running ? Color.primary : Color.secondary)
                .accessibilityElement(children: .combine)
            Text(statusDetail)
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Divider()
            permissionRow("辅助功能", granted: state.permissions.accessibility, action: PermissionService.openAccessibilitySettings)
            permissionRow("输入监控", granted: state.permissions.inputMonitoring, action: PermissionService.openInputSettings)
            if !state.permissions.ready {
                Text("在系统设置中允许 FinderWrap 访问，再返回启用。应用不会自动申请或更改权限。")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Divider()
            Toggle("登录时启动", isOn: Binding(get: { state.loginEnabled }, set: state.setLoginEnabled))
                .toggleStyle(.checkbox).disabled(state.loginBusy || state.testMode)
            if state.loginNeedsApproval {
                Button("在系统设置中批准登录项") { SMAppService.openSystemSettingsLoginItems() }
                    .controlSize(.small)
            }
            if let error = state.loginError {
                Text(error).font(.caption).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
            }
            DisclosureGroup("支持范围") {
                Text("支持已确认布局中的左右跨行与日期分组切换。自由排列、Quick Look、超过 160 项或布局不完整时保留原生行为。")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 4)
            }
            .font(.caption)
            if state.testMode {
                Text("测试模式：仅操作已授权的脱敏目录。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Divider()
            HStack {
                Button(state.copiedDiagnostics ? "已复制诊断信息" : "复制诊断信息", action: state.copyDiagnostics)
                Spacer()
                Button("退出", action: state.quit)
            }
            .controlSize(.small)
        }
        .padding(16)
        .frame(width: 320)
        .onAppear { state.refresh(); state.copiedDiagnostics = false }
    }

    private var statusTitle: String {
        if !state.permissions.ready { return "需要系统权限" }
        if state.status.running { return state.status.cacheReady ? "正在运行" : "等待 Finder 图标视图" }
        return state.enabled ? "正在启动" : "已暂停"
    }

    private var statusDetail: String {
        if state.status.indeterminate > 0 { return "上次选择结果无法确认，监听已暂停。可复制诊断信息后重新启用。" }
        if let failure = state.status.failure { return failure }
        if state.status.running { return "行内移动、上下键与组合键保持原有行为。" }
        return "开启后，在行末按 → 进入下一行，行首按 ← 返回上一行。"
    }

    private func permissionRow(_ title: String, granted: Bool, action: @escaping @MainActor () -> Void) -> some View {
        HStack {
            Text(title)
            Spacer()
            if granted { Label("已允许", systemImage: "checkmark").foregroundStyle(.secondary) }
            else { Button("打开设置", action: action).controlSize(.small) }
        }
        .font(.caption)
    }
}
