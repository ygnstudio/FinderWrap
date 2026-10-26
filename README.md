# FinderWrap

Finder 图标视图的左右键换行工具。**当前版本：1.0.4（build 7），核心已按“常驻布局 + 按键时实时选择”重做。**

上一版核心在每次选择变化后作废布局，正常按键速度下经常等不到“就绪”，表现为时灵时不灵。1.0.4 改成：布局在后台按需刷新，按键时只读一次当前选择，几何判定放宽到“可见行”，不再要求整行完整可见或分区端点可证明。

应用只驻留菜单栏：点图标打开面板，开关、权限状态、视图选项、诊断与退出都在面板里。

## 当前行为

- 图标视图：单/多选都能跨行换行，行尾按右键到下一行第一个，行首按左键回上一行最后一个；整个文档首尾也会循环。
- 覆盖：普通文件夹、搜索/智能文件夹、按种类分组、桌面图标、Quick Look（Finder 前台但焦点在 Quick Look 窗口时继续驱动底下的图标布局）。
- 画廊视图：缩略图条到两端循环（可在窗口里关闭）；按 Finer 的做法接管左右键（读 AX 选择→算目标→写选择+设焦点），不再依赖 Finder 光标。
- 列表视图：左右键切换上一项/下一项（独立开关，默认关闭）。**列表首尾不循环**：到端点后按键被吞掉、保持原选择（不交给 Finder，避免右键变成展开文件夹）；向不可见行写选择会清空选择，所以不做循环。
- 分栏、重命名、搜索框等编辑态保持原生。
- 开关状态会记住，下次启动自动恢复（权限不全时保持关闭）。

只需要两项权限：**辅助功能**与**输入监控**。1.0.4 不再需要“自动化 Finder”（Apple Events）权限。

## 下载与升级

公开稳定版 Release / Homebrew 仍是 1.0.3；预览包由 GitHub Actions 的 main 构建生成，在成功运行的 `FinderWrap-fixed-signature-<commit>` 附件中下载。包沿用仓库固定证书与签名要求，未经过 Apple 公证。不要关闭 Gatekeeper / SIP，也不要运行全局权限重置。见 [安装说明](docs/installation.html) 与 [签名约束](docs/signing.md)。

## 开发

需要 Xcode 命令行工具，不引入第三方运行时依赖。

```sh
bash scripts/test.sh
bash scripts/build.sh Release
# 固定证书已配置在钥匙串中时：
bash scripts/package.sh --fixed
```

`Rebuild/` 是当前唯一应用核心和 SwiftUI 宿主，`Resources/` 保存图标。测试默认不访问 Finder、不发送真实按键、不改权限。构建输出在 `build/Products/Release`，安装包在 `build/packages`。

[架构](docs/design.md) · [兼容性](docs/compatibility.md) · [验收](docs/testing.md) · [MIT](LICENSE)
