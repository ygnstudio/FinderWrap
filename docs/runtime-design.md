# 运行时设计与边界

## 分层

`NavigationEngine` 只处理不可变布局快照。按纵向中心聚类行、按 x 坐标排序；要求唯一标识、完整数据、有效且不重叠的坐标和明确的组顺序。快照内标识与代际绑定，不用文件名充当身份。

`FinderAccessibility` 定位当前 Finder 标准窗口及焦点 `IconView`，读取真实 section、包装元素和图像。日期分组要求实际观察到的标题签名（一个 AXStaticText 和一个 AXButton），不以“有多个容器”推断分组。自由排列未获得可靠判别信息，运行时保持不支持。

`LayoutCache` 用锁保护不可变快照，350 ms 后过期。失效时递增 epoch，旧后台刷新不能覆盖新的失效状态。进程、窗口、焦点、滚动视口、图标坐标、section 数量、选择状态在写入前重新检查；不把缓存中的选中项当作当前选中项。

`KeyboardMonitor` 使用专用线程和 CFRunLoop 承载 session event tap。布局在工作队列每 150 ms 刷新，最多 160 项/24 组。AX 数组分页按实际返回数量推进，每页最多 20 项；缺失、失效引用、截断和选择不一致均放行。

## 输入协调

1. 非左右键、Shift/Control/Option/Command/Fn/Help 组合直接放行并使缓存失效。Caps Lock、数字键盘以及方向键自带的 function 标记不作为拒绝条件。Fn/Globe 按住状态单独通过 CGEventSource.keyState（虚拟键码 63，session / HID 状态）检查；Home/End 等系统转换后的键码始终放行。不能要求 raw flags 等于零，也不能将 maskSecondaryFn 等同于物理 Fn 按住。
2. 验证用户图形会话、前台 Finder、单选、同一窗口/焦点/几何以及新鲜缓存。
3. 引擎仅对明确的跨行/跨组返回目标。首尾、行内和不确定情况放行。
4. 同步写集合 `AXSelectedChildren`，立即读回。目标已选则消费事件；只有明确的参数/能力/权限拒绝且原项仍选时放行。通信失败、成功返回但原项未变、其他选择或读回不可用均暂停，并抑制本次原键。
5. tap 被系统禁用时停止，不自动反复重新启用。用户可检查诊断后手动重启监听。

产品没有“先吞键、后台异步写 AX”的路径，也没有未经验证的事件重放。实验工具的 CGEvent 投递代码不进入产品。

## 不确定写入的处理契约

AX 写入与 CGEventTap 返回值不是同一个系统事务。消息超时不是拒绝；此时即使读回原项，Finder 端仍可能稍后应用请求。1.0.0 不再把这类结果视为“没有写入”，也不把原按键再交给 Finder，从而消除本应用主动追加一次原生移动的路径。

结果分三类：读回目标为 committed；明确拒绝且读回原项为 unchanged；其余为 indeterminate。明确拒绝仅包含 illegalArgument、attributeUnsupported、invalidUIElement、notImplemented、apiDisabled；通用 failure、cannotComplete 和未知错误均不能证明拒绝。

不确定时停止监听，面板提示检查选中项。单次移动可能未完成，后续输入由 Finder 正常处理，用户可重新开启。这里保证本应用不会为一次不确定提交追加原事件，不承诺跨进程原子事务、撤销已排队请求、零丢键或物理长按的完整覆盖。

关闭导航通过 SelectionWriteGate 等待本进程正在执行的同步提交返回，关闭之后不再开始新写入。它不取消 Finder 端可能迟到的请求；旧监视器停止后再创建新实例。

回归测试先在旧实现复现“超时 + 原项读回被归为 unchanged”，修复后通过。注入测试覆盖已写入但读回丢失、迟到写入、明确拒绝、未知错误、故障后的 200 次输入和关闭期间的写入互斥。这些是可重复的适配层故障模拟，真实 Finder 挂起/通信超时与提交途中焦点变化仍需专项实机覆盖。

依据：Apple SDK `AXUIElement.h` 明确将 cannotComplete 描述为消息未能完成；系统级 messaging timeout 作用于本进程，不是取消协议。公开 API 没有提供将 AX 选择与 CGEventTap 返回值合并为事务的接口。

## 时间预算

进程 AX 默认消息超时 10 ms；后台采集软预算 150 ms，按键时实时验证软预算 20 ms，提交读回另有 15 ms 预算。它们在调用间检查，正在进行的 AX 调用可能超出截止时间，因此不是硬实时上限。

本机 12 次交替跨行加两次预热的最大回调为 23.123 ms；日期组间两次测试最大 34.082 ms。只代表这些样本，不是延迟分位数或极端负载保证。大型只读 probe 曾耗时 1.2–2.526 秒，该探查遍历没有进入键盘回调。

## 权限、生命周期及隐私

启动只检查 AX 和输入监控，不弹出授权请求。测试模式限制两个合成目录、默认暂停、不持久化启用状态、不允许注册登录项。普通模式通过用户开关保存期望启用状态；失去权限或监听失败后关闭开关，保留诊断提示。

OSLog 仅记录固定错误类别。复制诊断包含版本、权限、运行/缓存状态、最后一次 Finder 采集结果、左右键计数/标记及 Fn 状态、决策类别和最大回调耗时；打开面板导致当前采集变为 inactive 时，保留此前 Finder 采集结果供排障；不含文件名、路径、选中文本或键盘文本。测试状态文件含方向键编号/标志，仍不记录文本输入。

## 1.0.1 方向键回归

1.0.0 将 maskSecondaryFn 放在拒绝掩码中，旧 KeySmoke / KeyBurst / QuickLookSmoke 又将合成事件 flags 清空，因此无法发现真实导航键元数据被拒绝的问题。三处测试投递现已保留 function + numericPad；这是更接近硬件的合成事件，仍不替代物理键盘测试。回归先在原策略运行，左右两个断言均失败；修复后完整 48 项测试通过。

Apple 的 [function 文档](https://developer.apple.com/documentation/appkit/nsevent/modifierflags-swift.struct/function) 将方向键包括在 function 键范围内；[keyState 文档](https://developer.apple.com/documentation/coregraphics/cgeventsource/keystate(_:key:)) 描述独立虚拟键码的按下状态。
