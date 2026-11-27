part of 'text_editor_screen.dart';

/// The editor screen, tab bar, body and bottom bar widgets.
///
/// Moved out of [_TextEditorScreenState] as is: an extension in the
/// same library reads and writes the state's private fields exactly as the
/// class did.
extension _TextEditorUi on _TextEditorScreenState {
  Widget _buildEditorScreen(BuildContext context) {
    if (_tabs.isEmpty) {
      return const Scaffold(body: SizedBox.shrink());
    }

    final appTheme = Theme.of(context);
    final appSkinTokens = appTheme.extension<AppSkinTokens>();
    final activeTab = _activeTab;
    final appearance = _effectiveAppearance(
      ref.watch(textEditorAppearanceProvider),
    );

    final customColors = appSkinTokens?.editorFollowsAppSkin == true
        ? null
        : appearance.customColors.map((k, v) => MapEntry(k, Color(v)));
    final syntaxStyle = applyAppSkinEditorTokens(
      resolveEditorSyntaxStyle(
        activeTab.filePath,
        appTheme.brightness,
        appTheme.colorScheme,
        background: appearance.background,
        syntaxTheme: appearance.syntaxTheme,
        disableHighlight: activeTab.isLargeFile,
        customColors: customColors,
      ),
      appSkinTokens,
    );
    final chrome = _resolveChrome(
      syntaxStyle,
      appTheme.colorScheme,
      appSkinTokens,
    );
    final cs = chrome.colorScheme;

    ref.listen<TextEditorAppearancePrefs>(textEditorAppearanceProvider, (
      previous,
      next,
    ) {
      if (!next.autoSave) {
        for (final tab in _tabs) {
          tab.autosaveTimer?.cancel();
          tab.autosaveTimer = null;
        }
      }

      if (previous?.showTabBar != next.showTabBar ||
          previous?.autoHideTabBar != next.autoHideTabBar) {
        if (!next.showTabBar) {
          _animateTabBar(0);
        } else if (!next.autoHideTabBar ||
            previous?.showTabBar == false ||
            previous?.autoHideTabBar == false) {
          _animateTabBar(1);
        }
      }

      if (previous?.autoHideAppBar != next.autoHideAppBar) {
        _updateAppBarVisibility();
      }
    });

    final anyDirty = _tabs.any((t) => t.isDirty);

    return Theme(
      data: chrome.theme,
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: chrome.overlayStyle,
        child: PopScope(
          canPop: !anyDirty,
          onPopInvokedWithResult: (didPop, result) async {
            if (didPop) return;
            final shouldPop = await _onWillPop();
            if (shouldPop && context.mounted) {
              Navigator.of(context).pop();
            }
          },
          child: CallbackShortcuts(
            bindings: <ShortcutActivator, VoidCallback>{
              const SingleActivator(LogicalKeyboardKey.keyA, control: true):
                  _handleSelectAllShortcut,
              const SingleActivator(LogicalKeyboardKey.keyA, meta: true):
                  _handleSelectAllShortcut,
              const SingleActivator(LogicalKeyboardKey.keyS, control: true):
                  _handleSaveShortcut,
              const SingleActivator(LogicalKeyboardKey.keyS, meta: true):
                  _handleSaveShortcut,
              const SingleActivator(LogicalKeyboardKey.keyF, control: true):
                  _handleFindShortcut,
              const SingleActivator(LogicalKeyboardKey.keyF, meta: true):
                  _handleFindShortcut,
              const SingleActivator(LogicalKeyboardKey.keyW, control: true):
                  _handleCloseTabShortcut,
              const SingleActivator(LogicalKeyboardKey.keyW, meta: true):
                  _handleCloseTabShortcut,
              const SingleActivator(LogicalKeyboardKey.keyG, control: true):
                  _handleGoToLineShortcut,
              const SingleActivator(LogicalKeyboardKey.keyG, meta: true):
                  _handleGoToLineShortcut,
              const SingleActivator(LogicalKeyboardKey.keyZ, alt: true):
                  _toggleWordWrap,
              const SingleActivator(LogicalKeyboardKey.arrowUp, alt: true):
                  _handleMoveLineUp,
              const SingleActivator(LogicalKeyboardKey.arrowDown, alt: true):
                  _handleMoveLineDown,
              const SingleActivator(LogicalKeyboardKey.slash, control: true):
                  _handleCommentShortcut,
              const SingleActivator(LogicalKeyboardKey.slash, meta: true):
                  _handleCommentShortcut,
              const SingleActivator(LogicalKeyboardKey.keyZ, control: true):
                  _handleUndoShortcut,
              const SingleActivator(LogicalKeyboardKey.keyZ, meta: true):
                  _handleUndoShortcut,
              const SingleActivator(LogicalKeyboardKey.keyY, control: true):
                  _handleRedoShortcut,
              const SingleActivator(LogicalKeyboardKey.keyY, meta: true):
                  _handleRedoShortcut,
              const SingleActivator(
                LogicalKeyboardKey.keyZ,
                control: true,
                shift: true,
              ): _handleRedoShortcut,
              const SingleActivator(
                LogicalKeyboardKey.keyZ,
                meta: true,
                shift: true,
              ): _handleRedoShortcut,
              const SingleActivator(LogicalKeyboardKey.tab):
                  _handleIndentShortcut,
              const SingleActivator(LogicalKeyboardKey.tab, shift: true):
                  _handleOutdentShortcut,
              const SingleActivator(LogicalKeyboardKey.tab, control: true):
                  _handleNextTabShortcut,
              const SingleActivator(
                LogicalKeyboardKey.tab,
                control: true,
                shift: true,
              ): _handlePreviousTabShortcut,
              const SingleActivator(LogicalKeyboardKey.tab, meta: true):
                  _handleNextTabShortcut,
              const SingleActivator(
                LogicalKeyboardKey.tab,
                meta: true,
                shift: true,
              ): _handlePreviousTabShortcut,
            },
            child: Scaffold(
              key: _scaffoldKey,
              drawer: _ProjectDrawer(
                container: widget.container,
                initialDirPath: _projectDirPath,
                chrome: chrome,
                activeFilePath: activeTab.filePath,
                isTabOpen: (path) => _tabs.any((t) => t.filePath == path),
                onOpenFile: _openFileInTab,
                onSyncRenamedPath: _syncRenamedPath,
                onCloseTabsForDeletedPath: _closeTabsForDeletedPath,
                onShowImagePreview: _showImagePreviewDialog,
                isImageFile: _isImageFile,
                isUnsupportedBinaryFile: _isUnsupportedBinaryFile,
              ),
              appBar: PreferredSize(
                preferredSize: Size.fromHeight(
                  kToolbarHeight * _appBarAnimationController.value,
                ),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final topPadding = MediaQuery.paddingOf(context).top;
                    final fullHeight = topPadding + kToolbarHeight;

                    return ClipRect(
                      child: OverflowBox(
                        minWidth: constraints.maxWidth,
                        maxWidth: constraints.maxWidth,
                        minHeight: fullHeight,
                        maxHeight: fullHeight,
                        alignment: Alignment.topCenter,
                        child: AppBar(
                          systemOverlayStyle: chrome.overlayStyle,
                          leading: IconButton(
                            icon: const Icon(Icons.menu_rounded),
                            tooltip: context.l10n.textEditorProjectFilesTitle,
                            onPressed: () =>
                                _scaffoldKey.currentState?.openDrawer(),
                          ),
                          title: Text(activeTab.fileName),
                          actions: [
                            if (!activeTab.isLoading && activeTab.hasError)
                              PopupMenuButton<String>(
                                tooltip:
                                    context.l10n.textEditorMoreActionsTooltip,
                                icon: const Icon(Icons.more_vert_rounded),
                                onSelected: (value) {
                                  if (value == 'encoding') {
                                    _showEncodingPicker(activeTab);
                                  }
                                },
                                itemBuilder: (context) => [
                                  PopupMenuItem(
                                    value: 'encoding',
                                    child: Row(
                                      children: [
                                        const Icon(
                                          Icons.translate_rounded,
                                          size: 20,
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Text(
                                            context
                                                .l10n
                                                .textEditorEncodingTooltip,
                                          ),
                                        ),
                                        Text(activeTab.encoding.label),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            if (!activeTab.isLoading && !activeTab.hasError) ...[
                              if (activeTab.isMarkdownFile &&
                                  !activeTab.isLargeFile) ...[
                                if (!activeTab.showMarkdownPreview &&
                                    !_readOnly)
                                  IconButton(
                                    icon: const Icon(
                                      Icons.add_photo_alternate_outlined,
                                    ),
                                    tooltip: context.l10n.addFile,
                                    onPressed: _insertImageTemplate,
                                  ),
                                IconButton(
                                  icon: Icon(
                                    activeTab.showMarkdownPreview
                                        ? Icons.edit_note_rounded
                                        : Icons.visibility_outlined,
                                  ),
                                  tooltip: activeTab.showMarkdownPreview
                                      ? context.l10n.markdownViewerEditTooltip
                                      : context
                                          .l10n
                                          .markdownViewerPreviewTooltip,
                                  onPressed: _toggleMarkdownPreview,
                                ),
                              ],
                              IconButton(
                                icon: const Icon(Icons.search_rounded),
                                tooltip: context.l10n.textEditorFindTooltip,
                                onPressed: () {
                                  if (activeTab.showMarkdownPreview) {
                                    _toggleMarkdownPreview();
                                  }
                                  activeTab.findController.findMode();
                                },
                              ),
                              PopupMenuButton<String>(
                                tooltip:
                                    context.l10n.textEditorMoreActionsTooltip,
                                icon: const Icon(Icons.more_vert_rounded),
                                onSelected: (value) {
                                  switch (value) {
                                    case 'save':
                                      _saveFile(activeTab);
                                      break;
                                    case 'saveAs':
                                      _showSaveAsDialog();
                                      break;
                                    case 'revert':
                                      _revertActiveTab();
                                      break;
                                    case 'readOnly':
                                      _toggleReadOnly();
                                      break;
                                    case 'wordWrap':
                                      _toggleWordWrap();
                                      break;
                                    case 'selectAll':
                                      _selectAll();
                                      break;
                                    case 'goToLine':
                                      _showGoToLineDialog();
                                      break;
                                    case 'goToStart':
                                      _goToStart();
                                      break;
                                    case 'goToEnd':
                                      _goToEnd();
                                      break;
                                    case 'format':
                                      final formatter = _formatter;
                                      if (formatter != null) {
                                        _runFormatter(formatter);
                                      }
                                      break;
                                    case 'minify':
                                      _runFormatter(minifyJson);
                                      break;
                                    case 'encoding':
                                      _showEncodingPicker(activeTab);
                                      break;
                                    case 'appearance':
                                      showEditorAppearanceSheet(context);
                                      break;
                                  }
                                },
                                itemBuilder: (context) => [
                                  PopupMenuItem(
                                    value: 'save',
                                    enabled:
                                        activeTab.isDirty &&
                                        !activeTab.isSaving &&
                                        !activeTab.isAutosaving,
                                    child: Row(
                                      children: [
                                        Icon(
                                          Icons.save_rounded,
                                          size: 20,
                                          color:
                                              (activeTab.isDirty &&
                                                      !activeTab.isSaving &&
                                                      !activeTab.isAutosaving)
                                                  ? cs.primary
                                                  : cs.onSurface.withValues(
                                                      alpha: 0.38,
                                                    ),
                                        ),
                                        const SizedBox(width: 12),
                                        Text(context.l10n.save),
                                      ],
                                    ),
                                  ),
                                  PopupMenuItem(
                                    value: 'saveAs',
                                    child: Row(
                                      children: [
                                        const Icon(
                                          Icons.save_as_rounded,
                                          size: 20,
                                        ),
                                        const SizedBox(width: 12),
                                        Text(
                                          context
                                              .l10n
                                              .textEditorSaveAsMenuItem,
                                        ),
                                      ],
                                    ),
                                  ),
                                  PopupMenuItem(
                                    value: 'revert',
                                    enabled:
                                        activeTab.isDirty &&
                                        !activeTab.isSaving &&
                                        !activeTab.isAutosaving,
                                    child: Row(
                                      children: [
                                        Icon(
                                          Icons.restore_rounded,
                                          size: 20,
                                          color:
                                              (activeTab.isDirty &&
                                                      !activeTab.isSaving &&
                                                      !activeTab.isAutosaving)
                                                  ? cs.error
                                                  : cs.onSurface.withValues(
                                                      alpha: 0.38,
                                                    ),
                                        ),
                                        const SizedBox(width: 12),
                                        Text(
                                          context.l10n.textEditorRevertToSaved,
                                          style: TextStyle(
                                            color:
                                                (activeTab.isDirty &&
                                                        !activeTab.isSaving &&
                                                        !activeTab.isAutosaving)
                                                    ? cs.error
                                                    : null,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const PopupMenuDivider(),
                                  PopupMenuItem(
                                    value: 'encoding',
                                    child: Row(
                                      children: [
                                        const Icon(
                                          Icons.translate_rounded,
                                          size: 20,
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Text(
                                            context
                                                .l10n
                                                .textEditorEncodingTooltip,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  PopupMenuItem(
                                    value: 'wordWrap',
                                    child: Row(
                                      children: [
                                        const Icon(
                                          Icons.wrap_text_rounded,
                                          size: 20,
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Text(
                                            context.l10n.textEditorWordWrap,
                                          ),
                                        ),
                                        if (_wordWrap)
                                          Icon(
                                            Icons.check_rounded,
                                            size: 18,
                                            color: cs.primary,
                                          ),
                                      ],
                                    ),
                                  ),
                                  PopupMenuItem(
                                    value: 'readOnly',
                                    child: Row(
                                      children: [
                                        Icon(
                                          _readOnly
                                              ? Icons.lock_rounded
                                              : Icons.lock_open_rounded,
                                          size: 20,
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Text(
                                            context.l10n.textEditorReadOnly,
                                          ),
                                        ),
                                        if (_readOnly)
                                          Icon(
                                            Icons.check_rounded,
                                            size: 18,
                                            color: cs.primary,
                                          ),
                                      ],
                                    ),
                                  ),
                                  const PopupMenuDivider(),
                                  PopupMenuItem(
                                    value: 'selectAll',
                                    child: Row(
                                      children: [
                                        const Icon(
                                          Icons.select_all_rounded,
                                          size: 20,
                                        ),
                                        const SizedBox(width: 12),
                                        Text(
                                          context
                                              .l10n
                                              .textEditorSelectAllMenuItem,
                                        ),
                                      ],
                                    ),
                                  ),
                                  PopupMenuItem(
                                    value: 'goToLine',
                                    child: Row(
                                      children: [
                                        const Icon(
                                          Icons.format_list_numbered_rounded,
                                          size: 20,
                                        ),
                                        const SizedBox(width: 12),
                                        Text(
                                          context
                                              .l10n
                                              .textEditorGoToLineMenuItem,
                                        ),
                                      ],
                                    ),
                                  ),
                                  PopupMenuItem(
                                    value: 'goToStart',
                                    child: Row(
                                      children: [
                                        const Icon(
                                          Icons.vertical_align_top_rounded,
                                          size: 20,
                                        ),
                                        const SizedBox(width: 12),
                                        Text(
                                          context
                                              .l10n
                                              .textEditorGoToStartMenuItem,
                                        ),
                                      ],
                                    ),
                                  ),
                                  PopupMenuItem(
                                    value: 'goToEnd',
                                    child: Row(
                                      children: [
                                        const Icon(
                                          Icons.vertical_align_bottom_rounded,
                                          size: 20,
                                        ),
                                        const SizedBox(width: 12),
                                        Text(
                                          context
                                              .l10n
                                              .textEditorGoToEndMenuItem,
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (_formatter != null && !_readOnly) ...[
                                    const PopupMenuDivider(),
                                    PopupMenuItem(
                                      value: 'format',
                                      child: Row(
                                        children: [
                                          const Icon(
                                            Icons.auto_fix_high_rounded,
                                            size: 20,
                                          ),
                                          const SizedBox(width: 12),
                                          Text(
                                            context
                                                .l10n
                                                .textEditorFormatDocumentMenuItem,
                                          ),
                                        ],
                                      ),
                                    ),
                                    if (_isJsonFile)
                                      PopupMenuItem(
                                        value: 'minify',
                                        child: Row(
                                          children: [
                                            const Icon(
                                              Icons.compress_rounded,
                                              size: 20,
                                            ),
                                            const SizedBox(width: 12),
                                            Text(
                                              context
                                                  .l10n
                                                  .textEditorMinifyJsonMenuItem,
                                            ),
                                          ],
                                        ),
                                      ),
                                  ],
                                  const PopupMenuDivider(),
                                  PopupMenuItem(
                                    value: 'appearance',
                                    child: Row(
                                      children: [
                                        const Icon(
                                          Icons.palette_outlined,
                                          size: 20,
                                        ),
                                        const SizedBox(width: 12),
                                        Text(
                                          context
                                              .l10n
                                              .textEditorThemeMenuItem,
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              body: SafeArea(
                top: false,
                child: NotificationListener<ScrollNotification>(
                  onNotification: _handleTabBarScroll,
                  child: _buildBody(
                    chrome.theme,
                    syntaxStyle,
                    tabBar:
                        (appearance.showTabBar &&
                            _tabBarAnimationController.value > 0)
                        ? _buildTabBar(cs, syntaxStyle.textColor)
                        : null,
                  ),
                ),
              ),
              bottomNavigationBar:
                  activeTab.isLoading ||
                      activeTab.hasError ||
                      !appearance.showStatusBar
                  ? null
                  : _buildBottomBar(cs),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTabBar(ColorScheme cs, Color canvasForeground) {
    final tabStripBackground = cs.surfaceContainer;
    final activeTabBackground = cs.surfaceContainerHighest;

    Color tabForeground(Color background, {double opacity = 1}) {
      final preferred = Color.alphaBlend(
        canvasForeground.withValues(alpha: opacity),
        background,
      );
      if (_contrastRatio(preferred, background) >= 4.5) return preferred;

      final blackContrast = _contrastRatio(Colors.black, background);
      final whiteContrast = _contrastRatio(Colors.white, background);
      return blackContrast >= whiteContrast ? Colors.black : Colors.white;
    }

    return Container(
      height: 40,
      decoration: BoxDecoration(
        color: tabStripBackground,
        border: Border(
          bottom: BorderSide(color: cs.outlineVariant, width: 0.5),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: ReorderableListView.builder(
              scrollController: _tabScrollController,
              scrollDirection: Axis.horizontal,
              buildDefaultDragHandles: false,
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              itemCount: _tabs.length,
              onReorderStart: (_) => HapticFeedback.mediumImpact(),
              onReorderItem: _reorderTabs,
              proxyDecorator: (child, index, animation) {
                return AnimatedBuilder(
                  animation: animation,
                  builder: (context, child) {
                    final t = Curves.easeInOut.transform(animation.value);
                    return Material(
                      elevation: 6 * t,
                      color: activeTabBackground,
                      shadowColor: cs.shadow.withValues(alpha: 0.35),
                      borderRadius: BorderRadius.circular(8),
                      child: child,
                    );
                  },
                  child: child,
                );
              },
              itemBuilder: (context, index) {
                final tab = _tabs[index];
                final isActive = index == _activeTabIndex;
                final tabBackground = isActive
                    ? activeTabBackground
                    : tabStripBackground;
                final labelColor = tabForeground(tabBackground);

                return ReorderableDelayedDragStartListener(
                  key: ObjectKey(tab),
                  index: index,
                  child: Builder(
                    builder: (tabContext) {
                      tab.tabContext = tabContext;
                      return Material(
                        color: isActive
                            ? activeTabBackground
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(8),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(8),
                          onTap: () => _onTabTapped(tab, tabContext),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: isActive
                                    ? cs.primary.withValues(alpha: 0.5)
                                    : Colors.transparent,
                                width: 1,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (tab.isDirty)
                                  Container(
                                    width: 6,
                                    height: 6,
                                    margin: const EdgeInsets.only(right: 6),
                                    decoration: BoxDecoration(
                                      color: cs.primary,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                Text(
                                  tab.fileName,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: isActive
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                    color: labelColor,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                );
              },
            ),
          ),
          IconButton(
            icon: const Icon(Icons.add_rounded, size: 20),
            visualDensity: VisualDensity.compact,
            tooltip: context.l10n.textEditorNewFileTooltip,
            onPressed: _createNewFileFromTabBar,
          ),
          const SizedBox(width: 4),
        ],
      ),
    );
  }

  /// Lays out the editor area together with the tab strip.
  ///
  /// The strip always takes its own space above the area, so the visible
  /// result is unchanged. What changes is what the *editor* sees: with
  /// auto-hide on, [builder] receives the full height of this host and is
  /// expected to keep the editor laid out at exactly that height (see the
  /// OverflowBox in [_buildBody]) while the strip slides in and out. A strip
  /// that resizes the editor while the user is scrolling restarts the running
  /// fling on every frame and, in word wrap mode, re-estimates the scroll
  /// extent; that fed straight back into the scroll notifications driving
  /// the strip (flicker with the scroll handle, scrolling up stopping short
  /// of the first line).
  Widget _tabSlideHost({
    required Widget? tabBar,
    required Widget Function(double fullHeight) builder,
  }) {
    final appearance = ref.watch(textEditorAppearanceProvider);
    // While typing with the soft keyboard up, an auto-hiding strip steps
    // aside: with the editor kept at full height, the caret could otherwise
    // land in the band the strip covers.
    final editing =
        (MediaQuery.maybeViewInsetsOf(context)?.bottom ?? 0) > 0 &&
        _focusNode.hasFocus;
    final stripShown =
        appearance.showTabBar && !(appearance.autoHideTabBar && editing);
    final reveal = stripShown
        ? _tabBarAnimationController.value * _appBarAnimationController.value
        : 0.0;
    final stripHeight = _TextEditorScreenState._kTabStripHeight * reveal;
    return LayoutBuilder(
      builder: (context, constraints) {
        return ClipRect(
          child: Stack(
            children: [
              Positioned.fill(
                top: stripHeight,
                child: builder(constraints.maxHeight),
              ),
              if (tabBar != null && stripHeight > 0)
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: ClipRect(
                    child: Align(
                      alignment: Alignment.bottomCenter,
                      heightFactor: reveal,
                      child: tabBar,
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildBody(
    ThemeData editorTheme,
    EditorSyntaxStyle syntaxStyle, {
    Widget? tabBar,
  }) {
    final cs = editorTheme.colorScheme;
    final textTheme = editorTheme.textTheme;
    final activeTab = _activeTab;

    if (activeTab.isLoading) {
      return _tabSlideHost(
        tabBar: tabBar,
        builder: (_) => Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(strokeWidth: 2.5),
              const SizedBox(height: 16),
              Text(context.l10n.decryptingFileContent),
            ],
          ),
        ),
      );
    }
    if (activeTab.hasError) {
      return _tabSlideHost(
        tabBar: tabBar,
        builder: (_) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.error_outline_rounded, color: cs.error, size: 48),
                const SizedBox(height: 16),
                Text(
                  context.l10n.cannotOpenFile,
                  style: textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  activeTab.errorMessage,
                  textAlign: TextAlign.center,
                  style: textTheme.bodyMedium?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 24),
                OutlinedButton.icon(
                  onPressed: () => _loadFileForTab(activeTab),
                  icon: const Icon(Icons.refresh_rounded),
                  label: Text(context.l10n.retryButton),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (activeTab.isMarkdownFile && activeTab.showMarkdownPreview) {
      final canvasForeground = syntaxStyle.textColor;
      final canvasBackground = syntaxStyle.backgroundColor;
      Color canvasTone(double alpha) => Color.alphaBlend(
        canvasForeground.withValues(alpha: alpha),
        canvasBackground,
      );
      final markdownColorScheme = cs.copyWith(
        surface: canvasBackground,
        onSurface: canvasForeground,
        onSurfaceVariant: canvasTone(0.72),
        surfaceContainerLowest: canvasBackground,
        surfaceContainerLow: canvasBackground,
        surfaceContainer: canvasTone(0.04),
        surfaceContainerHigh: canvasTone(0.07),
        surfaceContainerHighest: canvasTone(0.11),
        outline: canvasTone(0.45),
        outlineVariant: canvasTone(0.14),
      );
      final markdownTheme = editorTheme.copyWith(
        colorScheme: markdownColorScheme,
        scaffoldBackgroundColor: canvasBackground,
        textTheme: textTheme.apply(
          bodyColor: canvasForeground,
          displayColor: canvasForeground,
        ),
      );
      // Same arrangement as the code editor below: with auto-hide on, the
      // preview keeps a constant full-height viewport while the tab strip
      // slides over it, and leaves slack at the end of the document for the
      // band the strip pushes out of view. Resizing the viewport instead
      // shifted the content and changed the scroll extent on every show/hide.
      final previewPrefs = ref.watch(textEditorAppearanceProvider);
      final previewStripSlack =
          (previewPrefs.showTabBar && previewPrefs.autoHideTabBar)
          ? _TextEditorScreenState._kTabStripHeight
          : 0.0;
      return _tabSlideHost(
        tabBar: tabBar,
        builder: (fullHeight) => Theme(
            data: markdownTheme,
            child: DefaultTextStyle(
              style: markdownTheme.textTheme.bodyMedium!.copyWith(
                color: canvasForeground,
              ),
              child: FastScrollbar(
                controller: activeTab.previewScrollController,
                // The handle scrolls with a stream of jumpTo calls; keep the
                // tab strip still until it is released.
                onDragStateChanged: _onScrollbarDragStateChanged,
                child: ClipRect(
                  child: OverflowBox(
                    alignment: Alignment.topCenter,
                    minHeight: previewStripSlack > 0 ? fullHeight : null,
                    maxHeight: previewStripSlack > 0 ? fullHeight : null,
                    child: SelectionArea(
                      child: MarkdownBodyView(
                        key: activeTab.previewKey,
                        source: activeTab.codeController.text,
                        container: widget.container,
                        currentFilePath: activeTab.filePath,
                        onLinkTap: _handleLinkTap,
                        scrollController: activeTab.previewScrollController,
                        onTaskToggled: _toggleMarkdownTask,
                        bottomInset: previewStripSlack,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      );
    }

    final appearance = _effectiveAppearance(
      ref.watch(textEditorAppearanceProvider),
    );
    final softKeyboardVisible = MediaQuery.viewInsetsOf(context).bottom > 0;

    final bgLuminance = syntaxStyle.backgroundColor.computeLuminance();
    final primaryLuminance = cs.primary.computeLuminance();
    final contrast = (primaryLuminance - bgLuminance).abs();
    final skinTokens = Theme.of(context).extension<AppSkinTokens>();
    final followsAppSkin = skinTokens?.editorFollowsAppSkin == true;
    final customCursor = followsAppSkin
        ? skinTokens!.editorCursor
        : appearance.customColor('cursor');
    final safeAccentColor =
        customCursor ??
        (contrast > 0.25
            ? cs.primary
            : (bgLuminance < 0.5 ? Colors.white : Colors.black));
    final customSelection = followsAppSkin
        ? skinTokens!.editorSelection
        : appearance.customColor('selection');
    final selectionColor =
        customSelection ?? safeAccentColor.withValues(alpha: 0.28);
    final customGutter = followsAppSkin
        ? skinTokens!.editorGutter
        : appearance.customColor('gutter');
    final gutterColor =
        customGutter ?? syntaxStyle.textColor.withValues(alpha: 0.45);

    // With auto-hide on, leave room at the bottom of the document for the
    // band the tab strip pushes out of view (see _tabSlideHost).
    final tabStripSlack = (appearance.showTabBar && appearance.autoHideTabBar)
        ? _TextEditorScreenState._kTabStripHeight
        : 0.0;

    return Column(
      children: [
        Expanded(
          child: _tabSlideHost(
            tabBar: tabBar,
            builder: (fullHeight) => Listener(
            behavior: HitTestBehavior.translucent,
            onPointerDown: (event) {
              _pinchPointers[event.pointer] = event.position;
              if (_pinchPointers.length == 2) {
                final pts = _pinchPointers.values.toList();
                _initialPinchDistance = (pts[0] - pts[1]).distance;
                _pinchStartFontSize = ref
                    .read(textEditorAppearanceProvider)
                    .fontSize;
                _pinchFontSizeChanged = false;
                _lastPinchFontSizeUpdate = null;
              }
            },
            onPointerMove: (event) {
              if (_pinchPointers.containsKey(event.pointer)) {
                _pinchPointers[event.pointer] = event.position;
              }
              final lastUpdate = _lastPinchFontSizeUpdate;
              if (lastUpdate == null ||
                  DateTime.now().difference(lastUpdate) >=
                      const Duration(milliseconds: 120)) {
                _applyPinchFontSize();
              }
            },
            onPointerUp: (event) {
              if (_pinchPointers.containsKey(event.pointer)) {
                _pinchPointers[event.pointer] = event.position;
                _applyPinchFontSize(force: true);
              }
              _pinchPointers.remove(event.pointer);
              if (_pinchPointers.length < 2) {
                _finishPinchFontSizeGesture();
              }
            },
            onPointerCancel: (event) {
              if (_pinchPointers.containsKey(event.pointer)) {
                _pinchPointers[event.pointer] = event.position;
                _applyPinchFontSize(force: true);
              }
              _pinchPointers.remove(event.pointer);
              if (_pinchPointers.length < 2) {
                _finishPinchFontSizeGesture();
              }
            },
            child: Focus(
              canRequestFocus: false,
              onKeyEvent: (node, event) {
                if (!_focusNode.hasFocus) return KeyEventResult.ignored;

                if (event is KeyDownEvent || event is KeyRepeatEvent) {
                  final key = event.logicalKey;
                  if (key == LogicalKeyboardKey.arrowLeft ||
                      key == LogicalKeyboardKey.arrowRight ||
                      key == LogicalKeyboardKey.arrowUp ||
                      key == LogicalKeyboardKey.arrowDown) {
                    final isShift = HardwareKeyboard.instance.isShiftPressed;
                    final isControl =
                        HardwareKeyboard.instance.isControlPressed ||
                        HardwareKeyboard.instance.isMetaPressed;
                    final isAlt = HardwareKeyboard.instance.isAltPressed;

                    if (isAlt &&
                        (key == LogicalKeyboardKey.arrowUp ||
                            key == LogicalKeyboardKey.arrowDown)) {
                      if (key == LogicalKeyboardKey.arrowUp) {
                        _handleMoveLineUp();
                      } else {
                        _handleMoveLineDown();
                      }
                      return KeyEventResult.handled;
                    }

                    final controller = activeTab.codeController;
                    final selection = controller.selection;
                    final lines = controller.codeLines;
                    if (lines.isEmpty) return KeyEventResult.handled;

                    int baseLine = selection.baseIndex;
                    int baseOffset = selection.baseOffset;
                    int extLine = selection.extentIndex;
                    int extOffset = selection.extentOffset;

                    if (!isShift && !selection.isCollapsed) {
                      if (key == LogicalKeyboardKey.arrowLeft ||
                          key == LogicalKeyboardKey.arrowUp) {
                        final start = selection.start;
                        extLine = baseLine = start.index;
                        extOffset = baseOffset = start.offset;
                      } else {
                        final end = selection.end;
                        extLine = baseLine = end.index;
                        extOffset = baseOffset = end.offset;
                      }
                      if (!isControl &&
                          (key == LogicalKeyboardKey.arrowLeft ||
                              key == LogicalKeyboardKey.arrowRight)) {
                        controller.selection = CodeLineSelection(
                          baseIndex: baseLine,
                          baseOffset: baseOffset,
                          extentIndex: extLine,
                          extentOffset: extOffset,
                        );
                        controller.makeCursorCenterIfInvisible();
                        return KeyEventResult.handled;
                      }
                    }

                    void moveLeft() {
                      if (extOffset > 0) {
                        extOffset--;
                      } else if (extLine > 0) {
                        extLine--;
                        extOffset = lines[extLine].text.length;
                      }
                    }

                    void moveRight() {
                      if (extOffset < lines[extLine].text.length) {
                        extOffset++;
                      } else if (extLine < lines.length - 1) {
                        extLine++;
                        extOffset = 0;
                      }
                    }

                    final whitespaceRe = RegExp(r'\s');
                    final wordRe = RegExp(r'\w');

                    if (key == LogicalKeyboardKey.arrowLeft) {
                      if (isControl) {
                        moveLeft();
                        while (extLine >= 0) {
                          final text = lines[extLine].text;
                          while (extOffset > 0 &&
                              whitespaceRe.hasMatch(text[extOffset - 1])) {
                            extOffset--;
                          }
                          if (extOffset > 0) {
                            bool isWord = wordRe.hasMatch(text[extOffset - 1]);
                            while (extOffset > 0 &&
                                (wordRe.hasMatch(text[extOffset - 1]) ==
                                    isWord) &&
                                !whitespaceRe.hasMatch(text[extOffset - 1])) {
                              extOffset--;
                            }
                            break;
                          } else if (extLine > 0) {
                            extLine--;
                            extOffset = lines[extLine].text.length;
                          } else {
                            break;
                          }
                        }
                      } else {
                        moveLeft();
                      }
                    } else if (key == LogicalKeyboardKey.arrowRight) {
                      if (isControl) {
                        moveRight();
                        while (extLine < lines.length) {
                          final text = lines[extLine].text;
                          while (extOffset < text.length &&
                              whitespaceRe.hasMatch(text[extOffset])) {
                            extOffset++;
                          }
                          if (extOffset < text.length) {
                            bool isWord = wordRe.hasMatch(text[extOffset]);
                            while (extOffset < text.length &&
                                (wordRe.hasMatch(text[extOffset]) == isWord) &&
                                !whitespaceRe.hasMatch(text[extOffset])) {
                              extOffset++;
                            }
                            break;
                          } else if (extLine < lines.length - 1) {
                            extLine++;
                            extOffset = 0;
                          } else {
                            break;
                          }
                        }
                      } else {
                        moveRight();
                      }
                    } else if (key == LogicalKeyboardKey.arrowUp) {
                      if (extLine > 0) {
                        extLine--;
                        extOffset = math.min(
                          extOffset,
                          lines[extLine].text.length,
                        );
                      } else {
                        extOffset = 0;
                      }
                    } else if (key == LogicalKeyboardKey.arrowDown) {
                      if (extLine < lines.length - 1) {
                        extLine++;
                        extOffset = math.min(
                          extOffset,
                          lines[extLine].text.length,
                        );
                      } else {
                        extOffset = lines[extLine].text.length;
                      }
                    }

                    if (!isShift) {
                      baseLine = extLine;
                      baseOffset = extOffset;
                    }

                    controller.selection = CodeLineSelection(
                      baseIndex: baseLine,
                      baseOffset: baseOffset,
                      extentIndex: extLine,
                      extentOffset: extOffset,
                    );
                    controller.makeCursorCenterIfInvisible();
                    return KeyEventResult.handled;
                  }
                }
                return KeyEventResult.ignored;
              },
              child: FastScrollbar(
                controller: activeTab.verticalScrollController,
                onDragStateChanged: _onScrollbarDragStateChanged,
                child: FastScrollbar(
                  controller: activeTab.horizontalScrollController,
                  axis: Axis.horizontal,
                  // Both scrollbars sit in the visible area; the editor inside
                  // keeps a constant height while the tab strip animates.
                  child: ClipRect(
                    child: OverflowBox(
                      alignment: Alignment.topCenter,
                      minHeight: tabStripSlack > 0 ? fullHeight : null,
                      maxHeight: tabStripSlack > 0 ? fullHeight : null,
                      child: TextSelectionTheme(
                    data: TextSelectionThemeData(
                      selectionColor: selectionColor,
                      selectionHandleColor: safeAccentColor,
                    ),
                    child: CodeEditor(
                      key: ValueKey(activeTab.filePath),
                      controller: activeTab.codeController,
                      scrollController: activeTab.scrollController,
                      scrollbarBuilder: (context, child, details) => child,
                      toolbarController: _toolbarController,
                      focusNode: _focusNode,
                      readOnly: _readOnly,
                      showCursorWhenReadOnly: true,
                      wordWrap: _wordWrap,
                      // The editor's own default is EdgeInsets.all(5).
                      padding: EdgeInsets.fromLTRB(5, 5, 5, 5 + tabStripSlack),
                      autofocus: false,
                      findController: activeTab.findController,
                      findBuilder: (context, controller, readOnly) =>
                          EditorFindPanel(
                            controller: controller,
                            readOnly: readOnly,
                          ),
                      chunkAnalyzer: activeTab.isLargeFile
                          ? const NonCodeChunkAnalyzer()
                          : const DefaultCodeChunkAnalyzer(),
                      style: CodeEditorStyle(
                        fontFamily: 'JetBrains Mono',
                        fontFamilyFallback: const ['monospace'],
                        fontSize: appearance.fontSize,
                        fontHeight: 1.5,
                        backgroundColor: syntaxStyle.backgroundColor,
                        textColor: syntaxStyle.textColor,
                        cursorColor: safeAccentColor,
                        cursorLineColor: safeAccentColor.withValues(
                          alpha: 0.15,
                        ),
                        chunkIndicatorColor: safeAccentColor,
                        selectionColor: selectionColor,
                        codeTheme: syntaxStyle.codeTheme,
                      ),
                      commentFormatter: _getCommentFormatter(
                        activeTab.filePath,
                      ),
                      indicatorBuilder: appearance.showLineNumbers
                          ? (
                              context,
                              editingController,
                              chunkController,
                              notifier,
                            ) {
                            return Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  DefaultCodeLineNumber(
                                    minNumberCount: 1,
                                    controller: editingController,
                                    notifier: notifier,
                                    pinToViewportTop: _wordWrap,
                                    textStyle: TextStyle(
                                      color: gutterColor,
                                      fontFamily: 'JetBrains Mono',
                                      fontFamilyFallback: const ['monospace'],
                                      fontSize: appearance.fontSize,
                                      height: 1.5,
                                    ),
                                    focusedTextStyle: TextStyle(
                                      color: safeAccentColor,
                                      fontFamily: 'JetBrains Mono',
                                      fontFamilyFallback: const ['monospace'],
                                      fontSize: appearance.fontSize,
                                      fontWeight: FontWeight.w700,
                                      height: 1.5,
                                    ),
                                    customLineIndex2Text:
                                        appearance.relativeLineNumbers
                                        ? (lineIndex) {
                                            final current = editingController
                                                .selection
                                                .extentIndex;
                                            return lineIndex == current
                                                ? '${lineIndex + 1}'
                                                : '${(lineIndex - current).abs()}';
                                          }
                                        : null,
                                  ),
                                  if (!activeTab.isLargeFile)
                                    DefaultCodeChunkIndicator(
                                      width: 1,
                                      controller: chunkController,
                                      notifier: notifier,
                                      painter: DefaultCodeChunkIndicatorPainter(
                                        color: gutterColor,
                                      ),
                                    ),
                                ],
                              );
                            }
                          : (
                              context,
                              editingController,
                              chunkController,
                              notifier,
                            ) => const SizedBox(width: 12),
                    ),
                  ),
                      ),
                    ),
                ),
              ),
            ),
          ),
          ),
        ),
        if (!_readOnly &&
            softKeyboardVisible &&
            appearance.showAccessoryBar &&
            (appearance.showAccessorySymbols ||
                appearance.showAccessoryActions ||
                appearance.showAccessoryScrubber))
          EditorAccessoryKeyBar(
            controller: activeTab.codeController,
            editorFocusNode: _focusNode,
            symbols: appearance.accessorySymbols,
            actions: appearance.accessoryActions,
            showSymbols: appearance.showAccessorySymbols,
            showActions: appearance.showAccessoryActions,
            showScrubber: appearance.showAccessoryScrubber,
            isWordWrap: _wordWrap,
            isReadOnly: _readOnly,
            onSearch: () {
              if (activeTab.showMarkdownPreview) {
                _toggleMarkdownPreview();
              }
              activeTab.findController.findMode();
            },
            onToggleWordWrap: _toggleWordWrap,
            onGoToLine: _showGoToLineDialog,
            onGoToStart: _goToStart,
            onGoToEnd: _goToEnd,
            onFormat: _formatter != null
                ? () => _runFormatter(_formatter!)
                : null,
            onToggleReadOnly: _toggleReadOnly,
          ),
      ],
    );
  }

  Widget _buildBottomBar(ColorScheme cs) {
    final activeTab = _activeTab;
    final appearance = _effectiveAppearance(
      ref.watch(textEditorAppearanceProvider),
    );
    final timeStr = activeTab.lastSavedAt != null
        ? '${activeTab.lastSavedAt!.hour.toString().padLeft(2, '0')}:${activeTab.lastSavedAt!.minute.toString().padLeft(2, '0')}'
        : null;

    final posStr = !activeTab.showMarkdownPreview
        ? '${context.l10n.textEditorCursorPosition(activeTab.cursorLine, activeTab.cursorCol)}  •  '
        : '';

    return DecoratedBox(
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        border: Border(top: BorderSide(color: cs.outlineVariant, width: 0.5)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '$posStr${context.l10n.linesCount(activeTab.lineCount)}  |  ${context.l10n.charsCount(activeTab.charCount)}',
                  style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (_readOnly && !activeTab.showMarkdownPreview) ...[
                const SizedBox(width: 8),
                Icon(
                  Icons.lock_outline_rounded,
                  size: 14,
                  color: cs.onSurfaceVariant,
                ),
                const SizedBox(width: 4),
                Text(
                  context.l10n.textEditorReadOnlyIndicatorLabel,
                  style: TextStyle(
                    color: cs.onSurfaceVariant,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ] else if (activeTab.isAutosaving) ...[
                const SizedBox(width: 8),
                SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.8,
                    color: cs.primary,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  context.l10n.autosavingLabel,
                  style: TextStyle(
                    color: cs.primary,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ] else if (activeTab.isSaving) ...[
                const SizedBox(width: 8),
                Text(
                  context.l10n.savingLabel,
                  style: TextStyle(
                    color: cs.primary,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
