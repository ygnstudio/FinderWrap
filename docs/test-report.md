# 测试报告

日期：2026-10-23。本机：macOS 26.6.2 (25G83)、Finder 26.4、arm64；Xcode 27.1 (27A9275)、Swift 6.4、SDK 27.0。当前为本地预览，未发布。

## 编译和单元测试

- Debug 和 Release 构建成功；Release 应用及独立 probe 含 arm64/x86_64，两个架构 minos=15.0、sdk=27.0。
- 19:44:55 的 XCTest 执行：36 项通过，0 失败。18 个导航、7 个探查支持、7 个键盘策略/提交结果分类、4 个缓存测试。
- 缓存测试覆盖过期、空刷新、失效 epoch 及旧刷新不能复活缓存。提交结果分类测试覆盖写入返回值和实际读回的组合；不是系统故障注入。
- 本地预览包使用 ad-hoc 签名，签名核验成功；没有 Developer ID、公证或下载后的 Gatekeeper 验收。
- GitHub Actions 配置执行单元测试和 Universal Release 构建，不发送系统输入。远端结果以对应提交的 [Actions 运行记录](https://github.com/ygnstudio/FinderWrap/actions) 为准；本报告中的本机测试不替代 CI 结果。

主要命令：

```sh
bash scripts/test.sh
bash scripts/build.sh Release
lipo -info build/DerivedData/Build/Products/Release/FinderWrap.app/Contents/MacOS/FinderWrap
otool -l build/DerivedData/Build/Products/Release/FinderWrap.app/Contents/MacOS/FinderWrap
otool -L build/DerivedData/Build/Products/Release/FinderWrap.app/Contents/MacOS/FinderWrap
bash scripts/package.sh
codesign --verify --strict build/Preview/FinderWrap.app
```

本地交付复核还确认：安装版、提取后的预览包及 ZIP 内可执行文件逐字节相同；ZIP 不含测试工具/fixture；SHA-256 匹配；所有 shell 脚本语法、Info.plist 和工程 plist 检查通过；JSON 证据可解析且未包含本机路径或 file URL。安装 dry run、已有目标拒绝覆盖、卸载 dry run 已验证，未执行卸载。

## 真实输入授权与方法

用户回复“允许，仅限脱敏测试目录”，范围为 `Tests/Fixtures/Synthetic` 和 `build/Fixtures/Large`。后续明确允许安装、辅助功能/输入监控和菜单栏显示，仍限测试目录，不允许登录启动。

输入实验使用独立工具，每次投递前核对前台 Finder、标准窗口、图标区及全部项目的测试 URL。KeySmoke 可核对预期起点，不匹配即退出且不发送键。RuntimeHarness 限时 120 秒、只接受两个合成目录；测试结束停止该进程。所有记录仅含快照内索引/坐标、状态和时序。

## 真实测试结果

下列功能证据来自使用产品 Core 代码的受约束测试宿主，**不是安装版 GUI 验收**。表内文件均位于 `docs/evidence/`，前缀为 `2026-10-23-`。

| 场景 | 结果 | 证据后缀 |
|---|---|---|
| Finder 原生行末/行首 | 重启后实际 7 列；第 7 项右键、第 8 项左键都停留 | `native-row-end-after-right.json` 及现场读回 |
| 原生行内 | 第 8→9 项正常右移 | `native-right-before.json`、`native-right-after.json` |
| 开启后行内/跨行 | 第 9→8 项由原生处理；第 8→7、第 7→8 项跨行成功 | `runtime-left-interior.json`、`runtime-left-wrap.json`、`runtime-right-wrap.json` |
| 短时连续按键 | 12 次交替左右，每次在第 7/8 项间正确跨行；首末投递间约 1118.9 ms | `runtime-key-burst.json` |
| 连续按键监听状态 | 包含两次预热共 14 个箭头事件、14 次确认写入、0 不确定；最大回调 23.123 ms | `runtime-burst-status.json` |
| 首项边界 | 首项按左保持不变，监听确认写入为 0 | `runtime-first-left.json`、`runtime-native-status.json` |
| 上下键 | 第 1 项向下到第 8 项，向上返回第 1 项 | `runtime-down.json`、`runtime-up.json` |
| 日期组间 | 第一组末项→第二组首项，再返回；零基索引 17→18→17 | `runtime-next-group.json`、`runtime-previous-group.json` |
| 日期组监听状态 | 2 事件、2 确认写入、0 不确定；最大回调 34.082 ms | `runtime-group-status.json` |
| Quick Look | 预览获得焦点后左右原生移动，空格关闭后焦点返回；0 写入 | `runtime-quick-look.json`、`runtime-quick-look-status.json` |
| 36 项多选 | 左键前后均为同一 36 项；监听 1 事件、0 写入 | `runtime-multiple-selection.json`、`runtime-multiple-selection-status.json` |

`native-right-before/after` 是行内对照，不能当跨行证据。`runtime-interior-burst.json` 是早期原生行内/冷缓存实验，不能当跨行成功。日期分组早期一次起点不正确，随后增加预期索引检查，只有核对起点后的两次结果进入上述成功记录。

## AX、GUI 与安装

多视图、大目录、滚动、自由排列、缩放、桌面区别与 Finder 重启的只读探查，以及真实选择写入/恢复见 [AX 发现](ax-findings.md)。结构探查不等于导航支持。

Debug 原生 SwiftUI 预览窗已检查 320 pt 单页布局、缺权限时禁用导航、展开支持范围、按钮和文字无截断；截图 `evidence/2026-10-23-panel-permissions.png`。Release 不包含该 Debug 窗口。窗口视觉验收不能替代菜单栏锚点和弹出交互验收。

本地预览已安装到 `~/Applications/FinderWrap.app`；系统设置读回辅助功能、输入监控均为开启。用户完成 Touch ID 验证后重启安装版，保留测试目录参数。登录启动未开启。

安装版菜单图标因 FinderWrap 被错误挂在 Codex 的隐藏菜单登记下而不可见；原因已由用户终端导出及控制中心日志确认。用户已执行最小修复并通过读回，系统设置独立项及正常显示日志均已核对，用户已打开面板；完整结果见 [菜单栏诊断](menubar-diagnosis.md)。用户确认面板显示测试模式、两项权限已允许并开启导航后，单独使用安装版进行了下述实测。原生自动化工具无法绑定 MenuBarExtra 浮层，面板操作由用户完成，没有冒充自动化 GUI 读回。

## 安装版独立验收

2026-10-23，进程路径为已安装应用，参数含 --test-fixtures，未运行 RuntimeHarness；安装二进制已逐字节比对本地 ZIP 一致。

| 场景 | 安装版读回 | 证据后缀（同目录/日期前缀） |
|---|---|---|
| 日期组间 | 零基索引 17→18→17 | `installed-next-group.json`、`installed-previous-group.json` |
| 组内左右跨行 | 零基索引 7→6→7 | `installed-left-wrap.json`、`installed-right-wrap.json` |
| 短连续输入 | 12 次交替跨行全部匹配，首末投递相隔 1116.657 ms | `installed-key-burst.json` |
| 首项向左 | 0→0 | `installed-first-left.json` |
| 上下键 | 0→7→0 | `installed-down.json`、`installed-up.json` |
| Quick Look | 预览内 0→1→0，空格关闭后焦点回 Finder | `installed-quick-look.json` |

末行不足一整行时，末项向右实际为 35→29，没有跳到全局首项；不能把该结果记为“保持不动”。默认暂停后同样为 35→29，确认是 Finder 原生空间导航，见 `installed-last-right.json` 与 `native-last-right.json`。产品保持这项原生行为，并未实现“所有末项右键强制不动”的额外策略。

用户从安装版复制的诊断：两项权限 true、确认跨行 16 次、未改变写入 0、不确定写入 0、最大回调 23.65 ms；证据 `installed-diagnostics.json`。复制时面板在前台，cacheReady=false / inactive-or-untrusted 符合只在 Finder 前台采集的策略。随后将同一安装版重启到默认暂停的测试模式，行首左键 7→7，与启用时 7→6 对照，确认暂停后恢复原生行为，见 `installed-paused-left.json`。应用最终保持暂停。

有一次前台不在 Finder，KeySmoke 在发送前退出，未投递按键；明确打开合成目录后重试成功。另有若干只读 AXMainWindow 调用返回 -25204，测试工具在完整采集成功后才发送按键；这不是写入失败或事务故障注入。

## 仍未覆盖

- 持续按住键盘产生的重复事件、不同键盘/输入法/辅助功能组合尚未验证。
- 真实 AX 写入失败、超时、迟到读回与焦点切换时的事务故障注入。同步写入不构成严格的系统原子事务；见 [运行时设计](runtime-design.md)。
- 原生自动化无法绑定菜单浮层，因此没有自动化的开关控件读回或安装版浮层截图；启用由用户完成并以真实行为核对，暂停通过重启默认状态及原生对照确认。实际权限撤销/恢复、运行中 Finder 重启回归、登录项注册/注销仍待验证。
- 日期之外的分组、自由排列的可靠模式识别、屏外边界、外接屏幕/不同缩放。
- macOS 15 / 27、Intel 真机及正式分发。

## 已记录并修正的问题

沙箱内 XCTest 被系统测试服务拒绝，正常宿主执行通过；AXDocument 返回 noValue 后改用内存核对测试 URL；AX 分页不足改为按实际数量推进；普通合成按键含非修饰元数据位，改为检查公开修饰键语义；日期标题不是文件包装元素，增加实际标题签名；折叠组或失效元素直接放行。初版菜单项移除导致自动退出，显式 isInserted 绑定只修复进程退出，登记冲突单独诊断处理。

## 2026-10-24：1.0.0 本地版

本轮 44 项 XCTest、Universal Release、包体内容/签名/校验值与隔离启动通过。新测试宿主完成 16 次确认写入（含 12 次短连续左右键）、日期跨组及上下键；最大回调 33.219 ms，未观察到不确定写入。

此前自动 reveal 带来的视口变化与前台丢失使部分尝试未满足前提，另保留一次跨行后上键未移动的原始记录。固定原生视口和起点后的完整序列通过；不把先前失败记录抹掉，也不以测试宿主结果代替安装版菜单验收。

详见 [1.0.0 交付记录](release-1.0.0.md) 及其证据链接。真实系统故障、物理长按、其他系统/硬件与完整安装版回归仍需分别验证。

## 2026-10-24 物理方向键回归（1.0.1）

用户实际键盘报告推翻此前“合成按键可代表普通键盘”的假设：普通左右键带 `0xa00100`，旧策略拒绝 function 标记，旧测试投递又清空了 flags。已运行红绿回归（旧策略两处失败；修复后 48 项通过），并修复三处输入工具。用户 Fn 组合在系统侧转换为 Home/End。详见 [1.0.1 记录](release-1.0.1.md)。更新安装副本后旧授权失效，权限刷新和物理安装版换行验收需单独完成，当前不能据单测替代。

### 1.0.1 安装版后续验收

两项授权已恢复，用户确认实际换行可用。出现两次 AX 未确认导致的自动暂停后，诊断宿主 13 次合成事务和 5 次物理事务没有复现；重新启动同一安装版后，15 次合成转换与用户物理复测均正常。用户最后反馈“没问题了”。没有为该间歇现象修改产品保护逻辑，具体 AX 错误仍未知，不能将重启后恢复记作永久修复。见 [详细证据](evidence/2026-10-24-auto-pause-investigation.json)。


## 2026-10-25 · 窗口焦点回归

1.0.2 新增 10 项 FinderFocusTests，旧判断实际出现 8 个失败断言，修复后完整 58 项测试通过；另有 5 项签名策略测试通过。Synthetic 原生 AX 测试正向 item-6→item-7、反向返回均确认，并恢复测试前选择。本轮没有模拟键盘事件或替换安装版，也没有 macOS 15 真机验证。完整边界和安装包验签见 [1.0.2 修复候选](release-1.0.2.md)。

推送前从独立源码副本复跑 58 项 XCTest 和 5 项签名策略测试，均通过。审查发现 FocusSmoke 辅助工具仅用集合选中列表保存/恢复选择可能遗漏屏外多选，已改为每次写入前后复用产品的逐项单选校验。纯内存 stub 执行该工具主流程，旧守卫在初始屏外多选、恢复前新增屏外选择两种情况下失败；新版四种控制流检查全部通过。此检查没有真实 AX 调用，不能算新增原生验收；前述原生结果来自工具保护加强前的测试。

## 2026-10-26 · 分组读取探针

仅新增只读诊断工具，没有修改产品。`test_section_probe.py` 的 12 项测试通过，覆盖 section 类型与空组、计数与分页异常、数量边界、读后变化、超时/焦点退出、角色和标识脱敏。完整脚本的未授权分支及正常宿主 AX 计数/分页/CF 桥接验证通过；未做真实按键、应用签名、安装或权限变更。没有 macOS 15.7.4 采样结果，不能声称修复用户故障。详见 [调查记录](macos15-section-diagnostic.md)。

## 2026-10-26 · 1.0.3 分组解析回归

新增 10 项 XCTest，直接测试生产解析器和 AX 分页边界：可选子类型、角色/内容错误、分组标题、160/164 两种上限、数组错误、重复和变化。旧逻辑已实际红灯，修复后的隔离副本 68 项全部通过；17 项 Python 测试通过。未把模拟可选属性标为 macOS 15 真实返回。原生对照与包体签名核验见 [1.0.3 记录](release-1.0.3.md)。
