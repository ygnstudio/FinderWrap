# 菜单栏登记异常诊断

2026-10-23，本机 macOS 26.6.2。FinderWrap 本地预览已安装并开启辅助功能/输入监控，但菜单栏图标不可见，系统设置“菜单栏”列表也没有 FinderWrap。用户已确认不是自动化工具漏读。

## 已确认的原因

用户在自己的终端运行只读脚本 `scripts/diagnose-menubar.py`，成功读取受保护的 ControlCenter 登记。与 FinderWrap 匹配的记录只有一条，以下仅提取本问题所需字段：

```json
{
  "ownerBundleID": "com.openai.codex",
  "isAllowed": false,
  "affectedMenuItemBundleID": "dev.finderwrap.finderwrap",
  "otherAssociationsPreserved": 4
}
```

FinderWrap 的菜单项归到了 Codex 的隐藏登记下。控制中心日志同时出现 `Starting to track blocked host` 和 `Requesting updated blocked host to not be visible`，主机标识明确含 FinderWrap 的 bundle ID。LaunchServices 则正确识别 FinderWrap 的 bundle、安装路径及独立进程；改为 Finder 双击启动仍被旧登记阻挡。

这证明菜单栏关联错误，不证明整个菜单栏数据库普遍损坏，也不证明是哪次启动写入了关联。不能靠开启其他应用的显示开关冒充修复 FinderWrap。

## 排查过程与代码处理

初版无 `isInserted` 绑定时，系统移除唯一菜单项会导致 SwiftUI 自动退出。LLDB 的 `-[NSApplication terminate:]` 调用栈来自 AppKit 的 status-item scene action；不是导航崩溃。加入显式 `isInserted` 状态后，进程可保持运行，但这并没有解除 ControlCenter 的隐藏登记。

Apple 的 [MenuBarExtra 初始化器说明](https://developer.apple.com/documentation/swiftui/menubarextra/init(content:label:))解释了唯一菜单项移除后的退出行为。[Apple Developer Forums 的同类开发者报告](https://developer.apple.com/forums/tags/macos?page=3&sortBy=newest&sortOrder=DESC)也描述过 foreign trackedApplications 关联导致隐藏；该报告仅用于形成排查方向，本机结论来自实际导出的记录和系统日志。

本次没有改写系统菜单栏的私有默认值来强制显示，也没有给产品加入 NSStatusItem 或私有 API。

## 最小修复方案

`scripts/repair-menubar-association.py` 是本机诊断维护工具，不进入应用或安装包。默认 dry run，`--apply` 才执行：

1. 要求 FinderWrap 已退出；核对当前用户拥有的实际登记文件，不接受符号链接。
2. 要求 `com.openai.codex` 的 `isAllowed=false` 记录中恰好有一条 FinderWrap 关联，否则拒绝修改。
3. 在忽略提交的 `build/menubar-backups/` 创建权限为 0600 的完整备份。
4. 只移除该记录内 FinderWrap 的 menuItemLocation，保留 Codex 的隐藏开关和其他关联。
5. 用系统 defaults 服务写入，读回核对，要求其他偏好值没有变化。

由于 macOS 拒绝 Codex 进程访问这一受保护文件，用户在已有访问能力的终端执行；没有扩大 Codex 的磁盘权限。用户此前对 FinderWrap 安装和菜单栏显示的授权仍有效。

修复脚本的变换逻辑已用实际导出的匹配记录及 JSON/plist 编码往返验证。用户于 20:19:14 执行后获得 Verified 读回：只删除目标关联，其他偏好值完全一致。20:19:40 从 Finder 启动后，控制中心从 blocked host 变为 Adding displayable items；20:20:34 带测试目录参数重启仍正常显示。系统设置新增独立 FinderWrap 开启项，原 Codex/ChatGPT 隐藏开关保持关闭。用户确认已看到并打开面板。原生自动化工具无法绑定该菜单浮层，因此面板开关由用户操作。后续导航已由受约束测试工具核对：16 次确认跨行，最大回调 23.65 ms，无不确定写入；最终默认暂停的原生对照也已通过。原始登记、完整备份和本机路径仅保留在忽略提交的 build/，不作为公开证据上传。
