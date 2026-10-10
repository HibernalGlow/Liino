import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:looper_player/core/theme/app_fonts.dart';
import 'package:looper_player/features/settings/presentation/providers/settings_notifier.dart';
import 'package:looper_player/ui/widgets/sheets/app_bottom_sheet.dart';
import 'package:looper_player/core/utils/l10n.dart';

class _GestureTip {
  final IconData icon;
  final String title;
  final String description;

  const _GestureTip({
    required this.icon,
    required this.title,
    required this.description,
  });
}

List<_GestureTip> _lyricsGestureTips(BuildContext context) {
  final l10n = context.l10n;
  return [
    _GestureTip(
      icon: LucideIcons.pointer,
      title: l10n.gestureTapLine,
      description: l10n.gestureTapLineDesc,
    ),
    _GestureTip(
      icon: LucideIcons.hand,
      title: l10n.gestureLongPressLine,
      description: l10n.gestureLongPressLineDesc,
    ),
    _GestureTip(
      icon: LucideIcons.zoomIn,
      title: l10n.gesturePinch,
      description: l10n.gesturePinchDesc,
    ),
    _GestureTip(
      icon: LucideIcons.mousePointer2,
      title: l10n.gestureScroll,
      description: l10n.gestureScrollDesc,
    ),
    _GestureTip(
      icon: LucideIcons.chevronsDown,
      title: l10n.gestureSwipeDown,
      description: l10n.gestureSwipeDownDesc,
    ),
  ];
}

/// Options that live in the lyrics ⋮ menu sheet.
List<_GestureTip> _lyricsMenuTips(BuildContext context) {
  final l10n = context.l10n;
  return [
    _GestureTip(
      icon: LucideIcons.sparkles,
      title: l10n.findWordSyncedLyrics,
      description: l10n.tipFindWordSyncDesc,
    ),
    _GestureTip(
      icon: LucideIcons.searchCheck,
      title: l10n.findSyncedLyrics,
      description: l10n.tipFindSyncedDesc,
    ),
    _GestureTip(
      icon: LucideIcons.highlighter,
      title: l10n.lyricsHighlightStyle,
      description: l10n.tipHighlightStyleDesc,
    ),
    _GestureTip(
      icon: LucideIcons.timer,
      title: l10n.lyricsTiming,
      description: l10n.tipLyricsTimingDesc,
    ),
    _GestureTip(
      icon: LucideIcons.globe,
      title: l10n.changeLyricsProvider,
      description: l10n.tipChangeProviderDesc,
    ),
    _GestureTip(
      icon: LucideIcons.fileText,
      title: l10n.tipOwnLyrics,
      description: l10n.tipOwnLyricsDesc,
    ),
  ];
}

/// Shows the one-time "hidden gestures" tutorial for the Lyrics screen.
/// Marks it as seen immediately (before the sheet even opens) so it's never
/// re-prompted — regardless of how the sheet ends up being dismissed
/// (the "Got it" button, the scrim, or the system back gesture).
Future<void> showLyricsGesturesTutorial(BuildContext context, WidgetRef ref) {
  ref.read(settingsProvider.notifier).updateLyricsGestureTutorialSeen(true);

  return showModalBottomSheet(
    context: context,
    useRootNavigator: true,
    // Without this, showModalBottomSheet caps the sheet to ~9/16 of screen
    // height regardless of content - this tutorial's header + tips +
    // button is just tall enough to exceed that on some devices, causing a
    // small "RenderFlex overflowed... on the bottom" (visible as the
    // debug-mode overflow banner). Matches the isScrollControlled: true +
    // SingleChildScrollView pattern the other sheets here already use.
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black54,
    builder: (context) => const _LyricsGesturesTutorialSheet(),
  );
}

class _LyricsGesturesTutorialSheet extends StatelessWidget {
  const _LyricsGesturesTutorialSheet();

  @override
  Widget build(BuildContext context) {
    final accentColor = Theme.of(context).colorScheme.primary;

    return AppBottomSheetContainer(
      // AppBottomSheetContainer lays its child out with unbounded height, so
      // the scroll view needs an explicit cap to scroll on short screens.
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.75,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(LucideIcons.lightbulb, color: accentColor, size: 18),
                  const SizedBox(width: 8),
                  Text(
                    context.l10n.lyricsGestures,
                    style: AppFonts.jostStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              _TipSection(
                label: context.l10n.lyricsTipsGestures,
                tips: _lyricsGestureTips(context),
                accentColor: accentColor,
              ),
              const SizedBox(height: 10),
              _TipSection(
                label: context.l10n.lyricsTipsMenu,
                tips: _lyricsMenuTips(context),
                accentColor: accentColor,
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 42,
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: accentColor,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: Text(
                    context.l10n.gotIt,
                    style: AppFonts.jostStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A small caps label followed by a rounded card of compact tip rows.
class _TipSection extends StatelessWidget {
  final String label;
  final List<_GestureTip> tips;
  final Color accentColor;

  const _TipSection({
    required this.label,
    required this.tips,
    required this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 6),
          child: Text(
            label.toUpperCase(),
            style: AppFonts.jostStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
              color: accentColor,
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            children: [
              for (final tip in tips)
                _TipRow(tip: tip, accentColor: accentColor),
            ],
          ),
        ),
      ],
    );
  }
}

class _TipRow extends StatelessWidget {
  final _GestureTip tip;
  final Color accentColor;

  const _TipRow({required this.tip, required this.accentColor});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: accentColor.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(tip.icon, color: accentColor, size: 14),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tip.title,
                  style: AppFonts.jostStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                Text(
                  tip.description,
                  style: AppFonts.jostStyle(
                    fontSize: 11.5,
                    color: Colors.white60,
                    height: 1.25,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
