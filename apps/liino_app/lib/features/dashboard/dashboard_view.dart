import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:liino_app/l10n/app_localizations.dart';
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

  String _transportLabel(AppLocalizations l) => switch (selectedTransport) {
        UiTransportMode.lanWifi => l.transportLanWifi,
        UiTransportMode.usb => l.transportUsb,
        UiTransportMode.bluetoothRfcomm => l.transportBtRfcomm,
      };

  @override
  Widget build(BuildContext context) {
    final m3e = M3ETheme.of(context);
    final emphasized = m3e.typography.emphasized;
    final l = AppLocalizations.of(context);

    return CustomScrollView(
      slivers: [
        M3EAppBar.sliver(
          titleText: l.navDashboard,
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
                      _buildFourColumnGrid(context, l, m3e, emphasized, gap)
                    else if (columns == 2)
                      _buildTwoColumnGrid(context, l, m3e, emphasized, gap)
                    else
                      _buildSingleColumn(context, l, m3e, emphasized, gap),
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
    AppLocalizations l,
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
                  child: _buildHeroCard(l, m3e, emphasized),
                ),
              ),
              Expanded(
                child: RepaintBoundary(
                  child: _buildMetricCard(
                    title: l.metricLatencyJitter,
                    primary: '${status?.rttMs ?? 0} ms',
                    secondary:
                        '${l.wordJitter} ${(status?.jitterMs ?? 0.0).toStringAsFixed(1)} ms',
                    icon: Icons.speed_rounded,
                    emphasized: emphasized,
                    m3e: m3e,
                  ),
                ),
              ),
              Expanded(
                child: RepaintBoundary(
                  child: _buildMetricCard(
                    title: l.metricStreamBitrate,
                    primary: '${((status?.bitrate ?? 0) / 1000).toStringAsFixed(1)} kbps',
                    secondary:
                        '${(status?.sampleRate ?? 48000) ~/ 1000} kHz · ${l.wordLoss} '
                        '${((status?.packetLossRate ?? 0.0) * 100).toStringAsFixed(1)}%',
                    icon: Icons.graphic_eq_rounded,
                    emphasized: emphasized,
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
            Expanded(flex: 2, child: _buildRoleControlBar(l)),
            Expanded(flex: 2, child: _buildTransportControlBar(l)),
          ],
        ),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: gap,
            children: [
              Expanded(child: RepaintBoundary(child: _buildVirtualMicCard(l, m3e, emphasized))),
              Expanded(child: RepaintBoundary(child: _buildDaemonCard(context, l, m3e, emphasized))),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTwoColumnGrid(
    BuildContext context,
    AppLocalizations l,
    M3EThemeData m3e,
    M3ETypeScale emphasized,
    double gap,
  ) {
    return Column(
      spacing: gap,
      children: [
        _buildHeroCard(l, m3e, emphasized),
        _buildRoleControlBar(l),
        _buildTransportControlBar(l),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: gap,
            children: [
              Expanded(
                child: _buildMetricCard(
                  title: l.metricLatencyJitter,
                  primary: '${status?.rttMs ?? 0} ms',
                  secondary:
                      '${l.wordJitter} ${(status?.jitterMs ?? 0.0).toStringAsFixed(1)} ms',
                  icon: Icons.speed_rounded,
                  emphasized: emphasized,
                  m3e: m3e,
                ),
              ),
              Expanded(
                child: _buildMetricCard(
                  title: l.metricStreamBitrate,
                  primary: '${((status?.bitrate ?? 0) / 1000).toStringAsFixed(1)} kbps',
                  secondary: '${(status?.sampleRate ?? 48000) ~/ 1000} kHz',
                  icon: Icons.graphic_eq_rounded,
                  emphasized: emphasized,
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
              Expanded(child: _buildVirtualMicCard(l, m3e, emphasized)),
              Expanded(child: RepaintBoundary(child: _buildDaemonCard(context, l, m3e, emphasized))),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSingleColumn(
    BuildContext context,
    AppLocalizations l,
    M3EThemeData m3e,
    M3ETypeScale emphasized,
    double gap,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: gap,
      children: [
        _buildHeroCard(l, m3e, emphasized),
        _buildRoleControlBar(l),
        _buildTransportControlBar(l),
        _buildMetricCard(
          title: l.metricLatencyStream,
          primary: '${status?.rttMs ?? 0} ms RTT',
          secondary:
              '${l.wordJitter} ${(status?.jitterMs ?? 0.0).toStringAsFixed(1)} ms · ${(status?.sampleRate ?? 48000) ~/ 1000} kHz',
          icon: Icons.speed_rounded,
          emphasized: emphasized,
          m3e: m3e,
        ),
        _buildVirtualMicCard(l, m3e, emphasized),
        _buildDaemonCard(context, l, m3e, emphasized),
      ],
    );
  }

  Widget _buildHeroCard(AppLocalizations l, M3EThemeData m3e, M3ETypeScale emphasized) {
    final resolved = (status?.resolvedRole ?? selectedMode.name).toUpperCase();
    return M3ECard(
      variant: isStreaming ? M3ECardVariant.filled : M3ECardVariant.outlined,
      headline: isStreaming ? l.audioLinkActive : l.readyToConnect,
      supportingText:
          '${l.labelRole}: $resolved · ${l.labelTransport}: ${_transportLabel(l)} · ${l.labelBuffer}: ${status?.bufferDurationMs ?? 0} ms',
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
                      ? l.syncing
                      : isStreaming
                          ? l.stopLink
                          : l.startLink,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRoleControlBar(AppLocalizations l) {
    return M3ESegmentedButton<UiRoleMode>(
      segments: [
        M3ESegment(value: UiRoleMode.auto, label: l.modeAuto),
        M3ESegment(
          value: UiRoleMode.sender,
          label: l.modeSender,
          enabled: status?.canCaptureAudio ?? true,
        ),
        M3ESegment(
          value: UiRoleMode.receiver,
          label: l.modeReceiver,
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

  Widget _buildTransportControlBar(AppLocalizations l) {
    return M3ESegmentedButton<UiTransportMode>(
      segments: [
        M3ESegment(value: UiTransportMode.lanWifi, label: l.segLan),
        M3ESegment(value: UiTransportMode.usb, label: l.segUsb),
        M3ESegment(value: UiTransportMode.bluetoothRfcomm, label: l.segBt),
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
    required M3ETypeScale emphasized,
    required M3EThemeData m3e,
  }) {
    return M3ECard(
      variant: M3ECardVariant.elevated,
      headline: title,
      supportingText: '$primary\n$secondary',
      overflow: Icon(icon, color: m3e.colorScheme.primary),
    );
  }

  Widget _buildVirtualMicCard(AppLocalizations l, M3EThemeData m3e, M3ETypeScale emphasized) {
    final driver = status?.virtualMicDriver ?? l.virtualMicDriverFallback;
    final ready = status?.canVirtualMicrophone ?? false;
    return M3ECard(
      variant: M3ECardVariant.outlined,
      headline: l.virtualMicTitle,
      supportingText: ready
          ? l.virtualMicReady(driver)
          : l.virtualMicMissing(driver),
      overflow: Icon(
        ready ? Icons.mic_rounded : Icons.mic_off_rounded,
        color: ready ? m3e.colorScheme.primary : m3e.colorScheme.error,
      ),
    );
  }

  Widget _buildDaemonCard(
    BuildContext context,
    AppLocalizations l,
    M3EThemeData m3e,
    M3ETypeScale emphasized,
  ) {
    final viaDaemon = status?.viaDaemon ?? false;
    final pidText = status?.daemonPid != null ? 'PID ${status!.daemonPid}' : l.inProcess;
    final isDesktop =
        !kIsWeb && (Platform.isMacOS || Platform.isLinux || Platform.isWindows);
    final hostName = status?.platformName ?? l.unknown;
    final ring = status?.ringBufferSummary != null
        ? ' · ${l.ringLabel} ${status!.ringBufferSummary}'
        : '';
    return M3ECard(
      variant: M3ECardVariant.outlined,
      headline: viaDaemon ? l.daemonActive : l.frbInProcess,
      supportingText: '${l.hostLabel}: $hostName ($pidText)$ring',
      actions: isDesktop && viaDaemon
          ? Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                M3EButton(
                  style: M3EButtonStyle.text,
                  onPressed: () {
                    SystemNavigator.pop();
                  },
                  child: Text(l.detachGui),
                ),
              ],
            )
          : null,
    );
  }
}
