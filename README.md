# FinderWrap

为 Finder 图标视图补充左右方向键跨行导航的原生 macOS 菜单栏应用。SwiftUI `MenuBarExtra`，无第三方运行时依赖，无账号、网络服务或遥测。最低编译目标 macOS 15，Release 为 Universal 2。

**当前版本为 0.1.0 本地预览，尚未达到正式发布门槛。** 核心导航已在本机 macOS 26.6.2 / Finder 26.4 的脱敏目录中实际运行。安装版菜单栏登记异常已修复，实际跨行、跨组与暂停对照已验证；AX 写入结果不确定时的输入原子性、其他系统及 Intel 真机仍待验证。

## 行为和支持边界

- 行末按 `→` 选择下一行首项；行首按 `←` 选择上一行末项。首尾不循环。
- 行内、上下键、带修饰键的组合和多选保留 Finder 原生行为。末行不满时，Finder 原生右键可能选择上一行更靠右的图标，本版保留此行为，不额外强制停留。
- 支持结构和坐标均可确认的普通图标网格，以及已验证的日期分组边界。
- Quick Look、桌面、列表、分栏、自由排列、不完整布局、屏外目标和超过 160 项的目录保留原生行为。原生左右键在这些边界可能仍停留，应用不会强制滚动或猜测目标。
- 仅在单选、焦点和窗口未改变、缓存有效且 AX 写入读回确认目标时消费按键。写入结果无法确认时暂停监听并放行原事件；极端情况下仍存在额外移动的风险，见 [事务限制](docs/runtime-design.md)。

## 构建与本地预览

需要 Xcode，无需安装第三方依赖：

```sh
bash scripts/build.sh Debug
bash scripts/test.sh
bash scripts/build.sh Release
bash scripts/package.sh
```

构建输出：`build/DerivedData/Build/Products/{Debug,Release}/`。打包输出：`build/packages/FinderWrap-0.1.0-preview-universal-adhoc.zip` 及 SHA-256 文件。预览包使用 ad-hoc 签名，不访问或创建证书；**不是 Developer ID 签名或公证发行版**。

安装脚本默认只预览，显式 `--apply` 才复制，且拒绝覆盖已有应用：

```sh
bash scripts/install.sh /absolute/path/FinderWrap.app
bash scripts/install.sh --apply /absolute/path/FinderWrap.app
```

应用默认暂停。用户自行在系统设置开启辅助功能、输入监控，再启用“左右键自动换行”。登录启动默认关闭，只响应用户显式操作。本机已按用户授权安装到 `~/Applications/FinderWrap.app` 并开启两项权限；没有开启登录启动。

安装验收限定到项目生成的两个测试目录：

```sh
open -n ~/Applications/FinderWrap.app --args --test-fixtures "$PWD"
```

该模式只接受 `Tests/Fixtures/Synthetic` 和 `build/Fixtures/Large`，不保存导航开关，禁用登录启动选项。测试前确认没有另一个 FinderWrap/RuntimeHarness 实例。

卸载脚本默认预览；先关闭登录启动并退出应用，`--apply` 才移入废纸篓，保留偏好和系统权限记录：

```sh
bash scripts/uninstall.sh
```

## 探查和隐私

```sh
bash scripts/probe.sh --help
bash scripts/probe.sh --scenario current-state --output build/probe.json
```

独立 probe 不申请授权、不写选择、不监听或发送按键。JSON 保存 AX 角色、坐标、布尔状态、快照内编号、错误码及耗时，不保存文件名、路径、标题或文本。`scenario` 是操作者标签，不是自动识别结果。集合和图像可能重复表达同一个选中项，不能用 `selectedItems` 长度计数。

`Tools/FinderAXProbe` 内的 SelectionCheck、KeySmoke、KeyBurst、QuickLookSmoke 和 RuntimeHarness 是独立实验程序，不进入应用包。真实输入必须得到用户明确授权；测试工具在每次操作前核对前台 Finder、窗口和合成项 URL。

## 验证与项目状态

36 个 XCTest 已通过；真实测试覆盖普通跨行、日期组间导航、12 次交替跨行、首项边界、上下键、Quick Look 和 36 项多选放行。测试宿主与安装版分开验收；安装版另外确认 16 次跨行/跨组写入、12 次交替按键、上下键、Quick Look 及暂停对照。跨系统和故障注入仍未完成。

- [阶段记录](docs/agent-progress.md)
- [AX 发现](docs/ax-findings.md) · [运行时设计](docs/runtime-design.md)
- [测试报告](docs/test-report.md) · [兼容矩阵](docs/compatibility.md)
- [真实输入测试授权](docs/native-test-plan.md)
- [菜单栏登记诊断](docs/menubar-diagnosis.md)
- [发布检查表](docs/release-checklist.md)

MIT 许可证。源码托管于 [ygnstudio/FinderWrap](https://github.com/ygnstudio/FinderWrap) 私有仓库。远端验证结果见 [GitHub Actions](https://github.com/ygnstudio/FinderWrap/actions)；源码托管和 CI 构建不代表正式发布。尚未创建 GitHub Release 或公开上传构建。
