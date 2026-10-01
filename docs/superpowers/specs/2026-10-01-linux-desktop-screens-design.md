# Linux desktop: screens, library data and settings

Date: 2026-10-01
Status: choices confirmed in chat, awaiting spec review

## Goal

Fix and polish the Linux screens the user listed: home order and alignment,
missing song photos, the Add Folder button, a two-column songs list, the
artists screen, Looper Analyze and Genres in the sidebar, a collapsible
settings page with the Android options and About, and a landscape
equalizer.

Builds on `2026-10-01-linux-window-foundation-and-lyrics-design.md`
(uses its `UiUtils.isDesktop` and `Responsive.windowClass`).

## Hard constraint: Android does not change

Same rule as the foundation spec. Every change is behind `UiUtils.isDesktop`
/ `Platform.isLinux`, lives in desktop-only files (`lib/ui/home_screen`,
`lib/ui/desktop`, `library_grids.dart`), or is an optional parameter Android
never passes. Shared dependencies in `pubspec.yaml` are not changed.

## 1. Song photos, titles and artists (root cause)

`metadata_god` fails to initialise on Linux on every launch ("codegen
version 2.11.1 should be the same as runtime version 2.13.0", logged from
`main.dart:113`). The scanner therefore gets no embedded tags and no cover:
songs show the file name, "Unknown Artist" and no photo. Android masks this
with native fallbacks that Linux lacks.

Fix, Linux only: `LinuxTagReader` in
`lib/features/library/data/scanner/linux_tag_reader.dart`.

- `read(path)`: runs `ffprobe -v quiet -print_format json -show_format
  -show_streams`, parses title, artist (falling back to album artist),
  album, genre, track number, year and duration from the container tags and
  the first audio stream's tags (Ogg/Opus keep tags on the stream).
- `readCover(path)`: runs `ffmpeg` to write the first attached picture to
  stdout as JPEG and returns the bytes.
- Both kill the process on timeout and rethrow `TimeoutException`, which the
  scanner already treats as "retry later". A missing binary returns null.
- `LibraryScanner._extractMetadata` uses them only when `Platform.isLinux`
  and `metadata_god` produced nothing.

Packaging: ffmpeg becomes a dependency of the .deb and .rpm.

Existing libraries were indexed without tags, so after the fix the user
runs the existing "Reset & Rescan" once. Not covered: editing tags on Linux
(`edit_album_sheet.dart`) and the tag read in `playFromFile`
(`playback_notifier.dart:990`) still go through `metadata_god`.

## 2. Sidebar and routes: Genres and Looper Analyze

- Sidebar gains "Genres" (shown when the library has at least one genre)
  and "Looper Analyze".
- The Linux shell routes `NavItem.genres` to the existing `GenresGridView`
  and `NavItem.analyze` to the existing `LooperAnalyzeView`. Today both fall
  through to Home, which is why the home page's Genres "View all" appears
  to do nothing.
- The top bar (search, Add Folder) is hidden on Lyrics and Analyze; Analyze
  has its own header and back button.

## 3. Add Folder button

Rules in a pure `DesktopShellRules`:

- shown when the library is empty, on any page;
- otherwise shown on Home, Songs, Albums, Artists and Genres only;
- hidden on Lyrics, Queue, Settings, Analyze, Playlists, Favorites,
  Recently played, Search and collection pages.

It is visible at every window size, including maximized. In the compact
window class it is icon-only with a tooltip. The search bar is capped at
640 px instead of taking half of a wide window.

## 4. Home

Fixed desktop order, each shown only when it has content:

1. Quick picks
2. Recently played (respects `showHomeRecent`)
3. Featured artists
4. Albums
5. Genres (respects `showHomeGenres`)
6. Artists (respects `showHomeArtists`)

The separate "My albums" block (shown for small libraries) is removed; the
Albums section covers it. `homeSectionOrder` is not used on desktop.

Alignment: every section uses one header (title left, "View all" right
where a full page exists), the same title size, the same 28 px gap, and
cards of one width. Quick picks uses a max-extent grid, so it gains columns
as the window widens instead of stopping at four.

## 5. Songs

When the songs list itself is at least 1100 px wide (a maximized window),
it shows two columns. One column otherwise, while searching (rows can grow
with a lyric snippet), and always on Android. Wrong titles and artists are
the tag problem in section 1.

## 6. Artists

Desktop-only `library_grids.dart`: hover feedback on cards (reusable
`HoverCard`, also applied to album cards), centred medium-weight names,
bottom padding so the last row clears the player bar, slightly larger
responsive tiles.

## 7. Settings

One desktop settings page. Each section is a card that expands and
collapses on click; Appearance starts expanded, the rest collapsed, and the
state is kept while the app runs.

Sections: Appearance, Fonts, Lyrics, Now playing, Home, Playback and audio,
Library, Backups and logs, About. New sections are built from the shared
Android tile widgets in `lib/features/settings/presentation/widgets/tiles`,
leaving out options that only make sense on a phone (haptics, stop service,
audio focus, Fluid Player, quality badge, segmented buttons, artwork
visualizer, section reordering). About mirrors the Android About page:
version, update check, maintainers, app info and privacy notes, lyrics
credits, licences.

## 8. Equalizer

On desktop the equalizer opens as a centred dialog that is always wider
than tall: width `min(1100, window - 64)`, height `min(window - 64, width *
0.7)`. At 820 px dialog width and above it has two columns: presets, bands
and pre-amp on the left, the DSP cards on the right. Below that, one column.
`AndroidEqualizerScreen` gets an optional `twoColumn` flag (default false);
its content is split into two lists that Android still renders as one
column in the same order. All four openers use the dialog on desktop.

## Testing

Unit tests for the pure parts: ffprobe JSON parsing, shell rules, home
section order, songs column count, equalizer dialog size. Widget tests for
`HoverCard` and the collapsible section. Manual run on Linux for each item.
Android guard: diff audit and debug APK build, as in the foundation plan.

## Out of scope

Tag editing on Linux, the expanded player, sheets other than the
equalizer, user-reorderable home sections on desktop.
