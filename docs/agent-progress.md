# Codex 阶段进度

日期：2026-10-23 / Asia/Shanghai。任务来源原样保存在 `FinderWrap_Codex_Task.md`；收到的 495 行文本在 7.3 节最后一条结束，没有假定未收到的后续要求。工作目录为本项目，未修改其他项目或中央 Skill 仓。

## 0. 环境检查 — 完成

实际执行 `sw_vers`、`uname -m`、`xcodebuild -version`、`xcode-select -p`、`swift --version`、`xcrun --show-sdk-version`。

macOS 26.6.2 (25G83)、arm64、Finder 26.4；Xcode 27.1 (27A9275)、Swift 6.4、SDK 27.0。没有安装额外依赖。Xcode 报告的旧 iOS CoreSimulator 不影响本次 macOS 目标，未调整该环境。

## 1. 最小工程与 AX 探查 — 本机可行性已证明

创建原生工程、独立只读 probe 和合成数据；覆盖普通图标、列表、分栏、名称排序、日期分组、排列为无、单选/多选、Quick Look 焦点、缩放、1,200 文件/滚动、Finder 重启与桌面区别。

```sh
bash scripts/build.sh Debug
bash scripts/probe.sh --scenario current-state --output docs/evidence/2026-10-23-host-probe.json
bash scripts/probe.sh --scenario large-folder-scroll --output docs/evidence/2026-10-23-large-after-scroll.json
bash scripts/selection-check.sh
```

沙箱内执行上下文看不到可信 AX 状态；正常宿主已有 AX 权限。最初未更改系统权限。先核对集合可写性，再完成实际写入、读回、恢复及恢复读回，四次均成功，之后才实现引擎。详见 `ax-findings.md`。

## 2. 纯 Swift 导航引擎 — 已实现

快照与代际、行聚类、组内/组间边缘关系、首尾不循环、自由排列坐标算法和不确定布局放行独立于 GUI/AX。自由排列算法测试通过不代表运行时模式识别已完成；目前产品放行该模式。

导航单元测试 18 项，包括真实采集的坐标 fixture。多选、重复 ID、异常坐标、重叠、不可见目标和不完整布局均有覆盖。

## 3. 运行时适配、缓存与键盘监听 — 成功路径已实测

在用户明确允许两处脱敏目录的真实键盘测试后，完成原生行内/边界对照，再接入同步 AX 提交与读回、专用 event-tap 线程、后台快照、缓存 epoch/过期及实时上下文核对。

主要工具编译方式：

```sh
xcrun swiftc -swift-version 6 -parse-as-library -target arm64-apple-macos15.0 -module-cache-path build/ModuleCache FinderWrap/Core/*.swift Tools/FinderAXProbe/RuntimeHarness.swift -o build/FinderWrapRuntimeHarness
xcrun swiftc -swift-version 6 -parse-as-library -target arm64-apple-macos15.0 -module-cache-path build/ModuleCache FinderWrap/Core/*.swift Tools/FinderAXProbe/KeySmoke.swift -o build/FinderWrapKeySmoke
```

实际执行受约束的 RuntimeHarness 与 KeySmoke/KeyBurst/QuickLookSmoke，工具不打进应用。单次测试前核对起点，结束停止监听。普通跨行、日期组间、12 次交替跨行、首项边界、上下键、Quick Look 与 36 项多选放行有证据。回调样本最大 34.082 ms；不当作硬实时保证。

尚未完成真实超时/失败故障注入。未知 AX 写入结果可能在原事件放行后造成额外移动，仍是正式发布阻塞，见 `runtime-design.md`。

## 4. SwiftUI 单页 GUI — 内容已验收，安装版菜单栏登记已修复

实现原生启停、权限状态及设置入口、支持范围、复制诊断、退出、显式登录启动。Debug 通过原生 SwiftUI Window 复用同一 View 做 320 pt 布局和缺权限状态检查，Release 不含该预览窗。

发现唯一 MenuBarExtra 被系统隐藏后自动退出；LLDB 确认退出调用来自 AppKit status-item scene action，加入 isInserted 绑定后保持进程存活。随后确认入口仍不可见，没有把进程存活当作修复完成。

用户批准安装/授权后，安装版已在 ~/Applications，辅助功能和输入监控经系统界面读回开启，用户完成 Touch ID。未注册登录项。用户确认看不到图标；ControlCenter 日志明确要求隐藏 FinderWrap。

按用户要求检查登记污染，用户运行只读脚本导出：FinderWrap 的 menuItemLocation 位于 com.openai.codex 的 isAllowed=false 记录下。已准备只删这条关联、先备份再校验的本机修复脚本，保留所有其他设置。用户执行修复并通过读回，Finder 正常启动及带测试参数重启均正常显示；系统设置独立项为开启，用户已打开面板。安装版另行完成 16 次确认写入、12 次交替跨行、上下键、Quick Look 及默认暂停对照，最终保持暂停，见 `menubar-diagnosis.md` 和 `test-report.md`。

## 5. 编译与测试 — 已完成本机范围

```sh
bash scripts/test.sh
bash scripts/build.sh Release
lipo -info build/DerivedData/Build/Products/Release/FinderWrap.app/Contents/MacOS/FinderWrap
otool -l build/DerivedData/Build/Products/Release/FinderWrap.app/Contents/MacOS/FinderWrap
otool -L build/DerivedData/Build/Products/Release/FinderWrap.app/Contents/MacOS/FinderWrap
```

36 项 XCTest 于 19:44:55 全部通过。Release 有 arm64/x86_64，minos 均为 15.0、sdk 27.0，只链接 Apple 框架和 Swift 运行库。沙箱内测试受测试服务限制，正常宿主通过。后续图标/界面文案的 Release 构建成功。

## 6. 跨系统测试 — 缺少环境，未完成

本机以外没有 macOS 15/27 或 Intel 真机。兼容矩阵逐项保留未验证；不把 Universal 架构或 SDK 27 编译当作系统兼容证明。外接屏幕、不同缩放、各种输入法和持续长按也待验证。

## 7. 安装、打包与发布准备 — 本地预览就绪

MIT LICENSE、原创程序生成图标、build/test/package/install/uninstall 脚本和 CI 配置已准备。

```sh
bash scripts/package.sh
bash scripts/install.sh --apply build/Preview/FinderWrap.app "$HOME/Applications/FinderWrap.app"
codesign --verify --strict "$HOME/Applications/FinderWrap.app"
open -n "$HOME/Applications/FinderWrap.app" --args --test-fixtures "$PWD"
```

本地 ZIP 为 ad-hoc 签名并带 SHA-256；没有使用或改变证书，没有公证。安装脚本拒绝覆盖已有应用，卸载脚本默认预览，实际移入废纸篓前必须停用登录并退出。

本地验收阶段的授权包括两个合成目录的真实按键、安装、两项权限及 FinderWrap 菜单栏显示。随后用户明确要求推送独立 GitHub 私有仓库；已建立 [ygnstudio/FinderWrap](https://github.com/ygnstudio/FinderWrap)，托管源码、合成测试和脱敏证据。`build/` 中的本机原始登记、备份、构建及缓存不纳入 Git。远端提交和 CI 状态以仓库及 Actions 为准。

没有开启登录启动，没有进行证书操作、创建 GitHub Release 或公开上传构建。私有源码托管不改变预览版的支持范围和正式发布门槛。

下一步：完成事务故障测试及可用系统环境的回归后，再讨论正式签名和公开发布。安装版核心验收已完成；末行不满时保留 Finder 原生的向右上方邻近项移动，已做启用/暂停对照，不把它写成末项保持不动。


## 2026-10-25 · 1.0.2 窗口焦点兼容修复候选

用户明确要求直接修复 macOS 15.8.1 不生效。已移除产品对主窗口的依赖，统一实际图标焦点/所属窗口确认，缺失可选属性需正向交叉验证，扩充内置诊断。旧判断的回归测试先失败，修复后 58 项 XCTest 与 5 项签名策略测试通过；本机 Synthetic 原生选择往返与恢复通过。Universal 2 构建并复用原固定证书生成 DMG/ZIP。本地验收未替换安装版；随后用户授权推送代码和 CI，Release 与 Homebrew 仍保持 1.0.1。macOS 15 反馈机效果仍待确认。见 [1.0.2 记录](release-1.0.2.md)。

## 2026-10-26 · 1.0.2 公开发布

用户明确授权发布。已将提交 `774e0a2` 的固定签名 CI 附件发布为 `v1.0.2` 最新正式版，公开附件下载读回与 CI 一致。Homebrew 仓库提交 `709f8ec` 将 FinderWrap 更新至 `1.0.2,5`，DMG SHA-256 与公开资产一致。证书身份沿用 1.0.1；本轮未安装或替换本机应用，未改变权限。macOS 15.8.1 反馈机效果与固定签名升级后的权限保留仍待确认。
