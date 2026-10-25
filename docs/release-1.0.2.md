# FinderWrap 1.0.2 · 窗口焦点兼容修复候选

2026-10-25，build 5。固定签名 Universal 2 修复候选；本记录对应本地验收，GitHub Release 和 Homebrew 尚未更新。macOS 15.8.1 的反馈机器仍待升级确认，不声称本轮已完成该系统实机验收。

## 问题与修复

1.0.1 把 `AXMainWindow` 作为键盘导航的窗口，并同时要求它等于 `AXFocusedWindow`、具有 `AXStandardWindow` 子类型。任何一项失败都无法产生布局缓存。用户报告停在这一层；该报告没有记录具体失败项，不能断定对方机器究竟是哪一种。

已确认的实现缺陷是：即使真实焦点、IconView 和所属窗口关系一致，主窗口属性读取失败、不同的主窗口或可选窗口子类型缺失仍会让有效焦点被拒绝。此前本机只读样本确实出现 `AXMainWindow` 返回 cannotComplete，而焦点窗口、IconView 和所属窗口均正常。Apple 的[窗口状态说明](https://developer.apple.com/design/human-interface-guidelines/windows)区分 main 和接收键盘输入的 key window；本机 SDK `AXAttributeConstants.h` 也明确 `AXSubrole` 不是每个元素必需的属性。

新逻辑从当前 `AXFocusedUIElement` 定位经过明确签名验证的 IconView，再取得它的所属窗口：

- 不再依赖 `AXMainWindow`，要求窗口基本类型为 `AXWindow`。
- `AXFocusedWindow` 可读时必须与所属窗口一致；若明确返回 attributeUnsupported/noValue，必须再由系统级 `AXFocusedUIElement` 确认同一个图标区。超时、类型错误和明确不一致都拒绝。
- 窗口子类型允许 Standard/Unknown，以及明确的 attributeUnsupported/noValue；显式对话框、浮动窗口和读取失败继续拒绝。
- 仍要求图标区为 `AXList / AXCollectionList / IconView`，父节点是滚动区。没有给任意列表、文本输入框、桌面或 Quick Look 开放导航。
- 写入前的实时校验使用同一套焦点确认，并增加所属窗口复核，避免采集通过、按键时又被旧规则拒绝。
- 诊断区分焦点、窗口、子类型及所属关系的失败，保留 AX 读取错误；增加按下最后一次左右键时的采集状态，减少打开面板后状态变化造成的误判。

缓存有效期、AX 时间预算、选择写入/读回保护和证书身份均未放宽。

## 回归证据

新增 `Tests/FinderFocusTests.swift`，通过注入 AX 返回值测试真实产品 resolver，不将模拟属性差异标记为 macOS 15 的已观察行为。

- 红灯：先只抽取旧判断并接入可注入 AX 边界，新增用例实际运行失败；58 项测试出现 8 个失败断言。原始日志保存在 `build/logs/focus-regression-red.log`。
- 绿灯：新逻辑下 58 项 XCTest 全部通过；包括原有 48 项与新增 10 项。日志 `build/logs/focus-regression-green.log`。
- 5 项签名策略测试通过。
- Release 成功构建 arm64 与 x86_64。
- macOS 26.6.2 原生适配层测试只操作 Synthetic：动态找到可见行边界，正向/反向选择均读回确认，并恢复测试前选择。没有投递键盘事件，也没有替换运行中的应用。
- 两个产品调用点（采集、实时选择复核）使用统一焦点关系判断。工具中的旧主窗口约束用于实验范围保护，未推广为产品导航条件；只读历史诊断脚本仍明确检查 1.0.1 规则。
- 推送审查另加强 FocusSmoke 的完整单选保护，避免集合列表漏掉屏外选择。四种纯 stub 控制流检查通过，旧守卫实际失败两种；不将其计为原生 AX 验收，前述原生结果来自保护加强前。

本轮没有 macOS 15、Intel 或物理键盘安装版复测；原生 AX 往返成功不替代这些验证。

## 安装包与签名

- `FinderWrap-1.0.2-b5-fixed-universal.dmg`
- `FinderWrap-1.0.2-b5-fixed-universal.zip`
- 同名 `.sha256` 和 `.signing.json`

本地文件位于 `build/packages/`；main 的固定签名 CI 另行生成候选安装包。复用此前的 FinderWrap 专用证书，不创建新证书，不降级为 ad-hoc。临时导入钥匙串在打包后删除，原搜索列表恢复。

新旧固定签名包的 bundle identifier、叶证书 SHA-256 和两架构 designated requirement 完全一致；ZIP 中的实际应用通过严格验签，DMG 完整性与文件哈希通过。仍没有苹果公证。身份一致是升级核验依据，具体机器上的 TCC 保留仍以安装读回为准；从更早 ad-hoc 包切换到固定证书是另一种迁移。

## 下一步

将本地安装包交给 macOS 15.8.1 反馈用户升级确认。若仍不生效，1.0.2 的内置诊断会直接给出具体失败分支，无需先运行独立终端探针。效果确认后再安排 GitHub Release 和 Homebrew 更新。
