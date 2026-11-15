import 'package:flutter_test/flutter_test.dart';
import 'package:liino_app/main.dart';
import 'package:liino_app/platform/core_gateway.dart';

class _FakeCoreGateway implements CoreGateway {
  String _mode = 'auto';
  String _transport = 'lan_wifi';
  bool _running = false;
  String? connectedBluetooth;

  @override
  Future<GatewayStatus> getStatus({required String preferredMode}) async {
    return GatewayStatus(
      platformName: 'macos',
      roleMode: _mode,
      resolvedRole: 'receiver',
      activeTransport: _transport,
      isRunning: _running,
      viaDaemon: true,
      daemonPid: 1234,
      canCaptureAudio: true,
      canPlayAudio: true,
      canVirtualMicrophone: false,
      virtualMicDriver: 'BlackHole',
      bluetoothAddress: connectedBluetooth,
    );
  }

  @override
  Future<void> setRoleMode(String mode) async => _mode = mode;

  @override
  Future<void> setTransport(String transport) async => _transport = transport;

  @override
  Future<void> startLink() async => _running = true;

  @override
  Future<void> stopLink() async => _running = false;

  @override
  Future<List<LiinoBluetoothDevice>> getBluetoothDevices() async => const [
    LiinoBluetoothDevice(address: 'f0-2c-7b-fb-ca-9f', name: 'Xiaomi 15'),
  ];

  @override
  Future<void> connectBluetooth(String address) async {
    connectedBluetooth = address;
  }

  @override
  Future<void> disconnectBluetooth() async {
    connectedBluetooth = null;
  }
}

void main() {
  testWidgets('LiinoApp renders FlClash-style MD3E dashboard', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(LiinoApp(gateway: _FakeCoreGateway()));
    await tester.pump();
    expect(find.text('Dashboard'), findsWidgets);
    expect(find.text('Ready to Connect'), findsOneWidget);
  });

  testWidgets('DevicesView lists paired Bluetooth devices and connects', (
    WidgetTester tester,
  ) async {
    final fake = _FakeCoreGateway();
    await tester.pumpWidget(LiinoApp(gateway: fake));
    await tester.pump();

    await tester.tap(find.text('Devices').first);
    await tester.pumpAndSettle();

    expect(find.text('Xiaomi 15'), findsOneWidget);
    expect(find.text('f0-2c-7b-fb-ca-9f'), findsOneWidget);

    await tester.ensureVisible(find.text('Connect'));
    await tester.tap(find.text('Connect'));
    await tester.pumpAndSettle();
    expect(fake.connectedBluetooth, 'f0-2c-7b-fb-ca-9f');
    expect(find.text('Disconnect'), findsOneWidget);

    await tester.ensureVisible(find.text('Disconnect'));
    await tester.tap(find.text('Disconnect'));
    await tester.pumpAndSettle();
    expect(fake.connectedBluetooth, isNull);
    expect(find.text('Connect'), findsOneWidget);
  });
}
