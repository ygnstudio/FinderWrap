# 固定签名与 CI 构建

本项目使用固定证书身份生成本地分发安装包。它不等于 Developer ID 签名或苹果公证。首次从旧 ad-hoc 包切换到固定证书，仍可能需要重新授予辅助功能和输入监控权限；后续更新必须沿用相同证书、应用标识和 designated requirement（DR）。系统权限是否保留仍需在实际安装环境验收。

## 身份约束

`config/signing.json` 只保存应用标识、证书 SHA-1 和 SHA-256，不保存私钥。未配置指纹时，默认打包立即失败。固定模式按 SHA-1 精确选择证书，签名 DR 同时约束 `dev.finderwrap.finderwrap` 和叶证书指纹。签名后分别检查 arm64/x86_64 的严格验签、DR 和实际叶证书 SHA-256，不能仅靠名称相同就通过。

证书和私钥只能初始化一次并妥善备份。不得每次构建重新生成，不得自动退回 ad-hoc，也不得将 DR 放宽为只有 bundle identifier。证书过期、丢失或主动更换时，要明确安排身份迁移；本地证书模式不承诺跨证书保留授权。

## GitHub Actions

推送或 PR 运行 58 项 XCTest、Universal 2 Release 构建及打包防护测试。每次上传明确标为 `verification-unsigned` 的验证归档，**不要用它覆盖已安装应用**。

仅 `main` 的 push / workflow_dispatch 且仓库变量 `FINDERWRAP_SIGNING_ENABLED=true` 时运行固定签名步骤。须先完成证书指纹配置，并设置两个仓库 Actions Secrets：

- `FINDERWRAP_CERTIFICATE_P12_BASE64`：同一份带私钥的加密 PKCS#12，Base64 编码。
- `FINDERWRAP_CERTIFICATE_PASSWORD`：该 PKCS#12 的随机密码。

签名步骤只在临时 runner 钥匙串导入此证书，私钥授权限于 codesign / Apple 工具；暂时加入钥匙串搜索列表，完成或失败均恢复列表并清理临时钥匙串和 P12，不添加系统证书信任。密钥不进入源码、构建日志或上传目录。Actions 固定到已核对的提交，checkout 不保留 Git 凭据，工作流只有 contents:read。配置缺失、证书不匹配或签名校验失败时整次构建失败，不上传安装包。

`fixed-signature` artifact 包含 DMG、ZIP、SHA-256 和签名清单。经下载验签后，将同一份文件发布至 FinderWrap Releases，并更新 `ygnstudio/homebrew-ygn` 中 cask 的版本和 SHA-256。CI 本身不自动创建 Release、不修改 TCC、不操作 Finder 或安装应用；Homebrew 不重新编译或重新签名。

## 本地打包

```sh
bash scripts/build.sh Release
bash scripts/package.sh --fixed
```

本地已导入同一固定证书时可直接使用；独立钥匙串通过 `FINDERWRAP_SIGNING_KEYCHAIN` 指定。旧的无证书实验路径只能显式执行 `bash scripts/package.sh --ad-hoc`，CI 禁用此路径。两类包有不同文件名，均拒绝覆盖既有产物。

固定证书首次启用前应完成两个不同构建的交叉 DR 校验，并检查从 CI 下载的实际包体。DR 相同是升级身份验证证据，不能替代目标机器的 TCC 权限保留验收。

## 本次启用证据

用户已批准建立专用证书并配置仓库 Actions Secrets，随后批准公开源码和安装包。公开指纹固定于配置文件；加密 P12 在维护者本机独立保存，密码保存在用户钥匙串，不随仓库交付。仓库公开不会将 Secrets 写入源码；签名仍仅限可信 main 构建，PR 不读取密钥。证书有效期为 10 年，丢失或到期前须另行安排迁移。

本地已验证固定签名包、不同 build 元数据候选包的 DR 一致性和交叉验证，以及同 bundle identifier 的 ad-hoc 包被拒绝。见 [签名证据](evidence/2026-10-24-fixed-signing.json)。当前已安装的 ad-hoc 应用未被替换，因此尚未执行首次证书迁移或后续 TCC 保留验收。

参考：[Apple TN3127](https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements)、[Apple TN2206](https://developer.apple.com/library/archive/technotes/tn2206/_index.html)、[GitHub 签名证书配置](https://docs.github.com/en/actions/how-tos/deploy/deploy-to-third-party-platforms/sign-xcode-applications)。
