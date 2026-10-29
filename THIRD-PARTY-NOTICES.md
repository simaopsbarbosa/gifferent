# third-party notices

gifferent is licensed under [AGPL-3.0-or-later](LICENSE). the full license text in `LICENSE` is copied verbatim from the [SPDX license list](https://github.com/spdx/license-list-data/blob/main/text/AGPL-3.0-or-later.txt).

## current app bundle

no third-party library or executable is bundled in normal app builds at this stage. compression stays unavailable until a verified encoder is included.

## Gifski 1.34.0 candidate

the source license and dependency notice files for the approved Gifski CLI candidate are collected under [`ThirdPartyNotices/Gifski-1.34.0`](ThirdPartyNotices/Gifski-1.34.0/README.md). the inventory is based on the pinned 1.34.0 source commit and its active macOS dependency graph. these files document the candidate and are not evidence that a CLI is present in the app bundle.

before bundling, verify the final binary's source revision, feature set, architecture, and dependency graph; provide the applicable full license and notice texts in the source and app; identify and provide corresponding source/build materials required by the selected licenses; sign the nested executable; and verify the finished app bundle. rerun the notice audit whenever the Gifski version, dependency lockfile, feature set, or build target changes.
