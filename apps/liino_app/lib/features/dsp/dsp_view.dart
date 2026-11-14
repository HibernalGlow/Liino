import 'package:liino_app/l10n/app_localizations.dart';
import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_ui/material_ui.dart';

class DspView extends StatefulWidget {
  const DspView({super.key});

  @override
  State<DspView> createState() => _DspViewState();
}

class _DspViewState extends State<DspView> {
  bool _pureVoxEnabled = false;
  bool _aecEnabled = false;
  bool _agcEnabled = true;
  double _gain = 0.5;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return CustomScrollView(
      slivers: [
        M3EAppBar.sliver(
          titleText: l.dspTitle,
          variant: M3EAppBarVariant.mediumFlexible,
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
                        headline: l.dspPureVox,
                        supportingText: l.dspPureVoxSub,
                        leading: const Icon(Icons.auto_fix_high_rounded),
                        trailing: M3ESwitch(
                          value: _pureVoxEnabled,
                          onChanged: (v) => setState(() => _pureVoxEnabled = v),
                        ),
                      ),
                    1 => M3EListItem(
                        headline: l.dspAec,
                        supportingText: l.dspAecSub,
                        leading: const Icon(Icons.hearing_rounded),
                        trailing: M3ESwitch(
                          value: _aecEnabled,
                          onChanged: (v) => setState(() => _aecEnabled = v),
                        ),
                      ),
                    _ => M3EListItem(
                        headline: l.dspAgc,
                        supportingText: l.dspAgcSub,
                        leading: const Icon(Icons.equalizer_rounded),
                        trailing: M3ESwitch(
                          value: _agcEnabled,
                          onChanged: (v) => setState(() => _agcEnabled = v),
                        ),
                      ),
                  };
                },
              ),
              const SizedBox(height: 16),
              M3ECard(
                variant: M3ECardVariant.outlined,
                headline: l.outputGain,
                supportingText: '${(_gain * 200).round()}%',
                actions: M3ESlider(
                  value: _gain,
                  onChanged: (v) => setState(() => _gain = v),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
