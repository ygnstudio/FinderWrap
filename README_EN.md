# FinderWrap

A native macOS menu bar app that adds left/right row wrapping to Finder icon views. Built with SwiftUI `MenuBarExtra`, public Accessibility APIs and `CGEventTap`. No third-party runtime, accounts, networking or telemetry.

**Current version: 1.0.1.** Universal 2 for Apple Silicon and Intel, with a macOS 15 deployment target. Source is MIT licensed. Installation packages use a fixed FinderWrap self-signed certificate; they are not Developer ID signed or Apple notarized.

## Install and update

```sh
brew install --cask ygnstudio/ygn/finderwrap
brew update
brew upgrade --cask ygnstudio/ygn/finderwrap
```

Alternatively, download the DMG or ZIP from [Releases](https://github.com/ygnstudio/FinderWrap/releases). If you already installed manually, quit and back up that copy before migrating. Do not force an overwrite of a running app.

Grant Accessibility and Input Monitoring in System Settings, then enable navigation. A fresh installation starts paused; launch at login is off by default. If macOS blocks the first launch, verify the download source and checksum, then use the system's Open Anyway option. Homebrew preserves system security checks.

Moving from an older ad-hoc build to the fixed certificate may require one-time reauthorization. Subsequent packages must retain the same certificate and designated requirement. Actual permission retention across upgrades still requires testing on the target machine.

## Behavior

At a row's right edge, Right selects the next row's first item. At its left edge, Left selects the previous row's last item. There is no end-to-start cycle. Interior movement, Up/Down, modified keys and multiple selection retain Finder behavior, including its behavior on incomplete final rows.

Confirmed ordinary icon grids and tested date-group boundaries are supported. Quick Look, desktop, list/column views, free arrangement, incomplete layouts, offscreen targets and folders over 160 items retain native behavior.

Selection is written synchronously and read back. A confirmed target consumes the original key; an explicit rejection with the original selection unchanged passes it through. An uncertain result consumes that one key and pauses navigation to avoid duplicate movement from a late AX write. Later keys use Finder's native behavior. An intermittent pause was observed and did not recur after restarting the same installed app; its underlying AX cause remains unresolved.

## Build and package

```sh
bash scripts/build.sh Debug
bash scripts/test.sh
bash scripts/build.sh Release
bash scripts/package.sh --fixed
```

Products are in `build/DerivedData/Build/Products/`; packages and checksums are in `build/packages/`. Fixed packaging requires the certificate pinned in [the signing policy](config/signing.json). It fails if the identity is missing or mismatched. Contributors can build unsigned products; local experiments may explicitly use `--ad-hoc`, which is forbidden in CI and is unsuitable for preserving an installed version's permissions.

The private signing key is not part of the repository. Main-branch signing uses Actions Secrets and a temporary keychain; pull requests do not receive the secrets. CI verification archives are marked unsigned and must not replace an installed app. See [signing and distribution](docs/signing.md).

`install.sh` defaults to a dry run and refuses replacement. `uninstall.sh` retains preferences and permission records. Experimental input helpers are not packaged in the app and require explicit authorization; all recorded navigation tests used synthetic directories.

## Verification and limits

48 XCTest cases cover navigation, cache behavior, key flags, uncertain/late writes and the stop barrier. Five packaging tests check signing guards. Local and CI packages with different binaries were verified to retain the same signing identity. These checks do not replace installed-app or permission-migration testing.

Main runtime evidence comes from macOS 26.6.2 / Finder 26.4 on Apple Silicon. Other macOS versions, Intel GUI behavior, physical long presses, more layouts, input methods and login-item lifecycle remain incompletely tested.

Diagnostic output excludes filenames, paths, selected text and keyboard text. See the [test report](docs/test-report.md), [compatibility matrix](docs/compatibility.md), [runtime design](docs/runtime-design.md) and [release checklist](docs/release-checklist.md).

Source and downloads: [ygnstudio/FinderWrap](https://github.com/ygnstudio/FinderWrap). Homebrew cask: [ygnstudio/homebrew-ygn](https://github.com/ygnstudio/homebrew-ygn).
