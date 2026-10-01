import 'dart:io';
import 'package:flutter/material.dart';
import 'package:looper_player/core/theme/app_fonts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:looper_player/core/utils/artwork_colors.dart';
import 'package:looper_player/features/library/domain/models/models.dart'
    show AppSettings;
import '../../../providers/playback/playback_notifier.dart';
import '../../../providers/lyrics/lyrics_search_provider.dart';
import '../../../../domain/lyric_models.dart';
import '../../../screens/lyrics_view.dart';
import '../../../../../settings/presentation/providers/settings_notifier.dart';
import 'word_synced_lyric_text.dart';
part 'pulsing_instrumental_icon.dart';

/// The current artwork's raw primary color, extracted once per song.
final artworkRawColorProvider = FutureProvider<Color?>((ref) async {
  final currentSong = ref.watch(playbackProvider.select((s) => s.currentSong));
  final artPath = currentSong?.artPath;
  if (artPath == null) return null;

  final file = File(artPath);
  if (!await file.exists()) return null;

  try {
    final colors = await ArtworkColors.fromProvider(FileImage(file));
    if (colors != null) return colors.primary;
  } catch (e) {}
  return null;
});

/// The artwork color, lifted to read on a dark background (lyrics share
/// card). Separate from [artworkRawColorProvider] so it's extracted once.
final artworkColorProvider = Provider<Color?>((ref) {
  final raw = ref.watch(artworkRawColorProvider).value;
  return raw == null ? null : readableOnDark(raw);
});

/// Whether the active lyric line is plain white ("Dynamic Color Active
/// Line" off). The accent toggle and intensity slider do nothing then.
bool activeLyricsIsWhite(AppSettings settings) =>
    !settings.dynamicColorActiveLyrics;

/// The active lyric line's color, from the app [accent] (theme primary,
/// which already follows the artwork with dynamic theming):
/// - "Accent Color Active Line" on: the accent itself, made more saturated
///   by the intensity slider ([lyricsActiveColor]).
/// - off: the accent blended with white, the slider bringing back more of
///   the color ([lyricsSoftActiveColor]).
Color activeLyricsColor(AppSettings settings, {required Color accent}) {
  if (activeLyricsIsWhite(settings)) return Colors.white;
  return !settings.activeLyricsSoftColor
      ? lyricsActiveColor(accent, intensity: settings.activeLyricsIntensity)
      : lyricsSoftActiveColor(
          accent,
          intensity: settings.activeLyricsIntensity,
        );
}

class AdvancedLyricLine extends ConsumerWidget {
  final LyricLine line;
  final LyricsSyncMode mode;
  final bool isActive;
  final int relativeIndex;
  final VoidCallback onTap;
  final double fontScale;

  /// Whether this line is part of the current share-card selection, and
  /// whether a selection is in progress at all (used to dim non-selected
  /// lines so the picked lines stand out). Long-pressing starts a selection.
  final bool isSelected;
  final bool selectionActive;
  final VoidCallback onLongPress;

  const AdvancedLyricLine({
    super.key,
    required this.line,
    required this.mode,
    required this.isActive,
    required this.relativeIndex,
    required this.onTap,
    required this.onLongPress,
    this.isSelected = false,
    this.selectionActive = false,
    this.fontScale = 1.0,
  });

  /// Word/char styles only apply to lines with real word timing; anything
  /// else is shown line by line, whatever style is picked.
  bool get usesWordTiming => mode != LyricsSyncMode.line && line.hasWordTiming;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Only watch position if this line is active and in word/char sync modes, avoiding rebuilds of all other lines
    final needsPosition = isActive && usesWordTiming;
    final reportedPosition = needsPosition
        ? ref.watch(playbackProvider.select((s) => s.position))
        : Duration.zero;
    // Right after tapping a line it's active before the seek lands, so the
    // position can still be from elsewhere in the song - show it unsung
    // rather than flashing it fully sung.
    final currentPosition =
        needsPosition &&
            (reportedPosition < line.startTime ||
                reportedPosition > line.endTime + const Duration(seconds: 1))
        ? line.startTime
        : reportedPosition;
    // Word-timed lines also need it while inactive: a line that just
    // finished keeps its last word running while it settles.
    final isPlaying = usesWordTiming
        ? ref.watch(playbackProvider.select((s) => s.isPlaying))
        : false;

    final isPast = isActive
        ? false
        : (ref.read(playbackProvider).position > line.endTime);

    // Calculate absolute distance for opacity and duration
    final absIndex = relativeIndex.abs();

    // Calculate dynamic opacity based on distance from active line for a smoother transition
    double lineOpacity = 1.0;
    if (isSelected) {
      lineOpacity =
          1.0; // selected lines should read clearly regardless of playback position
    } else if (selectionActive) {
      lineOpacity =
          0.18; // dim everything else while the user is picking lines to share
    } else if (!isActive) {
      lineOpacity =
          0.35; // ponytail: make inactive lyrics lines all have uniform opacity
    }

    final settings = ref.watch(settingsProvider);
    // Duet partner lines sit on the opposite side (centered stays centered).
    final alignmentString = switch ((
      line.isOppositeSide,
      settings.lyricsAlignment,
    )) {
      (true, 'left') => 'right',
      (true, 'right') => 'left',
      (_, final alignment) => alignment,
    };
    // Glow for colored active lines, not plain white.
    final useDynamicColor = !activeLyricsIsWhite(settings);

    final textAlign = alignmentString == 'left'
        ? TextAlign.left
        : alignmentString == 'right'
        ? TextAlign.right
        : TextAlign.center;

    final iconAlignment = alignmentString == 'left'
        ? Alignment.centerLeft
        : alignmentString == 'right'
        ? Alignment.centerRight
        : Alignment.center;

    final activeColor = activeLyricsColor(
      settings,
      accent: Theme.of(context).colorScheme.primary,
    );

    // Hindi and other Indic text falls back per glyph to a bundled font that
    // matches the chosen one (see AppFonts.scriptFallbackFor).
    final baseStyle = AppFonts.getLyricsStyle(
      useNewFontLyrics: settings.useNewFontLyrics,
      family: settings.customFontFamilyLyrics,
      weightDelta: settings.customFontWeightLyricsDelta,
      activeWeightDelta: settings.activeLyricsFontWeightDelta,
      isActive: isActive,
      fontSize: 30 * fontScale, //(isActive ? 30.5 : 30) * fontScale,
      height: 1.15,
      color: isActive
          ? activeColor
          : Colors.white.withValues(alpha: lineOpacity),
      shadows: isActive && useDynamicColor
          ? [
              Shadow(
                color: activeColor.withValues(alpha: 0.3),
                blurRadius: 20,
                offset: const Offset(0, 4),
              ),
            ]
          : null,
    );

    // Unified animation duration and easeInOutCubic curve for a buttery-smooth transition
    final animDuration = const Duration(milliseconds: 400);
    final curve = Curves.easeInOutCubic;

    // Watch the search query for highlighting
    final searchQuery = ref.watch(lyricsSearchQueryProvider).toLowerCase();

    final childWidget = _buildModeContent(
      context,
      isPast,
      baseStyle,
      activeColor,
      searchQuery,
      textAlign,
      iconAlignment,
      currentPosition,
      isPlaying,
    );

    // Optimization: If the line is far from the active line (distance > 1),
    // skip expensive animation/mouse widgets and render a static layout.
    // This reduces widget tree depth by 75% and resolves slow frames.
    if (absIndex > 2) {
      return GestureDetector(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: EdgeInsets.only(top: 8 * fontScale, bottom: 8 * fontScale),
          child: _selectionHighlight(
            child: DefaultTextStyle(
              style: baseStyle,
              textAlign: textAlign,
              softWrap: true,
              child: childWidget,
            ),
          ),
        ),
      );
    }

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        onLongPress: onLongPress,
        child: AnimatedPadding(
          duration: animDuration,
          curve: curve,
          padding: EdgeInsets.only(
            top: (isActive ? 12 : 8) * fontScale,
            bottom: (isActive ? 16 : 8) * fontScale,
          ),
          child: _selectionHighlight(
            child: AnimatedDefaultTextStyle(
              duration: animDuration,
              curve: curve,
              style: baseStyle,
              softWrap: true,
              textAlign: textAlign,
              child: childWidget,
            ),
          ),
        ),
      ),
    );
  }

  /// Wraps [child] in a tinted, rounded background when this line is part
  /// of the active share-card selection.
  Widget _selectionHighlight({required Widget child}) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      padding: EdgeInsets.symmetric(
        horizontal: isSelected ? 10 * fontScale : 0,
        vertical: 2 * fontScale,
      ),
      decoration: BoxDecoration(
        color: isSelected
            ? Colors.white.withValues(alpha: 0.08)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
      ),
      child: child,
    );
  }

  Widget _buildModeContent(
    BuildContext context,
    bool isPast,
    TextStyle baseStyle,
    Color activeColor,
    String searchQuery,
    TextAlign textAlign,
    Alignment iconAlignment,
    Duration position,
    bool isPlaying,
  ) {
    final String text = line.text;
    final bool isInstrumental =
        text.isEmpty ||
        text.toLowerCase().contains('instrumental') ||
        text.toLowerCase().contains('[music]') ||
        text.trim() == '♪';

    // If there is a search match, always highlight it
    final bool isSearchMatch =
        searchQuery.isNotEmpty && text.toLowerCase().contains(searchQuery);

    // Word/char styles follow the singer's real word timing (lrc.red,
    // LyricsPlus, enhanced LRC). The word-synced text stays up across the
    // hand-off in both directions: swapping it for plain text the frame
    // the line changed dropped the lifted words, cut the glow and faded
    // through a milky accent-to-white mix. Instead lift, glow and colour
    // settle together, and plain text takes over only once it looks the
    // same.
    if (!isInstrumental && usesWordTiming) {
      return TweenAnimationBuilder<double>(
        tween: Tween(end: isActive ? 1.0 : 0.0),
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOutCubic,
        builder: (context, emphasis, _) => !isActive && emphasis <= 0
            ? _inactiveText(
                isPast,
                baseStyle,
                activeColor,
                isSearchMatch,
                textAlign,
              )
            : WordSyncedLyricText(
                wipe: mode == LyricsSyncMode.char,
                line: line,
                position: position,
                isPlaying: isPlaying,
                style: baseStyle,
                activeColor: activeColor,
                // Upcoming words wear the plain inactive-line color (and a
                // settling line ends on exactly that color).
                unsungColor: isActive
                    ? Colors.white.withValues(alpha: 0.35)
                    : (baseStyle.color ?? Colors.white.withValues(alpha: 0.85)),
                textAlign: textAlign,
                fontScale: fontScale,
                active: isActive,
                emphasis: emphasis,
              ),
      );
    }

    if (!isActive && !isPast) {
      return isInstrumental
          ? Align(
              alignment: iconAlignment,
              child: Text(
                '♫',
                style: baseStyle.copyWith(color: Colors.white24),
              ),
            )
          : _inactiveText(
              isPast,
              baseStyle,
              activeColor,
              isSearchMatch,
              textAlign,
            );
    }

    if (isPast) {
      return isInstrumental
          ? Align(
              alignment: iconAlignment,
              child: Text(
                '♫',
                style: baseStyle.copyWith(color: Colors.white10),
              ),
            )
          : _inactiveText(
              isPast,
              baseStyle,
              activeColor,
              isSearchMatch,
              textAlign,
            );
    }

    // For active line, add music symbols if it's instrumental
    final displayText = isInstrumental ? '♫' : text;

    // Line style, or an instrumental break in any style.
    return isInstrumental
        ? Align(
            alignment: iconAlignment,
            // Same "♫" glyph as the not-active/past instrumental symbol
            // above - only the animation (see _PulsingInstrumentalIcon)
            // marks this one out as the active line, not a symbol swap.
            child: _PulsingInstrumentalIcon(
              color: activeColor,
              style: baseStyle,
            ),
          )
        : Text(
            displayText,
            textAlign: textAlign,
            softWrap: true,
            overflow: TextOverflow.visible,
            style: baseStyle,
          );
  }

  /// The plain text of a line that isn't current (upcoming lines can carry
  /// a search highlight; past ones never do).
  Widget _inactiveText(
    bool isPast,
    TextStyle baseStyle,
    Color activeColor,
    bool isSearchMatch,
    TextAlign textAlign,
  ) {
    return _withBackgroundVocals(
      Text(
        line.text,
        style: !isPast && isSearchMatch
            ? baseStyle.copyWith(color: activeColor.withValues(alpha: 0.9))
            : null,
        textAlign: textAlign,
        softWrap: true,
        overflow: TextOverflow.visible,
      ),
      baseStyle,
      textAlign,
    );
  }

  /// Background vocals as a smaller, dimmer line under [main] (inactive and
  /// past lines; the active line's are animated by WordSyncedLyricText).
  Widget _withBackgroundVocals(
    Widget main,
    TextStyle baseStyle,
    TextAlign textAlign,
  ) {
    final background = line.backgroundText;
    if (background.isEmpty) return main;
    return Column(
      crossAxisAlignment: switch (textAlign) {
        TextAlign.left => CrossAxisAlignment.start,
        TextAlign.right => CrossAxisAlignment.end,
        _ => CrossAxisAlignment.center,
      },
      mainAxisSize: MainAxisSize.min,
      children: [
        main,
        SizedBox(height: 4 * fontScale),
        Text(
          background,
          textAlign: textAlign,
          softWrap: true,
          style: baseStyle.copyWith(
            fontSize: (baseStyle.fontSize ?? 30) * 0.62,
            height: 1.2,
            color: (baseStyle.color ?? Colors.white).withValues(
              alpha: (baseStyle.color?.a ?? 1) * 0.7,
            ),
          ),
        ),
      ],
    );
  }
}
