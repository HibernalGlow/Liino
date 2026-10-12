import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Visits one ID3v2 frame with its format flags already undone. Frame ids
/// are the three (v2.2) or four (v2.3/v2.4) stored characters.
typedef Id3FrameVisitor = void Function(String id, Uint8List body);

/// The ID3v2 primitives shared by the lyric readers.
///
/// Everything here is best effort on untrusted bytes: anything unexpected
/// (corrupt sizes, compressed or encrypted frames, MPEG-frame timestamps)
/// stops the walk instead of throwing.
class Id3Frames {
  Id3Frames._();

  /// Tags are mostly cover art; one past this size isn't worth loading.
  static const int maxTagBytes = 32 * 1024 * 1024;

  static const int _encodingLatin1 = 0;
  static const int _encodingUtf16Bom = 1;
  static const int _encodingUtf16Be = 2;
  static const int _encodingUtf8 = 3;

  /// The whole ID3v2 tag of the file at [path] - its ten byte header plus
  /// the declared body - or null when the file has no usable tag.
  static Future<Uint8List?> readTag(String path) async {
    RandomAccessFile? file;
    try {
      file = await File(path).open();
      final header = await file.read(10);
      final size = tagSize(header);
      if (size == null || size > maxTagBytes) return null;
      final data = await file.read(size);
      return Uint8List.fromList([...header, ...data]);
    } catch (_) {
      return null;
    } finally {
      await file?.close();
    }
  }

  /// The declared body size of an ID3v2 tag, or null when [header] isn't an
  /// `ID3` header.
  static int? tagSize(List<int> header) {
    if (header.length < 10) return null;
    if (header[0] != 0x49 || header[1] != 0x44 || header[2] != 0x33) {
      return null;
    }
    return syncSafe(header, 6);
  }

  /// Visits every frame in [tag] - a file's bytes from its `ID3` header on,
  /// anything after the tag ignored. Frames whose body is compressed or
  /// encrypted are skipped rather than reported with a fabricated body.
  static void forEach(Uint8List tag, Id3FrameVisitor visit) {
    final size = tagSize(tag);
    if (size == null) return;
    final version = tag[3];
    if (version < 2 || version > 4) return;
    final flags = tag[5];
    final tagUnsync = flags & 0x80 != 0;

    var data = Uint8List.sublistView(
      tag,
      10,
      10 + size > tag.length ? tag.length : 10 + size,
    );
    // Up to v2.3 the whole tag is unsynchronised at once; v2.4 does it
    // frame by frame, with the sizes counting the stored bytes.
    if (tagUnsync && version < 4) data = resync(data);

    var pos = 0;
    if (flags & 0x40 != 0) {
      // v2.2 used this bit for a compression scheme that was never defined.
      if (version == 2) return;
      if (data.length < 4) return;
      pos = version == 3 ? 4 + uint32(data, 0) : syncSafe(data, 0);
    }

    final idLength = version == 2 ? 3 : 4;
    final headerLength = version == 2 ? 6 : 10;

    while (pos + headerLength <= data.length) {
      if (data[pos] == 0) break; // padding
      final id = String.fromCharCodes(data, pos, pos + idLength);
      final frameSize = switch (version) {
        2 => (data[pos + 3] << 16) | (data[pos + 4] << 8) | data[pos + 5],
        3 => uint32(data, pos + 4),
        _ => syncSafe(data, pos + 4),
      };
      final formatFlags = version == 2 ? 0 : data[pos + 9];
      final start = pos + headerLength;
      final end = start + frameSize;
      if (frameSize <= 0 || end > data.length) break;
      pos = end;

      final body = frameBody(
        Uint8List.sublistView(data, start, end),
        version,
        formatFlags,
        tagUnsync,
      );
      if (body == null) continue;
      visit(id, body);
    }
  }

  /// The frame's content with its format flags undone, or null when it is
  /// compressed or encrypted.
  static Uint8List? frameBody(
    Uint8List body,
    int version,
    int formatFlags,
    bool tagUnsync,
  ) {
    if (version == 3) {
      if (formatFlags & 0xc0 != 0) return null; // compressed / encrypted
      return formatFlags & 0x20 != 0 ? _skip(body, 1) : body; // group id
    }
    if (version == 4) {
      if (formatFlags & 0x0c != 0) return null; // compressed / encrypted
      var out = body;
      if (formatFlags & 0x40 != 0) out = _skip(out, 1); // group id
      if (formatFlags & 0x01 != 0) out = _skip(out, 4); // data length
      if (tagUnsync || formatFlags & 0x02 != 0) out = resync(out);
      return out;
    }
    return body;
  }

  /// Index of the string terminator at or after [from], or -1. UTF-16
  /// terminators are two zero bytes on a character boundary.
  static int terminator(Uint8List bytes, int from, bool wide) {
    if (!wide) return bytes.indexOf(0, from);
    for (var i = from; i + 1 < bytes.length; i += 2) {
      if (bytes[i] == 0 && bytes[i + 1] == 0) return i;
    }
    return -1;
  }

  /// Decodes the ID3 text [bytes] between [start] and [end] using the frame
  /// encoding byte, falling back to the raw code units for anything else.
  static String decode(Uint8List bytes, int start, int end, int encoding) {
    final slice = Uint8List.sublistView(bytes, start, end);
    switch (encoding) {
      case _encodingLatin1:
        return latin1.decode(slice);
      case _encodingUtf8:
        return utf8.decode(slice, allowMalformed: true);
    }
    // UTF-16: with a byte order mark (1), or big-endian without one (2).
    var bigEndian = encoding == _encodingUtf16Be;
    var i = 0;
    if (slice.length >= 2) {
      if (slice[0] == 0xff && slice[1] == 0xfe) {
        bigEndian = false;
        i = 2;
      } else if (slice[0] == 0xfe && slice[1] == 0xff) {
        bigEndian = true;
        i = 2;
      }
    }
    final units = <int>[];
    for (; i + 1 < slice.length; i += 2) {
      units.add(
        bigEndian
            ? (slice[i] << 8) | slice[i + 1]
            : (slice[i + 1] << 8) | slice[i],
      );
    }
    return String.fromCharCodes(units);
  }

  /// The encoding byte's "is this frame UTF-16" answer, and the byte width
  /// of its terminators.
  static bool isWideEncoding(int encoding) =>
      encoding == _encodingUtf16Bom || encoding == _encodingUtf16Be;

  /// Whether [encoding] is one this reader understands.
  static bool isKnownEncoding(int encoding) => encoding <= _encodingUtf8;

  /// Reverses unsynchronisation: drops the 0x00 inserted after every 0xff.
  static Uint8List resync(Uint8List bytes) {
    final out = BytesBuilder(copy: false);
    for (var i = 0; i < bytes.length; i++) {
      out.addByte(bytes[i]);
      if (bytes[i] == 0xff && i + 1 < bytes.length && bytes[i + 1] == 0) i++;
    }
    return out.toBytes();
  }

  static Uint8List _skip(Uint8List bytes, int count) =>
      Uint8List.sublistView(bytes, count > bytes.length ? bytes.length : count);

  static int uint32(List<int> b, int at) =>
      (b[at] << 24) | (b[at + 1] << 16) | (b[at + 2] << 8) | b[at + 3];

  static int syncSafe(List<int> b, int at) =>
      ((b[at] & 0x7f) << 21) |
      ((b[at + 1] & 0x7f) << 14) |
      ((b[at + 2] & 0x7f) << 7) |
      (b[at + 3] & 0x7f);
}
