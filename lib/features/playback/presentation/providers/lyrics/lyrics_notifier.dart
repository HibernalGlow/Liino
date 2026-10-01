import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:looper_player/core/services/storage/db_service.dart';
import 'package:looper_player/features/settings/presentation/providers/settings_notifier.dart';
import '../../../data/lyrics_fetcher.dart';
import '../../../domain/lyric_models.dart';

part 'lyrics_notifier.g.dart';

class LyricsState {
  final String? rawLrc;
  final bool isLoading;
  final int? songId;
  final List<LyricLine> parsedLines;
  final String? source;

  LyricsState({
    this.rawLrc,
    this.isLoading = false,
    this.songId,
    this.parsedLines = const [],
    this.source,
  });

  LyricsState copyWith({
    String? rawLrc,
    bool? isLoading,
    int? songId,
    List<LyricLine>? parsedLines,
    String? source,
  }) {
    return LyricsState(
      rawLrc: rawLrc ?? this.rawLrc,
      isLoading: isLoading ?? this.isLoading,
      songId: songId ?? this.songId,
      parsedLines: parsedLines ?? this.parsedLines,
      source: source ?? this.source,
    );
  }
}

@Riverpod(keepAlive: true)
class Lyrics extends _$Lyrics {
  /// What [_applyLrcToState] last showed, so a lyrics offset change can
  /// re-time it in place.
  Song? _shownSong;
  String? _shownLrc;

  @override
  LyricsState build() {
    ref.listen(settingsProvider.select((s) => s.lyricsOffsetMs), (prev, next) {
      final song = _shownSong;
      if (prev != next && song != null && state.songId == song.id) {
        _applyLrcToState(song, _shownLrc);
      }
    });
    return LyricsState();
  }

  void fetchForSong(Song song, {bool force = false}) {
    _fetchLyrics(song, force: force);
  }

  Future<void> _fetchLyrics(Song song, {bool force = false}) async {
    if (!force && state.songId == song.id && state.rawLrc != null) return;

    state = LyricsState(
      isLoading: true,
      songId: song.id,
      rawLrc: null,
      parsedLines: [],
      source: null,
    );

    final lrc = await LyricsFetcher.fetchLyrics(song);

    if (state.songId == song.id) {
      _applyLrcToState(song, lrc);
    }

    // Lyrics without word timing (embedded tags, sidecar files, LRCLIB...):
    // shown right away (above), then swapped for word-synced ones if
    // lrc.red/LyricsPlus have them. Asked once per song - the answer or a
    // "checked" mark is saved.
    if (lrc != null && LyricsFetcher.canUpgradeToWordSync(lrc)) {
      final upgraded = await LyricsFetcher.upgradeToWordSync(song, lrc);
      if (upgraded != null && state.songId == song.id) {
        _applyLrcToState(song, upgraded);
      }
    }
  }

  /// "Find word-synced lyrics" in the lyrics menu: an explicit, unmarked
  /// lookup on lrc.red then LyricsPlus. Keeps the current lyrics (and
  /// returns false) when neither has word timing for this song.
  Future<bool> findWordSynced(Song song) async {
    state = state.copyWith(isLoading: true);
    final lrc = await LyricsFetcher.findWordSynced(song);
    if (lrc != null) {
      _applyLrcToState(song, lrc);
      return true;
    }
    state = state.copyWith(isLoading: false);
    return false;
  }

  /// Lyrics menu provider pick ('Local' = the song's own files). With
  /// auto-fallback on, the rest of the lookup chain is tried after it.
  /// Returns the source the lyrics came from (e.g. 'lrclib', 'embedded'),
  /// or null when nothing was found - the current lyrics then stay.
  Future<String?> fetchWithProvider(Song song, String provider) async {
    state = state.copyWith(isLoading: true);
    final lrc = await LyricsFetcher.fetchWithProvider(song, provider);
    if (lrc == null) {
      state = state.copyWith(isLoading: false);
      return null;
    }
    _applyLrcToState(song, lrc);
    return state.source;
  }

  Future<void> applyCustomLyrics(Song song, String rawContent) async {
    state = state.copyWith(isLoading: true);
    await LyricsFetcher.store(
      song,
      (song.artist ?? 'Unknown Artist').trim(),
      song.title.trim(),
      '[source:custom_file]\n$rawContent',
    );
    _applyLrcToState(song, '[source:custom_file]\n$rawContent');
  }

  void _applyLrcToState(Song song, String? lrc) {
    // Keep cleanLrc nullable -- null means "no lyrics found" and must reach
    // LyricsState.rawLrc as null too (that's what the lyrics screen checks
    // to show its empty state). Defaulting it to '' here used to make every
    // not-found case (offline, no provider match, disabled internet, etc.)
    // render as an empty AdvancedLyricRenderer instead: a blank screen with
    // no "no lyrics found" message at all.
    String? source;
    String? cleanLrc = lrc;
    if (lrc != null && lrc.startsWith('[source:')) {
      final sourceMatch = RegExp(r'^\[source:(.*)\]').firstMatch(lrc);
      if (sourceMatch != null) {
        source = sourceMatch.group(1);
        cleanLrc = lrc.replaceFirst(RegExp(r'^\[source:.*\]\n?'), '');
      }
    }

    _shownSong = song;
    _shownLrc = lrc;
    final lines = cleanLrc != null
        ? LrcParser.parse(
            cleanLrc,
            Duration(milliseconds: song.duration ?? 0),
            // The setting is positive = earlier; the parser's shift is
            // positive = later.
            shift: Duration(
              milliseconds: -ref.read(settingsProvider).lyricsOffsetMs,
            ),
          )
        : <LyricLine>[];

    // A fresh LyricsState (not copyWith) -- copyWith's null-coalescing
    // pattern can't null out rawLrc once it's set, which would silently
    // resurrect a previous song's lyrics text here.
    state = LyricsState(
      rawLrc: cleanLrc,
      isLoading: false,
      parsedLines: lines,
      source: source,
      songId: song.id,
    );
  }
}

@Riverpod(keepAlive: true)
class LyricsManualScroll extends _$LyricsManualScroll {
  @override
  bool build() => false;

  void set(bool value) => state = value;
}

/// Desktop only: the lyrics page shown alone (no sidebar, top bar or player
/// bar) with the window in full screen.
@Riverpod(keepAlive: true)
class LyricsFullscreen extends _$LyricsFullscreen {
  @override
  bool build() => false;

  void set(bool value) {
    if (state == value) return;
    state = value;
    if (Platform.isLinux) windowManager.setFullScreen(value);
  }
}

/// Whether the currently active lyric line's row is within the lyrics
/// list's visible viewport right now - kept up to date by
/// AdvancedLyricRenderer. Lets the "re-sync" button (see
/// AndroidLyricsScreen) only show once the user has actually scrolled the
/// active line out of view, instead of on every scroll touch regardless of
/// whether the line ever left the screen.
@Riverpod(keepAlive: true)
class LyricsActiveLineVisible extends _$LyricsActiveLineVisible {
  @override
  bool build() => true;

  void set(bool value) => state = value;
}
