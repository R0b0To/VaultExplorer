import 'dart:math' as math;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/theme/app_theme.dart';
import 'package:vaultexplorer/features/browser/viewer/background_playback/background_playback_host.dart';
import 'package:vaultexplorer/features/library/controllers/music_hub.dart';
import 'package:vaultexplorer/features/library/widgets/library_cover.dart';
import 'package:vaultexplorer/features/library/widgets/music_covers.dart';
import 'package:vaultexplorer/features/library/widgets/now_playing_info.dart';

/// Height of one queue row.
const double kMusicQueueRowHeight = 64;

/// How much of the inline queue shows under the full player: its handle and
/// the "Queue  3 / 20" line. The player leaves room for it.
const double kMusicQueuePeekHeight = 56;

/// One row of the play queue: cover, title, artist, and the playing one
/// highlighted. Shared by the queue sheet and the queue inside the player.
class MusicQueueRow extends StatelessWidget {
  final NowPlayingInfo info;
  final bool playing;
  final MusicCovers covers;
  final VoidCallback onTap;

  const MusicQueueRow({
    super.key,
    required this.info,
    required this.playing,
    required this.covers,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    return ListTile(
      selected: playing,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)),
      ),
      selectedTileColor: cs.primaryContainer.withValues(alpha: 0.4),
      contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      leading: LibraryCover(
        covers: covers,
        track: info.coverTrack,
        groupKey: info.coverKey,
        size: 44,
        borderRadius: 6,
      ),
      title: Text(info.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: info.artist.isEmpty
          ? null
          : Text(info.artist, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: playing
          ? Icon(Icons.graphic_eq_rounded, color: cs.primary)
          : null,
      onTap: onTap,
    );
  }
}

/// The queue that rises from the bottom of the full player
/// Meant to be the child of a `DraggableScrollableSheet`, whose
/// [scrollController] it uses so dragging its handle or list moves the sheet.
///
/// Its first [kMusicQueuePeekHeight] (plus [bottomInset]) is what shows while
/// the sheet is down; [onHeaderTap] toggles it.
class MusicInlineQueue extends StatelessWidget {
  final MusicHub hub;
  final MusicCovers covers;
  final ScrollController scrollController;
  final double bottomInset;

  /// How far the sheet is open, 0 to 1 (turns the chevron).
  final ValueListenable<double> openness;
  final VoidCallback onHeaderTap;

  const MusicInlineQueue({
    super.key,
    required this.hub,
    required this.covers,
    required this.scrollController,
    required this.bottomInset,
    required this.openness,
    required this.onHeaderTap,
  });

  @override
  Widget build(BuildContext context) {
    final host = BackgroundPlaybackHost.instance;
    final cs = context.colors;
    final text = context.typography;
    const radius = BorderRadius.vertical(top: Radius.circular(20));

    return ValueListenableBuilder<BackgroundPlaybackSession?>(
      valueListenable: host.activeSession,
      builder: (context, session, _) {
        if (session == null) return const SizedBox.shrink();
        return ListenableBuilder(
          listenable: session.playlist,
          builder: (context, _) {
            final queue = session.playlist.playlist;
            final current = session.playlist.currentIndex;
            // A Material, not a plain box, so the rows' highlight and
            // ripples are painted on top of the sheet's colour.
            return Material(
              color: cs.surfaceContainerHigh,
              elevation: 8,
              shadowColor: Colors.black,
              shape: const RoundedRectangleBorder(borderRadius: radius),
              clipBehavior: Clip.antiAlias,
              child: CustomScrollView(
                controller: scrollController,
                slivers: [
                    SliverToBoxAdapter(
                    child: InkWell(
                      onTap: onHeaderTap,
                      child: SizedBox(
                        height: kMusicQueuePeekHeight,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const SizedBox(height: 8),
                            Center(
                              child: Container(
                                width: 32,
                                height: 4,
                                decoration: BoxDecoration(
                                  color: cs.onSurfaceVariant.withValues(
                                    alpha: 0.4,
                                  ),
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.fromLTRB(
                                AppSpacing.lg,
                                10,
                                AppSpacing.lg,
                                0,
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      context.l10n.nowPlayingQueue,
                                      style: text.titleMedium,
                                    ),
                                  ),
                                  Text(
                                    '${current + 1} / ${queue.length}',
                                    style: text.bodySmall?.copyWith(
                                      color: cs.onSurfaceVariant,
                                    ),
                                  ),
                                  const SizedBox(width: AppSpacing.sm),
                                  ValueListenableBuilder<double>(
                                    valueListenable: openness,
                                    builder: (context, q, child) =>
                                        Transform.rotate(
                                          angle: math.pi * q,
                                          child: child,
                                        ),
                                    child: Icon(
                                      Icons.keyboard_arrow_up_rounded,
                                      color: cs.onSurfaceVariant,
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
                  SliverFixedExtentList(
                    itemExtent: kMusicQueueRowHeight,
                    delegate: SliverChildBuilderDelegate(
                      (context, i) => Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.sm,
                        ),
                        child: MusicQueueRow(
                          info: NowPlayingInfo.resolve(hub, session, queue[i]),
                          playing: i == current,
                          covers: covers,
                          onTap: () => host.playQueueIndex(i),
                        ),
                      ),
                      childCount: queue.length,
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: SizedBox(height: bottomInset + AppSpacing.md),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
