#!/bin/bash
# Only called for trusted main builds. Never generate a replacement identity.
set -euo pipefail
set +x
cd "$(dirname "$0")/.."
[[ "${GITHUB_ACTIONS:-}" == true && "${GITHUB_REF:-}" == refs/heads/main ]] || exit 2
case "${GITHUB_EVENT_NAME:-}" in push|workflow_dispatch) ;; *) exit 2 ;; esac
python3 scripts/signing-policy.py identity >/dev/null
: "${FINDERWRAP_CERTIFICATE_P12_BASE64:?Missing fixed certificate secret}"
: "${FINDERWRAP_CERTIFICATE_PASSWORD:?Missing certificate password secret}"
: "${RUNNER_TEMP:?Missing runner temporary directory}"
umask 077
private_dir=$(mktemp -d "$RUNNER_TEMP/finderwrap-signing.XXXXXX")
keychain="$private_dir/signing.keychain-db"
cleanup() {
    if [[ -f "$private_dir/keychains.txt" ]]; then
        python3 - "$private_dir/keychains.txt" <<'PY' || true
import pathlib, shlex, subprocess, sys
previous = shlex.split(pathlib.Path(sys.argv[1]).read_text())
subprocess.run(['/usr/bin/security', 'list-keychains', '-d', 'user', '-s', *previous], check=True)
PY
    fi
    /usr/bin/security delete-keychain "$keychain" >/dev/null 2>&1 || true
    rm -rf "$private_dir"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
# Only a complete, successful snapshot is eligible for restoration.
/usr/bin/security list-keychains -d user > "$private_dir/keychains.pending"
mv "$private_dir/keychains.pending" "$private_dir/keychains.txt"
keychain_password=$(/usr/bin/openssl rand -hex 32)
printf '::add-mask::%s\n' "$keychain_password"
printf '%s' "$FINDERWRAP_CERTIFICATE_P12_BASE64" | /usr/bin/base64 --decode > "$private_dir/signing.p12"
unset FINDERWRAP_CERTIFICATE_P12_BASE64
/usr/bin/security create-keychain -p "$keychain_password" "$keychain"
/usr/bin/security set-keychain-settings -lut 3600 "$keychain"
/usr/bin/security unlock-keychain -p "$keychain_password" "$keychain"
/usr/bin/security import "$private_dir/signing.p12" -P "$FINDERWRAP_CERTIFICATE_PASSWORD" \
    -k "$keychain" -t cert -f pkcs12 -T /usr/bin/codesign >/dev/null
unset FINDERWRAP_CERTIFICATE_PASSWORD
rm "$private_dir/signing.p12"
/usr/bin/security set-key-partition-list -S apple-tool:,apple: -s -k "$keychain_password" "$keychain" >/dev/null
# --keychain alone does not make a new keychain visible to identity resolution.
python3 - "$private_dir/keychains.txt" "$keychain" <<'PY'
import pathlib, shlex, subprocess, sys
previous = shlex.split(pathlib.Path(sys.argv[1]).read_text())
subprocess.run(['/usr/bin/security', 'list-keychains', '-d', 'user', '-s', *previous, sys.argv[2]], check=True)
PY
export FINDERWRAP_SIGNING_KEYCHAIN="$keychain"
bash scripts/package.sh --fixed
