# Linux Desktop Screens Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix the missing song photos and wrong titles on Linux, and bring the Linux home, songs, artists, genres, analyze, settings and equalizer screens up to desktop quality.

**Architecture:** One data fix (an ffprobe/ffmpeg tag reader used only on Linux when `metadata_god` is unavailable) and a set of desktop-shell changes. Each screen's decision logic (which sections, how many columns, when to show a button, how big a dialog) is a pure function with unit tests; the widgets are thin wiring in files only the Linux shell builds.

**Tech Stack:** Flutter (Linux desktop), Riverpod, Isar, `ffprobe`/`ffmpeg` via `dart:io` `Process`.

**Spec:** `docs/superpowers/specs/2026-10-01-linux-desktop-screens-design.md`

**Prerequisite:** Task 1 of `docs/superpowers/plans/2026-10-01-linux-window-foundation-and-lyrics.md` (it adds `UiUtils.isDesktop`, `Responsive.windowClass` and `WindowClass`). Do that task first, on the same branch.

## Global Constraints

- **Android must not change, in behaviour or pixels.** Every change is behind `UiUtils.isDesktop` / `Platform.isLinux`, lives in desktop-only files, or is an optional parameter Android never passes.
- Desktop-only files (free to change): everything in `lib/ui/home_screen/`, `lib/ui/desktop/`, and `lib/features/library/presentation/widgets/library_grids.dart` (its `AlbumsGrid`/`ArtistsGrid` are built only by `home_screen.dart`).
- Shared files (gate every change): `scanner.dart`, `songs_list.dart`, `android_equalizer_screen.dart`, `player_bar.dart`, `song_options_bottom_sheet.dart`, `playback_settings_tiles.dart`.
- Do not edit `pubspec.yaml` dependencies or `lib/features/playback/presentation/providers/playback/playback_notifier.dart` (it holds the user's uncommitted work).
- All UI text through ARB / `context.l10n`. This plan needs no new strings: `genres`, `looperAnalyze`, `addFolder`, `viewAll`, `themeGroupFonts`, `lyrics`, `nowPlaying`, `homeDashboardSettings`, `audioPlayback`, `backupsAndLogs`, `aboutApp` already exist.
- Exact values from the spec: search bar max width 640; home section gap 28; songs two columns from a list width of 1100; equalizer dialog width `min(1100, window - 64)`, height `min(window - 64, width * 0.7)`, two columns from dialog width 820.
- `test/` is gitignored: tests run locally and are not committed.
- The working tree holds unrelated uncommitted changes. `git add` only the paths each task names.
- Run `dart format` on every Dart file you edit.

## Review Focus

1. **ffmpeg/ffprobe not installed.** The scan must still finish and index songs by file name, with no crash and no per-file hang. Pinned by the missing-binary test in Task 1.
2. **Files with unusual tags:** tags only on the audio stream (Ogg/Opus), upper-case keys (`TITLE`), `track` as `3/12`, `date` as `2019-05-01`, no tags at all. Pinned by the parser tests in Task 1.
3. **A file whose probe hangs** (network mount, damaged file). The process must be killed and the scan must move on. Pinned by the timeout test in Task 1.
4. **Empty library.** The Add Folder button must be reachable from every page, and Home must not render empty section headers. Pinned by the rules tests in Tasks 2 and 3.
5. **Small windows.** At the 720x480 minimum the equalizer dialog must still be wider than tall and must not overflow. Pinned by the size tests in Task 7.

---

### Task 1: Read tags and covers on Linux without metadata_god

**Files:**
- Create: `lib/features/library/data/scanner/linux_tag_reader.dart`
- Modify: `lib/features/library/data/scanner/scanner.dart:699-763` (`_extractMetadata`)
- Modify: `linux/packaging/deb/make_config.yaml`, `linux/packaging/rpm/make_config.yaml`
- Test: `test/linux_tag_reader_test.dart`

**Interfaces:**
- Produces:
  - `class LinuxTags { String? title, artist, album, genre; int? durationMs, trackNumber, year; }`
  - `LinuxTagReader.parse(Map<String, dynamic> json) -> LinuxTags` (pure)
  - `LinuxTagReader.read(String path, {required Duration timeout, String executable = 'ffprobe'}) -> Future<LinuxTags?>`
  - `LinuxTagReader.readCover(String path, {required Duration timeout, String executable = 'ffmpeg'}) -> Future<List<int>?>`
  - Both throw `TimeoutException` on timeout and return null when the binary is missing or exits non-zero.

- [ ] **Step 1: Write the failing tests**

`test/linux_tag_reader_test.dart`:

```dart
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:looper_player/features/library/data/scanner/linux_tag_reader.dart';

void main() {
  group('LinuxTagReader.parse', () {
    test('reads the common container tags', () {
      final tags = LinuxTagReader.parse({
        'format': {
          'duration': '215.48',
          'tags': {
            'title': 'Tere Bina',
            'artist': 'A. R. Rahman',
            'album': 'Guru',
            'genre': 'Soundtrack',
            'track': '3/12',
            'date': '2007-01-12',
          },
        },
      });
      expect(tags.title, 'Tere Bina');
      expect(tags.artist, 'A. R. Rahman');
      expect(tags.album, 'Guru');
      expect(tags.genre, 'Soundtrack');
      expect(tags.trackNumber, 3);
      expect(tags.year, 2007);
      expect(tags.durationMs, 215480);
    });

    test('keys are matched without regard to case', () {
      final tags = LinuxTagReader.parse({
        'format': {
          'tags': {'TITLE': 'Black', 'ARTIST': 'Pearl Jam', 'TRACKNUMBER': '5'},
        },
      });
      expect(tags.title, 'Black');
      expect(tags.artist, 'Pearl Jam');
      expect(tags.trackNumber, 5);
    });

    test('Ogg and Opus keep their tags on the audio stream', () {
      final tags = LinuxTagReader.parse({
        'format': {'duration': '10.0'},
        'streams': [
          {'codec_type': 'video'},
          {
            'codec_type': 'audio',
            'tags': {'title': 'Why Go', 'artist': 'Pearl Jam'},
          },
        ],
      });
      expect(tags.title, 'Why Go');
      expect(tags.artist, 'Pearl Jam');
      expect(tags.durationMs, 10000);
    });

    test('container tags win over stream tags', () {
      final tags = LinuxTagReader.parse({
        'format': {
          'tags': {'title': 'From container'},
        },
        'streams': [
          {
            'codec_type': 'audio',
            'tags': {'title': 'From stream', 'album': 'Stream album'},
          },
        ],
      });
      expect(tags.title, 'From container');
      expect(tags.album, 'Stream album');
    });

    test('album artist stands in for a missing artist', () {
      final tags = LinuxTagReader.parse({
        'format': {
          'tags': {'album_artist': 'Lana Del Rey'},
        },
      });
      expect(tags.artist, 'Lana Del Rey');
    });

    test('blank and missing values come back as null', () {
      final tags = LinuxTagReader.parse({
        'format': {
          'tags': {'title': '   ', 'track': 'x', 'date': 'unknown'},
        },
      });
      expect(tags.title, isNull);
      expect(tags.trackNumber, isNull);
      expect(tags.year, isNull);
      expect(tags.durationMs, isNull);
    });

    test('empty or malformed JSON gives empty tags instead of throwing', () {
      expect(LinuxTagReader.parse({}).title, isNull);
      expect(LinuxTagReader.parse({'format': 'nope'}).title, isNull);
      expect(LinuxTagReader.parse({'streams': 'nope'}).artist, isNull);
    });
  });

  group('LinuxTagReader process handling', () {
    const timeout = Duration(seconds: 2);

    test('a missing binary returns null', () async {
      expect(
        await LinuxTagReader.read(
          '/tmp/none.mp3',
          timeout: timeout,
          executable: 'looper-no-such-binary',
        ),
        isNull,
      );
      expect(
        await LinuxTagReader.readCover(
          '/tmp/none.mp3',
          timeout: timeout,
          executable: 'looper-no-such-binary',
        ),
        isNull,
      );
    });

    test('a failing process returns null', () async {
      // `false` ignores its arguments and exits 1.
      expect(
        await LinuxTagReader.read('/x', timeout: timeout, executable: 'false'),
        isNull,
      );
      expect(
        await LinuxTagReader.readCover(
          '/x',
          timeout: timeout,
          executable: 'false',
        ),
        isNull,
      );
    });

    test('a process that hangs is killed and reported as a timeout', () async {
      // `yes` ignores its arguments and never exits.
      await expectLater(
        LinuxTagReader.read(
          '/x',
          timeout: const Duration(milliseconds: 300),
          executable: 'yes',
        ),
        throwsA(isA<TimeoutException>()),
      );
    });
  });
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `flutter test test/linux_tag_reader_test.dart`
Expected: FAIL to compile, "Target of URI doesn't exist: linux_tag_reader.dart".

- [ ] **Step 3: Implement the reader**

Create `lib/features/library/data/scanner/linux_tag_reader.dart`:

```dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// The tags [LinuxTagReader] could find. Every field is null when absent.
class LinuxTags {
  final String? title;
  final String? artist;
  final String? album;
  final String? genre;
  final int? durationMs;
  final int? trackNumber;
  final int? year;

  const LinuxTags({
    this.title,
    this.artist,
    this.album,
    this.genre,
    this.durationMs,
    this.trackNumber,
    this.year,
  });
}

/// Reads embedded tags and cover art with ffprobe/ffmpeg. Linux only: the
/// scanner falls back to it when metadata_god is unavailable, the same way
/// Android falls back to its native readers.
class LinuxTagReader {
  /// Pure: turns `ffprobe -print_format json -show_format -show_streams`
  /// output into tags. Container tags win; the first audio stream's tags
  /// fill the gaps (Ogg/Opus keep their tags there).
  static LinuxTags parse(Map<String, dynamic> json) {
    final tags = <String, String>{};

    void addAll(Object? source) {
      if (source is! Map) return;
      source.forEach((key, value) {
        final text = value?.toString().trim() ?? '';
        if (text.isEmpty) return;
        tags.putIfAbsent(key.toString().toLowerCase(), () => text);
      });
    }

    final format = json['format'];
    if (format is Map) addAll(format['tags']);

    final streams = json['streams'];
    if (streams is List) {
      for (final stream in streams) {
        if (stream is Map && stream['codec_type'] == 'audio') {
          addAll(stream['tags']);
          break;
        }
      }
    }

    int? leadingInt(String? text) {
      if (text == null) return null;
      final match = RegExp(r'^\d+').firstMatch(text);
      return match == null ? null : int.tryParse(match.group(0)!);
    }

    int? durationMs;
    if (format is Map) {
      final seconds = double.tryParse(format['duration']?.toString() ?? '');
      if (seconds != null && seconds.isFinite && seconds > 0) {
        durationMs = (seconds * 1000).round();
      }
    }

    final year = leadingInt(tags['date'] ?? tags['year']);

    return LinuxTags(
      title: tags['title'],
      artist: tags['artist'] ?? tags['album_artist'] ?? tags['albumartist'],
      album: tags['album'],
      genre: tags['genre'],
      durationMs: durationMs,
      trackNumber: leadingInt(tags['track'] ?? tags['tracknumber']),
      year: (year != null && year >= 1000) ? year : null,
    );
  }

  static Future<LinuxTags?> read(
    String path, {
    required Duration timeout,
    String executable = 'ffprobe',
  }) async {
    final bytes = await _run(executable, [
      '-v',
      'quiet',
      '-print_format',
      'json',
      '-show_format',
      '-show_streams',
      path,
    ], timeout);
    if (bytes == null || bytes.isEmpty) return null;
    try {
      final json = jsonDecode(utf8.decode(bytes, allowMalformed: true));
      return json is Map<String, dynamic> ? parse(json) : null;
    } catch (_) {
      return null;
    }
  }

  /// The first attached picture as JPEG bytes, or null when there is none.
  static Future<List<int>?> readCover(
    String path, {
    required Duration timeout,
    String executable = 'ffmpeg',
  }) async {
    final bytes = await _run(executable, [
      '-v',
      'quiet',
      '-i',
      path,
      '-an',
      '-map',
      '0:v:0',
      '-frames:v',
      '1',
      '-c:v',
      'mjpeg',
      '-f',
      'image2pipe',
      '-',
    ], timeout);
    return (bytes == null || bytes.isEmpty) ? null : bytes;
  }

  /// Stdout of the process, or null when it can't start or exits non-zero.
  /// A process still running at [timeout] is killed and reported as a
  /// TimeoutException, so one bad file can't stall the scan.
  static Future<List<int>?> _run(
    String executable,
    List<String> args,
    Duration timeout,
  ) async {
    final Process process;
    try {
      process = await Process.start(executable, args);
    } on ProcessException {
      return null;
    }

    final output = BytesBuilder(copy: false);
    final stdoutDone = process.stdout.forEach(output.add);
    // Drained so a chatty process can't block on a full stderr pipe.
    final stderrDone = process.stderr.drain<void>();
    try {
      final exitCode = await process.exitCode.timeout(timeout);
      await stdoutDone;
      await stderrDone;
      return exitCode == 0 ? output.takeBytes() : null;
    } on TimeoutException {
      process.kill(ProcessSignal.sigkill);
      rethrow;
    }
  }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `flutter test test/linux_tag_reader_test.dart`
Expected: all tests PASS.

- [ ] **Step 5: Use it in the scanner**

In `lib/features/library/data/scanner/scanner.dart`, add the import:

```dart
import 'linux_tag_reader.dart';
```

In `_extractMetadata`, the block that currently reads

```dart
      String? title = metadata?.title;
      String? artist = metadata?.artist;
      String? album = metadata?.album;
      String? genre = _cleanGenre(metadata?.genre);
      int? durationMs = metadata?.durationMs?.toInt();
      int? trackNumber = metadata?.trackNumber;
      int? year = metadata?.year;
      List<int>? pictureData = metadata?.picture?.data;
```

becomes

```dart
      // Linux has no native tag fallback, so when metadata_god couldn't
      // read the file (or failed to initialise at all) ask ffprobe.
      LinuxTags? linuxTags;
      if (Platform.isLinux && metadata == null) {
        try {
          linuxTags = await LinuxTagReader.read(file.path, timeout: tagTimeout);
        } on TimeoutException {
          transient = true;
        }
      }

      String? title = metadata?.title ?? linuxTags?.title;
      String? artist = metadata?.artist ?? linuxTags?.artist;
      String? album = metadata?.album ?? linuxTags?.album;
      String? genre = _cleanGenre(metadata?.genre ?? linuxTags?.genre);
      int? durationMs =
          metadata?.durationMs?.toInt() ?? linuxTags?.durationMs;
      int? trackNumber = metadata?.trackNumber ?? linuxTags?.trackNumber;
      int? year = metadata?.year ?? linuxTags?.year;
      List<int>? pictureData = metadata?.picture?.data;
```

On Android `linuxTags` is always null, so every expression evaluates to what it did before.

Directly after the existing `if (pictureData == null && Platform.isAndroid) { ... }` block, add:

```dart

      if (pictureData == null && Platform.isLinux) {
        try {
          pictureData = await LinuxTagReader.readCover(
            file.path,
            timeout: pictureTimeout,
          );
        } on TimeoutException {
          transient = true;
        }
      }
```

- [ ] **Step 6: Declare the package dependency**

In `linux/packaging/deb/make_config.yaml`, under `depends:`, add a line:

```yaml
  - ffmpeg
```

In `linux/packaging/rpm/make_config.yaml`, under `requires:`, add file dependencies (Fedora ships the binaries in `ffmpeg-free`, RPM Fusion in `ffmpeg`; a path dependency matches both):

```yaml
  - /usr/bin/ffprobe
  - /usr/bin/ffmpeg
```

`package.sh` also builds a Depends line (`echo "libgtk-3-0, libmpv1 | libmpv2"` near line 293). It has uncommitted changes of the user's: do not edit it; report in the task summary that `, ffmpeg` should be added there.

- [ ] **Step 7: Verify on Linux**

Run: `flutter analyze lib/features/library/data/scanner && flutter test test/linux_tag_reader_test.dart test/library_scanner_filter_test.dart`
Expected: no new issues; tests PASS.

Run: `flutter run -d linux`, open Songs, choose "Reset & Rescan" and confirm. Then:
1. Songs show their real titles and artists instead of file names and "Unknown Artist".
2. Songs with embedded covers show them in the list, on Home and in the player bar.
3. `ls ~/.local/share/com.looper.player/album_art | head` lists image files.
4. Albums, Artists and Genres pages are populated from the tags.

- [ ] **Step 8: Format and commit**

```bash
dart format lib/features/library/data/scanner/linux_tag_reader.dart lib/features/library/data/scanner/scanner.dart test/linux_tag_reader_test.dart
git add lib/features/library/data/scanner/linux_tag_reader.dart lib/features/library/data/scanner/scanner.dart linux/packaging/deb/make_config.yaml linux/packaging/rpm/make_config.yaml
git commit -m "Read tags and cover art with ffprobe/ffmpeg on Linux when metadata_god is unavailable"
```

---

### Task 2: Shell rules, sidebar entries and routes for Genres and Analyze

**Files:**
- Create: `lib/ui/home_screen/desktop_shell_rules.dart`
- Modify: `lib/ui/home_screen/sidebar.dart` (items list, lines 52-108)
- Modify: `lib/ui/home_screen/home_screen.dart` (`_getWidgetForNavItem`, and the `if (nav.activeItem != NavItem.lyrics)` check near line 260)
- Test: `test/desktop_shell_rules_test.dart`

**Interfaces:**
- Produces:
  - `DesktopShellRules.showTopBar(NavItem item) -> bool`
  - `DesktopShellRules.showAddFolder(NavItem item, {required bool libraryEmpty}) -> bool` (used in Task 3)

- [ ] **Step 1: Write the failing tests**

`test/desktop_shell_rules_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:looper_player/core/providers/navigation_provider.dart';
import 'package:looper_player/ui/home_screen/desktop_shell_rules.dart';

void main() {
  group('DesktopShellRules.showTopBar', () {
    test('hidden where the page brings its own header', () {
      expect(DesktopShellRules.showTopBar(NavItem.lyrics), isFalse);
      expect(DesktopShellRules.showTopBar(NavItem.analyze), isFalse);
    });

    test('shown everywhere else', () {
      for (final item in NavItem.values) {
        if (item == NavItem.lyrics || item == NavItem.analyze) continue;
        expect(DesktopShellRules.showTopBar(item), isTrue, reason: '$item');
      }
    });
  });

  group('DesktopShellRules.showAddFolder', () {
    test('shown on the library pages', () {
      for (final item in [
        NavItem.home,
        NavItem.songs,
        NavItem.albums,
        NavItem.artists,
        NavItem.genres,
      ]) {
        expect(
          DesktopShellRules.showAddFolder(item, libraryEmpty: false),
          isTrue,
          reason: '$item',
        );
      }
    });

    test('hidden on the other pages once there is a library', () {
      for (final item in [
        NavItem.queue,
        NavItem.settings,
        NavItem.playlists,
        NavItem.favorites,
        NavItem.recentlyPlayed,
        NavItem.search,
        NavItem.collectionDetail,
      ]) {
        expect(
          DesktopShellRules.showAddFolder(item, libraryEmpty: false),
          isFalse,
          reason: '$item',
        );
      }
    });

    test('an empty library always offers it', () {
      for (final item in NavItem.values) {
        expect(
          DesktopShellRules.showAddFolder(item, libraryEmpty: true),
          isTrue,
          reason: '$item',
        );
      }
    });
  });
}
```

- [ ] **Step 2: Run them to verify they fail**

Run: `flutter test test/desktop_shell_rules_test.dart`
Expected: FAIL to compile, "Target of URI doesn't exist: desktop_shell_rules.dart".

- [ ] **Step 3: Implement the rules**

Create `lib/ui/home_screen/desktop_shell_rules.dart`:

```dart
import 'package:looper_player/core/providers/navigation_provider.dart';

/// What the desktop shell shows around each page.
class DesktopShellRules {
  /// Pages where adding music is the natural next step.
  static const Set<NavItem> _libraryPages = {
    NavItem.home,
    NavItem.songs,
    NavItem.albums,
    NavItem.artists,
    NavItem.genres,
  };

  /// Lyrics and Analyze are full-pane views with their own header.
  static bool showTopBar(NavItem item) =>
      item != NavItem.lyrics && item != NavItem.analyze;

  /// With no music yet, every page offers Add Folder. After that it only
  /// appears on the library pages, where it is not in the way.
  static bool showAddFolder(NavItem item, {required bool libraryEmpty}) =>
      libraryEmpty || _libraryPages.contains(item);
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `flutter test test/desktop_shell_rules_test.dart`
Expected: all tests PASS.

- [ ] **Step 5: Add the sidebar entries**

In `lib/ui/home_screen/sidebar.dart`, directly after the Artists `_SidebarItem` (the one with `label: l10n.artists`), add:

```dart
                    if (ref.watch(songsByGenreProvider).isNotEmpty)
                      _SidebarItem(
                        icon: LucideIcons.music,
                        label: l10n.genres,
                        isSelected: activeItem == NavItem.genres,
                        onTap: () => navigateTo(NavItem.genres),
                      ),
```

Directly after the Favorites `_SidebarItem` (`label: l10n.favorites`), add:

```dart
                    _SidebarItem(
                      icon: LucideIcons.barChart3,
                      label: l10n.looperAnalyze,
                      isSelected: activeItem == NavItem.analyze,
                      onTap: () => navigateTo(NavItem.analyze),
                    ),
```

`songsByGenreProvider` comes from `library_notifier.dart`, which `home_screen.dart` (the library this part belongs to) already imports. The sidebar already calls `ref.watch(albumsProvider)` in this list, so `ref` is in scope.

- [ ] **Step 6: Route the two pages and hide the top bar on Analyze**

In `lib/ui/home_screen/home_screen.dart`, add imports:

```dart
import 'package:looper_player/features/analyze/presentation/screens/looper_analyze_view.dart';
import 'package:looper_player/ui/android/tabs/library/categories/genres_grid_view.dart';
import 'desktop_shell_rules.dart';
```

In `_getWidgetForNavItem`, add before `case NavItem.home:`:

```dart
      case NavItem.genres:
        return const GenresGridView();
      case NavItem.analyze:
        return const LooperAnalyzeView();
```

Replace

```dart
                                        if (nav.activeItem != NavItem.lyrics)
```

with

```dart
                                        if (DesktopShellRules.showTopBar(
                                          nav.activeItem,
                                        ))
```

- [ ] **Step 7: Verify on Linux**

Run: `flutter analyze lib/ui/home_screen`
Expected: no new issues.

Run: `flutter run -d linux`:
1. Sidebar shows Genres (after Artists) and Looper Analyze (after Favorites), each highlighting when active.
2. Genres opens the genre grid; clicking a genre opens its songs; Back returns to the grid.
3. Home's Genres "View all" now opens the genre grid instead of staying on Home.
4. Looper Analyze opens the report with its own header; the search bar is hidden; its back arrow returns to the previous page.

- [ ] **Step 8: Format and commit**

```bash
dart format lib/ui/home_screen test/desktop_shell_rules_test.dart
git add lib/ui/home_screen/desktop_shell_rules.dart lib/ui/home_screen/sidebar.dart lib/ui/home_screen/home_screen.dart
git commit -m "Add Genres and Looper Analyze to the desktop sidebar and shell"
```

---

### Task 3: Add Folder button visibility and top bar layout

**Files:**
- Modify: `lib/ui/home_screen/sidebar.dart` (`_HeaderButton`, line 125)
- Modify: `lib/ui/home_screen/home_screen.dart` (top bar `Row`, lines 263-320)

**Interfaces:**
- Consumes: `DesktopShellRules.showAddFolder` (Task 2); `Responsive.windowClass`, `WindowClass` (prerequisite)

The rule itself is tested in Task 2. This task is wiring; verified by the manual run.

- [ ] **Step 1: Give `_HeaderButton` a compact form**

In `sidebar.dart`, add a field and constructor parameter to `_HeaderButton`:

```dart
  /// Icon only, with the label as a tooltip. For narrow windows.
  final bool compact;
```

```dart
    this.compact = false,
```

In its `build`, wrap the returned `InkWell` in a tooltip and drop the label when compact. Replace `return InkWell(` with `return Tooltip(message: compact ? label : '', child: InkWell(` (closing the extra parenthesis at the end), change the horizontal padding to

```dart
        padding: EdgeInsets.symmetric(horizontal: (compact ? 16 : 20).s),
```

and replace the trailing

```dart
            SizedBox(width: 10.s),
            Text(
              label,
              style: AppFonts.jostStyle(
                color: Colors.white,
                fontSize: 14.ts,
                fontWeight: FontWeight.normal,
              ),
            ),
```

with

```dart
            if (!compact) ...[
              SizedBox(width: 10.s),
              Text(
                label,
                style: AppFonts.jostStyle(
                  color: Colors.white,
                  fontSize: 14.ts,
                  fontWeight: FontWeight.normal,
                ),
              ),
            ],
```

An empty tooltip message shows nothing, so the full button is unchanged.

- [ ] **Step 2: Apply the rule and fix the search bar width**

In `home_screen.dart`, in the top bar `Row`, replace

```dart
                                                const Expanded(
                                                  child: GlobalSearchBar(),
                                                ),
                                                // const SizedBox(width: 48),
                                                Spacer(),
                                                _HeaderButton(
                                                  onTap: () {
                                                    FolderPickerHelper.pickFolder(
                                                      context,
                                                      ref,
                                                    );
                                                  },
                                                  icon: LucideIcons.plus,
                                                  label: l10n.addFolder,
                                                  isDynamic: isDynamic,
                                                ),
```

with

```dart
                                                // The search bar takes the
                                                // row but stops growing at
                                                // 640px, so on a wide window
                                                // it doesn't stretch to half
                                                // the screen.
                                                Expanded(
                                                  child: Align(
                                                    alignment:
                                                        Alignment.centerLeft,
                                                    child: ConstrainedBox(
                                                      constraints:
                                                          const BoxConstraints(
                                                            maxWidth: 640,
                                                          ),
                                                      child:
                                                          const GlobalSearchBar(),
                                                    ),
                                                  ),
                                                ),
                                                if (DesktopShellRules.showAddFolder(
                                                  nav.activeItem,
                                                  libraryEmpty:
                                                      library.songs.isEmpty,
                                                )) ...[
                                                  const SizedBox(width: 16),
                                                  _HeaderButton(
                                                    onTap: () {
                                                      FolderPickerHelper.pickFolder(
                                                        context,
                                                        ref,
                                                      );
                                                    },
                                                    icon: LucideIcons.plus,
                                                    label: l10n.addFolder,
                                                    isDynamic: isDynamic,
                                                    compact: isNarrowLayout,
                                                  ),
                                                ],
```

`isNarrowLayout` is the local already defined at the top of this `LayoutBuilder` builder; `nav` and `library` are locals of `build`.

- [ ] **Step 3: Verify on Linux**

Run: `flutter analyze lib/ui/home_screen`
Expected: no new issues.

Run: `flutter run -d linux`:
1. Home, Songs, Albums, Artists, Genres: "Add Folder" is at the right end of the top bar.
2. Queue, Settings, Playlists, Favorites, Recently played, an album page: it is gone, and the search bar does not jump.
3. Maximize the window: the button is still there on the library pages, at the right edge; the search bar is 640 px wide, not half the window.
4. Narrow the window below 800 px: the button shows only the plus icon; hovering shows "Add Folder".
5. With an empty library (use a fresh profile: `XDG_DATA_HOME=$(mktemp -d) flutter run -d linux`, skip the welcome screen): the button shows on every page.

- [ ] **Step 4: Format and commit**

```bash
dart format lib/ui/home_screen
git add lib/ui/home_screen/sidebar.dart lib/ui/home_screen/home_screen.dart
git commit -m "Show Add Folder only where it helps; cap the desktop search bar width"
```

---

### Task 4: Home order and alignment

**Files:**
- Create: `lib/ui/desktop/dashboard/desktop_home_sections.dart`
- Modify: `lib/ui/desktop/dashboard/home_dashboard.dart` (the section-building part of `build`, lines 69-163)
- Modify: `lib/ui/desktop/dashboard/dashboard_sections.dart` (section headers and sizes)
- Modify: `lib/ui/desktop/dashboard/desktop_items.dart` (`_buildDesktopHorizontalSection` header)
- Test: `test/desktop_home_sections_test.dart`

**Interfaces:**
- Produces:
  - `enum DesktopHomeSection { quickPicks, recentlyPlayed, featuredArtists, albums, genres, artists }`
  - `desktopHomeSections({required bool showRecent, required bool showGenres, required bool showArtists}) -> List<DesktopHomeSection>`

- [ ] **Step 1: Write the failing tests**

`test/desktop_home_sections_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:looper_player/ui/desktop/dashboard/desktop_home_sections.dart';

void main() {
  test('everything on: the agreed order', () {
    expect(
      desktopHomeSections(showRecent: true, showGenres: true, showArtists: true),
      [
        DesktopHomeSection.quickPicks,
        DesktopHomeSection.recentlyPlayed,
        DesktopHomeSection.featuredArtists,
        DesktopHomeSection.albums,
        DesktopHomeSection.genres,
        DesktopHomeSection.artists,
      ],
    );
  });

  test('switched-off rows drop out without disturbing the order', () {
    expect(
      desktopHomeSections(
        showRecent: false,
        showGenres: false,
        showArtists: false,
      ),
      [
        DesktopHomeSection.quickPicks,
        DesktopHomeSection.featuredArtists,
        DesktopHomeSection.albums,
      ],
    );
    expect(
      desktopHomeSections(showRecent: true, showGenres: false, showArtists: true),
      [
        DesktopHomeSection.quickPicks,
        DesktopHomeSection.recentlyPlayed,
        DesktopHomeSection.featuredArtists,
        DesktopHomeSection.albums,
        DesktopHomeSection.artists,
      ],
    );
  });

  test('no section appears twice', () {
    final sections = desktopHomeSections(
      showRecent: true,
      showGenres: true,
      showArtists: true,
    );
    expect(sections.toSet().length, sections.length);
  });
}
```

- [ ] **Step 2: Run them to verify they fail**

Run: `flutter test test/desktop_home_sections_test.dart`
Expected: FAIL to compile, "Target of URI doesn't exist: desktop_home_sections.dart".

- [ ] **Step 3: Implement the order**

Create `lib/ui/desktop/dashboard/desktop_home_sections.dart`:

```dart
/// The rows of the desktop home page.
enum DesktopHomeSection {
  quickPicks,
  recentlyPlayed,
  featuredArtists,
  albums,
  genres,
  artists,
}

/// The desktop home page's rows, top to bottom. The order is fixed; the
/// three flags are the user's "show on home" settings. Quick picks,
/// featured artists and albums are always candidates (each still hides
/// itself when it has nothing to show).
List<DesktopHomeSection> desktopHomeSections({
  required bool showRecent,
  required bool showGenres,
  required bool showArtists,
}) => [
  DesktopHomeSection.quickPicks,
  if (showRecent) DesktopHomeSection.recentlyPlayed,
  DesktopHomeSection.featuredArtists,
  DesktopHomeSection.albums,
  if (showGenres) DesktopHomeSection.genres,
  if (showArtists) DesktopHomeSection.artists,
];
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `flutter test test/desktop_home_sections_test.dart`
Expected: all tests PASS.

- [ ] **Step 5: One shared section header**

In `lib/ui/desktop/dashboard/desktop_items.dart`, add this method to the `_DashboardDesktopItems` extension, above `_buildDesktopHorizontalSection`:

```dart
  /// The one header every home row uses, so titles and "View all" line up.
  Widget _buildSectionHeader(
    BuildContext context,
    String title, {
    VoidCallback? onViewAll,
  }) {
    return SizedBox(
      height: 40,
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 18.ts,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
          ),
          if (onViewAll != null)
            TextButton(
              onPressed: onViewAll,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    context.l10n.viewAll,
                    style: const TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                  const SizedBox(width: 4),
                  const Icon(
                    LucideIcons.chevronRight,
                    size: 16,
                    color: Colors.white70,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
```

Then make every row use it. In each of the places below, replace the row's own title widget (a `Text(...)`, or a `Row` holding a `Text` and a `TextButton`) and the `SizedBox(height: 16)` or `SizedBox(height: 12)` that follows it with the header call and `const SizedBox(height: 12)`:

| File and method | Replace with |
|---|---|
| `desktop_items.dart`, `_buildDesktopHorizontalSection` (the `Row` with `title` and the "View all" `TextButton`) | `_buildSectionHeader(context, title, onViewAll: onViewAll),` |
| `dashboard_sections.dart`, `_buildRecentlyPlayed` (`Text(l10n.playedLabel, ...)`) | `_buildSectionHeader(context, l10n.playedLabel, onViewAll: () => ref.read(appNavigationProvider.notifier).setItem(NavItem.recentlyPlayed)),` |
| `dashboard_sections.dart`, `_buildQuickPicks` (`Text(l10n.quickPicks, ...)`) | `_buildSectionHeader(context, l10n.quickPicks),` |
| `dashboard_sections.dart`, `_buildTopArtists` (`Text(l10n.featuredArtists, ...)`) | `_buildSectionHeader(context, l10n.featuredArtists, onViewAll: () => ref.read(appNavigationProvider.notifier).setItem(NavItem.artists)),` |
| `dashboard_sections.dart`, `_buildFeaturedAlbums` (the `Row` with `l10n.albums` and "View all") | `_buildSectionHeader(context, l10n.albums, onViewAll: () => ref.read(appNavigationProvider.notifier).setItem(NavItem.albums)),` |

`_buildDesktopHorizontalSection`, `_buildRecentlyPlayed`, `_buildQuickPicks` and `_buildTopArtists` do not receive a `BuildContext` today. Add `BuildContext context` as their first parameter and pass `context` from the call sites in `home_dashboard.dart` (Step 7). `_buildFeaturedAlbums` already has one.

- [ ] **Step 6: One card size, and a quick-picks grid that grows**

In `dashboard_sections.dart`:

- In `_buildRecentlyPlayed` and `_buildFeaturedAlbums`, the list height is `isNarrow ? 200 : 230`, the card width `isNarrow ? 120 : 140` and the image `isNarrow ? 104 : 124`. Leave the narrow values; these two rows already match each other.
- In `_buildQuickPicks`, delete the `crossAxisCount` variable and its `if`/`else if`, and replace the grid delegate with:

```dart
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 340,
                mainAxisExtent: 70,
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
              ),
```

  The `isMedium` parameter is then unused: remove it from the method signature.

In `desktop_items.dart`, `_buildDesktopHorizontalSection` uses `SizedBox(height: 180, ...)` for its list. Leave it: artist and genre tiles are shorter than album cards by design.

- [ ] **Step 7: Build the page from the ordered list**

In `home_dashboard.dart`, add to the imports (above the `part` lines):

```dart
import 'package:looper_player/ui/desktop/dashboard/desktop_home_sections.dart';
```

In `build`, delete everything from the comment `// Support desktop-specific helper rows at the very top` down to and including the closing brace of the `for (final section in settings.homeSectionOrder) { ... }` loop, and put this in its place:

```dart
        const gap = SizedBox(height: 28);

        for (final section in desktopHomeSections(
          showRecent: settings.showHomeRecent,
          showGenres: settings.showHomeGenres,
          showArtists: settings.showHomeArtists,
        )) {
          switch (section) {
            case DesktopHomeSection.quickPicks:
              orderedChildren.add(
                _buildQuickPicks(context, ref, isNarrow, isDynamic, l10n),
              );
            case DesktopHomeSection.recentlyPlayed:
              orderedChildren.add(
                _buildRecentlyPlayed(context, ref, isNarrow, isDynamic, l10n),
              );
            case DesktopHomeSection.featuredArtists:
              orderedChildren.add(
                _buildTopArtists(context, ref, isNarrow, isDynamic, l10n),
              );
            case DesktopHomeSection.albums:
              orderedChildren.add(
                _buildFeaturedAlbums(ref, isNarrow, isDynamic, context),
              );
            case DesktopHomeSection.genres:
              if (genres.isEmpty) continue;
              orderedChildren.add(
                _buildDesktopHorizontalSection(
                  context,
                  title: l10n.genres,
                  l10n: l10n,
                  onViewAll: () => ref
                      .read(appNavigationProvider.notifier)
                      .setItem(NavItem.genres),
                  itemCount: genres.length,
                  itemBuilder: (context, index) {
                    final genre = genres[index];
                    return _buildDesktopGenreItem(
                      ref,
                      genre,
                      genresMap[genre]!,
                      l10n,
                    );
                  },
                ),
              );
            case DesktopHomeSection.artists:
              if (library.artists.isEmpty) continue;
              orderedChildren.add(
                _buildDesktopHorizontalSection(
                  context,
                  title: l10n.artists,
                  l10n: l10n,
                  onViewAll: () => ref
                      .read(appNavigationProvider.notifier)
                      .setItem(NavItem.artists),
                  itemCount: library.artists.length,
                  itemBuilder: (context, index) =>
                      _buildDesktopArtistItem(ref, library.artists[index], l10n),
                ),
              );
          }
          orderedChildren.add(gap);
        }
```

Then:

- Delete the now-unused local `final bool isMedium = constraints.maxWidth < 1000;`.
- Delete the `_buildAlbumsIfSmall` method from `dashboard_sections.dart` (nothing calls it any more).
- Sections that return `SizedBox.shrink()` when empty (quick picks, recently played, featured artists, albums) would still be followed by a 28 px gap. Make them collapse cleanly: in each of those four builders, the empty/loading/error returns stay `SizedBox.shrink()`, and in the loop above wrap the add as shown for one case and apply the same to the other three:

```dart
            case DesktopHomeSection.quickPicks:
              final topSongs = ref.watch(topSongsProvider).value ?? const [];
              if (topSongs.isEmpty) continue;
              orderedChildren.add(
                _buildQuickPicks(context, ref, isNarrow, isDynamic, l10n),
              );
```

  using `ref.watch(dashboardRecentlyPlayedProvider).value ?? const []` for recently played, `ref.watch(artistsProvider).value ?? const []` for featured artists, and `ref.watch(albumsProvider).value ?? const []` for albums. These are the same providers the builders already watch.

These `ref.watch` calls sit inside the `LayoutBuilder` builder, as the builders' own watches already do in this file today; keep to the file's existing pattern.

- [ ] **Step 8: Verify on Linux**

Run: `flutter analyze lib/ui/desktop/dashboard`
Expected: no new issues, in particular no unused-parameter or unused-element warnings.

Run: `flutter run -d linux`, open Home:
1. Order top to bottom: Quick picks, Recently played, Featured artists, Albums, Genres, Artists.
2. All section titles share one left edge, size and weight; every "View all" sits at the same right edge and opens the matching page (Recently played, Artists, Albums, Genres).
3. No "My albums" block; no doubled Albums row.
4. Maximize: Quick picks gains columns (five or more at 1920 wide) instead of stretching four.
5. Turn off "Show genres row" / "Show artists row" in settings (available after Task 6; until then confirm with the defaults): the row disappears and no blank gap is left.
6. Fresh empty profile: Home shows the empty-library view, no stray headers.

- [ ] **Step 9: Format and commit**

```bash
dart format lib/ui/desktop/dashboard test/desktop_home_sections_test.dart
git add lib/ui/desktop/dashboard
git commit -m "Reorder and align the desktop home page sections"
```

---

### Task 5: Two-column songs list and artists polish

**Files:**
- Create: `lib/features/library/presentation/widgets/songs/song_columns.dart`
- Modify: `lib/features/library/presentation/widgets/songs/songs_list.dart` (the non-`shrinkWrap` branch of `build`, lines 351-397)
- Create: `lib/ui/desktop/widgets/hover_card.dart`
- Modify: `lib/features/library/presentation/widgets/library_grids.dart` (`AlbumsGrid`, `ArtistsGrid`, `_ArtistCard`, `_AlbumCard`)
- Test: `test/song_columns_test.dart`, `test/hover_card_test.dart`

**Interfaces:**
- Produces:
  - `songColumnsFor(double width, {required bool desktop, required bool searching}) -> int`
  - `HoverCard({required Widget child, VoidCallback? onTap, BorderRadius borderRadius, bool selected})`

- [ ] **Step 1: Write the failing tests**

`test/song_columns_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:looper_player/features/library/presentation/widgets/songs/song_columns.dart';

void main() {
  test('two columns once the list is 1100 wide on desktop', () {
    expect(songColumnsFor(1099, desktop: true, searching: false), 1);
    expect(songColumnsFor(1100, desktop: true, searching: false), 2);
    expect(songColumnsFor(1640, desktop: true, searching: false), 2);
  });

  test('never on phones and tablets', () {
    expect(songColumnsFor(1600, desktop: false, searching: false), 1);
  });

  test('one column while searching: rows may grow with a lyric snippet', () {
    expect(songColumnsFor(1600, desktop: true, searching: true), 1);
  });

  test('unbounded or unusable widths mean one column', () {
    expect(songColumnsFor(double.infinity, desktop: true, searching: false), 1);
    expect(songColumnsFor(double.nan, desktop: true, searching: false), 1);
    expect(songColumnsFor(0, desktop: true, searching: false), 1);
  });
}
```

`test/hover_card_test.dart`:

```dart
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:looper_player/ui/desktop/widgets/hover_card.dart';

void main() {
  Widget host({VoidCallback? onTap, bool selected = false}) => MaterialApp(
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: 160,
          height: 200,
          child: HoverCard(
            onTap: onTap,
            selected: selected,
            child: const Text('Artist'),
          ),
        ),
      ),
    ),
  );

  double scaleOf(WidgetTester tester) =>
      tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale;

  testWidgets('lifts while the pointer is over it', (tester) async {
    await tester.pumpWidget(host(onTap: () {}));
    expect(scaleOf(tester), 1.0);

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(tester.getCenter(find.text('Artist')));
    await tester.pumpAndSettle();
    expect(scaleOf(tester), greaterThan(1.0));

    await mouse.moveTo(Offset.zero);
    await tester.pumpAndSettle();
    expect(scaleOf(tester), 1.0);
  });

  testWidgets('taps reach the callback', (tester) async {
    var taps = 0;
    await tester.pumpWidget(host(onTap: () => taps++));
    await tester.tap(find.text('Artist'));
    expect(taps, 1);
  });

  testWidgets('without a callback it does not react to hover', (tester) async {
    await tester.pumpWidget(host());
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(tester.getCenter(find.text('Artist')));
    await tester.pumpAndSettle();
    expect(scaleOf(tester), 1.0);
  });
}
```

- [ ] **Step 2: Run them to verify they fail**

Run: `flutter test test/song_columns_test.dart test/hover_card_test.dart`
Expected: FAIL to compile, both target files missing.

- [ ] **Step 3: Implement the two helpers**

Create `lib/features/library/presentation/widgets/songs/song_columns.dart`:

```dart
/// From this list width a desktop songs list shows two columns.
const double songTwoColumnWidth = 1100;

/// How many columns the songs list shows. Two only on desktop, on a list
/// at least [songTwoColumnWidth] wide, and not while searching (a search
/// hit can add a lyric snippet, which makes rows different heights).
int songColumnsFor(
  double width, {
  required bool desktop,
  required bool searching,
}) {
  if (!desktop || searching || !width.isFinite) return 1;
  return width >= songTwoColumnWidth ? 2 : 1;
}
```

Create `lib/ui/desktop/widgets/hover_card.dart`:

```dart
import 'package:flutter/material.dart';

/// A clickable card for grids on mouse platforms: it brightens and lifts
/// slightly under the pointer, and stays highlighted while [selected].
class HoverCard extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final BorderRadius borderRadius;
  final bool selected;

  const HoverCard({
    super.key,
    required this.child,
    this.onTap,
    this.borderRadius = const BorderRadius.all(Radius.circular(24)),
    this.selected = false,
  });

  @override
  State<HoverCard> createState() => _HoverCardState();
}

class _HoverCardState extends State<HoverCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final active = _hovered && widget.onTap != null;
    final lit = active || widget.selected;

    return MouseRegion(
      cursor: widget.onTap == null
          ? SystemMouseCursors.basic
          : SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: active ? 1.03 : 1.0,
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOutCubic,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOutCubic,
            decoration: BoxDecoration(
              borderRadius: widget.borderRadius,
              color: lit
                  ? Colors.white.withValues(alpha: 0.06)
                  : Colors.transparent,
              border: Border.all(
                color: lit
                    ? Colors.white.withValues(alpha: 0.10)
                    : Colors.transparent,
              ),
            ),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `flutter test test/song_columns_test.dart test/hover_card_test.dart`
Expected: all tests PASS.

- [ ] **Step 5: Two columns in `SongsList`**

In `songs_list.dart`, add imports:

```dart
import 'package:looper_player/core/utils/ui_utils.dart';

import 'song_columns.dart';
```

In `build`, the `else` branch currently is `Expanded(child: AppRefreshIndicator(onRefresh: ..., child: ListView.builder(...)))`. Restructure it so the existing `ListView.builder` is built by a local function and the desktop path can choose a grid. Add these two methods to `_SongsListState` and call the first from the `else` branch:

```dart
  Widget _buildRow(int index, AppLocalizations l10n) {
    final song = widget.songs[index];
    return SongTile(
      key: ValueKey(song.path),
      song: song,
      l10n: l10n,
      songs: widget.songs,
      searchQuery: widget.searchQuery,
      playlist: widget.playlist,
      selectionMode: _isSelecting,
      selected: _selectedPaths.contains(song.path),
      onToggleSelect: () => _toggleSelected(song),
      onEnterSelection: () => _enterSelection(song),
    );
  }

  /// Desktop only: the same rows laid out two across. 72 is the height of
  /// a two-line SongTile.
  Widget _buildTwoColumnGrid(AppLocalizations l10n) {
    return GridView.builder(
      controller: widget.controller,
      physics:
          widget.physics ??
          const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
      padding: const EdgeInsets.fromLTRB(0, 8, 0, 180),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisExtent: 72,
        crossAxisSpacing: 24,
      ),
      itemCount: widget.songs.length,
      itemBuilder: (context, index) => _buildRow(index, l10n),
    );
  }
```

Then, inside the `else` branch, name the existing list and wrap it:

```dart
        else
          Expanded(
            child: AppRefreshIndicator(
              onRefresh: () => ref
                  .read(libraryProvider.notifier)
                  .scanSavedFolders(showVisualIndicator: false),
              child: UiUtils.isDesktop
                  ? LayoutBuilder(
                      builder: (context, constraints) =>
                          songColumnsFor(
                                constraints.maxWidth,
                                desktop: true,
                                searching:
                                    widget.searchQuery?.isNotEmpty ?? false,
                              ) ==
                              2
                          ? _buildTwoColumnGrid(l10n)
                          : _buildSingleColumnList(l10n),
                    )
                  : _buildSingleColumnList(l10n),
            ),
          ),
```

where `_buildSingleColumnList(AppLocalizations l10n)` is a new method whose body is `return` followed by the existing `ListView.builder(...)` expression moved verbatim (controller, `shrinkWrap: false`, physics, padding, `itemCount`, `prototypeItem`, `itemBuilder`), unchanged. Do not replace its `itemBuilder` with `_buildRow`; leaving the moved code byte-for-byte the same is what keeps the Android path identical.

- [ ] **Step 6: Polish the artists and albums grids**

`library_grids.dart` is built only by the desktop shell. Confirm before editing:

Run: `grep -rn "ArtistsGrid()\|AlbumsGrid()" lib`
Expected: only `lib/ui/home_screen/home_screen.dart`.

Add the import:

```dart
import 'package:looper_player/ui/desktop/widgets/hover_card.dart';
```

In `ArtistsGrid.build`, replace the `GridView.builder` padding and delegate with:

```dart
        padding: EdgeInsets.fromLTRB(24.s, 16.s, 24.s, 140),
        gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 190.s,
          childAspectRatio: 0.82,
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
        ),
```

In `AlbumsGrid.build`, change only the padding to `EdgeInsets.fromLTRB(24.s, 16.s, 24.s, 140)` so the last row clears the player bar there too.

In `_ArtistCard.build`:

1. Move the body of the `InkWell`'s `onTap` closure into a local `Future<void> openArtist() async { ... }` declared before `return`, unchanged.
2. Replace the `InkWell(onTap: ..., borderRadius: ..., child: AnimatedContainer(... decoration: BoxDecoration(...), child: Column(...)))` with:

```dart
    return HoverCard(
      onTap: openArtist,
      selected: isSelected,
      child: Padding(
        padding: EdgeInsets.all(12.s),
        child: Column(
          children: [
            // the existing Expanded(...) with the circular image, unchanged
            // the existing SizedBox(height: 12), unchanged
            // the existing artist-name Text, with the style below
          ],
        ),
      ),
    );
```

   keeping the three existing `Column` children in place, and changing the name `Text` to be centred and medium weight:

```dart
            Text(
              artist.name,
              textAlign: TextAlign.center,
              style: AppFonts.jostStyle(
                fontWeight: FontWeight.w500,
                fontSize: 14.ts,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
```

3. The `isDynamic` local in `_ArtistCard.build` and in `ArtistsGrid.build` is then unused: delete those two lines.

Apply the same wrapper to `_AlbumCard`: its root is also an `InkWell` around an `AnimatedContainer` with a selected-state decoration. Replace that pair with `HoverCard(onTap: <the same closure, moved to a local function>, selected: isSelected, child: Padding(padding: EdgeInsets.all(12.s), child: <the AnimatedContainer's existing child>))`, leaving the image and text children untouched.

- [ ] **Step 7: Verify on Linux**

Run: `flutter analyze lib/features/library/presentation/widgets lib/ui/desktop/widgets`
Expected: no new issues.

Run: `flutter run -d linux`:
1. Songs at the default 1150 wide window: one column, as before.
2. Maximize: two columns. Rows are evenly tall, nothing is clipped, the playing-song highlight, long-press selection, the options button and click-to-play all work in both columns. Playing a song in the right column continues to the next song in list order.
3. Type in the search box: results are one column even when maximized.
4. Drag the window narrower: it returns to one column without losing the scroll position by more than a row.
5. Artists: cards brighten and lift under the pointer, the pointer becomes a hand, names are centred, the selected artist stays highlighted, the last row is not hidden behind the player bar.
6. Albums: same hover behaviour.

If two-line `SongTile` rows are not 72 px tall on this build (text clipped or loose), measure one with the Flutter inspector and use that height for `mainAxisExtent`.

- [ ] **Step 8: Format and commit**

```bash
dart format lib/features/library/presentation/widgets lib/ui/desktop/widgets test/song_columns_test.dart test/hover_card_test.dart
git add lib/features/library/presentation/widgets/songs/song_columns.dart lib/features/library/presentation/widgets/songs/songs_list.dart lib/features/library/presentation/widgets/library_grids.dart lib/ui/desktop/widgets/hover_card.dart
git commit -m "Two-column songs list on wide desktop windows; hover feedback on artist and album cards"
```

---

### Task 6: Collapsible settings with the Android options and About

**Files:**
- Create: `lib/ui/desktop/settings/collapsible_settings_section.dart`
- Modify: `lib/ui/desktop/settings/settings_rows.dart` (`_Section`, lines 3-47)
- Modify: `lib/ui/desktop/settings/settings_view.dart` (section list)
- Test: `test/collapsible_settings_section_test.dart`

**Interfaces:**
- Produces: `CollapsibleSettingsSection({required String id, required String title, required IconData icon, required List<Widget> children, bool initiallyExpanded = false})`

First confirm which settings page each platform uses:

Run: `grep -n "settings_view.dart" lib/ui/android/shell/android_main_screen.dart lib/ui/home_screen/home_screen.dart`
Expected: Android imports `features/settings/presentation/screens/settings_view/settings_view.dart`; the Linux shell imports `ui/desktop/settings/settings_view.dart`. If Android also imports the desktop file, stop and report: this task would then change Android.

- [ ] **Step 1: Write the failing tests**

`test/collapsible_settings_section_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:looper_player/ui/desktop/settings/collapsible_settings_section.dart';

void main() {
  setUp(CollapsibleSettingsSection.resetRememberedState);

  Widget host({required String id, bool initiallyExpanded = false}) =>
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: CollapsibleSettingsSection(
              id: id,
              title: 'Appearance',
              icon: Icons.palette,
              initiallyExpanded: initiallyExpanded,
              children: const [Text('Row one'), Text('Row two')],
            ),
          ),
        ),
      );

  testWidgets('starts collapsed and expands on click', (tester) async {
    await tester.pumpWidget(host(id: 'a'));
    expect(find.text('Appearance'), findsOneWidget);
    expect(find.text('Row one'), findsNothing);

    await tester.tap(find.text('Appearance'));
    await tester.pumpAndSettle();
    expect(find.text('Row one'), findsOneWidget);
    expect(find.text('Row two'), findsOneWidget);

    await tester.tap(find.text('Appearance'));
    await tester.pumpAndSettle();
    expect(find.text('Row one'), findsNothing);
  });

  testWidgets('can start expanded', (tester) async {
    await tester.pumpWidget(host(id: 'b', initiallyExpanded: true));
    expect(find.text('Row one'), findsOneWidget);
  });

  testWidgets('remembers its state when the page is rebuilt', (tester) async {
    await tester.pumpWidget(host(id: 'c'));
    await tester.tap(find.text('Appearance'));
    await tester.pumpAndSettle();

    // Leave the page and come back.
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await tester.pumpWidget(host(id: 'c'));
    expect(find.text('Row one'), findsOneWidget);
  });

  testWidgets('sections remember independently', (tester) async {
    await tester.pumpWidget(host(id: 'd'));
    await tester.tap(find.text('Appearance'));
    await tester.pumpAndSettle();

    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await tester.pumpWidget(host(id: 'e'));
    expect(find.text('Row one'), findsNothing);
  });

  testWidgets('the header is reachable from the keyboard', (tester) async {
    await tester.pumpWidget(host(id: 'f'));
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.text('Row one'), findsOneWidget);
  });
}
```

Add `import 'package:flutter/services.dart';` at the top of that test for `LogicalKeyboardKey`.

- [ ] **Step 2: Run them to verify they fail**

Run: `flutter test test/collapsible_settings_section_test.dart`
Expected: FAIL to compile, "Target of URI doesn't exist: collapsible_settings_section.dart".

- [ ] **Step 3: Implement the section**

Create `lib/ui/desktop/settings/collapsible_settings_section.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:looper_player/ui/android/widgets/premium_section.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// A settings group that opens and closes when its header is clicked.
/// Whether it is open is remembered per [id] for as long as the app runs,
/// so leaving the settings page and coming back keeps the layout.
class CollapsibleSettingsSection extends StatefulWidget {
  final String id;
  final String title;
  final IconData icon;
  final List<Widget> children;
  final bool initiallyExpanded;

  const CollapsibleSettingsSection({
    super.key,
    required this.id,
    required this.title,
    required this.icon,
    required this.children,
    this.initiallyExpanded = false,
  });

  static final Map<String, bool> _remembered = {};

  @visibleForTesting
  static void resetRememberedState() => _remembered.clear();

  @override
  State<CollapsibleSettingsSection> createState() =>
      _CollapsibleSettingsSectionState();
}

class _CollapsibleSettingsSectionState
    extends State<CollapsibleSettingsSection> {
  late bool _expanded =
      CollapsibleSettingsSection._remembered[widget.id] ??
      widget.initiallyExpanded;

  void _toggle() {
    setState(() => _expanded = !_expanded);
    CollapsibleSettingsSection._remembered[widget.id] = _expanded;
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: PremiumSection(
        borderRadius: BorderRadius.circular(20),
        padding: EdgeInsets.zero,
        useExpanded: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: _toggle,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 16,
                ),
                child: Row(
                  children: [
                    Icon(widget.icon, size: 18, color: Colors.white70),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        widget.title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    AnimatedRotation(
                      turns: _expanded ? 0.5 : 0,
                      duration: const Duration(milliseconds: 180),
                      child: const Icon(
                        LucideIcons.chevronDown,
                        size: 18,
                        color: Colors.white54,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOutCubic,
              alignment: Alignment.topCenter,
              child: _expanded
                  ? Column(
                      children: [
                        const Divider(height: 1, color: Colors.white10),
                        ...widget.children,
                      ],
                    )
                  : const SizedBox(width: double.infinity),
            ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `flutter test test/collapsible_settings_section_test.dart`
Expected: all tests PASS. If `PremiumSection` needs a `ProviderScope` (it reads settings for blur), wrap the test `host` in `ProviderScope(child: ...)`, or follow how `test/analyze_view_render_test.dart` hosts widgets that contain `PremiumSection`.

- [ ] **Step 5: Make the existing desktop sections collapsible**

In `lib/ui/desktop/settings/settings_view.dart`, add imports (`dart:io` only if missing):

```dart
import 'package:looper_player/core/theme/app_assets.dart';
import 'package:looper_player/core/utils/app_links.dart';
import 'package:looper_player/features/settings/presentation/widgets/tiles/about_settings_tiles.dart';
import 'package:looper_player/features/settings/presentation/widgets/tiles/audio_playback_settings_tiles.dart';
import 'package:looper_player/features/settings/presentation/widgets/tiles/backup_logs_settings_tiles.dart';
import 'package:looper_player/features/settings/presentation/widgets/tiles/dashboard_settings_tiles.dart';
import 'package:looper_player/features/settings/presentation/widgets/tiles/theme/theme_settings_tiles.dart';
import 'collapsible_settings_section.dart';
```

In `lib/ui/desktop/settings/settings_rows.dart`, replace the whole `_Section` class with a thin wrapper, so every existing `_Section(title: ..., children: [...])` call keeps working:

```dart
class _Section extends StatelessWidget {
  final String title;
  final IconData icon;
  final bool initiallyExpanded;
  final List<Widget> children;

  const _Section({
    required this.title,
    required this.children,
    this.icon = LucideIcons.settings,
    this.initiallyExpanded = false,
  });

  @override
  Widget build(BuildContext context) {
    return CollapsibleSettingsSection(
      // The title is unique per section and stable within a session.
      id: title,
      title: title,
      icon: icon,
      initiallyExpanded: initiallyExpanded,
      children: children,
    );
  }
}
```

In `settings_view.dart`, give each existing `_Section(` call an icon, and open the first one:

| Section title | Add |
|---|---|
| `l10n.appearance` | `icon: LucideIcons.palette, initiallyExpanded: true,` |
| `l10n.audioPlayback` | `icon: LucideIcons.sliders,` |
| `l10n.librarySettings` | `icon: LucideIcons.listMusic,` |
| `l10n.aboutApp` | (this section is replaced in Step 7) |

All four icons are already used elsewhere in the repo, so they resolve.

- [ ] **Step 6: Add the sections built from the shared tiles**

In `settings_view.dart`, each section is a `SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 20.0), child: _Section(...)))`. Add the following sections in that same wrapper, placed as stated. `divider` stands for `const Divider(height: 1, indent: 72, color: Colors.white10)`; declare it once as a local at the top of `build`:

```dart
    const divider = Divider(height: 1, indent: 72, color: Colors.white10);
    final dynamicTheming = settings.enableDynamicTheming;
```

Directly after the Appearance section:

```dart
                _Section(
                  title: l10n.themeGroupFonts,
                  icon: LucideIcons.languages,
                  children: [
                    const UseNewFontTile(),
                    if (settings.useNewFont) ...[
                      divider,
                      const FontFamilySelectionTile(),
                      divider,
                      const FontWeightSelectionTile(),
                    ],
                    divider,
                    const UseNewFontLyricsTile(),
                    if (settings.useNewFontLyrics) ...[
                      divider,
                      const LyricsFontFamilySelectionTile(),
                      divider,
                      const LyricsFontWeightSelectionTile(),
                    ],
                  ],
                ),
```

```dart
                _Section(
                  title: l10n.lyrics,
                  icon: LucideIcons.alignCenter,
                  children: [
                    const AmbientLyricsBgTile(),
                    divider,
                    const BlurredArtworkLyricsTile(),
                    if (dynamicTheming ||
                        settings.ambientColorBackground ||
                        settings.keepBackgroundGradient ||
                        settings.blurredArtworkForLyrics) ...[
                      divider,
                      const LyricsDarknessSlider(),
                    ],
                    divider,
                    const LyricsProviderTile(),
                  ],
                ),
```

```dart
                _Section(
                  title: l10n.nowPlaying,
                  icon: LucideIcons.music,
                  children: [
                    const ProgressBarStyleTile(),
                    divider,
                    const EnablePlayerGradientTile(),
                    if (settings.enablePlayerGradient) ...[
                      divider,
                      const AnimatePlayerGradientTile(),
                      divider,
                      const KeepBackgroundGradientTile(),
                      if (settings.keepBackgroundGradient) ...[
                        divider,
                        const AnimateBackgroundGradientTile(),
                      ],
                    ],
                    if (!dynamicTheming) ...[
                      divider,
                      const AlwaysBlurSheetsTile(),
                    ],
                  ],
                ),
```

```dart
                _Section(
                  title: l10n.homeDashboardSettings,
                  icon: LucideIcons.listOrdered,
                  children: const [
                    ShowRecentRowTile(),
                    divider,
                    ShowGenresRowTile(),
                    divider,
                    ShowArtistsRowTile(),
                  ],
                ),
```

Inside the existing Audio/Playback section, append to its `children` (after the existing rows, each preceded by `divider`): `const ShuffleTile()`, `const PersistQueueTile()`, `const KeepSongProgressTile()`.

Directly after the Library section:

```dart
                _Section(
                  title: l10n.backupsAndLogs,
                  icon: LucideIcons.share2,
                  children: const [
                    ExportBackupTile(),
                    divider,
                    ImportBackupTile(),
                    divider,
                    ExportLogsTile(),
                    divider,
                    ClearLogsTile(),
                  ],
                ),
```

Left out on purpose (phone-only or not built on Linux): `HapticFeedbackTile`, `StopServiceTile`, `ManageAudioFocusTile`, `ResumeAfterCallTile`, `ResumeOnBluetoothConnectTile`, `FluidPlayerTile`, `ArtworkVisualizerTile`, `ShowQualityBadgeTile`, `QualityBadgeStyleTile`, `SegmentedUtilityButtonsTile`, `IncludeSystemAndMessagingAudioTile`, `ReorderDashboardSectionsTile`, `ShowAlbumsRowTile` (the desktop Albums row is always shown).

The Lyrics rows that the Appearance section already has (dynamic lyrics background, active-line colour, intensity, alignment) stay where they are; the new Lyrics section only adds what was missing, so nothing is listed twice. If a tile added above duplicates a row the desktop page already has under a different widget, drop the new tile and keep the existing row.

- [ ] **Step 7: Replace the About section**

Replace the existing `_Section(title: l10n.aboutApp, ...)` (near line 335 onwards, through its closing `)`) with a section that mirrors the Android About page (`settings_category_screen.dart`, `categoryId == 'about'`):

```dart
                _Section(
                  title: l10n.aboutApp,
                  icon: LucideIcons.user,
                  children: [
                    const LooperVersionTile(),
                    divider,
                    const CheckForUpdatesTile(),
                    divider,
                    AboutMaintainerRow(
                      name: 'Nilesh Suthar',
                      role: l10n.creatorAndMaintainer,
                      avatar: AppAssets.maintainerAvatar,
                      github: AppLinks.nileshGithub,
                      telegram: AppLinks.nileshTelegram,
                    ),
                    divider,
                    AboutMaintainerRow(
                      name: 'Krn.',
                      role: l10n.designerAndMaintainer,
                      avatar: AppAssets.designerAvatar,
                      github: AppLinks.karanGithub,
                      telegram: AppLinks.karanTelegram,
                    ),
                    divider,
                    AboutMaintainerRow(
                      name: 'Madan Suthar',
                      role: 'Free Rider',
                      avatar: AppAssets.freeRiderAvatar,
                      github: AppLinks.madanGithub,
                      telegram: AppLinks.madanTelegram,
                    ),
                    divider,
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 16,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            l10n.appInfoPrivacy.toUpperCase(),
                            style: AppFonts.jostStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Color(
                                settings.accentColor,
                              ).withValues(alpha: 0.8),
                              letterSpacing: 1.0,
                            ),
                          ),
                          const SizedBox(height: 16),
                          InfoSubTile(
                            icon: LucideIcons.music,
                            title: l10n.corePurpose,
                            description: l10n.corePurposeDesc,
                          ),
                          const SizedBox(height: 16),
                          InfoSubTile(
                            icon: LucideIcons.globe,
                            title: l10n.whyInternetUsed,
                            description: l10n.whyInternetUsedDesc,
                          ),
                          const SizedBox(height: 16),
                          InfoSubTile(
                            icon: LucideIcons.lock,
                            title: l10n.privacySafety,
                            description: l10n.privacySafetyDesc,
                          ),
                        ],
                      ),
                    ),
                    divider,
                    const GitHubStarTile(),
                    divider,
                    const OpenSourceLicensesTile(),
                    divider,
                    const LyricsCreditsSection(),
                  ],
                ),
```

The Android page's "Why permissions are used" note is left out: Linux asks for no permissions. Before deleting the old About section, check whether it contains a row with no equivalent above (the old page has "Source code" and "Lyrics sources" rows): `GitHubStarTile` and `LyricsCreditsSection` cover those. `CheckForUpdatesTile` and `LyricsCreditsSection` take constructor arguments in some versions; if either does not have a no-argument `const` constructor, construct it the way `settings_category_screen.dart` does. Add `import 'package:looper_player/core/theme/app_fonts.dart';` if the file doesn't have it.

If `settings_view.dart` passes 800 lines after these additions, move the new section builders into a new part file `lib/ui/desktop/settings/settings_sections.dart` (`part of 'settings_view.dart';`), one function per section taking `(AppLocalizations l10n, AppSettings settings)`.

- [ ] **Step 8: Verify on Linux**

Run: `flutter analyze lib/ui/desktop/settings`
Expected: no new issues.

Run: `flutter run -d linux`, open Settings:
1. Nine cards: Appearance (open), Fonts, Lyrics, Now playing, Home, Playback and audio, Library, Backups and logs, About (all closed).
2. Clicking a header opens it with a short animation and turns the chevron; clicking again closes it. Several can be open at once.
3. Open Fonts and About, go to Songs, come back: Fonts and About are still open.
4. Every toggle, slider and dropdown in the new sections changes the app as it does on Android: font family, lyrics provider, progress bar style, player gradient, home row toggles (Home updates), export logs.
5. About shows the version, the three maintainers with working links, the privacy notes, GitHub, licences and lyrics credits.
6. Tab moves focus between headers; Enter toggles the focused one.
7. No option appears twice across sections.

- [ ] **Step 9: Format and commit**

```bash
dart format lib/ui/desktop/settings test/collapsible_settings_section_test.dart
git add lib/ui/desktop/settings
git commit -m "Collapsible desktop settings with fonts, lyrics, player, home, backups and About"
```

---

### Task 7: Landscape equalizer dialog

**Files:**
- Create: `lib/ui/desktop/equalizer/desktop_equalizer_dialog.dart`
- Modify: `lib/ui/android/player/equalizer/android_equalizer_screen.dart` (constructor; the scroll body at lines 240-1085)
- Modify the four openers: `lib/ui/widgets/player/player_bar/player_bar.dart:482-490`, `lib/ui/widgets/sheets/song_options_bottom_sheet.dart:~467`, `lib/ui/desktop/settings/settings_view.dart:~381`, `lib/features/settings/presentation/widgets/tiles/playback_settings_tiles.dart:~265`
- Test: `test/desktop_equalizer_dialog_test.dart`

**Interfaces:**
- Produces:
  - `equalizerDialogSize(Size window) -> Size`
  - `equalizerUsesTwoColumns(double dialogWidth) -> bool`
  - `showDesktopEqualizer(BuildContext context) -> Future<void>`
  - `AndroidEqualizerScreen({super.key, bool twoColumn = false})`

- [ ] **Step 1: Write the failing tests**

`test/desktop_equalizer_dialog_test.dart`:

```dart
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:looper_player/ui/desktop/equalizer/desktop_equalizer_dialog.dart';

void main() {
  group('equalizerDialogSize', () {
    test('is always wider than tall', () {
      for (final window in const [
        Size(720, 480),
        Size(800, 1200),
        Size(1150, 700),
        Size(1920, 1080),
        Size(3840, 2160),
        Size(600, 2000),
      ]) {
        final size = equalizerDialogSize(window);
        expect(size.width, greaterThan(size.height), reason: '$window');
      }
    });

    test('never exceeds the window minus its margin', () {
      for (final window in const [Size(720, 480), Size(1150, 700), Size(900, 400)]) {
        final size = equalizerDialogSize(window);
        expect(size.width, lessThanOrEqualTo(window.width - 64));
        expect(size.height, lessThanOrEqualTo(window.height - 64));
      }
    });

    test('stops growing at 1100 wide', () {
      final size = equalizerDialogSize(const Size(3840, 2160));
      expect(size.width, 1100);
      expect(size.height, closeTo(770, 0.01));
    });

    test('the default window gives a two-column dialog', () {
      final size = equalizerDialogSize(const Size(1150, 700));
      expect(size.width, 1086);
      expect(size.height, 636);
      expect(equalizerUsesTwoColumns(size.width), isTrue);
    });

    test('the minimum window falls back to one column', () {
      final size = equalizerDialogSize(const Size(720, 480));
      expect(size.width, 656);
      expect(size.height, 416);
      expect(equalizerUsesTwoColumns(size.width), isFalse);
    });

    test('a degenerate window still yields a positive size', () {
      final size = equalizerDialogSize(const Size(40, 40));
      expect(size.width, greaterThan(0));
      expect(size.height, greaterThan(0));
      expect(size.width, greaterThan(size.height));
    });
  });

  test('two columns from 820 wide', () {
    expect(equalizerUsesTwoColumns(819), isFalse);
    expect(equalizerUsesTwoColumns(820), isTrue);
  });
}
```

- [ ] **Step 2: Run them to verify they fail**

Run: `flutter test test/desktop_equalizer_dialog_test.dart`
Expected: FAIL to compile, "Target of URI doesn't exist: desktop_equalizer_dialog.dart".

- [ ] **Step 3: Implement the dialog**

Create `lib/ui/desktop/equalizer/desktop_equalizer_dialog.dart`:

```dart
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:looper_player/ui/android/player/equalizer/android_equalizer_screen.dart';

const double _margin = 64;
const double _maxWidth = 1100;
const double _twoColumnWidth = 820;

/// The equalizer dialog's size for a window: as wide as allowed, and always
/// wider than it is tall (at most 70% as tall as wide).
Size equalizerDialogSize(Size window) {
  final width = math.max(math.min(_maxWidth, window.width - _margin), 120.0);
  final height = math.max(
    math.min(window.height - _margin, width * 0.7),
    math.min(80.0, width * 0.7),
  );
  return Size(width, height);
}

bool equalizerUsesTwoColumns(double dialogWidth) =>
    dialogWidth >= _twoColumnWidth;

/// Desktop: the equalizer as a centred landscape dialog instead of a
/// phone-shaped sheet.
Future<void> showDesktopEqualizer(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (context) {
      final size = equalizerDialogSize(MediaQuery.sizeOf(context));
      return Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: EdgeInsets.zero,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: SizedBox.fromSize(
            size: size,
            child: AndroidEqualizerScreen(
              twoColumn: equalizerUsesTwoColumns(size.width),
            ),
          ),
        ),
      );
    },
  );
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `flutter test test/desktop_equalizer_dialog_test.dart`
Expected: FAIL to compile until Step 5 adds the `twoColumn` parameter. Do Step 5, then run again; expected: all tests PASS.

- [ ] **Step 5: Give the equalizer screen a two-column mode**

In `lib/ui/android/player/equalizer/android_equalizer_screen.dart`:

Add the parameter to the widget (keep its existing constructor shape; if it is `const AndroidEqualizerScreen({super.key});`):

```dart
  /// Desktop dialog only: bands on the left, DSP cards on the right.
  final bool twoColumn;

  const AndroidEqualizerScreen({super.key, this.twoColumn = false});
```

If `build` lives in a `State`/`ConsumerState` class, read it as `widget.twoColumn`; otherwise as `twoColumn`.

The scroll body is, today:

```dart
              Expanded(
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 16,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Preset Selector Row ... (presets, playing-song
                      // details, band sliders, pre-amp card)
                      const SizedBox(height: 16),

                      // Advanced DSP Panels (Only visible when EQ is enabled)
                      if (eqState.enabled) ...[ /* DSP cards */ ],

                      const SizedBox(height: 24),
                      /* anything after it, to the end of the list */
                    ],
                  ),
                ),
              ),
```

Split the `children` list into two named lists at the `// Advanced DSP Panels` comment, without changing, reordering or re-indenting any element's own code:

1. Directly above `return Scaffold(`, declare `final mainSections = <Widget>[ ... ];` containing every element from `// Preset Selector Row` up to and including the `const SizedBox(height: 16),` just before `// Advanced DSP Panels`.
2. Below it, declare `final dspSections = <Widget>[ ... ];` containing every element from `if (eqState.enabled) ...[` to the end of the original list.
3. Replace the `Expanded(child: SingleChildScrollView(...))` with:

```dart
              Expanded(
                child: twoColumn
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            flex: 3,
                            child: SingleChildScrollView(
                              physics: const BouncingScrollPhysics(),
                              padding: const EdgeInsets.fromLTRB(
                                20,
                                16,
                                12,
                                16,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: mainSections,
                              ),
                            ),
                          ),
                          const VerticalDivider(
                            width: 1,
                            color: Colors.white10,
                          ),
                          Expanded(
                            flex: 2,
                            child: SingleChildScrollView(
                              physics: const BouncingScrollPhysics(),
                              padding: const EdgeInsets.fromLTRB(
                                12,
                                16,
                                20,
                                16,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: dspSections,
                              ),
                            ),
                          ),
                        ],
                      )
                    : SingleChildScrollView(
                        physics: const BouncingScrollPhysics(),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 16,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [...mainSections, ...dspSections],
                        ),
                      ),
              ),
```

(use `widget.twoColumn` if applicable). With `twoColumn` false, the tree is the same `SingleChildScrollView` > `Column` with the same children in the same order as before.

The moved elements reference locals of `build` (`eqState`, `eqNotifier`, `l10n`, `song`, `accentColor`, `barModeHeight`, `isGraphMode`, `context`). They must all be declared before the two lists; they already are, since they are declared at the top of `build`. If any element uses a `Builder`/`LayoutBuilder` `context` from an enclosing widget rather than `build`'s, leave that enclosing widget whole inside its list.

Check the result:

Run: `git diff --stat lib/ui/android/player/equalizer/android_equalizer_screen.dart`
Expected: a large line count from re-indentation, which is fine.

Run: `git diff -w --ignore-blank-lines lib/ui/android/player/equalizer/android_equalizer_screen.dart | grep -c "^[+-][^+-]"`
Expected: a small number (roughly 60-80): only the new field, the two list declarations, and the new `Expanded` block. If it is in the hundreds, element code was changed while moving; redo the move.

- [ ] **Step 6: Open the dialog from all four places on desktop**

Add the imports to each of the four files:

```dart
import 'package:looper_player/core/utils/ui_utils.dart';
import 'package:looper_player/ui/desktop/equalizer/desktop_equalizer_dialog.dart';
```

In each opener, put this at the start of the tap handler, before the existing code that shows `AndroidEqualizerScreen`, and leave the existing code in place below it:

```dart
            if (UiUtils.isDesktop) {
              showDesktopEqualizer(context);
              return;
            }
```

- `player_bar.dart`: the equalizer `IconButton`'s `onPressed`, before `showModalBottomSheet(`.
- `song_options_bottom_sheet.dart`: the equalizer option's handler near line 467. If the handler first closes the sheet with `Navigator.pop(context)`, put the block after that pop, and use a context that is still mounted afterwards (the same one the existing code uses to show the equalizer).
- `lib/ui/desktop/settings/settings_view.dart`: the equalizer row near line 381. This file is desktop-only, so replace the existing open call with `showDesktopEqualizer(context);` outright.
- `playback_settings_tiles.dart`: `EqualizerTile`'s tap handler near line 265.

- [ ] **Step 7: Verify on Linux**

Run: `flutter analyze lib/ui/android/player/equalizer lib/ui/desktop/equalizer lib/ui/widgets/player/player_bar lib/ui/widgets/sheets lib/features/settings/presentation/widgets/tiles && flutter test test/desktop_equalizer_dialog_test.dart test/equalizer_gain_clamp_test.dart`
Expected: no new issues; tests PASS.

Run: `flutter run -d linux`:
1. Equalizer button in the player bar: a centred dialog, clearly wider than tall, with rounded corners; the page behind is dimmed.
2. At the default window: presets, band sliders and pre-amp on the left; DSP cards on the right; each side scrolls on its own.
3. With the equalizer switched off, the right side is empty and the left still shows the bands, as on Android.
4. Dragging bands, picking presets, switching graph/bar mode and every DSP control changes the sound.
5. The back button in its title bar, Escape and clicking outside all close it.
6. Window at 720x480: one column, still wider than tall, no overflow stripes.
7. The same dialog opens from the song options menu and from Settings.

- [ ] **Step 8: Format and commit**

```bash
dart format lib/ui/desktop/equalizer lib/ui/android/player/equalizer/android_equalizer_screen.dart lib/ui/widgets/player/player_bar/player_bar.dart lib/ui/widgets/sheets/song_options_bottom_sheet.dart lib/ui/desktop/settings/settings_view.dart lib/features/settings/presentation/widgets/tiles/playback_settings_tiles.dart test/desktop_equalizer_dialog_test.dart
git add lib/ui/desktop/equalizer lib/ui/android/player/equalizer/android_equalizer_screen.dart lib/ui/widgets/player/player_bar/player_bar.dart lib/ui/widgets/sheets/song_options_bottom_sheet.dart lib/ui/desktop/settings/settings_view.dart lib/features/settings/presentation/widgets/tiles/playback_settings_tiles.dart
git commit -m "Open the equalizer as a landscape two-column dialog on desktop"
```

`song_options_bottom_sheet.dart` and `playback_settings_tiles.dart` may carry the user's own uncommitted edits. Run `git diff` on each before staging; if there are changes that are not yours, stage only your hunk with `git apply --cached` on a patch of just that hunk, or leave the file unstaged and report it.

---

### Task 8: Whole-change verification and Android audit

**Files:** none modified unless a check fails.

- [ ] **Step 1: Analyze and test**

Run: `flutter analyze`
Expected: no issues in files this branch touched (`git diff main --stat` lists them).

Run: `flutter test`
Expected: all PASS, including `linux_tag_reader_test`, `desktop_shell_rules_test`, `desktop_home_sections_test`, `song_columns_test`, `hover_card_test`, `collapsible_settings_section_test`, `desktop_equalizer_dialog_test`.

- [ ] **Step 2: Android audit of the diff**

Run: `git diff main -- lib ':!lib/l10n' ':!*.g.dart'` and classify every hunk as one of:

- a new file used only by desktop code or pure logic;
- a change in a desktop-only file (`lib/ui/home_screen`, `lib/ui/desktop`, `library_grids.dart`);
- code behind `UiUtils.isDesktop` / `Platform.isLinux`;
- an optional parameter Android never passes (`AndroidEqualizerScreen.twoColumn`).

Then confirm specifically:

```bash
git diff main --stat -- lib/ui/android
```

Expected from this plan: only `android_equalizer_screen.dart` (plus `android_lyrics_menu_sheet.dart` if the foundation plan is on the same branch).

```bash
grep -rn "twoColumn" lib
```

Expected: the field and its uses in `android_equalizer_screen.dart`, and the single `twoColumn:` argument in `desktop_equalizer_dialog.dart`.

```bash
git diff main -- pubspec.yaml pubspec.lock lib/features/playback/presentation/providers/playback/playback_notifier.dart
```

Expected: no changes made by this branch.

In `scanner.dart`, re-read the edited block and confirm that with `Platform.isLinux` false, `linuxTags` is null and each of the seven assignments reduces to its previous expression.

In `songs_list.dart`, confirm the non-desktop path calls `_buildSingleColumnList`, whose `ListView.builder` is textually the one that was there before.

Any hunk that fits none of the four classes is a defect: fix it before continuing.

- [ ] **Step 3: Android build check**

```bash
JAVA_HOME=~/.jdks/corretto-21.0.8 flutter build apk --debug --flavor github
```

Expected: build succeeds. If a device is attached (`adb devices`), check the equalizer (one column, same order), the songs tab (one column) and a library rescan. If none is attached, say so in the report.

- [ ] **Step 4: Linux end-to-end pass**

Run: `flutter run -d linux` and walk through the manual checks of Tasks 1 to 7 in one session, at 720x480, 1150x700 and maximized.

- [ ] **Step 5: Report**

Summarise: test and analyzer results, the audit command outputs, whether the Android device check was possible, the `package.sh` dependency line still to be added by the user, and anything on Linux that differs from the expected behaviour. Do not merge or push.
