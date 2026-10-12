import 'dart:typed_data';

import 'id3_frames.dart';
import 'timed_lyrics.dart';

/// Reads the ID3v2 SYLT frame (synchronised lyrics) of an mp3 and turns it
/// into LRC. Neither jaudiotagger's FieldKey.LYRICS nor ffprobe expose this
/// frame - both only return USLT, the unsynced copy taggers write next to
/// it - so a file with synced lyrics showed up as plain text.
///
/// The frame body, after the tag and frame headers:
///
///   encoding (1) | language (3) | timestamp format (1) | content type (1)
///   descriptor, terminated
///   then repeated: text, terminated | timestamp (4, big-endian)
///
/// An entry is a whole line or, in word-timed files, a single word - there
/// a newline in the text marks where a line ends. Words are joined back
/// into lines, each timed by its first word.
///
/// Everything here is best effort on untrusted bytes: anything unexpected
/// (corrupt sizes, compressed or encrypted frames, MPEG-frame timestamps)
/// gives null and the caller falls back to the USLT text.
class Id3SyltReader {
  static const int _timestampMs = 2;
  static const int _contentOther = 0;
  static const int _contentLyrics = 1;
  static const int _contentTranscription = 2;

  /// The synced lyrics of the file at [path] as LRC, or null.
  static Future<String?> readFile(String path) async {
    final tag = await Id3Frames.readTag(path);
    return tag == null ? null : fromTag(tag);
  }

  /// The synced lyrics in [tag] - a file's bytes from its `ID3` header on,
  /// anything after the tag ignored - as LRC, or null.
  static String? fromTag(Uint8List tag) {
    try {
      return _fromTag(tag);
    } catch (_) {
      return null;
    }
  }

  static String? _fromTag(Uint8List tag) {
    String? fallback;
    String? preferred;

    Id3Frames.forEach(tag, (id, body) {
      // A `lyrics` content type always wins over the fallbacks, and the
      // walk can't be broken out of - so once one has been seen the rest is
      // only worth skipping.
      if (preferred != null) return;
      if (id != 'SYLT' && id != 'SLT') return;
      if (body.length < 6) return;
      if (body[4] != _timestampMs) return;
      final contentType = body[5];
      if (contentType != _contentLyrics &&
          contentType != _contentOther &&
          contentType != _contentTranscription) {
        return;
      }
      final lrc = _toLrc(body);
      if (lrc == null) return;
      if (contentType == _contentLyrics) {
        preferred = lrc;
        return;
      }
      fallback ??= lrc;
    });

    return preferred ?? fallback;
  }

  static String? _toLrc(Uint8List body) {
    final encoding = body[0];
    if (!Id3Frames.isKnownEncoding(encoding)) return null;
    final wide = Id3Frames.isWideEncoding(encoding);

    // Descriptor first, then text + timestamp pairs.
    var pos = Id3Frames.terminator(body, 6, wide);
    if (pos < 0) return null;
    pos += wide ? 2 : 1;

    final entries = <({String text, int ms})>[];
    while (pos < body.length) {
      final textEnd = Id3Frames.terminator(body, pos, wide);
      if (textEnd < 0) break;
      final stamp = textEnd + (wide ? 2 : 1);
      if (stamp + 4 > body.length) break;
      entries.add((
        text: Id3Frames.decode(
          body,
          pos,
          textEnd,
          encoding,
        ).replaceAll('\r', ''),
        ms: Id3Frames.uint32(body, stamp),
      ));
      pos = stamp + 4;
    }
    if (entries.isEmpty) return null;

    final lines = <({int ms, String text})>[];
    if (entries.any((e) => e.text.contains('\n'))) {
      // Word-timed: a line runs until the next newline.
      int? lineMs;
      final text = StringBuffer();
      void endLine() {
        if (lineMs != null) lines.add((ms: lineMs!, text: text.toString()));
        lineMs = null;
        text.clear();
      }

      for (final entry in entries) {
        final pieces = entry.text.split('\n');
        for (var i = 0; i < pieces.length; i++) {
          if (i > 0) endLine();
          if (pieces[i].isEmpty) continue;
          lineMs ??= entry.ms;
          text.write(pieces[i]);
        }
      }
      endLine();
    } else {
      for (final entry in entries) {
        lines.add((ms: entry.ms, text: entry.text));
      }
    }

    return TimedLrcWriter.write([
      for (var i = 0; i < lines.length; i++)
        TimedLyricLine(
          startMs: lines[i].ms,
          endMs: i + 1 < lines.length ? lines[i + 1].ms : lines[i].ms,
          text: lines[i].text.trim(),
        ),
    ]);
  }
}
