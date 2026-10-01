import 'package:flutter/material.dart' hide RepeatMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/svg.dart';
import 'package:looper_player/core/theme/app_icons.dart';
import 'package:looper_player/core/utils/ui_utils.dart';
import 'package:looper_player/features/playback/presentation/providers/playback/playback_notifier.dart';
import 'package:looper_player/ui/android/widgets/queue_bottom_sheet.dart';

import '../../widgets/premium_section.dart';
import 'package:looper_player/core/services/haptics/app_haptics.dart';

/// Shuffle / repeat / next up / lyrics as four equal icon-only tiles styled
/// like the prev / play / next transport row: pill-rounded outer ends, 12dp
/// inner corners, 6dp gaps. Shown instead of the two pill groups when the
/// "Segmented utility buttons" theme option is on.
class SegmentedUtilityRow extends ConsumerWidget {
  const SegmentedUtilityRow({
    super.key,
    required this.height,
    required this.horizontalPadding,
    required this.useBlur,
    required this.onLyrics,
  });

  final double height;
  final double horizontalPadding;
  final bool useBlur;
  final VoidCallback onLyrics;

  static const Radius _inner = Radius.circular(12);
  static final Color _idle = Colors.white.withValues(alpha: 0.04);
  static final Color _active = Colors.white.withValues(alpha: 0.10);
  static final Color _dimIcon = Colors.white.withValues(alpha: 0.5);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Half the height keeps the outer ends true semicircles at any height.
    final Radius outer = Radius.circular(height / 2);

    Widget tile({
      String? heroTag,
      required BorderRadius borderRadius,
      required VoidCallback onTap,
      required Widget child,
      Color? backgroundColor,
    }) {
      return PremiumSection(
        heroTag: heroTag,
        borderRadius: borderRadius,
        height: height,
        showShadow: false,
        useBlur: useBlur,
        forceNoBlur: true,
        showBorder: false,
        animate: true,
        backgroundColor: backgroundColor ?? _idle,
        instantPressFeedback: true,
        onTap: onTap,
        child: child,
      );
    }

    Widget icon(String asset, Color color) => SvgPicture.asset(
      asset,
      colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
      width: AppIcons.miniPlayerIcon.s,
      height: AppIcons.miniPlayerIcon.s,
    );

    final isShuffle = ref.watch(playbackProvider.select((s) => s.isShuffle));
    final repeatMode = ref.watch(playbackProvider.select((s) => s.repeatMode));
    final bool isRepeat = repeatMode != RepeatMode.off;

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
      child: Row(
        children: [
          // Shuffle
          tile(
            heroTag: 'nav_morph_1',
            borderRadius: BorderRadius.horizontal(left: outer, right: _inner),
            backgroundColor: isShuffle ? _active : _idle,
            onTap: () {
              AppHaptics.selection();
              ref.read(playbackProvider.notifier).toggleShuffle();
            },
            child: icon(AppIcons.shuffle, isShuffle ? Colors.white : _dimIcon),
          ),
          const SizedBox(width: 6),
          // Repeat (no hero tag: the navbar only has three morph targets)
          tile(
            borderRadius: BorderRadius.circular(12),
            backgroundColor: isRepeat ? _active : _idle,
            onTap: () {
              AppHaptics.selection();
              ref.read(playbackProvider.notifier).nextRepeatMode();
            },
            child: icon(
              repeatMode == RepeatMode.off
                  ? AppIcons.repeat
                  : repeatMode == RepeatMode.one
                  ? AppIcons.repeatOne
                  : AppIcons.repeatAll,
              isRepeat ? Colors.white : _dimIcon,
            ),
          ),
          const SizedBox(width: 6),
          // Next Up
          tile(
            heroTag: 'nav_morph_2',
            borderRadius: BorderRadius.circular(12),
            onTap: () {
              AppHaptics.medium();
              showModalBottomSheet(
                context: context,
                useRootNavigator: true,
                isScrollControlled: true,
                backgroundColor: Colors.transparent,
                builder: (context) => const QueueBottomSheet(),
              );
            },
            child: icon(AppIcons.queue, Colors.white),
          ),
          const SizedBox(width: 6),
          // Lyrics
          tile(
            heroTag: 'nav_morph_3',
            borderRadius: BorderRadius.horizontal(left: _inner, right: outer),
            onTap: onLyrics,
            child: icon(AppIcons.lyrics, Colors.white),
          ),
        ],
      ),
    );
  }
}
