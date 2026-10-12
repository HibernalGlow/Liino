# Looper platform compatibility matrix

Regenerate the plugin half from the real project state rather than trusting
this file:

```
python3 - <<'PY'
import json
d = json.load(open('.flutter-plugins-dependencies'))
names = sorted({p['name'] for v in d['plugins'].values() if isinstance(v, list) for p in v})
for n in names:
    plats = [k for k, v in d['plugins'].items()
             if isinstance(v, list) and any(p['name'] == n for p in v)]
    print(f"{n}: {plats}")
PY
```

Checked against Flutter 3.47.4 / Dart 3.13.3, `pubspec.lock` at the
`feat/macos-windows-desktop` branch point.

## Native plugins

| Plugin | Android | Linux | Windows | macOS | Notes |
| --- | --- | --- | --- | --- | --- |
| `mpv_audio_kit` | yes | yes | yes | yes | Audio engine. Downloads and bundles `libmpv.dll` (Windows) / `libmpv.xcframework` (macOS) at build time. Windows build also links `windowsapp` + `shell32` for SMTC media keys; macOS podspec links `MediaPlayer` for Now Playing. macOS podspec requires `platform :osx, '12.0'`. |
| `metadata_god` | yes | yes | yes | yes | Tag reader. No platform needs a fallback for it to *load*, but a per-file failure is why `DesktopTagReader` exists. |
| `isar_community_flutter_libs` | yes | yes | yes | yes | Database. No migration needed for the port. |
| `window_manager` | - | yes | yes | yes | Desktop only. `TitleBarStyle.hidden` is honoured on all three. |
| `screen_retriever_*` | - | yes | yes | yes | Transitively via `window_manager`. |
| `file_picker` | yes | yes | yes | yes | `FilePicker.getDirectoryPath()` already the non-Android path. |
| `path_provider_*` | yes | yes | yes | yes | `getApplicationSupportDirectory()` backs `window_state.json`. |
| `share_plus` | yes | yes | yes | yes | `LoggerHelper.shareCrashLog`. |
| `url_launcher_*` | yes | yes | yes | yes | About links. |
| `wakelock_plus` | yes | yes | yes | yes | - |
| `package_info_plus` | yes | yes | yes | yes | - |
| `device_info_plus` | yes | yes | yes | yes | - |
| `gal` | yes | - | yes | yes | Gallery save. Not referenced from `lib/` today. |
| `permission_handler` | yes | - | yes | **not registered** | The macOS slice of this resolution declares `ios` only, so nothing is registered there at all. Harmless in practice: every call is already behind `Platform.isAndroid`. Do not add a macOS permission call expecting it to work. |
| `flutter_displaymode` | yes | - | - | - | High refresh rate. **Was called unconditionally in `lib/main.dart`**; now scoped to Android. |
| `home_widget` | yes | - | - | - | Not referenced from `lib/`; Android manifest only. |
| `haptic_feedback`, `vibration` | yes | - | - | - | `AppHaptics` already returns a desktop no-op. |
| `appambit_sdk_flutter` | yes | - | - | - | `AppAmbitReporter.start()` already returns early off mobile. |
| `sqflite_darwin`, `jni`, etc. | transitive | transitive | transitive | transitive | Not called directly. |

## Platform checks, by intent

### Desktop-generic (changed to `UiUtils.isDesktop`)

| Location | Was | Why it is desktop behaviour |
| --- | --- | --- |
| `lib/ui/widgets/player/premium_progress_bar.dart` | `useDesktopLayout = Platform.isLinux` + two font weights | The desktop progress bar look; the other two desktops were rendering the phone bar. |
| `lib/ui/widgets/player/player_bar/player_bar.dart` | `trackHeight` / `thumbHeight` | Same bar, desktop geometry. |
| `lib/features/analyze/presentation/screens/looper_analyze_view.dart` | `!Platform.isLinux` ×3, `final desktop = Platform.isLinux` | The desktop shell paints the artwork background for the page; nothing Linux-specific about it. |
| `lib/features/playback/presentation/providers/lyrics/lyrics_notifier.dart` | `if (Platform.isLinux) windowManager.setFullScreen(value)` | Full-screen lyrics belong to the shared desktop shell. |
| `lib/features/settings/presentation/screens/settings_category_screen.dart` | `!Platform.isLinux` around `FluidPlayerTile` | Fluid Player is a **swipe** gesture; a mouse can't make one on any desktop. |
| `lib/features/settings/presentation/screens/settings_view/settings_search.dart` | same | Search must match the tile's visibility. |
| `lib/ui/desktop/settings/settings_view.dart` | same | Same switch, desktop settings page. |

### Desktop-generic, but a *fallback* rather than a layout choice

| Location | Was | Now |
| --- | --- | --- |
| `lib/features/library/data/scanner/scanner.dart` tag fallback | `Platform.isLinux && metadata == null` → `LinuxTagReader` | `UiUtils.isDesktop && metadata == null` → `DesktopTagReader`, gated on `ffprobe()` resolving |
| `lib/features/library/data/scanner/scanner.dart` cover fallback | `Platform.isLinux` → `LinuxTagReader.readCover` | `UiUtils.isDesktop` → `DesktopTagReader.readCover`, gated on `ffmpeg()` resolving |
| `lib/features/playback/data/metadata_service.dart` | `Platform.isLinux` → ffprobe; everything else `null` | ffprobe on any desktop, plus a pure-Dart USLT decode as the last resort |

### Android-only (left alone, and one hardened)

| Location | Note |
| --- | --- |
| MediaStore / SAF queries, `_fetchNativeEmbeddedPicture`, `_fetchNativeGenre` | Already behind `Platform.isAndroid`. |
| `StorageAccess`, `Permission.*`, `android_audio_focus_manager`, `apk_installer`, `device_audio_info`, `media_sources` | Already behind `Platform.isAndroid`. |
| `lib/main.dart` `FlutterDisplayMode.setHighRefreshRate()` | **Fixed**: was called on every platform inside a `try`/`catch`. Now inside `if (Platform.isAndroid)`. |
| `lib/features/library/presentation/providers/library/library_notifier.dart` `scanRoots.add('/storage/emulated/0')` | **Fixed**: was the last-resort fallback on *every* platform, so a desktop with no saved folders scanned an Android path. Now `Platform.isAndroid` only. |

### Linux-specific (intentionally unchanged)

| Location | Why |
| --- | --- |
| `DesktopPaths._xdgMusicDirectory()` (`xdg-user-dir MUSIC`) | Linux desktop-folder convention; macOS/Windows have their own branch. |
| `lib/linux/**`, `.deb` / `.rpm` / AppImage makers in `distribute_options.yaml` | Linux packaging. |

## Paths and separators

`Isar.pathStartsWith` is a plain string comparison. Seven call sites built a
containment prefix as `'$folder/'`, which never matches on Windows where
`p.dirname()` yields `\`-separated paths. All of them now go through
`directoryPrefix()` (`lib/core/utils/desktop_paths.dart`).

| File | Sites |
| --- | --- |
| `lib/features/library/data/scanner/scanner.dart` | 2 |
| `lib/features/library/data/scanner/scan_paths.dart` | 1 (`isUnderExcludedFolder`) |
| `lib/features/library/presentation/providers/library/library_notifier.dart` | 3 |

`_isCoarseStorageRoot` (`library_state.dart`) still matches only
`/storage/...`; that is correct, since it exists to reject Android storage
roots and simply never matches on a desktop.

## CI blockers found while wiring the desktop builds

| Blocker | Detail | Handling |
| --- | --- | --- |
| `appambit_sdk_flutter` 1.2.0 plugin declaration | The package declares `pluginClass: AppAmbitSdkFlutterPlugin` (matching the class inside the file) but names the file `AppambitSdkFlutterPlugin.kt`. `flutter_tools`' Android plugin validation looks for a file named after `pluginClass`, case-sensitively, and aborts `pub get`. It therefore fails on **every case-sensitive filesystem** - including Linux CI - and passes on macOS and Windows only because APFS and NTFS are case-insensitive, which is why it never reproduced locally. The validation runs regardless of which platforms are enabled, so turning Android off does not avoid it. No fixed release on pub.dev as of 1.2.0. | The Linux CI jobs rename the file in the pub cache before the second `pub get`. Renaming is safe: Kotlin does not require file and class names to match, and the generated Android registrant then names a class that actually exists. |
| Fork workflow triggers | The first tag push on the fork produced no run at all, even though GitHub recorded the push and the workflow was registered. | `gh workflow run release.yml --ref <tag> -R <owner>/<repo>` dispatches on the tag ref, so `github.ref` is still the tag and the publish step runs. Note that with both an `origin` and an `upstream` remote, plain `gh` commands resolve against upstream - always pass `-R`. |
| macOS Release signature | A local `flutter build macos --release` is ad-hoc signed and carries `com.apple.security.get-task-allow`, which is a debugging grant. Fine for local runs, not for distribution. | A real distribution needs a Developer ID certificate and notarisation; the CI job does not have one. |

## Known gaps after this pass

| Gap | Detail |
| --- | --- |
| Embedded lyrics outside `.mp3` | FLAC / Ogg / M4A still need `metadata_god` or ffprobe. Only MP3 has the pure-Dart path. |
| Windows `Known Folder` redirection | `DesktopPaths` reads `%OneDrive%` rather than calling `FOLDERID_Music` through FFI, so an unusual redirection target is not found automatically. "Add Folder" still works. |
| `~/Music` under the macOS sandbox | `DesktopPaths.realUserHomeFrom` unwraps the container path, and `assets.music.read-only` grants the access. A non-standard sandbox container shape would fall back to "Add Folder". |
| Mobile-only welcome copy | The "no songs found" instructions still describe a USB transfer. Behaviour is fixed; the strings are not localised for desktop. |
| System tray / media keys | Windows SMTC and macOS Now Playing come from `mpv_audio_kit`. There is no tray icon on either platform yet. |
| Windows CI signing | The Windows artifact is unsigned, so SmartScreen warns on first run. |
