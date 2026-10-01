import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:metadata_god/metadata_god.dart';
import 'package:path/path.dart' as p;

class AudioAnalysis {
  final String codec;
  final String container;
  final int sampleRate;
  final int channels;
  final int bitrate;
  final int bitsPerSample;
  final double duration;
  final double? integratedLufs;
  final double? truePeakDb;

  // Extended Metadata
  final String? isrc;
  final String? copyright;
  final String? composer;
  final String? label;
  final String? encoder;

  AudioAnalysis({
    required this.codec,
    required this.container,
    required this.sampleRate,
    required this.channels,
    required this.bitrate,
    required this.bitsPerSample,
    required this.duration,
    this.integratedLufs,
    this.truePeakDb,
    this.isrc,
    this.copyright,
    this.composer,
    this.label,
    this.encoder,
  });

  String get bitDepth => bitsPerSample > 0 ? '$bitsPerSample-bit' : 'N/A';
  String get sampleRateKhz => '${(sampleRate / 1000).toStringAsFixed(1)} kHz';
  String get bitrateKbps => '${(bitrate / 1000).round()} kbps';
}

class AudioAnalyzer {
  static final Map<String, AudioAnalysis> _cache = {};

  static AudioAnalysis? getCachedAnalysis(String filePath) {
    return _cache[filePath];
  }

  static Future<AudioAnalysis?> analyze(String filePath) async {
    if (_cache.containsKey(filePath)) {
      return _cache[filePath];
    }
    try {
      final ext = p.extension(filePath).replaceAll('.', '').toUpperCase();
      final file = File(filePath);
      final fileSize = await file.length();
      final technical = await _readTechnicalInfo(file, ext);

      Metadata? metadata;
      try {
        metadata = await MetadataGod.readMetadata(file: filePath);
      } catch (_) {}

      final metadataDuration = (metadata?.durationMs ?? 0) / 1000.0;
      final durationSec = metadataDuration > 0
          ? metadataDuration
          : technical.duration;
      final bitrate = technical.bitrate > 0
          ? technical.bitrate
          : durationSec > 0
          ? ((fileSize * 8) / durationSec).round()
          : 0;

      final analysis = AudioAnalysis(
        codec: technical.codec ?? (ext.isNotEmpty ? ext : 'AUDIO'),
        container: ext.isNotEmpty ? ext : 'FILE',
        sampleRate: technical.sampleRate,
        channels: technical.channels,
        bitrate: bitrate,
        bitsPerSample: technical.bitsPerSample,
        duration: durationSec,
      );
      _cache[filePath] = analysis;
      return analysis;
    } catch (_) {
      return null;
    }
  }

  static Future<Map<String, double>?> getLoudness(String filePath) async {
    return null;
  }

  static Future<_TechnicalAudioInfo> _readTechnicalInfo(
    File file,
    String extension,
  ) async {
    final length = await file.length();
    final handle = await file.open();
    try {
      const int window = 1024 * 1024;
      final bytes = await handle.read(math.min(length, window));
      switch (extension) {
        case 'FLAC':
          return _parseFlac(bytes);
        case 'WAV' || 'WAVE':
          return _parseWave(bytes);
        case 'AIFF' || 'AIF' || 'AIFC':
          return _parseAiff(bytes);
        case 'DSF':
          return _parseDsf(bytes);
        case 'DFF':
          return _parseDff(bytes);
        case 'WV':
          return _parseWavPack(bytes);
        case 'M4A' || 'MP4' || 'ALAC':
          final info = _parseMp4(bytes);
          // Files that aren't "fast start" keep the moov box at the end.
          if (info.codec == null && length > window) {
            await handle.setPosition(length - window);
            return _parseMp4(await handle.read(window));
          }
          return info;
      }
      return const _TechnicalAudioInfo();
    } finally {
      await handle.close();
    }
  }

  static _TechnicalAudioInfo _parseFlac(Uint8List bytes) {
    if (bytes.length < 42 ||
        bytes[0] != 0x66 ||
        bytes[1] != 0x4c ||
        bytes[2] != 0x61 ||
        bytes[3] != 0x43) {
      return const _TechnicalAudioInfo();
    }

    var offset = 4;
    while (offset + 4 <= bytes.length) {
      final type = bytes[offset] & 0x7f;
      final blockLength =
          (bytes[offset + 1] << 16) |
          (bytes[offset + 2] << 8) |
          bytes[offset + 3];
      final dataOffset = offset + 4;
      if (dataOffset + blockLength > bytes.length) break;
      if (type == 0 && blockLength >= 34) {
        final packed = ByteData.sublistView(
          bytes,
          dataOffset + 10,
          dataOffset + 18,
        ).getUint64(0, Endian.big);
        final sampleRate = (packed >> 44) & 0xfffff;
        final channels = ((packed >> 41) & 0x7) + 1;
        final bitsPerSample = ((packed >> 36) & 0x1f) + 1;
        final totalSamples = packed & 0xfffffffff;
        return _TechnicalAudioInfo(
          sampleRate: sampleRate,
          channels: channels,
          bitsPerSample: bitsPerSample,
          duration: sampleRate > 0 ? totalSamples / sampleRate : 0,
        );
      }
      offset = dataOffset + blockLength;
    }
    return const _TechnicalAudioInfo();
  }

  static _TechnicalAudioInfo _parseWave(Uint8List bytes) {
    if (bytes.length < 12 ||
        !((bytes[0] == 0x52 &&
                bytes[1] == 0x49 &&
                bytes[2] == 0x46 &&
                bytes[3] == 0x46) ||
            (bytes[0] == 0x52 &&
                bytes[1] == 0x46 &&
                bytes[2] == 0x36 &&
                bytes[3] == 0x34)) ||
        bytes[8] != 0x57 ||
        bytes[9] != 0x41 ||
        bytes[10] != 0x56 ||
        bytes[11] != 0x45) {
      return const _TechnicalAudioInfo();
    }

    final data = ByteData.sublistView(bytes);
    var offset = 12;
    while (offset + 8 <= bytes.length) {
      final chunkSize = data.getUint32(offset + 4, Endian.little);
      final dataOffset = offset + 8;
      if (bytes[offset] == 0x66 &&
          bytes[offset + 1] == 0x6d &&
          bytes[offset + 2] == 0x74 &&
          bytes[offset + 3] == 0x20 &&
          chunkSize >= 16 &&
          dataOffset + 16 <= bytes.length) {
        final formatTag = data.getUint16(dataOffset, Endian.little);
        final containerBits = data.getUint16(dataOffset + 14, Endian.little);
        final validBits =
            formatTag == 0xfffe &&
                chunkSize >= 20 &&
                dataOffset + 20 <= bytes.length
            ? data.getUint16(dataOffset + 18, Endian.little)
            : 0;
        return _TechnicalAudioInfo(
          channels: data.getUint16(dataOffset + 2, Endian.little),
          sampleRate: data.getUint32(dataOffset + 4, Endian.little),
          bitrate: data.getUint32(dataOffset + 8, Endian.little) * 8,
          bitsPerSample: validBits > 0 ? validBits : containerBits,
        );
      }
      offset = dataOffset + chunkSize + (chunkSize.isOdd ? 1 : 0);
    }
    return const _TechnicalAudioInfo();
  }

  static int _indexOf(Uint8List bytes, String tag, [int start = 0]) {
    final codes = tag.codeUnits;
    outer:
    for (int i = math.max(0, start); i + codes.length <= bytes.length; i++) {
      for (int j = 0; j < codes.length; j++) {
        if (bytes[i + j] != codes[j]) continue outer;
      }
      return i;
    }
    return -1;
  }

  static bool _tagAt(Uint8List bytes, int offset, String tag) =>
      offset >= 0 &&
      offset + tag.length <= bytes.length &&
      String.fromCharCodes(bytes, offset, offset + tag.length) == tag;

  /// MP4/M4A: the first audio sample entry in the `stsd` box tells ALAC
  /// (lossless) apart from AAC, which share the .m4a extension.
  static _TechnicalAudioInfo _parseMp4(Uint8List bytes) {
    final int stsd = _indexOf(bytes, 'stsd');
    // Entry: size(4) format(4) reserved(6) dataRef(2) version(2) revision(2)
    // vendor(4) channels(2) sampleSize(2) compression(2) packet(2) rate(4).
    final int entry = stsd + 12;
    if (stsd < 0 || entry + 36 > bytes.length) {
      return const _TechnicalAudioInfo();
    }
    final data = ByteData.sublistView(bytes);
    final String format = String.fromCharCodes(bytes, entry + 4, entry + 8);
    final int channels = data.getUint16(entry + 24);
    final int sampleSize = data.getUint16(entry + 26);
    // 16.16 fixed point, so it tops out at 65535 Hz; ALAC has its own field.
    final int rate = data.getUint16(entry + 32);

    if (format == 'alac') {
      // ALACSpecificConfig, after the inner 'alac' box's version/flags.
      final int box = _indexOf(bytes, 'alac', entry + 36);
      final int config = box + 8;
      if (box >= 0 && config + 24 <= bytes.length) {
        return _TechnicalAudioInfo(
          codec: 'ALAC',
          bitsPerSample: bytes[config + 5],
          channels: bytes[config + 9],
          bitrate: data.getUint32(config + 16),
          sampleRate: data.getUint32(config + 20),
        );
      }
      return _TechnicalAudioInfo(
        codec: 'ALAC',
        channels: channels,
        bitsPerSample: sampleSize,
        sampleRate: rate,
      );
    }
    final String? codec = switch (format) {
      'mp4a' => 'AAC',
      'fLaC' => 'FLAC',
      'Opus' => 'OPUS',
      'ac-3' => 'AC3',
      'ec-3' => 'EAC3',
      _ => null,
    };
    if (codec == null) return const _TechnicalAudioInfo();
    return _TechnicalAudioInfo(
      codec: codec,
      channels: channels,
      // AAC and the other lossy codecs have no real bit depth; the entry
      // always says 16.
      bitsPerSample: codec == 'FLAC' ? sampleSize : 0,
      sampleRate: rate,
    );
  }

  /// AIFF/AIFC: the COMM chunk, with the sample rate as an 80-bit float.
  static _TechnicalAudioInfo _parseAiff(Uint8List bytes) {
    if (!_tagAt(bytes, 0, 'FORM') ||
        !(_tagAt(bytes, 8, 'AIFF') || _tagAt(bytes, 8, 'AIFC'))) {
      return const _TechnicalAudioInfo();
    }
    final data = ByteData.sublistView(bytes);
    int offset = 12;
    while (offset + 8 <= bytes.length) {
      final int size = data.getUint32(offset + 4);
      final int body = offset + 8;
      if (_tagAt(bytes, offset, 'COMM') && body + 18 <= bytes.length) {
        final int channels = data.getUint16(body);
        final int frames = data.getUint32(body + 2);
        final int bits = data.getUint16(body + 6);
        final int exponent = (data.getUint16(body + 8) & 0x7fff) - 16383;
        final double sampleRate =
            data.getUint32(body + 10) * math.pow(2, exponent - 31).toDouble() +
            data.getUint32(body + 14) * math.pow(2, exponent - 63).toDouble();
        final int rate = sampleRate.round();
        return _TechnicalAudioInfo(
          codec: 'AIFF',
          channels: channels,
          bitsPerSample: bits,
          sampleRate: rate,
          bitrate: rate * channels * bits,
          duration: rate > 0 ? frames / rate : 0,
        );
      }
      offset = body + size + (size.isOdd ? 1 : 0);
    }
    return const _TechnicalAudioInfo();
  }

  /// DSF (Sony DSD stream file): fixed little-endian "fmt " chunk at 28.
  static _TechnicalAudioInfo _parseDsf(Uint8List bytes) {
    if (!_tagAt(bytes, 0, 'DSD ') ||
        !_tagAt(bytes, 28, 'fmt ') ||
        bytes.length < 72) {
      return const _TechnicalAudioInfo();
    }
    final data = ByteData.sublistView(bytes);
    final int channels = data.getUint32(52, Endian.little);
    final int rate = data.getUint32(56, Endian.little);
    final int samples = data.getUint64(64, Endian.little);
    return _TechnicalAudioInfo(
      codec: 'DSD',
      channels: channels,
      sampleRate: rate,
      bitsPerSample: 1,
      bitrate: rate * channels,
      duration: rate > 0 ? samples / rate : 0,
    );
  }

  /// DFF (DSDIFF): big-endian "FS  " and "CHNL" chunks inside PROP.
  static _TechnicalAudioInfo _parseDff(Uint8List bytes) {
    if (!_tagAt(bytes, 0, 'FRM8') || !_tagAt(bytes, 12, 'DSD ')) {
      return const _TechnicalAudioInfo();
    }
    final data = ByteData.sublistView(bytes);
    final int fs = _indexOf(bytes, 'FS  ');
    final int chnl = _indexOf(bytes, 'CHNL');
    final int rate = fs >= 0 && fs + 16 <= bytes.length
        ? data.getUint32(fs + 12)
        : 0;
    final int channels = chnl >= 0 && chnl + 14 <= bytes.length
        ? data.getUint16(chnl + 12)
        : 0;
    return _TechnicalAudioInfo(
      codec: 'DSD',
      channels: channels,
      sampleRate: rate,
      bitsPerSample: 1,
      bitrate: rate * channels,
    );
  }

  static const _wavPackRates = [
    6000, 8000, 9600, 11025, 12000, 16000, 22050, 24000, //
    32000, 44100, 48000, 64000, 88200, 96000, 192000,
  ];

  /// WavPack: the first block header's flags word.
  static _TechnicalAudioInfo _parseWavPack(Uint8List bytes) {
    if (!_tagAt(bytes, 0, 'wvpk') || bytes.length < 32) {
      return const _TechnicalAudioInfo();
    }
    final int flags = ByteData.sublistView(bytes).getUint32(24, Endian.little);
    final int rateIndex = (flags >> 23) & 0xf;
    return _TechnicalAudioInfo(
      // Hybrid mode without its correction file is lossy.
      codec: flags & 0x8 != 0 ? 'WV-LOSSY' : 'WV',
      bitsPerSample: ((flags & 0x3) + 1) * 8,
      channels: flags & 0x4 != 0 ? 1 : 2,
      sampleRate: rateIndex < _wavPackRates.length
          ? _wavPackRates[rateIndex]
          : 0,
    );
  }
}

class _TechnicalAudioInfo {
  /// Overrides the extension-based codec when the header says better
  /// (ALAC vs AAC in .m4a, DSD, ...).
  final String? codec;
  final int sampleRate;
  final int channels;
  final int bitsPerSample;
  final int bitrate;
  final double duration;

  const _TechnicalAudioInfo({
    this.codec,
    this.sampleRate = 0,
    this.channels = 0,
    this.bitsPerSample = 0,
    this.bitrate = 0,
    this.duration = 0,
  });
}
