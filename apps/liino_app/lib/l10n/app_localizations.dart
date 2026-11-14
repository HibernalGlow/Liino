import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('zh'),
  ];

  /// Dashboard tab / page title
  ///
  /// In en, this message translates to:
  /// **'Dashboard'**
  String get navDashboard;

  /// Devices tab label
  ///
  /// In en, this message translates to:
  /// **'Devices'**
  String get navDevices;

  /// DSP (audio processing) tab label
  ///
  /// In en, this message translates to:
  /// **'DSP'**
  String get navDsp;

  /// App bar title of the Devices page
  ///
  /// In en, this message translates to:
  /// **'Devices & Transports'**
  String get devicesTitle;

  /// App bar title of the DSP page
  ///
  /// In en, this message translates to:
  /// **'Audio & DSP'**
  String get dspTitle;

  /// Full label of the LAN Wi-Fi transport
  ///
  /// In en, this message translates to:
  /// **'LAN Wi-Fi'**
  String get transportLanWifi;

  /// Full label of the USB transport
  ///
  /// In en, this message translates to:
  /// **'USB Tunnel'**
  String get transportUsb;

  /// Full label of the Bluetooth RFCOMM transport
  ///
  /// In en, this message translates to:
  /// **'BT RFCOMM'**
  String get transportBtRfcomm;

  /// Short transport segment label for LAN
  ///
  /// In en, this message translates to:
  /// **'LAN'**
  String get segLan;

  /// Short transport segment label for USB
  ///
  /// In en, this message translates to:
  /// **'USB'**
  String get segUsb;

  /// Short transport segment label for Bluetooth
  ///
  /// In en, this message translates to:
  /// **'BT'**
  String get segBt;

  /// Hero card headline while streaming
  ///
  /// In en, this message translates to:
  /// **'Audio Link Active'**
  String get audioLinkActive;

  /// Hero card headline while idle
  ///
  /// In en, this message translates to:
  /// **'Ready to Connect'**
  String get readyToConnect;

  /// Hero summary label for the resolved role
  ///
  /// In en, this message translates to:
  /// **'Role'**
  String get labelRole;

  /// Hero summary label for the active transport
  ///
  /// In en, this message translates to:
  /// **'Transport'**
  String get labelTransport;

  /// Hero summary label for the buffer duration
  ///
  /// In en, this message translates to:
  /// **'Buffer'**
  String get labelBuffer;

  /// Hero button label while a transition is in progress
  ///
  /// In en, this message translates to:
  /// **'Syncing...'**
  String get syncing;

  /// Hero button label to stop the audio link
  ///
  /// In en, this message translates to:
  /// **'Stop Link'**
  String get stopLink;

  /// Hero button label to start the audio link
  ///
  /// In en, this message translates to:
  /// **'Start Link'**
  String get startLink;

  /// Role mode segment: automatic
  ///
  /// In en, this message translates to:
  /// **'AUTO'**
  String get modeAuto;

  /// Role mode segment: audio sender
  ///
  /// In en, this message translates to:
  /// **'SENDER'**
  String get modeSender;

  /// Role mode segment: audio receiver
  ///
  /// In en, this message translates to:
  /// **'RECEIVER'**
  String get modeReceiver;

  /// Metric card title for latency and jitter
  ///
  /// In en, this message translates to:
  /// **'Latency & Jitter'**
  String get metricLatencyJitter;

  /// Metric card title for stream bitrate
  ///
  /// In en, this message translates to:
  /// **'Stream Bitrate'**
  String get metricStreamBitrate;

  /// Compact metric card title for latency and stream
  ///
  /// In en, this message translates to:
  /// **'Latency & Stream'**
  String get metricLatencyStream;

  /// Word 'Jitter' used inside metric secondary lines
  ///
  /// In en, this message translates to:
  /// **'Jitter'**
  String get wordJitter;

  /// Word 'Loss' (packet loss) used inside metric secondary lines
  ///
  /// In en, this message translates to:
  /// **'Loss'**
  String get wordLoss;

  /// Virtual microphone card headline
  ///
  /// In en, this message translates to:
  /// **'Virtual Microphone'**
  String get virtualMicTitle;

  /// Default virtual microphone driver name
  ///
  /// In en, this message translates to:
  /// **'System Audio'**
  String get virtualMicDriverFallback;

  /// Virtual microphone card text when the driver is available
  ///
  /// In en, this message translates to:
  /// **'{driver} installed & ready'**
  String virtualMicReady(String driver);

  /// Virtual microphone card text when the driver is absent
  ///
  /// In en, this message translates to:
  /// **'{driver} not detected (fallback: speaker monitor)'**
  String virtualMicMissing(String driver);

  /// Daemon card headline when running via daemon IPC
  ///
  /// In en, this message translates to:
  /// **'Daemon IPC Active'**
  String get daemonActive;

  /// Daemon card headline when running in-process
  ///
  /// In en, this message translates to:
  /// **'FRB In-Process'**
  String get frbInProcess;

  /// Daemon card label for the host platform
  ///
  /// In en, this message translates to:
  /// **'Host'**
  String get hostLabel;

  /// Fallback text for an unknown value
  ///
  /// In en, this message translates to:
  /// **'unknown'**
  String get unknown;

  /// Daemon card text when no daemon PID is present
  ///
  /// In en, this message translates to:
  /// **'In-Process'**
  String get inProcess;

  /// Daemon card label for the ring buffer summary
  ///
  /// In en, this message translates to:
  /// **'Ring'**
  String get ringLabel;

  /// Daemon card button label to detach the GUI
  ///
  /// In en, this message translates to:
  /// **'Detach GUI'**
  String get detachGui;

  /// Devices list: LAN / Wi-Fi entry title
  ///
  /// In en, this message translates to:
  /// **'LAN / Wi-Fi (mDNS)'**
  String get deviceLanTitle;

  /// Devices list: LAN / Wi-Fi entry subtitle
  ///
  /// In en, this message translates to:
  /// **'TCP 9123 · UDP 9124 · Dual-stack IPv4/IPv6'**
  String get deviceLanSubtitle;

  /// Devices list: USB tunnel entry title
  ///
  /// In en, this message translates to:
  /// **'USB Tunnel (ADB / usbmux)'**
  String get deviceUsbTitle;

  /// Devices list: USB tunnel entry subtitle
  ///
  /// In en, this message translates to:
  /// **'Low-jitter wired audio transport'**
  String get deviceUsbSubtitle;

  /// Devices list: Bluetooth entry title
  ///
  /// In en, this message translates to:
  /// **'Bluetooth Classic (RFCOMM)'**
  String get deviceBtTitle;

  /// Devices list: Bluetooth entry subtitle
  ///
  /// In en, this message translates to:
  /// **'Native RFCOMM adapter (Android / Desktop)'**
  String get deviceBtSubtitle;

  /// DSP list: PureVox noise suppression entry title
  ///
  /// In en, this message translates to:
  /// **'PureVox6 AI Noise Suppression'**
  String get dspPureVox;

  /// DSP list: PureVox noise suppression entry subtitle
  ///
  /// In en, this message translates to:
  /// **'On-demand pure-Rust inference VM'**
  String get dspPureVoxSub;

  /// DSP list: echo cancellation entry title
  ///
  /// In en, this message translates to:
  /// **'AEC7 Echo Cancellation'**
  String get dspAec;

  /// DSP list: echo cancellation entry subtitle
  ///
  /// In en, this message translates to:
  /// **'On-demand acoustic echo canceller'**
  String get dspAecSub;

  /// DSP list: automatic gain control entry title
  ///
  /// In en, this message translates to:
  /// **'Automatic Gain Control (AGC)'**
  String get dspAgc;

  /// DSP list: automatic gain control entry subtitle
  ///
  /// In en, this message translates to:
  /// **'Real-time vocal level normalization'**
  String get dspAgcSub;

  /// DSP output gain card headline
  ///
  /// In en, this message translates to:
  /// **'Output Gain'**
  String get outputGain;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'zh'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'zh':
      return AppLocalizationsZh();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
