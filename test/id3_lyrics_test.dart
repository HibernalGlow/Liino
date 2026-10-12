import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:looper_player/features/playback/data/lyrics_formats/id3_frames.dart';
import 'package:looper_player/features/playback/data/lyrics_formats/id3_sylt_reader.dart';
import 'package:looper_player/features/playback/data/lyrics_formats/id3_uslt_reader.dart';

Uint8List _syncSafe(int value) => Uint8List.fromList([
  (value >> 21) & 0x7f,
  (value >> 14) & 0x7f,
  (value >> 7) & 0x7f,
  value & 0x7f,
]);

/// One ID3v2 frame. [formatFlags] is the second flag byte, the one that
/// carries the group/compression/encryption bits.
Uint8List _frame(
  String id,
  List<int> body, {
  required int version,
  int formatFlags = 0,
}) {
  final out = BytesBuilder();
  out.add(ascii.encode(id));
  if (version == 4) {
    out.add(_syncSafe(body.length));
  } else {
    out.add([
      (body.length >> 24) & 0xff,
      (body.length >> 16) & 0xff,
      (body.length >> 8) & 0xff,
      body.length & 0xff,
    ]);
  }
  out.add([0, formatFlags]);
  out.add(body);
  return out.toBytes();
}

/// A whole ID3v2 tag: the ten byte header plus [frames].
Uint8List _tag(List<Uint8List> frames, {int version = 3}) {
  final body = BytesBuilder(copy: false);
  for (final frame in frames) {
    body.add(frame);
  }
  final bodyBytes = body.toBytes();
  final out = BytesBuilder(copy: false);
  out.add(ascii.encode('ID3'));
  out.add([version, 0, 0]);
  out.add(_syncSafe(bodyBytes.length));
  out.add(bodyBytes);
  return out.toBytes();
}

Uint8List _usltLatin1(String lyrics) => Uint8List.fromList([
  0, // ISO-8859-1
  ...ascii.encode('eng'),
  0, // empty descriptor terminator
  ...latin1.encode(lyrics),
]);

Uint8List _usltUtf8(String lyrics) => Uint8List.fromList([
  3, // UTF-8
  ...ascii.encode('eng'),
  0,
  ...utf8.encode(lyrics),
]);

Uint8List _usltUtf16(String lyrics) {
  final out = BytesBuilder(copy: false);
  out.add([1]); // UTF-16 with BOM
  out.add(ascii.encode('eng'));
  out.add([0, 0]); // UTF-16 descriptor terminator
  out.add([0xff, 0xfe]); // little-endian BOM
  for (final unit in lyrics.codeUnits) {
    out.add([unit & 0xff, (unit >> 8) & 0xff]);
  }
  return out.toBytes();
}

/// SYLT: encoding, language, ms timestamps, content type, descriptor, then
/// `text \0 timestamp` pairs.
Uint8List _sylt(
  List<(String, int)> entries, {
  int contentType = 1,
  int timestampFormat = 2,
}) {
  final out = BytesBuilder(copy: false);
  out.add([0]); // ISO-8859-1
  out.add(ascii.encode('eng'));
  out.add([timestampFormat, contentType, 0]);
  for (final (text, ms) in entries) {
    out.add(ascii.encode(text));
    out.add([0]);
    out.add([
      (ms >> 24) & 0xff,
      (ms >> 16) & 0xff,
      (ms >> 8) & 0xff,
      ms & 0xff,
    ]);
  }
  return out.toBytes();
}

void main() {
  group('Id3UsltReader.fromTag', () {
    test('reads a latin1 USLT frame', () {
      final tag = _tag([
        _frame('USLT', _usltLatin1('Hello\nWorld'), version: 3),
      ]);
      expect(Id3UsltReader.fromTag(tag), 'Hello\nWorld');
    });

    test('reads a UTF-8 USLT frame', () {
      final tag = _tag([
        _frame('USLT', _usltUtf8('Взгляд сквозь стекло'), version: 3),
      ]);
      expect(Id3UsltReader.fromTag(tag), 'Взгляд сквозь стекло');
    });

    test('reads a UTF-16 USLT frame with a byte order mark', () {
      final tag = _tag([_frame('USLT', _usltUtf16('さよなら'), version: 3)]);
      expect(Id3UsltReader.fromTag(tag), 'さよなら');
    });

    test('reads a v2.4 frame, whose size is syncsafe', () {
      // A body long enough that the syncsafe and plain encodings differ.
      final lyrics = 'a' * 200;
      final tag = _tag([
        _frame('USLT', _usltUtf8(lyrics), version: 4),
      ], version: 4);
      expect(Id3UsltReader.fromTag(tag), lyrics);
    });

    test('walks past unrelated frames', () {
      final tag = _tag([
        _frame('TIT2', [3, ...utf8.encode('A Title')], version: 3),
        _frame('APIC', List.filled(64, 7), version: 3),
        _frame('USLT', _usltLatin1('after the others'), version: 3),
      ]);
      expect(Id3UsltReader.fromTag(tag), 'after the others');
    });

    test('returns LRC stored in USLT unchanged', () {
      const lrc = '[00:12.340]first line\n[00:15.000]second line';
      final tag = _tag([_frame('USLT', _usltUtf8(lrc), version: 3)]);
      expect(Id3UsltReader.fromTag(tag), lrc);
    });

    test('normalises CRLF line endings', () {
      final tag = _tag([_frame('USLT', _usltLatin1('one\r\ntwo'), version: 3)]);
      expect(Id3UsltReader.fromTag(tag), 'one\ntwo');
    });

    test('skips a compressed frame instead of guessing at its bytes', () {
      final tag = _tag([
        _frame(
          'USLT',
          _usltLatin1('compressed'),
          version: 3,
          formatFlags: 0x80,
        ),
      ]);
      expect(Id3UsltReader.fromTag(tag), isNull);
    });

    test('is null for a tag with no lyrics frame', () {
      final tag = _tag([
        _frame('TIT2', [3, ...utf8.encode('A Title')], version: 3),
      ]);
      expect(Id3UsltReader.fromTag(tag), isNull);
    });

    test('is null for a file that is not ID3 at all', () {
      final tag = Uint8List.fromList(List.filled(64, 0x2a));
      expect(Id3UsltReader.fromTag(tag), isNull);
      expect(Id3SyltReader.fromTag(tag), isNull);
    });

    test('is null for an empty descriptor with no lyrics after it', () {
      final tag = _tag([
        _frame('USLT', [0, 0x65, 0x6e, 0x67, 0], version: 3),
      ]);
      expect(Id3UsltReader.fromTag(tag), isNull);
    });

    test('is null for an encoding byte it does not understand', () {
      final tag = _tag([
        _frame('USLT', [9, 0x65, 0x6e, 0x67, 0, 0x41], version: 3),
      ]);
      expect(Id3UsltReader.fromTag(tag), isNull);
    });
  });

  group('Id3SyltReader.fromTag', () {
    test('turns a millisecond-timed SYLT frame into LRC', () {
      final tag = _tag([
        _frame(
          'SYLT',
          _sylt([('Line one', 1500), ('Line two', 3000)]),
          version: 3,
        ),
      ]);

      final lrc = Id3SyltReader.fromTag(tag);
      expect(lrc, isNotNull);
      expect(lrc, contains('[00:01.500]Line one'));
      expect(lrc, contains('[00:03.000]Line two'));
    });

    test('reads a v2.4 SYLT frame too', () {
      final tag = _tag([
        _frame('SYLT', _sylt([('Later', 45000)]), version: 4),
      ], version: 4);

      expect(Id3SyltReader.fromTag(tag), contains('[00:45.000]Later'));
    });

    test('prefers a lyrics content type over a fallback one', () {
      final tag = _tag([
        _frame(
          'SYLT',
          _sylt([('Transcription', 1000)], contentType: 2),
          version: 3,
        ),
        _frame(
          'SYLT',
          _sylt([('Real lyrics', 2000)], contentType: 1),
          version: 3,
        ),
      ]);

      final lrc = Id3SyltReader.fromTag(tag);
      expect(lrc, contains('Real lyrics'));
      expect(lrc, isNot(contains('Transcription')));
    });

    test('falls back to a non-lyrics content type when it is all there is', () {
      final tag = _tag([
        _frame(
          'SYLT',
          _sylt([('Only transcription', 1000)], contentType: 2),
          version: 3,
        ),
      ]);

      expect(Id3SyltReader.fromTag(tag), contains('Only transcription'));
    });

    test('ignores MPEG-frame timestamps it cannot convert', () {
      final tag = _tag([
        _frame('SYLT', _sylt([('Nope', 1234)], timestampFormat: 1), version: 3),
      ]);

      expect(Id3SyltReader.fromTag(tag), isNull);
    });

    test('joins word-timed entries back into lines', () {
      final tag = _tag([
        _frame(
          'SYLT',
          _sylt([('Hel', 1000), ('lo\n', 1200), ('Wor', 2000), ('ld', 2200)]),
          version: 3,
        ),
      ]);

      final lrc = Id3SyltReader.fromTag(tag);
      expect(lrc, contains('[00:01.000]Hello'));
      expect(lrc, contains('[00:02.000]World'));
    });
  });

  group('Id3Frames', () {
    test('reports the declared tag size', () {
      final tag = _tag([_frame('USLT', _usltLatin1('x'), version: 3)]);
      expect(Id3Frames.tagSize(tag), tag.length - 10);
    });

    test('rejects headers that are too short or not ID3', () {
      expect(Id3Frames.tagSize(const [0x49, 0x44, 0x33]), isNull);
      expect(Id3Frames.tagSize(ascii.encode('RIFF0000xx')), isNull);
    });

    test('stops cleanly on a truncated frame rather than throwing', () {
      final tag = _tag([_frame('USLT', _usltLatin1('x'), version: 3)]);
      // Drop the last ten bytes so the frame's declared size overruns the tag.
      final truncated = Uint8List.sublistView(tag, 0, tag.length - 5);
      expect(Id3UsltReader.fromTag(truncated), isNull);
    });

    test('reads a tag straight off disk', () async {
      final dir = Directory.systemTemp.createTempSync('looper_id3_test');
      addTearDown(() => dir.deleteSync(recursive: true));
      final file = File('${dir.path}/song.mp3');
      final tag = _tag([
        _frame('USLT', _usltLatin1('from a file'), version: 3),
      ]);
      // Real mp3s carry audio after the tag; the reader must ignore it.
      file.writeAsBytesSync([...tag, ...List.filled(2048, 0x11)]);

      expect(await Id3UsltReader.readFile(file.path), 'from a file');
    });

    test('reading a missing file is null, not an exception', () async {
      expect(await Id3UsltReader.readFile('/nonexistent/nope.mp3'), isNull);
      expect(await Id3SyltReader.readFile('/nonexistent/nope.mp3'), isNull);
    });
  });
}
