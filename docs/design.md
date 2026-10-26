# 2.0 预览架构

1.x 在每次方向键时重读全目录，并将运行 failure 保存为关闭偏好。新核心通过三个独立部分处理：官方完整选择、工作线程的可见布局、按键时的局部边界校验。

- Apple Events 只读取 selection、文件 URL、窗口 ID、目录与视图，不通过脚本写选择。窗口后续读取绑定同一 ID。
- AX 批量读取可见布局。完整选择与窗口前后两次读取一致，且观察器就绪后，才发布短期有效候选。
- 键鼠、焦点与布局变更使候选失效。采集最多一项在途，旧结果不能在暂停或上下文变化后重新激活。
- 按键回调验证源/目标与窗口身份，最多执行一次 AX 选择写入；不重放原键。不确定结果隔离会话，等待用户核对。
- 系统监听超时最多尝试恢复两次。系统停用、权限缺失和未知写入分别显示状态，不等同于用户关闭开关。
- 源项和目标必须属于当前官方 Finder 文件夹。可选测试目录限制始终保留。

AX / Apple Events 没有跨进程原子事务。不要同时使用另一工具通过自动化更改 Finder 选择；通知成功登记也不等于每次变更必然即时送达。

## 依据与已观察事实

本机 Finder.sdef 的 selection、URL、Finder window、current view 和 target 是脚本接口的直接依据。实际只读验证发现：分组图标的脚本 position 不提供可用几何；AX 可见选择也可能遗漏屏外多选，因此二者不能互相替代。

[Apple Finder Sync](https://developer.apple.com/library/archive/documentation/General/Conceptual/ExtensibilityPG/Finder.html) 仅提供菜单等扩展入口，不是持续键盘导航接口。[AX 通知](https://developer.apple.com/documentation/applicationservices/1462089-axobserveraddnotification) 需要处理不支持或注册失败。[AX 超时](https://developer.apple.com/documentation/applicationservices/1459345-axuielementsetmessagingtimeout) 不代表写入已取消。

参考过 [Hammerspoon eventtap](https://github.com/Hammerspoon/hammerspoon/blob/master/extensions/eventtap/libeventtap.m)、[Scroll Reverser](https://github.com/pilotmoon/Scroll-Reverser/blob/master/MouseTap.m) 的监听生命周期，以及 [Finer](https://github.com/taka0hn0/Finer) 的布局读取分工；它们不能代替本项目兼容性验收。
