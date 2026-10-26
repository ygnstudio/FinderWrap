# 当前应用核心

这里包含 FinderBridge、SwiftUI 宿主及单元测试，是 2.0.0 Preview 1 的唯一应用实现。

默认读取当前普通 Finder 文件夹，不限制 Synthetic。测试宿主可以传入目录限制；正式启动不需要参数。应用初始暂停，异常运行状态与用户开关意愿分开。

完整构建入口为 `bash scripts/build.sh Release`；单独核心测试为 `swift test --package-path Rebuild`。安装包需要 `bash scripts/package.sh --fixed` 并通过固定证书策略校验。旧 1.x 工程不再参与 CI。

尚未完成的 Quick Look、桌面、屏外跨行及跨系统验证见 [兼容性](../docs/compatibility.md)。
