import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:meta/meta.dart';

/// The tags [DesktopTagReader] could find. Every field is null when absent.
class DesktopTags {
  final String? title;
  final String? artist;
  final String? album;
  final String? genre;
  final int? durationMs;
  final int? trackNumber;
  final int? year;

  const DesktopTags({
    this.title,
    this.artist,
    this.album,
    this.genre,
    this.durationMs,
    this.trackNumber,
    this.year,
  });
}

/// Reads embedded tags and cover art with ffprobe/ffmpeg on the desktop
/// platforms: the scanner falls back to it when metadata_god is unavailable
/// or couldn't read a particular file, the same way Android falls back to
/// its native readers.
///
/// Started Linux-only - there metadata_god needed the extra safety net, and
/// the reader was reached through a bare `ffprobe` PATH lookup - and is now
/// shared by all three desktops. A Windows or macOS machine with ffmpeg
/// installed gets the same tag and cover-art fallback; one without ffmpeg
/// resolves no executable and simply skips it.
class DesktopTagReader {
  static String? _ffprobe;
  static String? _ffmpeg;
  static bool _ffprobeResolved = false;
  static bool _ffmpegResolved = false;

  /// Absolute path of a usable `ffprobe`, or null when there is none.
  /// Resolved once - the search costs a couple of process spawns.
  static Future<String?> ffprobe() async {
    if (!_ffprobeResolved) {
      _ffprobe = await _locate('ffprobe');
      _ffprobeResolved = true;
    }
    return _ffprobe;
  }

  /// Absolute path of a usable `ffmpeg`, or null when there is none.
  static Future<String?> ffmpeg() async {
    if (!_ffmpegResolved) {
      _ffmpeg = await _locate('ffmpeg');
      _ffmpegResolved = true;
    }
    return _ffmpeg;
  }

  /// Clears the cached executable lookups. Tests only.
  @visibleForTesting
  static void resetResolvedExecutables() {
    _ffprobe = null;
    _ffmpeg = null;
    _ffprobeResolved = false;
    _ffmpegResolved = false;
  }

  /// Every place [name] is worth looking for, bare name first so a PATH
  /// entry still wins.
  ///
  /// The absolute candidates exist because a GUI-launched macOS app does not
  /// inherit the login shell's PATH, which hides Homebrew's
  /// `/opt/homebrew/bin` from a double-clicked build entirely.
  @visibleForTesting
  static List<String> candidateExecutables(
    String name, {
    String? operatingSystem,
    Map<String, String>? environment,
  }) {
    final os = operatingSystem ?? Platform.operatingSystem;
    final env = environment ?? Platform.environment;
    final candidates = <String>[name];
    if (os == 'windows') {
      const suffixes = [r'\ffmpeg\bin', r'\ffmpeg'];
      final roots = <String>[
        env['ProgramFiles'] ?? '',
        env['ProgramFiles(x86)'] ?? '',
        env['ChocolateyInstall'] ?? '',
        env['LOCALAPPDATA'] ?? '',
      ].where((root) => root.isNotEmpty);
      for (final root in roots) {
        for (final suffix in suffixes) {
          candidates.add('$root$suffix\\$name.exe');
        }
      }
      return candidates;
    }
    if (os == 'macos') {
      candidates.addAll([
        '/opt/homebrew/bin/$name',
        '/usr/local/bin/$name',
        '/opt/local/bin/$name',
        '/usr/bin/$name',
      ]);
      return candidates;
    }
    candidates.addAll(['/usr/bin/$name', '/usr/local/bin/$name']);
    return candidates;
  }

  /// The first candidate that actually runs, or null.
  static Future<String?> _locate(String name) async {
    for (final candidate in candidateExecutables(name)) {
      // A bare name is resolved by the OS through PATH; only an absolute
      // candidate is worth a cheaper existence check first.
      if (candidate.contains(Platform.pathSeparator)) {
        if (!await File(candidate).exists()) continue;
      }
      if (await _runs(candidate)) return candidate;
    }
    return null;
  }

  static Future<bool> _runs(String executable) async {
    try {
      final result = await Process.run(executable, ['-version']);
      return result.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  /// Pure: turns `ffprobe -print_format json -show_format -show_streams`
  /// output into tags. Container tags win; the first audio stream's tags
  /// fill the gaps (Ogg/Opus keep their tags there).
  static DesktopTags parse(Map<String, dynamic> json) {
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

    return DesktopTags(
      title: tags['title'],
      artist: tags['artist'] ?? tags['album_artist'] ?? tags['albumartist'],
      album: tags['album'],
      genre: tags['genre'],
      durationMs: durationMs,
      trackNumber: leadingInt(tags['track'] ?? tags['tracknumber']),
      year: (year != null && year >= 1000) ? year : null,
    );
  }

  static Future<DesktopTags?> read(
    String path, {
    required Duration timeout,
    required String executable,
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
    required String executable,
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
