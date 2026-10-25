# macOS 15.8.1 不生效：窗口识别层调查

2026-10-25 初始调查记录。随后用户要求直接修复，已准备 [1.0.2 修复候选](release-1.0.2.md)，改为验证实际焦点和所属窗口，并细分内置诊断。本文以下保留 1.0.1 调查时的证据和边界；反馈机器的具体子条件及新版效果仍待确认。

## 现有证据

用户提供 FinderWrap 1.0.1 / macOS 15.8.1 (24H32) 的诊断：两项权限为 true、Running=true、Horizontal key events=26、flags=0xa00100、Fn=false、Last decision=no-fresh-cache、Last Finder capture=focused-standard-window; budgetExpired=false、三种写入计数均为 0、Maximum callback=0.00。

源码 `FinderWrap/Core/FinderAccessibility.swift` 的 `capture` 先取得主窗口，再在同一个 guard 检查：

1. 能读到 `AXFocusedWindow`；
2. 主窗口与焦点窗口 `CFEqual`；
3. 主窗口 subrole 为 `AXStandardWindow`。

三项中任一失败都会输出同一个 `focused-standard-window`。因此现在只能确认最近一次记录的 Finder 采集未通过窗口守卫，不能判定是哪一项，也不能据此判定所有 macOS 15 都不兼容。

## 全链路核对

| 环节 | 已确认 | 仍不能推断 |
|---|---|---|
| 授权与监听 | 反馈诊断两项 true，监听 running | 不支持把问题归为升级丢失授权 |
| 按键进入 | 26 次左右键事件；当前标记通过 1.0.1 的过滤规则 | 计数包含其他前台应用的左右键，不能声称 26 次都发生在 Finder |
| 前台会话 | `Last Finder capture` 至少记录过 Finder 前台采集 | 复制时的 inactive 可能来自打开面板或切换应用；不是权限失效证明 |
| 主窗口与焦点 | 最近记录停在三项窗口守卫之一 | 未区分读取失败、窗口不一致、subrole 差异 |
| 单次 AX 请求 | 原版每次请求超时 10 ms | `budgetExpired=false` 不排除单次超时或属性不可用 |
| 普通图标视图 | 后续还需 `AXList / AXCollectionList / IconView`、正确 owner 和 scroll parent | 此次记录尚未进入这层，不能把它归为排序设置错误 |
| 桌面、列表、分栏、预览、文本焦点 | 现行策略要求特定图标焦点；不满足时保留原生行为 | 当前用户究竟处于哪种界面未知；不能自动给非标准窗口放行 |
| section、分组与项目 | 现行限制 24 组、160 项、已观察到的 section/header/image 结构 | 此次记录尚未进入，文件数量或组结构不是已证实原因 |
| 缓存 | 没有新鲜上下文时直接放行；350 ms 过期保护正常 | 不能通过延长缓存寿命修复未成功采集 |
| 几何与导航 | 现有测试覆盖行内、首尾、多选、重叠、屏外、分组、重复/无效数据 | 未取得这台 macOS 15 的几何；不能声称已实机验证 |
| 写入与自动暂停 | 三种写入计数都是 0 | 不支持把本次归为写入失败或不确定写入自动暂停 |
| 耗时 | 计时起点位于成功获取缓存之后 | 0.00 不表示监听没收到按键或实际耗时为零 |
| 签名与升级 | 现有 5 项固定签名/禁止降级测试通过 | 本轮没有构建分发包、替换安装版或更换证书 |

## 只读采样工具

文件：`scripts/diagnose-finder-window.command`。只使用 macOS 内置 bash、osascript 和公开 AX API，不依赖 Xcode、Homebrew 或 Python。

1. 将脚本发送给反馈用户。
2. 用户打开终端，输入 `bash `（末尾有空格），将脚本拖进终端，然后按回车。这是一次命令，不需要猜下载目录。
3. 五秒内回到出现故障的 Finder 界面，保持原来的窗口/视图状态，等待约十秒。不要为了采样先切换视图或关闭预览。
4. 将输出的完整 JSON 发回。若 JSON 显示没有采到 Finder 前台，重新运行并保持 Finder 前台即可。

工具不发送按键，不写选中项，不激活其他应用，不申请权限，不读取窗口标题、文件名、文件 URL 或输入文本。只记录操作系统/Finder 版本、AX 错误码、角色/白名单标识、引用相等关系与子节点数量。结构快照限定 100 个节点、7 层、每层最多 24 个子节点、1.5 秒软预算；截断会明确标记，不冒充完整布局。

前三次采样用原版 10 ms 单次请求超时，后三次用 50 ms 作只读对照；仅修改探针自身的请求超时，不修改 FinderWrap 或系统设置。它检查窗口和焦点条件，并保留有界角色结构以区分不同视图；不执行完整几何算法或导航写入。

如果返回 `probe-accessibility-unavailable-no-permission-requested`，说明终端探针自身没有读取权限，**不代表 FinderWrap 失去权限**。先返回这段输出，无需重置 FinderWrap 的授权。Apple 的 [AXIsProcessTrusted 文档](https://developer.apple.com/documentation/applicationservices/1460720-axisprocesstrusted) 明确该查询针对当前进程。

## 本轮验证

- `bash scripts/test.sh`：48 项 XCTest 通过，0 失败。
- `python3 -m unittest discover -s Tests -p 'test_*.py' -v`：5 项签名策略测试通过。
- 脚本语法、未授权分支、JXA 的 CF 引用转换及非白名单字符串脱敏已检查。
- macOS 26.6.2 脱敏 Synthetic 图标视图：6 次采样中首次主窗口读取失败，随后 5 次窗口/焦点守卫通过；角色结构成功采集并明确报告截断。仅证明探针在本机工作，不是 macOS 15 或导航写入验收。
- 未向对方机器执行任何操作；未改应用代码、权限或安装状态，未推送或发布。

## 收到结果后的判定

- `focused-window-unavailable`：根据 AXError 区分不可用/通信失败；用两档超时与重复采样判断是否稳定。
- `main-focused-window-mismatch`：结合两个窗口的角色和焦点结构判断预览/弹窗/不同窗口，不删除安全校验。
- `main-window-subrole-not-standard`：依据该系统真实返回的角色和 owner 关系研究兼容；不直接接受任意窗口。
- `focus-*-not-*`：根据实际焦点、父节点和结构确认当前界面，防止把侧边栏、列表、分栏或编辑焦点当成图标区。
- 初始守卫均通过：说明采样时未复现原阻塞；继续对齐失败时刻与应用布局采集，不宣布已修复。

在取得 macOS 15 的实际返回值前，保留窗口/焦点守卫、缓存寿命和签名身份。
