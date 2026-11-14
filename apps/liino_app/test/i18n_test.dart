import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liino_app/l10n/app_localizations.dart';
import 'package:liino_app/main.dart';

void main() {
  group('i18n', () {
    test('supports English and Chinese, English first as the fallback', () {
      expect(AppLocalizations.supportedLocales, const [
        Locale('en'),
        Locale('zh'),
      ]);
    });

    test('English strings resolve', () {
      final l = lookupAppLocalizations(const Locale('en'));
      expect(l.navDashboard, 'Dashboard');
      expect(l.readyToConnect, 'Ready to Connect');
      expect(l.virtualMicReady('System Audio'),
          'System Audio installed & ready');
    });

    test('Chinese strings resolve', () {
      final l = lookupAppLocalizations(const Locale('zh'));
      expect(l.navDashboard, '仪表盘');
      expect(l.readyToConnect, '准备连接');
      expect(l.virtualMicReady('系统音频'), '系统音频 已安装并就绪');
    });

    test('any Chinese region variant resolves to the zh translations', () {
      expect(lookupAppLocalizations(const Locale('zh', 'CN')).navDevices, '设备');
      expect(lookupAppLocalizations(const Locale('zh', 'TW')).navDevices, '设备');
      expect(lookupAppLocalizations(const Locale('zh', 'HK')).navDevices, '设备');
    });

    test('default locale resolution follows the system language', () {
      // This is the exact algorithm WidgetsApp uses when no explicit locale or
      // resolution callback is set. Chinese systems -> zh, everything else
      // (including unsupported locales) -> en.
      final supported = AppLocalizations.supportedLocales;
      expect(
        basicLocaleListResolution(const [Locale('zh', 'CN')], supported),
        const Locale('zh'),
      );
      expect(
        basicLocaleListResolution(const [Locale('zh', 'TW')], supported),
        const Locale('zh'),
      );
      expect(
        basicLocaleListResolution(const [Locale('en', 'US')], supported),
        const Locale('en'),
      );
      expect(
        basicLocaleListResolution(const [Locale('fr', 'FR')], supported),
        const Locale('en'),
      );
    });

    testWidgets('app renders Chinese when the system locale is Chinese',
        (tester) async {
      addTearDown(() {
        tester.platformDispatcher.clearLocaleTestValue();
        tester.platformDispatcher.clearLocalesTestValue();
      });
      tester.platformDispatcher.localeTestValue = const Locale('zh', 'CN');
      tester.platformDispatcher.localesTestValue = const <Locale>[
        Locale('zh', 'CN'),
      ];

      // M3EMaterialApp rebuilds its inner MaterialApp, which makes Flutter's
      // LocalizationsResolver re-run a debug-only assert. Since MaterialApp
      // always appends English-only Default*Localizations delegates, that
      // assert reports a non-fatal FlutterError for non-English locales.
      // Capture it and assert nothing else was reported; it never fires in a
      // release build.
      final reported = <FlutterErrorDetails>[];
      final previousOnError = FlutterError.onError;
      FlutterError.onError = reported.add;
      addTearDown(() => FlutterError.onError = previousOnError);

      await tester.pumpWidget(const LiinoApp());
      expect(find.text('仪表盘'), findsWidgets);
      expect(find.text('准备连接'), findsOneWidget);
      expect(
        reported.every((d) => d.exception
            .toString()
            .contains('not supported by all of its localization delegates')),
        isTrue,
        reason: 'only the known debug-only delegate warning is expected',
      );
    });
  });
}
