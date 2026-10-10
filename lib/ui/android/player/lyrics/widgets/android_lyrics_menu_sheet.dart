import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:looper_player/core/theme/app_fonts.dart';
import 'package:looper_player/features/library/domain/models/models.dart';
import 'package:looper_player/features/playback/data/lyrics_fetcher.dart';
import 'package:looper_player/features/playback/data/lyrics_providers/lyrics_provider_info.dart';
import 'package:looper_player/features/playback/presentation/providers/lyrics/lyrics_notifier.dart';
import 'package:looper_player/features/playback/presentation/widgets/lyrics/desktop_lyrics_toolbar.dart';
import 'package:looper_player/features/playback/presentation/widgets/lyrics/lyrics_scale.dart';
import 'package:looper_player/features/settings/presentation/providers/settings_notifier.dart';
import 'package:looper_player/l10n/app_localizations.dart';
import 'package:looper_player/ui/widgets/sheets/app_bottom_sheet.dart';
import 'package:looper_player/ui/widgets/common/optimized_image.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'lyrics_gestures_tutorial_sheet.dart';
import 'package:looper_player/core/services/haptics/app_haptics.dart';
import 'package:looper_player/core/services/haptics/haptic_snack_bar.dart';

void showLyricsMenuBottomSheet(BuildContext context, WidgetRef ref, Song song) {
  showModalBottomSheet(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    backgroundColor: Colors.black12,
    builder: (context) {
      return _LyricsMenuSheetContent(song: song);
    },
  );
}

/// The same menu for mouse-and-window platforms: a centred dialog instead
/// of a bottom sheet, without the touch-only entries.
void showLyricsMenuDialog(BuildContext context, WidgetRef ref, Song song) {
  showDialog<void>(
    context: context,
    useRootNavigator: true,
    builder: (context) => Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(30),
          child: _LyricsMenuSheetContent(song: song, desktop: true),
        ),
      ),
    ),
  );
}

class _LyricsMenuSheetContent extends ConsumerWidget {
  final Song song;

  /// Shown in a dialog on desktop: no drag handle, no touch-gesture tips.
  final bool desktop;

  const _LyricsMenuSheetContent({required this.song, this.desktop = false});

  String _formatSourceLabel(AppLocalizations l10n, String? source) {
    if (source == null || source.isEmpty) return l10n.noLyricsSource;
    final name = switch (source.toLowerCase()) {
      'embedded' => l10n.lyricsSourceEmbedded,
      'local' => l10n.lyricsSourceLocalSidecar,
      'custom_file' => l10n.lyricsSourceCustomFile,
      'lrc.red' => 'lrc.red',
      'lyricsplus' => 'LyricsPlus',
      'lrclib' => 'LRCLIB',
      'genius' => 'Genius',
      'musixmatch' => 'Musixmatch',
      'azlyrics' => 'AZLyrics',
      'lyricsmint' => 'LyricsMINT',
      'lyricfind' => 'LyricFind',
      'not_found' => l10n.lyricsSourceNotFoundOnline,
      _ => source.toUpperCase(),
    };
    return l10n.lyricsSourceLabel(name);
  }

  String _formatDuration(int durationMs) {
    final duration = Duration(milliseconds: durationMs);
    final minutes = duration.inMinutes.toString().padLeft(2, '0');
    final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final settings = ref.watch(settingsProvider);
    final lyricsState = ref.watch(lyricsProvider);
    final currentAccent = settings.accentColor;
    final isWordSynced = lyricsState.parsedLines.any((l) => l.hasWordTiming);
    final isSynced = lyricsState.isSynced;
    final syncStyle = switch (settings.lyricsSyncStyle) {
      'line' || 'word' => settings.lyricsSyncStyle,
      _ => 'char',
    };

    // The services in the user's order; one that is switched off for
    // automatic lookups can still be picked here for this song.
    final availableProviders = [
      'Local',
      for (final id in LyricsFetcher.providerOrder(settings))
        LyricsProviderInfo.of(id)?.label ?? id,
    ];

    final accent = Color(currentAccent);
    final hasLyrics = lyricsState.parsedLines.isNotEmpty;
    final lyricsScale = LyricsScale.normalize(settings.lyricsFontScale);

    return AppBottomSheetContainer(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      showDragHandle: !desktop,
      // The sheet shell lays its child out with unbounded height, so the
      // scroll view needs an explicit cap to actually scroll.
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.75,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header: artwork, song info, close
              Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: OptimizedImage(
                      imagePath: song.artPath,
                      width: 44,
                      height: 44,
                      fit: BoxFit.cover,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          song.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppFonts.jostStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${song.artist ?? l10n.unknownArtist} • ${_formatDuration(song.duration ?? 0)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppFonts.jostStyle(
                            color: Colors.white54,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(
                      LucideIcons.x,
                      color: Colors.white54,
                      size: 20,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 8),

              // Lyrics source badge + whether the lyrics carry word timing
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: accent.withValues(alpha: 0.3),
                        width: 1,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(LucideIcons.disc, size: 13, color: accent),
                        const SizedBox(width: 6),
                        Text(
                          _formatSourceLabel(l10n, lyricsState.source),
                          style: AppFonts.jostStyle(
                            color: accent,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (hasLyrics)
                    _SyncBadge(
                      wordSynced: isWordSynced,
                      synced: isSynced,
                      accent: accent,
                    ),
                ],
              ),

              const SizedBox(height: 12),

              // Section 1: how the lyrics are synced - highlight style (or a
              // way to get word timing) and the timing offset.
              _MenuSection(
                children: [
                  if (isWordSynced)
                    // Only offered when the lyrics have word timing -
                    // otherwise it's line by line.
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _SectionLabel(l10n.lyricsHighlightStyle),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              for (final (value, label) in [
                                ('line', l10n.lyricsStyleLine),
                                ('word', l10n.lyricsStyleWord),
                                ('char', l10n.lyricsStyleCharacter),
                              ])
                                _MenuChip(
                                  label: label,
                                  selected: syncStyle == value,
                                  accent: accent,
                                  onSelected: () {
                                    AppHaptics.selection();
                                    ref
                                        .read(settingsProvider.notifier)
                                        .updateLyricsSyncStyle(value);
                                  },
                                ),
                            ],
                          ),
                        ],
                      ),
                    )
                  else if (hasLyrics && !isSynced)
                    // No timestamps at all: any synced lyrics would do.
                    _MenuActionTile(
                      icon: LucideIcons.searchCheck,
                      iconColor: accent,
                      title: l10n.findSyncedLyrics,
                      onTap: () async {
                        AppHaptics.medium();
                        final messenger = ScaffoldMessenger.of(context);
                        Navigator.pop(context);
                        messenger.showSnackBar(
                          SnackBar(
                            content: Text(l10n.searchingSyncedLyrics),
                            duration: const Duration(seconds: 2),
                          ),
                        );
                        final found = await ref
                            .read(lyricsProvider.notifier)
                            .findSynced(song);
                        messenger.showHapticSnackBar(
                          found ? AppHaptics.success : AppHaptics.error,
                          SnackBar(
                            content: Text(
                              found
                                  ? l10n.syncedLyricsLoaded
                                  : l10n.noSyncedLyricsFound,
                            ),
                          ),
                        );
                      },
                    )
                  else
                    _MenuActionTile(
                      icon: LucideIcons.sparkles,
                      iconColor: accent,
                      title: l10n.findWordSyncedLyrics,
                      onTap: () async {
                        AppHaptics.medium();
                        // See the provider chips below for why the messenger
                        // is captured before popping.
                        final messenger = ScaffoldMessenger.of(context);
                        Navigator.pop(context);
                        messenger.showSnackBar(
                          SnackBar(
                            content: Text(l10n.searchingWordSyncedLyrics),
                            duration: const Duration(seconds: 2),
                          ),
                        );
                        final found = await ref
                            .read(lyricsProvider.notifier)
                            .findWordSynced(song);
                        messenger.showHapticSnackBar(
                          found ? AppHaptics.success : AppHaptics.error,
                          SnackBar(
                            content: Text(
                              found
                                  ? l10n.wordSyncedLyricsLoaded
                                  : l10n.noWordSyncedLyricsFound,
                            ),
                          ),
                        );
                      },
                    ),
                  // Nothing to shift without timestamps.
                  if (hasLyrics && isSynced)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 10, 8, 2),
                      child: _LyricsOffsetControl(
                        offsetMs: lyricsState.songId == song.id
                            ? lyricsState.songOffsetMs
                            : lyricsShiftMs(song.lyricsOffsetMs),
                        accent: accent,
                        onChanged: (ms) => ref
                            .read(lyricsProvider.notifier)
                            .updateSongOffsetMs(song, ms),
                      ),
                    ),
                ],
              ),

              const SizedBox(height: 8),

              // Section 2: where the lyrics come from - provider for this
              // song, and whether to fall back through the others.
              _MenuSection(
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 10, bottom: 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: _SectionLabel(l10n.changeLyricsProvider),
                        ),
                        const SizedBox(height: 6),
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: availableProviders.map((provider) {
                              final isLocalSource =
                                  lyricsState.source == 'embedded' ||
                                  lyricsState.source == 'local';
                              final isSelected =
                                  (provider.toLowerCase() == 'local' &&
                                      isLocalSource) ||
                                  (lyricsState.source?.toLowerCase() ==
                                      provider.toLowerCase());
                              return Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: _MenuChip(
                                  label: provider == 'Local'
                                      ? l10n.lyricsProviderLocal
                                      : provider,
                                  selected: isSelected,
                                  accent: accent,
                                  onSelected: () async {
                                    if (isSelected) return;
                                    AppHaptics.medium();
                                    // Captured BEFORE popping: context belongs
                                    // to this bottom sheet, which Navigator.pop
                                    // starts tearing down immediately below.
                                    // Calling ScaffoldMessenger.of(context)
                                    // with that same context afterwards is
                                    // unreliable (it's the "loading" snackbar
                                    // showing nothing sometimes), and a later
                                    // `if (context.mounted)` guard is always
                                    // false after a real pop - it's the sheet's
                                    // own context, permanently unmounted the
                                    // instant it closes - so the result
                                    // snackbar could never fire. The messenger
                                    // itself belongs to the screen behind the
                                    // sheet, so it stays valid regardless.
                                    final messenger = ScaffoldMessenger.of(
                                      context,
                                    );
                                    Navigator.pop(context);
                                    // "Fetching..." only when it's really
                                    // a download: the song's own files and
                                    // saved provider copies load instantly.
                                    if (provider != 'Local' &&
                                        !await LyricsFetcher.hasAnswer(
                                          song,
                                          provider,
                                        )) {
                                      messenger.showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            l10n.fetchingLyricsFrom(provider),
                                          ),
                                          duration: const Duration(seconds: 2),
                                        ),
                                      );
                                    }
                                    // With auto-fallback the lyrics may
                                    // come from a later source than the
                                    // one picked - name the real one.
                                    final source = await ref
                                        .read(lyricsProvider.notifier)
                                        .fetchWithProvider(song, provider);
                                    final String resultMsg;
                                    if (source == null) {
                                      resultMsg = provider == 'Local'
                                          ? l10n.noLocalLyricsFound
                                          : l10n.noLyricsFoundOn(provider);
                                    } else if (source == 'embedded' ||
                                        source == 'local') {
                                      resultMsg = l10n.loadedLocalLyrics;
                                    } else {
                                      resultMsg = l10n.lyricsUpdatedFrom(
                                        availableProviders.firstWhere(
                                          (p) => p.toLowerCase() == source,
                                          orElse: () => source,
                                        ),
                                      );
                                    }
                                    messenger.showHapticSnackBar(
                                      source == null
                                          ? AppHaptics.error
                                          : AppHaptics.success,
                                      SnackBar(content: Text(resultMsg)),
                                    );
                                  },
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                      ],
                    ),
                  ),
                  _MenuSwitchTile(
                    icon: LucideIcons.layers,
                    title: l10n.autoFallbackProviders,
                    subtitle: l10n.autoFallbackProvidersDesc,
                    value: settings.autoLyricsFallback,
                    accent: accent,
                    onChanged: (val) => ref
                        .read(settingsProvider.notifier)
                        .updateAutoLyricsFallback(val),
                  ),
                ],
              ),

              const SizedBox(height: 8),

              // Section 3: look & feel of the lyrics screen
              _MenuSection(
                children: [
                  // Only the Android lyrics screen has an ambient background.
                  if (!desktop)
                    _MenuSwitchTile(
                      icon: LucideIcons.palette,
                      title: l10n.ambientColorBackground,
                      subtitle: l10n.ambientColorBackgroundDesc,
                      value: settings.ambientColorBackground,
                      accent: accent,
                      onChanged: (val) => ref
                          .read(settingsProvider.notifier)
                          .updateAmbientColorBackground(val),
                    ),
                  if (desktop)
                    ListTile(
                      contentPadding: const EdgeInsets.only(
                        left: 16,
                        right: 10,
                      ),
                      dense: true,
                      visualDensity: VisualDensity.compact,
                      leading: const _MenuIcon(LucideIcons.type),
                      title: Text(
                        l10n.lyricsSize,
                        style: AppFonts.jostStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w500,
                          fontSize: 15,
                        ),
                      ),
                      trailing: LyricsSizeControl(
                        scale: lyricsScale,
                        onSmaller: () => ref
                            .read(settingsProvider.notifier)
                            .updateLyricsFontScale(
                              LyricsScale.stepBy(lyricsScale, -1),
                            ),
                        onLarger: () => ref
                            .read(settingsProvider.notifier)
                            .updateLyricsFontScale(
                              LyricsScale.stepBy(lyricsScale, 1),
                            ),
                        onReset: () => ref
                            .read(settingsProvider.notifier)
                            .updateLyricsFontScale(1.0),
                      ),
                    ),
                  if (!desktop)
                    _MenuActionTile(
                      icon: LucideIcons.hand,
                      title: l10n.gestureTips,
                      subtitle: l10n.gestureTipsDesc,
                      onTap: () {
                        AppHaptics.medium();
                        Navigator.pop(context);
                        showLyricsGesturesTutorial(context, ref);
                      },
                    ),
                ],
              ),

              const SizedBox(height: 8),

              // Section 4: LRC files in and out
              _MenuSection(
                children: [
                  _MenuActionTile(
                    icon: LucideIcons.download,
                    title: l10n.exportLyricsLrc,
                    subtitle: l10n.saveLyricsToDevice,
                    onTap: () async {
                      AppHaptics.medium();
                      Navigator.pop(context);

                      final rawLrc = lyricsState.rawLrc;
                      if (rawLrc == null || rawLrc.trim().isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(l10n.noLyricsToExport)),
                        );
                        return;
                      }

                      try {
                        final safeArtist = (song.artist ?? 'Artist').replaceAll(
                          RegExp(r'[^a-zA-Z0-9_\-]'),
                          '_',
                        );
                        final safeTitle = song.title.replaceAll(
                          RegExp(r'[^a-zA-Z0-9_\-]'),
                          '_',
                        );
                        final defaultFileName = '$safeArtist - $safeTitle.lrc';

                        // Write to Downloads directory or custom path
                        String? exportPath;
                        if (Platform.isAndroid) {
                          final downloadsDir = Directory(
                            '/storage/emulated/0/Download',
                          );
                          if (await downloadsDir.exists()) {
                            exportPath =
                                '${downloadsDir.path}/$defaultFileName';
                            final file = File(exportPath);
                            await file.writeAsString(rawLrc);
                          }
                        }

                        exportPath ??= (await FilePicker.saveFile(
                          dialogTitle: l10n.exportLyrics,
                          fileName: defaultFileName,
                          bytes: Uint8List.fromList(rawLrc.codeUnits),
                        ))?.path;

                        if (context.mounted && exportPath != null) {
                          ScaffoldMessenger.of(context).showHapticSnackBar(
                            AppHaptics.success,
                            SnackBar(
                              content: Text(l10n.lyricsExportedTo(exportPath)),
                            ),
                          );
                        }
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showHapticSnackBar(
                            AppHaptics.error,
                            SnackBar(
                              content: Text(l10n.failedToExportLyrics('$e')),
                            ),
                          );
                        }
                      }
                    },
                  ),
                  _MenuActionTile(
                    icon: LucideIcons.filePlus,
                    title: l10n.useCustomLyricsLrc,
                    subtitle: l10n.selectLocalLrcFile,
                    onTap: () async {
                      AppHaptics.medium();
                      Navigator.pop(context);

                      final result = await FilePicker.pickFile(
                        type: FileType.custom,
                        allowedExtensions: ['lrc', 'txt'],
                      );

                      if (result != null && result.path != null) {
                        final file = File(result.path!);
                        final content = await file.readAsString();

                        if (content.trim().isNotEmpty) {
                          await ref
                              .read(lyricsProvider.notifier)
                              .applyCustomLyrics(song, content);

                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(l10n.customLyricsAppliedSuccess),
                              ),
                            );
                          }
                        }
                      }
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Rounded card grouping related menu rows, with hairline dividers between
/// them.
class _MenuSection extends StatelessWidget {
  final List<Widget> children;

  const _MenuSection({required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0)
                Divider(color: Colors.white.withValues(alpha: 0.06), height: 1),
              children[i],
            ],
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;

  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: AppFonts.jostStyle(
        color: Colors.white70,
        fontSize: 13,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

/// Leading icon badge shared by the menu's switch and action rows.
class _MenuIcon extends StatelessWidget {
  final IconData icon;
  final Color color;

  const _MenuIcon(this.icon, {this.color = Colors.white70});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(icon, color: color, size: 18),
    );
  }
}

class _MenuActionTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;

  const _MenuActionTile({
    required this.icon,
    required this.title,
    required this.onTap,
    this.subtitle,
    this.iconColor = Colors.white70,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      dense: true,
      visualDensity: VisualDensity.compact,
      leading: _MenuIcon(icon, color: iconColor),
      title: Text(
        title,
        style: AppFonts.jostStyle(
          color: Colors.white,
          fontWeight: FontWeight.w500,
          fontSize: 15,
        ),
      ),
      subtitle: subtitle == null
          ? null
          : Text(
              subtitle!,
              style: AppFonts.jostStyle(color: Colors.white54, fontSize: 12),
            ),
      trailing: const Icon(
        LucideIcons.chevronRight,
        color: Colors.white38,
        size: 18,
      ),
      onTap: onTap,
    );
  }
}

class _MenuSwitchTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final Color accent;
  final ValueChanged<bool> onChanged;

  const _MenuSwitchTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.accent,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      contentPadding: const EdgeInsets.only(left: 16, right: 10),
      dense: true,
      visualDensity: VisualDensity.compact,
      activeColor: accent,
      secondary: _MenuIcon(icon),
      title: Text(
        title,
        style: AppFonts.jostStyle(
          color: Colors.white,
          fontWeight: FontWeight.w500,
          fontSize: 15,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: AppFonts.jostStyle(color: Colors.white54, fontSize: 12),
      ),
      value: value,
      onChanged: (val) {
        AppHaptics.light();
        onChanged(val);
      },
    );
  }
}

/// "Word-synced" / "Line-synced" / "Not synced" pill next to the lyrics
/// source.
class _SyncBadge extends StatelessWidget {
  final bool wordSynced;
  final bool synced;
  final Color accent;

  const _SyncBadge({
    required this.wordSynced,
    required this.synced,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final color = wordSynced ? accent : Colors.white54;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            wordSynced
                ? LucideIcons.sparkles
                : synced
                ? LucideIcons.alignLeft
                : LucideIcons.timerOff,
            size: 13,
            color: color,
          ),
          const SizedBox(width: 6),
          Text(
            wordSynced
                ? l10n.lyricsWordSynced
                : synced
                ? l10n.lyricsLineSynced
                : l10n.lyricsNotSynced,
            style: AppFonts.jostStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// Choice chip used by both the highlight-style and provider pickers.
class _MenuChip extends StatelessWidget {
  final String label;
  final bool selected;
  final Color accent;
  final VoidCallback onSelected;

  const _MenuChip({
    required this.label,
    required this.selected,
    required this.accent,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(
        label,
        style: AppFonts.jostStyle(
          color: selected ? Colors.white : Colors.white70,
          fontWeight: selected ? FontWeight.bold : FontWeight.normal,
          fontSize: 13,
        ),
      ),
      selected: selected,
      showCheckmark: false,
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      selectedColor: accent,
      backgroundColor: Colors.white.withValues(alpha: 0.06),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: selected ? accent : Colors.white.withValues(alpha: 0.1),
        ),
      ),
      onSelected: (_) => onSelected(),
    );
  }
}

/// Lyrics timing offset: nudges this song's lyric timing later/earlier in
/// 0.1 s steps. Every song starts at the app default; a change is saved for
/// the song it was made on only.
class _LyricsOffsetControl extends StatelessWidget {
  static const int _step = 100;

  final int offsetMs;
  final Color accent;
  final ValueChanged<int> onChanged;

  const _LyricsOffsetControl({
    required this.offsetMs,
    required this.accent,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    // Positive = lyrics earlier; the default nudges them a little early.
    const int defaultMs = AppSettings.defaultLyricsOffsetMs;
    final bool isDefault = offsetMs == defaultMs;
    final seconds = (offsetMs / 1000).toStringAsFixed(1);
    final label = offsetMs > 0 ? '+$seconds s' : '$seconds s';

    Widget stepButton(IconData icon, String tooltip, int delta) => IconButton(
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
      icon: Icon(icon, size: 18, color: Colors.white70),
      onPressed: () {
        AppHaptics.selection();
        onChanged(offsetMs + delta);
      },
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.lyricsTiming,
          style: AppFonts.jostStyle(
            color: Colors.white70,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          l10n.lyricsTimingDesc,
          style: AppFonts.jostStyle(color: Colors.white38, fontSize: 12),
        ),
        Row(
          children: [
            stepButton(LucideIcons.minus, l10n.lyricsTimingLater, -_step),
            Container(
              constraints: const BoxConstraints(minWidth: 72),
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: (isDefault ? Colors.white : accent).withValues(
                  alpha: 0.1,
                ),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                label,
                style: AppFonts.jostStyle(
                  color: isDefault ? Colors.white70 : accent,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            stepButton(LucideIcons.plus, l10n.lyricsTimingEarlier, _step),
            const Spacer(),
            if (!isDefault)
              TextButton(
                onPressed: () {
                  AppHaptics.selection();
                  onChanged(defaultMs);
                },
                child: Text(
                  l10n.lyricsTimingReset,
                  style: AppFonts.jostStyle(color: accent, fontSize: 13),
                ),
              ),
          ],
        ),
      ],
    );
  }
}
