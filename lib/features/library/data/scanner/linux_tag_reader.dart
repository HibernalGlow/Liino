import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

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
