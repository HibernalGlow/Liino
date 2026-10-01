import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:looper_player/core/theme/app_fonts.dart';
import 'package:looper_player/core/utils/app_links.dart';
import 'package:looper_player/l10n/app_localizations.dart';
import 'package:looper_player/core/utils/ui_utils.dart';
import 'package:looper_player/features/settings/presentation/providers/settings_notifier.dart';

import 'package:looper_player/core/providers/providers.dart';
import 'package:looper_player/core/utils/l10n.dart';
import 'package:looper_player/core/theme/app_assets.dart';
import 'package:looper_player/core/services/haptics/app_haptics.dart';
import 'package:looper_player/core/services/update/apk_update_notifier.dart';
import 'package:looper_player/ui/widgets/sheets/apk_update_sheet.dart';

class LooperVersionTile extends ConsumerWidget {
  const LooperVersionTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final versionAsync = ref.watch(appVersionProvider);
    final versionStr = versionAsync.value != null
        ? context.l10n.versionLabel('${versionAsync.value}')
        : context.l10n.versionLabel('...');

    return ListTile(
      leading: const Icon(LucideIcons.info, color: Colors.white70),
      title: Text(
        'Looper Player',
        style: AppFonts.jostStyle(
          color: Colors.white,
          fontWeight: FontWeight.w500,
        ),
      ),
      subtitle: Text(
        versionStr,
        style: AppFonts.jostStyle(color: Colors.white54, fontSize: 12),
      ),
      onTap: () async {
        final Uri uri = Uri.parse(AppLinks.githubRepo);
        try {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        } catch (e) {}
      },
    );
  }
}

class LyricsProviderTile extends ConsumerWidget {
  const LyricsProviderTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final l10n = AppLocalizations.of(context)!;

    final availableProviders = [
      'lrc.red',
      'LyricsPlus',
      'LRCLIB',
      'Genius',
      'Musixmatch',
      'AZLyrics',
      'LyricsMINT',
      'LyricFind',
    ];

    final providerUrls = AppLinks.lyricsProviderUrls;

    final currentProvider = settings.lyricsProvider;

    return ListTile(
      leading: const Icon(LucideIcons.music, color: Colors.white70),
      title: Text(
        l10n.lyricsProvider,
        style: AppFonts.jostStyle(
          color: Colors.white,
          fontWeight: FontWeight.w500,
        ),
      ),
      subtitle: Text(
        providerUrls[currentProvider] ?? 'lrc.red',
        style: AppFonts.jostStyle(color: Colors.white54, fontSize: 12),
      ),
      trailing: DropdownButton<String>(
        value: availableProviders.contains(currentProvider)
            ? currentProvider
            : 'lrc.red',
        dropdownColor: const Color(0xFF1A1A1A),
        underline: const SizedBox(),
        items: availableProviders.map((prov) {
          return DropdownMenuItem<String>(
            value: prov,
            child: Text(prov, style: AppFonts.jostStyle(color: Colors.white)),
          );
        }).toList(),
        onChanged: (value) {
          if (value != null) {
            ref.read(settingsProvider.notifier).updateLyricsProvider(value);
          }
        },
      ),
    );
  }
}

class OpenSourceLicensesTile extends ConsumerWidget {
  const OpenSourceLicensesTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final versionAsync = ref.watch(appVersionProvider);

    return ListTile(
      leading: const Icon(LucideIcons.scrollText, color: Colors.white70),
      title: Text(
        l10n.openSourceLicenses,
        style: AppFonts.jostStyle(
          color: Colors.white,
          fontWeight: FontWeight.w500,
        ),
      ),
      subtitle: Text(
        l10n.openSourceLicensesDesc,
        style: AppFonts.jostStyle(color: Colors.white54, fontSize: 12),
      ),
      trailing: Icon(
        LucideIcons.chevronRight,
        color: Colors.white.withValues(alpha: 0.4),
        size: 18,
      ),
      onTap: () {
        AppHaptics.light();
        Navigator.of(context, rootNavigator: true).push(
          MaterialPageRoute(
            builder: (context) => LicensePage(
              applicationName: 'Looper Player',
              applicationVersion: versionAsync.value,
            ),
          ),
        );
      },
    );
  }
}

class GitHubStarTile extends StatelessWidget {
  const GitHubStarTile({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.amber.withValues(alpha: 0.15),
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.star_rounded, color: Colors.amber, size: 22),
      ),
      title: Text(
        l10n.giveStarOnGithub,
        style: AppFonts.jostStyle(
          color: Colors.white,
          fontSize: 15,
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle: Text(
        l10n.supportProjectLove,
        style: AppFonts.jostStyle(
          color: Colors.white.withValues(alpha: 0.4),
          fontSize: 12,
        ),
      ),
      trailing: Icon(
        LucideIcons.chevronRight,
        color: Colors.white.withValues(alpha: 0.4),
        size: 18,
      ),
      onTap: () async {
        AppHaptics.light();
        final Uri uri = Uri.parse(AppLinks.githubRepo);
        try {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        } catch (e) {}
      },
    );
  }
}

/// Manual update check for the github build (see [ApkInstaller.supported]);
/// opens the in-app update sheet when a newer release exists.
class CheckForUpdatesTile extends ConsumerStatefulWidget {
  const CheckForUpdatesTile({super.key});

  @override
  ConsumerState<CheckForUpdatesTile> createState() =>
      _CheckForUpdatesTileState();
}

class _CheckForUpdatesTileState extends ConsumerState<CheckForUpdatesTile> {
  bool _checking = false;

  Future<void> _check() async {
    if (_checking) return;
    AppHaptics.light();
    setState(() => _checking = true);
    final result = await ref.read(apkUpdateProvider.notifier).check();
    if (!mounted) return;
    setState(() => _checking = false);

    if (result == ApkCheckResult.available) {
      showApkUpdateSheet(context);
      return;
    }
    final l10n = context.l10n;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text(
          result == ApkCheckResult.upToDate
              ? l10n.updateUpToDate
              : l10n.updateCheckFailed,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final update = ref.watch(apkUpdateProvider);
    final release = update.release;
    final accentColor = Color(
      ref.watch(settingsProvider.select((s) => s.accentColor)),
    );

    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: accentColor.withValues(alpha: 0.15),
          shape: BoxShape.circle,
        ),
        child: Icon(LucideIcons.download, color: accentColor, size: 22),
      ),
      title: Text(
        l10n.checkForUpdates,
        style: AppFonts.jostStyle(
          color: Colors.white,
          fontSize: 15,
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle: release == null
          ? null
          : Text(
              l10n.updateAvailableOnGithub(release.tag),
              style: AppFonts.jostStyle(
                color: Colors.white.withValues(alpha: 0.4),
                fontSize: 12,
              ),
            ),
      trailing: _checking || update.phase == ApkUpdatePhase.downloading
          ? SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: accentColor,
                value: _checking ? null : update.progress,
              ),
            )
          : Icon(
              LucideIcons.chevronRight,
              color: Colors.white.withValues(alpha: 0.4),
              size: 18,
            ),
      onTap: _check,
    );
  }
}

class InfoSubTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;

  const InfoSubTile({
    super.key,
    required this.icon,
    required this.title,
    required this.description,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16.s, color: Colors.white60),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: AppFonts.jostStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                description,
                style: AppFonts.jostStyle(
                  fontSize: 12,
                  height: 1.5,
                  color: Colors.white.withValues(alpha: 0.5),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class AboutMaintainerRow extends StatelessWidget {
  final String name;
  final String role;
  final String avatar;
  final String github;
  final String telegram;

  const AboutMaintainerRow({
    super.key,
    required this.name,
    required this.role,
    required this.avatar,
    required this.github,
    required this.telegram,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      child: Row(
        children: [
          CircleAvatar(
            radius: 24,
            backgroundColor: Colors.white10,
            backgroundImage: AssetImage(avatar),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: AppFonts.jostStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  role,
                  style: AppFonts.jostStyle(
                    color: Colors.white.withValues(alpha: 0.4),
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: () async {
              AppHaptics.light();
              final Uri uri = Uri.parse(github);
              try {
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              } catch (e) {}
            },
            child: Container(
              width: 24,
              height: 24,
              alignment: Alignment.center,
              child: SvgPicture.asset(AppAssets.github, width: 24, height: 24),
            ),
          ),
          const SizedBox(width: 12),
          GestureDetector(
            onTap: () async {
              AppHaptics.light();
              final Uri uri = Uri.parse(telegram);
              try {
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              } catch (e) {}
            },
            child: SizedBox(
              width: 24,
              height: 24,
              child: SvgPicture.asset(
                AppAssets.telegram,
                width: 24,
                height: 24,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The About screen's maintainers card body: shows only the first row until
/// tapped, then reveals [rest]. The rows' own link buttons keep their taps.
class CollapsibleMaintainers extends StatefulWidget {
  final Widget first;
  final List<Widget> rest;

  const CollapsibleMaintainers({
    super.key,
    required this.first,
    required this.rest,
  });

  @override
  State<CollapsibleMaintainers> createState() => _CollapsibleMaintainersState();
}

class _CollapsibleMaintainersState extends State<CollapsibleMaintainers> {
  static const _duration = Duration(milliseconds: 260);
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        AppHaptics.light();
        setState(() => _expanded = !_expanded);
      },
      child: Column(
        children: [
          widget.first,
          ClipRect(
            child: AnimatedSize(
              duration: _duration,
              curve: Curves.easeOutCubic,
              alignment: Alignment.topCenter,
              child: _expanded
                  ? Column(children: widget.rest)
                  : const SizedBox(width: double.infinity),
            ),
          ),
          AnimatedRotation(
            turns: _expanded ? 0.5 : 0,
            duration: _duration,
            curve: Curves.easeOutCubic,
            child: Icon(
              Icons.keyboard_arrow_down_rounded,
              size: 22,
              color: Colors.white.withValues(alpha: 0.4),
            ),
          ),
        ],
      ),
    );
  }
}

/// Services and projects Looper's online lyrics rely on, credited in About on
/// both Android and desktop. None publish terms of use, so each gets a name,
/// what it provides, its license where it has one, and a link.
typedef LyricsCredit = ({String name, String description, String url});

List<LyricsCredit> lyricsCredits(AppLocalizations l10n) => [
  (
    name: 'lrc.red',
    description: l10n.creditLrcRedDesc,
    url: AppLinks.lrcRedWeb,
  ),
  (
    name: 'LyricsPlus',
    description: l10n.creditLyricsPlusDesc,
    url: AppLinks.lyricsPlusSource,
  ),
  (name: 'LRCLIB', description: l10n.creditLrclibDesc, url: AppLinks.lrclibWeb),
  (
    name: 'MusicBrainz',
    description: l10n.creditMusicBrainzDesc,
    url: AppLinks.musicBrainzWeb,
  ),
  (
    name: 'am-lyrics',
    description: l10n.creditAmLyricsDesc,
    url: AppLinks.amLyricsSource,
  ),
];

class LyricsCreditsSection extends StatelessWidget {
  final Color accentColor;

  const LyricsCreditsSection({super.key, required this.accentColor});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.lyricsSources.toUpperCase(),
            style: AppFonts.jostStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: accentColor.withValues(alpha: 0.8),
              letterSpacing: 1.0,
            ),
          ),
          const SizedBox(height: 8),
          for (final credit in lyricsCredits(l10n))
            InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () async {
                AppHaptics.light();
                try {
                  await launchUrl(
                    Uri.parse(credit.url),
                    mode: LaunchMode.externalApplication,
                  );
                } catch (e) {}
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: InfoSubTile(
                        icon: LucideIcons.music,
                        title: credit.name,
                        description: credit.description,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(
                      LucideIcons.externalLink,
                      size: 14.s,
                      color: Colors.white38,
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 8),
          Text(
            l10n.lyricsCopyrightNote,
            style: AppFonts.jostStyle(
              fontSize: 11,
              height: 1.5,
              color: Colors.white.withValues(alpha: 0.35),
            ),
          ),
        ],
      ),
    );
  }
}
