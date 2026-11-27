part of 'directory_content_view.dart';

/// Opening, previewing, compressing and extracting archives.
///
/// Moved out of [_DirectoryContentViewState] unchanged: an extension in the
/// same library reads and writes the state's private fields exactly as the
/// class did.
extension _DirectoryArchiveActions on _DirectoryContentViewState {
  Future<void> _openArchive(String fullPath, String archiveName) async {
    // Remember where the containing folder is scrolled to, so that leaving the
    // archive restores it exactly like leaving a sub-folder does. Read once,
    // before the (possibly repeated) open attempts below.
    final currentOffset = _browserScrollController.hasClients
        ? _browserScrollController.offset
        : 0.0;
    String? passphrase;
    try {
      while (true) {
        final ctx = await _navNotifier.openArchive(
          widget.container,
          fullPath,
          archiveName,
          passphrase: passphrase,
          layoutMode: _getLayoutModeForFolder(fullPath),
          onActivity: _signalActivity,
          currentScrollOffset: currentOffset,
        );

        if (ctx.status == ArchiveOpenStatus.ok) {
          final archiveSort = _getSortStateForFolder(fullPath);
          _sortNotifier.restore(archiveSort.sortBy, archiveSort.sortAscending);
          // The archive root starts at the top, not at the parent's offset.
          if (mounted) _resetBrowserScrollController(initialOffset: 0.0);
          _clearSearch();
          return;
        }

        if (!mounted) return;
        final entered = await BrowserDialogs.showArchivePasswordPrompt(
          context,
          wrongPassword: ctx.status == ArchiveOpenStatus.wrongPassphrase,
        );
        if (entered == null) return;
        passphrase = entered;
      }
    } catch (e) {
      if (mounted) {
        _setStatus(
          context.l10n.failedToReadArchive('${e.runtimeType}'),
          error: true,
        );
      }
    }
  }

  /// Opens an archive that is an entry of the archive being browsed (a `.zip`
  /// inside a `.7z`, say), on top of it. Going back leaves it and returns to
  /// the outer archive.
  ///
  /// The entry can't be read in place: ZIP and 7z need random access, which
  /// an entry that is still compressed inside its parent doesn't offer. It is
  /// streamed into the same app-private temporary file archive previews use
  /// and browsed from there; that file is securely wiped when the nested
  /// archive is closed (see [StagedArchiveSource]).
  Future<void> _openNestedArchive(String fullPath, String archiveName) async {
    final parent = _archiveContext;
    if (parent == null) return;
    if (parent.nestingDepth + 1 > ArchiveContext.maxNestingDepth) {
      _setStatus('Archives are nested too deeply to open', error: true);
      return;
    }

    final archiveRootPath = _pathStack[parent.pathStackEntryIndex].fatPath;
    var subPath = '';
    if (fullPath.length > archiveRootPath.length) {
      subPath = fullPath.substring(archiveRootPath.length);
      if (subPath.startsWith('/')) subPath = subPath.substring(1);
    }
    // Read before the awaits below, like _openArchive does, so leaving the
    // nested archive restores the scroll position of this folder.
    final currentOffset = _browserScrollController.hasClients
        ? _browserScrollController.offset
        : 0.0;

    _signalActivity();
    _navNotifier.setLoading(true);
    StagedArchiveSource? source;
    try {
      final staged = await _stageArchiveEntryWithPassword(subPath);
      final stagedPath = staged?.path;
      if (stagedPath == null) {
        if (mounted) {
          _navNotifier.setLoading(false);
          if (staged != null) {
            _setStatus(context.l10n.failedToReadFileFromArchive, error: true);
          }
        }
        return;
      }
      final stagedSource = ArchiveService.adoptStagedArchive(stagedPath);
      source = stagedSource;
      if (!mounted) return;

      String? passphrase;
      while (true) {
        final ctx = await _navNotifier.openNestedArchive(
          stagedSource,
          fullPath,
          archiveName,
          passphrase: passphrase,
          layoutMode: _getLayoutModeForFolder(fullPath),
          onActivity: _signalActivity,
          currentScrollOffset: currentOffset,
        );

        if (ctx.status == ArchiveOpenStatus.ok) {
          // The nested archive owns the temporary copy from here on.
          source = null;
          final archiveSort = _getSortStateForFolder(fullPath);
          _sortNotifier.restore(archiveSort.sortBy, archiveSort.sortAscending);
          if (mounted) _resetBrowserScrollController(initialOffset: 0.0);
          _clearSearch();
          return;
        }

        if (!mounted) return;
        final entered = await BrowserDialogs.showArchivePasswordPrompt(
          context,
          wrongPassword: ctx.status == ArchiveOpenStatus.wrongPassphrase,
        );
        if (entered == null) return;
        passphrase = entered;
      }
    } catch (e) {
      if (mounted) {
        _navNotifier.setLoading(false);
        _setStatus(
          context.l10n.failedToReadArchive('${e.runtimeType}'),
          error: true,
        );
      }
    } finally {
      // Still ours only when the open failed or was abandoned: wipe the copy.
      source?.release();
    }
  }

  Future<ArchiveEntryExtractResult?> _extractArchiveEntryWithPassword(
    String entryPath,
  ) async {
    final currentArchive = _archiveContext;
    if (currentArchive == null) return null;
    var archive = currentArchive;

    while (mounted) {
      final result = await archive.extractEntryResult(entryPath);
      if (!result.needsPassphrase) return result;

      final entered = await BrowserDialogs.showArchivePasswordPrompt(
        context,
        wrongPassword: result.status == ArchiveOpenStatus.wrongPassphrase,
      );
      if (entered == null || !mounted) return null;

      archive = archive.withPassphrase(entered);
      _navNotifier.updateArchiveContext(archive);
    }
    return null;
  }

  Future<ArchiveEntryStageResult?> _stageArchiveEntryWithPassword(
    String entryPath,
  ) async {
    final currentArchive = _archiveContext;
    if (currentArchive == null) return null;
    var archive = currentArchive;

    while (mounted) {
      final result = await archive.stageEntryForBrowse(entryPath);
      if (!result.needsPassphrase) return result;

      final entered = await BrowserDialogs.showArchivePasswordPrompt(
        context,
        wrongPassword: result.status == ArchiveOpenStatus.wrongPassphrase,
      );
      if (entered == null || !mounted) return null;

      archive = archive.withPassphrase(entered);
      _navNotifier.updateArchiveContext(archive);
    }
    return null;
  }

  Future<ArchiveContext?> _ensureArchivePasswordForExtraction(
    ArchiveContext archive,
  ) async {
    if (archive.passphrase?.isNotEmpty == true) return archive;

    ArchiveEntryInfo? encryptedEntry;
    for (final entry in archive.allEntries) {
      if (!entry.isDirectory &&
          entry.isEncrypted &&
          entry.uncompressedSize > 0) {
        encryptedEntry = entry;
        break;
      }
    }
    if (encryptedEntry == null) return archive;

    var wrongPassword = false;
    while (mounted) {
      final entered = await BrowserDialogs.showArchivePasswordPrompt(
        context,
        wrongPassword: wrongPassword,
      );
      if (entered == null || !mounted) return null;
      if (entered.isEmpty) {
        wrongPassword = true;
        continue;
      }

      final candidate = await archive.rescanWithPassphrase(entered);
      if (candidate.status == ArchiveOpenStatus.ok) return candidate;
      if (candidate.status == ArchiveOpenStatus.passphraseRequired ||
          candidate.status == ArchiveOpenStatus.wrongPassphrase) {
        wrongPassword = candidate.status == ArchiveOpenStatus.wrongPassphrase;
        continue;
      }

      _setStatus(
        context.l10n.failedToReadArchive(
          candidate.indexResult.errorMessage.isEmpty
              ? 'Archive scan failed'
              : candidate.indexResult.errorMessage,
        ),
        error: true,
      );
      return null;
    }
    return null;
  }

  Future<void> _openArchivePreview(String fileName, String previewPath) async {
    final archiveApi = ref.read(vaultArchiveApiProvider);
    final preview = ArchivePreviewFile.fromNativePath(previewPath);
    try {
      if (!mounted) return;

      final previewFile = preview;
      final previewContainer = buildLocalStorageContainer(
        rootPath: p.dirname(previewFile.path),
        displayName: fileName,
        readOnly: true,
      );
      final stagedFileName = p.basename(previewFile.path);

      // A normal open reaches the viewer with the image's aspect ratio already
      // cached (the grid's thumbnails put it there). An archive preview has no
      // thumbnails -- they are disabled so nothing from the archive reaches a
      // cache -- so the viewer would lay the image out blind and only settle
      // once it had decoded the picture, in the middle of the first pinch.
      // Read the size from the staged file's header and seed the cache so the
      // preview starts from the same geometry as any other image.
      if (MediaViewerConstants.isImage(fileName)) {
        final size = await previewFile.readImageSize();
        if (size != null) {
          MediaAspectRatioCache.put(
            previewContainer,
            stagedFileName,
            size.$1,
            size.$2,
          );
        }
      }
      if (!mounted) return;
      _navNotifier.setLoading(false);

      // The preview shows a copy under a throw-away local container, so the
      // screen cannot tell which vault it came from: close it here if the
      // archive's vault is locked while it is open.
      if (fileName.toLowerCase().endsWith('.pdf')) {
        await pushClosingWhenVolumeGone<void>(
          context,
          _vaultEvents,
          widget.container.volId,
          MaterialPageRoute<void>(
            builder: (_) => PdfViewerScreen(
              container: previewContainer,
              filePath: stagedFileName,
            ),
          ),
        );
      } else {
        await pushClosingWhenVolumeGone<void>(
          context,
          _vaultEvents,
          widget.container.volId,
          _buildMediaViewerRoute(
            mediaFiles: [stagedFileName],
            initialIndex: 0,
            container: previewContainer,
            isArchivePreview: true,
          ),
        );
      }
    } finally {
      await preview.discard(secureDelete: archiveApi.discardBrowseFile);
    }
  }

  Future<void> _openArchiveTextPreview(
    String fileName,
    String previewPath,
  ) async {
    final archiveApi = ref.read(vaultArchiveApiProvider);
    final preview = ArchivePreviewFile.fromNativePath(previewPath);
    try {
      if (!mounted) return;

      final previewContainer = buildLocalStorageContainer(
        rootPath: p.dirname(preview.path),
        displayName: fileName,
        readOnly: true,
      );
      _navNotifier.setLoading(false);
      await pushClosingWhenVolumeGone<void>(
        context,
        _vaultEvents,
        widget.container.volId,
        MaterialPageRoute<void>(
          builder: (_) => TextEditorScreen(
            container: previewContainer,
            filePath: p.basename(preview.path),
          ),
        ),
      );
    } finally {
      await preview.discard(secureDelete: archiveApi.discardBrowseFile);
    }
  }

  Future<void> _compressSelected() async {
    final selected = _uniqueSelectedBrowserEntries
        .where((item) => !item.insideArchive)
        .toList();
    if (selected.isEmpty ||
        selected.map((item) => item.container.volId).toSet().length != 1) {
      return;
    }
    final entries = selected.map((item) => item.entry).toList();
    final source = selected.first.container;
    final currentDirPath = _currentDirPath;
    final existingEntries = _currentItems;
    String stem(RawEntry e) {
      if (e.isDir) return e.name;
      final dot = e.name.lastIndexOf('.');
      return dot > 0 ? e.name.substring(0, dot) : e.name;
    }

    final suggestedName = entries.length == 1
        ? '${stem(entries.first)}.zip'
        : '${currentDirPath.isEmpty ? source.displayName : currentDirPath.split('/').last}.zip';
    exitSelectionMode();
    if (!mounted) return;
    BrowserDialogs.showCreateArchive(
      context,
      container: widget.container,
      currentDirPath: currentDirPath,
      existingEntries: existingEntries,
      suggestedName: suggestedName,
      selectedEntries: entries,
      freeSpace: _freeSpace,
      readOnly: _isReadOnly,
      onCreate:
          (
            destPath,
            format,
            passphrase,
            encryptFilenames,
            compressionLevel,
            compressionMethod,
          ) async {
            final clipItems = selected.map((item) {
              final entry = item.entry;
              final path = fullPathOf(entry, item.currentDirPath);
              return ClipboardItem(
                path: path,
                isDir: entry.isDir,
                sizeBytes: entry.isDir ? 0 : entry.sizeBytes,
                modifiedSecs: entry.modifiedSecs,
              );
            }).toList();

            final archiveName = destPath.split('/').last;
            _clip.setArchiveCreate(
              volId: source.volId,
              displayName: source.displayName,
              clipItems: clipItems,
              archiveName: archiveName,
              format: format,
              passphrase: passphrase,
              encryptFilenames: encryptFilenames,
              compressionLevel: compressionLevel,
              compressionMethod: compressionMethod,
            );
            _setStatus('${context.l10n.verbArchiving}: $archiveName');
          },
    );
  }

  Future<void> _extractSelectedArchive() async {
    // ── Inside archive: stage selected items for extraction ─────────────
    if (_archiveContext != null) {
      final entries = selectedItems.toList();
      if (entries.isEmpty) return;

      final archivePath =
          _pathStack[_archiveContext!.pathStackEntryIndex].fatPath;

      final subPathPrefix = _currentDirPath.length > archivePath.length
          ? _currentDirPath
                .substring(archivePath.length)
                .replaceFirst(RegExp(r'^/+'), '')
          : '';

      final selectedPaths = entries.map((e) {
        final clean = subPathPrefix.isEmpty
            ? e.name
            : '$subPathPrefix/${e.name}';
        return clean.startsWith('/') ? clean.substring(1) : clean;
      }).toList();

      final clipItems = entries.map((e) {
        return ClipboardItem(
          path: subPathPrefix.isEmpty ? e.name : '$subPathPrefix/${e.name}',
          isDir: e.isDir,
          sizeBytes: e.sizeBytes,
          modifiedSecs: e.modifiedSecs,
        );
      }).toList();

      _clip.setArchiveExtract(
        volId: widget.container.volId,
        displayName: widget.container.displayName,
        archiveItem: ClipboardItem(
          path: archivePath,
          isDir: false,
          sizeBytes: 0,
        ),
        archiveContext: _archiveContext!,
        selectedEntryPaths: selectedPaths,
        stagedItems: clipItems,
      );
      exitSelectionMode();

      _setStatus(
        entries.length == 1
            ? 'Item staged for extraction. Navigate to destination and paste.'
            : '${entries.length} items staged for extraction. Navigate to destination and paste.',
      );
      return;
    }

    // ── Outside archive: stage full archive file for extraction ─────────
    if (selectedItems.length != 1) return;
    final entry = selectedItems.first;
    final ext =
        ArchiveService.splitPartExtension(entry.name) ??
        (entry.name.contains('.')
            ? entry.name.split('.').last.toLowerCase()
            : '');
    if (entry.isDir || !ArchiveService.isOpenableAsArchive(ext)) return;
    if (_isReadOnly) {
      _setStatus(context.l10n.readOnlyContainerWarning, error: true);
      return;
    }
    final fullPath = _fullPathOf(entry);
    exitSelectionMode();

    ArchiveContext archiveContext;
    String? passphrase;
    try {
      while (true) {
        archiveContext = widget.container.isLocalStorage
            ? await ArchiveService.openLocal(
                pathOrUri: p.join(widget.container.uri, fullPath),
                archiveName: entry.name,
                archivePathInContainer: fullPath,
                pathStackEntryIndex: _pathStack.length,
                passphrase: passphrase,
              )
            : await ArchiveService.open(
                container: widget.container,
                archivePathInContainer: fullPath,
                pathStackEntryIndex: _pathStack.length,
                passphrase: passphrase,
              );
        if (archiveContext.status == ArchiveOpenStatus.ok) break;
        if (!mounted) return;
        final entered = await BrowserDialogs.showArchivePasswordPrompt(
          context,
          wrongPassword:
              archiveContext.status == ArchiveOpenStatus.wrongPassphrase,
        );
        if (entered == null) return;
        passphrase = entered;
      }
    } catch (e) {
      if (mounted) {
        _setStatus(
          context.l10n.failedToReadArchive('${e.runtimeType}'),
          error: true,
        );
      }
      return;
    }

    final clipItem = ClipboardItem(
      path: fullPath,
      isDir: false,
      sizeBytes: entry.sizeBytes,
      modifiedSecs: entry.modifiedSecs,
    );

    _clip.setArchiveExtract(
      volId: widget.container.volId,
      displayName: widget.container.displayName,
      archiveItem: clipItem,
      archiveContext: archiveContext,
      selectedEntryPaths: null, // Full archive
    );
    if (mounted) {
      _setStatus(
        'Archive "${entry.name}" staged. Navigate to destination and paste.',
      );
    }
  }

  Future<void> _extractArchive() async {
    if (_archiveContext == null) return;
    if (_isReadOnly) {
      _setStatus(context.l10n.readOnlyContainerWarning, error: true);
      return;
    }
    // For an archive opened from inside another archive the destination is
    // the folder that holds the outermost one: the nested archive has no file
    // of its own to sit next to.
    final archivePath =
        _pathStack[_archiveContext!.outermost.pathStackEntryIndex].fatPath;
    final parentDir = archivePath.contains('/')
        ? archivePath.substring(0, archivePath.lastIndexOf('/'))
        : '';
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.l10n.extractArchive),
        content: Text(
          context.l10n.extractAllFilesToFolder(
            parentDir.isEmpty ? context.l10n.rootFolderLabel : parentDir,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(context.l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(context.l10n.extract),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    final verifiedArchive = await _ensureArchivePasswordForExtraction(
      _archiveContext!,
    );
    if (verifiedArchive == null || !mounted) return;
    _navNotifier.updateArchiveContext(verifiedArchive);
    _navNotifier.setLoading(true);
    try {
      // Same handling as FileOperationService._runArchiveExtract: entries
      // that differ only by case would replace one another on a
      // case-insensitive destination, so they are extracted one by one under
      // unique names ("notes (1).txt") instead of the bulk route.
      final caseSafePlan = isDestinationCaseSensitive(widget.container)
          ? null
          : ArchiveService.caseSafeExtractPlan(verifiedArchive);
      final count = caseSafePlan != null
          ? await ArchiveService.extractMappedToContainer(
              container: widget.container,
              archiveContext: verifiedArchive,
              destRelByEntryPath: caseSafePlan,
              targetDirInContainer: parentDir,
            )
          : await ArchiveService.extractAllToContainer(
              container: widget.container,
              archiveContext: verifiedArchive,
              targetDirInContainer: parentDir,
            );
      if (mounted) {
        _setStatus(
          context.l10n.extractedCount(count),
          autoClear: const Duration(seconds: 3),
        );
        _opSvc.notifyVolumeContentChanged(widget.container.volId);
      }
    } catch (e) {
      if (mounted) {
        _setStatus(
          context.l10n.failedToExtractGeneric('${e.runtimeType}'),
          error: true,
        );
      }
    } finally {
      if (mounted) _navNotifier.setLoading(false);
    }
  }
}
