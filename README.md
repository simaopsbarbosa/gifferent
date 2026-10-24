# gifferent

a fast, native GIF maker for macOS. summon capture, record while using your Mac, then copy, save, or compress locally.

the app and its test suite are being built in tested iterations. capture selection has a permission guide, configurable global shortcuts, and a display, window, and region selection overlay. the current recording slice can capture to a private temporary workspace, encode a playable GIF candidate, and show an animated preview with metadata. copy and save actions are implemented behind testable adapters; clipboard compatibility with GitHub, Discord, and other destinations remains unverified. compression and the release encoder are not available yet.

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

the build and test scripts write logs and `.xcresult` bundles under `.build/ci/`. UI tests need a macOS session that permits Xcode automation. deterministic UI tests use synthetic capture frames and injected clipboard and save adapters without requesting screen access. actual menu bar clicking, screen permission, shortcut delivery, overlay interaction, animated paste in destination apps, and release checks remain acceptance gates in [delivery-plan.md](delivery-plan.md).
# gifferent
