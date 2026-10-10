import 'package:looper_player/features/library/domain/models/models.dart';

/// Length assumed for a song whose duration tag is missing.
const int _fallbackDurationMs = 210000;

/// How many times [song] has been listened to all the way through, measured
/// from real listening time rather than from how often it was started: ten
/// 5-second skips of a 3-minute song come to about 0.3, three full listens
/// to 3.0.
double songFullPlays(Song song) {
  final durationMs = (song.duration ?? 0) > 0
      ? song.duration!
      : _fallbackDurationMs;
  return song.totalListenedMs / durationMs;
}

/// Orders songs by [songFullPlays], most first; ties go to the song started
/// more often, then to the more recently played one.
int compareByFullPlays(Song a, Song b) {
  final byFull = songFullPlays(b).compareTo(songFullPlays(a));
  if (byFull != 0) return byFull;
  final byPlays = b.playCount.compareTo(a.playCount);
  if (byPlays != 0) return byPlays;
  return (b.lastPlayed ?? DateTime(0)).compareTo(a.lastPlayed ?? DateTime(0));
}
