# FinderWrap

Row-wrap helper for Finder icon view left/right arrow keys. **Current version: 1.0.4 (build 7).**

The previous core invalidated the prepared layout on every selection change, so a normal key cadence rarely found the app "ready". 1.0.4 keeps a background grid snapshot, reads the live selection once per key, and uses permissive visible-row geometry.

Menu-bar only: click the status item for the switch, permission state, view options, diagnostics and quit.

## Behaviour

- Icon views: wrap at row ends, cyclically at the document ends; single and multiple selection.
- Covered: ordinary/search/smart folders, grouped icons, desktop icons, Quick Look (Finder stays frontmost while the preview window owns focus).
- Gallery view: cycles at both ends.
- List view: left/right step to the previous/next row (separate switch, off by default). **List first/last cycling is not supported yet** — Finder 26 clears the selection when a non-visible row is written through AX.
- Column view, rename and search fields stay native.

Permissions: **Accessibility** and **Input Monitoring** only. Apple Events automation is no longer required.

## Development

```sh
bash scripts/test.sh
bash scripts/build.sh Release
```

See [architecture](docs/design.md), [compatibility](docs/compatibility.md) and [testing](docs/testing.md).
