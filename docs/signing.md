# 固定签名

bundle ID 保持 `dev.finderwrap.finderwrap`。`config/signing.json` 固定公开证书指纹，`scripts/signing-policy.py` 校验证书和 designated requirement。CI 仅在受信任的 main push / workflow_dispatch 导入既有证书；私钥和密码仅来自 GitHub Actions Secrets，临时钥匙串在结束时清理。不要将证书私钥、密码、钥匙串或本机诊断备份提交到仓库。

1.0.8 预览包继续使用既有身份，不创建证书、不悄悄改用 ad-hoc。当前没有 Developer ID 公证。固定证书有助于后续升级保持身份，但无法保证从不同签名的旧包迁移无需授权，也不保证 macOS 永远保留权限。

构建：`bash scripts/build.sh Release`。打包：`bash scripts/package.sh --fixed`。校验：`python3 scripts/signing-policy.py verify /path/to/FinderWrap.app`。签名包不再包含 Automation Finder entitlement，只用辅助功能与输入监控；权限仍由用户在系统中决定。
