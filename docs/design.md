# 1.0.5 架构

三层：事件监听、布局缓存、按键判决。

1. **事件监听**：`FinderWrapMonitor` 在独立线程跑 CGEvent tap，只关心左右方向键（无修饰键、非 Fn）。回调里只做有界 AX 读：焦点窗口/元素、一次 `AXSelectedChildren`、源/目标两帧、一次写入与回读。
2. **布局缓存**：`GridReader` 在后台队列（350ms 周期）抓取一次可见图标表面，发布不可变快照；选择变化**不**作废布局。快照含 grid 元素、可见项 URL/几何、行聚类结果、是否 Quick Look、grid 的角色/子角色/标识。
3. **按键判决**：`WrapEngine` 是纯函数 —— 按 Y 聚类成行、按 X 排序，行尾/行首跨行，文档首尾循环；多选时用最外侧选中项定位。画廊视图走单行循环规则。列表视图单独走原生按键（Right→Down、Left→Up）。

场景识别：

- 图标视图：焦点向上找到 `AXGrid`，或 `AXList/AXCollectionList`（IconView/GalleryView）。
- 画廊视图：每一键都读 AX 选择、按条带顺序取模算目标、写 `AXSelectedChildren`，再设容器焦点并滚动（参考 Finer 的 setSelection）；不依赖 Finder 原生光标。
- 列表视图：只做原生上一项/下一项（Down/Up）；两个端点吞掉按键，避免 Finder 把右键解释成展开文件夹。
- 桌面：没有 AXGrid，也没有焦点窗口；取焦点 AXGroup/AXScrollArea 中能读到图标项的那一层作为表面。
- Quick Look：Finder 前台、焦点窗口子角色是 `Quick Look`；取 AXWindows 中第一个非 Quick Look 的图标窗口作为被预览布局。
- 列表：焦点是 `AXOutline` + 标识 `ListView`。

安全边界：

- 写入后必须回读确认；回读失败不重放、不清空已有选择。
- 列表边界交回 Finder 原生处理：AX 写选择会清空选中项，Apple Events 与合成点击不能稳定移动高亮，因此边界不拦截。
- 诊断只导出角色、几何、计数与决策原因，不含文件名、路径或按键内容。
