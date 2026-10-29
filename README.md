# gifferent

a fast, native GIF maker for macOS. summon capture, record while using your Mac, then copy, save, or compress locally.

the app and its test suite are being built in tested iterations. capture selection has a permission guide, configurable global shortcuts, and a display, window, and region selection overlay. recording writes a private temporary workspace and opens an animated GIF preview with metadata, trim, speed, loop, copy, and save. the Gifski adapter and bounded destination search have deterministic acceptance and local CLI checks; normal builds show compression as unavailable until the verified encoder is bundled. animated paste into GitHub and the remaining real-Mac/release gates still need acceptance.

the source license is [AGPL-3.0-or-later](LICENSE). [third-party notices](THIRD-PARTY-NOTICES.md) track bundled dependencies and tools.

- [agent hub](AGENTS.md)
- [vision](vision.md)
- [brand direction](brand.md)
- [first release scope](mvp.md)
- [architecture and experiments](architecture.md)
- [definition of done](definition-of-done.md)
- [decisions and open questions](decisions.md)
- [delivery plan](delivery-plan.md)
- [editing and optimization acceptance](editing-optimization-evidence-2026-10-25.md)

## local development

use Xcode 26.2 (build 17C52) for the current foundation. open `gifferent.xcodeproj` with the shared `gifferent` scheme, or run:

```sh
bash Scripts/ci-local.sh
bash Scripts/check-toolchain.sh
python3 Scripts/check-docs.py
python3 Scripts/check-gifski-notices.py
bash Scripts/format-check.sh
bash Scripts/lint.sh
bash Scripts/build.sh
bash Scripts/test-unit.sh
bash Scripts/test-ui.sh
```

`Scripts/ci-local.sh` runs the same quality and test commands as GitHub Actions. it stops at the first failure and stores build/test logs and `.xcresult` bundles under `.build/ci/`. if only a different Xcode version is installed, `GIFFERENT_SKIP_TOOLCHAIN_CHECK=1 bash Scripts/ci-local.sh` runs the remaining checks locally; that result may differ from CI.

the build and test scripts write logs and `.xcresult` bundles under `.build/ci/`. UI tests need a macOS session that permits Xcode automation. deterministic UI tests use synthetic capture frames and injected clipboard and save adapters without requesting screen access. actual menu bar clicking, screen permission, shortcut delivery, overlay interaction, animated paste in destination apps, and release checks remain acceptance gates in [delivery-plan.md](delivery-plan.md).

test scripts use ad hoc signing by default. when local macOS policy requires the project's configured Apple Development identity, set `GIFFERENT_TEST_DEVELOPMENT_TEAM` to that team identifier when running either test script. runner launch/container consent is separate from a test result; a blocked runner does not count as passing UI acceptance.

for a reliable local Screen Recording permission check, choose an Apple Development team in Xcode's signing settings and build with `bash Scripts/build.sh`. unsigned or ad hoc builds may lose the permission association after a rebuild. after enabling access in System Settings, quit and reopen gifferent before checking again. CI intentionally builds without signing because it does not exercise live screen capture.
# gifferent
