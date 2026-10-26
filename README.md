# FinderWrap

Finder 图标视图的左右键换行工具。**当前开发版本：2.0.0 预览版 1（200002）**。

新核心已替换 1.x 的全目录扫描。普通文件夹可直接使用，不要求 Synthetic 或命令行测试参数。应用初始暂停，开启前需要辅助功能、输入监控和自动化 Finder 三项权限。

## 当前行为

- 单选时，在可确认的可见行边界增强左右键；行内仍交给 Finder。
- 当前文件夹以外的应用、编辑、多选、列表、分栏、画廊保持原生交互。
- 运行失败显示恢复或暂停原因，保留用户开关意愿。
- **Quick Look、桌面、屏外目标和无法确认的分组边界暂不增强。** 这不是“所有布局均已支持”的正式稳定版。

仅 Apple Silicon；构建最低系统为 macOS 13。13/14/15/27 的真实输入兼容性仍待验证，部署目标不代表验收完成。详见 [兼容性](docs/compatibility.md)。

## 下载与升级

本次预览包由 GitHub Actions 的 main 构建生成，在成功运行的 `FinderWrap-fixed-signature-<commit>` 附件中下载。公开稳定版 Release / Homebrew 仍是 1.0.3；不会把预览包自动推送给稳定版用户。

包沿用仓库固定证书与签名要求，未经过 Apple 公证。若本机旧包是临时签名，首次迁移到固定证书仍可能需要重新授权；固定证书不会消除不同签名身份之间的迁移。不要关闭 Gatekeeper / SIP，也不要运行全局权限重置。见 [安装说明](docs/installation.html) 与 [签名约束](docs/signing.md)。

## 开发

需要 Xcode 命令行工具，不引入第三方运行时依赖。

```sh
bash scripts/test.sh
bash scripts/build.sh Release
# 固定证书已配置在钥匙串中时：
bash scripts/package.sh --fixed
```

`Rebuild/` 是当前唯一应用核心和 SwiftUI 宿主，`Resources/` 保存图标。旧 Xcode 工程、1.x 核心和过期调试工具已从工作树移除，可通过 Git 历史恢复。测试默认不访问 Finder、不发送真实按键、不改权限。构建输出在 `build/Products/Release`，安装包在 `build/packages`。

应用正常双击启动。开发者仍可使用 `--synthetic-directory /absolute/path/Tests/Fixtures/Synthetic` 约束自动化测试；这是可选的测试保护，不是普通用户的使用限制。

[架构](docs/design.md) · [验收](docs/testing.md) · [MIT](LICENSE)
