import 'dart:io';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:metadata_god/metadata_god.dart';

import 'package:looper_player/core/utils/ui_utils.dart';

import 'lyrics_formats/id3_sylt_reader.dart';
import 'lyrics_formats/id3_uslt_reader.dart';

class MetadataService {
  static const MethodChannel _broadcastChannel = MethodChannel(
    'com.looper.player/broadcast',
  );

  static Future<String?> getEmbeddedLyrics(String path) async {
    // Synced lyrics (ID3 SYLT) first: the tag readers below only return the
    // unsynced USLT copy stored next to them.
    if (path.toLowerCase().endsWith('.mp3')) {
      final synced = await Id3SyltReader.readFile(path);
      if (synced != null && synced.isNotEmpty) return synced;
    }

    if (Platform.isAndroid) {
      final native = await _getLyricsAndroid(path);
      if (native != null && native.isNotEmpty) return native;
    } else if (UiUtils.isDesktop) {
      // Linux has always read USLT through ffprobe; the same works on
      // Windows and macOS whenever ffmpeg is installed, so the desktop
      // branch is shared and the probe is simply absent-safe (a missing
      // executable throws ProcessException, which reads as "no lyrics").
      final probed = await _getLyricsViaFfprobe(path);
      if (probed != null && probed.isNotEmpty) return probed;
    }

    // Last resort, and the reason Windows/macOS are no longer lyrics-less
    // out of the box: the USLT frame is decoded straight from the tag
    // bytes, with no native reader and no external binary involved. This
    // also covers a Linux install without ffmpeg.
    if (path.toLowerCase().endsWith('.mp3')) {
      final unsynced = await Id3UsltReader.readFile(path);
      if (unsynced != null && unsynced.isNotEmpty) return unsynced;
    }

    return null;
  }

  static Future<String?> _getLyricsAndroid(String path) async {
    try {
      // See LibraryScanner._fetchNativeEmbeddedPicture's doc comment - same
      // reasoning: this runs inside enrichPendingSongs' batched Future.wait,
      // so one file that hangs the native side here would otherwise stall
      // every song batched after it, not just this one's lyrics.
      final lyrics = await _broadcastChannel
          .invokeMethod<String>('getEmbeddedLyrics', {'path': path})
          .timeout(const Duration(seconds: 6));
      return (lyrics != null && lyrics.isNotEmpty) ? lyrics : null;
    } catch (_) {
      return null;
    }
  }

  /// The `USLT`/`lyrics` tag of [path] via ffprobe, on any desktop that has
  /// ffmpeg available. Null when ffprobe is missing or found nothing.
  static Future<String?> _getLyricsViaFfprobe(String path) async {
    try {
      final result = await Process.run('ffprobe', [
        '-v',
        'quiet',
        '-print_format',
        'json',
        '-show_format',
        path,
      ]);

      if (result.exitCode == 0) {
        final data = jsonDecode(result.stdout);
        return _extractLyricsFromJson(data);
      }
    } catch (_) {}
    return null;
  }

  static String? _extractLyricsFromJson(Map<String, dynamic> data) {
    final tags = data['format']?['tags'];
    if (tags != null) {
      return _extractLyricsFromMap(Map<String, dynamic>.from(tags));
    }
    return null;
  }

  static String? _extractLyricsFromMap(Map<String, dynamic> tags) {
    // Look for common lyrics tags (case-insensitive)
    for (final key in tags.keys) {
      final lowerKey = key.toLowerCase();
      if (lowerKey == 'lyrics' ||
          lowerKey == 'unsync-lyrics' ||
          lowerKey == 'unsyncedlyrics' ||
          lowerKey == 'uslt') {
        return tags[key]?.toString();
      }
    }
    return null;
  }
}
