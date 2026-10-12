---
name: looper-desktop-port
description: Audit, implement, or debug Windows and macOS desktop support in Looper. Use before changing platform checks, native plugins, filesystem access, audio playback, desktop UI behaviour, or release packaging. Trigger phrases include desktop port, Windows support, macOS support, platform check, Platform.isLinux, entitlements, desktop build.
---

# Looper Desktop Port Skill

## Objective

Add and maintain native Windows and macOS support while preserving the
existing Android and Linux behaviour. Prefer the maintained dependency's own
platform implementation over new code, and prefer a shared desktop branch over
a per-OS one.

## Workflow

1. Inspect `pubspec.yaml`, `pubspec.lock`, `.flutter-plugins-dependencies`,
   the platform directories, `.github/workflows/release.yml` and `test/`
   before editing anything.

2. Build a platform compatibility matrix for every native plugin from
   `.flutter-plugins-dependencies` (which lists real platform declarations,
   not guesses). `references/platform-matrix.md` holds the current one -
   regenerate it rather than trusting it. Never infer support from a package
   name.

3. Audit platform-specific code. The four shapes that gave Windows and macOS
   trouble here, and the shape to search for again:

   - `Platform.isLinux / isWindows / isMacOS / isAndroid / isIOS`
   - `MethodChannel` and FFI calls
   - `Process.run` / `Process.start` and any external executable
   - hard-coded paths and separators (`'/storage/emulated/0'`, `'$folder/'`)
   - window management, full screen, media keys, keyboard, lifecycle
   - entitlements and release packaging

4. Classify each occurrence as one of:

   - **Linux-specific** - e.g. the `xdg-user-dir` lookup, GTK packaging
   - **Android-specific** - e.g. MediaStore, SAF, `Permission.*`,
     `FlutterDisplayMode`, the home widget
   - **Shared desktop behaviour** - e.g. window geometry, title bar, desktop
     layout, full-screen lyrics
   - **Unverified** - investigate before touching it

   Never replace every `Platform.isLinux` with a desktop check blindly. A
   layout decision usually wants `UiUtils.isDesktop`; a capability decision
   usually does not.

5. Reuse the centralized helpers instead of inlining a new branch:

   - `UiUtils.isDesktop` - `lib/core/utils/ui_utils.dart`
   - `DesktopPaths.defaultMusicDirectories()` and `directoryPrefix()` -
     `lib/core/utils/desktop_paths.dart`
   - `DesktopTagReader` (ffprobe/ffmpeg fallback) -
     `lib/features/library/data/scanner/desktop_tag_reader.dart`
   - `Id3SyltReader` / `Id3UsltReader` / `Id3Frames` (pure-Dart tags) -
     `lib/features/playback/data/lyrics_formats/`

6. Keep behaviour on Android and Linux unchanged unless the change *is* the
   fix. When a platform abstraction is introduced, the old platform's output
   must be byte-identical.

7. Add regression tests for anything pure: path resolution, prefix matching,
   tag parsing, JSON/tag parsing fallbacks. `test/` holds them and is tracked
   in git on purpose - it used to be in `.gitignore`, which left `flutter
   test` with nothing to run on a fresh checkout and the CI job gating every
   platform build green for the wrong reason. There is no golden-file suite,
   so prefer asserting on values.

8. Run, in this order, and record the actual output:

   ```
   dart format lib test
   flutter analyze
   flutter test
   flutter build macos --release   # on macOS
   flutter build windows --release # on Windows
   ```

   Then launch the built app on each real target OS and exercise the checks in
   "Completion criteria" below. A build is not a verification.

## Looper-specific requirements

- Resolve each desktop's own default music folder through `DesktopPaths`.
  Never let a desktop fall through to an Android storage path.
- Keep `ffprobe`/`ffmpeg` usage optional: resolve the executable once, and
  treat "not installed" as "no fallback", not as an error. A macOS app
  launched from Finder does not inherit the shell `PATH`, so the Homebrew
  locations in `DesktopTagReader.candidateExecutables` matter.
- Embedded lyrics: `.mp3` is covered by `Id3SyltReader` (synced) and
  `Id3UsltReader` (unsynced) in pure Dart. Other containers (FLAC, Ogg, M4A)
  still depend on `metadata_god` or ffprobe, so state that as a gap rather
  than claiming full coverage.
- Never call Android-only functionality on desktop: `MethodChannel`
  broadcast channels, MediaStore, SAF, `Permission.*`, `FlutterDisplayMode`,
  `home_widget`.
- Do not gate Android-only plugins behind `try`/`catch` to make desktop work.
  Put an explicit platform check around them so a regression raises instead
  of disappearing.
- Preserve Isar data, playback state, saved folders and settings across the
  port. `window_state.json` and the settings store must keep working.
- Path comparisons must go through `directoryPrefix()` /
  `withoutTrailingSeparator()`. Isar's `pathStartsWith` is a plain string
  compare, and Windows paths are backslash-separated.
- macOS keeps the App Sandbox. Anything that needs the network or a music
  folder needs the matching entitlement in **both**
  `macos/Runner/DebugProfile.entitlements` and
  `macos/Runner/Release.entitlements`.
- Windows ships `libmpv.dll` next to the executable, downloaded by the
  plugin's CMake configure step; never hand-copy a different build of libmpv.

## Completion criteria

Do not report desktop support as complete because the app compiles. Record
the actual result for each row:

| Check | Minimum |
| --- | --- |
| Native build | Debug **and** Release pass on Windows and on macOS |
| Library | First scan, Add Folder and rescan all find the right songs |
| Playback and tags | Common formats play; title, album and cover art read correctly |
| Lyrics | Network lyrics, `.lrc` sidecars and embedded lyrics each verified; unsupported containers named |
| Persistence | Library, settings and playback state survive a restart |
| Desktop behaviour | Window size, position restore, title bar, keyboard and media keys behave |
| Release | The packaged app starts on a clean machine with its native libraries present |

Also record known feature gaps, dependency constraints and the artifact paths.
