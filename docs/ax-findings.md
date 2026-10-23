# Finder AX 实测记录

日期：2026-10-23（Asia/Shanghai）。环境：macOS 26.6.2 (25G83)，Finder 26.4，arm64，Xcode 27.1，SDK 27.0。本文仅说明本机实测；不推广为 macOS 15/27 的结构保证。

## 基本可行性门槛

| 条件 | 实测结果 | 证据 |
|---|---|---|
| 定位普通窗口图标区 | `AXWindow / AXStandardWindow` 下的 `AXList / AXCollectionList`，语义标识为 `IconView`；桌面不具有此签名 | `2026-10-23-name-sort.json` |
| 读取单选 | 集合的 `AXSelectedChildren` 返回 `AXGroup` 包装元素，内层 `AXImage.AXSelected` 为 true | `2026-10-23-single-selection.json` |
| 读取布局 | section 下的图标包装元素、内层图像提供屏幕坐标与尺寸；名称排序采到 8 列布局 | `2026-10-23-resized-window.json` |
| 确定相邻关系 | 已获取同一 section 中的坐标，可依据纵向行与横向位置确定相邻项；AX 子项顺序不作为导航顺序 | `Tests/Fixtures/macOS26/fully-visible.json` |
| 安全修改选择 | 集合 `AXSelectedChildren` 写入另一已核对 URL 的测试项成功，读回一致，恢复原选择成功 | `2026-10-23-selection-roundtrip.json` |

以上是实现前取得的可行性证据。随后已完成运行时适配器及受约束的真实按键测试；它们仍不构成严格的键盘原子性或跨系统保证。

## 普通图标视图

本机观察到的主要结构：

```text
AXWindow / AXStandardWindow
  AXScrollArea
    AXList / AXCollectionList (AXIdentifier = IconView)
      AXList / AXSectionList
        AXGroup                ← 集合选中项引用这个元素
          AXImage              ← AXSelected 可读，报告不可写
```

集合 `AXSelectedChildren` 报告可写。图像的 `AXSelected` 报告不可写。需要设置集合的选中列表，不能对图像直接写 selected，也不能把层级固定为所有系统通用模板。

自由排列的 section 还出现了覆盖整个 section 的无图像 `AXGroup`，因此“每个 AXGroup 都是文件”同样不成立。只读探查保存结构，不自动把它们当作图标或分组。

## 写入实验与限制

独立程序 `SelectionCheck.swift` 仅在项目合成文件夹内运行。它核对 Finder 前台状态、主窗口、当前焦点图标区、窗口关联、单选、可写性以及每个可见项的文件 URL，再写入另一项并恢复。

第一次实验发现 `AXDocument` 虽被窗口列为支持属性，实际返回 `-25212 / noValue`，因此在写入前退出，没有改变选择。随后改为在内存中核对合成项的 URL；原始 URL 不写入 JSON。

成功实验的单次耗时：写入目标 4.204 ms，读回 3.585 ms，恢复 2.965 ms，恢复读回 3.017 ms。四次调用均返回 success，两个读回均匹配。**这些单次数据不足以证明 CGEventTap 回调预算、连续按键行为或超时后的原子性。**

## 多选、滚动和不完整数据

- 36 项全选时，Finder 状态栏显示 36 项，集合选中列表只返回当前可见的 32 项；逐个检查图像可读到全部 36 项 selected=true。
- 放大窗口后，集合选中列表返回 36 项。不能仅凭集合返回一项断定实际单选，尤其在存在不可见项目时。
- 1,200 文件场景中，受 150 子项上限约束的探查明确输出 `sampled-partial`，出现失效元素 `-25202`。滚动前约 1.199 秒，滚动后约 2.526 秒，均为整个探查流程耗时，不能放进键盘回调。
- AX 数组一次可能只返回请求数量的一部分。探查已改为最多每页 20 项、按实际返回数量推进，并标记截断。早期的 desktop、fixture-window、single-selection、list、column、date-groups、free-arrangement、quick-look 文件来自修正分页前的探查版本，即使标为 sampled，也不能证明所有关系完整；它们仅用于已经实际返回的结构、可写性与焦点证据。
- 运行时适配器现已要求完整快照，最多 160 项、24 个 section；失效引用、缺失分页、选择不一致及不确定可见性均放行，不从文件列表补造目标。写入前重新核对每项坐标与选择，不能仅凭集合选中列表判断单选。

## 分组与 Quick Look

通过 Finder 菜单把测试文件夹按修改日期分组；测试文件只使用生成的数据，并人为设置了当天、昨天和九天前的修改时间。界面确实显示不同日期分组，AX 中有三个 `AXSectionList`。包含标题的 section 会有额外子元素，因此不能直接用子项计数当文件数。后续确认标题包装包含 AXStaticText 和 AXButton，与普通文件的 AXImage 包装不同；运行时要求这个实际签名。折叠第三组曾返回失效元素 -25202，适配器拒绝该快照。展开全部后得到 36 项完整布局，已实测零基索引 17→18→17 的组间导航。屏外组加载仍不支持。

通过鼠标菜单打开合成文本的 Quick Look，Finder 的 mainWindow 仍是标准窗口；focusedWindow 变为无标准 subrole 的预览窗口，focusedElement 为 `AXTextArea`。这明确不满足普通图标视图的焦点条件。后续受约束测试中，预览左右原生移动索引 10→11→10，空格关闭后回到标准窗口；监听观察到两个方向键但确认写入为 0。运行时放行 Quick Look，未尝试以 AX 写入驱动预览更新。

## 桌面、视图与重启

初始 Finder 没有普通主窗口，AXWindows 中有桌面滚动区和图标组。桌面组也报告 selectedChildren 可写，但本次没有对桌面执行写入实验；桌面不纳入普通窗口适配。

列表视图被界面标识为 `ListView`，分栏为 `ColumnView`，与普通 `IconView` 不同。只读快照已保存，尚未做运行时键盘放行测试。

执行正常终止 Finder 后，其进程由 PID 684 变为 55655。重启后重新创建 AX 根引用并成功采样，受 100 节点上限限制而标为 partial。生产缓存必须关联进程实例和窗口代际；快照内 `n0001` 等编号不能跨运行复用。

## 尚未验证

真实写入错误/超时及迟到回复处理、长按与输入法、Quick Look 内自定义跨行、可靠自动判断所有排序/自由排列模式、任意不规则布局、外接显示器与缩放、macOS 15/27、Intel 真机。普通跨行、日期组间、短时连续按键、多选/Quick Look 放行的实测结果见 test-report.md。

## 公开 API 依据

- [AXUIElementIsAttributeSettable](https://developer.apple.com/documentation/applicationservices/1459972-axuielementisattributesettable)：可写性逐元素查询；查询结果仍需实际写入与读回验证。
- [AXUIElementSetMessagingTimeout](https://developer.apple.com/documentation/applicationservices/1459345-axuielementsetmessagingtimeout)：对 system-wide element 设置超时会成为该探查进程的默认值。独立 probe 设置 150 ms，并另设总预算、节点和分页上限；运行时消息超时为 10 ms，相关软预算和局限见 runtime-design.md。
- 同时检查了当前 SDK 的 `AXUIElement.h` 与 `AXAttributeConstants.h`。没有使用私有 API、Finder 注入或系统文件修改。
