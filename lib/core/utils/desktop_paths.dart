import 'dart:io';

import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;

/// Filesystem locations that differ per desktop platform.
///
/// Looper grew its desktop support on Linux first, where the user's music
/// folder comes from `xdg-user-dir MUSIC`. Windows and macOS have their own
/// conventions - and on macOS the App Sandbox rewrites `HOME`, which hides
/// the real `~/Music` - so those lookups live here instead of being inlined
/// at each call site.
///
/// Every answer is a *candidate*: a path is returned whether or not it
/// exists, because a missing music folder is normal on a fresh machine and
/// callers already filter with `Directory(...).existsSync()`.
class DesktopPaths {
  const DesktopPaths._();

  /// Mouse-and-window platforms, matching `UiUtils.isDesktop`. Repeated
  /// here rather than imported so path resolution can be unit-tested
  /// without pulling in the widget layer.
  static bool get isDesktopPlatform =>
      Platform.isLinux || Platform.isWindows || Platform.isMacOS;

  /// The default music directories for the running platform, best first.
  static Future<List<String>> defaultMusicDirectories() async {
    if (Platform.isLinux) {
      return defaultMusicDirectoriesFor(
        operatingSystem: 'linux',
        environment: Platform.environment,
        xdgMusicDirectory: await _xdgMusicDirectory(),
      );
    }
    return defaultMusicDirectoriesFor(
      operatingSystem: Platform.operatingSystem,
      environment: Platform.environment,
    );
  }

  /// Pure form of [defaultMusicDirectories], so the Windows and macOS
  /// branches stay testable from any host.
  ///
  /// Joins with the *declared* platform's context rather than the host's, so
  /// asking for the Windows answer from a macOS machine produces a real
  /// Windows path instead of a forward-slash hybrid.
  @visibleForTesting
  static List<String> defaultMusicDirectoriesFor({
    required String operatingSystem,
    required Map<String, String> environment,
    String? xdgMusicDirectory,
  }) {
    final paths = operatingSystem == 'windows' ? p.windows : p.posix;
    switch (operatingSystem) {
      case 'linux':
        final xdg = xdgMusicDirectory?.trim();
        if (xdg != null && xdg.isNotEmpty) return [xdg];
        final home = homeFromEnvironment(environment);
        return home == null ? const [] : [paths.join(home, 'Music')];

      case 'macos':
        final home = realUserHomeFrom(environment);
        if (home == null) return const [];
        return [
          paths.join(home, 'Music'),
          // Apple Music keeps imported media one level deeper, so a library
          // managed by it is invisible if only `~/Music` is scanned. It is
          // strictly a fallback: `~/Music` still recurses into it, which is
          // why it comes second rather than replacing the first entry.
          paths.join(home, 'Music', 'Music', 'Media'),
        ];

      case 'windows':
        final profile = homeFromEnvironment(environment);
        if (profile == null) return const [];
        final roots = <String>[paths.join(profile, 'Music')];
        // A redirected (OneDrive) Music library is a Known Folder that
        // lives outside the user profile entirely. Reading the Known Folder
        // API would need FFI; the environment variable covers the common
        // redirection case without it.
        final oneDrive = environment['OneDrive']?.trim();
        if (oneDrive != null && oneDrive.isNotEmpty) {
          roots.add(paths.join(oneDrive, 'Music'));
        }
        return roots;
    }
    return const [];
  }

  /// The user's home directory for a desktop platform, or null when the
  /// environment doesn't describe one.
  @visibleForTesting
  static String? homeFromEnvironment(Map<String, String> environment) {
    for (final key in const ['HOME', 'USERPROFILE']) {
      final value = environment[key]?.trim();
      if (value != null && value.isNotEmpty) return value;
    }
    final drive = environment['HOMEDRIVE']?.trim() ?? '';
    final path = environment['HOMEPATH']?.trim() ?? '';
    if (drive.isEmpty || path.isEmpty) return null;
    return '$drive$path';
  }

  /// macOS: the user's real home, undoing the App Sandbox rewrite.
  ///
  /// A sandboxed build gets `HOME=~/Library/Containers/<bundle-id>/Data`,
  /// so `HOME/Music` points at an empty folder inside the container instead
  /// of the user's library. The container path is derived from the real home
  /// by a fixed suffix, so cutting it recovers the real one; an
  /// unsandboxed run (and every non-macOS platform) passes through
  /// unchanged.
  static String? realUserHomeFrom(Map<String, String> environment) {
    final home = homeFromEnvironment(environment);
    if (home == null) return null;
    final match = RegExp(
      r'^(.+?)[/\\]Library[/\\]Containers[/\\]',
    ).firstMatch(home);
    final realHome = match?.group(1);
    if (realHome == null || realHome.isEmpty) return home;
    return realHome;
  }

  /// An example path for the "enter a folder path manually" dialog, so the
  /// hint matches the platform the dialog is running on.
  static String manualPathHint() {
    if (Platform.isWindows) return r'C:\Users\username\Music';
    if (Platform.isMacOS) return '/Users/username/Music';
    if (Platform.isLinux) return '/home/username/Music';
    return '/storage/emulated/0/Music';
  }

  /// `xdg-user-dir MUSIC` on Linux, or null when the tool is missing or
  /// answers nothing usable.
  static Future<String?> _xdgMusicDirectory() async {
    try {
      final result = await Process.run('xdg-user-dir', ['MUSIC']);
      if (result.exitCode != 0) return null;
      final value = result.stdout.toString().trim();
      return value.isEmpty ? null : value;
    } catch (_) {
      return null;
    }
  }
}

/// The prefix that matches every path *inside* [folder], or [folder] itself
/// when it already ends in a separator.
///
/// Isar's `pathStartsWith` is a plain string comparison, so the previous
/// hard-coded `'$folder/'` made every containment check miss on Windows,
/// where `p.dirname()` hands back backslash-separated paths.
String directoryPrefix(String folder) {
  if (folder.isEmpty) return folder;
  final last = folder[folder.length - 1];
  if (last == '/' || last == '\\') return folder;
  return '$folder${p.separator}';
}

/// [path] with any trailing separator removed - the shape libraryFolders
/// entries are stored and compared in.
String withoutTrailingSeparator(String path) {
  if (path.length <= 1) return path;
  final last = path[path.length - 1];
  if (last == '/' || last == '\\') return path.substring(0, path.length - 1);
  return path;
}
