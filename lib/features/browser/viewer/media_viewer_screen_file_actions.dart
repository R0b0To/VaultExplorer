part of 'media_viewer_screen.dart';

/// Per-file actions: bookmark, edit, rename and the file info sheet.
///
/// Moved out of [_MediaViewerScreenState] as is: an extension in the
/// same library reads and writes the state's private fields exactly as the
/// class did.
extension _MediaViewerFileActions on _MediaViewerScreenState {
  Future<void> _toggleBookmarkCurrentFile() async {
    final file = _playlistController.currentFile;
    final wasBookmark = _marks.isBookmarked(file);
    await _marksNotifier.toggleBookmarks(widget.container, [
      VaultBookmark(file, isDir: false),
    ], bookmark: !wasBookmark);
    if (mounted) {
      showAppSnackBar(
        context,
        message: wasBookmark
            ? context.l10n.unbookmarkedCount(1)
            : context.l10n.bookmarkedCount(1),
        tone: AppBannerTone.success,
      );
    }
  }

  Future<void> _openImageEditor() async {
    _menuOpened();
    final fileToEdit = _playlistController.currentFile;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ImageEditorScreen(
          container: widget.container,
          filePath: fileToEdit,
          thumbnailQuality: widget.thumbnailQuality,
        ),
      ),
    );
    if (!mounted || ref.read(mediaViewerLockProvider(widget.container.volId))) {
      return;
    }
    _menuClosed();
    // Whether or not anything was actually saved, force this item's
    // ImagePageItem to remount so it re-reads through FullResImageCache /
    // ThumbnailCacheService rather than keep showing whatever bytes it
    // already had in memory from before the editor opened. If nothing
    // changed, those caches weren't touched and the remount just re-hits
    // them -- cheap and correct either way.
    _sessionController.bumpImageReloadEpoch(fileToEdit);
  }

  Future<void> _openVideoEditor() async {
    final fileToEdit = _playlistController.currentFile;
    if (!MediaViewerConstants.isVideo(fileToEdit)) return;
    _menuOpened();
    // The app has a single native player. Release the viewer's before the
    // editor creates its own, and wait for that release to finish so it can't
    // land on top of the editor's player.
    _playbackManager.pauseActive();
    await _playbackManager.invalidateActive();
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => VideoEditorScreen(
          container: widget.container,
          filePath: fileToEdit,
        ),
      ),
    );
    if (!mounted || ref.read(mediaViewerLockProvider(widget.container.volId))) {
      return;
    }
    _menuClosed();
    // The editor has released the player by now (it does so before popping);
    // bring this video back up.
    unawaited(_activateCurrentMedia());
  }

  Future<void> _openAudioEditor() async {
    final fileToEdit = _playlistController.currentFile;
    if (!MediaViewerConstants.isAudio(fileToEdit)) return;
    _menuOpened();
    // The app has a single native player. Release the viewer's before the
    // editor creates its own, and wait for that release to finish so it can't
    // land on top of the editor's player.
    _playbackManager.pauseActive();
    await _playbackManager.invalidateActive();
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AudioEditorScreen(
          container: widget.container,
          filePath: fileToEdit,
        ),
      ),
    );
    if (!mounted || ref.read(mediaViewerLockProvider(widget.container.volId))) {
      return;
    }
    _menuClosed();
    // The editor has released the player by now (it does so before popping);
    // bring this track back up.
    unawaited(_activateCurrentMedia());
  }

  Future<void> _renameCurrentFile() async {
    _menuOpened();
    final fileToRename = _playlistController.currentFile;
    final lastSlash = fileToRename.lastIndexOf('/');
    final dirPath = lastSlash == -1 ? '' : fileToRename.substring(0, lastSlash);
    final baseName = lastSlash == -1
        ? fileToRename
        : fileToRename.substring(lastSlash + 1);

    var existingEntries = <RawEntry>[];
    try {
      final raw = await _fileIoApi.listDirectory(widget.container, dirPath);
      if (raw != null) {
        existingEntries = RawEntry.parseAll(raw);
      }
    } catch (e) {
      VeLog.w(
        'MediaViewerScreen',
        'Directory listing failed at ${VeLog.censorUri(dirPath)} during rename conflict check',
        e,
      );
    }

    final currentEntry = existingEntries.firstWhere(
      (e) => e.name == baseName,
      orElse: () =>
          RawEntry(name: baseName, isDir: false, sizeBytes: 0, modifiedSecs: 0),
    );

    if (!mounted) {
      _menuClosed();
      return;
    }

    await BrowserDialogs.showRename(
      context,
      container: widget.container,
      oldEntries: [currentEntry],
      existingEntries: existingEntries,
      currentDirPath: dirPath,
      onSuccess: () {},
      onEntryRenamed: (oldPath, newPath) {
        final rotation = _rotations[oldPath];
        if (rotation != null) {
          _sessionController.setRotation(newPath, rotation);
        }
        final adjustments = _session.adjustments[oldPath];
        if (adjustments != null) {
          _sessionController.moveAdjustments(oldPath, newPath);
        }
        _playbackManager.renameFile(oldPath, newPath);
        _playlistController.renameFile(oldPath, newPath);
        if (mounted) {
          showAppSnackBar(
            context,
            message: context.l10n.mediaFileRenamedMessage,
            tone: AppBannerTone.success,
          );
        }
      },
    );
    _menuClosed();
  }

  void _handleMediaError(String fileName) {
    if (fileName != _playlistController.currentFile) return;
    _cancelSlideshowTimer();
    _playbackManager.pauseActive();
  }

  Future<void> _showFileInfoHelper(VaultFileIoApi fileIoApi) async {
    _menuOpened();
    final file = _playlistController.currentFile;
    final lastSlash = file.lastIndexOf('/');
    final dirPath = lastSlash == -1 ? '' : file.substring(0, lastSlash);
    final baseName = lastSlash == -1 ? file : file.substring(lastSlash + 1);
    var existingEntries = <RawEntry>[];
    try {
      final raw = await fileIoApi.listDirectory(widget.container, dirPath);
      if (raw != null) {
        existingEntries = RawEntry.parseAll(raw);
      }
    } catch (e) {
      VeLog.w(
        'MediaViewerScreen',
        'Directory listing failed at ${VeLog.censorUri(dirPath)} during file info lookup',
        e,
      );
    }
    final currentEntry = existingEntries.firstWhere(
      (e) => e.name == baseName,
      orElse: () =>
          RawEntry(name: baseName, isDir: false, sizeBytes: 0, modifiedSecs: 0),
    );
    if (mounted) {
      await FileInfoSheet.show(
        context,
        container: widget.container,
        entry: currentEntry,
        currentDirPath: dirPath,
      );
    }
    _menuClosed();
  }
}
