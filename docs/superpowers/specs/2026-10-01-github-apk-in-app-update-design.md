# In-app APK update for the GitHub build

## Goal

The Android `github` flavor finds a newer GitHub release, downloads the right
APK inside the app with visible progress, and hands it to the system installer.
The Play flavor and Linux are unchanged.

## Decisions

- Download starts only after the user taps Update. No Wi-Fi setting.
- No installer plugin: the download uses `http`, the install uses Android's
  `PackageInstaller` in `android/app/src/github`, so the Play build ships no
  sideload code. `crypto` is added for the SHA-256 check.
- `REQUEST_INSTALL_PACKAGES` is declared in `src/github/AndroidManifest.xml`
  only.

## Flow

1. On launch (and from About > Check for updates) fetch
   `releases/latest`. If the tag is newer, pick the APK asset matching
   `Build.SUPPORTED_ABIS` in order, falling back to the universal APK.
2. Show the update sheet: version, size, release notes, Update / Later.
   Later remembers the tag, so launch does not prompt for it again; the About
   tile still opens it.
3. Download to `<cache>/updates/<asset>.part` with progress and Cancel, hashing
   as it streams. Size and the release's `sha256:` digest must match, then the
   file is renamed to its final name.
4. Install through a `PackageInstaller` session. The system confirmation
   dialog also covers the "install unknown apps" grant. If the app is in the
   background when the download ends, the sheet waits on an Install button.
5. A verified APK left in the cache is reused; other files in `updates/` are
   removed on each check, and the folder is removed once up to date.

## Errors

Network or HTTP failure, checksum or size mismatch (file deleted), not enough
storage, install failure (system message shown), user cancel (back to
Install). All but cancel offer Retry.

## Pieces

- `lib/core/services/update/github_release.dart`: release model, asset
  choice, version comparison (pure, unit tested).
- `lib/core/services/update/apk_installer.dart`: method-channel wrapper.
- `lib/core/services/update/apk_update_notifier.dart`: `apkUpdateProvider`
  state machine.
- `lib/ui/widgets/sheets/apk_update_sheet.dart`: the sheet.
- `CheckForUpdatesTile` in About (github flavor only).
- `InAppUpdater.onMethodCall` in both flavors; the play one handles nothing.

## Release requirements

Assets keep the `...-<abi>-release.apk` / `...-universal-release.apk` naming,
and every release is signed with the same keystore.
