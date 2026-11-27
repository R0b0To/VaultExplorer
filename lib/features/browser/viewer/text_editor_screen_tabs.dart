part of 'text_editor_screen.dart';

/// Opening, switching, renaming, closing and reordering tabs, and the tab bar
/// scrolling.
///
/// Moved out of [_TextEditorScreenState] as is: an extension in the
/// same library reads and writes the state's private fields exactly as the
/// class did.
extension _TextEditorTabs on _TextEditorScreenState {
  void _animateTabBar(double value) {
    _tabBarAnimationController.animateTo(value, curve: Curves.easeOutCubic);
  }

  bool _handleTabBarScroll(ScrollNotification notification) {
    if (notification.metrics.axis != Axis.vertical) return false;
    final appearance = ref.read(textEditorAppearanceProvider);
    if (!appearance.showTabBar || !appearance.autoHideTabBar) return false;

    // Dragging the fast-scroll handle scrolls with a stream of `jumpTo`
    // calls. In word-wrap mode the scroll extent is only an estimate, so
    // those jumps come back with alternating signs; read as scroll
    // direction they made the strip flicker. The strip stays put until the
    // handle is released (see _onScrollbarDragStateChanged).
    if (_scrollbarDragging) return false;

    final canScroll = notification.metrics.maxScrollExtent > 0;
    if (notification is ScrollUpdateNotification) {
      final delta = notification.scrollDelta ?? 0.0;
      if (canScroll && notification.metrics.pixels <= 0 && delta <= 0) {
        _tabBarAnimationController.value = 1;
      } else if (delta != 0) {
        final nextValue =
            (_tabBarAnimationController.value -
                    delta / _TextEditorScreenState._kTabStripHeight)
                .clamp(0.0, 1.0);
        _tabBarAnimationController.value = nextValue;
      }
    } else if (notification is OverscrollNotification) {
      final delta = notification.overscroll;
      if (delta != 0) {
        final nextValue =
            (_tabBarAnimationController.value -
                    delta / _TextEditorScreenState._kTabStripHeight)
                .clamp(0.0, 1.0);
        _tabBarAnimationController.value = nextValue;
      }
    } else if (notification is ScrollEndNotification) {
      final double target;
      if (canScroll && notification.metrics.pixels <= 0) {
        target = 1;
      } else if (_tabBarAnimationController.value > 0 &&
          _tabBarAnimationController.value < 1) {
        target = _tabBarAnimationController.value >= 0.5 ? 1 : 0;
      } else {
        return false;
      }
      _animateTabBar(target);
    }
    return false;
  }

  void _onScrollbarDragStateChanged(bool dragging) {
    _scrollbarDragging = dragging;
    if (dragging || !mounted || _tabs.isEmpty) return;
    final appearance = ref.read(textEditorAppearanceProvider);
    if (!appearance.showTabBar || !appearance.autoHideTabBar) return;
    // The handle was released: show the strip if the editor ended up at the
    // top, otherwise leave it as it was but never stranded half-way.
    double? atTop;
    final tab = _activeTab;
    // The handle may have been dragging the markdown preview, which scrolls
    // with its own controller.
    final controller = (tab.isMarkdownFile && tab.showMarkdownPreview)
        ? tab.previewScrollController
        : tab.verticalScrollController;
    if (controller.hasClients) {
      final pos = controller.position;
      if (pos.hasPixels && pos.pixels <= 0) atTop = 1;
    }
    final value = _tabBarAnimationController.value;
    final target = atTop ?? (value >= 0.5 ? 1.0 : 0.0);
    if (value != target) _animateTabBar(target);
  }

  /// The tab strip's "+": creates a new file next to the file being edited
  /// and opens it in a new tab.
  Future<void> _createNewFileFromTabBar() async {
    var parentDir = _projectDirPath;
    if (_tabs.isNotEmpty) {
      final activePath = _activeTab.filePath;
      final slash = activePath.lastIndexOf('/');
      parentDir = slash >= 0 ? activePath.substring(0, slash) : '';
    }
    final newFilePath = await _promptAndCreateEmptyFile(
      context: context,
      ref: ref,
      container: widget.container,
      parentDir: parentDir,
    );
    if (newFilePath == null || !mounted) return;
    _openFileInTab(newFilePath);
  }

  void _scrollToActiveTab() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _activeTabIndex < 0 || _activeTabIndex >= _tabs.length) {
        return;
      }
      final tabContext = _tabs[_activeTabIndex].tabContext;
      if (tabContext != null && tabContext.mounted) {
        Scrollable.ensureVisible(
          tabContext,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeInOut,
          alignment: 0.5,
        );
      }
    });
  }

  Future<void> _closeOtherTabs(int keepIndex) async {
    final keepTab = _tabs[keepIndex];
    for (int i = _tabs.length - 1; i >= 0; i--) {
      if (!mounted) break;
      if (i != _tabs.indexOf(keepTab)) {
        await _closeTab(i);
      }
    }
  }

  Future<void> _closeAllTabs() async {
    for (int i = _tabs.length - 1; i >= 0; i--) {
      if (!mounted) break;
      await _closeTab(i);
    }
  }

  Future<void> _showTabMenu(EditorTab tab, BuildContext tabContext) async {
    if (!tabContext.mounted) return;
    final tabBox = tabContext.findRenderObject() as RenderBox?;
    final overlayBox =
        Overlay.of(tabContext).context.findRenderObject() as RenderBox?;
    if (tabBox == null ||
        overlayBox == null ||
        !tabBox.attached ||
        !tabBox.hasSize) {
      return;
    }
    final topLeft = tabBox.localToGlobal(Offset.zero, ancestor: overlayBox);
    final bottomRight = tabBox.localToGlobal(
      tabBox.size.bottomRight(Offset.zero),
      ancestor: overlayBox,
    );
    final anchor = Rect.fromLTRB(
      topLeft.dx,
      bottomRight.dy,
      bottomRight.dx,
      bottomRight.dy,
    );

    PopupMenuItem<_TabMenuAction> item(
      _TabMenuAction value,
      IconData icon,
      String label, {
      bool enabled = true,
    }) {
      return PopupMenuItem<_TabMenuAction>(
        value: value,
        enabled: enabled,
        child: Row(
          children: [
            Icon(icon, size: 20),
            const SizedBox(width: 12),
            Text(label),
          ],
        ),
      );
    }

    final l10n = context.l10n;
    final choice = await showMenu<_TabMenuAction>(
      context: tabContext,
      position: RelativeRect.fromRect(anchor, Offset.zero & overlayBox.size),
      items: [
        item(_TabMenuAction.close, Icons.close_rounded, l10n.textEditorCloseTab),
        item(
          _TabMenuAction.closeOthers,
          Icons.tab_unselected_rounded,
          l10n.textEditorCloseOtherTabs,
          enabled: _tabs.length > 1,
        ),
        item(
          _TabMenuAction.closeAll,
          Icons.clear_all_rounded,
          l10n.textEditorCloseAllTabs,
        ),
        const PopupMenuDivider(),
        item(
          _TabMenuAction.rename,
          Icons.edit_outlined,
          l10n.textEditorRenameMenuItem,
        ),
      ],
    );
    if (!mounted || choice == null) return;

    final index = _tabs.indexOf(tab);
    if (index < 0) return;
    switch (choice) {
      case _TabMenuAction.close:
        await _closeTab(index);
      case _TabMenuAction.closeOthers:
        await _closeOtherTabs(index);
      case _TabMenuAction.closeAll:
        await _closeAllTabs();
      case _TabMenuAction.rename:
        await _renameTab(tab);
    }
  }

  void _closeTabsForDeletedPath(String deletedPath, bool isDir) {
    final toClose = <int>[];
    for (int i = _tabs.length - 1; i >= 0; i--) {
      final t = _tabs[i];
      if (t.filePath == deletedPath ||
          (isDir && t.filePath.startsWith('$deletedPath/'))) {
        toClose.add(i);
      }
    }
    for (final idx in toClose) {
      _unbindTabController(_tabs[idx]);
      _tabs[idx].dispose();
      _tabs.removeAt(idx);
    }
    if (_tabs.isEmpty) {
      final newTab = EditorTab(filePath: 'untitled.txt');
      _bindTabController(newTab);
      _tabs.add(newTab);
    }
    _activeTabIndex = _activeTabIndex.clamp(0, _tabs.length - 1);
  }
}
