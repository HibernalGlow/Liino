import 'dart:typed_data';

import 'id3_frames.dart';

/// Reads the ID3v2 USLT frame (unsynchronised lyrics) of an mp3 - the plain
/// text lyrics tag almost every tagger writes.
///
/// The frame body, after the tag and frame headers:
///
///   encoding (1) | language (3) | descriptor, terminated | lyrics
///
/// Looper already had two ways to read this tag, and neither reaches
/// Windows or macOS: Android goes through MediaMetadataRetriever over a
/// MethodChannel, and Linux shells out to `ffprobe`. [Id3Frames] already
/// knows how to walk the tag bytes, so the same frame is decoded in pure
/// Dart here and both desktops get embedded lyrics without depending on an
/// external binary being installed.
///
/// Some taggers store full LRC in USLT. That is returned as-is rather than
/// stripped: it is what the ffprobe and Android paths return today, and the
/// lyric parsers downstream already recognise it.
class Id3UsltReader {
  /// The unsynced lyrics of the file at [path], or null.
  static Future<String?> readFile(String path) async {
    final tag = await Id3Frames.readTag(path);
    return tag == null ? null : fromTag(tag);
  }

  /// The unsynced lyrics in [tag] - a file's bytes from its `ID3` header on,
  /// anything after the tag ignored - or null.
  static String? fromTag(Uint8List tag) {
    try {
      return _fromTag(tag);
    } catch (_) {
      return null;
    }
  }

  static String? _fromTag(Uint8List tag) {
    String? lyrics;

    Id3Frames.forEach(tag, (id, body) {
      if (lyrics != null) return;
      if (id != 'USLT' && id != 'ULT') return;
      // encoding (1) + language (3), then the descriptor.
      if (body.length < 4) return;
      final encoding = body[0];
      if (!Id3Frames.isKnownEncoding(encoding)) return;
      final wide = Id3Frames.isWideEncoding(encoding);

      var pos = Id3Frames.terminator(body, 4, wide);
      if (pos < 0) return;
      pos += wide ? 2 : 1;
      if (pos >= body.length) return;

      final text = Id3Frames.decode(
        body,
        pos,
        body.length,
        encoding,
      ).replaceAll('\r\n', '\n').trim();
      if (text.isNotEmpty) lyrics = text;
    });

    return lyrics;
  }
}
