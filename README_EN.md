# FinderWrap

Row-wrap helper for Finder icon view left/right arrow keys. **Current version: 1.0.6 (build 9).**

The previous core invalidated the prepared layout on every selection change, so a normal key cadence rarely found the app "ready". 1.0.6 keeps a background grid snapshot, reads the live selection once per key, and uses permissive visible-row geometry.

Menu-bar only: click the status item for the switch, permission state, view options, diagnostics and quit.

## Behaviour

- Icon views: wrap at row ends, cyclically at the document ends; single and multiple selection.
- Covered: ordinary/search/smart folders, grouped icons, desktop icons, Quick Look (Finder stays frontmost while the preview window owns focus).
- Gallery view: cycles at both ends; keys are taken over Finer-style (read AX selection, compute target, write selection and focus).
- List view: left/right step to the previous/next row (separate switch, off by default). **List first/last cycling is not supported** — the end keys are consumed so Finder never expands/collapses a folder, and writing an off-screen row clears the selection.
- Column view, rename and search fields stay native.

Permissions: **Accessibility** and **Input Monitoring** only. Apple Events automation is no longer required.

## Download

Latest stable release: **1.0.6 (build 9)** — [Releases](https://github.com/ygnstudio/FinderWrap/releases) or Homebrew:

```sh
brew tap ygnstudio/ygn
brew install --cask ygnstudio/ygn/finderwrap
```

1.0.6 ships Apple Silicon (arm64) only, macOS 13+. Intel users stay on 1.0.3.

## Development

```sh
bash scripts/test.sh
bash scripts/build.sh Release
```

See [architecture](docs/design.md), [compatibility](docs/compatibility.md) and [testing](docs/testing.md).
