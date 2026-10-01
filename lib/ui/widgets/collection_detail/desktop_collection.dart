part of 'collection_detail_view.dart';

/// Desktop (Linux) layout of the collection page: a wide header, a stats row
/// and full-width song rows over the shell's blurred artwork background. The
/// shell's top bar already carries Back and search.
extension _DesktopCollection on CollectionDetailView {
  static const _pillColor = Color(0x0FFFFFFF);

  Widget _buildDesktop(
    BuildContext context,
    WidgetRef ref, {
    required String title,
    required String? subtitle,
    required String? art,
    required List<Song> songs,
    required Playlist? reactivePlaylist,
    required Album? reactiveAlbum,
    required bool canReorder,
    required String? activePath,
  }) {
    final l10n = AppLocalizations.of(context)!;
    final totalMs = songs.fold<int>(0, (sum, s) => sum + (s.duration ?? 0));
    final totalMinutes = (totalMs / 60000).round();
    final durationLabel = totalMinutes >= 60
        ? l10n.durationHoursMinutes(totalMinutes ~/ 60, totalMinutes % 60)
        : l10n.minutesShort(totalMinutes);

    Widget row(int index, {int? reorderIndex}) {
      final song = songs[index];
      return _DesktopSongRow(
        key: ValueKey(song.path),
        song: song,
        songs: songs,
        playlist: reactivePlaylist,
        isCurrent: song.path == activePath,
        reorderIndex: reorderIndex,
      );
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 0),
            sliver: SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      OptimizedImage(
                        imagePath: art,
                        imageUrl: imageUrl,
                        width: 140,
                        height: 140,
                        borderRadius: BorderRadius.circular(6),
                        placeholder: Container(
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.05),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Icon(
                            LucideIcons.music,
                            size: 48,
                            color: Colors.grey,
                          ),
                        ),
                      ),
                      const SizedBox(width: 22),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 4),
                            Text(
                              title,
                              style: AppFonts.jostStyle(
                                fontSize: 34,
                                height: 1.15,
                                fontWeight: FontWeight.w500,
                                color: Colors.white,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (subtitle != null) ...[
                              const SizedBox(height: 4),
                              Text(
                                subtitle,
                                style: AppFonts.jostStyle(
                                  fontSize: 22,
                                  color: Colors.white.withValues(alpha: 0.45),
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                            const SizedBox(height: 16),
                            Row(
                              children: [
                                _DesktopPill(
                                  onTap: () => ref
                                      .read(playbackProvider.notifier)
                                      .setPlaylist(songs),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(
                                        Icons.play_arrow_rounded,
                                        color: Colors.white,
                                        size: 20,
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        l10n.playAll,
                                        style: AppFonts.jostStyle(
                                          color: Colors.white,
                                          fontSize: 14,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 10),
                                _DesktopPill.icon(
                                  icon: LucideIcons.shuffle,
                                  tooltip: l10n.shuffleTitle,
                                  onTap: () {
                                    ref
                                        .read(playbackProvider.notifier)
                                        .toggleShuffle();
                                    ref
                                        .read(playbackProvider.notifier)
                                        .setPlaylist(songs);
                                  },
                                ),
                                if (reactivePlaylist != null) ...[
                                  const SizedBox(width: 10),
                                  _DesktopPill.icon(
                                    icon: LucideIcons.moreHorizontal,
                                    onTap: () => _showPlaylistOptions(
                                      context,
                                      ref,
                                      reactivePlaylist,
                                    ),
                                  ),
                                ] else if (reactiveAlbum != null) ...[
                                  const SizedBox(width: 10),
                                  _DesktopPill.icon(
                                    icon: LucideIcons.edit2,
                                    onTap: () => _showEditAlbumSheet(
                                      context,
                                      ref,
                                      reactiveAlbum,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 38),
                  Row(
                    children: [
                      _DesktopPill(
                        child: Text(
                          l10n.songsCountTitle(songs.length),
                          style: AppFonts.jostStyle(
                            color: Colors.white,
                            fontSize: 14,
                          ),
                        ),
                      ),
                      const Spacer(),
                      _DesktopPill.icon(
                        icon: LucideIcons.arrowUpDown,
                        onTap: () => _showSortBottomSheet(context, ref),
                      ),
                      const SizedBox(width: 12),
                      _DesktopPill(
                        child: Text(
                          durationLabel,
                          style: AppFonts.jostStyle(
                            color: Colors.white.withValues(alpha: 0.45),
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            // Dragging to reorder only applies to a playlist in its own saved
            // order (see the mobile layout).
            sliver: canReorder
                ? SliverReorderableList(
                    itemCount: songs.length,
                    itemBuilder: (context, index) =>
                        row(index, reorderIndex: index),
                    onReorder: (oldIndex, newIndex) {
                      PlaylistService.reorderSong(
                        reactivePlaylist!,
                        oldIndex,
                        newIndex,
                      );
                    },
                  )
                : SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) => row(index),
                      childCount: songs.length,
                    ),
                  ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 48)),
        ],
      ),
    );
  }
}

/// Dark rounded pill used for the header buttons and the stats chips.
class _DesktopPill extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  final String? tooltip;
  final bool circle;

  const _DesktopPill({required this.child, this.onTap})
    : tooltip = null,
      circle = false;

  _DesktopPill.icon({required IconData icon, this.onTap, this.tooltip})
    : child = Icon(icon, size: 15, color: Colors.white),
      circle = true;

  @override
  Widget build(BuildContext context) {
    final pill = Material(
      color: _DesktopCollection._pillColor,
      shape: const StadiumBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          height: 36,
          width: circle ? 36 : null,
          alignment: circle ? Alignment.center : null,
          padding: circle ? null : const EdgeInsets.symmetric(horizontal: 18),
          child: circle ? child : Center(widthFactor: 1, child: child),
        ),
      ),
    );
    return tooltip == null ? pill : Tooltip(message: tooltip!, child: pill);
  }
}

/// One song in the desktop collection list: artwork, title, artist, favourite
/// and duration. Click plays, right-click (or the hover button) opens the
/// song options.
class _DesktopSongRow extends ConsumerStatefulWidget {
  final Song song;
  final List<Song> songs;
  final Playlist? playlist;
  final bool isCurrent;
  final int? reorderIndex;

  const _DesktopSongRow({
    super.key,
    required this.song,
    required this.songs,
    required this.isCurrent,
    this.playlist,
    this.reorderIndex,
  });

  @override
  ConsumerState<_DesktopSongRow> createState() => _DesktopSongRowState();
}

class _DesktopSongRowState extends ConsumerState<_DesktopSongRow> {
  bool _hovered = false;
  late bool _favorite = widget.song.isFavorite;

  @override
  void didUpdateWidget(_DesktopSongRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.song, widget.song)) {
      _favorite = widget.song.isFavorite;
    }
  }

  void _play() {
    final index = widget.songs.indexWhere((s) => s.path == widget.song.path);
    final playback = ref.read(playbackProvider.notifier);
    if (index != -1) {
      playback.setPlaylist(widget.songs, initialIndex: index);
    } else {
      playback.play(widget.song);
    }
  }

  void _showOptions() => showSongOptionsBottomSheet(
    context: context,
    ref: ref,
    song: widget.song,
    playlist: widget.playlist,
    showEqualizerAndTechnicalInfoOptions: false,
  );

  String _duration() {
    final d = Duration(milliseconds: widget.song.duration ?? 0);
    final minutes = d.inMinutes.toString().padLeft(2, '0');
    final seconds = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final song = widget.song;
    final lit = _hovered || widget.isCurrent;
    // The playing song's favourite state lives in the playback state.
    final favorite = widget.isCurrent
        ? ref.watch(
            playbackProvider.select(
              (s) => s.currentSong?.isFavorite ?? _favorite,
            ),
          )
        : _favorite;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _play,
        onSecondaryTap: _showOptions,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          height: 56,
          padding: const EdgeInsets.only(left: 8, right: 12),
          decoration: BoxDecoration(
            color: lit
                ? Colors.white.withValues(alpha: 0.04)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              OptimizedImage(
                imagePath: song.artPath,
                width: 42,
                height: 42,
                borderRadius: BorderRadius.circular(4),
                placeholder: Container(
                  color: Colors.white.withValues(alpha: 0.05),
                  child: const Icon(
                    LucideIcons.music,
                    size: 16,
                    color: Colors.white24,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      song.title,
                      style: AppFonts.jostStyle(
                        color: Colors.white,
                        fontSize: 16,
                        height: 1.2,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      song.artist ?? l10n.unknownArtist,
                      style: AppFonts.jostStyle(
                        color: Colors.white.withValues(alpha: 0.45),
                        fontSize: 12,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (widget.reorderIndex != null)
                ReorderableDragStartListener(
                  index: widget.reorderIndex!,
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 6),
                    child: Icon(
                      LucideIcons.gripVertical,
                      size: 18,
                      color: Colors.white38,
                    ),
                  ),
                ),
              Opacity(
                opacity: _hovered ? 1 : 0,
                child: IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(
                    Icons.more_vert,
                    size: 18,
                    color: Colors.white54,
                  ),
                  onPressed: _showOptions,
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: l10n.toggleFavorite,
                icon: SvgPicture.asset(
                  favorite ? AppAssets.desktopLiked : AppAssets.desktopLike,
                  width: 16,
                  height: 16,
                  colorFilter: ColorFilter.mode(
                    favorite ? Colors.red : Colors.white54,
                    BlendMode.srcIn,
                  ),
                ),
                onPressed: () {
                  setState(() => _favorite = !favorite);
                  ref.read(libraryProvider.notifier).toggleFavorite(song);
                },
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 48,
                child: Text(
                  _duration(),
                  style: AppFonts.jostStyle(
                    color: Colors.white.withValues(alpha: 0.45),
                    fontSize: 15,
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
