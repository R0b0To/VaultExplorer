import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/theme/app_theme.dart';
import 'package:vaultexplorer/features/browser/viewer/background_playback/background_playback_host.dart';
import 'package:vaultexplorer/features/library/controllers/music_hub.dart';
import 'package:vaultexplorer/features/library/widgets/library_cover.dart';
import 'package:vaultexplorer/features/library/widgets/music_covers.dart';
import 'package:vaultexplorer/features/library/widgets/now_playing_info.dart';

/// Shows the running play queue: every track, the playing one highlighted, a
/// tap jumps to it. It follows the session, so it updates when the track
/// changes or the queue is shuffled, and closes itself when playback ends.
Future<void> showMusicQueueSheet(
  BuildContext context, {
  required MusicHub hub,
  required MusicCovers covers,
}) {
  return showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => _QueueSheet(hub: hub, covers: covers),
  );
}

class _QueueSheet extends StatefulWidget {
  final MusicHub hub;
  final MusicCovers covers;

  const _QueueSheet({required this.hub, required this.covers});

  @override
  State<_QueueSheet> createState() => _QueueSheetState();
}

class _QueueSheetState extends State<_QueueSheet> {
  static const double _rowHeight = 64;

  final BackgroundPlaybackHost _host = BackgroundPlaybackHost.instance;
  bool _scrolled = false;

  @override
  void initState() {
    super.initState();
    _host.activeSession.addListener(_onSession);
  }

  @override
  void dispose() {
    _host.activeSession.removeListener(_onSession);
    super.dispose();
  }

  void _onSession() {
    if (_host.activeSession.value != null || !mounted) return;
    Navigator.of(context).maybePop();
  }

  void _scrollToCurrent(ScrollController controller, int current) {
    if (_scrolled) return;
    _scrolled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!controller.hasClients) return;
      final target = math.max(0, current - 1) * _rowHeight;
      controller.jumpTo(
        math.min(target, controller.position.maxScrollExtent),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final session = _host.activeSession.value;
    if (session == null) return const SizedBox.shrink();
    final cs = context.colors;
    final text = context.typography;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      builder: (context, controller) => ListenableBuilder(
        listenable: session.playlist,
        builder: (context, _) {
          final queue = session.playlist.playlist;
          final current = session.playlist.currentIndex;
          _scrollToCurrent(controller, current);
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  0,
                  AppSpacing.lg,
                  AppSpacing.sm,
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
                      style: text.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView.builder(
                  controller: controller,
                  itemExtent: _rowHeight,
                  itemCount: queue.length,
                  itemBuilder: (context, i) {
                    final info = NowPlayingInfo.resolve(
                      widget.hub,
                      session,
                      queue[i],
                    );
                    final playing = i == current;
                    return ListTile(
                      selected: playing,
                      selectedTileColor: cs.primaryContainer.withValues(
                        alpha: 0.4,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.md,
                      ),
                      leading: LibraryCover(
                        covers: widget.covers,
                        track: info.coverTrack,
                        groupKey: info.coverKey,
                        size: 44,
                        borderRadius: 6,
                      ),
                      title: Text(
                        info.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: info.artist.isEmpty
                          ? null
                          : Text(
                              info.artist,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                      trailing: playing
                          ? Icon(Icons.graphic_eq_rounded, color: cs.primary)
                          : null,
                      onTap: () => _host.playQueueIndex(i),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
