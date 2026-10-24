# 系统兼容矩阵

截至 2026-10-24。编译、启动、GUI、AX 和完整核心验收分别记录，不把 SDK 版本当作运行环境。

| 系统 / 架构 | 编译 | 应用启动 | GUI | Finder AX | 核心导航 |
|---|---|---|---|---|---|
| macOS 15 arm64 | macos-15 CI / Xcode 16.4 构建及测试通过（0.1.0 提交 c3f1e40） | 未验证 | 未验证 | 未验证 | 未验证 |
| macOS 15 x86_64 | 有 minos 15.0 的产物 | 未验证 | 未验证 | 未验证 | 未验证 |
| macOS 26.6.2 arm64 | 本机 Debug/Release 成功 | Debug/安装版均执行 | 单页预览已查；登记已修复，用户确认面板权限/测试模式 | 多场景探查、选择写入读回通过 | 测试宿主与安装版跨行/日期组/短连按及放行场景已验；1.0.0 适配层故障模拟已完成，真实系统故障矩阵未完成 |
| macOS 26 x86_64 | Universal 2 含该架构 | 未验证 | 未验证 | 未验证 | 未验证 |
| macOS 27 arm64 / x86_64 | 使用 SDK 27.0 构建 | 未验证 | 未验证 | 未验证 | 未验证 |

本机：macOS 26.6.2 (25G83)、Finder 26.4、arm64；Xcode 27.1 (27A9275)、Swift 6.4、SDK 27.0。没有声称 macOS 27 正式兼容，也没有把 x86_64 编译通过称为 Intel 真机验证。

GUI 为 SwiftUI `MenuBarExtra` 和 `.window` 样式，Debug 验收用同一 View 的原生 SwiftUI Window。没有 NSStatusItem、NSMenu、NSPopover、自定义 NSWindow 或 NSViewRepresentable。AppKit 限于公开前台应用查询、打开系统设置、复制诊断和退出。

自由排列、大型目录、屏外目标和 Quick Look 的自定义跨行暂不支持；这些场景保留系统行为。跨屏幕、运行中 Finder 重启、各种输入法和物理修饰键仍待实机回归。

1.0.0 本机新增 44 项 XCTest 与 Universal Release 构建；远端 CI 的旧提交结果不作为本次未推送改动的 CI 结果。完整新版本证据见 release-1.0.0.md。
