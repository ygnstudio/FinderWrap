# 当前应用核心（1.0.6）

- `Sources/FinderBridge/AX.swift`：有界 AX 读取助手。
- `Sources/FinderBridge/GridModel.swift`：网格模型与纯函数换行判决（含文档首尾循环、画廊单行循环）。
- `Sources/FinderBridge/GridReader.swift`：后台布局抓取、桌面/Quick Look 场景识别、实机诊断。
- `Sources/FinderBridge/FinderWrapMonitor.swift`：事件 tap、按键判决、写入回读、列表原生切项、诊断。
- `Host/CandidateApp.swift`：SwiftUI 宿主与场景开关。

完整构建入口为 `bash scripts/build.sh Release`；核心测试为 `swift test --package-path Rebuild`。测试不访问 Finder、不发真实按键、不改权限。
