import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_ui/material_ui.dart';
import '../../platform/core_gateway.dart';

enum UiRoleMode { auto, sender, receiver }

enum UiTransportMode { lanWifi, usb, bluetoothRfcomm }

class DashboardView extends StatelessWidget {
  const DashboardView({
    super.key,
    required this.selectedMode,
    required this.selectedTransport,
    required this.isStreaming,
    required this.isTransitioning,
    required this.status,
    required this.onModeChanged,
    required this.onTransportChanged,
    required this.onToggleLink,
  });

  final UiRoleMode selectedMode;
  final UiTransportMode selectedTransport;
  final bool isStreaming;
  final bool isTransitioning;
  final GatewayStatus? status;
  final ValueChanged<UiRoleMode> onModeChanged;
  final ValueChanged<UiTransportMode> onTransportChanged;
  final VoidCallback onToggleLink;

  String get _transportLabel => switch (selectedTransport) {
        UiTransportMode.lanWifi => 'LAN Wi-Fi',
        UiTransportMode.usb => 'USB Tunnel',
        UiTransportMode.bluetoothRfcomm => 'BT RFCOMM',
      };

  @override
  Widget build(BuildContext context) {
    final m3e = M3ETheme.of(context);
    final emphasized = m3e.typography.emphasized;

    return CustomScrollView(
      slivers: [
        const M3EAppBar.sliver(
          titleText: 'Dashboard',
          variant: M3EAppBarVariant.mediumFlexible,
          pinned: true,
        ),
        SliverLayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.crossAxisExtent;
            final columns = width >= 860
                ? 4
                : width >= 600
                    ? 2
                    : 1;
            const gap = 14.0;
            final side = columns == 1
                ? math.max(16.0, (width - 560.0) / 2)
                : 20.0;

            return SliverPadding(
              padding: EdgeInsets.fromLTRB(side, 12, side, 28),
              sliver: SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (columns == 4)
                      _buildFourColumnGrid(context, m3e, emphasized, gap)
                    else if (columns == 2)
                      _buildTwoColumnGrid(context, m3e, emphasized, gap)
                    else
                      _buildSingleColumn(context, m3e, emphasized, gap),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildFourColumnGrid(
    BuildContext context,
    M3EThemeData m3e,
    M3ETypeScale emphasized,
    double gap,
  ) {
    return Column(
      spacing: gap,
      children: [
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: gap,
            children: [
              Expanded(
                flex: 2,
                child: RepaintBoundary(
                  child: _buildHeroCard(m3e, emphasized),
                ),
              ),
              Expanded(
                child: RepaintBoundary(
                  child: _buildMetricCard(
                    title: 'Latency & Jitter',
                    primary: '${status?.rttMs ?? 0} ms',
                    secondary:
                        'Jitter ${(status?.jitterMs ?? 0.0).toStringAsFixed(1)} ms',
                    icon: Icons.speed_rounded,
                    m3e: m3e,
                  ),
                ),
              ),
              Expanded(
                child: RepaintBoundary(
                  child: _buildMetricCard(
                    title: 'Stream Bitrate',
                    primary: '${((status?.bitrate ?? 0) / 1000).toStringAsFixed(1)} kbps',
                    secondary:
                        '${(status?.sampleRate ?? 48000) ~/ 1000} kHz · Loss ${((status?.packetLossRate ?? 0.0) * 100).toStringAsFixed(1)}%',
                    icon: Icons.graphic_eq_rounded,
                    m3e: m3e,
                  ),
                ),
              ),
            ],
          ),
        ),
        Row(
          spacing: gap,
          children: [
            Expanded(flex: 2, child: _buildRoleControlBar()),
            Expanded(flex: 2, child: _buildTransportControlBar()),
          ],
        ),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: gap,
            children: [
              Expanded(child: RepaintBoundary(child: _buildVirtualMicCard(m3e))),
              Expanded(child: RepaintBoundary(child: _buildDaemonCard(context, m3e))),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTwoColumnGrid(
    BuildContext context,
    M3EThemeData m3e,
    M3ETypeScale emphasized,
    double gap,
  ) {
    return Column(
      spacing: gap,
      children: [
        _buildHeroCard(m3e, emphasized),
        _buildRoleControlBar(),
        _buildTransportControlBar(),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: gap,
            children: [
              Expanded(
                child: _buildMetricCard(
                  title: 'Latency & Jitter',
                  primary: '${status?.rttMs ?? 0} ms',
                  secondary:
                      'Jitter ${(status?.jitterMs ?? 0.0).toStringAsFixed(1)} ms',
                  icon: Icons.speed_rounded,
                  m3e: m3e,
                ),
              ),
              Expanded(
                child: _buildMetricCard(
                  title: 'Stream Bitrate',
                  primary: '${((status?.bitrate ?? 0) / 1000).toStringAsFixed(1)} kbps',
                  secondary: '${(status?.sampleRate ?? 48000) ~/ 1000} kHz',
                  icon: Icons.graphic_eq_rounded,
                  m3e: m3e,
                ),
              ),
            ],
          ),
        ),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: gap,
            children: [
              Expanded(child: _buildVirtualMicCard(m3e)),
              Expanded(child: _buildDaemonCard(context, m3e)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSingleColumn(
    BuildContext context,
    M3EThemeData m3e,
    M3ETypeScale emphasized,
    double gap,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: gap,
      children: [
        _buildHeroCard(m3e, emphasized),
        _buildRoleControlBar(),
        _buildTransportControlBar(),
        _buildMetricCard(
          title: 'Latency & Stream',
          primary: '${status?.rttMs ?? 0} ms RTT',
          secondary:
              'Jitter ${(status?.jitterMs ?? 0.0).toStringAsFixed(1)} ms · ${(status?.sampleRate ?? 48000) ~/ 1000} kHz',
          icon: Icons.speed_rounded,
          m3e: m3e,
        ),
        _buildVirtualMicCard(m3e),
        _buildDaemonCard(context, m3e),
      ],
    );
  }

  Widget _buildHeroCard(M3EThemeData m3e, M3ETypeScale emphasized) {
    final resolved = (status?.resolvedRole ?? selectedMode.name).toUpperCase();
    return M3ECard(
      variant: isStreaming ? M3ECardVariant.filled : M3ECardVariant.outlined,
      headline: isStreaming ? 'Audio Link Active' : 'Ready to Connect',
      supportingText:
          'Role: $resolved · Transport: $_transportLabel · Buffer: ${status?.bufferDurationMs ?? 0} ms',
      actions: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (isStreaming || isTransitioning) ...[
            const M3EProgressIndicator.linearWavy(),
            const SizedBox(height: 12),
          ],
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              M3EButton(
                style: isStreaming
                    ? M3EButtonStyle.tonal
                    : M3EButtonStyle.filled,
                icon: Icon(
                  isTransitioning
                      ? Icons.sync_rounded
                      : isStreaming
                          ? Icons.stop_rounded
                          : Icons.play_arrow_rounded,
                ),
                onPressed: isTransitioning ? null : onToggleLink,
                child: Text(
                  isTransitioning
                      ? 'Syncing...'
                      : isStreaming
                          ? 'Stop Link'
                          : 'Start Link',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRoleControlBar() {
    return M3ESegmentedButton<UiRoleMode>(
      segments: [
        const M3ESegment(value: UiRoleMode.auto, label: 'AUTO'),
        M3ESegment(
          value: UiRoleMode.sender,
          label: 'SENDER',
          enabled: status?.canCaptureAudio ?? true,
        ),
        M3ESegment(
          value: UiRoleMode.receiver,
          label: 'RECEIVER',
          enabled:
              (status?.canPlayAudio ?? true) ||
              (status?.canVirtualMicrophone ?? true),
        ),
      ],
      selected: {selectedMode},
      onSelectionChanged: (v) {
        if (v.isNotEmpty) onModeChanged(v.first);
      },
    );
  }

  Widget _buildTransportControlBar() {
    return M3ESegmentedButton<UiTransportMode>(
      segments: const [
        M3ESegment(value: UiTransportMode.lanWifi, label: 'LAN'),
        M3ESegment(value: UiTransportMode.usb, label: 'USB'),
        M3ESegment(value: UiTransportMode.bluetoothRfcomm, label: 'BT'),
      ],
      selected: {selectedTransport},
      onSelectionChanged: (v) {
        if (v.isNotEmpty) onTransportChanged(v.first);
      },
    );
  }

  Widget _buildMetricCard({
    required String title,
    required String primary,
    required String secondary,
    required IconData icon,
    required M3EThemeData m3e,
  }) {
    return M3ECard(
      variant: M3ECardVariant.elevated,
      headline: title,
      supportingText: '$primary\n$secondary',
      overflow: Icon(icon, color: m3e.colorScheme.primary),
    );
  }

  Widget _buildVirtualMicCard(M3EThemeData m3e) {
    final driver = status?.virtualMicDriver ?? 'System Audio';
    final ready = status?.canVirtualMicrophone ?? false;
    return M3ECard(
      variant: M3ECardVariant.outlined,
      headline: 'Virtual Microphone',
      supportingText: ready
          ? '$driver installed & ready'
          : '$driver not detected (fallback: speaker monitor)',
      overflow: Icon(
        ready ? Icons.mic_rounded : Icons.mic_off_rounded,
        color: ready ? m3e.colorScheme.primary : m3e.colorScheme.error,
      ),
    );
  }

  Widget _buildDaemonCard(BuildContext context, M3EThemeData m3e) {
    final viaDaemon = status?.viaDaemon ?? false;
    final pidText = status?.daemonPid != null ? 'PID ${status!.daemonPid}' : 'In-Process';
    final isDesktop =
        !kIsWeb && (Platform.isMacOS || Platform.isLinux || Platform.isWindows);
    return M3ECard(
      variant: M3ECardVariant.outlined,
      headline: viaDaemon ? 'Daemon IPC Active' : 'FRB In-Process',
      supportingText:
          'Host: ${status?.platformName ?? "unknown"} ($pidText)${status?.ringBufferSummary != null ? " · Ring ${status!.ringBufferSummary}" : ""}',
      actions: isDesktop && viaDaemon
          ? Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                M3EButton(
                  style: M3EButtonStyle.text,
                  onPressed: () {
                    SystemNavigator.pop();
                  },
                  child: const Text('Detach GUI'),
                ),
              ],
            )
          : null,
    );
  }
}
