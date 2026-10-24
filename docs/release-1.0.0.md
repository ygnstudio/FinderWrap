# FinderWrap 1.0.0 · 本地安装包

> 已发现输入过滤缺陷：真实方向键的 function 标记被当成按住 Fn，可能导致完全不触发换行。下文的系统按键测试人为清空了 flags，未覆盖这条路径，不能作为物理键盘可用的证据。修复和补充验收见 1.0.1 记录；不再推荐安装 1.0.0。

2026-10-24。用户选择：正式应用、仓库仍私有、先提供本地安装包；暂无 Developer ID 证书。本次版本为 **1.0.0 / build 2**，分发范围为本地 ad-hoc 签名包，未做苹果公证。

1. **跨行导航**：在可确认的 Finder 图标布局中，左右方向键可跨行并切换日期分组；单页菜单栏提供启停、权限提示和诊断。
2. **异常暂停**：选择结果不确定时暂停自动换行，避免原按键被再次执行；这一次可能没有完成移动，后续输入仍由 Finder 处理。
3. **安装交付**：提供 Apple Silicon / Intel 通用 DMG、ZIP、安装说明和 SHA-256；打包排除实验工具及本机诊断备份。

## 安装包

文件位于项目 `build/packages/`，最终 DMG 与 ZIP 内的应用逐文件一致：

| 文件 | 字节数 | SHA-256 |
|---|---:|---|
| FinderWrap-1.0.0-local-universal.dmg | 556189 | `3f6c8e771f07f45dab4d50f2b0ef8c62ace8f119e738967ab73c382e68964ea3` |
| FinderWrap-1.0.0-local-universal.zip | 506835 | `1191a408d50bfb67c88fbffc46ab9b71d34749653bf9a4299602babb5fa6c7ef` |

DMG 内有 FinderWrap.app、Applications 快捷入口、Install.html 和 LICENSE.txt。ZIP 内有同一应用、说明与许可证，没有 AppleDouble 元数据。包内只有应用二进制、Info.plist、PkgInfo、图标/资源与签名，不含 probe、测试工具、源码、日志或用户文件。

安装前退出旧版，在原位置备份并替换，避免同时存在两个运行副本。安装与卸载方法见 [说明](installation.html)。本次未覆盖 `~/Applications` 中的旧版；隔离验收副本已停止。

## 本轮验证

- `scripts/test.sh`：**44 项 XCTest 通过**。新增回归先在旧实现复现失败，再验证修复；覆盖超时与迟到写入、读回丢失、明确拒绝、故障后连续输入和停用写入互斥。
- `scripts/build.sh Release`：应用与独立 probe 均构建成功；应用包含 arm64 / x86_64，最低目标 15.0。probe 不进入安装包。
- 最终 DMG 挂载、映像校验、签名严格验证、DMG/ZIP 内容比对、包内版本与架构读回、校验值复核均通过。
- 从最终 DMG 复制出的应用以 `--test-fixtures` 启动，已核对进程路径及参数，启动存活检查通过，随后停止；测试模式默认暂停。该检查仅证明包内应用启动，不替代安装后的菜单交互/导航验收。
- 新编译测试宿主在授权 Synthetic 目录完成 **16 次确认写入**：左右跨行、12 次短连续左右键、日期跨组，以及上下键原生行为。没有 unchanged / indeterminate，最大回调 **33.219 ms**。这不是物理长按、端到端延迟分位数或硬上限。
- 代码按标准深度复核，覆盖输入处理、关闭互斥与打包边界；发现并移除了归档中不必要的扩展属性；签名前剥离包含本机源码路径的调试符号，最终包重新验签、启动及隐私扫描通过。新增文档单独检查，不触碰既有宣传视频。

证据：[包体与启动](evidence/2026-10-24-package-1.0.0.json)、[完整真实输入复测](evidence/2026-10-24-runtime-local-1.0.0.json)、[固定视口跨行后上键](evidence/2026-10-24-fixed-viewport-wrap-up.json)。

测试前提排查：早期尝试出现前台丢失被守卫拦截，以及跨行后 Up 的一次未移动。检查发现 `open -R` 会改变滚动位置；后续通过原生界面固定顶部视口、原生选择起点，再仅激活 Finder，完整序列通过。保留原始对照记录，不将前提失败统计成产品通过，也不声称已经证实所有早期异常的唯一原因。测试宿主、直接 AX 写入及无宿主原生对照分别记录。

## 仍需区分的验证层级

- 没有 Developer ID 签名或公证。`spctl` 在本机返回 0，但只读检查显示本机原本为 `assessments disabled`，因此不能将该结果当作下载后 Gatekeeper 验收；本次未修改此设置。
- 当前运行验证来自 macOS 26.6.2 / Finder 26.4 / Apple Silicon。Intel、macOS 15/27、外接屏和更多缩放组合仍待实机验证。
- 真实 Finder 挂起/通信超时、提交途中焦点切换、物理长按、输入法、权限撤销恢复、运行中 Finder 重启和登录项注册/注销仍待专项验证。故障模拟不冒充系统故障测试；未为验收开启登录启动或修改系统权限。
- 产品在已说明的模式中保守降级；不保证跨进程严格原子性，无法确认的单次按键可能没有移动。详见 [运行时设计](runtime-design.md)。

## 仓库与发布状态

本轮读取 GitHub 确认 [ygnstudio/FinderWrap](https://github.com/ygnstudio/FinderWrap) 仍为私有。基线为 `c3f1e4014c88bb468ae748b54954ec379e81431e`；本次应用源码、测试与文档改动保留在工作区，未推送、未创建标签或 GitHub Release。

旧提交在 macos-15 / Xcode 16.4 的 CI 已通过，但不当作本次改动的远端 CI 结果。已有 `media/promo-2026-10-23-v1/` 宣传素材保持原样，未加入安装包。

正式对外分发还需要 Developer ID 签名、公证及启用标准 Gatekeeper 的另一台 Mac 下载验收。苹果要求见 [Notarizing macOS software before distribution](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)。
