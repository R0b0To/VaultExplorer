part of 'media_viewer_screen.dart';

/// Pickers, option menus and sheets, and the media actions they run.
///
/// Moved out of [_MediaViewerScreenState] as is: an extension in the
/// same library reads and writes the state's private fields exactly as the
/// class did.
extension _MediaViewerSheets on _MediaViewerScreenState {
  void _showDecoderPicker(BuildContext context) {
    _menuOpened();
    final l10n = context.l10n;
    final isAudio = MediaViewerConstants.isAudio(
      _playlistController.currentFile,
    );

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppRadius.sheet),
        ),
      ),
      builder: (sheetContext) {
        String selectedTab = isAudio ? 'audio' : 'video';
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final cs = Theme.of(context).colorScheme;
            final mediaConfig = ref
                .watch(fileManagerToolbarSettingsProvider(null))
                .config
                .mediaViewerToolbarConfig;
            final isVideoSelected = selectedTab == 'video';
            final currentMode = isVideoSelected
                ? mediaConfig.videoDecoderMode
                : mediaConfig.audioDecoderMode;

            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.sm,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 8,
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.memory_rounded, color: cs.primary),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              l10n.decoderSelectionHeader,
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    if (!isAudio) ...[
                      const SizedBox(height: 12),
                      Center(
                        child: SegmentedButton<String>(
                          segments: [
                            ButtonSegment<String>(
                              value: 'video',
                              icon: const Icon(Icons.videocam_rounded),
                              label: Text(l10n.videoDecoderTitle),
                            ),
                            ButtonSegment<String>(
                              value: 'audio',
                              icon: const Icon(Icons.audiotrack_rounded),
                              label: Text(l10n.audioDecoderTitle),
                            ),
                          ],
                          selected: {selectedTab},
                          onSelectionChanged: (newSelection) {
                            setSheetState(() {
                              selectedTab = newSelection.first;
                            });
                          },
                        ),
                      ),
                      const SizedBox(height: 8),
                    ] else ...[
                      Padding(
                        padding: const EdgeInsets.only(
                          left: 8,
                          top: 12,
                          bottom: 4,
                        ),
                        child: Text(
                          l10n.audioDecoderTitle,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                    for (final mode in MediaDecoderMode.values) ...[
                      ListTile(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        selected: currentMode == mode,
                        selectedTileColor: cs.primaryContainer.withValues(
                          alpha: 0.3,
                        ),
                        title: Text(
                          _MediaViewerScreenState._decoderModeLabel(l10n, mode),
                          style: TextStyle(
                            fontWeight: currentMode == mode
                                ? FontWeight.bold
                                : FontWeight.normal,
                          ),
                        ),
                        trailing: currentMode == mode
                            ? Icon(Icons.check_rounded, color: cs.primary)
                            : null,
                        onTap: () {
                          HapticFeedback.lightImpact();
                          final controller = ref.read(
                            fileManagerToolbarSettingsProvider(null).notifier,
                          );
                          if (isVideoSelected) {
                            controller.setMediaViewerVideoDecoderMode(mode);
                          } else {
                            controller.setMediaViewerAudioDecoderMode(mode);
                          }
                          Navigator.pop(sheetContext);
                        },
                      ),
                    ],
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            );
          },
        );
      },
    ).whenComplete(_menuClosed);
  }

  /// The audio equalizer. Changes reach the native audio pipeline on every
  /// slider tick, but are only persisted once the person lets go (see
  /// [AudioEqualizerSheet]), so dragging doesn't queue encrypted writes.
  void _showEqualizerSheet(BuildContext context) {
    _menuOpened();
    final settings = ref.read(
      fileManagerToolbarSettingsProvider(null).notifier,
    );
    final initial = ref
        .read(fileManagerToolbarSettingsProvider(null))
        .config
        .mediaViewerToolbarConfig
        .equalizer;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      // The band sliders are vertical, so a drag-to-dismiss sheet would fight
      // them for the same gesture. Tap outside / back still closes it.
      enableDrag: false,
      constraints: const BoxConstraints(maxWidth: 640),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppRadius.sheet),
        ),
      ),
      builder: (sheetContext) => AudioEqualizerSheet(
        initial: initial,
        onChanged: _applyEqualizerLive,
        onCommit: (value) => unawaited(settings.setMediaViewerEqualizer(value)),
      ),
    ).whenComplete(_menuClosed);
  }

  void _applyEqualizerLive(AudioEqualizerSettings value) {
    final controller = _playbackManager.activeController;
    if (controller == null) return;
    unawaited(
      controller.setEqualizer(value).catchError((Object error) {
        VeLog.w('MediaViewer', 'Could not apply the equalizer', error);
      }),
    );
  }

  void _showPlaylistOptionsMenu() {
    _menuOpened();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppRadius.sheet),
        ),
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final isPlaylist = _playlistController.isPlaylistMode;
            final folderScope = _playlistController.selectedFolder;
            final isThisFolderSelected =
                isPlaylist && folderScope == 'Current Folder Only';
            final isAllSelected = isPlaylist && folderScope == 'All';
            final cs = Theme.of(context).colorScheme;
            final l10n = context.l10n;

            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.sm,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 8,
                      ),
                      child: Text(
                        l10n.playlistOptionsTooltip,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: Icon(
                        Icons.folder_outlined,
                        color: isThisFolderSelected ? cs.primary : null,
                      ),
                      title: Text(l10n.thisFolderMenu),
                      trailing: isThisFolderSelected
                          ? Icon(Icons.check_rounded, color: cs.primary)
                          : null,
                      onTap: () async {
                        final targetFile = _playlistController.currentFile;
                        if (isThisFolderSelected) {
                          _playlistController.disablePlaylist();
                        } else {
                          await _playlistController.enablePlaylist(
                            'Current Folder Only',
                          );
                        }
                        final newIndex = _playlistController.playlist.indexOf(
                          targetFile,
                        );
                        if (newIndex != -1) {
                          _playlistController.updateIndex(newIndex);
                        }
                        _onPlaylistChanged();
                        setSheetState(() {});
                      },
                    ),
                    ListTile(
                      leading: Icon(
                        Icons.folder_copy_outlined,
                        color: isAllSelected ? cs.primary : null,
                      ),
                      title: Text(l10n.allInclSubfoldersMenu),
                      trailing: isAllSelected
                          ? Icon(Icons.check_rounded, color: cs.primary)
                          : null,
                      onTap: () async {
                        final targetFile = _playlistController.currentFile;
                        if (isAllSelected) {
                          _playlistController.disablePlaylist();
                        } else {
                          await _playlistController.enablePlaylist('All');
                        }
                        final newIndex = _playlistController.playlist.indexOf(
                          targetFile,
                        );
                        if (newIndex != -1) {
                          _playlistController.updateIndex(newIndex);
                        }
                        _onPlaylistChanged();
                        setSheetState(() {});
                      },
                    ),
                    if (_playlistController.isPlaylistMode) ...[
                      const Divider(),
                      ListTile(
                        leading: Icon(
                          Icons.shuffle_rounded,
                          color: _playlistController.isShuffled
                              ? cs.primary
                              : null,
                        ),
                        title: Text(
                          _playlistController.isShuffled
                              ? l10n.disableShuffleMenu
                              : l10n.shufflePlaylistMenu,
                        ),
                        trailing: Switch(
                          value: _playlistController.isShuffled,
                          onChanged: (_) {
                            final targetFile = _playlistController.currentFile;
                            _playlistController.toggleShuffle();
                            final newIndex = _playlistController.playlist
                                .indexOf(targetFile);
                            if (newIndex != -1) {
                              _playlistController.updateIndex(newIndex);
                            }
                            _onPlaylistChanged();
                            setSheetState(() {});
                          },
                        ),
                        onTap: () {
                          final targetFile = _playlistController.currentFile;
                          _playlistController.toggleShuffle();
                          final newIndex = _playlistController.playlist.indexOf(
                            targetFile,
                          );
                          if (newIndex != -1) {
                            _playlistController.updateIndex(newIndex);
                          }
                          _onPlaylistChanged();
                          setSheetState(() {});
                        },
                      ),
                      const SizedBox(height: 8),
                      Padding(
                        padding: const EdgeInsets.only(left: 8, bottom: 6),
                        child: Text(
                          l10n.playlistScrollModeMenu,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ),
                      SizedBox(
                        width: double.infinity,
                        child: SegmentedButton<PlaylistScrollMode>(
                          segments: PlaylistScrollMode.values.map((mode) {
                            return ButtonSegment<PlaylistScrollMode>(
                              value: mode,
                              icon: Icon(mode.icon, size: 16),
                              label: Text(
                                mode.getLocalizedLabel(l10n),
                                style: const TextStyle(fontSize: 11),
                              ),
                            );
                          }).toList(),
                          selected: {_scrollMode},
                          onSelectionChanged: (newSelection) {
                            final newMode = newSelection.first;
                            _sessionController.setScrollMode(newMode);
                            ref
                                .read(appSettingsServiceProvider)
                                .loadSettings()
                                .then((s) {
                                  ref
                                      .read(appSettingsServiceProvider)
                                      .saveSettings(
                                        s.copyWith(playlistScrollMode: newMode),
                                      );
                                });
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              if (mounted) {
                                _scrollToCurrentIndex(animate: false);
                              }
                            });
                            setSheetState(() {});
                          },
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            );
          },
        );
      },
    ).whenComplete(_menuClosed);
  }

  void _executeMediaAction(MediaViewerAction action) {
    if (widget._isPreviewOnly &&
        !_MediaViewerScreenState._archivePreviewActions.contains(action)) {
      return;
    }
    _startHideTimer();
    final fileIoApi = ref.read(vaultFileIoApiProvider);
    final isImage = MediaViewerConstants.isImage(
      _playlistController.currentFile,
    );

    switch (action) {
      case MediaViewerAction.playPause:
        final controller = _playbackManager.activeController;
        if (isImage) {
          _updatePlaybackMode(
            _autoAdvance
                ? VideoPlaybackMode.playOnce
                : VideoPlaybackMode.playAndAdvance,
          );
        } else if (controller != null) {
          if (controller.value.isPlaying) {
            controller.pause();
          } else {
            controller.play();
          }
        }
        break;
      case MediaViewerAction.previous:
        _navigateToPrev();
        break;
      case MediaViewerAction.next:
        _navigateToNext();
        break;
      case MediaViewerAction.mute:
        _startHideTimer();
        _sessionController.toggleMute();
        _playbackManager.activeController?.setVolume(_effectiveVolume);
        ref.read(appSettingsServiceProvider).loadSettings().then((appSettings) {
          ref
              .read(appSettingsServiceProvider)
              .saveSettings(appSettings.copyWith(videoMuted: _isMuted));
        });
        break;
      case MediaViewerAction.playbackMode:
        VideoPlaybackMode nextMode;
        if (!_playlistController.isPlaylistMode) {
          nextMode = _videoPlaybackMode == VideoPlaybackMode.loop
              ? VideoPlaybackMode.playOnce
              : VideoPlaybackMode.loop;
        } else {
          nextMode = switch (_videoPlaybackMode) {
            VideoPlaybackMode.playOnce => VideoPlaybackMode.loop,
            VideoPlaybackMode.loop => VideoPlaybackMode.playAndAdvance,
            VideoPlaybackMode.playAndAdvance => VideoPlaybackMode.playOnce,
          };
        }
        _updatePlaybackMode(nextMode);
        break;
      case MediaViewerAction.abLoop:
        if (!isImage) unawaited(_advanceAbLoop());
        break;
      case MediaViewerAction.thumbnailCarousel:
        if (_enableCarousel && _playlistController.isPlaylistMode) {
          _toggleCarousel();
        }
        break;
      case MediaViewerAction.rotate90:
        _startHideTimer();
        _sessionController.rotateClockwise(_playlistController.currentFile);
        break;
      case MediaViewerAction.pictureInPicture:
        if (!isImage) {
          unawaited(
            PlatformFeatures.isDesktop
                ? _floatVideoOnDesktop()
                : _enterPictureInPictureWindow(),
          );
        }
        break;
      case MediaViewerAction.lockControls:
        if (!_isEditingLayout) _setControlsLocked(true);
        break;
      case MediaViewerAction.playlistMenu:
        _showPlaylistOptionsMenu();
        break;
      case MediaViewerAction.bookmark:
        _toggleBookmarkCurrentFile();
        break;
      case MediaViewerAction.fileInfo:
        _showFileInfoHelper(fileIoApi);
        break;
      case MediaViewerAction.openWithApp:
        fileIoApi.openWithApp(
          widget.container,
          _playlistController.currentFile,
        );
        break;
      case MediaViewerAction.editImage:
        _openImageEditor();
        break;
      case MediaViewerAction.editVideo:
        _openVideoEditor();
        break;
      case MediaViewerAction.editAudio:
        _openAudioEditor();
        break;
      case MediaViewerAction.rename:
        _renameCurrentFile();
        break;
      case MediaViewerAction.delete:
        _deleteCurrentFile();
        break;
      case MediaViewerAction.diagnostics:
        _showDiagnostics(context);
        break;
      case MediaViewerAction.advancedSettings:
        _showAdvancedSettings(context, isImage);
        break;
      case MediaViewerAction.playbackSpeed:
        _showAdvancedSettings(context, isImage, initialPage: 'playbackSpeed');
        break;
      case MediaViewerAction.imageFit:
        _showAdvancedSettings(context, isImage, initialPage: 'imageFit');
        break;
      case MediaViewerAction.adjustments:
        _showAdjustmentsSheet(context);
        break;
      case MediaViewerAction.aspectRatio:
        _showAdvancedSettings(context, isImage, initialPage: 'aspectRatio');
        break;
      case MediaViewerAction.slideshowDelay:
        _showAdvancedSettings(context, isImage, initialPage: 'slideshowDelay');
        break;
      case MediaViewerAction.subtitles:
        _showAdvancedSettings(context, isImage, initialPage: 'subtitleTracks');
        break;
      case MediaViewerAction.audioTrack:
        _showAdvancedSettings(context, isImage, initialPage: 'audioTracks');
        break;
      case MediaViewerAction.decoder:
        _showDecoderPicker(context);
        break;
      case MediaViewerAction.equalizer:
        _showEqualizerSheet(context);
        break;
      case MediaViewerAction.screenOrientation:
        _cycleScreenOrientation();
        break;
    }
  }

  /// One press of the A-B repeat button: mark A, then mark B (which starts
  /// repeating the section), then clear it.
  Future<void> _advanceAbLoop() async {
    final controller = _playbackManager.activeController;
    if (controller == null ||
        controller.isDisposed ||
        !controller.value.isInitialized) {
      return;
    }

    // The position shown in the UI is up to 200ms stale; ask the player for
    // the exact one so A and B land where the person pressed.
    final position =
        await controller.getExactPosition() ?? controller.value.position;
    if (!mounted ||
        controller.isDisposed ||
        _playbackManager.activeController != controller) {
      return;
    }

    // Read after the await above, so a quick second press builds on the
    // state the first one left rather than on a stale copy.
    final result = _abLoopNotifier.value.advance(
      position,
      controller.value.duration,
    );
    final loop = result.state;

    if (result.event == AbLoopEvent.endTooClose) {
      // The playhead can't be before A (see setAbLoopStart), so this is a
      // press within a hair of A: nothing to set yet. A tick is enough to
      // show it registered.
      unawaited(HapticFeedback.lightImpact());
      return;
    }

    final l10n = context.l10n;
    final message = switch (result.event) {
      AbLoopEvent.startMarked => l10n.abLoopStartMarkedMessage(
        formatClockDuration(loop.a!),
      ),
      AbLoopEvent.loopStarted => l10n.abLoopStartedMessage(
        formatClockDuration(loop.a!),
        formatClockDuration(loop.b!),
      ),
      AbLoopEvent.cleared => l10n.abLoopClearedMessage,
      AbLoopEvent.endTooClose => '', // Returned above.
    };

    final previous = _abLoopNotifier.value;
    _abLoopNotifier.value = loop;
    try {
      switch (result.event) {
        case AbLoopEvent.loopStarted:
          await controller.setAbLoop(loop.a!, loop.b!);
          // B was marked at the playhead, so go straight back to A: the
          // section starts repeating now rather than after the rest of the
          // video has played.
          await controller.seekTo(loop.a!);
        case AbLoopEvent.cleared:
          await controller.clearAbLoop();
        case AbLoopEvent.startMarked:
          // From here on nothing before A can be picked.
          await controller.setAbLoopStart(loop.a!);
        case AbLoopEvent.endTooClose:
          break;
      }
    } catch (e) {
      VeLog.w('MediaViewer', 'A-B repeat update failed', e);
      _abLoopNotifier.value = previous;
      return;
    }

    if (!mounted) return;
    _showAbLoopToast(message);
  }

  /// Replaces whatever the A-B repeat toast is showing, so quick successive
  /// presses never queue up or wait for the previous message to go away.
  void _showAbLoopToast(String message) {
    _abLoopToastTimer?.cancel();
    _abLoopToast.value = message;
    _abLoopToastTimer = Timer(const Duration(milliseconds: 1600), () {
      _abLoopToast.value = null;
    });
  }

  void _showAdvancedSettings(
    BuildContext context,
    bool isImage, {
    String initialPage = 'main',
  }) {
    _menuOpened();

    final toolbarSettings = ref.read(fileManagerToolbarSettingsProvider(null));
    final mediaConfig = _effectiveToolbarConfig(
      toolbarSettings.config.mediaViewerToolbarConfig,
    );

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return AdvancedSettingsSheet(
          initialPage: initialPage,
          actions: mediaConfig.advancedSettingsActions,
          sessionKey: _sessionKey,
          isMuted: _isMuted,
          onExecuteAction: _executeMediaAction,
          onCustomizeControls: _openCustomizeControls,
          isPlaylistMode: _playlistController.isPlaylistMode,
          isImage: isImage,
          currentFileName: _playlistController.currentFile,
          initialRotation: _rotations[_playlistController.currentFile] ?? 0,
          initialImageFit: _imageFit,
          initialSlideshowDelaySeconds: _slideshowDelaySeconds,
          initialPlaybackSpeed: _playbackSpeed,
          initialAspectRatioMode: _videoAspectRatioMode,
          hasSubtitles: _playbackManager.isSubtitleAvailable(
            _playlistController.currentFile,
          ),
          initialSubtitlesEnabled: _subtitlesEnabled,
          initialSubtitleFontSize: _subtitleFontSize,
          initialSubtitleVerticalPosition: _subtitleVerticalPosition,
          videoController: _playbackManager.activeController,
          onSubtitleFontSizeChanged: (size) {
            _startHideTimer();
            _sessionController.setSubtitleFontSize(size);
          },
          onSubtitleVerticalPositionChanged: (pos) {
            _startHideTimer();
            _sessionController.setSubtitleVerticalPosition(pos);
          },
          onRotationChanged: (rot) {
            _startHideTimer();
            _sessionController.setRotation(
              _playlistController.currentFile,
              rot,
            );
          },
          onImageFitChanged: (fit) {
            _startHideTimer();
            _sessionController.setImageFit(fit);
          },
          onSlideshowDelayChanged: (delay) {
            _startHideTimer();
            _sessionController.setSlideshowDelaySeconds(delay);
            if (_autoAdvance) {
              _startSlideshowTimerIfNeeded();
            }
          },
          onPlaybackSpeedChanged: (speed) {
            _startHideTimer();
            _sessionController.setPlaybackSpeed(speed);
          },
          onAspectRatioModeChanged: (mode) {
            _startHideTimer();
            _sessionController.setVideoAspectRatioMode(mode);
          },
          onSubtitlesEnabledChanged: (enabled) {
            _startHideTimer();
            _sessionController.setSubtitlesEnabled(enabled);
          },
        );
      },
    ).whenComplete(_menuClosed);
  }

  /// Shows compact adjustment controls over the live preview, using a side
  /// panel in landscape and a short bottom sheet in portrait.
  void _showAdjustmentsSheet(BuildContext context) {
    _menuOpened();
    final path = _playlistController.currentFile;
    final size = MediaQuery.sizeOf(context);
    final isLandscape = size.width > size.height;
    final sheet = AdjustmentsSheet(
      sessionKey: _sessionKey,
      path: path,
      showApplyToAll: _playlistController.isPlaylistMode,
      onInteraction: _startHideTimer,
      isSidebar: isLandscape,
    );
    void onClosed() {
      // Never leave "hold to compare" stuck if the panel closes mid-press.
      if (mounted) _sessionController.setCompareOriginal(false);
      _menuClosed();
    }

    if (isLandscape) {
      final panelWidth = (size.width * 0.42).clamp(280.0, 420.0).toDouble();
      showGeneralDialog<void>(
        context: context,
        barrierDismissible: true,
        barrierLabel: MaterialLocalizations.of(
          context,
        ).modalBarrierDismissLabel,
        barrierColor: Colors.transparent,
        transitionDuration: MediaViewerConstants.animationDuration,
        pageBuilder: (context, animation, secondaryAnimation) => SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) => Align(
              alignment: AlignmentDirectional.centerEnd,
              child: Material(
                elevation: 16,
                borderRadius: const BorderRadiusDirectional.horizontal(
                  start: Radius.circular(24),
                ),
                clipBehavior: Clip.antiAlias,
                child: SizedBox(
                  width: panelWidth.clamp(0.0, constraints.maxWidth).toDouble(),
                  height: constraints.maxHeight,
                  child: sheet,
                ),
              ),
            ),
          ),
        ),
        transitionBuilder: (context, animation, secondaryAnimation, child) =>
            SlideTransition(
              position:
                  Tween<Offset>(
                    begin: Directionality.of(context) == TextDirection.rtl
                        ? const Offset(-1, 0)
                        : const Offset(1, 0),
                    end: Offset.zero,
                  ).animate(
                    CurvedAnimation(
                      parent: animation,
                      curve: Curves.easeOutCubic,
                    ),
                  ),
              child: child,
            ),
      ).whenComplete(onClosed);
    } else {
      showModalBottomSheet<void>(
        context: context,
        barrierColor: Colors.transparent,
        showDragHandle: true,
        isScrollControlled: true,
        constraints: BoxConstraints(maxHeight: size.height * 0.38),
        builder: (context) => sheet,
      ).whenComplete(onClosed);
    }
  }

  void _showDiagnostics(BuildContext context) {
    final controller = _playbackManager.activeController;
    if (controller == null) return;
    _menuOpened();
    showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.6),
      barrierDismissible: true,
      builder: (context) {
        return MediaDiagnosticsDialog(
          fileName: _playlistController.currentFile,
          controller: controller,
          playbackSpeed: _playbackSpeed,
        );
      },
    ).whenComplete(_menuClosed);
  }

  void _updateWakelock(bool enable) {
    if (_wakelockEnabled != enable) {
      _wakelockEnabled = enable;
      _fileIoApi.setKeepScreenOn(enable);
    }
  }

  void _dismissRouteAfterContainerLock() {
    // A locked vault must never leave a player behind.
    _backgroundPlaybackHandoff = null;
    if (_lockedRouteDismissalScheduled) return;
    _lockedRouteDismissalScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final route = ModalRoute.of(context);
      if (route == null || !route.isActive) return;
      // A media editor may be above this route. The editor handles the same
      // lock event and removes itself; removing this route too prevents its
      // locked black placeholder from being left over the dashboard.
      Navigator.of(context).removeRoute(route);
    });
  }
}
