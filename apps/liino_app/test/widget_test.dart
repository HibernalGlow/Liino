import 'package:flutter_test/flutter_test.dart';
import 'package:liino_app/main.dart';
import 'package:liino_app/platform/core_gateway.dart';

class _FakeCoreGateway implements CoreGateway {
  String _mode = 'auto';
  String _transport = 'lan_wifi';
  bool _running = false;

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
  Future<List<LiinoBluetoothDevice>> getBluetoothDevices() async => const [];

  @override
  Future<void> connectBluetooth(String address) async {}

  @override
  Future<void> disconnectBluetooth() async {}
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
}
