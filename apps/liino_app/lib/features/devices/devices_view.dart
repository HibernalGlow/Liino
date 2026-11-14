import 'package:liino_app/l10n/app_localizations.dart';
import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_ui/material_ui.dart';

class DevicesView extends StatelessWidget {
  const DevicesView({super.key});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return CustomScrollView(
      slivers: [
        M3EAppBar.sliver(
          titleText: l.devicesTitle,
          variant: M3EAppBarVariant.mediumFlexible,
          pinned: true,
        ),
        SliverPadding(
          padding: const EdgeInsets.all(20),
          sliver: SliverToBoxAdapter(
            child: M3EList(
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
          ),
        ),
      ],
    );
  }
}
