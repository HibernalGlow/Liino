# Linux desktop: window foundation and lyrics sizing

Date: 2026-10-01
Status: design approved in chat, awaiting spec review

## Goal

The Linux build runs on large, resizable windows but is sized like a fixed
1150x700 panel. This spec covers the first two of four desktop sub-projects:

1. **Window foundation**: minimum size, remembered geometry, window size
   classes, a manual UI scale.
2. **Lyrics on desktop**: a persisted and automatically growing lyrics size,
   a toolbar with size and sync controls, and the lyrics menu that today
   exists only on Android.

Later specs (not covered here): 3. sheets, dialogs, equalizer and song info
on desktop; 4. feature parity (new settings screen, expanded player, Analyze).

## Hard constraint: Android does not change

Nothing in the Android build may change, in behaviour or in pixels.

- Every new behaviour is gated on a single `UiUtils.isDesktop` check
  (Linux/Windows/macOS) or lives in files only the desktop shell builds
  (`lib/ui/home_screen`, `lib/ui/desktop`).
- Shared widgets gain only optional parameters whose defaults reproduce
  today's behaviour exactly. `LyricsView` is embedded by
  `AndroidLyricsScreen`, so its non-desktop branch must return today's tree.
- `UiUtils.scale` (0.85 on Android) and `player_scale.dart` are not touched.
- New `AppSettings` fields are only read on desktop. Adding them changes the
  Isar schema on both platforms, which is additive and needs no migration.
- No file under `lib/ui/android` is restructured or moved. One file there
  (`android_lyrics_menu_sheet.dart`) gets an additive change (section 4.3).
- Pinch-to-resize lyrics on Android stays unsaved, as today.

## 1. Window

New file `lib/core/services/window/window_geometry.dart`.

- `WindowGeometry { double width, height; double? x, y; bool maximized }`
  with `toJson` / `fromJson`.
- `WindowGeometry.sanitize(raw, desktop)`: pure function. `desktop` is the
  combined size of the connected displays. Returns null (use the default)
  when width or height is missing or non-finite. Clamps the size to between
  the minimum and `desktop`. Drops the position when the window would not
  be at least 100 px inside `desktop`, so a layout saved on a monitor that
  is no longer connected cannot open off-screen.
- `WindowGeometryStore`: reads and writes `window_state.json` in the
  application support directory (`path_provider`, already a dependency).
  A plain file rather than Isar so it can be read before the window shows.
  Read and write failures are logged through `LoggerHelper` and ignored.

Constants: minimum 720x480, default 1150x700.

`lib/main.dart` desktop init:

- Load stored geometry before `waitUntilReadyToShow`.
- `WindowOptions.size` is the stored size or the default; `center` is true
  only when there is no stored position; `minimumSize` is always set.
- After show: restore position if stored, then maximize if it was maximized.

New `WindowGeometryListener` widget (desktop only, wraps the home screen):
a `WindowListener` that on resize, move, maximize and unmaximize saves the
geometry, debounced by 400 ms. While maximized it saves only the flag, so
un-maximizing later returns to the previous normal size. It also keeps the
window's minimum size at 720x480 multiplied by the UI scale (when above
100%), so the logical layout never gets smaller than 720x480.

Wayland: compositors do not let clients read or set position. Position
restore silently does nothing there; size and maximized state still work.

## 2. Size classes

`lib/core/utils/responsive.dart` gains:

```dart
enum WindowClass { compact, medium, expanded }

static const double mediumWidth = 800;
static const double expandedWidth = 1400;
static WindowClass windowClass(double width);
```

`home_screen.dart` replaces its two literal `< 800` checks with
`Responsive.windowClass(width) == WindowClass.compact`. Behaviour is
identical; this is the hook later sub-projects build on. Existing
`isLandscape` / `isShort` are unchanged.

## 3. UI scale (manual, desktop only)

- New setting `desktopUiScale` (double, default 1.0), allowed steps
  0.8, 0.9, 1.0, 1.1, 1.25, 1.5. Values read from rows saved before the
  field existed come back as NaN and are treated as 1.0.
- New widget `DesktopUiScale` in `lib/ui/widgets/common/desktop_ui_scale.dart`,
  placed in `MaterialApp.builder` so routes, dialogs and sheets are inside it.
  On non-desktop platforms, or at scale 1.0, it returns its child unchanged.
  Otherwise it lays the child out at `size / scale` inside a `FittedBox`
  that paints it scaled up, and overrides `MediaQuery` size to match so
  breakpoints see the scaled-down logical size.
- Shortcuts in `KeyboardHandler`: Ctrl `+`/`=` next step, Ctrl `-` previous
  step, Ctrl `0` reset. Only handled on desktop.
- Not automatic: a whole-UI scale that follows window width would jump at
  thresholds while the user drags the window edge.

## 4. Lyrics

### 4.1 Size

- New setting `lyricsFontScale` (double, default 1.0, range 0.6 to 2.5, the
  renderer's existing clamp; NaN treated as 1.0).
- Pure helpers in `lib/features/playback/presentation/widgets/lyrics/lyrics_scale.dart`:
  `LyricsScale.auto(paneWidth)` = `(paneWidth / 760).clamp(1.0, 1.6)`,
  plus `normalize` and `stepBy`.
- `AdvancedLyricRenderer` gains optional `fontScale`, `onFontScaleChanged`,
  `horizontalPadding` and `bottomPadding`. When they are null (the Android
  path) the renderer behaves exactly as today, including its internal
  pinch-driven scale.
- Desktop `LyricsView` passes `lyricsFontScale * LyricsScale.auto(paneWidth)`.

### 4.2 Toolbar

New `lib/features/playback/presentation/widgets/lyrics/desktop_lyrics_toolbar.dart`,
shown top-right of the lyrics pane on desktop only:

- `A-` / `A+`: step `lyricsFontScale` by 0.1. The current percentage sits
  between them; clicking it resets to 100%.
- The line / word / char sync selector (`_buildModeSelector` already exists
  in `LyricsView` but is not shown anywhere today). Hidden when the pane is
  narrower than 520 px; the same choice is available in the menu.
- `more` button opening the lyrics menu (4.3). Disabled when no song plays.
- All buttons have tooltips.

Keyboard: `-` and `=` change the lyrics size while the lyrics view is the
active item (without Ctrl, which belongs to UI scale).

### 4.3 Menu

`android_lyrics_menu_sheet.dart` gains a second public entry point,
`showLyricsMenuDialog(context, ref, song)`, which presents the same
`_LyricsMenuSheetContent` in a centred dialog (max width 480). The content
widget gets an optional `desktop` flag, default false; when true it hides
the drag handle and the "Gesture tips" entry. The menu already contains
sync style, timing offset, provider, find word-synced, auto fallback and
LRC export/import. `showLyricsMenuBottomSheet` and everything Android calls
are unchanged.

### 4.4 Layout

On desktop `LyricsView` measures its pane and passes the renderer:

- horizontal padding of `max(24, (paneWidth - 900) / 2)`, so the lyrics
  column is at most 900 logical px and centred while the whole pane still
  scrolls; `lyricsAlignment` still controls text alignment inside it;
- bottom padding of 45% of the pane height instead of the fixed `400.s`.

## 5. Settings and text

- `lib/ui/desktop/settings/settings_view.dart` (the settings page Linux
  uses): "UI scale" dropdown and "Lyrics size" slider in Appearance, both
  shown only on desktop.
- New ARB keys in all 14 languages, per the repo's l10n convention:
  `uiScale`, `lyricsSize`, `lyricsSizeDesc`,
  `lyricsSizeSmaller`, `lyricsSizeLarger`, `lyricsOptions`. The existing
  `reset` key is reused.

## 6. Testing

Unit tests (pure functions):

- `Responsive.windowClass` at and around 800 and 1400.
- `LyricsScale.auto`, `normalize` and `stepBy`, including NaN.
- `UiScaleSteps` normalize, next and previous, including NaN.
- `WindowGeometry.sanitize` and the JSON round trip, including corrupt
  input and an off-screen position.

Widget tests: `DesktopUiScale` reports `MediaQuery.size` divided by the
scale and is a pass-through at 1.0; the lyrics toolbar does not overflow at
a 360 px pane width.

`test/` is gitignored in this repo, so tests run locally and are not
committed.

Manual, on the Linux build: windows at 720x480, 1150x700, 1920x1080 and
maximized; restart to confirm geometry restore; each UI scale step; lyrics
at each size class with line and word sync.

Android guard: `flutter analyze` clean, and a review of the final diff
confirming every changed line that Android executes is either an optional
parameter left at its default or behind `UiUtils.isDesktop`.

## Out of scope

Sheets and dialogs on desktop, equalizer and song info layouts, the new
settings screen on Linux, the expanded player, Analyze in the sidebar,
a two-pane immersive lyrics view, Ctrl+scroll lyrics zoom.
