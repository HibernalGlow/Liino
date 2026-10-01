# Linux Window Foundation and Lyrics Sizing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the Linux build behave like a desktop app on large, resizable windows: sane window geometry, a UI scale, and lyrics whose size the user can control and that grows with the window.

**Architecture:** Pure sizing helpers (window class, UI scale steps, lyrics scale, window geometry) carry all the logic and are unit tested. Thin desktop-only widgets apply them: a root `DesktopUiScale` in `MaterialApp.builder`, a `WindowGeometryListener` around the home screen, and a desktop branch in `LyricsView` that adds a toolbar and feeds optional parameters into the shared lyric renderer.

**Tech Stack:** Flutter (Linux desktop), Riverpod, Isar (`AppSettings`), `window_manager` 0.5, `path_provider`, ARB localisation (14 languages).

**Spec:** `docs/superpowers/specs/2026-10-01-linux-window-foundation-and-lyrics-design.md`

## Global Constraints

- **Android must not change, in behaviour or pixels.** Every new behaviour is behind `UiUtils.isDesktop` or lives in desktop-only files. Shared widgets gain only optional parameters whose defaults reproduce today's behaviour.
- Do not touch `UiUtils.scale`, `lib/ui/widgets/common/player_scale.dart`, or restructure anything under `lib/ui/android`. The only edit there is the additive one in Task 7.
- `LyricsView` is embedded by `AndroidLyricsScreen` (`android_lyrics_screen.dart:511`). Its non-desktop path must build exactly today's widget tree.
- New `double` fields in `AppSettings` read back as `NaN` for rows saved before the field existed. Always pass them through the `normalize` helpers.
- Every field added to `AppSettings` must also be added to `_clone` in `settings_notifier.dart`, or updates silently drop it.
- All UI text goes through ARB files in all 14 languages (`lib/l10n/app_*.arb`); use `context.l10n`.
- Window minimum 720x480, default 1150x700. UI scale steps 0.8, 0.9, 1.0, 1.1, 1.25, 1.5. Lyrics scale range 0.6 to 2.5, step 0.1. Lyrics auto scale `(paneWidth / 760).clamp(1.0, 1.6)`. Lyrics column cap 900 px. Size classes: compact below 800, medium 800 to below 1400, expanded from 1400.
- `test/` is gitignored: tests run locally and are not committed.
- The working tree holds unrelated uncommitted changes. Work on a branch, and `git add` only the paths each task names. Never `git add -A`.
- Run `dart format` on every Dart file you edit.

## Review Focus

1. **Settings rows saved before this change** return `NaN` for `desktopUiScale` and `lyricsFontScale`. The UI must render at 100%, not blank or infinitely large. Pinned by the NaN tests in Task 1.
2. **Geometry saved on a monitor that is no longer connected.** The window must open on-screen, at a size that fits. Pinned by the off-screen and oversize tests in Task 3.
3. **Corrupt or half-written `window_state.json`** (app killed mid-write, hand-edited). The app must start with the default window. Pinned by the corrupt-input tests in Task 3.
4. **Changing the UI scale while the app is in use** must not reset navigation, scroll position or playback UI state. Pinned by the state-survives test in Task 4.
5. **A very narrow lyrics pane** (window at minimum width with the sidebar open, or 150% UI scale). The toolbar must not overflow. Pinned by the 360 px toolbar test in Task 7.

---

### Task 1: Pure sizing helpers

**Files:**
- Modify: `lib/core/utils/ui_utils.dart`
- Modify: `lib/core/utils/responsive.dart`
- Create: `lib/core/utils/ui_scale_steps.dart`
- Create: `lib/features/playback/presentation/widgets/lyrics/lyrics_scale.dart`
- Test: `test/desktop_sizing_helpers_test.dart`

**Interfaces:**
- Produces:
  - `UiUtils.isDesktop` (`static bool get`)
  - `enum WindowClass { compact, medium, expanded }`, `Responsive.windowClass(double width) -> WindowClass`
  - `UiScaleSteps.steps` (`List<double>`), `UiScaleSteps.normalize(double) -> double`, `.next(double) -> double`, `.previous(double) -> double`
  - `LyricsScale.min`, `.max`, `.step`, `LyricsScale.normalize(double) -> double`, `.stepBy(double value, int direction) -> double`, `.auto(double paneWidth) -> double`

- [ ] **Step 1: Create the branch**

```bash
git checkout -b linux-desktop-foundation
```

- [ ] **Step 2: Write the failing tests**

`test/desktop_sizing_helpers_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:looper_player/core/utils/responsive.dart';
import 'package:looper_player/core/utils/ui_scale_steps.dart';
import 'package:looper_player/features/playback/presentation/widgets/lyrics/lyrics_scale.dart';

void main() {
  group('Responsive.windowClass', () {
    test('splits at 800 and 1400', () {
      expect(Responsive.windowClass(720), WindowClass.compact);
      expect(Responsive.windowClass(799.9), WindowClass.compact);
      expect(Responsive.windowClass(800), WindowClass.medium);
      expect(Responsive.windowClass(1399.9), WindowClass.medium);
      expect(Responsive.windowClass(1400), WindowClass.expanded);
      expect(Responsive.windowClass(3840), WindowClass.expanded);
    });
  });

  group('UiScaleSteps', () {
    test('normalize snaps to the nearest step', () {
      expect(UiScaleSteps.normalize(1.0), 1.0);
      expect(UiScaleSteps.normalize(1.04), 1.0);
      expect(UiScaleSteps.normalize(1.2), 1.25);
      expect(UiScaleSteps.normalize(9), 1.5);
      expect(UiScaleSteps.normalize(0.1), 0.8);
    });

    test('values from before the setting existed mean 100%', () {
      expect(UiScaleSteps.normalize(double.nan), 1.0);
      expect(UiScaleSteps.normalize(0), 1.0);
      expect(UiScaleSteps.normalize(-1), 1.0);
      expect(UiScaleSteps.normalize(double.infinity), 1.0);
    });

    test('next and previous walk the steps and stop at the ends', () {
      expect(UiScaleSteps.next(1.0), 1.1);
      expect(UiScaleSteps.next(1.1), 1.25);
      expect(UiScaleSteps.next(1.5), 1.5);
      expect(UiScaleSteps.previous(1.0), 0.9);
      expect(UiScaleSteps.previous(0.8), 0.8);
      expect(UiScaleSteps.next(double.nan), 1.1);
    });
  });

  group('LyricsScale', () {
    test('normalize clamps to the renderer range', () {
      expect(LyricsScale.normalize(1.3), 1.3);
      expect(LyricsScale.normalize(0.2), 0.6);
      expect(LyricsScale.normalize(7), 2.5);
    });

    test('values from before the setting existed mean 100%', () {
      expect(LyricsScale.normalize(double.nan), 1.0);
      expect(LyricsScale.normalize(0), 1.0);
      expect(LyricsScale.normalize(double.infinity), 1.0);
    });

    test('stepBy moves by a tenth without float drift', () {
      expect(LyricsScale.stepBy(1.0, 1), 1.1);
      expect(LyricsScale.stepBy(1.1, 1), 1.2);
      expect(LyricsScale.stepBy(1.0, -1), 0.9);
      expect(LyricsScale.stepBy(2.5, 1), 2.5);
      expect(LyricsScale.stepBy(0.6, -1), 0.6);
      expect(LyricsScale.stepBy(double.nan, 1), 1.1);
    });

    test('auto grows with the pane, within limits', () {
      expect(LyricsScale.auto(400), 1.0);
      expect(LyricsScale.auto(760), 1.0);
      expect(LyricsScale.auto(950), 1.25);
      expect(LyricsScale.auto(1216), 1.6);
      expect(LyricsScale.auto(4000), 1.6);
      expect(LyricsScale.auto(double.infinity), 1.6);
      expect(LyricsScale.auto(double.nan), 1.0);
    });
  });
}
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `flutter test test/desktop_sizing_helpers_test.dart`
Expected: FAIL to compile, "Target of URI doesn't exist: ui_scale_steps.dart".

- [ ] **Step 4: Implement**

In `lib/core/utils/ui_utils.dart`, add below the `isLinux` getter (leave everything else untouched):

```dart
  /// Mouse-and-window platforms. Desktop-only behaviour keys off this.
  static bool get isDesktop =>
      Platform.isLinux || Platform.isWindows || Platform.isMacOS;
```

In `lib/core/utils/responsive.dart`, add the enum above the class and the members inside it:

```dart
/// How much horizontal room a desktop window offers.
enum WindowClass { compact, medium, expanded }
```

```dart
  /// From this width the sidebar is shown beside the content.
  static const double mediumWidth = 800;

  /// From this width there is room for extra panes.
  static const double expandedWidth = 1400;

  static WindowClass windowClass(double width) {
    if (width < mediumWidth) return WindowClass.compact;
    if (width < expandedWidth) return WindowClass.medium;
    return WindowClass.expanded;
  }
```

Create `lib/core/utils/ui_scale_steps.dart`:

```dart
/// The whole-UI scale a desktop user can pick.
class UiScaleSteps {
  static const List<double> steps = [0.8, 0.9, 1.0, 1.1, 1.25, 1.5];

  /// The nearest step. Rows saved before the setting existed read back as
  /// NaN - those, and anything else unusable, mean 100%.
  static double normalize(double value) {
    if (!value.isFinite || value <= 0) return 1.0;
    return steps.reduce(
      (a, b) => (value - a).abs() <= (value - b).abs() ? a : b,
    );
  }

  static double next(double value) {
    final i = steps.indexOf(normalize(value));
    return steps[(i + 1).clamp(0, steps.length - 1)];
  }

  static double previous(double value) {
    final i = steps.indexOf(normalize(value));
    return steps[(i - 1).clamp(0, steps.length - 1)];
  }
}
```

Create `lib/features/playback/presentation/widgets/lyrics/lyrics_scale.dart`:

```dart
/// Sizing rules for the lyrics text on desktop.
class LyricsScale {
  /// Same limits the renderer's pinch gesture uses.
  static const double min = 0.6;
  static const double max = 2.5;
  static const double step = 0.1;

  /// Rows saved before the setting existed read back as NaN: 100%.
  static double normalize(double value) {
    if (!value.isFinite || value <= 0) return 1.0;
    return value.clamp(min, max);
  }

  /// One step larger ([direction] > 0) or smaller, rounded to a tenth so
  /// repeated steps don't drift.
  static double stepBy(double value, int direction) {
    final stepped = normalize(value) + (direction > 0 ? step : -step);
    return ((stepped * 10).round() / 10).clamp(min, max);
  }

  /// Grows the text with the lyrics pane: 1.0 up to 760px, 1.6 from 1216px.
  static double auto(double paneWidth) {
    if (paneWidth.isNaN) return 1.0;
    return (paneWidth / 760).clamp(1.0, 1.6);
  }
}
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `flutter test test/desktop_sizing_helpers_test.dart`
Expected: all tests PASS.

- [ ] **Step 6: Format and commit**

```bash
dart format lib/core/utils/ui_utils.dart lib/core/utils/responsive.dart lib/core/utils/ui_scale_steps.dart lib/features/playback/presentation/widgets/lyrics/lyrics_scale.dart test/desktop_sizing_helpers_test.dart
git add lib/core/utils/ui_utils.dart lib/core/utils/responsive.dart lib/core/utils/ui_scale_steps.dart lib/features/playback/presentation/widgets/lyrics/lyrics_scale.dart
git commit -m "Add desktop sizing helpers: window class, UI scale steps, lyrics scale"
```

---

### Task 2: Settings fields

**Files:**
- Modify: `lib/features/library/domain/models/models.dart` (class `AppSettings`, ends near line 338)
- Modify: `lib/features/settings/presentation/providers/settings_notifier.dart` (`_clone` near line 247-381; updaters)
- Regenerated: `lib/features/library/domain/models/models.g.dart`

**Interfaces:**
- Consumes: `UiScaleSteps.normalize`, `LyricsScale.normalize` (Task 1)
- Produces:
  - `AppSettings.desktopUiScale` (`double`, default 1.0), `AppSettings.lyricsFontScale` (`double`, default 1.0)
  - `SettingsNotifier.updateDesktopUiScale(double) -> Future<void>`, `SettingsNotifier.updateLyricsFontScale(double) -> Future<void>`

No unit test: the notifier needs a live Isar instance. The normalisation it relies on is covered in Task 1; the fields are exercised by the manual run in Task 9.

- [ ] **Step 1: Add the fields**

In `models.dart`, inside `AppSettings`, directly after the `lyricsGestureTutorialSeen` field:

```dart

  /// Desktop only: whole-UI scale, one of UiScaleSteps.steps. Rows saved
  /// before this field existed come back as NaN - read it through
  /// UiScaleSteps.normalize.
  double desktopUiScale = 1.0;

  /// Desktop only: lyrics text scale chosen by the user, multiplied by the
  /// automatic window-based scale. NaN on old rows - read it through
  /// LyricsScale.normalize.
  double lyricsFontScale = 1.0;
```

- [ ] **Step 2: Copy them in `_clone`**

In `settings_notifier.dart`, the last line of `_clone` is
`..lyricsGestureTutorialSeen = s.lyricsGestureTutorialSeen;`. Replace it with:

```dart
      ..lyricsGestureTutorialSeen = s.lyricsGestureTutorialSeen
      ..desktopUiScale = s.desktopUiScale
      ..lyricsFontScale = s.lyricsFontScale;
```

- [ ] **Step 3: Add the updaters**

In `settings_notifier.dart`, directly after `updateLyricsAlignment`:

```dart

  Future<void> updateDesktopUiScale(double value) =>
      _update((s) => s..desktopUiScale = UiScaleSteps.normalize(value));

  Future<void> updateLyricsFontScale(double value) =>
      _update((s) => s..lyricsFontScale = LyricsScale.normalize(value));
```

Add the imports at the top of the file:

```dart
import 'package:looper_player/core/utils/ui_scale_steps.dart';
import 'package:looper_player/features/playback/presentation/widgets/lyrics/lyrics_scale.dart';
```

- [ ] **Step 4: Regenerate the Isar schema**

Run: `dart run build_runner build --delete-conflicting-outputs`
Expected: completes with "Succeeded"; `git diff --stat` shows `models.g.dart` changed, with `desktopUiScale` and `lyricsFontScale` present in it.

- [ ] **Step 5: Analyze**

Run: `flutter analyze lib/features/library/domain/models lib/features/settings/presentation/providers`
Expected: "No issues found!", or only issues in lines this task did not add (none may mention the two new fields or updaters).

- [ ] **Step 6: Format and commit**

```bash
dart format lib/features/library/domain/models/models.dart lib/features/settings/presentation/providers/settings_notifier.dart
git add lib/features/library/domain/models/models.dart lib/features/library/domain/models/models.g.dart lib/features/settings/presentation/providers/settings_notifier.dart
git commit -m "Add desktopUiScale and lyricsFontScale settings"
```

If `build_runner` rewrote other `.g.dart` files with real changes, leave them unstaged and report it; do not commit files this task did not intend to change.

---

### Task 3: Window geometry

**Files:**
- Create: `lib/core/services/window/window_geometry.dart`
- Create: `lib/core/services/window/window_geometry_listener.dart`
- Modify: `lib/main.dart:78-99` (the `desktopInit` block) and `lib/main.dart:178` (`buildHome`)
- Test: `test/window_geometry_test.dart`

**Interfaces:**
- Consumes: `UiUtils.isDesktop`, `UiScaleSteps.normalize` (Task 1); `AppSettings.desktopUiScale` (Task 2)
- Produces:
  - `WindowGeometry({required double width, required double height, double? x, double? y, bool maximized})`, `.size`, `.toJson()`, `WindowGeometry.fromJson(Object?) -> WindowGeometry?`, `WindowGeometry.sanitize(WindowGeometry? raw, Size? desktop) -> WindowGeometry?`, `WindowGeometry.minimumSize`, `.defaultSize`, `WindowGeometry.desktopSize() -> Size?`
  - `WindowGeometryStore.load() -> Future<WindowGeometry?>`, `.save(WindowGeometry) -> Future<void>`
  - `WindowGeometryListener({required Widget child})`

- [ ] **Step 1: Write the failing tests**

`test/window_geometry_test.dart`:

```dart
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:looper_player/core/services/window/window_geometry.dart';

void main() {
  const desktop = Size(1920, 1080);

  group('WindowGeometry JSON', () {
    test('round trips', () {
      const g = WindowGeometry(
        width: 1300,
        height: 800,
        x: 40,
        y: 60,
        maximized: true,
      );
      final back = WindowGeometry.fromJson(g.toJson())!;
      expect(back.width, 1300);
      expect(back.height, 800);
      expect(back.x, 40);
      expect(back.y, 60);
      expect(back.maximized, isTrue);
    });

    test('position is optional', () {
      final g = WindowGeometry.fromJson({'width': 900, 'height': 600})!;
      expect(g.x, isNull);
      expect(g.y, isNull);
      expect(g.maximized, isFalse);
    });

    test('corrupt input yields null instead of throwing', () {
      expect(WindowGeometry.fromJson(null), isNull);
      expect(WindowGeometry.fromJson('nope'), isNull);
      expect(WindowGeometry.fromJson(<String, dynamic>{}), isNull);
      expect(WindowGeometry.fromJson({'width': 'wide', 'height': 600}), isNull);
      expect(WindowGeometry.fromJson({'width': 900}), isNull);
      expect(
        WindowGeometry.fromJson({'width': 900, 'height': 600, 'x': 'left'}),
        isNotNull,
      );
    });
  });

  group('WindowGeometry.sanitize', () {
    test('null and non-finite sizes fall back to the default', () {
      expect(WindowGeometry.sanitize(null, desktop), isNull);
      expect(
        WindowGeometry.sanitize(
          const WindowGeometry(width: double.nan, height: 600),
          desktop,
        ),
        isNull,
      );
      expect(
        WindowGeometry.sanitize(
          const WindowGeometry(width: 900, height: double.infinity),
          desktop,
        ),
        isNull,
      );
    });

    test('too-small sizes are raised to the minimum', () {
      final g = WindowGeometry.sanitize(
        const WindowGeometry(width: 200, height: 100),
        desktop,
      )!;
      expect(g.width, 720);
      expect(g.height, 480);
    });

    test('a size from a bigger monitor is cut down to the desktop', () {
      final g = WindowGeometry.sanitize(
        const WindowGeometry(width: 3840, height: 2100),
        desktop,
      )!;
      expect(g.width, 1920);
      expect(g.height, 1080);
    });

    test('an off-screen position is dropped, the size kept', () {
      final g = WindowGeometry.sanitize(
        const WindowGeometry(width: 1000, height: 700, x: 2600, y: 100),
        desktop,
      )!;
      expect(g.x, isNull);
      expect(g.y, isNull);
      expect(g.width, 1000);
    });

    test('a negative or barely-visible position is dropped', () {
      for (final pos in const [Offset(-50, 10), Offset(10, -5), Offset(1850, 10), Offset(10, 1000)]) {
        final g = WindowGeometry.sanitize(
          WindowGeometry(width: 1000, height: 700, x: pos.dx, y: pos.dy),
          desktop,
        )!;
        expect(g.x, isNull, reason: '$pos');
      }
    });

    test('an on-screen position survives', () {
      final g = WindowGeometry.sanitize(
        const WindowGeometry(width: 1000, height: 700, x: 300, y: 120),
        desktop,
      )!;
      expect(g.x, 300);
      expect(g.y, 120);
    });

    test('with no display information nothing is clamped to the desktop', () {
      final g = WindowGeometry.sanitize(
        const WindowGeometry(width: 3000, height: 1500, x: 2500, y: 10),
        null,
      )!;
      expect(g.width, 3000);
      expect(g.x, 2500);
    });

    test('maximized is carried through', () {
      final g = WindowGeometry.sanitize(
        const WindowGeometry(width: 1000, height: 700, maximized: true),
        desktop,
      )!;
      expect(g.maximized, isTrue);
    });
  });
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `flutter test test/window_geometry_test.dart`
Expected: FAIL to compile, "Target of URI doesn't exist: window_geometry.dart".

- [ ] **Step 3: Implement the model and store**

Create `lib/core/services/window/window_geometry.dart`:

```dart
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';

import 'package:looper_player/core/utils/logger_helper.dart';
import 'package:path_provider/path_provider.dart';

/// Where the desktop window was, and how big, when the app last ran.
class WindowGeometry {
  static const Size minimumSize = Size(720, 480);
  static const Size defaultSize = Size(1150, 700);

  /// A restored window must show at least this much of itself on the
  /// desktop, or its position is discarded.
  static const double _visibleMargin = 100;

  final double width;
  final double height;
  final double? x;
  final double? y;
  final bool maximized;

  const WindowGeometry({
    required this.width,
    required this.height,
    this.x,
    this.y,
    this.maximized = false,
  });

  Size get size => Size(width, height);

  WindowGeometry copyWith({bool? maximized}) => WindowGeometry(
    width: width,
    height: height,
    x: x,
    y: y,
    maximized: maximized ?? this.maximized,
  );

  Map<String, dynamic> toJson() => {
    'width': width,
    'height': height,
    if (x != null) 'x': x,
    if (y != null) 'y': y,
    'maximized': maximized,
  };

  /// Null for anything that isn't a usable geometry map.
  static WindowGeometry? fromJson(Object? json) {
    if (json is! Map) return null;
    final width = json['width'];
    final height = json['height'];
    if (width is! num || height is! num) return null;
    final x = json['x'];
    final y = json['y'];
    final hasPosition = x is num && y is num;
    return WindowGeometry(
      width: width.toDouble(),
      height: height.toDouble(),
      x: hasPosition ? x.toDouble() : null,
      y: hasPosition ? y.toDouble() : null,
      maximized: json['maximized'] == true,
    );
  }

  /// A geometry that is safe to open with, or null to use the default.
  /// [desktop] is the combined size of the connected displays (null when
  /// unknown): the size is cut down to it, and a position that would leave
  /// the window off-screen - saved on a monitor since unplugged - is dropped.
  static WindowGeometry? sanitize(WindowGeometry? raw, Size? desktop) {
    if (raw == null || !raw.width.isFinite || !raw.height.isFinite) {
      return null;
    }
    var width = math.max(raw.width, minimumSize.width);
    var height = math.max(raw.height, minimumSize.height);
    if (desktop != null) {
      width = math.min(width, math.max(desktop.width, minimumSize.width));
      height = math.min(height, math.max(desktop.height, minimumSize.height));
    }

    double? x = raw.x;
    double? y = raw.y;
    final positionUsable =
        x != null &&
        y != null &&
        x.isFinite &&
        y.isFinite &&
        x >= 0 &&
        y >= 0 &&
        (desktop == null ||
            (x <= desktop.width - _visibleMargin &&
                y <= desktop.height - _visibleMargin));
    if (!positionUsable) {
      x = null;
      y = null;
    }

    return WindowGeometry(
      width: width,
      height: height,
      x: x,
      y: y,
      maximized: raw.maximized,
    );
  }

  /// The connected displays laid side by side, in logical pixels. Null when
  /// the platform reports none.
  static Size? desktopSize() {
    final displays = PlatformDispatcher.instance.displays;
    if (displays.isEmpty) return null;
    double width = 0;
    double height = 0;
    for (final display in displays) {
      final ratio = display.devicePixelRatio <= 0
          ? 1.0
          : display.devicePixelRatio;
      width += display.size.width / ratio;
      height = math.max(height, display.size.height / ratio);
    }
    if (width <= 0 || height <= 0) return null;
    return Size(width, height);
  }
}

/// Keeps [WindowGeometry] in a small file rather than the database, so it
/// can be read before the window is shown.
class WindowGeometryStore {
  static Future<File> _file() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/window_state.json');
  }

  static Future<WindowGeometry?> load() async {
    try {
      final file = await _file();
      if (!await file.exists()) return null;
      return WindowGeometry.fromJson(jsonDecode(await file.readAsString()));
    } catch (e, s) {
      LoggerHelper.write('Failed to read window geometry', e, s);
      return null;
    }
  }

  static Future<void> save(WindowGeometry geometry) async {
    try {
      final file = await _file();
      await file.writeAsString(jsonEncode(geometry.toJson()), flush: true);
    } catch (e, s) {
      LoggerHelper.write('Failed to save window geometry', e, s);
    }
  }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `flutter test test/window_geometry_test.dart`
Expected: all tests PASS.

- [ ] **Step 5: Implement the listener**

Create `lib/core/services/window/window_geometry_listener.dart`:

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:looper_player/core/services/window/window_geometry.dart';
import 'package:looper_player/core/utils/logger_helper.dart';
import 'package:looper_player/core/utils/ui_scale_steps.dart';
import 'package:looper_player/features/settings/presentation/providers/settings_notifier.dart';
import 'package:window_manager/window_manager.dart';

/// Desktop only. Remembers the window's size, position and maximized state
/// as the user changes them, and keeps the minimum window size in step with
/// the UI scale so the logical layout never drops below
/// [WindowGeometry.minimumSize].
class WindowGeometryListener extends ConsumerStatefulWidget {
  final Widget child;

  const WindowGeometryListener({super.key, required this.child});

  @override
  ConsumerState<WindowGeometryListener> createState() =>
      _WindowGeometryListenerState();
}

class _WindowGeometryListenerState
    extends ConsumerState<WindowGeometryListener>
    with WindowListener {
  static const Duration _debounce = Duration(milliseconds: 400);

  Timer? _timer;
  WindowGeometry? _last;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    WindowGeometryStore.load().then((stored) => _last ??= stored);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _applyMinimumSize(ref.read(settingsProvider).desktopUiScale);
      }
    });
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    _timer?.cancel();
    super.dispose();
  }

  @override
  void onWindowResize() => _schedule();

  @override
  void onWindowMove() => _schedule();

  @override
  void onWindowMaximize() => _schedule();

  @override
  void onWindowUnmaximize() => _schedule();

  void _schedule() {
    _timer?.cancel();
    _timer = Timer(_debounce, _save);
  }

  Future<void> _save() async {
    try {
      if (await windowManager.isMaximized()) {
        // Keep the normal size and position, so un-maximizing after the
        // next launch returns to them.
        final base =
            _last ??
            WindowGeometry(
              width: WindowGeometry.defaultSize.width,
              height: WindowGeometry.defaultSize.height,
            );
        _last = base.copyWith(maximized: true);
      } else {
        final bounds = await windowManager.getBounds();
        _last = WindowGeometry(
          width: bounds.width,
          height: bounds.height,
          x: bounds.left,
          y: bounds.top,
        );
      }
      await WindowGeometryStore.save(_last!);
    } catch (e, s) {
      LoggerHelper.write('Failed to record window geometry', e, s);
    }
  }

  Future<void> _applyMinimumSize(double uiScale) async {
    final scale = UiScaleSteps.normalize(uiScale);
    final factor = scale > 1.0 ? scale : 1.0;
    try {
      await windowManager.setMinimumSize(WindowGeometry.minimumSize * factor);
    } catch (e, s) {
      LoggerHelper.write('Failed to set minimum window size', e, s);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<double>(
      settingsProvider.select((s) => s.desktopUiScale),
      (_, next) => _applyMinimumSize(next),
    );
    return widget.child;
  }
}
```

- [ ] **Step 6: Wire it into `main.dart`**

Add imports:

```dart
import 'core/services/window/window_geometry.dart';
import 'core/services/window/window_geometry_listener.dart';
import 'core/utils/ui_utils.dart';
```

Replace the body of the `try` in `desktopInit` (currently `await windowManager.ensureInitialized();` through the end of the `waitUntilReadyToShow` call) with:

```dart
        await windowManager.ensureInitialized();
        final geometry = WindowGeometry.sanitize(
          await WindowGeometryStore.load(),
          WindowGeometry.desktopSize(),
        );
        final position = (geometry?.x != null && geometry?.y != null)
            ? Offset(geometry!.x!, geometry.y!)
            : null;
        WindowOptions windowOptions = WindowOptions(
          size: geometry?.size ?? WindowGeometry.defaultSize,
          minimumSize: WindowGeometry.minimumSize,
          center: position == null,
          skipTaskbar: false,
          titleBarStyle: TitleBarStyle.hidden,
          title: 'Looper Player',
          backgroundColor: const Color(0xFF121214),
        );
        await windowManager.waitUntilReadyToShow(windowOptions, () async {
          if (position != null) {
            await windowManager.setPosition(position);
          }
          await windowManager.show();
          if (geometry?.maximized ?? false) {
            await windowManager.maximize();
          }
          await windowManager.focus();
        });
```

In `buildHome`, replace

```dart
        data: (_) => const KeyboardHandler(child: HomeScreen()),
```

with

```dart
        data: (_) => KeyboardHandler(
          child: UiUtils.isDesktop
              ? const WindowGeometryListener(child: HomeScreen())
              : const HomeScreen(),
        ),
```

On Android this builds the same `KeyboardHandler(child: HomeScreen())` as before.

- [ ] **Step 7: Verify on Linux**

Run: `flutter analyze lib/main.dart lib/core/services/window`
Expected: no new issues.

Run: `flutter run -d linux`, then:
1. Drag the window smaller: it stops at 720x480.
2. Resize to roughly 1400x900, move it, quit, relaunch: same size (and same position on X11).
3. Maximize, quit, relaunch: opens maximized; un-maximize returns to the 1400x900 size.
4. `echo garbage > ~/.local/share/*/window_state.json` (use the actual app support path printed by `find ~/.local/share -name window_state.json`), relaunch: opens at the centred default 1150x700, no crash.

- [ ] **Step 8: Format and commit**

```bash
dart format lib/core/services/window lib/main.dart test/window_geometry_test.dart
git add lib/core/services/window/window_geometry.dart lib/core/services/window/window_geometry_listener.dart lib/main.dart
git commit -m "Remember desktop window geometry and enforce a minimum size"
```

---

### Task 4: UI scale and keyboard shortcuts

**Files:**
- Create: `lib/ui/widgets/common/desktop_ui_scale.dart`
- Modify: `lib/main.dart:245` (`builder:`)
- Modify: `lib/ui/widgets/common/keyboard_handler.dart`
- Test: `test/desktop_ui_scale_test.dart`

**Interfaces:**
- Consumes: `UiUtils.isDesktop`, `UiScaleSteps`, `LyricsScale` (Task 1); `desktopUiScale`, `lyricsFontScale`, `updateDesktopUiScale`, `updateLyricsFontScale` (Task 2)
- Produces: `DesktopUiScale({required double scale, required Widget child})`

`flutter test` runs on Linux, so `UiUtils.isDesktop` is true in tests.

- [ ] **Step 1: Write the failing tests**

`test/desktop_ui_scale_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:looper_player/ui/widgets/common/desktop_ui_scale.dart';

class _Counter extends StatefulWidget {
  const _Counter();

  @override
  State<_Counter> createState() => _CounterState();
}

class _CounterState extends State<_Counter> {
  int taps = 0;

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: () => setState(() => taps++),
    child: Text('taps $taps', textDirection: TextDirection.ltr),
  );
}

void main() {
  Future<Size> pumpAt(WidgetTester tester, double scale) async {
    late Size seen;
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(size: Size(800, 600)),
        child: Center(
          child: SizedBox(
            width: 800,
            height: 600,
            child: DesktopUiScale(
              scale: scale,
              child: Builder(
                builder: (context) {
                  seen = MediaQuery.sizeOf(context);
                  return const SizedBox.expand();
                },
              ),
            ),
          ),
        ),
      ),
    );
    return seen;
  }

  testWidgets('at 100% the child sees the real window size', (tester) async {
    expect(await pumpAt(tester, 1.0), const Size(800, 600));
  });

  testWidgets('the child sees the window size divided by the scale', (
    tester,
  ) async {
    expect(await pumpAt(tester, 1.25), const Size(640, 480));
    final small = await pumpAt(tester, 0.8);
    expect(small.width, closeTo(1000, 0.01));
    expect(small.height, closeTo(750, 0.01));
  });

  testWidgets('an unusable scale behaves like 100%', (tester) async {
    expect(await pumpAt(tester, double.nan), const Size(800, 600));
    expect(await pumpAt(tester, 0), const Size(800, 600));
  });

  testWidgets('the scaled child fills the window and takes taps', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MediaQuery(
        data: MediaQueryData(size: Size(800, 600)),
        child: DesktopUiScale(scale: 1.5, child: _Counter()),
      ),
    );
    await tester.tapAt(const Offset(780, 580));
    await tester.pump();
    expect(find.text('taps 1'), findsOneWidget);
  });

  testWidgets('changing the scale keeps the state below it', (tester) async {
    Widget app(double scale) => MediaQuery(
      data: const MediaQueryData(size: Size(800, 600)),
      child: DesktopUiScale(scale: scale, child: const _Counter()),
    );

    await tester.pumpWidget(app(1.0));
    await tester.tapAt(const Offset(400, 300));
    await tester.pump();
    expect(find.text('taps 1'), findsOneWidget);

    await tester.pumpWidget(app(1.25));
    expect(find.text('taps 1'), findsOneWidget);

    await tester.pumpWidget(app(1.0));
    expect(find.text('taps 1'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `flutter test test/desktop_ui_scale_test.dart`
Expected: FAIL to compile, "Target of URI doesn't exist: desktop_ui_scale.dart".

- [ ] **Step 3: Implement the widget**

Create `lib/ui/widgets/common/desktop_ui_scale.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:looper_player/core/utils/ui_scale_steps.dart';
import 'package:looper_player/core/utils/ui_utils.dart';

/// Desktop only: draws the whole app [scale] times larger. The app is laid
/// out in a box of the window size divided by [scale] and painted scaled up
/// to fill the window, and MediaQuery reports that smaller size, so
/// breakpoints react to the room the layout really has.
///
/// The widget tree has the same shape at every scale (including 100%), so
/// changing the scale never remounts the app below it. On other platforms
/// it returns [child] untouched.
class DesktopUiScale extends StatelessWidget {
  final double scale;
  final Widget child;

  const DesktopUiScale({super.key, required this.scale, required this.child});

  @override
  Widget build(BuildContext context) {
    if (!UiUtils.isDesktop) return child;

    final s = UiScaleSteps.normalize(scale);
    final mq = MediaQuery.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final logical = constraints.biggest / s;
        return FittedBox(
          fit: BoxFit.fill,
          child: SizedBox(
            width: logical.width,
            height: logical.height,
            child: MediaQuery(
              data: mq.copyWith(
                size: logical,
                devicePixelRatio: mq.devicePixelRatio * s,
                padding: mq.padding / s,
                viewPadding: mq.viewPadding / s,
                viewInsets: mq.viewInsets / s,
              ),
              child: child,
            ),
          ),
        );
      },
    );
  }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `flutter test test/desktop_ui_scale_test.dart`
Expected: all tests PASS.

- [ ] **Step 5: Apply it in `main.dart`**

Add the import:

```dart
import 'package:looper_player/ui/widgets/common/desktop_ui_scale.dart';
```

Replace

```dart
        builder: (context, child) => child!,
```

with

```dart
        builder: (context, child) => DesktopUiScale(
          scale: settings?.desktopUiScale ?? 1.0,
          child: child!,
        ),
```

(`settings` is the nullable local already defined at the top of `MyApp.build`.)

- [ ] **Step 6: Add the shortcuts**

In `lib/ui/widgets/common/keyboard_handler.dart`, add imports:

```dart
import 'package:looper_player/core/utils/ui_scale_steps.dart';
import 'package:looper_player/core/utils/ui_utils.dart';
import 'package:looper_player/features/playback/presentation/widgets/lyrics/lyrics_scale.dart';
import 'package:looper_player/features/settings/presentation/providers/settings_notifier.dart';
```

In `_handleKeyEvent`, directly after the line `final key = event.logicalKey;` and before the `// Global Playback Shortcuts` comment, insert:

```dart
    // Desktop sizing: Ctrl +/-/0 for the whole UI, plain +/- for the lyrics
    // text while the lyrics view is open.
    if (UiUtils.isDesktop) {
      final settings = ref.read(settingsProvider);
      final settingsNotifier = ref.read(settingsProvider.notifier);
      final bool larger =
          key == LogicalKeyboardKey.equal ||
          key == LogicalKeyboardKey.add ||
          key == LogicalKeyboardKey.numpadAdd;
      final bool smaller =
          key == LogicalKeyboardKey.minus ||
          key == LogicalKeyboardKey.numpadSubtract;

      if (HardwareKeyboard.instance.isControlPressed) {
        if (larger) {
          settingsNotifier.updateDesktopUiScale(
            UiScaleSteps.next(settings.desktopUiScale),
          );
          return true;
        }
        if (smaller) {
          settingsNotifier.updateDesktopUiScale(
            UiScaleSteps.previous(settings.desktopUiScale),
          );
          return true;
        }
        if (key == LogicalKeyboardKey.digit0 ||
            key == LogicalKeyboardKey.numpad0) {
          settingsNotifier.updateDesktopUiScale(1.0);
          return true;
        }
      } else if ((larger || smaller) &&
          ref.read(appNavigationProvider).activeItem == NavItem.lyrics) {
        settingsNotifier.updateLyricsFontScale(
          LyricsScale.stepBy(settings.lyricsFontScale, larger ? 1 : -1),
        );
        return true;
      }
    }
```

The whole block is skipped on Android, so its key handling is unchanged.

- [ ] **Step 7: Verify on Linux**

Run: `flutter analyze lib/main.dart lib/ui/widgets/common`
Expected: no new issues.

Run: `flutter run -d linux`, then:
1. Ctrl `+` four times: the UI grows through 110%, 125%, 150% and stays there. Text stays sharp.
2. While at 150%, the current page, scroll position and playing song are unchanged, and the window cannot be dragged below 1080x720.
3. Ctrl `-` back down to 80%; Ctrl `0` returns to 100%.
4. Click buttons near the right and bottom edges at 125%: they respond where they are drawn.
5. Open a dialog or bottom sheet at 125%: it is scaled like the rest.
6. Type `-` and `=` in the search box: characters are typed, the UI does not scale.

- [ ] **Step 8: Format and commit**

```bash
dart format lib/ui/widgets/common/desktop_ui_scale.dart lib/ui/widgets/common/keyboard_handler.dart lib/main.dart test/desktop_ui_scale_test.dart
git add lib/ui/widgets/common/desktop_ui_scale.dart lib/ui/widgets/common/keyboard_handler.dart lib/main.dart
git commit -m "Add desktop UI scale with Ctrl +/-/0 and lyrics size keys"
```

---

### Task 5: Optional sizing parameters on the lyric renderer

**Files:**
- Modify: `lib/features/playback/presentation/widgets/lyrics/advanced_lyric_renderer.dart`

**Interfaces:**
- Produces: `AdvancedLyricRenderer` accepts four new optional named parameters:
  - `double? fontScale`: when set, replaces the internal pinch-driven scale
  - `ValueChanged<double>? onFontScaleChanged`: when set, a pinch reports the new scale here instead of changing internal state
  - `double? horizontalPadding`: replaces the `24.s` left/right list padding
  - `double? bottomPadding`: replaces the platform bottom list padding

No automated test: this widget needs the playback provider, which builds a real mpv player. Correctness rule for review: **with all four parameters null, every code path must be the same as before this task.**

- [ ] **Step 1: Add the parameters**

Replace the widget's fields and constructor:

```dart
class AdvancedLyricRenderer extends ConsumerStatefulWidget {
  final List<LyricLine> lines;
  final LyricsSyncMode mode;
  final Function(Duration) onSeek;

  /// Text scale supplied by the parent. Null keeps the renderer's own
  /// pinch-driven scale.
  final double? fontScale;

  /// With [fontScale] set, a pinch reports the scale it asks for here.
  final ValueChanged<double>? onFontScaleChanged;

  /// Left/right and bottom padding of the list. Null keeps the defaults.
  final double? horizontalPadding;
  final double? bottomPadding;

  const AdvancedLyricRenderer({
    super.key,
    required this.lines,
    required this.mode,
    required this.onSeek,
    this.fontScale,
    this.onFontScaleChanged,
    this.horizontalPadding,
    this.bottomPadding,
  });
```

- [ ] **Step 2: Use the supplied scale**

In `_AdvancedLyricRendererState`, add below the `_baseScale` field:

```dart
  double get _effectiveFontScale => widget.fontScale ?? _fontScale;
```

In `_onPointerDown`, change `_baseScale = _fontScale;` to `_baseScale = _effectiveFontScale;`.

In `_onPointerMove`, replace

```dart
    if (newFontScale != _fontScale) {
      setState(() => _fontScale = newFontScale);
    }
```

with

```dart
    if (newFontScale != _effectiveFontScale) {
      final onChanged = widget.onFontScaleChanged;
      if (widget.fontScale != null && onChanged != null) {
        onChanged(newFontScale);
      } else {
        setState(() => _fontScale = newFontScale);
      }
    }
```

In `_onPointerUpOrCancel`, change the final `_baseScale = _fontScale;` to `_baseScale = _effectiveFontScale;`.

In `build`, change `fontScale: _fontScale,` (passed to `AdvancedLyricLine`) to `fontScale: _effectiveFontScale,`.

- [ ] **Step 3: Use the supplied padding**

In `build`, replace the `ListView.builder` padding with:

```dart
          padding: EdgeInsets.only(
            top: 60.s,
            bottom:
                widget.bottomPadding ??
                ((Platform.isAndroid || Platform.isIOS) ? 120.s : 400.s),
            left: widget.horizontalPadding ?? 24.s,
            right: widget.horizontalPadding ?? 24.s,
          ),
```

- [ ] **Step 4: Check for other uses of `_fontScale`**

Run: `grep -n "_fontScale" lib/features/playback/presentation/widgets/lyrics/advanced_lyric_renderer.dart`
Expected: only the field declaration, the `_effectiveFontScale` getter, and the `setState` in `_onPointerMove`. Any other read must become `_effectiveFontScale`.

- [ ] **Step 5: Analyze and run the existing lyrics tests**

Run: `flutter analyze lib/features/playback/presentation/widgets/lyrics && flutter test test/lyrics_sync_style_test.dart test/lyrics_skeleton_and_haptics_test.dart`
Expected: no new issues; tests PASS.

- [ ] **Step 6: Format and commit**

```bash
dart format lib/features/playback/presentation/widgets/lyrics/advanced_lyric_renderer.dart
git add lib/features/playback/presentation/widgets/lyrics/advanced_lyric_renderer.dart
git commit -m "Let the lyric renderer take its scale and padding from the parent"
```

---

### Task 6: Localised strings

**Files:**
- Modify: `lib/l10n/app_en.arb`, `app_ar.arb`, `app_de.arb`, `app_es.arb`, `app_fr.arb`, `app_hi.arb`, `app_it.arb`, `app_ja.arb`, `app_ko.arb`, `app_nl.arb`, `app_pt.arb`, `app_ru.arb`, `app_tr.arb`, `app_zh.arb`
- Regenerated: `lib/l10n/app_localizations*.dart`
- Test: `test/desktop_l10n_test.dart`

**Interfaces:**
- Produces: `AppLocalizations` getters `uiScale`, `lyricsSize`, `lyricsSizeDesc`, `lyricsSizeSmaller`, `lyricsSizeLarger`, `lyricsOptions`.

- [ ] **Step 1: Write the failing test**

`test/desktop_l10n_test.dart`:

```dart
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:looper_player/l10n/app_localizations.dart';

void main() {
  test('every locale has the desktop sizing strings', () {
    for (final locale in AppLocalizations.supportedLocales) {
      final l10n = lookupAppLocalizations(locale);
      for (final text in [
        l10n.uiScale,
        l10n.lyricsSize,
        l10n.lyricsSizeDesc,
        l10n.lyricsSizeSmaller,
        l10n.lyricsSizeLarger,
        l10n.lyricsOptions,
      ]) {
        expect(text, isNotEmpty, reason: '$locale');
      }
    }
  });

  test('the strings are translated, not copied from English', () {
    expect(lookupAppLocalizations(const Locale('de')).lyricsSize, 'Songtext-Größe');
    expect(lookupAppLocalizations(const Locale('hi')).uiScale, 'इंटरफ़ेस का आकार');
    expect(lookupAppLocalizations(const Locale('ja')).lyricsOptions, '歌詞オプション');
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/desktop_l10n_test.dart`
Expected: FAIL to compile, "The getter 'uiScale' isn't defined".

- [ ] **Step 3: Add the keys to all 14 ARB files**

Save this as `add_desktop_l10n.py` in a temp directory and run it from the repo root with `python3 <path>/add_desktop_l10n.py`. It appends the six keys before the closing brace of each ARB file, keeping the file's existing formatting, and refuses to run twice.

```python
import json
import pathlib

KEYS = ["uiScale", "lyricsSize", "lyricsSizeDesc", "lyricsSizeSmaller", "lyricsSizeLarger", "lyricsOptions"]

T = {
    "en": ["UI scale", "Lyrics size", "Text size on the lyrics screen", "Smaller lyrics", "Larger lyrics", "Lyrics options"],
    "ar": ["حجم الواجهة", "حجم كلمات الأغنية", "حجم النص في شاشة الكلمات", "كلمات أصغر", "كلمات أكبر", "خيارات الكلمات"],
    "de": ["Oberflächengröße", "Songtext-Größe", "Textgröße in der Songtext-Ansicht", "Songtext kleiner", "Songtext größer", "Songtext-Optionen"],
    "es": ["Escala de la interfaz", "Tamaño de la letra", "Tamaño del texto en la pantalla de letras", "Letra más pequeña", "Letra más grande", "Opciones de letra"],
    "fr": ["Échelle de l'interface", "Taille des paroles", "Taille du texte sur l'écran des paroles", "Paroles plus petites", "Paroles plus grandes", "Options des paroles"],
    "hi": ["इंटरफ़ेस का आकार", "लिरिक्स का आकार", "लिरिक्स स्क्रीन पर टेक्स्ट का आकार", "लिरिक्स छोटे करें", "लिरिक्स बड़े करें", "लिरिक्स विकल्प"],
    "it": ["Scala dell'interfaccia", "Dimensione del testo", "Dimensione del testo nella schermata dei testi", "Testo più piccolo", "Testo più grande", "Opzioni del testo"],
    "ja": ["UIの拡大率", "歌詞のサイズ", "歌詞画面の文字サイズ", "歌詞を小さく", "歌詞を大きく", "歌詞オプション"],
    "ko": ["UI 배율", "가사 크기", "가사 화면의 글자 크기", "가사 작게", "가사 크게", "가사 옵션"],
    "nl": ["Interfaceschaal", "Grootte songtekst", "Tekstgrootte op het songtekstscherm", "Kleinere songtekst", "Grotere songtekst", "Songtekstopties"],
    "pt": ["Escala da interface", "Tamanho da letra", "Tamanho do texto na tela de letras", "Letra menor", "Letra maior", "Opções de letra"],
    "ru": ["Масштаб интерфейса", "Размер текста песни", "Размер текста на экране текста песни", "Текст меньше", "Текст больше", "Параметры текста песни"],
    "tr": ["Arayüz ölçeği", "Şarkı sözü boyutu", "Şarkı sözleri ekranındaki metin boyutu", "Sözleri küçült", "Sözleri büyüt", "Şarkı sözü seçenekleri"],
    "zh": ["界面缩放", "歌词大小", "歌词页面的文字大小", "缩小歌词", "放大歌词", "歌词选项"],
}

for lang, values in T.items():
    path = pathlib.Path(f"lib/l10n/app_{lang}.arb")
    text = path.read_text(encoding="utf-8")
    existing = json.loads(text)
    if any(k in existing for k in KEYS):
        raise SystemExit(f"{path}: keys already present, nothing changed")
    body = text.rstrip()
    assert body.endswith("}"), path
    body = body[:-1].rstrip()
    lines = ",\n".join(
        f"  {json.dumps(k)}: {json.dumps(v, ensure_ascii=False)}"
        for k, v in zip(KEYS, values)
    )
    path.write_text(f"{body},\n{lines}\n}}\n", encoding="utf-8")
    json.loads(path.read_text(encoding="utf-8"))
    print("updated", path)
```

Expected output: fourteen `updated lib/l10n/app_xx.arb` lines.

- [ ] **Step 4: Regenerate the localisation classes**

Run: `flutter gen-l10n`
Expected: no errors and no "untranslated message" warnings for the six keys.

- [ ] **Step 5: Run the tests to verify they pass**

Run: `flutter test test/desktop_l10n_test.dart test/l10n_smoke_test.dart`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/l10n
git commit -m "Add desktop sizing strings in all languages"
```

---

### Task 7: Desktop lyrics toolbar, menu dialog and layout

**Files:**
- Create: `lib/features/playback/presentation/widgets/lyrics/desktop_lyrics_toolbar.dart`
- Modify: `lib/ui/android/player/lyrics/widgets/android_lyrics_menu_sheet.dart` (additive only)
- Modify: `lib/features/playback/presentation/screens/lyrics_view.dart` (`build`, lines 77-120)
- Test: `test/desktop_lyrics_toolbar_test.dart`

**Interfaces:**
- Consumes: `UiUtils.isDesktop`, `LyricsScale` (Task 1); `lyricsFontScale`, `updateLyricsFontScale` (Task 2); renderer parameters `fontScale`, `onFontScaleChanged`, `horizontalPadding`, `bottomPadding` (Task 5); l10n getters (Task 6)
- Produces:
  - `DesktopLyricsToolbar({required double scale, required VoidCallback onSmaller, required VoidCallback onLarger, required VoidCallback onReset, Widget? syncSelector, VoidCallback? onMenu})`
  - `showLyricsMenuDialog(BuildContext context, WidgetRef ref, Song song)`

- [ ] **Step 1: Write the failing toolbar tests**

`test/desktop_lyrics_toolbar_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:looper_player/features/playback/presentation/widgets/lyrics/desktop_lyrics_toolbar.dart';
import 'package:looper_player/l10n/app_localizations.dart';

void main() {
  Widget host({
    required double width,
    required double scale,
    VoidCallback? onSmaller,
    VoidCallback? onLarger,
    VoidCallback? onReset,
    VoidCallback? onMenu,
    Widget? syncSelector,
  }) => MaterialApp(
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: Align(
        alignment: Alignment.topRight,
        child: SizedBox(
          width: width,
          child: Align(
            alignment: Alignment.topRight,
            child: DesktopLyricsToolbar(
              scale: scale,
              onSmaller: onSmaller ?? () {},
              onLarger: onLarger ?? () {},
              onReset: onReset ?? () {},
              onMenu: onMenu,
              syncSelector: syncSelector,
            ),
          ),
        ),
      ),
    ),
  );

  testWidgets('shows the size as a percentage and reports each button', (
    tester,
  ) async {
    final calls = <String>[];
    await tester.pumpWidget(
      host(
        width: 900,
        scale: 1.2,
        onSmaller: () => calls.add('smaller'),
        onLarger: () => calls.add('larger'),
        onReset: () => calls.add('reset'),
        onMenu: () => calls.add('menu'),
      ),
    );

    expect(find.text('120%'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('lyrics-size-smaller')));
    await tester.tap(find.byKey(const ValueKey('lyrics-size-larger')));
    await tester.tap(find.text('120%'));
    await tester.tap(find.byKey(const ValueKey('lyrics-menu')));
    expect(calls, ['smaller', 'larger', 'reset', 'menu']);
  });

  testWidgets('the size buttons stop at the limits', (tester) async {
    var calls = 0;
    await tester.pumpWidget(
      host(width: 900, scale: 0.6, onSmaller: () => calls++),
    );
    await tester.tap(find.byKey(const ValueKey('lyrics-size-smaller')));
    expect(calls, 0);

    await tester.pumpWidget(
      host(width: 900, scale: 2.5, onLarger: () => calls++),
    );
    await tester.tap(find.byKey(const ValueKey('lyrics-size-larger')));
    expect(calls, 0);
  });

  testWidgets('the menu button is disabled without a song', (tester) async {
    await tester.pumpWidget(host(width: 900, scale: 1.0));
    final button = tester.widget<IconButton>(
      find.byKey(const ValueKey('lyrics-menu')),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('fits a 360px pane without overflowing', (tester) async {
    await tester.pumpWidget(host(width: 360, scale: 2.5, onMenu: () {}));
    expect(tester.takeException(), isNull);
    expect(find.text('250%'), findsOneWidget);
  });

  testWidgets('shows the sync selector when one is given', (tester) async {
    await tester.pumpWidget(
      host(
        width: 900,
        scale: 1.0,
        syncSelector: const Text('SYNC', key: ValueKey('sync')),
      ),
    );
    expect(find.byKey(const ValueKey('sync')), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run them to verify they fail**

Run: `flutter test test/desktop_lyrics_toolbar_test.dart`
Expected: FAIL to compile, "Target of URI doesn't exist: desktop_lyrics_toolbar.dart".

- [ ] **Step 3: Implement the toolbar**

Create `lib/features/playback/presentation/widgets/lyrics/desktop_lyrics_toolbar.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:looper_player/core/theme/app_fonts.dart';
import 'package:looper_player/core/utils/l10n.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'lyrics_scale.dart';

/// The lyrics controls a mouse user needs: text size, sync style, and the
/// lyrics menu. Pure presentation - the lyrics view owns the state.
class DesktopLyricsToolbar extends StatelessWidget {
  /// The user's lyrics scale (1.0 = 100%), before the automatic scale.
  final double scale;
  final VoidCallback onSmaller;
  final VoidCallback onLarger;
  final VoidCallback onReset;

  /// Line/word/char selector; left out when the pane is too narrow.
  final Widget? syncSelector;

  /// Null disables the menu button (nothing is playing).
  final VoidCallback? onMenu;

  const DesktopLyricsToolbar({
    super.key,
    required this.scale,
    required this.onSmaller,
    required this.onLarger,
    required this.onReset,
    this.syncSelector,
    this.onMenu,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final canShrink = scale > LyricsScale.min + 0.001;
    final canGrow = scale < LyricsScale.max - 0.001;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (syncSelector != null) ...[syncSelector!, const SizedBox(width: 12)],
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(32),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _SizeButton(
                key: const ValueKey('lyrics-size-smaller'),
                label: 'A−',
                fontSize: 12,
                tooltip: l10n.lyricsSizeSmaller,
                onTap: canShrink ? onSmaller : null,
              ),
              Tooltip(
                message: l10n.reset,
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: onReset,
                  child: Container(
                    width: 52,
                    height: 32,
                    alignment: Alignment.center,
                    child: Text(
                      '${(scale * 100).round()}%',
                      style: AppFonts.jostStyle(
                        color: Colors.white70,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              ),
              _SizeButton(
                key: const ValueKey('lyrics-size-larger'),
                label: 'A+',
                fontSize: 15,
                tooltip: l10n.lyricsSizeLarger,
                onTap: canGrow ? onLarger : null,
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        IconButton(
          key: const ValueKey('lyrics-menu'),
          tooltip: l10n.lyricsOptions,
          onPressed: onMenu,
          icon: const Icon(LucideIcons.moreVertical, size: 18),
          color: Colors.white70,
          disabledColor: Colors.white24,
        ),
      ],
    );
  }
}

class _SizeButton extends StatelessWidget {
  final String label;
  final double fontSize;
  final String tooltip;
  final VoidCallback? onTap;

  const _SizeButton({
    super.key,
    required this.label,
    required this.fontSize,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          width: 36,
          height: 32,
          alignment: Alignment.center,
          child: Text(
            label,
            style: AppFonts.jostStyle(
              color: onTap == null ? Colors.white24 : Colors.white,
              fontSize: fontSize,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Run the toolbar tests to verify they pass**

Run: `flutter test test/desktop_lyrics_toolbar_test.dart`
Expected: all tests PASS. If `AppFonts.jostStyle` tries to load a font over the network in tests, look at how `test/lyrics_tips_sheet_test.dart` sets up fonts and copy that setup.

- [ ] **Step 5: Add the menu dialog (additive edit under `lib/ui/android`)**

In `lib/ui/android/player/lyrics/widgets/android_lyrics_menu_sheet.dart`:

Directly after the `showLyricsMenuBottomSheet` function, add:

```dart

/// The same menu for mouse-and-window platforms: a centred dialog instead
/// of a bottom sheet, without the touch-only entries.
void showLyricsMenuDialog(BuildContext context, WidgetRef ref, Song song) {
  showDialog<void>(
    context: context,
    useRootNavigator: true,
    builder: (context) => Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(30),
          child: _LyricsMenuSheetContent(song: song, desktop: true),
        ),
      ),
    ),
  );
}
```

Change the content widget's fields and constructor to:

```dart
class _LyricsMenuSheetContent extends ConsumerWidget {
  final Song song;

  /// Shown in a dialog on desktop: no drag handle, no touch-gesture tips.
  final bool desktop;

  const _LyricsMenuSheetContent({required this.song, this.desktop = false});
```

In its `build`, add one argument to the `AppBottomSheetContainer(` call (it currently starts with `padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),`):

```dart
      showDragHandle: !desktop,
```

Find the `_MenuActionTile(` whose `title` is `l10n.gestureTips` (near line 424) and put `if (!desktop)` directly in front of it:

```dart
                  if (!desktop)
                    _MenuActionTile(
                      icon: LucideIcons.hand,
                      title: l10n.gestureTips,
```

(leave the tile's own arguments as they are). Nothing else in this file changes. `showLyricsMenuBottomSheet` still builds `_LyricsMenuSheetContent(song: song)`, so `desktop` is false and the Android sheet is identical.

- [ ] **Step 6: Add the desktop branch to `LyricsView`**

In `lib/features/playback/presentation/screens/lyrics_view.dart`, add imports:

```dart
import 'dart:math' as math;

import 'package:looper_player/core/utils/ui_utils.dart';
import 'package:looper_player/ui/android/player/lyrics/widgets/android_lyrics_menu_sheet.dart';

import '../widgets/lyrics/desktop_lyrics_toolbar.dart';
import '../widgets/lyrics/lyrics_scale.dart';
```

Replace the whole `build` method of `_LyricsViewState` with the following. `_buildLyrics` is the old body unchanged apart from taking the sync mode and the four optional renderer arguments.

```dart
  @override
  Widget build(BuildContext context) {
    final syncMode = _syncMode;
    if (!UiUtils.isDesktop) return _buildLyrics(context, syncMode);

    // Read everything here, not inside the LayoutBuilder: its builder runs
    // during layout, where providers must not be watched.
    final userScale = LyricsScale.normalize(
      ref.watch(settingsProvider.select((s) => s.lyricsFontScale)),
    );
    final song = ref.watch(playbackProvider.select((s) => s.currentSong));
    final settingsNotifier = ref.read(settingsProvider.notifier);
    final syncSelector = _buildModeSelector(true);

    return LayoutBuilder(
      builder: (context, constraints) {
        final paneWidth = constraints.maxWidth;
        final autoScale = LyricsScale.auto(paneWidth);
        return Stack(
          children: [
            Positioned.fill(
              child: _buildLyrics(
                context,
                syncMode,
                fontScale: userScale * autoScale,
                onFontScaleChanged: (scale) =>
                    settingsNotifier.updateLyricsFontScale(scale / autoScale),
                // Cap the lyrics column at 900px, centred, while the whole
                // pane keeps scrolling.
                horizontalPadding: math.max(24.0, (paneWidth - 900) / 2),
                bottomPadding: constraints.maxHeight * 0.45,
              ),
            ),
            Positioned(
              top: 8,
              right: 16,
              child: DesktopLyricsToolbar(
                scale: userScale,
                onSmaller: () => settingsNotifier.updateLyricsFontScale(
                  LyricsScale.stepBy(userScale, -1),
                ),
                onLarger: () => settingsNotifier.updateLyricsFontScale(
                  LyricsScale.stepBy(userScale, 1),
                ),
                onReset: () => settingsNotifier.updateLyricsFontScale(1.0),
                syncSelector: paneWidth >= 520 ? syncSelector : null,
                onMenu: song == null
                    ? null
                    : () => showLyricsMenuDialog(context, ref, song),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildLyrics(
    BuildContext context,
    LyricsSyncMode syncMode, {
    double? fontScale,
    ValueChanged<double>? onFontScaleChanged,
    double? horizontalPadding,
    double? bottomPadding,
  }) {
    final l10n = AppLocalizations.of(context)!;
    final lyricsState = ref.watch(lyricsProvider);
    final primaryColor = Theme.of(context).colorScheme.primary;

    return Stack(
      children: [
        Column(
          children: [
            Expanded(
              // Cross-fades between the three states. The keys are fixed per
              // state, so new lines for the same state (an offset change,
              // a word-sync upgrade) update the renderer in place instead
              // of fading it out and back in.
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 280),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                layoutBuilder: (current, previous) => Stack(
                  fit: StackFit.expand,
                  children: [...previous, ?current],
                ),
                child: lyricsState.isLoading
                    ? const LyricsSkeleton(key: ValueKey('loading'))
                    : lyricsState.rawLrc == null
                    ? KeyedSubtree(
                        key: const ValueKey('empty'),
                        child: _buildNoLyricsState(context, l10n, primaryColor),
                      )
                    : AdvancedLyricRenderer(
                        key: const ValueKey('lyrics'),
                        lines: lyricsState.parsedLines,
                        mode: syncMode,
                        onSeek: (pos) =>
                            ref.read(playbackProvider.notifier).seek(pos),
                        fontScale: fontScale,
                        onFontScaleChanged: onFontScaleChanged,
                        horizontalPadding: horizontalPadding,
                        bottomPadding: bottomPadding,
                      ),
              ),
            ),
          ],
        ),
      ],
    );
  }
```

Two things to check while editing:

1. `lyricsProvider` is watched inside `_buildLyrics`, which on desktop is called from the `LayoutBuilder` builder. Move that watch out: add `final lyricsState = ref.watch(lyricsProvider);` at the very top of `build` (before the `isDesktop` check), give `_buildLyrics` a required `LyricsState lyricsState` positional parameter after `syncMode`, pass it at both call sites, and delete the `ref.watch(lyricsProvider)` line inside `_buildLyrics`. Use the state class name that `lyricsProvider` actually exposes (see `lyrics_notifier.dart`).
2. `_buildNoLyricsState` also watches `playbackProvider`. On desktop it now runs inside the `LayoutBuilder` too. Give it a `Song? song` parameter instead: watch `currentSong` at the top of `build` (the desktop branch already does; hoist that line above the `isDesktop` check), thread it through `_buildLyrics`, and remove the `ref.watch` inside `_buildNoLyricsState`.

After both changes the Android path still watches exactly the same three things (`lyricsSyncStyle`, `lyricsProvider`, `currentSong`) and builds the same tree. `currentSong` used to be watched only in the empty state; watching it always adds a rebuild of `LyricsView` on song change, at which point `lyricsProvider` changes anyway.

- [ ] **Step 7: Analyze and run the tests**

Run: `flutter analyze lib/features/playback lib/ui/android/player/lyrics && flutter test test/desktop_lyrics_toolbar_test.dart test/lyrics_tips_sheet_test.dart test/lyrics_sync_style_test.dart`
Expected: no new issues (in particular, no "unused element `_buildModeSelector`" any more); tests PASS.

- [ ] **Step 8: Verify on Linux**

Run: `flutter run -d linux`, play a song with lyrics, open Lyrics (`L`):
1. Toolbar sits top-right: sync selector, `A−  100%  A+`, more button.
2. `A+` three times: text grows, label reads 130%. Click the label: back to 100%.
3. `=` and `-` keys do the same. Restart the app: the size is remembered.
4. Widen the window from 1150 to 1920: the text grows smoothly; the lyrics stay in a centred column instead of spanning the window. Wheel-scrolling works with the pointer anywhere in the pane.
5. Scroll to the end: the last line can reach the middle of the pane without a huge blank area below it.
6. Switch LINE / WORD / CHAR: the highlight style changes.
7. More button: a centred dialog with provider, timing, find word-synced, export/import. No "Gesture tips" entry, no drag handle. Escape and clicking outside close it.
8. Narrow the window to 720 wide with the sidebar open: the sync selector disappears, nothing overflows.
9. Song with no lyrics: the empty state shows, the toolbar is still usable.

- [ ] **Step 9: Format and commit**

```bash
dart format lib/features/playback/presentation/widgets/lyrics/desktop_lyrics_toolbar.dart lib/features/playback/presentation/screens/lyrics_view.dart lib/ui/android/player/lyrics/widgets/android_lyrics_menu_sheet.dart test/desktop_lyrics_toolbar_test.dart
git add lib/features/playback/presentation/widgets/lyrics/desktop_lyrics_toolbar.dart lib/features/playback/presentation/screens/lyrics_view.dart lib/ui/android/player/lyrics/widgets/android_lyrics_menu_sheet.dart
git commit -m "Add desktop lyrics toolbar, menu dialog and window-aware lyrics layout"
```

---

### Task 8: Desktop settings rows and size-class adoption

**Files:**
- Modify: `lib/ui/desktop/settings/settings_view.dart` (Appearance section; the `lyricsAlignment` dropdown ends near line 214)
- Modify: `lib/ui/home_screen/home_screen.dart:107` and `:215`

**Interfaces:**
- Consumes: `UiUtils.isDesktop`, `UiScaleSteps`, `LyricsScale`, `Responsive.windowClass`, `WindowClass` (Task 1); settings fields and updaters (Task 2); l10n getters (Task 6)

No new automated test: both files are thin wiring over tested helpers. Verified by the manual run below.

- [ ] **Step 1: Add the settings rows**

In `lib/ui/desktop/settings/settings_view.dart`, add imports if missing:

```dart
import 'package:looper_player/core/utils/ui_scale_steps.dart';
import 'package:looper_player/core/utils/ui_utils.dart';
import 'package:looper_player/features/playback/presentation/widgets/lyrics/lyrics_scale.dart';
```

Directly after the `_PremiumDropdownRow<String>` for `l10n.lyricsAlignment` (after its closing `),`), insert:

```dart
                    if (UiUtils.isDesktop) ...[
                      _PremiumSliderRow(
                        icon: LucideIcons.languages,
                        title: l10n.lyricsSize,
                        subtitle: l10n.lyricsSizeDesc,
                        value:
                            LyricsScale.normalize(settings.lyricsFontScale) *
                            100,
                        min: LyricsScale.min * 100,
                        max: LyricsScale.max * 100,
                        divisions: 19,
                        suffix: '%',
                        onChanged: (val) => ref
                            .read(settingsProvider.notifier)
                            .updateLyricsFontScale(
                              (val / 10).round() / 10,
                            ),
                        isLast: false,
                      ),
                      _PremiumDropdownRow<double>(
                        icon: LucideIcons.sliders,
                        title: l10n.uiScale,
                        value: UiScaleSteps.normalize(settings.desktopUiScale),
                        items: [
                          for (final step in UiScaleSteps.steps)
                            DropdownMenuItem(
                              value: step,
                              child: Text('${(step * 100).round()}%'),
                            ),
                        ],
                        onChanged: (step) {
                          if (step != null) {
                            ref
                                .read(settingsProvider.notifier)
                                .updateDesktopUiScale(step);
                          }
                        },
                        isLast: false,
                      ),
                    ],
```

`divisions: 19` gives one stop per 10% between 60% and 250%. If `LucideIcons.languages` or `LucideIcons.sliders` does not resolve in this file, use any Lucide icon the file already imports successfully (for example `LucideIcons.alignCenter`).

- [ ] **Step 2: Adopt the size class in the shell**

In `lib/ui/home_screen/home_screen.dart`, add the import if missing:

```dart
import 'package:looper_player/core/utils/responsive.dart';
```

Replace line 107

```dart
    final bool isNarrow = MediaQuery.of(context).size.width < 800;
```

with

```dart
    final bool isNarrow =
        Responsive.windowClass(MediaQuery.of(context).size.width) ==
        WindowClass.compact;
```

Replace (near line 215)

```dart
                            final bool isNarrowLayout =
                                constraints.maxWidth < 800;
```

with

```dart
                            final bool isNarrowLayout =
                                Responsive.windowClass(constraints.maxWidth) ==
                                WindowClass.compact;
```

Both lines sit after the `if (Platform.isAndroid) return const AndroidMainScreen();` early return, so Android never runs them.

- [ ] **Step 3: Verify on Linux**

Run: `flutter analyze lib/ui/desktop lib/ui/home_screen`
Expected: no new issues.

Run: `flutter run -d linux`, open Settings:
1. Appearance shows "Lyrics size" (slider, 60% to 250%) and "UI scale" (dropdown 80% to 150%).
2. Picking 125% in the dropdown scales the app at once; the dropdown shows 125% afterwards; Ctrl `0` sets it back to 100% and the dropdown follows.
3. Moving the lyrics slider to 150%, then opening Lyrics: toolbar reads 150%.
4. Dragging the window across 800 px wide: the sidebar turns into a drawer below 800, exactly as before. At 125% UI scale this happens at a 1000 px window, because the layout then has 800 logical px.

- [ ] **Step 4: Format and commit**

```bash
dart format lib/ui/desktop/settings/settings_view.dart lib/ui/home_screen/home_screen.dart
git add lib/ui/desktop/settings/settings_view.dart lib/ui/home_screen/home_screen.dart
git commit -m "Expose UI scale and lyrics size in desktop settings; use window classes in the shell"
```

---

### Task 9: Whole-change verification and Android audit

**Files:** none modified unless a check fails.

- [ ] **Step 1: Full static analysis**

Run: `flutter analyze`
Expected: no issues that were not present on `main`. Run `git diff main --stat` to list the files this branch touched and confirm every reported issue is in a file not on that list.

- [ ] **Step 2: Full test suite**

Run: `flutter test`
Expected: all tests PASS, including the five new files: `desktop_sizing_helpers_test.dart`, `window_geometry_test.dart`, `desktop_ui_scale_test.dart`, `desktop_l10n_test.dart`, `desktop_lyrics_toolbar_test.dart`.

- [ ] **Step 3: Android audit of the diff**

Run: `git diff main -- lib ':!lib/l10n' ':!*.g.dart'`

Go through every hunk and classify it. Each must be one of:

- a new file that only desktop code imports or that is pure logic (`ui_scale_steps.dart`, `lyrics_scale.dart`, `window_geometry*.dart`, `desktop_ui_scale.dart`, `desktop_lyrics_toolbar.dart`);
- inside `if (UiUtils.isDesktop)` / after `if (!UiUtils.isDesktop) return ...` / after `if (Platform.isAndroid) return ...`;
- an optional parameter whose Android callers do not pass it (`AdvancedLyricRenderer`, `_LyricsMenuSheetContent.desktop`);
- a new `AppSettings` field, its `_clone` line, or its updater.

Then confirm specifically:

```bash
git diff main --stat -- lib/ui/android
```

Expected: exactly one file, `android_lyrics_menu_sheet.dart`.

```bash
git diff main -- lib/core/utils/ui_utils.dart lib/ui/widgets/common/player_scale.dart
```

Expected: `ui_utils.dart` shows only the added `isDesktop` getter; `player_scale.dart` shows nothing.

```bash
grep -rn "AdvancedLyricRenderer(\|showLyricsMenuBottomSheet(\|_LyricsMenuSheetContent(" lib
```

Expected: the only call passing `fontScale`/`horizontalPadding`/`bottomPadding` is in `_buildLyrics`, and only the `showLyricsMenuDialog` path passes `desktop: true`.

Any hunk that does not fit one of the four classes is a defect: fix it before continuing.

- [ ] **Step 4: Android build check**

Run (JDK 21 is required; the system JDK 25 fails with a bare "25.0.4.1" error):

```bash
JAVA_HOME=~/.jdks/corretto-21.0.8 flutter build apk --debug --flavor github
```

Expected: build succeeds. If a device or emulator is attached (`adb devices`), install it and check the lyrics screen: pinch still resizes, the size is not remembered after reopening, the menu sheet still has its drag handle and "Gesture tips". If no device is attached, say so in the report rather than claiming it was checked.

- [ ] **Step 5: Linux end-to-end pass**

Run: `flutter run -d linux` and walk through the manual checks of Tasks 3, 4, 7 and 8 once more in a single session at window sizes 720x480, 1150x700, 1920x1080 and maximized.

- [ ] **Step 6: Report**

Summarise: tests run and their result, analyzer result, the outcome of the Android audit (with the three command outputs), whether the Android device check was possible, and anything observed on Linux that differs from the expected behaviour. Do not merge or push; the branch is left for review.
