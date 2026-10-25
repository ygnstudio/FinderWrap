# macOS 15.7.4：section-0 读取失败调查

2026-10-26 初始调查。用户转交 FinderWrap 1.0.1 / macOS 15.7.4 (24G517) 的失败诊断。初始调查轮次只增加只读检测工具、测试和记录；没有修改应用行为、版本、签名或安装状态，没有提交、推送或发布新版本。实际拒绝的子条件仍待反馈机采样。随后用户明确要求直接修改并发布 1.0.3，已补上可选分组信息兼容及内置诊断；见 [1.0.3 记录](release-1.0.3.md)。以下保留初始证据，不将新增兼容分支视为已确定的反馈机根因。

## 证据与边界

诊断中 Accessibility、Input monitoring、Running 均为 true；Horizontal key events=42，flags=0xa00100、Fn=false；Cache ready=false、Last decision=no-fresh-cache，三种写入计数均为 0。Capture / Last Finder capture 均停在 `section-0; budgetExpired=false`。原文部分 `0` 写作 `O`，按阶段命名和数值格式解读，不据此推断其他数据。

`capture` 已经通过窗口、图标焦点、所属窗口、视口几何、集合子节点及选择属性可写性检查。第一个 section 的读取未形成可用快照，所以按键处理没有新鲜缓存，未进入选中项写入。这支持继续检查布局采集；不支持重置授权或归因于写入失败自动暂停。事件计数是全局左右键计数，并不证明 42 次都发生在 Finder。

1.0.1 的发布源码提交 `39def2a` 与 1.0.2 的 `774e0a2` 相比，section 循环及 `AXAccess.elements` 的拒绝条件未改。1.0.2 修复窗口焦点识别，并保留部分 AX 属性读取错误；**不能据此声称此次 section 层问题已解决**。只有反馈机仍在运行 1.0.1 是已知事实；不能把旧版本本身当作本次根因。

## `section-0` 的全部直接退出分支

| 分支 | 具体可能性 | 检测结果 |
|---|---|---|
| 读取 subrole 失败 | 属性不可用、失效元素、单次通信失败等 | `section-subrole-read-failed` 加 AXError |
| subrole 类型不符 | 成功返回但不是字符串 | `section-subrole-not-string` |
| subrole 值不符 | 不是预期 `AXSectionList` | `section-subrole-mismatch` 加脱敏角色 |
| 子节点计数失败或非法 | 数组属性不可读、负数等 | `section-count-read-failed` / `section-count-invalid` |
| 子节点数量超限 | 单 section 超过 164 个包装/标题节点 | `section-count-over-limit` 加数量 |
| 分页读取失败 | AXError，或成功但不是数组 | `section-page-read-failed` / `section-page-not-array` |
| 分页内容异常 | 空页、超过剩余数量、非 AX 元素、重复元素 | `section-page-empty` / `page-too-large` / `child-not-element` / `duplicate-child` |
| 读后计数变化或不可读 | Finder 布局变化、读后 API 错误 | `section-count-changed` / `section-count-recheck-failed` |
| 总预算耗尽 | 本次执行遇到 150 ms 采集预算 | 原日志 false 不支持该次由总预算耗尽直接拒绝；不能排除 10 ms 单次 AX 超时 |
| 空 section | 子节点数组为空，尚未进入 item 循环 | `section-empty` |

产品全局项目上限 160 与单 section 的 164 个子节点上限是两项不同限制。161–164 个普通文件可能进入 item 阶段后被拒绝，不能简单说“超过 160 一定输出 section-0”。collection 超过 24 个子节点会更早停在 `collection-sections`，也不是本次已知阶段。

已有本机 AX 记录来自 macOS 26.6.2，不能证明 macOS 15.7.4 返回相同层级。未采到反馈机实际 subrole/count/error 前，不接受任意容器、不扩大数量或超时、不延长缓存寿命。

## 发给反馈用户的只读检测

工具为 `scripts/diagnose-finder-sections.command`，只需 macOS 自带 bash / osascript，不需要 Xcode、Homebrew 或 Python。

1. 在终端输入 `bash `（末尾有空格），把收到的脚本拖进去，按回车。
2. 五秒内切回出现故障的 Finder 图标区域，保持原窗口、视图和文件数量，等待约 12 秒。
3. 把终端中的完整 JSON 发回。不需要按方向键或重置 FinderWrap 权限。

若 `probeAccessibility=false` 或状态为 `probe-accessibility-unavailable-no-permission-requested`，直接返回结果即可。这只说明终端探针自身没有读取权限，不代表 FinderWrap 丢失授权；工具不会弹出授权申请。

工具不发送按键、不修改选中项、不切换应用、不读文件名/路径/窗口标题/输入文字。输出只包括系统/Finder 版本、公开 AX 角色、白名单视图标识、数量、错误码和耗时。两次 10 ms 与两次 50 ms 单次调用作只读对照；这只改变探针自己的超时。每次采样 1.2 秒软预算，分页最多 20 个引用，collection 最多 24 个子节点，每个 section 最多 164 个子节点，发现前台变化即停止。

它只检查 section 前置条件；不检查文件包装内部结构、几何、全局 160 项限制或实际换行。`section-gates-pass-items-not-tested` 不等于故障已解决；采样时焦点变化、预算耗尽或没有 Finder 前台时需重新采样。1.2 秒探针预算也不能证明产品的 150 ms 采集预算足够。

## 本轮验证

- `bash -n scripts/diagnose-finder-sections.command`：通过。
- `python3 -m unittest discover -s Tests -p 'test_section_probe.py' -v`：12 项通过，覆盖分页、每类拒绝、边界、焦点/预算变化及脱敏正反对照；无真实 AX 或键盘输入。
- 沙箱中执行完整脚本：正确返回探针无权限分支，没有申请权限。
- 正常宿主的原生桥接检查：Finder 的子节点计数、分页、CF 引用转换、AX 元素类型与角色读取通过。只读取后台 Finder 的窗口/菜单栏节点，没有完整前台 section 采样，也没有导航验证。
- macOS 15.7.4 反馈机：尚未取得脚本结果；根因和修复效果未确认。

后续依据具体错误码、角色和数量选择最小修复，并以对应失败结构建立回归测试；不同超时的结果只作为通信失败线索，不直接用增大超时替代诊断。
