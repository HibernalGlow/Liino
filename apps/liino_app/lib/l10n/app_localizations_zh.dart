// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get navDashboard => '仪表盘';

  @override
  String get navDevices => '设备';

  @override
  String get navDsp => '音频处理';

  @override
  String get devicesTitle => '设备与传输';

  @override
  String get dspTitle => '音频与 DSP';

  @override
  String get transportLanWifi => '局域网 Wi-Fi';

  @override
  String get transportUsb => 'USB 通道';

  @override
  String get transportBtRfcomm => '蓝牙 RFCOMM';

  @override
  String get segLan => '局域网';

  @override
  String get segUsb => 'USB';

  @override
  String get segBt => '蓝牙';

  @override
  String get audioLinkActive => '音频连接已建立';

  @override
  String get readyToConnect => '准备连接';

  @override
  String get labelRole => '角色';

  @override
  String get labelTransport => '传输';

  @override
  String get labelBuffer => '缓冲';

  @override
  String get syncing => '同步中…';

  @override
  String get stopLink => '停止连接';

  @override
  String get startLink => '开始连接';

  @override
  String get modeAuto => '自动';

  @override
  String get modeSender => '发送端';

  @override
  String get modeReceiver => '接收端';

  @override
  String get metricLatencyJitter => '延迟与抖动';

  @override
  String get metricStreamBitrate => '流码率';

  @override
  String get metricLatencyStream => '延迟与流状态';

  @override
  String get wordJitter => '抖动';

  @override
  String get wordLoss => '丢包';

  @override
  String get virtualMicTitle => '虚拟麦克风';

  @override
  String get virtualMicDriverFallback => '系统音频';

  @override
  String virtualMicReady(String driver) {
    return '$driver 已安装并就绪';
  }

  @override
  String virtualMicMissing(String driver) {
    return '未检测到 $driver（回退：扬声器监听）';
  }

  @override
  String get daemonActive => '守护进程 IPC 已激活';

  @override
  String get frbInProcess => 'FRB 进程内';

  @override
  String get hostLabel => '主机';

  @override
  String get unknown => '未知';

  @override
  String get inProcess => '进程内';

  @override
  String get ringLabel => '环形缓冲';

  @override
  String get detachGui => '分离界面';

  @override
  String get deviceLanTitle => '局域网 / Wi-Fi (mDNS)';

  @override
  String get deviceLanSubtitle => 'TCP 9123 · UDP 9124 · IPv4/IPv6 双栈';

  @override
  String get deviceUsbTitle => 'USB 通道 (ADB / usbmux)';

  @override
  String get deviceUsbSubtitle => '低抖动有线音频传输';

  @override
  String get deviceBtTitle => '蓝牙经典 (RFCOMM)';

  @override
  String get deviceBtSubtitle => '原生 RFCOMM 适配器（Android / 桌面端）';

  @override
  String get dspPureVox => 'PureVox6 AI 降噪';

  @override
  String get dspPureVoxSub => '按需加载的纯 Rust 推理虚拟机';

  @override
  String get dspAec => 'AEC7 回声消除';

  @override
  String get dspAecSub => '按需加载的声学回声消除器';

  @override
  String get dspAgc => '自动增益控制 (AGC)';

  @override
  String get dspAgcSub => '实时人声电平归一化';

  @override
  String get outputGain => '输出增益';
}
