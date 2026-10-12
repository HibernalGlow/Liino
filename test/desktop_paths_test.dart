import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:looper_player/core/utils/desktop_paths.dart';
import 'package:path/path.dart' as p;

void main() {
  group('DesktopPaths.defaultMusicDirectoriesFor', () {
    test('linux prefers the xdg music directory', () {
      expect(
        DesktopPaths.defaultMusicDirectoriesFor(
          operatingSystem: 'linux',
          environment: const {'HOME': '/home/looper'},
          xdgMusicDirectory: '/mnt/media/Tunes',
        ),
        ['/mnt/media/Tunes'],
      );
    });

    test('linux falls back to HOME/Music without xdg-user-dir', () {
      expect(
        DesktopPaths.defaultMusicDirectoriesFor(
          operatingSystem: 'linux',
          environment: const {'HOME': '/home/looper'},
        ),
        [p.posix.join('/home/looper', 'Music')],
      );
    });

    test('linux treats a blank xdg answer as no answer', () {
      expect(
        DesktopPaths.defaultMusicDirectoriesFor(
          operatingSystem: 'linux',
          environment: const {'HOME': '/home/looper'},
          xdgMusicDirectory: '   ',
        ),
        [p.posix.join('/home/looper', 'Music')],
      );
    });

    test('macos unwraps the sandbox container before resolving ~/Music', () {
      final directories = DesktopPaths.defaultMusicDirectoriesFor(
        operatingSystem: 'macos',
        environment: const {
          'HOME':
              '/Users/looper/Library/Containers/com.looper.looperPlayer/Data',
        },
      );

      expect(directories.first, p.posix.join('/Users/looper', 'Music'));
      expect(
        directories,
        contains(p.posix.join('/Users/looper', 'Music', 'Music', 'Media')),
      );
    });

    test('macos leaves an unsandboxed home alone', () {
      final directories = DesktopPaths.defaultMusicDirectoriesFor(
        operatingSystem: 'macos',
        environment: const {'HOME': '/Users/looper'},
      );

      expect(directories.first, p.posix.join('/Users/looper', 'Music'));
    });

    test('windows returns the profile Music and a redirected OneDrive one', () {
      final directories = DesktopPaths.defaultMusicDirectoriesFor(
        operatingSystem: 'windows',
        environment: const {
          'USERPROFILE': r'C:\Users\looper',
          'OneDrive': r'C:\Users\looper\OneDrive',
        },
      );

      expect(directories, [
        r'C:\Users\looper\Music',
        r'C:\Users\looper\OneDrive\Music',
      ]);
    });

    test('windows still finds Music with no OneDrive redirection', () {
      expect(
        DesktopPaths.defaultMusicDirectoriesFor(
          operatingSystem: 'windows',
          environment: const {'USERPROFILE': r'C:\Users\looper'},
        ),
        [r'C:\Users\looper\Music'],
      );
    });

    test('windows falls back to HOMEDRIVE + HOMEPATH', () {
      expect(
        DesktopPaths.defaultMusicDirectoriesFor(
          operatingSystem: 'windows',
          environment: const {'HOMEDRIVE': 'D:', 'HOMEPATH': r'\Users\looper'},
        ),
        [r'D:\Users\looper\Music'],
      );
    });

    test('never answers with a path it cannot derive', () {
      for (final os in ['linux', 'macos', 'windows', 'android', 'ios']) {
        expect(
          DesktopPaths.defaultMusicDirectoriesFor(
            operatingSystem: os,
            environment: const {},
          ),
          isEmpty,
          reason: os,
        );
      }
    });

    test('an unknown platform answers nothing rather than a guess', () {
      expect(
        DesktopPaths.defaultMusicDirectoriesFor(
          operatingSystem: 'fuchsia',
          environment: const {'HOME': '/home/looper'},
        ),
        isEmpty,
      );
    });
  });

  group('DesktopPaths.homeFromEnvironment', () {
    test('HOME wins over USERPROFILE', () {
      expect(
        DesktopPaths.homeFromEnvironment(const {
          'HOME': '/home/looper',
          'USERPROFILE': r'C:\Users\looper',
        }),
        '/home/looper',
      );
    });

    test('ignores empty values', () {
      expect(
        DesktopPaths.homeFromEnvironment(const {
          'HOME': '  ',
          'USERPROFILE': '',
        }),
        isNull,
      );
    });
  });

  group('directoryPrefix', () {
    test('appends the platform separator when missing', () {
      expect(
        directoryPrefix('${p.separator}music'),
        '${p.separator}music${p.separator}',
      );
    });

    test('leaves an existing separator alone', () {
      expect(
        directoryPrefix('${p.separator}music${p.separator}'),
        '${p.separator}music${p.separator}',
      );
    });

    test(
      'accepts either separator so a Windows path is not double-appended',
      () {
        expect(
          directoryPrefix(r'C:\Users\looper\Music\'),
          r'C:\Users\looper\Music\',
        );
        expect(directoryPrefix('/home/looper/Music/'), '/home/looper/Music/');
      },
    );

    test('is empty-safe', () {
      expect(directoryPrefix(''), '');
    });

    test('matches only real children, not sibling names sharing a prefix', () {
      final prefix = directoryPrefix('${p.separator}Music');
      expect(
        '${p.separator}Music${p.separator}song.mp3'.startsWith(prefix),
        isTrue,
      );
      expect(
        '${p.separator}MusicVideos${p.separator}song.mp3'.startsWith(prefix),
        isFalse,
      );
    });
  });

  group('withoutTrailingSeparator', () {
    test('strips one trailing separator', () {
      expect(
        withoutTrailingSeparator('/home/looper/Music/'),
        '/home/looper/Music',
      );
    });

    test('leaves a rooted path alone', () {
      expect(withoutTrailingSeparator('/'), '/');
    });

    test('leaves a path with no separator alone', () {
      expect(
        withoutTrailingSeparator('/home/looper/Music'),
        '/home/looper/Music',
      );
    });
  });

  group('DesktopPaths.manualPathHint', () {
    test('describes the platform it is running on', () {
      final hint = DesktopPaths.manualPathHint();
      if (Platform.isWindows) {
        expect(hint, r'C:\Users\username\Music');
      } else if (Platform.isMacOS) {
        expect(hint, '/Users/username/Music');
      } else if (Platform.isLinux) {
        expect(hint, '/home/username/Music');
      } else {
        expect(hint, '/storage/emulated/0/Music');
      }
    });
  });

  group('DesktopPaths.isDesktopPlatform', () {
    test('is true on the host running this suite', () {
      // The whole desktop port is verified on a desktop, so a false here
      // means the test environment itself is the surprise.
      expect(DesktopPaths.isDesktopPlatform, isTrue);
    });
  });
}
