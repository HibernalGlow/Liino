import 'package:looper_player/core/utils/app_links.dart';

/// Shared request settings for the community lyrics APIs (lrc.red,
/// LyricsPlus). They're free, volunteer-run services: identify the app
/// honestly so operators can reach out, and give up quickly instead of
/// stalling the fallback chain.
class LyricsHttp {
  static const Map<String, String> headers = {
    'User-Agent': 'LooperPlayer (${AppLinks.githubRepo})',
    'Accept': 'application/json, application/ttml+xml, */*',
  };

  static const Duration timeout = Duration(seconds: 6);
}
