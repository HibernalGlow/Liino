// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get navDashboard => 'Dashboard';

  @override
  String get navDevices => 'Devices';

  @override
  String get navDsp => 'DSP';

  @override
  String get devicesTitle => 'Devices & Transports';

  @override
  String get dspTitle => 'Audio & DSP';

  @override
  String get transportLanWifi => 'LAN Wi-Fi';

  @override
  String get transportUsb => 'USB Tunnel';

  @override
  String get transportBtRfcomm => 'BT RFCOMM';

  @override
  String get segLan => 'LAN';

  @override
  String get segUsb => 'USB';

  @override
  String get segBt => 'BT';

  @override
  String get audioLinkActive => 'Audio Link Active';

  @override
  String get readyToConnect => 'Ready to Connect';

  @override
  String get labelRole => 'Role';

  @override
  String get labelTransport => 'Transport';

  @override
  String get labelBuffer => 'Buffer';

  @override
  String get syncing => 'Syncing...';

  @override
  String get stopLink => 'Stop Link';

  @override
  String get startLink => 'Start Link';

  @override
  String get modeAuto => 'AUTO';

  @override
  String get modeSender => 'SENDER';

  @override
  String get modeReceiver => 'RECEIVER';

  @override
  String get metricLatencyJitter => 'Latency & Jitter';

  @override
  String get metricStreamBitrate => 'Stream Bitrate';

  @override
  String get metricLatencyStream => 'Latency & Stream';

  @override
  String get wordJitter => 'Jitter';

  @override
  String get wordLoss => 'Loss';

  @override
  String get virtualMicTitle => 'Virtual Microphone';

  @override
  String get virtualMicDriverFallback => 'System Audio';

  @override
  String virtualMicReady(String driver) {
    return '$driver installed & ready';
  }

  @override
  String virtualMicMissing(String driver) {
    return '$driver not detected (fallback: speaker monitor)';
  }

  @override
  String get daemonActive => 'Daemon IPC Active';

  @override
  String get frbInProcess => 'FRB In-Process';

  @override
  String get hostLabel => 'Host';

  @override
  String get unknown => 'unknown';

  @override
  String get inProcess => 'In-Process';

  @override
  String get ringLabel => 'Ring';

  @override
  String get detachGui => 'Detach GUI';

  @override
  String get deviceLanTitle => 'LAN / Wi-Fi (mDNS)';

  @override
  String get deviceLanSubtitle => 'TCP 9123 · UDP 9124 · Dual-stack IPv4/IPv6';

  @override
  String get deviceUsbTitle => 'USB Tunnel (ADB / usbmux)';

  @override
  String get deviceUsbSubtitle => 'Low-jitter wired audio transport';

  @override
  String get deviceBtTitle => 'Bluetooth Classic (RFCOMM)';

  @override
  String get deviceBtSubtitle => 'Native RFCOMM adapter (Android / Desktop)';

  @override
  String get dspPureVox => 'PureVox6 AI Noise Suppression';

  @override
  String get dspPureVoxSub => 'On-demand pure-Rust inference VM';

  @override
  String get dspAec => 'AEC7 Echo Cancellation';

  @override
  String get dspAecSub => 'On-demand acoustic echo canceller';

  @override
  String get dspAgc => 'Automatic Gain Control (AGC)';

  @override
  String get dspAgcSub => 'Real-time vocal level normalization';

  @override
  String get outputGain => 'Output Gain';
}
