import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_ui/material_ui.dart';

enum UiRoleMode { auto, sender, receiver }

class LiinoHomePage extends StatefulWidget {
  const LiinoHomePage({super.key});

  @override
  State<LiinoHomePage> createState() => _LiinoHomePageState();
}

class _LiinoHomePageState extends State<LiinoHomePage> {
  Set<UiRoleMode> _selectedMode = {UiRoleMode.auto};
  int _navIndex = 0;
  bool _isStreaming = false;

  @override
  Widget build(BuildContext context) {
    final m3e = M3ETheme.of(context);
    final scheme = m3e.colorScheme;

    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isDesktop = constraints.maxWidth >= 780;
          return Row(
            children: [
              if (isDesktop)
                M3ENavigationRail(
                  selectedIndex: _navIndex,
                  onDestinationSelected: (i) => setState(() => _navIndex = i),
                  sections: const [
                    M3ENavigationRailSection(
                      destinations: [
                        M3ENavigationRailDestination(
                          icon: Icon(Icons.graphic_eq_rounded),
                          label: 'Audio',
                        ),
                        M3ENavigationRailDestination(
                          icon: Icon(Icons.devices_rounded),
                          label: 'Devices',
                        ),
                        M3ENavigationRailDestination(
                          icon: Icon(Icons.tune_rounded),
                          label: 'DSP',
                        ),
                      ],
                    ),
                  ],
                ),
              Expanded(
                child: CustomScrollView(
                  slivers: [
                    M3EAppBar.sliver(
                      titleText: 'liino',
                      variant: M3EAppBarVariant.mediumFlexible,
                      pinned: true,
                      actions: [
                        Padding(
                          padding: const EdgeInsets.only(right: 16),
                          child: M3ESegmentedButton<UiRoleMode>(
                            segments: const [
                              M3ESegment(value: UiRoleMode.auto, label: 'AUTO'),
                              M3ESegment(value: UiRoleMode.sender, label: 'SENDER'),
                              M3ESegment(
                                value: UiRoleMode.receiver,
                                label: 'RECEIVER',
                              ),
                            ],
                            selected: _selectedMode,
                            onSelectionChanged: (v) {
                              if (v.isNotEmpty) {
                                setState(() => _selectedMode = v);
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                    SliverPadding(
                      padding: const EdgeInsets.all(24),
                      sliver: SliverList.list(
                        children: [
                          M3ECard(
                            variant: _isStreaming
                                ? M3ECardVariant.filled
                                : M3ECardVariant.outlined,
                            headline: _isStreaming
                                ? 'Audio Link Active'
                                : 'Ready to Connect',
                            supportingText:
                                'Mode: ${_selectedMode.first.name.toUpperCase()} · '
                                'RingBuffer: 16/64 · Transports: LAN / USB / BT',
                            actions: Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                M3EButton(
                                  style: _isStreaming
                                      ? M3EButtonStyle.tonal
                                      : M3EButtonStyle.filled,
                                  icon: Icon(
                                    _isStreaming
                                        ? Icons.stop_rounded
                                        : Icons.play_arrow_rounded,
                                  ),
                                  onPressed: () =>
                                      setState(() => _isStreaming = !_isStreaming),
                                  child: Text(
                                    _isStreaming ? 'Stop' : 'Start Link',
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                          if (_isStreaming)
                            const M3EProgressIndicator.linearWavy()
                          else
                            Divider(color: scheme.outlineVariant),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
      bottomNavigationBar: MediaQuery.sizeOf(context).width < 780
          ? M3ENavigationBar(
              selectedIndex: _navIndex,
              onDestinationSelected: (i) => setState(() => _navIndex = i),
              destinations: const [
                M3ENavigationBarDestination(
                  icon: Icon(Icons.graphic_eq_rounded),
                  label: 'Audio',
                ),
                M3ENavigationBarDestination(
                  icon: Icon(Icons.devices_rounded),
                  label: 'Devices',
                ),
                M3ENavigationBarDestination(
                  icon: Icon(Icons.tune_rounded),
                  label: 'DSP',
                ),
              ],
            )
          : null,
    );
  }
}
