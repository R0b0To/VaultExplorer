import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/theme/app_theme.dart';
import 'package:vaultexplorer/features/browser/viewer/background_playback/background_playback_host.dart';
import 'package:vaultexplorer/features/browser/viewer/media_viewer_constants.dart';
import 'package:vaultexplorer/features/browser/viewer/native_video_controller.dart';
import 'package:vaultexplorer/features/library/controllers/music_hub.dart';
import 'package:vaultexplorer/features/library/models/library_track.dart';
import 'package:vaultexplorer/features/library/widgets/library_cover.dart';
import 'package:vaultexplorer/features/library/widgets/music_covers.dart';

/// Playback controls for music that keeps playing after its viewer is closed:
/// what is playing, previous, play or pause, next, stop. Tapping the bar
/// reopens the full player.
///
/// It follows [BackgroundPlaybackHost.activeSession], so it appears only while
/// a session (not a viewer) owns audio playback, and disappears the moment the
/// music stops or a viewer takes over. Tapping or swiping up expands the player.
/// It shows tags from the library when the file is in it and falls back to the
/// file name.
class MusicMiniPlayer extends StatelessWidget {
  final MusicHub hub;
  final MusicCovers covers;

  const MusicMiniPlayer({super.key, required this.hub, required this.covers});

  @override
  Widget build(BuildContext context) {
    final host = BackgroundPlaybackHost.instance;
    return ValueListenableBuilder<BackgroundPlaybackSession?>(
      valueListenable: host.activeSession,
      builder: (context, session, _) {
        if (session == null) return const SizedBox.shrink();
        final manager = session.playbackManager;
        return ValueListenableBuilder<String?>(
          valueListenable: manager.currentFileNotifier,
          builder: (context, file, _) {
            final path = session.playlist.currentFile.isNotEmpty
                ? session.playlist.currentFile
                : (file ?? '');
            // Video sessions have their own floating window; this is for music.
            if (path.isEmpty || !MediaViewerConstants.isAudio(path)) {
              return const SizedBox.shrink();
            }
            return ValueListenableBuilder<NativeVideoController?>(
              valueListenable: manager.activeControllerNotifier,
              builder: (context, controller, _) => _MiniBar(
                host: host,
                session: session,
                controller: controller,
                path: path,
                hub: hub,
                covers: covers,
              ),
            );
          },
        );
      },
    );
  }
}

class _MiniBar extends StatelessWidget {
  final BackgroundPlaybackHost host;
  final BackgroundPlaybackSession session;
  final NativeVideoController? controller;
  final String path;
  final MusicHub hub;
  final MusicCovers covers;

  const _MiniBar({
    required this.host,
    required this.session,
    required this.controller,
    required this.path,
    required this.hub,
    required this.covers,
  });

  LibraryTrack? get _track =>
      hub.index.trackForKey('${session.container.uri}\u0000$path');

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final text = context.typography;
    final l10n = context.l10n;
    final track = _track;
    final fileName = path.contains('/')
        ? path.substring(path.lastIndexOf('/') + 1)
        : path;
    final title = track?.title ?? LibraryTrack.titleFromFileName(fileName);
    final artist = track == null || track.artists.isEmpty
        ? ''
        : track.artists.join(', ');

    final listenable = Listenable.merge([
      if (controller != null) controller!,
      session.playlist,
    ]);
    var verticalDrag = 0.0;

    return Material(
      color: cs.surfaceContainerHigh,
      elevation: 2,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onVerticalDragStart: (_) => verticalDrag = 0,
        onVerticalDragUpdate: (details) => verticalDrag += details.delta.dy,
        onVerticalDragEnd: (details) {
          if (verticalDrag < -24 || (details.primaryVelocity ?? 0) < -100) {
            host.expand();
          } else if (verticalDrag > 24 ||
              (details.primaryVelocity ?? 0) > 100) {
            host.closeAndWait();
          }
        },
        child: InkWell(
          onTap: () => host.expand(),
          child: ListenableBuilder(
            listenable: listenable,
            builder: (context, _) {
              final value = controller?.value;
              final playing = value?.isPlaying ?? false;
              final total = value?.duration.inMilliseconds ?? 0;
              final done = value?.position.inMilliseconds ?? 0;
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  LinearProgressIndicator(
                    minHeight: 2,
                    value: total > 0 ? (done / total).clamp(0.0, 1.0) : 0,
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.md,
                      6,
                      AppSpacing.xs,
                      6,
                    ),
                    child: Row(
                      children: [
                        Hero(
                          tag: 'media_hero_${session.container.volId}_$path',
                          createRectTween: (begin, end) =>
                              MaterialRectArcTween(begin: begin, end: end),
                          child: Material(
                            color: Colors.transparent,
                            child: LibraryCover(
                              covers: covers,
                              track: track,
                              size: 44,
                              borderRadius: 6,
                            ),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: text.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              if (artist.isNotEmpty)
                                Text(
                                  artist,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: text.bodySmall?.copyWith(
                                    color: cs.onSurfaceVariant,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: l10n.musicMiniPrevious,
                          icon: const Icon(Icons.skip_previous_rounded),
                          onPressed: host.canStepPrevious
                              ? () => host.stepItem(-1)
                              : null,
                        ),
                        IconButton.filled(
                          tooltip: playing
                              ? l10n.musicMiniPause
                              : l10n.musicMiniPlay,
                          icon: Icon(
                            playing
                                ? Icons.pause_rounded
                                : Icons.play_arrow_rounded,
                          ),
                          onPressed: controller == null
                              ? null
                              : () => playing
                                    ? controller!.pause()
                                    : controller!.play(),
                        ),
                        IconButton(
                          tooltip: l10n.musicMiniNext,
                          icon: const Icon(Icons.skip_next_rounded),
                          onPressed: host.canStepNext
                              ? () => host.stepItem(1)
                              : null,
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
