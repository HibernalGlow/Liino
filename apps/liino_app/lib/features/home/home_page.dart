import 'dart:async';

import 'package:liino_app/l10n/app_localizations.dart';
import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_ui/material_ui.dart';
import '../../platform/core_gateway.dart';
import '../dashboard/dashboard_view.dart';
import '../devices/devices_view.dart';
import '../dsp/dsp_view.dart';

class LiinoHomePage extends StatefulWidget {
  const LiinoHomePage({super.key});

  @override
  State<LiinoHomePage> createState() => _LiinoHomePageState();
}

class _LiinoHomePageState extends State<LiinoHomePage> {
  final CoreGateway _gateway = CoreGateway.platformDefault();
  UiRoleMode _selectedMode = UiRoleMode.auto;
  UiTransportMode _selectedTransport = UiTransportMode.lanWifi;
  int _navIndex = 0;
  bool _isStreaming = false;
  bool _isTransitioning = false;
  GatewayStatus? _status;

  @override
  void initState() {
    super.initState();
    _refreshFromCore();
  }

  Future<void> _refreshFromCore() async {
    try {
      final status = await _gateway.getStatus(
        preferredMode: _selectedMode.name,
      );
      if (!mounted) return;
      setState(() {
        _status = status;
        _isStreaming = status.isRunning;
        _selectedTransport = switch (status.activeTransport) {
          'usb' => UiTransportMode.usb,
          'bluetooth_rfcomm' => UiTransportMode.bluetoothRfcomm,
          _ => UiTransportMode.lanWifi,
        };
      });
    } catch (_) {
      // Fallback gracefully when native library & daemon are unavailable.
    }
  }

  /// FlClash-style 600ms display hold so fast IPC transitions do not flash.
  Future<void> _toggleLink() async {
    if (_isTransitioning) return;
    final next = !_isStreaming;
    setState(() => _isTransitioning = true);
    final hold = Future<void>.delayed(const Duration(milliseconds: 600));
    if (next) {
      await _gateway.startLink();
    } else {
      await _gateway.stopLink();
    }
    await hold;
    if (!mounted) return;
    setState(() {
      _isStreaming = next;
      _isTransitioning = false;
    });
    await _refreshFromCore();
  }

  Future<void> _onModeChanged(UiRoleMode mode) async {
    setState(() => _selectedMode = mode);
    await _gateway.setRoleMode(mode.name);
    await _refreshFromCore();
  }

  Future<void> _onTransportChanged(UiTransportMode transport) async {
    setState(() => _selectedTransport = transport);
    final wire = switch (transport) {
      UiTransportMode.lanWifi => 'lan_wifi',
      UiTransportMode.usb => 'usb',
      UiTransportMode.bluetoothRfcomm => 'bluetooth_rfcomm',
    };
    await _gateway.setTransport(wire);
    await _refreshFromCore();
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.sizeOf(context).width >= 640;
    final l = AppLocalizations.of(context);

    final body = switch (_navIndex) {
      1 => const DevicesView(),
      2 => const DspView(),
      _ => DashboardView(
          selectedMode: _selectedMode,
          selectedTransport: _selectedTransport,
          isStreaming: _isStreaming,
          isTransitioning: _isTransitioning,
          status: _status,
          onModeChanged: _onModeChanged,
          onTransportChanged: _onTransportChanged,
          onToggleLink: _toggleLink,
        ),
    };

    return Scaffold(
      body: Row(
        children: [
          if (isDesktop)
            M3ENavigationRail(
              selectedIndex: _navIndex,
              onDestinationSelected: (i) => setState(() => _navIndex = i),
              sections: [
                M3ENavigationRailSection(
                  destinations: [
                    M3ENavigationRailDestination(
                      icon: const Icon(Icons.dashboard_rounded),
                      label: l.navDashboard,
                    ),
                    M3ENavigationRailDestination(
                      icon: const Icon(Icons.devices_rounded),
                      label: l.navDevices,
                    ),
                    M3ENavigationRailDestination(
                      icon: const Icon(Icons.tune_rounded),
                      label: l.navDsp,
                    ),
                  ],
                ),
              ],
            ),
          Expanded(child: body),
        ],
      ),
      bottomNavigationBar: isDesktop
          ? null
          : M3ENavigationBar(
              selectedIndex: _navIndex,
              onDestinationSelected: (i) => setState(() => _navIndex = i),
              destinations: [
                M3ENavigationBarDestination(
                  icon: const Icon(Icons.dashboard_rounded),
                  label: l.navDashboard,
                ),
                M3ENavigationBarDestination(
                  icon: const Icon(Icons.devices_rounded),
                  label: l.navDevices,
                ),
                M3ENavigationBarDestination(
                  icon: const Icon(Icons.tune_rounded),
                  label: l.navDsp,
                ),
              ],
            ),
    );
  }
}
