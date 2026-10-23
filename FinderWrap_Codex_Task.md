以下是改回 Codex 的完整 Markdown 开发任务书，可直接复制保存为 `FinderWrap_Codex_Task.md`，然后交给 Codex 执行。

# FinderWrap — Codex 完整开发任务书

> 文档版本：0.2.0 项目名称：FinderWrap 项目类型：macOS 原生菜单栏应用 执行主体：Codex 开发语言：Swift UI 框架：SwiftUI First 最低系统版本：macOS 15.0 目标系统：macOS 15、26、27 处理器架构：arm64 + x86_64 发布方式：GitHub 开源、GitHub Releases 开发原则：先探查、后实现；最小依赖；安全降级；真实验证

## 1. 项目目标

开发一款轻量级、免费、开源的 macOS 菜单栏应用，为 Finder 图标视图补充左右方向键自动换行能力。

### 1.1 核心行为

在 Finder 图标视图中：

- 当前选中项位于一行最右侧时，按 `→`，选中下一行最左侧图标。
- 当前选中项位于一行最左侧时，按 `←`，选中上一行最右侧图标。
- 当前选中项位于行中时，优先保留 Finder 原生行为。
- 第一行第一个图标按 `←`，以及最后一行最后一个图标按 `→`，不得循环跳转。
- 不改变上下方向键、修饰键组合或其他 Finder 快捷键的原生行为。

### 1.2 特殊场景

需要研究并尽可能支持：

1. 按名称、日期、种类等排序。
2. 按日期、种类等分组。
3. 排列方式为“无”的自由摆放模式。
4. Quick Look 空格预览打开时的导航。
5. Finder 窗口大小变化。
6. 大量文件与滚动区域。
7. 外接显示器及显示缩放变化。

### 1.3 非目标

不开发独立文件管理器，不修改 Finder 程序或系统文件，不注入 Finder 进程，不使用私有 API，不增加账号、云同步、自动更新框架、遥测、广告或付费功能。

第一版不开发多页面设置、快捷键自定义、主题切换、插件系统。

## 2. Codex 执行协议

本任务书是执行要求，不是仅供参考的产品说明。

### 2.1 执行顺序

必须严格按照以下顺序推进：

1. 检查本机开发环境。
2. 创建最小工程和独立 AX 探查工具。
3. 探查 Finder 的真实辅助功能结构。
4. 验证读取与修改选中项的可行性。
5. 实现导航算法和测试。
6. 实现键盘监听与运行时状态管理。
7. 实现 SwiftUI 单页菜单栏 GUI。
8. 完成跨系统测试。
9. 完成安装、签名、打包和发布准备。

禁止在 AX 验证完成之前，将预想的 Finder 层级或属性可写性当成已确认事实。

### 2.2 Codex 可自主执行的操作

- 检查开发环境与项目文件。
- 创建和修改当前项目内的代码、测试和文档。
- 编译、静态检查、运行单元测试。
- 执行不涉及真实键盘输入的探查。
- 生成脱敏测试数据。
- 维护阶段进度和测试报告。

### 2.3 需要用户确认的操作

- 触发真实系统键盘模拟测试。
- 修改辅助功能或输入监控权限。
- 创建、导入、删除或更换代码签名证书。
- 安装登录项或改变系统级持久配置。
- 删除项目目录以外的文件。
- 执行不可逆的 Git 操作。
- 向远程仓库推送代码、创建 Release 或公开发布构建。

Codex 不得尝试绕过系统安全授权，不得自动关闭 Gatekeeper 或 SIP。

### 2.4 阶段记录

维护：

```
docs/agent-progress.md
docs/ax-findings.md
docs/test-report.md
docs/compatibility.md
docs/release-checklist.md
```

每个阶段记录：

- 已完成的工作。
- 实际执行的命令。
- 编译及测试结果。
- 已验证的系统行为。
- 未解决问题。
- 下一阶段的前置条件。

不得把推测、模拟测试或尚未执行的操作标记为真实验证通过。

## 3. 开发环境与系统支持

### 3.1 系统范围

| 系统               | 支持策略             |
| ---------------- | ---------------- |
| macOS 15 Sequoia | 最低支持版本           |
| macOS 26 Tahoe   | 重点适配版本           |
| macOS 27         | 目标兼容版本，实际验证后正式支持 |

必须明确区分：

- 已编译。
- 已启动。
- 已完成 GUI 验证。
- 已完成 Finder AX 验证。
- 已通过全部核心导航测试。

macOS 27 未具备相应测试环境时，不得声称正式兼容。

### 3.2 开发环境检查

Codex 首先执行：

```
sw_vers
uname -m
xcodebuild -version
xcode-select -p
swift --version
xcrun --show-sdk-version
```

确认当前 Xcode 和 SDK 是否满足开发要求。

如果缺少工具链，应报告缺失项目及安装建议，不擅自安装大型开发环境。

### 3.3 构建要求

- Xcode 原生工程。
- `MACOSX_DEPLOYMENT_TARGET = 15.0`。
- Release 目标为 Universal 2。
- SwiftUI 负责 GUI。
- 不引入第三方运行时依赖。
- 优先采用系统提供的原生控件和材质。

构建完成后使用 `lipo -info` 检查架构，使用 `otool` 检查部署目标与动态链接依赖。

## 4. 技术架构

### 4.1 主要技术

| 功能          | 技术                                |
| ----------- | --------------------------------- |
| 菜单栏 GUI     | SwiftUI `MenuBarExtra`            |
| 弹出界面        | `.menuBarExtraStyle(.window)`     |
| 配置保存        | `@AppStorage` / UserDefaults      |
| 登录启动        | `SMAppService.mainApp`            |
| 键盘事件        | Core Graphics `CGEventTap`        |
| Finder 辅助功能 | ApplicationServices `AXUIElement` |
| 权限检查        | Accessibility API 与系统权限机制         |
| 运行日志        | OSLog                             |
| 单元测试        | XCTest                            |
| 构建与发布       | Xcode、GitHub Actions              |

### 4.2 SwiftUI First 原则

优先使用 SwiftUI 实现所有 GUI。

原则上不使用：

- `NSStatusItem`
- `NSMenu`
- `NSPopover`
- 自定义 `NSWindow`
- `NSViewRepresentable`

只有实际验证发现 SwiftUI 无法满足必要的系统行为时，才允许引入最小 AppKit 桥接，并在文档中解释原因。

Core Graphics、ApplicationServices 和 ServiceManagement 不属于 AppKit，可正常使用。

### 4.3 工程结构

```
FinderWrap/
├── FinderWrap.xcodeproj/
├── FinderWrap/
│   ├── App/
│   │   ├── FinderWrapApp.swift
│   │   └── AppState.swift
│   ├── UI/
│   │   └── MenuBarView.swift
│   ├── Core/
│   │   ├── KeyboardMonitor.swift
│   │   ├── FinderAccessibility.swift
│   │   ├── NavigationEngine.swift
│   │   ├── NavigationModels.swift
│   │   ├── LayoutCache.swift
│   │   └── FinderContext.swift
│   ├── Services/
│   │   ├── PermissionService.swift
│   │   ├── LaunchAtLoginService.swift
│   │   └── DiagnosticService.swift
│   ├── Resources/
│   │   └── Assets.xcassets/
│   └── Info.plist
├── Tools/
│   └── FinderAXProbe/
├── Tests/
│   ├── NavigationEngineTests.swift
│   ├── LayoutTests.swift
│   ├── KeyboardPolicyTests.swift
│   ├── FinderIntegrationTests.swift
│   └── Fixtures/
│       ├── macOS15/
│       ├── macOS26/
│       └── macOS27/
├── scripts/
│   ├── build.sh
│   ├── test.sh
│   ├── package.sh
│   ├── install.sh
│   └── uninstall.sh
├── .github/
│   └── workflows/
│       └── ci.yml
├── docs/
│   ├── agent-progress.md
│   ├── ax-findings.md
│   ├── test-report.md
│   ├── compatibility.md
│   └── release-checklist.md
├── README.md
├── README_EN.md
├── LICENSE
└── .gitignore
```

该结构是建议结构。Codex 可以适度精简，但必须保持 GUI、导航算法、系统接口和测试相互解耦。

## 5. 第一阶段：Finder AX 探查

### 5.1 目标

先建立 Finder 实际界面结构与辅助功能行为的证据。

不得直接假定 `AXChildren` 顺序等于 Finder 视觉顺序，也不得假定 `AXSelectedChildren` 在所有视图中可写。

### 5.2 探查内容

独立探查工具应读取：

- Finder 进程 PID。
- 当前前台应用及焦点窗口。
- Finder 主窗口。
- 图标视图容器及其 AXRole、AXSubrole。
- 图标元素的位置、尺寸、角色。
- 当前选中图标。
- 选中属性的可写性。
- 分组容器结构。
- 滚动区域与可见元素。
- Quick Look 打开时的窗口及焦点变化。

使用 `AXUIElementCopyAttributeValue`、`AXUIElementCopyAttributeNames`、`AXUIElementIsAttributeSettable` 等公开接口。

对 AX 通信设置合理超时，并记录错误码与调用耗时。

### 5.3 输出

每次探查保存脱敏 JSON，包含：

```
{
  "osVersion": "detected-at-runtime",
  "finderVersion": "detected-at-runtime",
  "scenario": "normal-icon-view",
  "attributes": [],
  "selectedItems": [],
  "visibleItems": [],
  "errors": [],
  "measurements": {}
}
```

不得默认记录真实文件名、完整路径或私人文件夹信息。

### 5.4 探查场景

至少覆盖：

1. 普通图标视图。
2. 列表视图和分栏视图。
3. 按名称排序。
4. 按日期或种类分组。
5. 排列方式为“无”。
6. 单选与多选。
7. Quick Look 打开。
8. 窗口缩放。
9. 大量文件和滚动。
10. Finder 重启。
11. 桌面图标与普通 Finder 窗口的区别。

### 5.5 阶段门槛

进入正式导航实现前，必须证明：

- 能可靠定位目标图标视图。
- 能读取当前单选图标。
- 能读取足够的布局信息。
- 能确定图标间的目标导航关系。
- 能通过 AX 安全修改选中项，或找到经过验证的公开 API 替代方案。

若无法满足，停止核心开发，输出可行性报告，不得假装功能已经实现。

## 6. 第二阶段：导航引擎

### 6.1 设计原则

导航引擎必须独立于 SwiftUI 和 Finder AX 接口。

建议将其设计为纯 Swift 逻辑模块，输入布局快照、选中项及方向，输出导航决策。

导航引擎本身不直接操作 Finder。

### 6.2 数据模型

建议包含以下概念：

```
enum NavigationDirection {
    case left
    case right
}

enum LayoutMode {
    case ordered
    case grouped
    case freeArrangement
    case unsupported
}

enum NavigationDecision {
    case passThrough
    case selectTarget(ItemID)
}
```

其中 `ItemID` 是内部稳定标识，不应简单使用文件名。相同名称、重复 AX 属性或元素重新加载都可能导致标识冲突。

需要在实际 AX 探查后确定身份匹配方式，并提供缓存失效机制。

### 6.3 普通图标视图

处理原则：

- 只有在确认跨行时才接管方向键。
- 行中方向键由 Finder 原生处理。
- 左右跨行必须严格符合视觉阅读顺序。
- 不允许在最后一个图标之后自动回到第一个。
- 不允许在第一个图标之前自动跳到最后一个。

需要建立原生行为对照测试，确认 Finder 原本正常的导航没有被改变。

### 6.4 自由排列模式

Finder 排列方式为“无”时，不能依赖内部元素顺序。

应使用图标坐标构建阅读顺序。

算法要求：

1. 读取可见图标的位置及尺寸。
2. 根据纵向中心、图标高度及间距进行行聚类。
3. 将行按照屏幕视觉顺序排列。
4. 每行图标按照横向坐标从左到右排列。
5. 根据当前选中项计算前后邻居。
6. 对坐标异常、重叠或不确定的布局进行安全降级。

自由排列模式下，已确认布局中的左右方向键原则上由 FinderWrap 接管。

但必须注意：坐标排序得到的是 FinderWrap 定义的视觉阅读顺序，不一定等于 Finder 的原生顺序。

### 6.5 分组模式

分组布局应包含：

- 分组标识。
- 分组视觉顺序。
- 组内图标顺序。
- 组首与组尾。
- 当前可见范围。

组内行中导航优先保持原生行为。

组尾按 `→`，在目标明确时进入下一组首项；组首按 `←`，在目标明确时进入上一组尾项。

不能因为 AX 树存在多个子容器，就直接认为它们代表 Finder 的视觉分组。

### 6.6 Quick Look

Quick Look 期间需要单独验证：

- Finder 主窗口是否仍可访问。
- 当前预览对应的 Finder 选中项。
- 焦点是否转移至预览窗口。
- 修改 Finder 选中项能否更新预览。
- 方向键是否被 Quick Look 自身使用。

只有在可以可靠区分 Finder 导航与预览窗口操作时，才允许接管按键。

不得干扰 Quick Look 的关闭、空格操作或其他原生快捷键。

### 6.7 多选策略

检测到多个文件被选中时，所有方向键原样放行。

第一版不实现多选范围扩展，也不修改 Shift、Command、Option 等修饰键的行为。

### 6.8 滚动边界

Finder 可能只通过 AX 暴露当前可见区域附近的图标。

当导航目标不在已加载范围时：

- 不凭空构造目标。
- 不强制滚动到未知位置。
- 不依赖不可验证的文件列表顺序。
- 允许 Finder 原生处理。
- 安排后续缓存刷新。

如果实测发现原生处理也无法正确跨越边界，应记录为已知限制，而不是声明已经解决。

## 7. 第三阶段：键盘事件处理

### 7.1 监听范围

使用 `CGEventTap` 监听键盘事件。

只关注左右方向键：

```
let leftArrowKeyCode: CGKeyCode = 123
let rightArrowKeyCode: CGKeyCode = 124
```

仅在以下条件同时满足时考虑接管：

- FinderWrap 已启用。
- 事件来自有效的用户图形会话。
- Finder 是目标活动应用，或处于已验证的 Quick Look 场景。
- 当前焦点对应可支持的图标视图。
- 没有不允许的修饰键。
- 当前只有一个选中项。
- 导航缓存有效。
- 目标图标明确。

其他事件原样放行。

### 7.2 修饰键处理

不得干预以下组合：

- Command + 方向键。
- Option + 方向键。
- Shift + 方向键。
- Control + 方向键。
- Function 或其他系统级组合。

应检查事件标志位，并验证不同键盘、输入法及辅助功能设置下的行为。

### 7.3 事件原子性

这是关键技术要求。

键盘事件拦截与 AX 选中项修改必须协调处理。

禁止简单采用以下不可靠流程：

```
拦截按键
    ↓
异步修改选中项
    ↓
不检查结果
```

必须研究并验证以下策略：

- 同步提交是否能满足响应预算。
- 已缓存目标能否降低 AX 调用耗时。
- AX 写入失败后如何避免永久丢失输入。
- 是否需要经过验证的事件重放机制。
- 重放事件如何防止再次被自身拦截。
- 快速连续按键时如何避免状态错乱