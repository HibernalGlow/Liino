import 'package:flutter/material.dart';
import '../design_system/tokens.dart';

enum UiRoleMode { auto, sender, receiver }

class LiinoHomePage extends StatefulWidget {
  const LiinoHomePage({super.key});

  @override
  State<LiinoHomePage> createState() => _LiinoHomePageState();
}

class _LiinoHomePageState extends State<LiinoHomePage>
    with SingleTickerProviderStateMixin {
  UiRoleMode _selectedMode = UiRoleMode.auto;
  bool _isStreaming = false;
  late final AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  void _toggleStream() {
    setState(() {
      _isStreaming = !_isStreaming;
      if (_isStreaming) {
        _pulseController.repeat(reverse: true);
      } else {
        _pulseController.stop();
        _pulseController.reset();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isDesktop = constraints.maxWidth >= 780;
            return Row(
              children: [
                if (isDesktop)
                  NavigationRail(
                    backgroundColor: scheme.surfaceContainerLowest,
                    selectedIndex: 0,
                    onDestinationSelected: (_) {},
                    labelType: NavigationRailLabelType.all,
                    destinations: const [
                      NavigationRailDestination(
                        icon: Icon(Icons.graphic_eq_rounded),
                        label: Text('Audio'),
                      ),
                      NavigationRailDestination(
                        icon: Icon(Icons.devices_rounded),
                        label: Text('Devices'),
                      ),
                      NavigationRailDestination(
                        icon: Icon(Icons.tune_rounded),
                        label: Text('DSP'),
                      ),
                    ],
                  ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('liino', style: textTheme.displaySmall),
                                const SizedBox(height: 4),
                                Text(
                                  'Unified Bidirectional Audio Core',
                                  style: textTheme.bodyMedium,
                                ),
                              ],
                            ),
                            _buildRoleSelector(scheme),
                          ],
                        ),
                        const SizedBox(height: 24),
                        _buildHeroStatusCard(scheme, textTheme),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildRoleSelector(ColorScheme scheme) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(LiinoDesignTokens.radiusFull),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: UiRoleMode.values.map((mode) {
          final selected = _selectedMode == mode;
          return GestureDetector(
            onTap: () => setState(() => _selectedMode = mode),
            child: AnimatedContainer(
              duration: LiinoDesignTokens.motionQuick,
              curve: LiinoDesignTokens.springCurve,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: selected ? scheme.primaryContainer : Colors.transparent,
                borderRadius: BorderRadius.circular(LiinoDesignTokens.radiusFull),
              ),
              child: Text(
                mode.name.toUpperCase(),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: selected
                      ? scheme.onPrimaryContainer
                      : scheme.onSurfaceVariant,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildHeroStatusCard(ColorScheme scheme, TextTheme textTheme) {
    return AnimatedContainer(
      duration: LiinoDesignTokens.motionEmphasized,
      curve: LiinoDesignTokens.springCurve,
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: _isStreaming
            ? scheme.primaryContainer
            : scheme.surfaceContainerLow,
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(LiinoDesignTokens.radiusExtraLarge),
          topRight: const Radius.circular(LiinoDesignTokens.radiusMedium),
          bottomLeft: const Radius.circular(LiinoDesignTokens.radiusMedium),
          bottomRight: const Radius.circular(LiinoDesignTokens.radiusExtraLarge),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _isStreaming ? 'Audio Link Active' : 'Ready to Connect',
                  style: textTheme.headlineSmall?.copyWith(
                    color: _isStreaming
                        ? scheme.onPrimaryContainer
                        : scheme.onSurface,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Mode: ${_selectedMode.name.toUpperCase()} · RingBuffer: 16/64 · Transports: LAN / USB / BT',
                  style: textTheme.bodyMedium,
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          FilledButton.icon(
            onPressed: _toggleStream,
            icon: Icon(_isStreaming ? Icons.stop_rounded : Icons.play_arrow_rounded),
            label: Text(_isStreaming ? 'Stop' : 'Start Link'),
          ),
        ],
      ),
    );
  }
}
