# FinderWrap

Arrow-key wrapping for Finder icon views. Current development build: **2.0.0 Preview 1 (200002)**, Apple Silicon, deployment target macOS 13.

The rebuilt application works with ordinary folders without a test-directory requirement. It starts paused and needs Accessibility, Input Monitoring, and Automation for Finder. It enhances confirmed visible row boundaries for a single selection, preserving native interaction elsewhere. Runtime failures preserve the requested toggle and show a separate recovery state.

Quick Look, Desktop, off-screen targets, and uncertain group boundaries currently remain native. macOS 13/14/15/27 input compatibility is not yet verified. This is a preview, not a claim of universal layout support.

Run `bash scripts/test.sh` and `bash scripts/build.sh Release`. The `Rebuild/` package and host are the sole current implementation. Installation artifacts are signed by the existing pinned certificate in trusted main-branch GitHub Actions runs. Stable Releases and Homebrew remain at 1.0.3. No Apple notarization is provided; an old ad-hoc installation may need permission approval once when migrating to the fixed identity.

See [Chinese documentation](README.md), [installation](docs/installation.html), [architecture](docs/design.md), and [testing](docs/testing.md).
