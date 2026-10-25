# FinderWrap

为 Finder 图标视图补充左右方向键跨行导航的原生 macOS 菜单栏应用。SwiftUI `MenuBarExtra`，无第三方运行时依赖，无账号、网络服务或遥测。

**当前发布版本：1.0.1。** 提供 Universal 2 DMG 和 ZIP，使用 FinderWrap 专用固定自签证书，未做 Developer ID 签名或苹果公证。源码按 MIT 许可证公开；安装包不代表跨系统兼容性已全部验证。

main 已包含 [1.0.2 窗口焦点修复候选](docs/release-1.0.2.md)，用于处理有效图标焦点被旧窗口条件拒绝的问题。反馈用户的 macOS 15.8.1 实际效果仍待确认，Release 与 Homebrew 暂保持 1.0.1。

## 安装

通过现有 [Homebrew tap](https://github.com/ygnstudio/homebrew-ygn) 安装和升级：

```sh
brew install --cask ygnstudio/ygn/finderwrap
brew update
brew upgrade --cask ygnstudio/ygn/finderwrap
```

已手动安装的用户请先退出并备份原应用，再安排迁移；不要使用 `--force` 直接覆盖正在运行的应用。

也可从 [Releases](https://github.com/ygnstudio/FinderWrap/releases) 下载已验签的安装包。

打开 `FinderWrap-1.0.1-b3-fixed-universal.dmg`，将 FinderWrap 拖入“应用程序”。已有预览版时，先退出应用并备份，在原位置替换，避免同时保留两个副本。详细说明见包内或 [安装说明](docs/installation.html)。

全新安装默认暂停。用户在系统设置开启辅助功能、输入监控，再启用“左右键自动换行”。升级保留导航偏好；从旧 ad-hoc 包首次迁移到固定证书，可能需要重新授权一次。后续包强制沿用固定证书和代码身份，实际权限保留仍需目标机器验收。若诊断为 false，需在系统设置为更新后的应用重新授权并重新开启导航；登录启动默认关闭，只响应用户显式操作。未公证应用可能被系统阻止；核对来源和校验值后，使用系统设置提供的“仍要打开”，无需关闭 Gatekeeper 或 SIP。

## 行为和支持边界

- 行末按 `→` 选择下一行首项；行首按 `←` 选择上一行末项。首尾不循环。
- 行内、上下键、带修饰键的组合和多选保留 Finder 原生行为。末行不满时，原生右键可能选择上一行更靠右的图标，本版保留此行为。
- 支持结构和坐标均可确认的普通图标网格，以及已验证的日期分组边界。
- Quick Look、桌面、列表、分栏、自由排列、不完整布局、屏外目标和超过 160 项的目录保留原生行为，不强制滚动或猜测目标。
- 写入前验证单选、焦点、窗口、布局和缓存。明确拒绝且读回原项时放行；目标读回确认时消费原键。结果不确定则暂停且不再投递该键，避免迟到写入叠加原生移动；这一次可能没有完成移动，后续输入恢复原生处理。详见 [输入协调](docs/runtime-design.md)。

实机证据主要来自 **macOS 26.6.2 / Finder 26.4 / Apple Silicon**。最低编译目标 macOS 15；Intel、macOS 15/27 的完整 GUI 与 Finder 导航尚未验证。

## 构建与打包

需要 Xcode，无需第三方依赖：

```sh
bash scripts/build.sh Debug
bash scripts/test.sh
bash scripts/build.sh Release
bash scripts/package.sh
```

构建位于 `build/DerivedData/Build/Products/{Debug,Release}/`；DMG、ZIP 和 SHA-256 文件位于 `build/packages/`。打包默认要求 [固定签名配置](docs/signing.md)，配置缺失或证书不匹配即失败；拒绝覆盖同名包，排除 probe、测试工具、源码和本地诊断备份。仅本地实验可显式使用 `--ad-hoc`，CI 禁止生成这种安装包。

GitHub Actions 执行单测和 Universal Release 构建，上传 `verification-unsigned` 验证归档（不可用于覆盖安装）。固定证书配置完成后，main 分支构建另提供 `fixed-signature` 安装包，并逐架构校验证书指纹与升级身份；不会每次生成新证书。CI 不操作 Finder 或修改系统权限。

安装脚本默认只预览，`--apply` 才复制，拒绝覆盖已有应用：

```sh
bash scripts/install.sh /absolute/path/FinderWrap.app
bash scripts/install.sh --apply /absolute/path/FinderWrap.app
```

测试模式仅接受项目内两个合成目录、默认暂停、不保存导航开关并禁用登录启动：

```sh
open -n ~/Applications/FinderWrap.app --args --test-fixtures "$PWD"
```

真实输入必须先获得授权；测试前确认没有其他 FinderWrap/RuntimeHarness 实例。卸载前先关闭登录启动并退出，`scripts/uninstall.sh` 默认预览，`--apply` 才移至废纸篓，保留偏好和系统权限记录。

## 验证与隐私

58 项 XCTest 覆盖窗口焦点、导航、缓存、修饰键、超时/迟到写入故障模拟和停用写入屏障。实际 Finder 输入与安装验收分别记录，模拟故障不冒充真实系统故障。

独立只读 probe 不申请授权、不写选择、不监听或发送按键；JSON 只含 AX 结构、坐标、状态、错误码及耗时。实验工具不进入应用包；复制诊断不含文件名、路径、选中文本或键盘文本。

- [1.0.1 交付记录](docs/release-1.0.1.md) · [发布检查表](docs/release-checklist.md)
- [测试报告](docs/test-report.md) · [兼容矩阵](docs/compatibility.md)
- [AX 发现](docs/ax-findings.md) · [运行时设计](docs/runtime-design.md)
- [真实输入测试授权](docs/native-test-plan.md) · [菜单栏登记诊断](docs/menubar-diagnosis.md)
- [历史阶段记录](docs/agent-progress.md)

MIT 许可证。源码与安装包托管于 [ygnstudio/FinderWrap](https://github.com/ygnstudio/FinderWrap)，安装定义维护于 [ygnstudio/homebrew-ygn](https://github.com/ygnstudio/homebrew-ygn)。签名私钥不进入源码或安装包。
