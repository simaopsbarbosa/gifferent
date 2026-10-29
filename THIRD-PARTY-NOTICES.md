# third-party notices

gifferent is licensed under [AGPL-3.0-or-later](LICENSE). the full license text in `LICENSE` is copied verbatim from the [SPDX license list](https://github.com/spdx/license-list-data/blob/main/text/AGPL-3.0-or-later.txt).

## current app bundle

the app embeds the Gifski 1.34.0 helper at `Contents/MacOS/gifski`. Xcode signs it as nested code when app signing is enabled. the app also embeds the complete notice inventory in `Contents/Resources/Gifski-1.34.0`.

## Gifski 1.34.0 candidate

the source license and dependency notice files for the bundled helper are collected under [`ThirdPartyNotices/Gifski-1.34.0`](ThirdPartyNotices/Gifski-1.34.0/README.md). the inventory is based on the pinned 1.34.0 source commit and its active macOS dependency graph. [`Vendor/Gifski-1.34.0`](Vendor/Gifski-1.34.0/README.md) records the embedded binary hash and rebuild command.

before release, verify the final app bundle and signing, and provide corresponding source/build materials required by the selected licenses. rerun the notice audit whenever the Gifski version, dependency lockfile, feature set, or build target changes.
