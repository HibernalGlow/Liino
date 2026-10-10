import 'package:looper_player/features/library/domain/models/models.dart';

/// One track line of an M3U playlist, with the `#EXTINF` artist/title that
/// preceded it when the playlist is an extended one.
class M3uEntry {
  final String path;
  final String? title;
  final String? artist;

  const M3uEntry({required this.path, this.title, this.artist});
}

/// Reads `.m3u` / `.m3u8` playlists, plain or extended (`#EXTM3U`).
class M3uParser {
  /// The local-file entries of [content], in playlist order. Comments and
  /// network streams are skipped - the player only plays local files.
  static List<M3uEntry> parse(String content) {
    final entries = <M3uEntry>[];
    String? title;
    String? artist;

    for (var line in content.split(RegExp(r'\r\n|\r|\n'))) {
      line = line.replaceFirst('\uFEFF', '').trim();
      if (line.isEmpty) continue;

      if (line.startsWith('#')) {
        if (line.toUpperCase().startsWith('#EXTINF:')) {
          // #EXTINF:<seconds>[ attributes],<Artist - Title>
          final comma = line.indexOf(',');
          final info = comma == -1 ? '' : line.substring(comma + 1).trim();
          final dash = info.indexOf(' - ');
          if (dash == -1) {
            title = info.isEmpty ? null : info;
            artist = null;
          } else {
            artist = info.substring(0, dash).trim();
            title = info.substring(dash + 3).trim();
          }
        }
        continue;
      }

      final path = _localPath(line);
      if (path != null) {
        entries.add(M3uEntry(path: path, title: title, artist: artist));
      }
      title = null;
      artist = null;
    }
    return entries;
  }

  /// [line] as a file path with forward slashes, or null for a network
  /// stream.
  static String? _localPath(String line) {
    var path = line;
    final scheme = RegExp(r'^([a-zA-Z][a-zA-Z0-9+.-]+)://').firstMatch(path);
    if (scheme != null) {
      if (scheme.group(1)!.toLowerCase() != 'file') return null;
      path = path.substring(scheme.end);
      // file://localhost/music/a.mp3 and file:///C:/music/a.mp3
      if (path.startsWith('localhost/')) path = path.substring(9);
      if (RegExp(r'^/[a-zA-Z]:/').hasMatch(path)) path = path.substring(1);
      try {
        path = Uri.decodeFull(path);
      } catch (_) {
        // Not percent-encoded after all - keep it as written.
      }
    }
    path = path.replaceAll('\\', '/');
    return path.isEmpty ? null : path;
  }
}

/// Finds the library songs an M3U playlist refers to. Playlists usually come
/// from another app or device, so a path that doesn't exist here falls back
/// to the file name and then to the `#EXTINF` title and artist.
class M3uSongMatcher {
  final Map<String, Song> _byPath = {};
  final Map<String, List<Song>> _byFileName = {};
  final Map<String, Song> _byTitleArtist = {};

  M3uSongMatcher(Iterable<Song> songs) {
    for (final song in songs) {
      final path = _normalize(song.path);
      _byPath[path] = song;
      _byFileName.putIfAbsent(_fileName(path), () => []).add(song);
      _byTitleArtist.putIfAbsent(
        _titleArtistKey(song.title, song.artist),
        () => song,
      );
    }
  }

  /// The song [entry] refers to, or null when the library has none.
  /// [playlistDir] is the folder the playlist file sits in, for relative
  /// paths.
  Song? match(M3uEntry entry, {String? playlistDir}) {
    final path = _normalize(entry.path);

    final exact = _byPath[path];
    if (exact != null) return exact;

    if (playlistDir != null && !_isAbsolute(path)) {
      final relative = _byPath[_join(_normalize(playlistDir), path)];
      if (relative != null) return relative;
    }

    final sameName = _byFileName[_fileName(path)];
    if (sameName != null) {
      if (sameName.length == 1) return sameName.first;
      // Several files share the name: the one whose folders match the
      // entry's furthest back is the likeliest.
      Song best = sameName.first;
      int bestShared = -1;
      for (final song in sameName) {
        final shared = _sharedTrailingSegments(path, _normalize(song.path));
        if (shared > bestShared) {
          best = song;
          bestShared = shared;
        }
      }
      return best;
    }

    final title = entry.title;
    if (title != null && title.isNotEmpty) {
      return _byTitleArtist[_titleArtistKey(title, entry.artist)];
    }
    return null;
  }

  static String _normalize(String path) =>
      path.replaceAll('\\', '/').toLowerCase();

  static String _fileName(String path) =>
      path.substring(path.lastIndexOf('/') + 1);

  static bool _isAbsolute(String path) =>
      path.startsWith('/') || RegExp(r'^[a-z]:/').hasMatch(path);

  /// [dir] + relative [path], with `.` and `..` segments resolved.
  static String _join(String dir, String path) {
    final segments = dir.split('/');
    if (segments.isNotEmpty && segments.last.isEmpty) segments.removeLast();
    for (final segment in path.split('/')) {
      if (segment == '.' || segment.isEmpty) continue;
      if (segment == '..') {
        if (segments.length > 1) segments.removeLast();
        continue;
      }
      segments.add(segment);
    }
    return segments.join('/');
  }

  static int _sharedTrailingSegments(String a, String b) {
    final as = a.split('/');
    final bs = b.split('/');
    int shared = 0;
    while (shared < as.length &&
        shared < bs.length &&
        as[as.length - 1 - shared] == bs[bs.length - 1 - shared]) {
      shared++;
    }
    return shared;
  }

  static String _titleArtistKey(String title, String? artist) =>
      '${title.trim().toLowerCase()}\n${(artist ?? '').trim().toLowerCase()}';
}

/// [name], or "[name] (2)", "[name] (3)"... - the first one not in [taken].
String uniquePlaylistName(String name, Set<String> taken) {
  if (!taken.contains(name)) return name;
  int n = 2;
  while (taken.contains('$name ($n)')) {
    n++;
  }
  return '$name ($n)';
}
