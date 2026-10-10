part of '../screens/search_view.dart';

/// A titled, horizontally scrolling row of result chips, for the result
/// kinds that have a name but no artwork of their own (playlists, genres).
class _ChipResultSection extends StatelessWidget {
  final String title;
  final List<Widget> children;
  const _ChipResultSection({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            title,
            style: AppFonts.jostStyle(
              fontSize: 18,
              fontWeight: FontWeight.normal,
            ),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 56,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: children.length,
            separatorBuilder: (_, _) => const SizedBox(width: 10),
            itemBuilder: (context, index) => children[index],
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}

class _ResultChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? detail;
  final VoidCallback onTap;

  const _ResultChip({
    required this.icon,
    required this.label,
    required this.onTap,
    this.detail,
  });

  @override
  Widget build(BuildContext context) {
    final accentColor = Theme.of(context).colorScheme.primary;
    return Material(
      color: Colors.white.withValues(alpha: 0.06),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 240),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 20, color: accentColor),
                const SizedBox(width: 10),
                Flexible(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppFonts.jostStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                      if (detail != null)
                        Text(
                          detail!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppFonts.jostStyle(
                            fontSize: 12,
                            color: Colors.grey,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PlaylistResultChip extends ConsumerWidget {
  final Playlist playlist;
  const _PlaylistResultChip({required this.playlist});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    return _ResultChip(
      icon: LucideIcons.listMusic,
      label: playlist.name,
      detail: l10n.songsCount(playlist.songPaths.length),
      onTap: () async {
        final songs = await DbService.isar.songs
            .filter()
            .anyOf(playlist.songPaths, (q, path) => q.pathEqualTo(path))
            .findAll();
        // Keep the playlist's own order, as the Playlists screen does.
        final songMap = {for (final s in songs) s.path: s};
        final orderedSongs = playlist.songPaths
            .map((path) => songMap[path])
            .whereType<Song>()
            .toList();
        ref
            .read(appNavigationProvider.notifier)
            .showCollection(
              title: playlist.name,
              subtitle: l10n.playlist,
              songs: orderedSongs,
              playlist: playlist,
            );
      },
    );
  }
}

class _GenreResultChip extends ConsumerWidget {
  final String genre;
  const _GenreResultChip({required this.genre});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    return _ResultChip(
      icon: LucideIcons.tag,
      label: genre,
      onTap: () async {
        final songs = await DbService.isar.songs
            .filter()
            .genreEqualTo(genre, caseSensitive: false)
            .findAll();
        if (songs.isEmpty) return;
        final withArt = songs.firstWhere(
          (s) => s.artPath != null,
          orElse: () => songs.first,
        );
        ref
            .read(appNavigationProvider.notifier)
            .showCollection(
              title: genre,
              subtitle: l10n.genre,
              art: withArt.artPath,
              songs: songs,
            );
      },
    );
  }
}
