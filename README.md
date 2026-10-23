# gifferent

a fast, native GIF maker for macOS. summon capture, record while using your Mac, then copy, save, or compress locally.

the app and its test suite are being built in tested iterations. capture selection has a permission guide, configurable global shortcuts, and a display, window, and region selection overlay. recording components are being integrated, but recording and GIF export are not available yet.

the source license is [AGPL-3.0-or-later](LICENSE). [third-party notices](THIRD-PARTY-NOTICES.md) track bundled dependencies and tools.

- [agent hub](AGENTS.md)
- [vision](vision.md)
- [brand direction](brand.md)
- [first release scope](mvp.md)
- [architecture and experiments](architecture.md)
- [definition of done](definition-of-done.md)
- [decisions and open questions](decisions.md)
- [delivery plan](delivery-plan.md)

## local development

use Xcode 26.2 (build 17C52) for the current foundation. open `gifferent.xcodeproj` with the shared `gifferent` scheme, or run:

```sh
bash Scripts/check-toolchain.sh
python3 Scripts/check-docs.py
bash Scripts/format-check.sh
bash Scripts/lint.sh
bash Scripts/build.sh
bash Scripts/test-unit.sh
bash Scripts/test-ui.sh
```

the build and test scripts write logs and `.xcresult` bundles under `.build/ci/`. UI tests need a macOS session that permits Xcode automation. deterministic UI tests open the production SwiftUI menu content in a debug-only test window and use a synthetic selection display without requesting screen access. actual menu bar clicking, screen permission, shortcut delivery, and overlay interaction remain real-Mac acceptance checks. recording, export, and release checks are later iterations in [delivery-plan.md](delivery-plan.md).
# gifferent
