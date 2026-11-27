part of 'directory_content_view.dart';

/// What a tap does: open a file in the right viewer or editor, or hand it to another app.
///
/// Moved out of [_DirectoryContentViewState] unchanged: an extension in the
/// same library reads and writes the state's private fields exactly as the
/// class did.
extension _DirectoryOpenActions on _DirectoryContentViewState {
  void _handleDirTap(RawEntry entry) {
    if (_handleModifierClick(entry)) return;
    if (_handleDoubleClickGate(entry)) return;
    _signalActivity();
    if (isSelectionMode) {
      toggleSelectItem(entry);
    } else {
      _enterDirectory(entry);
    }
  }

  /// Tapping directly on a row's leading icon/thumbnail always toggles that
  /// item's selection (entering selection mode on the first tap, same as a
  /// long-press would), regardless of whether the row body would otherwise
  /// open the item. This mirrors [_handleItemLongPress]'s haptic feedback
  /// so both entry points into selection feel the same.
  void _handleIconTap(RawEntry entry) {
    _signalActivity();
    if (!isSelectionMode && _selectedBrowserEntryCount > 0) {
      if (entry.isDir) {
        _handleDirTap(entry);
      } else {
        unawaited(_handleFileTap(entry));
      }
      return;
    }
    HapticFeedback.selectionClick();
    toggleSelectItem(entry);
  }

  /// Returns the effective target filename for a Cryptomator shortcut.
  ///
  /// Content is still opened through [linkPath] so the native vault layer
  /// follows the link. We only resolve the name here: dispatch, MIME/type
  /// detection and viewers need the target extension rather than the
  /// shortcut's arbitrary display name. Resolve chained links too, but never
  /// allow a target to escape the vault or loop forever.
  Future<String> _effectiveOpenName(RawEntry entry, String linkPath) async {
    if (!entry.isSymlink || !mayHaveVaultSymbolicLinks(widget.container)) {
      return entry.name;
    }

    final api = ref.read(vaultFileIoApiProvider);
    var currentPath = linkPath;
    final visited = <String>{};
    for (var hop = 0; hop < 40; hop++) {
      if (!visited.add(currentPath)) return entry.name;
      final target = await api.readVaultSymlink(widget.container, currentPath);
      if (target == null || target.isEmpty) {
        return p.posix.basename(currentPath);
      }
      // Cryptomator shortcuts are deliberately confined to this vault.
      if (p.posix.isAbsolute(target)) return entry.name;
      final resolved = p.posix.normalize(
        p.posix.join(p.posix.dirname(currentPath), target),
      );
      if (resolved == '..' ||
          resolved.startsWith('../') ||
          p.posix.isAbsolute(resolved)) {
        return entry.name;
      }
      currentPath = resolved;
    }
    return entry.name;
  }

  MediaKind? _mediaKindForName(String fileName) {
    if (MediaViewerConstants.isImage(fileName)) return MediaKind.image;
    if (MediaViewerConstants.isVideo(fileName)) return MediaKind.video;
    if (MediaViewerConstants.isAudio(fileName)) return MediaKind.audio;
    return null;
  }

  Future<void> _handleFileTap(RawEntry entry) async {
    if (_handleModifierClick(entry)) return;
    if (_handleDoubleClickGate(entry)) return;
    ThumbnailConcurrency.videoLimiter.cancelAll();
    _signalActivity();
    if (isSelectionMode) {
      toggleSelectItem(entry);
      return;
    }
    final fullPath = _fullPathOf(entry);
    final openName = await _effectiveOpenName(entry, fullPath);
    if (!mounted) return;
    if (MediaViewerConstants.isVideo(openName)) {
      await PlaybackThrottleController.setActive(true);
    }
    final parts = openName.split('.');
    final ext =
        ArchiveService.splitPartExtension(openName) ??
        (parts.length > 1
            ? parts.last.toLowerCase().replaceFirst(RegExp(r'^\.+'), '').trim()
            : '');
    if (ArchiveService.opensOnTap(ext)) {
      if (_archiveContext == null) {
        await _openArchive(fullPath, openName);
        return;
      }
      // Inside an archive the path is virtual, so the file can't be opened
      // like a container file; it is staged and opened on top of this one.
      // (A split archive part has no siblings to be read with, so it falls
      // through to the ordinary in-archive handling below.)
      if (ArchiveService.canOpenNested(openName, ext)) {
        await _openNestedArchive(fullPath, openName);
        return;
      }
    }
    if (_archiveContext != null) {
      _signalActivity();
      _navNotifier.setLoading(true);
      try {
        final archiveRootPath =
            _pathStack[_archiveContext!.pathStackEntryIndex].fatPath;
        String subPath = '';
        if (fullPath.length > archiveRootPath.length) {
          subPath = fullPath.substring(archiveRootPath.length);
          if (subPath.startsWith('/')) subPath = subPath.substring(1);
        }
        if (mounted) {
          final opensInNativeViewer =
              ext == 'pdf' ||
              MediaViewerConstants.isImage(openName) ||
              MediaViewerConstants.isVideo(openName) ||
              MediaViewerConstants.isAudio(openName);
          final opensInTextEditor = const {
            'txt',
            'md',
            'markdown',
            'csv',
            'json',
            'xml',
          }.contains(ext);
          if (opensInNativeViewer || opensInTextEditor) {
            final stageResult = await _stageArchiveEntryWithPassword(subPath);
            final previewPath = stageResult?.path;
            if (previewPath != null) {
              if (opensInTextEditor) {
                await _openArchiveTextPreview(openName, previewPath);
              } else {
                await _openArchivePreview(openName, previewPath);
              }
            } else if (mounted) {
              _navNotifier.setLoading(false);
              if (stageResult != null) {
                _setStatus(
                  context.l10n.failedToReadFileFromArchive,
                  error: true,
                );
              }
            }
          } else {
            final extractResult = await _extractArchiveEntryWithPassword(
              subPath,
            );
            _navNotifier.setLoading(false);
            if (extractResult?.status == ArchiveOpenStatus.ok &&
                extractResult?.data != null) {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => SkinAreaScope(
                    area: SkinArea.files,
                    child: ArchiveFileViewer(
                      bytes: extractResult!.data!,
                      fileName: openName,
                    ),
                  ),
                ),
              );
            } else if (extractResult != null) {
              _setStatus(context.l10n.failedToReadFileFromArchive, error: true);
            }
          }
        }
      } catch (e) {
        if (mounted) {
          _navNotifier.setLoading(false);
          _setStatus(
            context.l10n.failedToExtractFile('${e.runtimeType}'),
            error: true,
          );
        }
      }
      return;
    }
    if (VaultItemType.values.any((t) => t.name.toLowerCase() == ext)) {
      final item = await ref
          .read(vaultItemsServiceProvider)
          .loadItem(widget.container, fullPath);
      if (item != null) {
        final baseName = openName.substring(0, openName.lastIndexOf('.'));
        item.title = baseName;
        if (mounted) {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => VaultItemDetailScreen(
                container: widget.container,
                item: item,
                filePath: fullPath,
              ),
            ),
          );
          // The vault may have been locked (or the tab closed) while the
          // detail screen was open; `_currentDirPath` reads Riverpod state
          // through this widget's ref, which throws once unmounted.
          if (!mounted) return;
          _loadDirectoryContents(_currentDirPath);
        }
      } else {
        _setStatus(context.l10n.failedToReadSecureItem, error: true);
      }
      return;
    }
    final settings = await ref.read(appSettingsServiceProvider).loadSettings();
    final pref = settings.extensionPreferences[ext];
    // HTML is still a native, session-based viewer with no local-storage
    // counterpart (see LocalFileIoBackend's doc comment) -- checked ahead
    // of `pref` so a per-extension preference saved while browsing a real
    // vault (e.g. "always use the built-in viewer for .html") can't route
    // a local file into a viewer that can't render it. The device's own
    // browser already renders a real, already-plaintext HTML file fine, so
    // hand it off there instead. Video and audio are both exempt: the
    // native player reads local files directly off disk via its own local
    // branch (see NativePlayerManager.kt's buildMediaSource --
    // DefaultDataSource.Factory + Uri.fromFile), so they play in-app
    // exactly like vault content. PDF is exempt too: PdfViewerScreen has
    // its own isLocalStorage branch (VaultLocalShareApi.getLocalFileUri ->
    // PdfViewerRouter's localUri path), so it also renders in-app.
    final needsSystemAppForLocal =
        widget.container.isLocalStorage && (ext == 'html' || ext == 'htm');
    // Which viewer/action applies is decided by decideFileOpenAction
    // (file_open_dispatch.dart) -- a pure function of ext/pref/these two
    // booleans, extracted so the branch priority (needsSystemAppForLocal
    // first, then a saved preference, then the extension fallback) is
    // unit-tested directly instead of only reachable by tapping files in
    // a running app. This screen just computes the inputs and performs
    // whichever Navigator.push/side effect the result calls for.
    final action = decideFileOpenAction(
      ext: ext,
      extensionPreference: pref,
      needsSystemAppForLocal: needsSystemAppForLocal,
      isSupportedMedia: _isSupportedMedia(openName),
    );
    switch (action) {
      case OpenInEditor():
        if (!mounted) return;
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => TextEditorScreen(
              container: widget.container,
              filePath: fullPath,
            ),
          ),
        );
        if (!mounted) return;
        _loadDirectoryContents(_currentDirPath);
      case OpenInMediaViewer():
        // The media viewer classifies items by the path it receives. For a
        // shortcut that path is deliberately the link path (so reads still
        // go through the vault's link resolver), whose extension may differ
        // from the target. Pin the target's media kind to the link path for
        // the lifetime of the viewer so an image shortcut named `movie.mp4`
        // is still treated as an image, and vice versa.
        final shortcutMediaKind = entry.isSymlink
            ? _mediaKindForName(openName)
            : null;
        if (shortcutMediaKind == null) {
          await _openMediaViewer(openName, fullPath);
        } else {
          await MediaViewerConstants.withKindOverride(
            fullPath,
            shortcutMediaKind,
            // A folder playlist contains other paths whose shortcut targets
            // have not been resolved here. Keep this launch focused on the
            // selected shortcut so no neighbouring link is classified from
            // its display name.
            () => _openMediaViewer(
              openName,
              fullPath,
              singleFile: entry.isSymlink,
            ),
          );
        }
      case OpenInPdfViewer():
        await _openPdfViewer(fullPath);
      case OpenInHtmlViewer():
        _openHtmlViewer(fullPath);
      case OpenInComicReader():
        await _openBook(openName, fullPath, BookKind.comic);
      case OpenInEpubReader():
        await _openBook(openName, fullPath, BookKind.epub);
      case OpenWithSystemApp(packageName: final packageName):
        _openFileWithApp(
          openName,
          fullPath,
          packageName: packageName,
          // A saved external-app preference can fall back to the chooser (the
          // app is gone, lives in another profile, or was never captured).
          // Learn the app picked there so the preference repairs itself.
          appPickRequestId: (mounted && isExternalAppPreference(pref))
              ? armRememberedAppCapture(ref, ext)
              : null,
        );
      case InstallApk():
        await _installApk(openName, fullPath);
      case OpenAsArchive():
        // An APK is a ZIP; the archive browser sniffs the format from the
        // bytes, so the same path a .zip takes works unchanged.
        await _openArchive(fullPath, openName);
      case ShowApkOpenChooser():
        if (!mounted) return;
        await _showApkOpenChooser(openName, fullPath, ext);
      case ShowOpenWithDialog():
        if (!mounted) return;
        await _showOpenWithDialog(openName, fullPath, ext, settings);
    }
  }

  Future<void> _openPdfViewer(String fullPath) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            PdfViewerScreen(container: widget.container, filePath: fullPath),
      ),
    );
    if (!mounted) return;
    _loadDirectoryContents(_currentDirPath);
  }

  /// Opens a `.cbz`/`.epub` (or a comic under another name) in the in-app
  /// reader. The reader takes over the book session and closes it itself.
  ///
  /// Anything the reader cannot take -- a real RAR, a password-protected
  /// archive, an exotic compression method -- goes to the archive browser
  /// instead, where the pages can still be viewed one at a time.
  Future<void> _openBook(String name, String fullPath, BookKind kind) async {
    final api = ref.read(vaultBookApiProvider);
    _navNotifier.setLoading(true);
    BookOpenResult result;
    try {
      result = await api.open(
        container: widget.container,
        path: fullPath,
        kind: kind,
      );
    } catch (e) {
      if (!mounted) return;
      _navNotifier.setLoading(false);
      _setStatus(context.l10n.bookReaderOpenFailed, error: true);
      return;
    }
    final token = result.token;
    if (!mounted) {
      if (token != null) unawaited(api.close(token));
      return;
    }
    _navNotifier.setLoading(false);

    Future<void> fallBackToArchive() async {
      if (token != null) unawaited(api.close(token));
      await _openArchive(fullPath, name);
    }

    if (result.status != BookOpenStatus.ok || token == null) {
      if (result.status.archiveBrowserMayHelp) {
        await fallBackToArchive();
      } else {
        _setStatus(context.l10n.bookReaderOpenFailed, error: true);
      }
      return;
    }

    switch (kind) {
      case BookKind.comic:
        if (result.hasEncryptedEntries) {
          await fallBackToArchive();
          return;
        }
        final pages = comicPageNames(result.entries);
        if (pages.isEmpty) {
          unawaited(api.close(token));
          _setStatus(context.l10n.comicNoPages, error: true);
          return;
        }
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ComicReaderScreen(
              container: widget.container,
              title: name,
              filePath: fullPath,
              token: token,
              pages: pages,
            ),
          ),
        );
      case BookKind.epub:
        final info = result.epub;
        if (info == null || info.spine.isEmpty) {
          unawaited(api.close(token));
          _setStatus(context.l10n.bookReaderOpenFailed, error: true);
          return;
        }
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => EpubReaderScreen(
              container: widget.container,
              fallbackTitle: name,
              filePath: fullPath,
              token: token,
              info: info,
            ),
          ),
        );
    }
  }

  void _openHtmlViewer(String fullPath) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            HtmlViewerScreen(container: widget.container, filePath: fullPath),
      ),
    );
  }

  Route<void> _buildMediaViewerRoute({
    required List<String> mediaFiles,
    required int initialIndex,
    MountedContainer? container,
    bool isArchivePreview = false,
  }) {
    return PageRouteBuilder<void>(
      opaque: false,
      barrierColor: Colors.transparent,
      transitionDuration: Duration.zero,
      reverseTransitionDuration: const Duration(milliseconds: 250),
      pageBuilder: (context, animation, secondaryAnimation) => MediaViewerScreen(
        container: container ?? widget.container,
        mediaFiles: mediaFiles,
        initialIndex: initialIndex,
        startingFolder: isArchivePreview ? '' : _currentDirPath,
        thumbnailQuality: _resolvedThumbnailQuality,
        thumbnailCacheMode: isArchivePreview
            ? ThumbnailCacheMode.disabled
            : _resolvedThumbnailCacheMode,
        mediaFilter: _currentFilter,
        sortBy: sortBy,
        sortAscending: sortAscending,
        pinnedPaths: _pinnedPaths,
        onCurrentFileChanged: isArchivePreview
            ? null
            : (newFile) {
                // Intentionally avoid scrolling background directory during swipe
              },
        isArchivePreview: isArchivePreview,
      ),
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        return FadeTransition(
          opacity: CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
            reverseCurve: Curves.easeInCubic,
          ),
          child: child,
        );
      },
    );
  }

  Future<void> _editImage(String fileName, String fullPath) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ImageEditorScreen(
          container: widget.container,
          filePath: fullPath,
          thumbnailQuality: _resolvedThumbnailQuality,
        ),
      ),
    );
    if (!mounted) return;
    _loadDirectoryContents(_currentDirPath);
  }

  Future<void> _editVideo(String fullPath) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            VideoEditorScreen(container: widget.container, filePath: fullPath),
      ),
    );
    if (!mounted) return;
    // The editor writes new files next to the original.
    _loadDirectoryContents(_currentDirPath);
  }

  Future<void> _editAudio(String fullPath) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            AudioEditorScreen(container: widget.container, filePath: fullPath),
      ),
    );
    if (!mounted) return;
    // The editor writes new files next to the original.
    _loadDirectoryContents(_currentDirPath);
  }

  /// Opens [fullPath] in the media viewer. [forceKind] ("Open as...") makes
  /// the viewer treat the file as that kind regardless of its extension; the
  /// file then opens on its own, since a playlist built from the folder's
  /// other media would have no reason to include a file the extension filter
  /// does not recognise.
  Future<void> _openMediaViewer(
    String fileName,
    String fullPath, {
    MediaKind? forceKind,
    bool singleFile = false,
  }) async {
    if (forceKind != null) {
      await MediaViewerConstants.withKindOverride(
        fullPath,
        forceKind,
        () => _openMediaViewer(fileName, fullPath, singleFile: true),
      );
      return;
    }
    List<String> mediaFiles = [fullPath];
    int initialIndex = 0;

    final openStopwatch = Stopwatch()..start();
    if (!singleFile && _toolbarConfig.autoStartPlaylistMode) {
      final query = _searchQuery.trim().toLowerCase();
      final displayedListing = _getFilteredAndSortedItems(
        query,
        _activePlaceholders,
        _pendingDeletedNames,
      );

      final resolvedMedia = <String>[];
      int foundIdx = -1;
      for (final item in displayedListing.items) {
        if (item.isDir || !_isSupportedMedia(item.name)) continue;
        final itemPath =
            (_searchActive && _isDeepSearch && item.name.contains('/'))
            ? item.name
            : (_currentDirPath.isEmpty
                  ? item.name
                  : '$_currentDirPath/${item.name}');
        if (itemPath == fullPath) {
          foundIdx = resolvedMedia.length;
        }
        resolvedMedia.add(itemPath);
      }

      if (foundIdx != -1) {
        mediaFiles = resolvedMedia;
        initialIndex = foundIdx;
      }
    }
    VeLog.d(
      'MediaViewer',
      'Prepared playlist of ${mediaFiles.length} items in ${openStopwatch.elapsedMilliseconds}ms',
    );

    final initialOffset = _browserScrollController.hasClients
        ? _browserScrollController.offset
        : null;
    String lastViewedFile = fullPath;
    bool filesDeletedInViewer = false;

    final result = await Navigator.push<bool>(
      context,
      PageRouteBuilder<bool>(
        opaque: false,
        barrierColor: Colors.transparent,
        transitionDuration: Duration.zero,
        reverseTransitionDuration: const Duration(milliseconds: 250),
        pageBuilder: (context, animation, secondaryAnimation) =>
            MediaViewerScreen(
              container: widget.container,
              mediaFiles: mediaFiles,
              initialIndex: initialIndex,
              startingFolder: _currentDirPath,
              thumbnailQuality: _resolvedThumbnailQuality,
              thumbnailCacheMode: _resolvedThumbnailCacheMode,
              mediaFilter: _currentFilter,
              sortBy: sortBy,
              sortAscending: sortAscending,
              pinnedPaths: _pinnedPaths,
              onCurrentFileChanged: (newFile) {
                lastViewedFile = newFile;
              },
              onFileDeleted: (_) => filesDeletedInViewer = true,
            ),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(
            opacity: CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
              reverseCurve: Curves.easeInCubic,
            ),
            child: child,
          );
        },
      ),
    );

    if (!mounted) return;

    // If the user viewed the same file without swiping to another,
    // restore the exact pixel offset so no sub-pixel rounding drift occurs.
    if (lastViewedFile == fullPath &&
        initialOffset != null &&
        _browserScrollController.hasClients) {
      // Navigator completes the pushed route's result while its reverse
      // transition is being finalized. Defer the scroll notification until
      // the next frame so it cannot bubble through an inactive route element
      // (which can happen when returning from an external app as well).
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_browserScrollController.hasClients) return;
        if (ModalRoute.of(context)?.isCurrent == false) return;

        final position = _browserScrollController.position;
        if (!position.hasContentDimensions) return;
        final restoredOffset = initialOffset
            .clamp(position.minScrollExtent, position.maxScrollExtent)
            .toDouble();
        if ((position.pixels - restoredOffset).abs() > 0.5) {
          _browserScrollController.jumpTo(restoredOffset);
        }
      });
    } else if (lastViewedFile != fullPath &&
        _browserScrollController.hasClients) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_browserScrollController.hasClients) return;
        if (ModalRoute.of(context)?.isCurrent == false) return;
        _scrollToItem(lastViewedFile);
      });
    }

    // Only reload directory contents if files were actually modified/deleted in the viewer
    if (result == true || filesDeletedInViewer) {
      _loadDirectoryContents(_currentDirPath, refresh: true);
      _loadToolbarConfig();
    }
  }

  /// Asks whether an `.apk` should go to the package installer or open as a
  /// ZIP, and (optionally) remembers the answer for `.apk` -- stored as the
  /// `'installer'` / `'archive'` extension preferences, which
  /// [decideFileOpenAction] reads on the next tap and the file-associations
  /// settings list can clear.
  Future<void> _showApkOpenChooser(
    String fileName,
    String fullPath,
    String ext,
  ) async {
    final cleanExt = ext.toLowerCase().replaceFirst(RegExp(r'^\.+'), '').trim();
    final choice = await OpenWithDialog.showApkChooser(
      context,
      fileName: fileName,
      ext: cleanExt,
    );
    final action = choice.action;
    if (action == null) return;
    if (choice.remember && cleanExt.isNotEmpty) {
      await _saveExtensionPreference(cleanExt, action);
    }
    if (!mounted) return;
    if (action == 'installer') {
      await _installApk(fileName, fullPath);
    } else if (action == 'archive') {
      await _openArchive(fullPath, fileName);
    }
  }

  Future<void> _showOpenWithDialog(
    String fileName,
    String fullPath,
    String ext,
    AppSettings settings,
  ) async {
    // Every explicit "Open with" -- the item's 3-dots sheet and the selection
    // menu both end up here -- asks installer vs. ZIP for an APK, even when a
    // choice was remembered for plain taps. It's the way back to the other
    // option once "remember" has been ticked.
    if (ext.toLowerCase() == 'apk') {
      await _showApkOpenChooser(fileName, fullPath, ext);
      return;
    }
    final choice = await OpenWithDialog.show(
      context,
      fileName: fileName,
      ext: ext,
    );
    final cleanExt = ext.toLowerCase().replaceFirst(RegExp(r'^\.+'), '').trim();

    if (choice.action == 'editor') {
      if (choice.remember && cleanExt.isNotEmpty) {
        await _saveExtensionPreference(cleanExt, 'editor');
      }
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) =>
              TextEditorScreen(container: widget.container, filePath: fullPath),
        ),
      );
      _loadDirectoryContents(_currentDirPath);
    } else if (choice.action == 'media') {
      if (choice.remember && cleanExt.isNotEmpty) {
        await _saveExtensionPreference(cleanExt, 'media');
      }
      if (!mounted) return;
      await _openMediaViewer(fileName, fullPath);
    } else if (choice.action == 'external') {
      String? appPickRequestId;
      if (choice.remember && cleanExt.isNotEmpty) {
        // Saved as plain 'external' first so the choice sticks even if the
        // system chooser never reports which app was picked; the pick, when it
        // does arrive, upgrades it to that app (see armRememberedAppCapture).
        await _saveExtensionPreference(cleanExt, 'external');
        if (!mounted) return;
        appPickRequestId = armRememberedAppCapture(ref, cleanExt);
      }
      _openFileWithApp(fileName, fullPath, appPickRequestId: appPickRequestId);
    } else if (choice.action == 'open_as') {
      final mime = choice.mimeType;
      if (mime == null) return;
      if (choice.openExternally) {
        _openFileWithApp(fileName, fullPath, mimeType: mime);
        return;
      }
      if (!mounted) return;
      await _openFileAs(fileName, fullPath, mime);
    }
  }

  /// "Open as..." in the app's own viewers, whatever the file is called.
  ///
  /// The type is a hint the user gave, not something the app can check
  /// up front: a `.dat` the user says is a video may well not be one. Each
  /// target therefore opens through the same screen a correctly named file
  /// would, and any failure surfaces there (the player's error state, the
  /// archive browser's "failed to read archive" status) instead of being
  /// pre-judged here by extension. [mimeType] is one of the values the
  /// "Open as" dialog produces.
  Future<void> _openFileAs(
    String fileName,
    String fullPath,
    String mimeType,
  ) async {
    _signalActivity();
    switch (mimeType) {
      case 'text/plain':
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => TextEditorScreen(
              container: widget.container,
              filePath: fullPath,
            ),
          ),
        );
        if (mounted) _loadDirectoryContents(_currentDirPath);
      case 'image/*':
        await _openMediaViewer(fileName, fullPath, forceKind: MediaKind.image);
      case 'video/*':
        await _openMediaViewer(fileName, fullPath, forceKind: MediaKind.video);
      case 'audio/*':
        await _openMediaViewer(fileName, fullPath, forceKind: MediaKind.audio);
      case 'application/zip':
        // The archive browser sniffs the format from the bytes (zip, 7z, rar,
        // tar...), same as the APK-as-ZIP path, and asks for a password
        // itself when needed.
        await _openArchive(fullPath, fileName);
      default:
        _openFileWithApp(fileName, fullPath, mimeType: mimeType);
    }
  }

  void _cancelMediaScan() => _mediaScanToken?.cancel();

  bool _isSupportedMedia(String fileName) =>
      MediaViewerConstants.isSupported(fileName);

  /// Hands an APK to the system package installer (see
  /// [VaultFileIoApi.installApk]).
  ///
  /// The two non-install outcomes -- the user hasn't allowed this app to
  /// install apps, or the device has no installer at all -- are already
  /// surfaced natively, next to the settings page the first one opens, so
  /// they're deliberately not reported a second time here. Only an
  /// outright failure of the call gets a status message.
  Future<void> _installApk(String cleanName, String fullPath) async {
    _signalActivity();
    try {
      final outcome = await ref
          .read(vaultFileIoApiProvider)
          .installApk(widget.container, fullPath);
      if (outcome == null && mounted) {
        _setStatus(context.l10n.couldNotOpenFile(cleanName), error: true);
      }
    } catch (_) {
      if (mounted) {
        _setStatus(context.l10n.couldNotOpenFile(cleanName), error: true);
      }
    }
  }

  /// Hands the file to another app: [packageName] directly when given,
  /// otherwise through the system chooser. [appPickRequestId] (from
  /// [armRememberedAppCapture]) makes the chooser report the app picked there
  /// so it can be remembered.
  Future<void> _openFileWithApp(
    String cleanName,
    String fullPath, {
    String? packageName,
    String? mimeType,
    String? appPickRequestId,
  }) async {
    _signalActivity();
    try {
      // Local storage has no vault session to serve the file from --
      // VaultLocalShareApi exposes the real path directly via its own
      // FileProvider instead (see vault_local_share_api.dart).
      final ok = widget.container.isLocalStorage
          ? await ref
                .read(vaultLocalShareApiProvider)
                .openLocalFileWithApp(
                  p.join(widget.container.uri, fullPath),
                  mimeType: mimeType,
                  packageName: packageName,
                  requestId: appPickRequestId,
                )
          : await ref
                .read(vaultFileIoApiProvider)
                .openWithApp(
                  widget.container,
                  fullPath,
                  packageName: packageName,
                  mimeType: mimeType,
                  requestId: appPickRequestId,
                );
      if (!ok && mounted) {
        _setStatus(context.l10n.noAppFoundForFileType, error: true);
      }
    } catch (_) {
      if (mounted) {
        _setStatus(context.l10n.couldNotOpenFile(cleanName), error: true);
      }
    }
  }
}
