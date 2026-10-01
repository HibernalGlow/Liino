import 'dart:io';
import 'package:isar_community/isar.dart';
import 'package:path/path.dart' as p;
import 'package:looper_player/core/services/storage/db_service.dart';
import 'lrc_parser.dart';
import 'lyrics_cache.dart';
import 'metadata_service.dart';
import 'lyrics_service.dart';

/// Finds a song's lyrics and keeps them.
///
/// Once a song has lyrics (or a confirmed "not found"), that answer is saved
/// in song.lyrics and the lyrics cache and used from then on, with no
/// expiry - until the user picks another provider in the lyrics menu or
/// clears the lyrics cache ([clearAll]). The one exception is the one-time
/// word-sync upgrade ([upgradeToWordSync]), whose result is saved the same
/// way.
///
/// A fresh lookup walks one chain, first answer wins:
///   1. `LOCAL` - the song's own files: embedded tags, then a sidecar
///      .lrc/.txt.
///   2. The provider chosen in settings.
///   3. With auto-fallback on, every other provider in [allProviders] order.
class LyricsFetcher {
  static final LyricsService _service = LyricsService();

  /// The song's own files (embedded tags, sidecar .lrc/.txt).
  static const String local = 'LOCAL';

  /// Online fallback order: word-synced sources first (lrc.red, then the
  /// LyricsPlus aggregator), then line-synced LRCLIB, then the plain-text
  /// scrapers.
  static final List<String> allProviders = [
    'LRC.RED',
    'LYRICSPLUS',
    'LRCLIB',
    'GENIUS',
    'MUSIXMATCH',
    'AZLYRICS',
    'LYRICSMINT',
    'LYRICFIND',
  ];

  static const String notFound = '[source:not_found]';

  /// Providers that can return word timing.
  static const Set<String> _wordCapableProviders = {'LRC.RED', 'LYRICSPLUS'};
  static final RegExp _sourceTag = RegExp(r'^\[source:[^\]]*\]');
  static final RegExp _enhancedWordTag = RegExp(r'<\d{1,3}:\d{2}');

  static bool hasWordTiming(String lrc) =>
      lrc.contains('\n[w:') || _enhancedWordTag.hasMatch(lrc);

  /// Appended (as an LRC metadata line every parser ignores) to lyrics that
  /// already had their one word-sync upgrade attempt.
  static const String _wordSyncChecked = '[checked:wordsync]';

  /// Lyrics the user picked explicitly (a provider chosen in the lyrics
  /// menu) - marked so the automatic upgrade never overrides that choice.
  static String pinned(String lrc) =>
      lrc.contains(_wordSyncChecked) ? lrc : '$lrc\n$_wordSyncChecked';

  /// Whether [lrc] - lyrics as returned by [fetchLyrics] - gets its one
  /// background lookup for word-synced lyrics ([upgradeToWordSync]): any
  /// source without word timing (embedded tags, sidecar files, LRCLIB, the
  /// scrapers, a line-timed lrc.red/LyricsPlus answer) that isn't the
  /// user's own .lrc and hasn't been checked yet.
  static bool canUpgradeToWordSync(String lrc) {
    if (lrc.contains(_wordSyncChecked)) return false;
    final source = _sourceTag.firstMatch(lrc)?.group(0)?.toLowerCase();
    if (source == '[source:custom_file]') return false;
    return !hasWordTiming(lrc);
  }

  /// One-time upgrade of [current] (see [canUpgradeToWordSync]): returns
  /// word-synced lyrics from lrc.red/LyricsPlus, saved (song.lyrics and the
  /// cache file) in place of the old ones. Otherwise returns null and saves
  /// [current] marked as checked, so the lookup never repeats - unless the
  /// network was down, when it proved nothing and the next play tries again.
  static Future<String?> upgradeToWordSync(Song song, String current) async {
    final settings = await DbService.isar.appSettings.get(0);
    if (settings != null && !settings.enableInternet) return null;

    final found = await findWordSynced(song);
    if (found == null && await _isOnline()) {
      await store(
        song,
        (song.artist ?? 'Unknown Artist').trim(),
        song.title.trim(),
        pinned(current),
      );
    }
    return found;
  }

  /// Asks lrc.red, then LyricsPlus, for lyrics with word timing and saves
  /// the first hit as this song's lyrics. Returns it (source-tagged), or
  /// null when neither has word-synced lyrics - a line-synced answer
  /// doesn't count, it wouldn't improve on what the song already has.
  static Future<String?> findWordSynced(Song song) async {
    final artist = (song.artist ?? 'Unknown Artist').trim();
    final title = song.title.trim();
    for (final provider in const ['LRC.RED', 'LYRICSPLUS']) {
      final lrc = await _fromProvider(song, provider, needWordTiming: true);
      if (lrc != null && hasWordTiming(lrc)) {
        await store(song, artist, title, lrc);
        return lrc;
      }
    }
    return null;
  }

  /// Whether [provider] already has a saved answer for [song] - picking it
  /// in the lyrics menu then loads instantly, with no download.
  static Future<bool> hasSavedCopy(Song song, String provider) async =>
      await LyricsCache.getProvider(
        (song.artist ?? 'Unknown Artist').trim(),
        song.title.trim(),
        provider.toUpperCase(),
      ) !=
      null;

  /// [provider]'s answer for [song], source-tagged: its saved copy when
  /// there is one (with [needWordTiming], only a word-timed copy counts),
  /// else asked online ([network]) and saved for next time.
  static Future<String?> _fromProvider(
    Song song,
    String provider, {
    bool network = true,
    bool needWordTiming = false,
  }) async {
    final artist = (song.artist ?? 'Unknown Artist').trim();
    final title = song.title.trim();
    final saved = await LyricsCache.getProvider(artist, title, provider);
    if (saved != null && (!needWordTiming || hasWordTiming(saved))) {
      return saved;
    }
    if (!network) return null;
    try {
      final response = await _askOnline(song, provider);
      final raw = response?.syncedLyrics ?? response?.plainLyrics;
      if (raw == null || raw.isEmpty) return null;
      final tagged = '[source:${provider.toLowerCase()}]\n$raw';
      await LyricsCache.saveProvider(artist, title, provider, tagged);
      return tagged;
    } catch (_) {
      return null;
    }
  }

  /// Lyrics the user typed or edited, as stored: tagged like their own .lrc
  /// file, so nothing automatic (upgrade, rescan, cache clear) replaces
  /// them.
  static String userLyrics(String text) =>
      '[source:custom_file]\n${LrcParser.stripSourceTag(text.trim())!.trim()}';

  /// Call before replacing a song's lyrics by hand: files the current
  /// online lyrics (word timing included) under their provider, so the
  /// lyrics menu can bring them back without a download.
  static Future<void> backUpBeforeEdit(Song song) async {
    final current = (await DbService.isar.songs.get(song.id))?.lyrics;
    if (current != null && current.isNotEmpty) {
      await _keepProviderCopy(song, current);
    }
  }

  /// Files the song's current online lyrics under their provider too, for
  /// lyrics saved before per-provider copies existed.
  static Future<void> _keepProviderCopy(Song song, String lrc) async {
    final provider = _sourceTag
        .firstMatch(lrc)
        ?.group(0)
        ?.replaceAll(RegExp(r'^\[source:|\]$'), '')
        .toUpperCase();
    if (provider == null || !allProviders.contains(provider)) return;
    final artist = (song.artist ?? 'Unknown Artist').trim();
    final title = song.title.trim();
    final copy = lrc.replaceAll('\n$_wordSyncChecked', '');
    final existing = await LyricsCache.getProvider(artist, title, provider);
    if (existing == null || (hasWordTiming(copy) && !hasWordTiming(existing))) {
      await LyricsCache.saveProvider(artist, title, provider, copy);
    }
  }

  /// Saves [lrc] as the song's lyrics: cache file and song.lyrics.
  static Future<void> store(
    Song song,
    String artist,
    String title,
    String lrc,
  ) async {
    await LyricsCache.save(artist, title, lrc);
    await _saveToDb(song, lrc);
    await _keepProviderCopy(song, lrc);
  }

  static Future<void> _saveToDb(Song song, String lrc) async {
    await DbService.isar.writeTxn(() async {
      final dbSong = await DbService.isar.songs.get(song.id);
      if (dbSong != null) {
        dbSong.lyrics = lrc;
        await DbService.isar.songs.put(dbSong);
      }
    });
  }

  /// What a library rescan stores in song.lyrics: [existing] (the saved
  /// row) unless it holds nothing useful, [scanned] being the file's
  /// embedded lyrics as the scanner tags them. Saved lyrics - downloaded
  /// word-synced ones, sidecar, the user's picks and edits - must survive
  /// a rescan, or the next play shows the embedded text again and repeats
  /// the online upgrade. Only embedded lyrics are refreshed from the file
  /// (its tags may have been edited), keeping the checked mark when the
  /// text is unchanged.
  static String? mergeScanned(String? existing, String? scanned) {
    if (existing == null || existing.isEmpty || existing == notFound) {
      return scanned ?? existing;
    }
    if (scanned == null) return existing;
    final isEmbedded = existing.startsWith('[source:embedded]');
    if (!isEmbedded) return existing;
    final unmarked = existing.replaceAll('\n$_wordSyncChecked', '');
    return unmarked == scanned ? existing : scanned;
  }

  /// Automatic lookup, used on play, by the song info screen and by
  /// "Sync lyrics offline". Returns source-tagged lyrics, or null.
  static Future<String?> fetchLyrics(Song song) async {
    final artist = (song.artist ?? 'Unknown Artist').trim();
    final title = song.title.trim();

    // The database copy, not [song.lyrics]: the queue holds Song objects
    // loaded before lyrics were found or the cache was cleared.
    final dbSong = await DbService.isar.songs.get(song.id);
    var saved = dbSong != null ? dbSong.lyrics : song.lyrics;

    // 1. Saved lyrics (song.lyrics), then the cache file.
    if (saved == null || saved.isEmpty) {
      saved = await LyricsCache.get(artist, title);
      if (saved != null && saved.isNotEmpty) await _saveToDb(song, saved);
    }
    // Word-synced lyrics in the cache file beat unmarked ones without
    // word timing in the database (e.g. written back by an older rescan).
    if (saved != null &&
        saved.isNotEmpty &&
        !hasWordTiming(saved) &&
        canUpgradeToWordSync(saved)) {
      final cached = await LyricsCache.get(artist, title);
      if (cached != null && cached != notFound && hasWordTiming(cached)) {
        await _saveToDb(song, cached);
        return cached;
      }
    }

    if (saved != null && saved.isNotEmpty) {
      if (saved != notFound) {
        if (saved.startsWith('[source:')) {
          await _keepProviderCopy(song, saved);
          return saved;
        }
        // Self-heal untagged data: older scanners wrote embedded lyrics
        // untagged, and older editors saved the user's edits untagged. Tag
        // it once - embedded only when it matches the file's tags, else as
        // the user's own, so a rescan never replaces an edit.
        final embedded = await MetadataService.getEmbeddedLyrics(song.path);
        final tagged = embedded != null && embedded.trim() == saved.trim()
            ? '[source:embedded]\n$saved'
            : userLyrics(saved);
        await _saveToDb(song, tagged);
        return tagged;
      }
      // A saved "not found" still re-checks the song's own files - that's
      // fast and offline (and e.g. Android's embedded-lyrics reader was
      // added after some libraries were cached as not found) - but not the
      // online providers.
      final lrc = await _lookUp(song, const [local]);
      if (lrc != null) await store(song, artist, title, lrc);
      return lrc;
    }

    // 2. Nothing saved: walk the chain.
    final settings = await DbService.isar.appSettings.get(0);
    final lrc = await _lookUp(
      song,
      lookupChain(
        settings?.lyricsProvider ?? 'lrc.red',
        autoFallback: settings?.autoLyricsFallback ?? true,
      ),
      online: settings?.enableInternet ?? true,
    );
    if (lrc != null) {
      await store(song, artist, title, lrc);
      return lrc;
    }

    // Saved as "not found" only when the providers were really asked: with
    // internet off in settings, or no network, the next play tries again.
    if ((settings?.enableInternet ?? true) && await _isOnline()) {
      await store(song, artist, title, notFound);
    }
    return null;
  }

  /// Lyrics menu provider pick: asks [provider] first and, with
  /// auto-fallback on, the rest of the chain after it. Whatever is found
  /// replaces the song's current lyrics. Returns it (source-tagged), or null
  /// with the current lyrics left alone.
  static Future<String?> fetchWithProvider(Song song, String provider) async {
    final settings = await DbService.isar.appSettings.get(0);
    final chosen = provider.toUpperCase();
    final chain = [
      chosen,
      if (settings?.autoLyricsFallback ?? true)
        ...lookupChain(
          settings?.lyricsProvider ?? 'lrc.red',
          autoFallback: true,
        ).where((s) => s != chosen),
    ];
    // With internet off in settings, saved provider copies still load.
    final found = await _lookUp(
      song,
      chain,
      online: settings?.enableInternet ?? true,
    );
    final lrc = found == null ? null : pinned(found);
    if (lrc != null) {
      await store(
        song,
        (song.artist ?? 'Unknown Artist').trim(),
        song.title.trim(),
        lrc,
      );
    }
    return lrc;
  }

  /// The automatic lookup order: the song's own files, the [primary]
  /// provider, then (with [autoFallback]) the other providers.
  static List<String> lookupChain(
    String primary, {
    required bool autoFallback,
  }) {
    final chain = <String>[local, primary.toUpperCase()];
    if (autoFallback) chain.addAll(allProviders);
    return chain.toSet().toList();
  }

  /// Asks each source in [chain] in turn. First answer wins, except that a
  /// line-synced answer from a word-capable source (lrc.red serves some
  /// songs line-timed only) is held while the other word-capable source is
  /// asked for real word timing. Providers answer from their saved copy
  /// when they have one; with [online] false nothing else is asked.
  static Future<String?> _lookUp(
    Song song,
    List<String> chain, {
    bool online = true,
  }) async {
    String? heldLineSynced;
    for (final source in chain) {
      if (source == local) {
        final lrc = await _readLocal(song);
        if (lrc != null) return lrc;
        continue;
      }
      if (heldLineSynced != null && !_wordCapableProviders.contains(source)) {
        break;
      }
      final tagged = await _fromProvider(song, source, network: online);
      if (tagged == null) continue;
      if (hasWordTiming(tagged) || !_wordCapableProviders.contains(source)) {
        return tagged;
      }
      heldLineSynced ??= tagged;
    }
    return heldLineSynced;
  }

  static Future<LyricsResponse?> _askOnline(Song song, String provider) =>
      _service.getLyrics(
        trackName: song.title.trim(),
        artistName: (song.artist ?? 'Unknown Artist').trim(),
        albumName: (song.album ?? '').trim(),
        durationSeconds: (song.duration ?? 0) ~/ 1000,
        provider: provider,
      );

  /// Embedded tags, then a sidecar .lrc/.txt next to the song.
  static Future<String?> _readLocal(Song song) async {
    final embedded = await MetadataService.getEmbeddedLyrics(song.path);
    if (embedded != null && embedded.isNotEmpty) {
      return '[source:embedded]\n$embedded';
    }

    final songDir = File(song.path).parent.path;
    final baseName = p.basenameWithoutExtension(song.path);
    for (final path in [
      p.join(songDir, '$baseName.lrc'),
      p.join(songDir, '$baseName.txt'),
      p.join(songDir, 'lyrics', '$baseName.lrc'),
      p.join(songDir, 'lyrics', '$baseName.txt'),
      p.join(songDir, 'Lyrics', '$baseName.lrc'),
    ]) {
      try {
        final file = File(path);
        if (await file.exists()) {
          final content = await file.readAsString();
          if (content.isNotEmpty) return '[source:local]\n$content';
        }
      } catch (_) {}
    }
    return null;
  }

  /// Whether the network is reachable at all, so a lookup where every
  /// provider came back empty can be told apart from one that never got
  /// through (which must not be saved as "not found").
  static Future<bool> _isOnline() async {
    try {
      final result = await InternetAddress.lookup(
        'lrclib.net',
      ).timeout(const Duration(seconds: 3));
      return result.isNotEmpty && result.first.rawAddress.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// "Clear lyrics cache": forgets every online answer (downloaded lyrics
  /// and "not found") so those songs are looked up again on their next
  /// play. Lyrics from the song's own files, the user's .lrc picks and
  /// edits (stored untagged) are kept; the song's own files lose their
  /// word-sync "checked" mark, so they get the upgrade attempt again.
  static Future<void> clearAll() async {
    await LyricsCache.clear();
    final online = {
      for (final p in allProviders) '[source:${p.toLowerCase()}]',
    };
    await DbService.isar.writeTxn(() async {
      final songs = await DbService.isar.songs.where().findAll();
      final changed = <Song>[];
      for (final song in songs) {
        final lyrics = song.lyrics;
        if (lyrics == null) continue;
        final tag = _sourceTag.firstMatch(lyrics)?.group(0)?.toLowerCase();
        if (tag == '[source:embedded]' || tag == '[source:local]') {
          if (!lyrics.contains(_wordSyncChecked)) continue;
          song.lyrics = lyrics.replaceAll('\n$_wordSyncChecked', '');
        } else if (tag == notFound || online.contains(tag)) {
          song.lyrics = null;
        } else {
          continue;
        }
        changed.add(song);
      }
      await DbService.isar.songs.putAll(changed);
    });
  }
}
