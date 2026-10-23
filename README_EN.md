# FinderWrap

A native macOS menu bar utility that adds left/right row wrapping to Finder icon views. Built with SwiftUI `MenuBarExtra`, public Accessibility APIs and `CGEventTap`. No third-party runtime, accounts, networking or telemetry. Deployment target: macOS 15; Release: Universal 2.

**Version 0.1.0 is a local preview, not a production release.** Core navigation has run against synthetic folders on macOS 26.6.2 / Finder 26.4. Installed-app menu registration has been repaired; scoped row/group wrapping and paused native behavior were verified. AX failure atomicity, other macOS versions and Intel runtime compatibility remain unverified.

## Behavior

At a row's right edge, Right selects the next row's first item. At its left edge, Left selects the previous row's last item. There is no custom end-to-start cycle. On an incomplete final row, Finder may natively select an item farther right on the preceding row; this version preserves that behavior. Interior movement, Up/Down, modified keys and multiple selection pass through.

The runtime recognizes confirmed ordinary icon grids and tested date-group boundaries. Quick Look, desktop, list/column views, free arrangement, incomplete layouts, offscreen targets and folders over 160 items retain native behavior. Native movement can still stop at these unsupported boundaries.

A key is consumed only after a synchronous AX write and a readback matching the target. An unknown result pauses interception and passes the original event; a write that actually succeeded despite failed readback can cause extra movement. This remains a release blocker; see [runtime design](docs/runtime-design.md).

## Build and package

```sh
bash scripts/build.sh Debug
bash scripts/test.sh
bash scripts/build.sh Release
bash scripts/package.sh
```

Products are in `build/DerivedData/Build/Products/`. The local ZIP and SHA-256 file are in `build/packages/`. Packaging uses ad-hoc signing, without accessing certificates. It is not Developer ID signed or notarized.

`install.sh` defaults to a dry run; `--apply` copies to a new destination and refuses replacement. `uninstall.sh` defaults to a dry run; after login launch is disabled and the app quits, `--apply` moves the app to Trash while retaining preferences and permission records. Neither script grants permissions or registers login items.

The app starts paused. Grant Accessibility and Input Monitoring in System Settings, then enable navigation. Login at launch requires an explicit user action.

For this task, installation and permissions were authorized, but all navigation testing remains restricted to two synthetic folders. Start the installed app from the project root with:

```sh
open -n ~/Applications/FinderWrap.app --args --test-fixtures "$PWD"
```

Test mode accepts only `Tests/Fixtures/Synthetic` and `build/Fixtures/Large`, does not persist the navigation switch, and disables login launch.

## Evidence and limitations

36 XCTest cases passed. Scoped runtime tests demonstrated ordinary row wrapping, date-group crossing, 12 alternating boundary keys, the first-item boundary, native Up/Down, Quick Look pass-through and 36-item multiple selection. Separately, the installed app confirmed 16 wraps, a 12-key burst, Up/Down, Quick Look and a paused native comparison. Cross-version and fault-injection acceptance remain pending.

The standalone read-only probe saves roles, geometry, booleans, opaque snapshot IDs, errors and timing, not filenames, paths, titles or selected text. Input-generating experimental helpers are not packaged in the app and require explicit user authorization.

See the [test report](docs/test-report.md), [AX findings](docs/ax-findings.md), [compatibility matrix](docs/compatibility.md), [menu registration diagnosis](docs/menubar-diagnosis.md), and [release checklist](docs/release-checklist.md).

MIT licensed. Source is hosted in the private [ygnstudio/FinderWrap](https://github.com/ygnstudio/FinderWrap) repository. See [GitHub Actions](https://github.com/ygnstudio/FinderWrap/actions) for remote checks. Source hosting and CI builds do not constitute a production release; no GitHub Release or public binary upload has been made.
