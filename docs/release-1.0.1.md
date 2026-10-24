# FinderWrap 1.0.1 · 真实方向键修复

2026-10-24，build 3。以下安装验收及哈希对应最初的本地 ad-hoc 包。仓库保持私有；后续固定证书 CI 流程见 [签名说明](signing.md)，远端构建以对应提交的 [Actions 记录](https://github.com/ygnstudio/FinderWrap/actions) 为准。未创建 Release 或公证。

## 原因与修改

用户在已授权 Synthetic 日期分组视图使用真实键盘，1.0.0 两项权限和运行状态均为 true，却没有确认换行。只读探针测得普通左右键（123/124）的 flags 为 `0xa00100`，包含 function 位；旧 KeyboardPolicy 把该位当成按住 Fn，提前放行所有普通左右键。旧的三处实验按键投递清空 flags，导致此前模拟输入通过而物理键盘失效。

1.0.1 不再以 function 元数据判断 Fn 按住；独立查询虚拟键 63 的系统状态，并始终放行其他组合键、Home/End 和非左右键。此次用户键盘的 Fn 组合被转换成 Home/End（115/119），Fn 状态查询均为 false，因此不声称该键盘观测到 Fn-down；它通过非左右键规则保持原生行为。

复制诊断增加左右键计数/标记、Fn 状态、最后决策和上一次 Finder 采集结果。即使打开面板使 Finder 不再前台，仍能区分此前布局识别和输入过滤问题。没有记录文件名、路径或输入文本。

## 验证

- 新回归先在旧策略运行，左右两个断言均失败；修复后完整 48 项 XCTest 通过，并加入用户实测的精确标记。
- KeySmoke、KeyBurst 和 QuickLookSmoke 均不再清空导航键的 function/numericPad 标记。它们仍是合成事件，不能冒充物理键盘验证。
- Release 构建成功；arm64/x86_64；DMG 完整性、严格验签及 DMG/ZIP 应用内容一致性检查通过。
- 已将包内应用安装到 /Applications，二进制读回与包一致，旧版完整保存在项目 build/installed-backups 中。
- 替换后用户诊断显示 Accessibility=false、Input monitoring=false、Running=false：本地签名变化使旧授权失效。随后用户恢复授权，实际安装版真实键盘换行已经用户确认。期间出现两次自动暂停，后续恢复情况见下文；不能据编译/单测声明全部稳定性问题已解决。

证据：[真实按键及回归](evidence/2026-10-24-hardware-arrow-regression.json)。

## 安装包

- FinderWrap-1.0.1-local-universal.dmg：558199 字节，SHA-256 `b31cd129a60ebefbf623c345b7f714cbd85cc42a196da68508bf5274b792580c`
- FinderWrap-1.0.1-local-universal.zip：509190 字节，SHA-256 `149acde650b0bbf0f85687e6b6ba731ca82edad08f5e7756386099d9f8d86bfd`

旧 1.0.0 包保留用于对照，不再推荐使用。更新这种本地签名应用后，若系统设置仍显示旧开关开启，但应用诊断为 false，需为更新后的应用重新授权并按系统提示重启，再开启导航。保持现有安全设置，不关闭 Gatekeeper 或 SIP。

## 升级授权失效的核对

`codesign -d -r-` 已分别读取旧版备份与新安装版：两者的 designated requirement 都是各自二进制的 cdhash，且新旧 hash 不同。这说明 ad-hoc 更新无法满足旧版本的代码身份要求，并非单凭“无证书”推测。Apple [TN3127](https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements) 明确说明 ad-hoc 代码身份绑定具体构建，隐私授权以代码身份核验更新。长期升级应使用固定签名身份并保持 designated requirement 稳定；最初的故障修复没有创建、导入或更换签名证书。后续 CI 的默认打包已改为强制固定证书，禁止自动降级。

## 自动暂停调查与本轮结束状态

用户确认换行生效后报告开关自动关闭。22:06:04.833 和 22:06:15.595 的产品日志均为“Indeterminate AX selection result”；源码对应首次未确认后停止监听、AppState 关闭导航。故障前 TCC 明确允许辅助功能访问，因此不将这次现象归为权限丢失。旧日志未记录具体 AX 写入错误或读回分类，底层原因仍未知。

临时退出安装版，仅在授权脱敏目录运行带取证的诊断宿主：13 次合成跨行、用户 5 次物理跨行事务均立即读回目标；用户回复“这次持续正常”。随后停止诊断宿主，重新启动同一已授权 1.0.1，包体与签名未改变；安装版 15 次合成选择转换通过，没有新增暂停错误。用户再次用真实键盘复测，回复“没问题了”。

本轮没有为自动暂停修改产品代码、延长超时、去除保护或再次替换应用。当前恢复使用，不声称间歇性 AX 原因已永久修复。结束时仅一个安装版进程，导航开启，所有临时按键诊断宿主已停止。详见 [调查证据](evidence/2026-10-24-auto-pause-investigation.json)。
