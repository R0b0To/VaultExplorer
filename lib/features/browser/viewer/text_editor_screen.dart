import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/rendering.dart' show AxisDirection;
import 'package:flutter/scheduler.dart' show SchedulerBinding, SchedulerPhase;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:re_editor/re_editor.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/filesystem/local_storage_container.dart';
import 'package:vaultexplorer/core/providers/vault_engine_providers.dart';
import 'package:vaultexplorer/core/theme/file_manager_skin_scope.dart';
import 'package:vaultexplorer/core/utils/raw_entry.dart';
import 'package:vaultexplorer/core/widgets/common_widgets.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/data/services/text_editor_appearance_service.dart';
import 'package:vaultexplorer/features/browser/viewer/markdown/markdown_body_view.dart';
import 'package:vaultexplorer/features/browser/viewer/text_editor_appearance_provider.dart';
import 'package:vaultexplorer/features/browser/viewer/text_editor_chrome.dart';
import 'package:vaultexplorer/features/browser/viewer/editor_text_encoding.dart';
import 'package:vaultexplorer/features/browser/viewer/text_editor_formatters.dart';
import 'package:vaultexplorer/features/browser/viewer/text_editor_language.dart';
import 'package:vaultexplorer/features/browser/viewer/widgets/editor_accessory_key_bar.dart';
import 'package:vaultexplorer/features/browser/viewer/widgets/editor_appearance_sheet.dart';
import 'package:vaultexplorer/features/browser/controllers/file_browser_navigation_controller.dart'
    show PathSegment;
import 'package:vaultexplorer/features/browser/viewer/widgets/editor_find_panel.dart';
import 'package:vaultexplorer/features/browser/viewer/widgets/markdown_image.dart';
import 'package:vaultexplorer/features/settings/file_manager_toolbar_settings_controller.dart';
import 'package:vaultexplorer/data/models/file_manager_skin.dart';
import 'package:vaultexplorer/features/browser/widgets/breadcrumb_bar.dart';
import 'package:vaultexplorer/features/browser/widgets/fast_scrollbar.dart';

class EditorTab {
  String filePath;
  final CodeLineEditingController codeController;
  late final CodeFindController findController;
  final ScrollController verticalScrollController = ScrollController();
  final ScrollController horizontalScrollController = ScrollController();
  late final CodeScrollController scrollController;
  final GlobalKey<MarkdownBodyViewState> previewKey =
      GlobalKey<MarkdownBodyViewState>();
  final ScrollController previewScrollController = ScrollController();

  bool isLoading = true;
  bool hasError = false;
  String errorMessage = '';
  bool isDirty = false;
  bool isSaving = false;
  bool isAutosaving = false;
  int lineCount = 0;
  int charCount = 0;
  int cursorLine = 1;
  int cursorCol = 1;
  DateTime? lastSavedAt;
  bool lastSaveWasAutosave = false;
  bool appliedInitialText = false;
  String lastKnownText = '';
  Object? lastCodeLines;
  bool showMarkdownPreview;
  EditorTextEncoding encoding = EditorTextEncoding.utf8;
  bool encodingWasChosen = false;
  Timer? autosaveTimer;
  VoidCallback? textListener;

  EditorTab({
    required this.filePath,
    String initialText = '',
    bool isMarkdown = false,
  }) : codeController = CodeLineEditingController.fromText(initialText),
       showMarkdownPreview = isMarkdown {
    findController = CodeFindController(codeController);
    scrollController = CodeScrollController(
      verticalScroller: verticalScrollController,
      horizontalScroller: horizontalScrollController,
    );
  }

  String get fileName =>
      filePath.contains('/') ? filePath.split('/').last : filePath;

  bool get isMarkdownFile =>
      filePath.toLowerCase().endsWith('.md') ||
      filePath.toLowerCase().endsWith('.markdown');

  void dispose() {
    autosaveTimer?.cancel();
    findController.dispose();
    codeController.dispose();
    previewScrollController.dispose();
    verticalScrollController.dispose();
    horizontalScrollController.dispose();
  }
}

class TextEditorScreen extends ConsumerStatefulWidget {
  final MountedContainer container;
  final String filePath;

  const TextEditorScreen({
    super.key,
    required this.container,
    required this.filePath,
  });

  @override
  ConsumerState<TextEditorScreen> createState() => _TextEditorScreenState();
}

class _TextEditorScreenState extends ConsumerState<TextEditorScreen>
    with WidgetsBindingObserver, TickerProviderStateMixin {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final List<EditorTab> _tabs = [];
  int _activeTabIndex = 0;

  final ScrollController _tabScrollController = ScrollController();
  final List<GlobalKey> _tabKeys = [];
  late final AnimationController _tabBarAnimationController;

  // Pinch-to-zoom state
  final Map<int, Offset> _pinchPointers = {};
  double? _initialPinchDistance;
  double _pinchStartFontSize = 14.0;

  bool _readOnly = false;
  bool _wordWrap = true;
  final EditorFocusNode _focusNode = EditorFocusNode();
  late final SelectionToolbarController _toolbarController;

  late String _projectDirPath;

  /// Last resolved whole-screen theme, reused until the editor colors or the
  /// app scheme actually change (see [EditorChrome.matches]).
  EditorChrome? _chrome;

  EditorChrome _resolveChrome(EditorSyntaxStyle style, ColorScheme appScheme) {
    final cached = _chrome;
    if (cached != null &&
        cached.matches(style.backgroundColor, style.textColor, appScheme)) {
      return cached;
    }
    return _chrome = EditorChrome.resolve(
      background: style.backgroundColor,
      foreground: style.textColor,
      appScheme: appScheme,
    );
  }

  EditorTab get _activeTab => _tabs[_activeTabIndex];

  @override
  void initState() {
    super.initState();
    _tabBarAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 180),
      value: 1,
    )..addListener(_onTabBarAnimationTick);
    _readOnly = widget.container.readOnly;
    WidgetsBinding.instance.addObserver(this);
    _toolbarController = MobileSelectionToolbarController(
      builder:
          ({
            required BuildContext context,
            required TextSelectionToolbarAnchors anchors,
            required CodeLineEditingController controller,
            required VoidCallback onDismiss,
            required VoidCallback onRefresh,
          }) {
            final items = <ContextMenuButtonItem>[
              if (!_readOnly && !controller.selection.isCollapsed)
                ContextMenuButtonItem(
                  onPressed: () {
                    controller.cut();
                    onDismiss();
                  },
                  type: ContextMenuButtonType.cut,
                ),
              if (!controller.selection.isCollapsed)
                ContextMenuButtonItem(
                  onPressed: () {
                    controller.copy();
                    onDismiss();
                  },
                  type: ContextMenuButtonType.copy,
                ),
              if (!_readOnly)
                ContextMenuButtonItem(
                  onPressed: () {
                    controller.paste();
                    onDismiss();
                  },
                  type: ContextMenuButtonType.paste,
                ),
              if (!controller.isAllSelected)
                ContextMenuButtonItem(
                  onPressed: () {
                    controller.selectAll();
                    onRefresh();
                  },
                  type: ContextMenuButtonType.selectAll,
                ),
            ];

            if (items.isEmpty) {
              return const SizedBox.shrink();
            }

            final appTheme = Theme.of(this.context);
            final cs = appTheme.colorScheme;

            // Resolve current editor background to check for color collisions
            final appearance = ref.read(textEditorAppearanceProvider);
            final editorStyle = resolveEditorSyntaxStyle(
              _activeTab.filePath,
              appTheme.brightness,
              cs,
              background: appearance.background,
              syntaxTheme: appearance.syntaxTheme,
            );
            final editorBg = editorStyle.backgroundColor;

            // Base floating toolbar surface color
            Color surfaceColor = cs.surfaceContainerHigh;

            // If the floating menu and editor background share almost the exact same darkness,
            // boost the surface tone slightly so the card doesn't wash into the background.
            final lumDiff =
                (surfaceColor.computeLuminance() - editorBg.computeLuminance())
                    .abs();
            if (lumDiff < 0.06) {
              surfaceColor = editorBg.computeLuminance() < 0.5
                  ? Color.alphaBlend(
                      Colors.white.withValues(alpha: 0.12),
                      surfaceColor,
                    )
                  : Color.alphaBlend(
                      Colors.black.withValues(alpha: 0.08),
                      surfaceColor,
                    );
            }

            return Theme(
              data: appTheme,
              child: TextSelectionToolbar(
                anchorAbove: anchors.primaryAnchor,
                anchorBelow: anchors.secondaryAnchor ?? anchors.primaryAnchor,
                toolbarBuilder: (context, child) {
                  return Material(
                    color: surfaceColor,
                    elevation: 6,
                    shadowColor: Colors.black.withValues(alpha: 0.55),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(
                        color: cs.outlineVariant.withValues(alpha: 0.8),
                        width: 1,
                      ),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: child,
                  );
                },
                children: AdaptiveTextSelectionToolbar.getAdaptiveButtons(
                  context,
                  items,
                ).toList(),
              ),
            );
          },
    );

    final slash = widget.filePath.lastIndexOf('/');
    _projectDirPath = slash >= 0 ? widget.filePath.substring(0, slash) : '';

    final initialTab = EditorTab(
      filePath: widget.filePath,
      isMarkdown:
          widget.filePath.toLowerCase().endsWith('.md') ||
          widget.filePath.toLowerCase().endsWith('.markdown'),
    );
    _tabs.add(initialTab);
    _bindTabController(initialTab);

    Future.microtask(() => _loadFileForTab(initialTab));
  }

  void _bindTabController(EditorTab tab) {
    tab.textListener = () => _onTabTextChanged(tab);
    tab.codeController.addListener(tab.textListener!);
    tab.findController.addListener(_onFindChanged);
  }

  void _unbindTabController(EditorTab tab) {
    tab.autosaveTimer?.cancel();
    if (tab.textListener != null) {
      tab.codeController.removeListener(tab.textListener!);
      tab.textListener = null;
    }
    tab.findController.removeListener(_onFindChanged);
  }

  void _onFindChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _loadFileForTab(
    EditorTab tab, {
    EditorTextEncoding? encoding,
    bool markDirty = false,
  }) async {
    final l10n = context.l10n;
    setState(() {
      tab.isLoading = true;
      tab.hasError = false;
      tab.errorMessage = '';
    });

    try {
      final bytes = await ref
          .read(vaultFileIoApiProvider)
          .readWholeFile(widget.container, tab.filePath);
      if (bytes == null) {
        throw Exception(l10n.textEditorDecryptFailedMessage);
      }
      if (encoding != null) {
        tab.encoding = encoding;
        tab.encodingWasChosen = true;
      } else if (!tab.encodingWasChosen) {
        tab.encoding = EditorTextEncoding.detect(bytes);
      }
      String text;
      try {
        text = await tab.encoding.decode(bytes);
      } on FormatException {
        throw FormatException(l10n.textEditorInvalidTextFileMessage);
      }

      if (!mounted) return;
      tab.appliedInitialText = true;
      tab.lastKnownText = text;
      tab.codeController.text = text;
      tab.lastCodeLines = tab.codeController.value.codeLines;
      tab.codeController.clearHistory();
      tab.lineCount = tab.codeController.lineCount;
      tab.charCount = text.length;
      tab.isLoading = false;
      tab.isDirty = markDirty;
      if (mounted) setState(() {});
    } catch (e) {
      if (!mounted) return;
      setState(() {
        tab.isLoading = false;
        tab.hasError = true;
        tab.errorMessage = e.toString();
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      final appearance = ref.read(textEditorAppearanceProvider);
      if (appearance.autoSave) {
        for (final tab in _tabs.where(
          (t) => t.isDirty && !t.isSaving && !t.isAutosaving,
        )) {
          _saveFile(tab, isAutosave: true);
        }
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tabBarAnimationController.dispose();
    _tabScrollController.dispose();
    for (final tab in _tabs) {
      _unbindTabController(tab);
      tab.dispose();
    }
    _focusNode.dispose();
    super.dispose();
  }

  void _onTabBarAnimationTick() {
    if (mounted) setState(() {});
  }

  void _animateTabBar(double value) {
    _tabBarAnimationController.animateTo(value, curve: Curves.easeOutCubic);
  }

  bool _handleTabBarScroll(ScrollNotification notification) {
    if (notification.metrics.axis != Axis.vertical) return false;
    final appearance = ref.read(textEditorAppearanceProvider);
    if (!appearance.showTabBar || !appearance.autoHideTabBar) return false;

    final canScroll = notification.metrics.maxScrollExtent > 0;
    if (notification is ScrollUpdateNotification) {
      final delta = notification.scrollDelta ?? 0.0;
      if (canScroll && notification.metrics.pixels <= 0 && delta <= 0) {
        _tabBarAnimationController.value = 1;
      } else if (delta != 0) {
        final nextValue = (_tabBarAnimationController.value - delta / 42).clamp(
          0.0,
          1.0,
        );
        _tabBarAnimationController.value = nextValue;
      }
    } else if (notification is OverscrollNotification) {
      final delta = notification.overscroll;
      if (delta != 0) {
        final nextValue = (_tabBarAnimationController.value - delta / 42).clamp(
          0.0,
          1.0,
        );
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

  void _onTabTextChanged(EditorTab tab) {
    final selection = tab.codeController.selection;
    final lineCount = tab.codeController.lineCount;
    final newLine = (selection.extentIndex + 1).clamp(
      1,
      lineCount > 0 ? lineCount : 1,
    );
    final newCol = selection.extentOffset + 1;

    final cursorChanged = tab.cursorLine != newLine || tab.cursorCol != newCol;
    if (cursorChanged) {
      tab.cursorLine = newLine;
      tab.cursorCol = newCol;
    }

    final codeLines = tab.codeController.value.codeLines;
    final isSameCodeLines = identical(codeLines, tab.lastCodeLines);
    final currentText = tab.codeController.text;
    final isSameText = currentText == tab.lastKnownText;

    final isBusyBuilding =
        SchedulerBinding.instance.schedulerPhase ==
            SchedulerPhase.persistentCallbacks ||
        (WidgetsBinding.instance.buildOwner?.debugBuilding ?? false);

    if (isSameCodeLines || isSameText) {
      tab.lastCodeLines = codeLines;
      if (!cursorChanged) return;

      void updateCursor() {
        if (!mounted) return;
        setState(() {});
      }

      if (isBusyBuilding) {
        WidgetsBinding.instance.addPostFrameCallback((_) => updateCursor());
      } else {
        updateCursor();
      }
      return;
    }

    tab.lastCodeLines = codeLines;
    tab.lastKnownText = currentText;

    void updateState() {
      if (!mounted) return;
      setState(() {
        tab.isDirty = true;
        tab.lineCount = tab.codeController.lineCount;
        tab.charCount = currentText.length;
      });
    }

    if (isBusyBuilding) {
      WidgetsBinding.instance.addPostFrameCallback((_) => updateState());
    } else {
      updateState();
    }

    tab.autosaveTimer?.cancel();
    final appearance = ref.read(textEditorAppearanceProvider);

    if (appearance.autoSave && !tab.isLoading && !tab.hasError) {
      tab.autosaveTimer = Timer(const Duration(milliseconds: 2500), () {
        final currentAppearance = ref.read(textEditorAppearanceProvider);
        if (mounted &&
            currentAppearance.autoSave &&
            tab.isDirty &&
            !tab.isSaving &&
            !tab.isAutosaving) {
          _saveFile(tab, isAutosave: true);
        }
      });
    }
  }

  Future<void> _showEncodingPicker(EditorTab tab) async {
    final encodings = await EditorTextEncoding.available();
    if (!mounted) return;
    final encoding = await showDialog<EditorTextEncoding>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: Text(dialogContext.l10n.textEditorEncodingTooltip),
        children: [
          for (final option in encodings)
            SimpleDialogOption(
              onPressed: () => Navigator.of(dialogContext).pop(option),
              child: Row(
                children: [
                  Expanded(child: Text(option.label)),
                  if (tab.encoding.name == option.name)
                    Icon(
                      Icons.check_rounded,
                      size: 18,
                      color: Theme.of(dialogContext).colorScheme.primary,
                    ),
                ],
              ),
            ),
        ],
      ),
    );
    if (encoding != null) await _changeEncoding(tab, encoding);
  }

  Future<void> _changeEncoding(
    EditorTab tab,
    EditorTextEncoding encoding,
  ) async {
    if (tab.encoding == encoding && !tab.hasError) return;
    if (tab.isDirty) {
      setState(() {
        tab.encoding = encoding;
        tab.encodingWasChosen = true;
      });
      return;
    }
    await _loadFileForTab(tab, encoding: encoding, markDirty: true);
  }

  Future<Uint8List?> _encodeTabContent(EditorTab tab) async {
    try {
      return await tab.encoding.encode(tab.codeController.text);
    } on FormatException {
      if (mounted) {
        showAppSnackBar(
          context,
          message: context.l10n.textEditorEncodingEncodeError,
          tone: AppBannerTone.error,
        );
      }
      return null;
    }
  }

  Future<bool> _saveFile(EditorTab tab, {bool isAutosave = false}) async {
    tab.autosaveTimer?.cancel();

    final encodedContent = await _encodeTabContent(tab);
    if (encodedContent == null) return false;

    setState(() {
      if (isAutosave) {
        tab.isAutosaving = true;
      } else {
        tab.isSaving = true;
      }
    });

    final content = tab.codeController.text;
    final ok = await ref
        .read(vaultFileIoApiProvider)
        .writeWholeFile(widget.container, tab.filePath, encodedContent);

    if (ok) {
      if (mounted) {
        tab.lastKnownText = content;
        tab.lastCodeLines = tab.codeController.value.codeLines;
        setState(() {
          tab.isSaving = false;
          tab.isAutosaving = false;
          tab.isDirty = false;
          tab.lastSavedAt = DateTime.now();
          tab.lastSaveWasAutosave = isAutosave;
        });

        if (!isAutosave) {
          showAppSnackBar(
            context,
            message: context.l10n.changesSavedSuccessfully,
            tone: AppBannerTone.success,
          );
        }
      }
      return true;
    } else {
      if (mounted) {
        setState(() {
          tab.isSaving = false;
          tab.isAutosaving = false;
        });

        if (!isAutosave) {
          showAppSnackBar(
            context,
            message: context.l10n.saveFailedWithError(
              context.l10n.textEditorWriteBackFailedMessage,
            ),
            tone: AppBannerTone.error,
          );
        }
      }
      return false;
    }
  }

  Future<bool> _onWillPop() async {
    final anyDirty = _tabs.any((t) => t.isDirty);
    if (!anyDirty) return true;

    final appearance = ref.read(textEditorAppearanceProvider);
    if (appearance.autoSave) {
      for (final tab in _tabs.where((t) => t.isDirty)) {
        await _saveFile(tab, isAutosave: true);
      }
      return true;
    }

    if (!mounted) return true;
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.unsavedChangesTitle),
        content: Text(context.l10n.unsavedChangesMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop('discard'),
            child: Text(
              context.l10n.discardButton,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop('cancel'),
            child: Text(context.l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop('save'),
            child: Text(context.l10n.save),
          ),
        ],
      ),
    );

    if (result == 'save') {
      for (final tab in _tabs.where((t) => t.isDirty)) {
        await _saveFile(tab);
      }
      return true;
    } else if (result == 'discard') {
      return true;
    }
    return false;
  }

  void _openFileInTab(String filePath) {
    if (ref.read(textEditorAppearanceProvider).showTabBar) {
      // A short file may not produce scroll notifications, so it cannot
      // reveal a tab bar that was hidden while viewing a longer file.
      _animateTabBar(1);
    }

    final existingIndex = _tabs.indexWhere((t) => t.filePath == filePath);
    if (existingIndex != -1) {
      setState(() => _activeTabIndex = existingIndex);
      return;
    }

    final newTab = EditorTab(
      filePath: filePath,
      isMarkdown:
          filePath.toLowerCase().endsWith('.md') ||
          filePath.toLowerCase().endsWith('.markdown'),
    );
    _bindTabController(newTab);
    setState(() {
      _tabs.add(newTab);
      _activeTabIndex = _tabs.length - 1;
    });
    _scrollToActiveTab();

    _loadFileForTab(newTab);
  }

  void _scrollToActiveTab() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_activeTabIndex >= 0 && _activeTabIndex < _tabKeys.length) {
        final keyContext = _tabKeys[_activeTabIndex].currentContext;
        if (keyContext != null) {
          Scrollable.ensureVisible(
            keyContext,
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeInOut,
            alignment: 0.5,
          );
        }
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

  void _showTabContextMenu(int index) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.close_rounded),
              title: Text(ctx.l10n.textEditorCloseTab),
              onTap: () {
                Navigator.of(ctx).pop();
                _closeTab(index);
              },
            ),
            ListTile(
              leading: const Icon(Icons.tab_unselected_rounded),
              title: Text(ctx.l10n.textEditorCloseOtherTabs),
              onTap: () {
                Navigator.of(ctx).pop();
                _closeOtherTabs(index);
              },
            ),
            ListTile(
              leading: const Icon(Icons.clear_all_rounded),
              title: Text(ctx.l10n.textEditorCloseAllTabs),
              onTap: () {
                Navigator.of(ctx).pop();
                _closeAllTabs();
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _closeTab(int index) async {
    if (index < 0 || index >= _tabs.length) return;
    final tab = _tabs[index];
    if (tab.isDirty) {
      final shouldClose = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(ctx.l10n.unsavedChangesTitle),
          content: Text(ctx.l10n.unsavedChangesMessage),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(
                ctx.l10n.discardButton,
                style: TextStyle(color: Theme.of(ctx).colorScheme.error),
              ),
            ),
            FilledButton(
              onPressed: () async {
                final saved = await _saveFile(tab);
                if (ctx.mounted) Navigator.of(ctx).pop(saved);
              },
              child: Text(ctx.l10n.save),
            ),
          ],
        ),
      );

      if (shouldClose != true) return;
    }

    if (_tabs.length == 1) {
      if (mounted) Navigator.of(context).pop();
      return;
    }

    _unbindTabController(tab);
    tab.dispose();

    setState(() {
      _tabs.removeAt(index);
      _activeTabIndex = _activeTabIndex.clamp(0, _tabs.length - 1);
    });
    _scrollToActiveTab();
  }

  Future<void> _createNewFileTab() async {
    final parentDir = _projectDirPath;
    final controller = TextEditingController.fromValue(
      const TextEditingValue(
        text: 'untitled.txt',
        selection: TextSelection(baseOffset: 0, extentOffset: 8),
      ),
    );
    final formKey = GlobalKey<FormState>();

    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.l10n.textEditorNewFileTooltip),
        content: Form(
          key: formKey,
          child: TextFormField(
            controller: controller,
            autofocus: true,
            decoration: InputDecoration(
              labelText: ctx.l10n.textEditorSaveAsFileNameLabel,
            ),
            validator: (val) {
              final text = val?.trim() ?? '';
              if (text.isEmpty) return ctx.l10n.validationEmptyName;
              if (text.contains('/') || text.contains('\\')) {
                return ctx.l10n.validationIllegalChar('/', 0, 'vault');
              }
              return null;
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(ctx.l10n.cancel),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState?.validate() ?? false) {
                Navigator.of(ctx).pop(controller.text.trim());
              }
            },
            child: Text(ctx.l10n.done),
          ),
        ],
      ),
    );

    if (result == null || !mounted) return;
    final newFilePath = parentDir.isEmpty ? result : '$parentDir/$result';

    final rawList = await ref
        .read(vaultFileIoApiProvider)
        .listDirectory(widget.container, parentDir);
    final existingNames = RawEntry.parseAll(
      rawList ?? const [],
    ).map((e) => e.name.toLowerCase()).toSet();

    if (existingNames.contains(result.toLowerCase()) && mounted) {
      showAppSnackBar(
        context,
        message: context.l10n.textEditorFileAlreadyExistsError,
        tone: AppBannerTone.error,
      );
      return;
    }

    final ok = await ref
        .read(vaultFileIoApiProvider)
        .createEmptyFile(widget.container, newFilePath);

    if (ok && mounted) {
      _openFileInTab(newFilePath);
      _scrollToActiveTab();
    } else if (mounted) {
      showAppSnackBar(
        context,
        message: context.l10n.saveFailedWithError(''),
        tone: AppBannerTone.error,
      );
    }
  }

  Future<void> _createDrawerFolder() async {
    final parentDir = _projectDirPath;
    final controller = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.l10n.textEditorNewFolderDialogTitle),
        content: Form(
          key: formKey,
          child: TextFormField(
            controller: controller,
            autofocus: true,
            decoration: InputDecoration(
              labelText: ctx.l10n.textEditorNewFolderFieldLabel,
            ),
            validator: (val) {
              final text = val?.trim() ?? '';
              if (text.isEmpty) return ctx.l10n.validationEmptyName;
              if (text.contains('/') || text.contains('\\')) {
                return ctx.l10n.validationIllegalChar('/', 0, 'vault');
              }
              return null;
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(ctx.l10n.cancel),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState?.validate() ?? false) {
                Navigator.of(ctx).pop(controller.text.trim());
              }
            },
            child: Text(ctx.l10n.done),
          ),
        ],
      ),
    );

    if (result == null || !mounted) return;
    final newDirPath = parentDir.isEmpty ? result : '$parentDir/$result';

    final ok = await ref
        .read(vaultFileIoApiProvider)
        .createDirectory(widget.container, newDirPath);

    if (ok && mounted) {
      setState(() {});
    } else if (mounted) {
      showAppSnackBar(
        context,
        message: context.l10n.saveFailedWithError(''),
        tone: AppBannerTone.error,
      );
    }
  }

  void _syncRenamedPath(String oldPath, String newPath, bool isDir) {
    for (final tab in _tabs) {
      if (isDir) {
        if (tab.filePath == oldPath) {
          tab.filePath = newPath;
        } else if (tab.filePath.startsWith('$oldPath/')) {
          tab.filePath = '$newPath${tab.filePath.substring(oldPath.length)}';
        }
      } else {
        if (tab.filePath == oldPath) {
          tab.filePath = newPath;
        }
      }
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

  Future<void> _renameDrawerItem(RawEntry entry, String fullPath) async {
    final parentDir = _projectDirPath;
    final controller = TextEditingController(text: entry.name);
    final formKey = GlobalKey<FormState>();

    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.l10n.textEditorRenameDialogTitle),
        content: Form(
          key: formKey,
          child: TextFormField(
            controller: controller,
            autofocus: true,
            decoration: InputDecoration(
              labelText: entry.isDir
                  ? ctx.l10n.textEditorNewFolderFieldLabel
                  : ctx.l10n.textEditorSaveAsFileNameLabel,
            ),
            validator: (val) {
              final text = val?.trim() ?? '';
              if (text.isEmpty) return ctx.l10n.validationEmptyName;
              if (text.contains('/') || text.contains('\\')) {
                return ctx.l10n.validationIllegalChar('/', 0, 'vault');
              }
              return null;
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(ctx.l10n.cancel),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState?.validate() ?? false) {
                Navigator.of(ctx).pop(controller.text.trim());
              }
            },
            child: Text(ctx.l10n.done),
          ),
        ],
      ),
    );

    if (result == null || result == entry.name || !mounted) return;
    final newFullPath = parentDir.isEmpty ? result : '$parentDir/$result';

    final ok = await ref
        .read(vaultFileIoApiProvider)
        .renameFile(widget.container, fullPath, newFullPath);

    if (ok && mounted) {
      _syncRenamedPath(fullPath, newFullPath, entry.isDir);
      setState(() {});
    } else if (mounted) {
      showAppSnackBar(
        context,
        message: context.l10n.saveFailedWithError(''),
        tone: AppBannerTone.error,
      );
    }
  }

  Future<void> _moveDrawerItem(RawEntry entry, String fullPath) async {
    final targetDir = await showDialog<String>(
      context: context,
      builder: (ctx) => _MoveToFolderDialog(
        container: widget.container,
        currentEntryPath: fullPath,
        isDir: entry.isDir,
      ),
    );

    if (targetDir == null || !mounted) return;
    final newFullPath = targetDir.isEmpty
        ? entry.name
        : '$targetDir/${entry.name}';
    if (newFullPath == fullPath) return;

    final ok = await ref
        .read(vaultFileIoApiProvider)
        .renameFile(widget.container, fullPath, newFullPath);

    if (ok && mounted) {
      _syncRenamedPath(fullPath, newFullPath, entry.isDir);
      setState(() {});
    } else if (mounted) {
      showAppSnackBar(
        context,
        message: context.l10n.saveFailedWithError(''),
        tone: AppBannerTone.error,
      );
    }
  }

  Future<void> _deleteDrawerItem(RawEntry entry, String fullPath) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.l10n.textEditorDeleteConfirmTitle(entry.name)),
        content: Text(ctx.l10n.textEditorDeleteConfirmMessage(entry.name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(ctx.l10n.cancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
              foregroundColor: Theme.of(ctx).colorScheme.onError,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(ctx.l10n.textEditorDeleteMenuItem),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    final ok = await ref
        .read(vaultFileIoApiProvider)
        .deleteFile(widget.container, fullPath);

    if (ok && mounted) {
      _closeTabsForDeletedPath(fullPath, entry.isDir);
      setState(() {});
    } else if (mounted) {
      showAppSnackBar(
        context,
        message: context.l10n.saveFailedWithError(''),
        tone: AppBannerTone.error,
      );
    }
  }

  void _showDrawerItemContextMenu(RawEntry entry, String fullPath) {
    final cs = Theme.of(context).colorScheme;
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: Text(ctx.l10n.textEditorRenameMenuItem),
              onTap: () {
                Navigator.of(ctx).pop();
                _renameDrawerItem(entry, fullPath);
              },
            ),
            ListTile(
              leading: const Icon(Icons.drive_file_move_outlined),
              title: Text(ctx.l10n.textEditorMoveToMenuItem),
              onTap: () {
                Navigator.of(ctx).pop();
                _moveDrawerItem(entry, fullPath);
              },
            ),
            ListTile(
              leading: Icon(Icons.delete_outline_rounded, color: cs.error),
              title: Text(
                ctx.l10n.textEditorDeleteMenuItem,
                style: TextStyle(color: cs.error),
              ),
              onTap: () {
                Navigator.of(ctx).pop();
                _deleteDrawerItem(entry, fullPath);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showSaveAsDialog() async {
    final currentTab = _activeTab;
    final lastSlash = currentTab.filePath.lastIndexOf('/');
    final parentDir = lastSlash >= 0
        ? currentTab.filePath.substring(0, lastSlash)
        : '';
    final fileName = currentTab.fileName;
    final controller = TextEditingController(text: fileName);
    final formKey = GlobalKey<FormState>();

    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.l10n.textEditorSaveAsDialogTitle),
        content: Form(
          key: formKey,
          child: TextFormField(
            controller: controller,
            autofocus: true,
            decoration: InputDecoration(
              labelText: ctx.l10n.textEditorSaveAsFileNameLabel,
            ),
            validator: (val) {
              final text = val?.trim() ?? '';
              if (text.isEmpty) return ctx.l10n.validationEmptyName;
              if (text.contains('/') || text.contains('\\')) {
                return ctx.l10n.validationIllegalChar('/', 0, 'vault');
              }
              return null;
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(ctx.l10n.cancel),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState?.validate() ?? false) {
                Navigator.of(ctx).pop(controller.text.trim());
              }
            },
            child: Text(ctx.l10n.textEditorSaveAsButton),
          ),
        ],
      ),
    );

    if (result == null || result == fileName) return;

    final newFilePath = parentDir.isEmpty ? result : '$parentDir/$result';

    final rawList = await ref
        .read(vaultFileIoApiProvider)
        .listDirectory(widget.container, parentDir);
    final existingNames = RawEntry.parseAll(
      rawList ?? const [],
    ).map((e) => e.name.toLowerCase()).toSet();

    if (existingNames.contains(result.toLowerCase()) && mounted) {
      final overwrite = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(ctx.l10n.conflictResolutionTitle),
          content: Text(ctx.l10n.textEditorFileAlreadyExistsError),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(ctx.l10n.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(ctx.l10n.replaceExistingFile),
            ),
          ],
        ),
      );

      if (overwrite != true) return;
    }

    final encodedContent = await _encodeTabContent(currentTab);
    if (encodedContent == null) return;
    final ok = await ref
        .read(vaultFileIoApiProvider)
        .writeWholeFile(widget.container, newFilePath, encodedContent);

    if (ok && mounted) {
      setState(() {
        currentTab.filePath = newFilePath;
        currentTab.isDirty = false;
        currentTab.lastSavedAt = DateTime.now();
      });
      showAppSnackBar(
        context,
        message: context.l10n.changesSavedSuccessfully,
        tone: AppBannerTone.success,
      );
    }
  }

  Future<void> _handleLinkTap(String url) async {
    try {
      final ok = await ref.read(vaultFileIoApiProvider).launchUrl(url);
      if (!ok && mounted) {
        showAppSnackBar(
          context,
          message: context.l10n.couldNotOpenLinkMessage,
          tone: AppBannerTone.error,
        );
      }
    } catch (_) {
      if (mounted) {
        showAppSnackBar(
          context,
          message: context.l10n.couldNotOpenLinkMessage,
          tone: AppBannerTone.error,
        );
      }
    }
  }

  void _toggleReadOnly() {
    if (widget.container.readOnly) return;
    setState(() => _readOnly = !_readOnly);
    if (_readOnly) {
      _focusNode.unfocus();
    }
  }

  void _toggleWordWrap() => setState(() => _wordWrap = !_wordWrap);

  CodeCommentFormatter _getCommentFormatter(String filePath) {
    final dot = filePath.lastIndexOf('.');
    if (dot < 0) return DefaultCodeCommentFormatter(singleLinePrefix: '//');
    final ext = filePath.substring(dot + 1).toLowerCase();
    switch (ext) {
      case 'py':
      case 'sh':
      case 'bash':
      case 'zsh':
      case 'yaml':
      case 'yml':
      case 'ini':
      case 'cfg':
      case 'conf':
      case 'properties':
      case 'dockerfile':
        return DefaultCodeCommentFormatter(singleLinePrefix: '#');
      case 'sql':
        return DefaultCodeCommentFormatter(
          singleLinePrefix: '--',
          multiLinePrefix: '/*',
          multiLineSuffix: '*/',
        );
      case 'html':
      case 'htm':
      case 'xml':
      case 'svg':
        return DefaultCodeCommentFormatter(
          multiLinePrefix: '<!--',
          multiLineSuffix: '-->',
        );
      default:
        return DefaultCodeCommentFormatter(
          singleLinePrefix: '//',
          multiLinePrefix: '/*',
          multiLineSuffix: '*/',
        );
    }
  }

  void _handleCommentShortcut() {
    if (_tabs.isEmpty || _readOnly) return;
    final tab = _activeTab;
    final formatter = _getCommentFormatter(tab.filePath);
    final value = formatter.format(
      tab.codeController.value,
      tab.codeController.options.indent,
      true,
    );
    tab.codeController.runRevocableOp(() {
      tab.codeController.value = value;
    });
  }

  void _handleSaveShortcut() {
    if (_tabs.isEmpty) return;
    final tab = _activeTab;
    if (tab.isDirty && !tab.isSaving && !tab.isAutosaving) {
      _saveFile(tab);
    }
  }

  void _handleFindShortcut() {
    if (_tabs.isEmpty) return;
    final tab = _activeTab;
    if (tab.showMarkdownPreview) {
      _toggleMarkdownPreview();
    }
    tab.findController.findMode();
  }

  void _handleCloseTabShortcut() {
    if (_tabs.isEmpty) return;
    _closeTab(_activeTabIndex);
  }

  void _handleNextTabShortcut() {
    if (_tabs.length <= 1) return;
    setState(() {
      _activeTabIndex = (_activeTabIndex + 1) % _tabs.length;
    });
    _scrollToActiveTab();
    _focusNode.requestFocus();
  }

  void _handlePreviousTabShortcut() {
    if (_tabs.length <= 1) return;
    setState(() {
      _activeTabIndex = (_activeTabIndex - 1 + _tabs.length) % _tabs.length;
    });
    _scrollToActiveTab();
    _focusNode.requestFocus();
  }

  void _handleGoToLineShortcut() {
    if (_tabs.isEmpty) return;
    _showGoToLineDialog();
  }

  void _handleUndoShortcut() {
    if (_tabs.isEmpty || _readOnly) return;
    _activeTab.codeController.undo();
  }

  void _handleRedoShortcut() {
    if (_tabs.isEmpty || _readOnly) return;
    _activeTab.codeController.redo();
  }

  void _handleIndentShortcut() {
    if (_tabs.isEmpty || _readOnly) return;
    _activeTab.codeController.applyIndent();
  }

  void _handleOutdentShortcut() {
    if (_tabs.isEmpty || _readOnly) return;
    _activeTab.codeController.applyOutdent();
  }

  void _handleMoveLineUp() {
    if (_tabs.isEmpty || _readOnly) return;
    _activeTab.codeController.moveSelectionLinesUp();
  }

  void _handleMoveLineDown() {
    if (_tabs.isEmpty || _readOnly) return;
    _activeTab.codeController.moveSelectionLinesDown();
  }

  void _handleSelectAllShortcut() {
    if (_tabs.isEmpty) return;
    final tab = _activeTab;

    if (tab.findController.findInputFocusNode.hasFocus) {
      tab.findController.findInputController.selection = TextSelection(
        baseOffset: 0,
        extentOffset: tab.findController.findInputController.text.length,
      );
      return;
    }
    if (tab.findController.replaceInputFocusNode.hasFocus) {
      tab.findController.replaceInputController.selection = TextSelection(
        baseOffset: 0,
        extentOffset: tab.findController.replaceInputController.text.length,
      );
      return;
    }

    if (_focusNode.canRequestFocus && !_focusNode.hasFocus) {
      _focusNode.requestFocus();
    }
    _selectAll();
  }

  void _toggleMarkdownPreview() {
    final tab = _activeTab;
    if (!tab.showMarkdownPreview) {
      final cursorLine = tab.codeController.selection.extentIndex.clamp(
        0,
        tab.codeController.lineCount - 1,
      );
      setState(() => tab.showMarkdownPreview = true);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        tab.previewKey.currentState?.scrollToLine(cursorLine);
      });
    } else {
      final visibleLine =
          tab.previewKey.currentState?.getFirstVisibleLine() ?? 0;
      setState(() => tab.showMarkdownPreview = false);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _goToLineIndex(visibleLine);
      });
    }
  }

  void _toggleMarkdownTask(int sourceLine, bool currentChecked) {
    final tab = _activeTab;
    if (_readOnly || tab.codeController.lineCount <= sourceLine) return;

    final lineText = tab.codeController.codeLines[sourceLine].text;
    String updatedLine;
    if (currentChecked) {
      updatedLine = lineText.replaceFirst(RegExp(r'\[[xX]\]'), '[ ]');
    } else {
      updatedLine = lineText.replaceFirst(RegExp(r'\[ \]'), '[x]');
    }

    if (updatedLine == lineText) return;

    final lines = tab.codeController.text.split('\n');
    if (sourceLine >= 0 && sourceLine < lines.length) {
      lines[sourceLine] = updatedLine;
      tab.codeController.text = lines.join('\n');
      if (mounted) setState(() {});
    }
  }

  Future<void> _insertImageTemplate() async {
    final imageExts = {'png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp', 'svg'};
    final currentTab = _activeTab;
    final lastSlash = currentTab.filePath.lastIndexOf('/');
    final parentDir = lastSlash >= 0
        ? currentTab.filePath.substring(0, lastSlash)
        : '';

    final rawList = await ref
        .read(vaultFileIoApiProvider)
        .listDirectory(widget.container, parentDir);

    final images = rawList == null
        ? <RawEntry>[]
        : RawEntry.parseAll(rawList).where((e) {
            if (e.isDir) return false;
            final dot = e.name.lastIndexOf('.');
            if (dot < 0) return false;
            return imageExts.contains(e.name.substring(dot + 1).toLowerCase());
          }).toList();

    if (!mounted) return;

    final selectedImage = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.l10n.selectImageTitle),
        content: SizedBox(
          width: double.maxFinite,
          child: images.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Text(ctx.l10n.noImagesFoundMessage),
                )
              : ListView.builder(
                  shrinkWrap: true,
                  itemCount: images.length,
                  itemBuilder: (context, index) {
                    final img = images[index];
                    return ListTile(
                      leading: const Icon(Icons.image_outlined),
                      title: Text(img.name),
                      onTap: () => Navigator.of(ctx).pop(img.name),
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(ctx.l10n.cancel),
          ),
        ],
      ),
    );

    if (selectedImage == null) return;

    final template = '![$selectedImage]($selectedImage)';
    currentTab.codeController.replaceSelection(template);
    _focusNode.requestFocus();
  }

  void _selectAll() {
    final tab = _activeTab;
    if (tab.codeController.codeLines.isEmpty) return;
    final lastLineIndex = tab.codeController.codeLines.length - 1;
    final lastLineLength =
        tab.codeController.codeLines[lastLineIndex].text.length;
    tab.codeController.selection = CodeLineSelection(
      baseIndex: 0,
      baseOffset: 0,
      extentIndex: lastLineIndex,
      extentOffset: lastLineLength,
    );
  }

  void _goToLineIndex(int lineIndex, [int columnIndex = 0]) {
    final target = lineIndex.clamp(0, _activeTab.codeController.lineCount - 1);
    final lineLength = _activeTab.codeController.codeLines[target].text.length;
    final targetCol = columnIndex.clamp(0, lineLength);
    _activeTab.codeController.selection = CodeLineSelection.collapsed(
      index: target,
      offset: targetCol,
    );
    _activeTab.codeController.makeCursorCenterIfInvisible();
  }

  void _goToStart() {
    _goToLineIndex(0);
    _focusNode.requestFocus();
  }

  void _goToEnd() {
    _goToLineIndex(_activeTab.codeController.lineCount - 1);
    _focusNode.requestFocus();
  }

  Future<void> _showGoToLineDialog() async {
    final result = await showDialog<(int, int?)>(
      context: context,
      builder: (dialogContext) =>
          _GoToLineDialog(maxLine: _activeTab.codeController.lineCount),
    );

    if (result != null) {
      final (line, col) = result;
      _goToLineIndex(line - 1, col != null ? col - 1 : 0);
      _focusNode.requestFocus();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _activeTab.codeController.makeCursorCenterIfInvisible();
        }
      });
    }
  }

  Future<void> _revertActiveTab() async {
    final tab = _activeTab;
    if (!tab.isDirty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.l10n.textEditorRevertDialogTitle),
        content: Text(ctx.l10n.textEditorRevertDialogMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(ctx.l10n.cancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
              foregroundColor: Theme.of(ctx).colorScheme.onError,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(ctx.l10n.revertButton),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await _loadFileForTab(tab);
    }
  }

  static const _jsonExtensions = {
    'json',
    'password',
    'paymentcard',
    'identity',
    'securenote',
    'bankaccount',
    'softwarelicense',
    'authenticator',
  };

  String? Function(String)? get _formatter => formatterFor(_activeTab.filePath);

  bool get _isJsonFile {
    final dot = _activeTab.filePath.lastIndexOf('.');
    if (dot < 0) return false;
    return _jsonExtensions.contains(
      _activeTab.filePath.substring(dot + 1).toLowerCase(),
    );
  }

  void _runFormatter(String? Function(String) formatter) {
    final input = _activeTab.codeController.text;
    String? result;
    try {
      result = formatter(input);
    } catch (_) {
      result = null;
    }
    if (result == null) {
      showAppSnackBar(
        context,
        message: context.l10n.textEditorFormatFailedMessage,
        tone: AppBannerTone.error,
      );
      return;
    }
    if (result == input) return;
    _activeTab.codeController.text = result;
  }

  @override
  Widget build(BuildContext context) {
    if (_tabs.isEmpty) {
      return const Scaffold(body: SizedBox.shrink());
    }

    final appTheme = Theme.of(context);
    final activeTab = _activeTab;
    final appearance = ref.watch(textEditorAppearanceProvider);

    // The editor's own background/syntax theme drives the colors of the whole
    // screen (app bar, tabs, status bar, accessory bar, find panel, drawer,
    // menus, system navigation bar), not just the text area. `cs` from here
    // on is the editor-derived scheme; `appTheme` is only used to resolve the
    // editor style itself, whose "auto" syntax theme follows the app.
    final syntaxStyle = resolveEditorSyntaxStyle(
      activeTab.filePath,
      appTheme.brightness,
      appTheme.colorScheme,
      background: appearance.background,
      syntaxTheme: appearance.syntaxTheme,
    );
    final chrome = _resolveChrome(syntaxStyle, appTheme.colorScheme);
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
              const SingleActivator(LogicalKeyboardKey.keyT, control: true):
                  _createNewFileTab,
              const SingleActivator(LogicalKeyboardKey.keyT, meta: true):
                  _createNewFileTab,
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
              drawer: _buildProjectDrawer(cs),
              appBar: AppBar(
                systemOverlayStyle: chrome.overlayStyle,
                leading: IconButton(
                  icon: const Icon(Icons.menu_rounded),
                  tooltip: context.l10n.textEditorProjectFilesTitle,
                  onPressed: () => _scaffoldKey.currentState?.openDrawer(),
                ),
                title: Text(activeTab.fileName),
                actions: [
                  if (!activeTab.isLoading && activeTab.hasError)
                    PopupMenuButton<String>(
                      tooltip: context.l10n.textEditorMoreActionsTooltip,
                      icon: const Icon(Icons.more_vert_rounded),
                      onSelected: (value) {
                        if (value == 'encoding') _showEncodingPicker(activeTab);
                      },
                      itemBuilder: (context) => [
                        PopupMenuItem(
                          value: 'encoding',
                          child: Row(
                            children: [
                              const Icon(Icons.translate_rounded, size: 20),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  context.l10n.textEditorEncodingTooltip,
                                ),
                              ),
                              Text(activeTab.encoding.label),
                            ],
                          ),
                        ),
                      ],
                    ),
                  if (!activeTab.isLoading && !activeTab.hasError) ...[
                    if (activeTab.isMarkdownFile) ...[
                      if (!activeTab.showMarkdownPreview && !_readOnly)
                        IconButton(
                          icon: const Icon(Icons.add_photo_alternate_outlined),
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
                            : context.l10n.markdownViewerPreviewTooltip,
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
                      tooltip: context.l10n.textEditorMoreActionsTooltip,
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
                            if (formatter != null) _runFormatter(formatter);
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
                                    : cs.onSurface.withValues(alpha: 0.38),
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
                              const Icon(Icons.save_as_rounded, size: 20),
                              const SizedBox(width: 12),
                              Text(context.l10n.textEditorSaveAsMenuItem),
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
                                    : cs.onSurface.withValues(alpha: 0.38),
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
                              const Icon(Icons.translate_rounded, size: 20),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  context.l10n.textEditorEncodingTooltip,
                                ),
                              ),
                            ],
                          ),
                        ),
                        PopupMenuItem(
                          value: 'wordWrap',
                          child: Row(
                            children: [
                              const Icon(Icons.wrap_text_rounded, size: 20),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(context.l10n.textEditorWordWrap),
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
                                child: Text(context.l10n.textEditorReadOnly),
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
                              const Icon(Icons.select_all_rounded, size: 20),
                              const SizedBox(width: 12),
                              Text(context.l10n.textEditorSelectAllMenuItem),
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
                              Text(context.l10n.textEditorGoToLineMenuItem),
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
                              Text(context.l10n.textEditorGoToStartMenuItem),
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
                              Text(context.l10n.textEditorGoToEndMenuItem),
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
                                  context.l10n.textEditorFormatDocumentMenuItem,
                                ),
                              ],
                            ),
                          ),
                          if (_isJsonFile)
                            PopupMenuItem(
                              value: 'minify',
                              child: Row(
                                children: [
                                  const Icon(Icons.compress_rounded, size: 20),
                                  const SizedBox(width: 12),
                                  Text(
                                    context.l10n.textEditorMinifyJsonMenuItem,
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
                              const Icon(Icons.palette_outlined, size: 20),
                              const SizedBox(width: 12),
                              Text(context.l10n.textEditorThemeMenuItem),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
                bottom: (appearance.showTabBar ||
                        _tabBarAnimationController.value > 0)
                    ? PreferredSize(
                        preferredSize: Size.fromHeight(
                          42 * _tabBarAnimationController.value,
                        ),
                        child: ClipRect(
                          child: Align(
                            alignment: Alignment.bottomCenter,
                            heightFactor: _tabBarAnimationController.value,
                            child: _buildTabBar(cs),
                          ),
                        ),
                      )
                    : null,
              ),
              // Keeps the last lines clear of the gesture pill / display cutouts.
              // The Scaffold already strips the bottom inset from the body's
              // MediaQuery whenever the status bar is present (that bar handles its
              // own), so this never double-pads.
              body: SafeArea(
                top: false,
                child: NotificationListener<ScrollNotification>(
                  onNotification: _handleTabBarScroll,
                  child: _buildBody(cs, chrome.theme.textTheme, syntaxStyle),
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

  Widget _buildTabBar(ColorScheme cs) {
    while (_tabKeys.length < _tabs.length) {
      _tabKeys.add(GlobalKey());
    }
    if (_tabKeys.length > _tabs.length) {
      _tabKeys.removeRange(_tabs.length, _tabKeys.length);
    }

    return Container(
      height: 40,
      decoration: BoxDecoration(
        color: cs.surfaceContainer,
        border: Border(
          bottom: BorderSide(color: cs.outlineVariant, width: 0.5),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _tabScrollController,
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              itemCount: _tabs.length,
              itemBuilder: (context, index) {
                final tab = _tabs[index];
                final isActive = index == _activeTabIndex;

                return Material(
                  key: _tabKeys[index],
                  color: isActive
                      ? cs.surfaceContainerHighest
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () {
                      setState(() => _activeTabIndex = index);
                      _scrollToActiveTab();
                    },
                    onLongPress: () => _showTabContextMenu(index),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
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
                              color: isActive
                                  ? cs.onSurface
                                  : cs.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(width: 6),
                          InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: () => _closeTab(index),
                            child: Padding(
                              padding: const EdgeInsets.all(2.0),
                              child: Icon(
                                Icons.close_rounded,
                                size: 14,
                                color: isActive
                                    ? cs.onSurfaceVariant
                                    : cs.outline,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          IconButton(
            icon: const Icon(Icons.add_rounded, size: 20),
            visualDensity: VisualDensity.compact,
            tooltip: context.l10n.textEditorNewFileTooltip,
            onPressed: _createNewFileTab,
          ),
          const SizedBox(width: 4),
        ],
      ),
    );
  }

  List<PathSegment> get _drawerPathStack {
    final rootLabel = context.l10n.rootFolderLabel;
    final stack = <PathSegment>[PathSegment(rootLabel, '')];
    if (_projectDirPath.isEmpty) return stack;

    final segments = _projectDirPath.split('/');
    String accumulated = '';
    for (final seg in segments) {
      if (seg.isEmpty) continue;
      accumulated = accumulated.isEmpty ? seg : '$accumulated/$seg';
      stack.add(PathSegment(seg, accumulated));
    }
    return stack;
  }

  static const _imageExtensions = {
    'png',
    'jpg',
    'jpeg',
    'gif',
    'webp',
    'bmp',
    'svg',
  };

  bool _isImageFile(String fileName) {
    final dot = fileName.lastIndexOf('.');
    if (dot < 0) return false;
    return _imageExtensions.contains(fileName.substring(dot + 1).toLowerCase());
  }

  void _showImagePreviewDialog(String fullPath, String fileName) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(fileName),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 400),
          child: SingleChildScrollView(
            child: MarkdownImage(
              container: widget.container,
              resolvedPath: fullPath,
              alt: fileName,
            ),
          ),
        ),
        actions: [
          if (_activeTab.isMarkdownFile && !_readOnly)
            TextButton.icon(
              icon: const Icon(Icons.add_link_rounded),
              label: Text(ctx.l10n.addFile),
              onPressed: () {
                Navigator.of(ctx).pop();
                final template = '![$fileName]($fileName)';
                _activeTab.codeController.replaceSelection(template);
                _focusNode.requestFocus();
              },
            ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(ctx.l10n.close),
          ),
        ],
      ),
    );
  }

  static const _unsupportedBinaryExtensions = {
    'pdf',
    'mp4',
    'mov',
    'avi',
    'mkv',
    'webm',
    'm4v',
    'mpeg',
    'mpg',
    'mp3',
    'flac',
    'wav',
    'm4a',
    'zip',
    'gz',
    'tar',
    '7z',
    'rar',
    'bz2',
    'xz',
    'apk',
    'vxenc',
    'aes',
  };

  bool _isUnsupportedBinaryFile(String fileName) {
    final dot = fileName.lastIndexOf('.');
    if (dot < 0) return false;
    return _unsupportedBinaryExtensions.contains(
      fileName.substring(dot + 1).toLowerCase(),
    );
  }

  Widget _buildProjectDrawer(ColorScheme cs) {
    final settingsUri = widget.container.volId < 0
        ? null
        : widget.container.uri;
    final skin = ref
        .watch(fileManagerToolbarSettingsProvider(settingsUri))
        .config
        .skin;
    return Drawer(
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
              decoration: BoxDecoration(color: cs.surfaceContainerHigh),
              child: Row(
                children: [
                  Icon(Icons.inventory_2_outlined, size: 20, color: cs.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.container.displayName,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.note_add_outlined, size: 20),
                    tooltip: context.l10n.textEditorNewFileTooltip,
                    onPressed: _createNewFileTab,
                  ),
                  IconButton(
                    icon: const Icon(
                      Icons.create_new_folder_outlined,
                      size: 20,
                    ),
                    tooltip: context.l10n.textEditorNewFolderTooltip,
                    onPressed: _createDrawerFolder,
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 20),
                    tooltip: context.l10n.close,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            Container(
              decoration: BoxDecoration(color: cs.surfaceContainer),
              child: BreadcrumbBar(
                stack: _drawerPathStack,
                backgroundColor: Colors.transparent,
                onTap: (index) {
                  final target = _drawerPathStack[index];
                  setState(() => _projectDirPath = target.fatPath);
                },
              ),
            ),
            Expanded(
              child: FutureBuilder<List<String>?>(
                future: ref
                    .read(vaultFileIoApiProvider)
                    .listDirectory(widget.container, _projectDirPath),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  final rawEntries = snapshot.data ?? [];
                  final entries = RawEntry.parseAll(rawEntries)
                    ..sort((a, b) {
                      if (a.isDir != b.isDir) return a.isDir ? -1 : 1;
                      return a.name.compareTo(b.name);
                    });

                  if (entries.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.folder_open_rounded,
                            size: 40,
                            color: cs.onSurfaceVariant.withValues(alpha: 0.5),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            context.l10n.filesEmptyMessage,
                            style: TextStyle(color: cs.onSurfaceVariant),
                          ),
                        ],
                      ),
                    );
                  }

                  return ListView.builder(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 6,
                    ),
                    itemCount: entries.length,
                    itemBuilder: (context, index) {
                      final entry = entries[index];
                      final fullPath = _projectDirPath.isEmpty
                          ? entry.name
                          : '$_projectDirPath/${entry.name}';
                      final isOpen = _tabs.any((t) => t.filePath == fullPath);
                      final isCurrentActive = fullPath == _activeTab.filePath;
                      final isUnsupported = _isUnsupportedBinaryFile(
                        entry.name,
                      );
                      final (iconData, iconColor) = entry.isDir
                          ? (skin.folderIcon, skin.folderIconColor(cs))
                          : (
                              skin.fileIcon(entry.name),
                              skin.fileIconColor(cs, entry.name),
                            );
                      final itemStyle = skin.styleFor(isDir: entry.isDir);

                      return Padding(
                        padding: const EdgeInsets.only(bottom: 2),
                        child: Material(
                          color: isCurrentActive
                              ? cs.secondaryContainer.withValues(alpha: 0.6)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(8),
                          child: ListTile(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 0,
                            ),
                            visualDensity: VisualDensity.compact,
                            dense: true,
                            onLongPress: () =>
                                _showDrawerItemContextMenu(entry, fullPath),
                            leading: Container(
                              width: 32,
                              height: 32,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: isCurrentActive
                                    ? cs.primaryContainer
                                    : switch (itemStyle.container) {
                                        SkinContainerStyle.filled =>
                                          entry.isDir
                                              ? cs.secondaryContainer
                                                    .withValues(alpha: 0.4)
                                              : cs.surfaceContainerHighest,
                                        SkinContainerStyle.outlined ||
                                        SkinContainerStyle.none =>
                                          Colors.transparent,
                                      },
                                borderRadius: BorderRadius.circular(10),
                                border:
                                    itemStyle.container ==
                                        SkinContainerStyle.outlined
                                    ? Border.all(
                                        color: isCurrentActive
                                            ? cs.primary
                                            : cs.outlineVariant,
                                        width: 1.2,
                                      )
                                    : null,
                              ),
                              child: Icon(
                                iconData,
                                color: isCurrentActive
                                    ? cs.primary
                                    : (isUnsupported
                                          ? iconColor.withValues(alpha: 0.38)
                                          : iconColor),
                                size: 20,
                              ),
                            ),
                            title: Text(
                              entry.name,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: (isCurrentActive || isOpen)
                                    ? FontWeight.w600
                                    : FontWeight.normal,
                                color: isCurrentActive
                                    ? cs.onSecondaryContainer
                                    : (isUnsupported
                                          ? (itemStyle.nameColor ??
                                                    cs.onSurface)
                                                .withValues(alpha: 0.45)
                                          : itemStyle.nameColor ??
                                                cs.onSurface),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: entry.isDir
                                ? Icon(
                                    Icons.chevron_right_rounded,
                                    size: 18,
                                    color: cs.onSurfaceVariant,
                                  )
                                : (isCurrentActive
                                      ? Icon(
                                          Icons.edit_note_rounded,
                                          size: 18,
                                          color: cs.primary,
                                        )
                                      : (isOpen
                                            ? Container(
                                                width: 6,
                                                height: 6,
                                                decoration: BoxDecoration(
                                                  color: cs.primary,
                                                  shape: BoxShape.circle,
                                                ),
                                              )
                                            : null)),
                            onTap: () {
                              if (entry.isDir) {
                                setState(() => _projectDirPath = fullPath);
                              } else if (_isImageFile(entry.name)) {
                                Navigator.of(context).pop();
                                _showImagePreviewDialog(fullPath, entry.name);
                              } else if (isUnsupported) {
                                Navigator.of(context).pop();
                                showAppSnackBar(
                                  context,
                                  message: context
                                      .l10n
                                      .textEditorInvalidTextFileMessage,
                                  tone: AppBannerTone.error,
                                );
                              } else {
                                Navigator.of(context).pop();
                                _openFileInTab(fullPath);
                              }
                            },
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(
    ColorScheme cs,
    TextTheme textTheme,
    EditorSyntaxStyle syntaxStyle,
  ) {
    final activeTab = _activeTab;

    if (activeTab.isLoading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(strokeWidth: 2.5),
            const SizedBox(height: 16),
            Text(context.l10n.decryptingFileContent),
          ],
        ),
      );
    }
    if (activeTab.hasError) {
      return Center(
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
      );
    }

    if (activeTab.isMarkdownFile && activeTab.showMarkdownPreview) {
      return FastScrollbar(
        controller: activeTab.previewScrollController,
        child: SelectionArea(
          child: MarkdownBodyView(
            key: activeTab.previewKey,
            source: activeTab.codeController.text,
            container: widget.container,
            currentFilePath: activeTab.filePath,
            onLinkTap: _handleLinkTap,
            scrollController: activeTab.previewScrollController,
            onTaskToggled: _toggleMarkdownTask,
          ),
        ),
      );
    }

    final appearance = ref.watch(textEditorAppearanceProvider);
    final softKeyboardVisible = MediaQuery.of(context).viewInsets.bottom > 0;

    // Calculate a high-contrast accent color for the cursor, selection, and teardrop handles
    final bgLuminance = syntaxStyle.backgroundColor.computeLuminance();
    final primaryLuminance = cs.primary.computeLuminance();
    final contrast = (primaryLuminance - bgLuminance).abs();
    final safeAccentColor = contrast > 0.25
        ? cs.primary
        : (bgLuminance < 0.5 ? Colors.white : Colors.black);

    return Column(
      children: [
        Expanded(
          child: Listener(
            behavior: HitTestBehavior.translucent,
            onPointerDown: (event) {
              _pinchPointers[event.pointer] = event.position;
              if (_pinchPointers.length == 2) {
                final pts = _pinchPointers.values.toList();
                _initialPinchDistance = (pts[0] - pts[1]).distance;
                _pinchStartFontSize = appearance.fontSize;
              }
            },
            onPointerMove: (event) {
              if (_pinchPointers.containsKey(event.pointer)) {
                _pinchPointers[event.pointer] = event.position;
              }
              if (_pinchPointers.length == 2 &&
                  _initialPinchDistance != null &&
                  _initialPinchDistance! > 10) {
                final pts = _pinchPointers.values.toList();
                final currentDist = (pts[0] - pts[1]).distance;
                final scale = currentDist / _initialPinchDistance!;
                final newSize = (_pinchStartFontSize * scale).clamp(10.0, 24.0);
                final rounded = (newSize * 2).round() / 2.0;
                if ((rounded - appearance.fontSize).abs() >= 0.5) {
                  ref
                      .read(textEditorAppearanceProvider.notifier)
                      .setFontSize(rounded);
                }
              }
            },
            onPointerUp: (event) {
              _pinchPointers.remove(event.pointer);
              if (_pinchPointers.length < 2) {
                _initialPinchDistance = null;
              }
            },
            onPointerCancel: (event) {
              _pinchPointers.remove(event.pointer);
              if (_pinchPointers.length < 2) {
                _initialPinchDistance = null;
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

                    if (key == LogicalKeyboardKey.arrowLeft) {
                      if (isControl) {
                        moveLeft();
                        while (extLine >= 0) {
                          final text = lines[extLine].text;
                          while (extOffset > 0 &&
                              RegExp(r'\s').hasMatch(text[extOffset - 1]))
                            extOffset--;
                          if (extOffset > 0) {
                            bool isWord = RegExp(
                              r'\w',
                            ).hasMatch(text[extOffset - 1]);
                            while (extOffset > 0 &&
                                (RegExp(r'\w').hasMatch(text[extOffset - 1]) ==
                                    isWord) &&
                                !RegExp(r'\s').hasMatch(text[extOffset - 1])) {
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
                              RegExp(r'\s').hasMatch(text[extOffset]))
                            extOffset++;
                          if (extOffset < text.length) {
                            bool isWord = RegExp(
                              r'\w',
                            ).hasMatch(text[extOffset]);
                            while (extOffset < text.length &&
                                (RegExp(r'\w').hasMatch(text[extOffset]) ==
                                    isWord) &&
                                !RegExp(r'\s').hasMatch(text[extOffset])) {
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
                child: FastScrollbar(
                  controller: activeTab.horizontalScrollController,
                  axis: Axis.horizontal,
                  child: TextSelectionTheme(
                    data: TextSelectionThemeData(
                      selectionColor: safeAccentColor.withValues(alpha: 0.28),
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
                      autofocus: false,
                      findController: activeTab.findController,
                      findBuilder: (context, controller, readOnly) =>
                          EditorFindPanel(
                            controller: controller,
                            readOnly: readOnly,
                          ),
                      chunkAnalyzer: const DefaultCodeChunkAnalyzer(),
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
                        selectionColor: safeAccentColor.withValues(alpha: 0.28),
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
                                    controller: editingController,
                                    notifier: notifier,
                                    textStyle: TextStyle(
                                      color: syntaxStyle.textColor.withValues(
                                        alpha: 0.45,
                                      ),
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
                                  DefaultCodeChunkIndicator(
                                    width: 14,
                                    controller: chunkController,
                                    notifier: notifier,
                                    painter: DefaultCodeChunkIndicatorPainter(
                                      color: syntaxStyle.textColor.withValues(
                                        alpha: 0.45,
                                      ),
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
    final appearance = ref.watch(textEditorAppearanceProvider);
    final timeStr = activeTab.lastSavedAt != null
        ? '${activeTab.lastSavedAt!.hour.toString().padLeft(2, '0')}:${activeTab.lastSavedAt!.minute.toString().padLeft(2, '0')}'
        : null;

    final posStr = !activeTab.showMarkdownPreview
        ? '${context.l10n.textEditorCursorPosition(activeTab.cursorLine, activeTab.cursorCol)}  •  '
        : '';

    // The fill is the outer DecoratedBox so it runs edge-to-edge behind the
    // system gesture area; the SafeArea inside pushes the text up above the
    // gesture pill (and in from display cutouts in landscape) instead of
    // letting it sit underneath it.
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
                  '${activeTab.encoding.label}  |  $posStr${context.l10n.linesCount(activeTab.lineCount)}  |  ${context.l10n.charsCount(activeTab.charCount)}',
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

class _GoToLineDialog extends StatefulWidget {
  final int maxLine;

  const _GoToLineDialog({required this.maxLine});

  @override
  State<_GoToLineDialog> createState() => _GoToLineDialogState();
}

class _GoToLineDialogState extends State<_GoToLineDialog> {
  late final TextEditingController _controller = TextEditingController();
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  (int, int?)? _parseLineAndColumn(String raw) {
    final text = raw.trim();
    if (text.isEmpty) return null;

    final direct = RegExp(r'^(\d+)(?::(\d+))?$').firstMatch(text);
    if (direct != null) {
      final line = int.tryParse(direct.group(1)!);
      if (line == null || line < 1 || line > widget.maxLine) return null;
      final col = int.tryParse(direct.group(2) ?? '');
      return (line, (col != null && col > 0) ? col : null);
    }

    final extracted = RegExp(r'(?::|\b)(\d+):(\d+)\b').firstMatch(text);
    if (extracted != null) {
      final line = int.tryParse(extracted.group(1)!);
      if (line == null || line < 1 || line > widget.maxLine) return null;
      final col = int.tryParse(extracted.group(2)!);
      return (line, (col != null && col > 0) ? col : null);
    }

    return null;
  }

  void _submit() {
    if (_formKey.currentState?.validate() ?? false) {
      final parsed = _parseLineAndColumn(_controller.text);
      if (parsed != null) {
        Navigator.of(context).pop(parsed);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(context.l10n.textEditorGoToLineDialogTitle),
      content: Form(
        key: _formKey,
        child: TextFormField(
          controller: _controller,
          autofocus: true,
          keyboardType: TextInputType.text,
          autocorrect: false,
          enableSuggestions: false,
          decoration: InputDecoration(
            labelText: context.l10n.textEditorGoToLineFieldLabel,
            hintText: '42 or 42:15',
            helperText: context.l10n.textEditorGoToLineHelperText(
              widget.maxLine,
            ),
          ),
          validator: (value) {
            final parsed = _parseLineAndColumn(value ?? '');
            if (parsed == null) {
              return context.l10n.textEditorGoToLineInvalidNumber(
                widget.maxLine,
              );
            }
            return null;
          },
          onFieldSubmitted: (_) => _submit(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.l10n.cancel),
        ),
        FilledButton(
          onPressed: _submit,
          child: Text(context.l10n.goToLineButton),
        ),
      ],
    );
  }
}

class _MoveToFolderDialog extends ConsumerStatefulWidget {
  final MountedContainer container;
  final String currentEntryPath;
  final bool isDir;

  const _MoveToFolderDialog({
    required this.container,
    required this.currentEntryPath,
    required this.isDir,
  });

  @override
  ConsumerState<_MoveToFolderDialog> createState() =>
      _MoveToFolderDialogState();
}

class _MoveToFolderDialogState extends ConsumerState<_MoveToFolderDialog> {
  String _currentDir = '';

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return AlertDialog(
      title: Text(context.l10n.textEditorMoveToDialogTitle),
      content: SizedBox(
        width: double.maxFinite,
        height: 350,
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                children: [
                  if (_currentDir.isNotEmpty)
                    IconButton(
                      icon: const Icon(Icons.arrow_upward_rounded, size: 18),
                      visualDensity: VisualDensity.compact,
                      onPressed: () {
                        final lastSlash = _currentDir.lastIndexOf('/');
                        setState(() {
                          _currentDir = lastSlash >= 0
                              ? _currentDir.substring(0, lastSlash)
                              : '';
                        });
                      },
                    ),
                  Expanded(
                    child: Text(
                      _currentDir.isEmpty
                          ? context.l10n.rootFolderLabel
                          : _currentDir,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: FutureBuilder<List<String>?>(
                future: ref
                    .read(vaultFileIoApiProvider)
                    .listDirectory(widget.container, _currentDir),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  final folders =
                      RawEntry.parseAll(
                          snapshot.data ?? const [],
                        ).where((e) => e.isDir).toList()
                        ..sort((a, b) => a.name.compareTo(b.name));

                  if (folders.isEmpty) {
                    return Center(
                      child: Text(
                        context.l10n.filesEmptyMessage,
                        style: TextStyle(
                          color: cs.onSurfaceVariant,
                          fontSize: 13,
                        ),
                      ),
                    );
                  }

                  return ListView.builder(
                    itemCount: folders.length,
                    itemBuilder: (context, index) {
                      final folder = folders[index];
                      final folderFullPath = _currentDir.isEmpty
                          ? folder.name
                          : '$_currentDir/${folder.name}';

                      // Disallow moving a directory into itself or a subfolder of itself
                      final isInvalidTarget =
                          widget.isDir &&
                          (folderFullPath == widget.currentEntryPath ||
                              folderFullPath.startsWith(
                                '${widget.currentEntryPath}/',
                              ));

                      return ListTile(
                        leading: Icon(
                          Icons.folder_rounded,
                          color: isInvalidTarget ? cs.outline : cs.primary,
                          size: 20,
                        ),
                        title: Text(
                          folder.name,
                          style: TextStyle(
                            fontSize: 13,
                            color: isInvalidTarget
                                ? cs.onSurface.withValues(alpha: 0.38)
                                : null,
                          ),
                        ),
                        trailing: const Icon(
                          Icons.chevron_right_rounded,
                          size: 18,
                        ),
                        enabled: !isInvalidTarget,
                        onTap: () {
                          setState(() => _currentDir = folderFullPath);
                        },
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.l10n.cancel),
        ),
        FilledButton.icon(
          icon: const Icon(Icons.check_rounded, size: 18),
          label: Text(context.l10n.textEditorMoveHereButton),
          onPressed: () => Navigator.of(context).pop(_currentDir),
        ),
      ],
    );
  }
}