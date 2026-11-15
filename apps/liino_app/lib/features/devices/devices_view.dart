import 'package:liino_app/l10n/app_localizations.dart';
import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_ui/material_ui.dart';

import '../../platform/core_gateway.dart';

class DevicesView extends StatefulWidget {
  const DevicesView({
    super.key,
    required this.gateway,
    this.connectedBluetoothAddress,
    this.onBluetoothChanged,
  });

  final CoreGateway gateway;
  final String? connectedBluetoothAddress;
  final Future<void> Function()? onBluetoothChanged;

  @override
  State<DevicesView> createState() => _DevicesViewState();
}

class _DevicesViewState extends State<DevicesView> {
  List<LiinoBluetoothDevice> _devices = const [];
  bool _loading = false;
  String? _busyAddress;

  @override
  void initState() {
    super.initState();
    _loadDevices();
  }

  Future<void> _loadDevices() async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      final devices = await widget.gateway.getBluetoothDevices();
      if (!mounted) return;
      setState(() => _devices = devices);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _toggleDevice(LiinoBluetoothDevice device) async {
    if (_busyAddress != null) return;
    setState(() => _busyAddress = device.address);
    try {
      if (widget.connectedBluetoothAddress == device.address) {
        await widget.gateway.disconnectBluetooth();
      } else {
        await widget.gateway.connectBluetooth(device.address);
      }
      await widget.onBluetoothChanged?.call();
    } finally {
      if (mounted) setState(() => _busyAddress = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return CustomScrollView(
      slivers: [
        M3EAppBar.sliver(
          titleText: l.devicesTitle,
          variant: M3EAppBarVariant.small,
          pinned: true,
        ),
        SliverPadding(
          padding: const EdgeInsets.all(20),
          sliver: SliverList.list(
            children: [
              M3EList(
                variant: M3ECardVariant.outlined,
                itemCount: 3,
                itemBuilder: (context, index) {
                  return switch (index) {
                    0 => M3EListItem(
                        headline: l.deviceLanTitle,
                        supportingText: l.deviceLanSubtitle,
                        leading: const Icon(Icons.wifi_rounded),
                        trailing: const Icon(Icons.chevron_right_rounded),
                      ),
                    1 => M3EListItem(
                        headline: l.deviceUsbTitle,
                        supportingText: l.deviceUsbSubtitle,
                        leading: const Icon(Icons.usb_rounded),
                        trailing: const Icon(Icons.chevron_right_rounded),
                      ),
                    _ => M3EListItem(
                        headline: l.deviceBtTitle,
                        supportingText: l.deviceBtSubtitle,
                        leading: const Icon(Icons.bluetooth_rounded),
                        trailing: const Icon(Icons.chevron_right_rounded),
                      ),
                  };
                },
              ),
              const SizedBox(height: 16),
              M3ECard(
                variant: M3ECardVariant.outlined,
                headline: 'Bluetooth RFCOMM Devices',
                supportingText: _devices.isEmpty
                    ? 'Refresh to query paired Classic Bluetooth devices from daemon'
                    : '${_devices.length} paired device(s) available',
                actions: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    M3EButton(
                      style: M3EButtonStyle.tonal,
                      icon: const Icon(Icons.refresh_rounded),
                      onPressed: _loading ? null : _loadDevices,
                      child: Text(_loading ? 'Scanning...' : 'Refresh BT'),
                    ),
                  ],
                ),
              ),
              if (_devices.isNotEmpty) ...[
                const SizedBox(height: 12),
                M3EList(
                  variant: M3ECardVariant.outlined,
                  itemCount: _devices.length,
                  itemBuilder: (context, index) {
                    final device = _devices[index];
                    final isConnected =
                        widget.connectedBluetoothAddress == device.address;
                    final isBusy = _busyAddress == device.address;
                    return M3EListItem(
                      headline: device.name.isEmpty
                          ? device.address
                          : device.name,
                      supportingText: device.address,
                      leading: Icon(
                        isConnected
                            ? Icons.bluetooth_connected_rounded
                            : Icons.bluetooth_rounded,
                      ),
                      trailing: M3EButton(
                        style: isConnected
                            ? M3EButtonStyle.tonal
                            : M3EButtonStyle.filled,
                        onPressed: isBusy ? null : () => _toggleDevice(device),
                        child: Text(
                          isBusy
                              ? '...'
                              : isConnected
                                  ? 'Disconnect'
                                  : 'Connect',
                        ),
                      ),
                    );
                  },
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
