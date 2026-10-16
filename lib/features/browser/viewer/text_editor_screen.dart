import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/scheduler.dart' show SchedulerBinding, SchedulerPhase;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:re_editor/re_editor.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/filesystem/filesystem_type.dart';
import 'package:vaultexplorer/core/filesystem/mounted_container_filesystem.dart';
import 'package:vaultexplorer/core/providers/vault_engine_providers.dart';
import 'package:vaultexplorer/core/theme/file_manager_skin_scope.dart';
import 'package:vaultexplorer/core/theme/app_skin_tokens.dart';
import 'package:vaultexplorer/core/utils/format_utils.dart';
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
import 'package:vaultexplorer/features/browser/viewer/text_editor_theme.dart';
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

double _contrastRatio(Color first, Color second) {
  final firstLuminance = first.computeLuminance();
  final secondLuminance = second.computeLuminance();
  final lighter = firstLuminance >= secondLuminance
      ? firstLuminance
      : secondLuminance;
  final darker = firstLuminance >= secondLuminance
      ? secondLuminance
      : firstLuminance;
  return (lighter + 0.05) / (darker + 0.05);
}

enum _TabMenuAction { close, closeOthers, closeAll, rename }

class _ParsedEditorText {
  final CodeLines codeLines;
  final int charCount;

  const _ParsedEditorText(this.codeLines, this.charCount);
}

/// Splits the document without creating the temporary `List<String>` that
/// String.split would allocate for files containing many lines.
_ParsedEditorText _codeLinesFromText(String text) {
  final lines = <CodeLine>[];
  var lineStart = 0;
  var index = 0;
  var charCount = 0;

  while (index < text.length) {
    final codeUnit = text.codeUnitAt(index);
    if (codeUnit == 0x0A || codeUnit == 0x0D) {
      final lineText = text.substring(lineStart, index);
      lines.add(CodeLine(lineText));
      charCount += lineText.length + 1;
      if (codeUnit == 0x0D &&
          index + 1 < text.length &&
          text.codeUnitAt(index + 1) == 0x0A) {
        index++;
      }
      lineStart = index + 1;
    }
    index++;
  }

  final lastLine = text.substring(lineStart);
  lines.add(CodeLine(lastLine));
  charCount += lastLine.length;
  return _ParsedEditorText(CodeLines.of(lines), charCount);
}

/// UTF-8 line breaks are single-byte ASCII values, so large UTF-8 documents
/// can be decoded one line at a time without first allocating a full copy of
/// the document as a Dart String.
_ParsedEditorText _codeLinesFromUtf8Bytes(
  Uint8List bytes, {
  required int startOffset,
}) {
  final lines = <CodeLine>[];
  var lineStart = startOffset;
  var index = startOffset;
  var charCount = 0;

  void addLine(int end, {required bool hasLineBreak}) {
    final lineText = utf8.decode(
      Uint8List.sublistView(bytes, lineStart, end),
      allowMalformed: true,
    );
    lines.add(CodeLine(lineText));
    charCount += lineText.length + (hasLineBreak ? 1 : 0);
  }

  while (index < bytes.length) {
    final byte = bytes[index];
    if (byte == 0x0A || byte == 0x0D) {
      addLine(index, hasLineBreak: true);
      if (byte == 0x0D &&
          index + 1 < bytes.length &&
          bytes[index + 1] == 0x0A) {
        index++;
      }
      lineStart = index + 1;
    }
    index++;
  }

  addLine(bytes.length, hasLineBreak: false);
  return _ParsedEditorText(CodeLines.of(lines), charCount);
}

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
  Object? lastCodeLines;
  bool isApplyingProgrammaticText = false;
  bool showMarkdownPreview;
  EditorTextEncoding encoding = EditorTextEncoding.utf8;
  bool encodingWasChosen = false;
  Timer? autosaveTimer;
  VoidCallback? textListener;

  /// Context of this tab's widget in the tab bar, kept so the bar can scroll
  /// it into view and anchor the tab menu to it.
  BuildContext? tabContext;

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

  bool get isLargeFile => lineCount > 4000 || charCount > 300 * 1024;

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
  late final AnimationController _tabBarAnimationController;
  late final AnimationController _appBarAnimationController;

  // Pinch-to-zoom state
  final Map<int, Offset> _pinchPointers = {};
  double? _initialPinchDistance;
  double _pinchStartFontSize = 14.0;
  bool _pinchFontSizeChanged = false;
  DateTime? _lastPinchFontSizeUpdate;

  /// Height of the tab strip returned by [_buildTabBar].
  static const double _kTabStripHeight = 40.0;

  /// True while the fast-scroll handle is held. Its `jumpTo` calls must not
  /// drive the tab strip (see [_handleTabBarScroll]).
  bool _scrollbarDragging = false;

  bool _readOnly = false;
  bool _wordWrap = true;
  final EditorFocusNode _focusNode = EditorFocusNode();
  late final SelectionToolbarController _toolbarController;

  late String _projectDirPath;

  EditorChrome? _chrome;

  EditorChrome _resolveChrome(
    EditorSyntaxStyle style,
    ColorScheme appScheme,
    AppSkinTokens? appSkinTokens,
  ) {
    final cached = _chrome;
    if (cached != null &&
        cached.matches(
          style.backgroundColor,
          style.textColor,
          appScheme,
          appSkinTokens: appSkinTokens,
        )) {
      return cached;
    }
    return _chrome = EditorChrome.resolve(
      background: style.backgroundColor,
      foreground: style.textColor,
      appScheme: appScheme,
      appSkinTokens: appSkinTokens,
    );
  }

  EditorTab get _activeTab => _tabs[_activeTabIndex];

  TextEditorAppearancePrefs _effectiveAppearance(
    TextEditorAppearancePrefs prefs,
  ) {
    final tokens = Theme.of(context).extension<AppSkinTokens>();
    if (tokens == null || !tokens.editorFollowsAppSkin) return prefs;
    return prefs.copyWith(
      background: EditorBackgroundOption.values.firstWhere(
        (option) => option.name == tokens.editorBackgroundOption,
        orElse: () => EditorBackgroundOption.matchSyntaxTheme,
      ),
      syntaxTheme: EditorSyntaxThemeOption.values.firstWhere(
        (option) => option.name == tokens.editorSyntaxThemeOption,
        orElse: () => EditorSyntaxThemeOption.auto,
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    final initialShowTabBar =
        ref.read(textEditorAppearanceProvider).showTabBar;
    _tabBarAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 180),
      value: initialShowTabBar ? 1.0 : 0.0,
    )..addListener(_onTabBarAnimationTick);
    _appBarAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
      value: 1,
    )..addListener(_onAppBarAnimationTick);
    _focusNode.addListener(_onEditorFocusChanged);
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

            final appearance = _effectiveAppearance(
              ref.read(textEditorAppearanceProvider),
            );
            final tokens = appTheme.extension<AppSkinTokens>();
            final customColors = tokens?.editorFollowsAppSkin == true
                ? null
                : appearance.customColors.map((k, v) => MapEntry(k, Color(v)));
            final editorStyle = applyAppSkinEditorTokens(
              resolveEditorSyntaxStyle(
                _activeTab.filePath,
                appTheme.brightness,
                cs,
                background: appearance.background,
                syntaxTheme: appearance.syntaxTheme,
                customColors: customColors,
              ),
              tokens,
            );
            final editorBg = editorStyle.backgroundColor;

            Color surfaceColor = cs.surfaceContainerHigh;

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

  void _finishPinchFontSizeGesture() {
    _initialPinchDistance = null;
    _lastPinchFontSizeUpdate = null;
    if (!_pinchFontSizeChanged) return;

    _pinchFontSizeChanged = false;
    final fontSize = ref.read(textEditorAppearanceProvider).fontSize;
    ref.read(textEditorAppearanceProvider.notifier).setFontSize(fontSize);
  }

  void _applyPinchFontSize({bool force = false}) {
    if (_pinchPointers.length != 2 ||
        _initialPinchDistance == null ||
        _initialPinchDistance! <= 10) {
      return;
    }

    final points = _pinchPointers.values.toList();
    final scale = (points[0] - points[1]).distance / _initialPinchDistance!;
    final newSize = (_pinchStartFontSize * scale).clamp(10.0, 24.0);
    final rounded = (newSize * 2).round() / 2.0;
    final currentFontSize = ref.read(textEditorAppearanceProvider).fontSize;
    if (rounded == currentFontSize ||
        (!force && (rounded - currentFontSize).abs() < 1.0)) {
      return;
    }

    _pinchFontSizeChanged = true;
    _lastPinchFontSizeUpdate = DateTime.now();
    ref
        .read(textEditorAppearanceProvider.notifier)
        .setFontSize(rounded, persist: false);
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
      var bytes = await ref
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
      late final _ParsedEditorText parsedDocument;
      try {
        if (tab.encoding.isUtf8) {
          parsedDocument = _codeLinesFromUtf8Bytes(
            bytes,
            startOffset: tab.encoding.utf8PayloadOffset(bytes),
          );
        } else {
          final text = await tab.encoding.decode(bytes);
          bytes = Uint8List(0);
          parsedDocument = _codeLinesFromText(text);
        }
      } on FormatException {
        throw FormatException(l10n.textEditorInvalidTextFileMessage);
      }
      bytes = Uint8List(0);

      if (!mounted) return;
      tab.appliedInitialText = true;
      tab.isApplyingProgrammaticText = true;
      try {
        tab.codeController.value = CodeLineEditingValue(
          codeLines: parsedDocument.codeLines,
        );
      } finally {
        tab.isApplyingProgrammaticText = false;
      }
      tab.lastCodeLines = tab.codeController.value.codeLines;
      tab.codeController.clearHistory();
      tab.lineCount = tab.codeController.lineCount;
      tab.charCount = parsedDocument.charCount;
      if (tab.isLargeFile) {
        _wordWrap = false;
        tab.showMarkdownPreview = false;
      }
      tab.cursorLine = 1;
      tab.cursorCol = 1;
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
    _focusNode.removeListener(_onEditorFocusChanged);
    _appBarAnimationController.dispose();
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

  void _onAppBarAnimationTick() {
    if (mounted) setState(() {});
  }

  void _onEditorFocusChanged() {
    _updateAppBarVisibility();
  }

  @override
  void didChangeMetrics() {
    super.didChangeMetrics();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _updateAppBarVisibility();
    });
  }

  void _updateAppBarVisibility() {
    final appearance = ref.read(textEditorAppearanceProvider);
    if (!appearance.autoHideAppBar || _readOnly) {
      if (_appBarAnimationController.value != 1.0) {
        _appBarAnimationController.animateTo(
          1.0,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
        );
      }
      return;
    }

    final bottomInset = MediaQuery.maybeViewInsetsOf(context)?.bottom ?? 0;
    final isKeyboardOpen = bottomInset > 0;
    final isEditing = isKeyboardOpen && _focusNode.hasFocus;

    final target = isEditing ? 0.0 : 1.0;
    if (_appBarAnimationController.value != target) {
      _appBarAnimationController.animateTo(
        target,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeInOutCubic,
      );
    }
  }

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
            (_tabBarAnimationController.value - delta / _kTabStripHeight)
                .clamp(0.0, 1.0);
        _tabBarAnimationController.value = nextValue;
      }
    } else if (notification is OverscrollNotification) {
      final delta = notification.overscroll;
      if (delta != 0) {
        final nextValue =
            (_tabBarAnimationController.value - delta / _kTabStripHeight)
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
    final controller = _activeTab.verticalScrollController;
    if (controller.hasClients) {
      final pos = controller.position;
      if (pos.hasPixels && pos.pixels <= 0) atTop = 1;
    }
    final value = _tabBarAnimationController.value;
    final target = atTop ?? (value >= 0.5 ? 1.0 : 0.0);
    if (value != target) _animateTabBar(target);
  }

  void _onTabTextChanged(EditorTab tab) {
    if (tab.isApplyingProgrammaticText) {
      tab.lastCodeLines = tab.codeController.value.codeLines;
      return;
    }

    final selection = tab.codeController.selection;
    final codeLines = tab.codeController.value.codeLines;
    final isSameCodeLines = identical(codeLines, tab.lastCodeLines);
    final lineCount = isSameCodeLines ? tab.lineCount : codeLines.lineCount;
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

    final isBusyBuilding =
        SchedulerBinding.instance.schedulerPhase ==
            SchedulerPhase.persistentCallbacks ||
        (WidgetsBinding.instance.buildOwner?.debugBuilding ?? false);

    if (isSameCodeLines) {
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

    final updatedLineCount = lineCount;
    int totalChars = updatedLineCount > 0 ? updatedLineCount - 1 : 0;
    for (final segment in codeLines.segments) {
      for (final line in segment.codeLines) {
        totalChars += line.charCount;
      }
    }

    void updateState() {
      if (!mounted) return;
      setState(() {
        tab.isDirty = true;
        tab.lineCount = updatedLineCount;
        tab.charCount = totalChars;
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
    final activeIndex = encodings.indexWhere(
      (e) => e.name == tab.encoding.name,
    );
    final activeKey = GlobalKey();
    var scrolledToActive = false;
    final encoding = await showDialog<EditorTextEncoding>(
      context: context,
      builder: (dialogContext) {
        final cs = Theme.of(dialogContext).colorScheme;
        if (!scrolledToActive) {
          scrolledToActive = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            final activeContext = activeKey.currentContext;
            if (activeContext != null) {
              Scrollable.ensureVisible(activeContext, alignment: 0.5);
            }
          });
        }
        return SimpleDialog(
          title: Text(dialogContext.l10n.textEditorEncodingTooltip),
          children: [
            for (var i = 0; i < encodings.length; i++)
              ListTile(
                key: i == activeIndex ? activeKey : null,
                dense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 24),
                selected: i == activeIndex,
                selectedColor: cs.onPrimaryContainer,
                selectedTileColor: cs.primaryContainer,
                title: Text(
                  encodings[i].label,
                  style: i == activeIndex
                      ? const TextStyle(fontWeight: FontWeight.w600)
                      : null,
                ),
                trailing: i == activeIndex
                    ? const Icon(Icons.check_rounded, size: 18)
                    : null,
                onTap: () => Navigator.of(dialogContext).pop(encodings[i]),
              ),
          ],
        );
      },
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

  Future<Uint8List?> _encodeTabContent(EditorTab tab, [String? text]) async {
    try {
      final content = text ?? tab.codeController.text;
      return await tab.encoding.encode(content);
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

    final content = tab.codeController.text;
    final encodedContent = await _encodeTabContent(tab, content);
    if (encodedContent == null) return false;

    setState(() {
      if (isAutosave) {
        tab.isAutosaving = true;
      } else {
        tab.isSaving = true;
      }
    });
    final ok = await ref
        .read(vaultFileIoApiProvider)
        .writeWholeFile(widget.container, tab.filePath, encodedContent);

    if (ok) {
      if (mounted) {
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

  void _onTabTapped(EditorTab tab, BuildContext tabContext) {
    final index = _tabs.indexOf(tab);
    if (index < 0) return;
    if (index == _activeTabIndex) {
      _showTabMenu(tab, tabContext);
    } else {
      setState(() => _activeTabIndex = index);
      _scrollToActiveTab();
    }
  }

  void _reorderTabs(int oldIndex, int newIndex) {
    if (oldIndex == newIndex ||
        oldIndex < 0 ||
        oldIndex >= _tabs.length ||
        newIndex < 0 ||
        newIndex >= _tabs.length) {
      return;
    }
    final active = _activeTab;
    setState(() {
      final moved = _tabs.removeAt(oldIndex);
      _tabs.insert(newIndex, moved);
      _activeTabIndex = _tabs.indexOf(active);
    });
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

  Future<void> _renameTab(EditorTab tab) async {
    final oldPath = tab.filePath;
    final oldName = tab.fileName;
    final slash = oldPath.lastIndexOf('/');
    final parentDir = slash < 0 ? '' : oldPath.substring(0, slash);

    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => _RenameTabDialog(initialName: oldName),
    );

    if (result == null || result == oldName || !mounted) return;
    if (!_tabs.contains(tab)) return;
    final newPath = parentDir.isEmpty ? result : '$parentDir/$result';

    tab.autosaveTimer?.cancel();
    for (var i = 0; i < 30 && (tab.isSaving || tab.isAutosaving); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      if (!mounted) return;
    }

    final ok = await ref
        .read(vaultFileIoApiProvider)
        .renameFile(widget.container, oldPath, newPath);
    if (!mounted) return;

    if (ok) {
      _syncRenamedPath(oldPath, newPath, false);
      setState(() {});
      _scrollToActiveTab();
    } else {
      showAppSnackBar(
        context,
        message: context.l10n.saveFailedWithError(''),
        tone: AppBannerTone.error,
      );
    }
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
      if (index < _activeTabIndex) _activeTabIndex--;
      _activeTabIndex = _activeTabIndex.clamp(0, _tabs.length - 1);
    });
    _scrollToActiveTab();
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
    final caseSensitive = FilesystemRules.of(
      resolveFilesystemType(widget.container),
    ).caseSensitive;
    String foldName(String n) => caseSensitive ? n : n.toLowerCase();
    final existingNames = RawEntry.parseAll(
      rawList ?? const [],
    ).map((e) => foldName(e.name)).toSet();

    if (existingNames.contains(foldName(result)) && mounted) {
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
    if (tab.isLargeFile && !tab.showMarkdownPreview) return;
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

  @override
  Widget build(BuildContext context) {
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
    final stripHeight = _kTabStripHeight * reveal;
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
      return _tabSlideHost(
        tabBar: tabBar,
        builder: (_) => Theme(
            data: markdownTheme,
            child: DefaultTextStyle(
              style: markdownTheme.textTheme.bodyMedium!.copyWith(
                color: canvasForeground,
              ),
              child: FastScrollbar(
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
              ),
            ),
          ),
      );
    }

    final appearance = _effectiveAppearance(
      ref.watch(textEditorAppearanceProvider),
    );
    final softKeyboardVisible = MediaQuery.of(context).viewInsets.bottom > 0;

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
        ? _kTabStripHeight
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

class _RenameTabDialog extends StatefulWidget {
  final String initialName;

  const _RenameTabDialog({required this.initialName});

  @override
  State<_RenameTabDialog> createState() => _RenameTabDialogState();
}

class _RenameTabDialogState extends State<_RenameTabDialog> {
  late final TextEditingController _controller;
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    final name = widget.initialName;
    final dot = name.lastIndexOf('.');
    _controller = TextEditingController.fromValue(
      TextEditingValue(
        text: name,
        selection: TextSelection(
          baseOffset: 0,
          extentOffset: dot > 0 ? dot : name.length,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    if (_formKey.currentState?.validate() ?? false) {
      Navigator.of(context).pop(_controller.text.trim());
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(context.l10n.textEditorRenameDialogTitle),
      content: Form(
        key: _formKey,
        child: TextFormField(
          controller: _controller,
          autofocus: true,
          decoration: InputDecoration(
            labelText: context.l10n.textEditorSaveAsFileNameLabel,
          ),
          validator: (val) {
            final text = val?.trim() ?? '';
            if (text.isEmpty) return context.l10n.validationEmptyName;
            if (text.contains('/') || text.contains('\\')) {
              return context.l10n.validationIllegalChar('/', 0, 'vault');
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
        FilledButton(onPressed: _submit, child: Text(context.l10n.done)),
      ],
    );
  }
}

class _MoveToFolderDialog extends ConsumerStatefulWidget {
  final MountedContainer container;
  final String currentEntryPath;
  final bool isDir;
  final bool isCopy;

  const _MoveToFolderDialog({
    required this.container,
    required this.currentEntryPath,
    required this.isDir,
    this.isCopy = false,
  });

  @override
  ConsumerState<_MoveToFolderDialog> createState() =>
      _MoveToFolderDialogState();
}

class _MoveToFolderDialogState extends ConsumerState<_MoveToFolderDialog> {
  String _currentDir = '';
  late Future<List<String>?> _dirFuture;

  @override
  void initState() {
    super.initState();
    _loadDir();
  }

  void _loadDir() {
    _dirFuture = ref
        .read(vaultFileIoApiProvider)
        .listDirectory(widget.container, _currentDir);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return AlertDialog(
      title: Text(
        widget.isCopy
            ? context.l10n.textEditorCopyToDialogTitle
            : context.l10n.textEditorMoveToDialogTitle,
      ),
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
                          _loadDir();
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
                future: _dirFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  final folders =
                      RawEntry.parseAll(
                          snapshot.data ?? const [],
                        ).where((e) => e.isDir).toList()
                        ..sort(
                          (a, b) => a.name
                              .toLowerCase()
                              .compareTo(b.name.toLowerCase()),
                        );

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
                          setState(() {
                            _currentDir = folderFullPath;
                            _loadDir();
                          });
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
          label: Text(
            widget.isCopy
                ? context.l10n.textEditorCopyHereButton
                : context.l10n.textEditorMoveHereButton,
          ),
          onPressed: () => Navigator.of(context).pop(_currentDir),
        ),
      ],
    );
  }
}

/// Asks for a file name and creates an empty file with it in [parentDir].
///
/// Returns the new file's path, or null if the dialog was cancelled, the name
/// is already taken, or creation failed (the latter two show an error
/// snackbar).
Future<String?> _promptAndCreateEmptyFile({
  required BuildContext context,
  required WidgetRef ref,
  required MountedContainer container,
  required String parentDir,
}) async {
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

  if (result == null || !context.mounted) return null;
  final newFilePath = parentDir.isEmpty ? result : '$parentDir/$result';

  final rawList = await ref
      .read(vaultFileIoApiProvider)
      .listDirectory(container, parentDir);
  final caseSensitive = FilesystemRules.of(
    resolveFilesystemType(container),
  ).caseSensitive;
  String foldName(String n) => caseSensitive ? n : n.toLowerCase();
  final existingNames = RawEntry.parseAll(
    rawList ?? const [],
  ).map((e) => foldName(e.name)).toSet();

  if (existingNames.contains(foldName(result))) {
    if (context.mounted) {
      showAppSnackBar(
        context,
        message: context.l10n.textEditorFileAlreadyExistsError,
        tone: AppBannerTone.error,
      );
    }
    return null;
  }

  final ok = await ref
      .read(vaultFileIoApiProvider)
      .createEmptyFile(container, newFilePath);
  if (ok) return newFilePath;

  if (context.mounted) {
    showAppSnackBar(
      context,
      message: context.l10n.saveFailedWithError(''),
      tone: AppBannerTone.error,
    );
  }
  return null;
}

class _ProjectDrawer extends ConsumerStatefulWidget {
  final MountedContainer container;
  final String initialDirPath;
  final EditorChrome? chrome;
  final String activeFilePath;
  final bool Function(String path) isTabOpen;
  final ValueChanged<String> onOpenFile;
  final void Function(String oldPath, String newPath, bool isDir)
  onSyncRenamedPath;
  final void Function(String deletedPath, bool isDir)
  onCloseTabsForDeletedPath;
  final void Function(String fullPath, String name) onShowImagePreview;
  final bool Function(String name) isImageFile;
  final bool Function(String name) isUnsupportedBinaryFile;

  const _ProjectDrawer({
    required this.container,
    required this.initialDirPath,
    required this.chrome,
    required this.activeFilePath,
    required this.isTabOpen,
    required this.onOpenFile,
    required this.onSyncRenamedPath,
    required this.onCloseTabsForDeletedPath,
    required this.onShowImagePreview,
    required this.isImageFile,
    required this.isUnsupportedBinaryFile,
  });

  @override
  ConsumerState<_ProjectDrawer> createState() => _ProjectDrawerState();
}

class _ProjectDrawerState extends ConsumerState<_ProjectDrawer> {
  late String _projectDirPath;
  late Future<List<String>?> _directoryFuture;

  bool _drawerSearchOpen = false;
  final TextEditingController _drawerSearchController =
      TextEditingController();
  String _drawerSearchQuery = '';

  @override
  void initState() {
    super.initState();
    _projectDirPath = widget.initialDirPath;
    _loadDirectory();
    _drawerSearchController.addListener(() {
      final q = _drawerSearchController.text.trim().toLowerCase();
      if (q != _drawerSearchQuery) {
        setState(() => _drawerSearchQuery = q);
      }
    });
  }

  @override
  void dispose() {
    _drawerSearchController.dispose();
    super.dispose();
  }

  void _loadDirectory({bool refresh = false}) {
    _directoryFuture = ref
        .read(vaultFileIoApiProvider)
        .listDirectory(widget.container, _projectDirPath, refresh: refresh);
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

  String _generateDuplicateName(
    String fileName,
    Set<String> existingNames,
    bool caseSensitive,
  ) {
    String fold(String s) => caseSensitive ? s : s.toLowerCase();
    final dotIdx = fileName.lastIndexOf('.');
    final stem = dotIdx > 0 ? fileName.substring(0, dotIdx) : fileName;
    final ext = dotIdx > 0 ? fileName.substring(dotIdx) : '';

    for (int i = 1; i < 9999; i++) {
      final candidate = '$stem ($i)$ext';
      if (!existingNames.contains(fold(candidate))) {
        return candidate;
      }
    }
    return '$stem (copy)$ext';
  }

  Future<bool> _copySingleFile(String sourcePath, String destPath) async {
    final api = ref.read(vaultFileIoApiProvider);
    final directOk = await api.copyFile(
      widget.container,
      sourcePath,
      widget.container,
      destPath,
    );
    if (directOk) return true;

    final bytes = await api.readWholeFile(widget.container, sourcePath);
    if (bytes == null) return false;
    return api.writeWholeFile(widget.container, destPath, bytes);
  }

  Future<bool> _copyRecursive(
    String sourcePath,
    String destPath,
    bool isDir,
  ) async {
    final api = ref.read(vaultFileIoApiProvider);
    if (!isDir) {
      return _copySingleFile(sourcePath, destPath);
    }

    await api.createDirectory(widget.container, destPath);
    final rawList = await api.listDirectory(widget.container, sourcePath);
    final entries = RawEntry.parseAll(rawList ?? const []);
    var allOk = true;
    for (final child in entries) {
      if (child.name.startsWith('System:')) continue;
      final childSrc = '$sourcePath/${child.name}';
      final childDest = '$destPath/${child.name}';
      final ok = await _copyRecursive(childSrc, childDest, child.isDir);
      if (!ok) allOk = false;
    }
    return allOk;
  }

  Future<void> _duplicateDrawerItem(RawEntry entry, String fullPath) async {
    final parentDir = _projectDirPath;
    final rawList = await ref
        .read(vaultFileIoApiProvider)
        .listDirectory(widget.container, parentDir);
    final caseSensitive = FilesystemRules.of(
      resolveFilesystemType(widget.container),
    ).caseSensitive;
    String foldName(String n) => caseSensitive ? n : n.toLowerCase();
    final existingNames = RawEntry.parseAll(
      rawList ?? const [],
    ).map((e) => foldName(e.name)).toSet();

    final uniqueName = _generateDuplicateName(
      entry.name,
      existingNames,
      caseSensitive,
    );
    final newFullPath =
        parentDir.isEmpty ? uniqueName : '$parentDir/$uniqueName';

    final ok = await _copyRecursive(fullPath, newFullPath, entry.isDir);
    if (!mounted) return;
    if (ok) {
      setState(() => _loadDirectory(refresh: true));
      showAppSnackBar(
        context,
        message: context.l10n.textEditorCopiedSuccessfully,
        tone: AppBannerTone.success,
      );
    } else {
      showAppSnackBar(
        context,
        message: context.l10n.saveFailedWithError(''),
        tone: AppBannerTone.error,
      );
    }
  }

  Future<void> _copyDrawerItem(RawEntry entry, String fullPath) async {
    final targetDir = await showDialog<String>(
      context: context,
      builder: (ctx) => _MoveToFolderDialog(
        container: widget.container,
        currentEntryPath: fullPath,
        isDir: entry.isDir,
        isCopy: true,
      ),
    );

    if (targetDir == null || !mounted) return;
    var newFullPath =
        targetDir.isEmpty ? entry.name : '$targetDir/${entry.name}';

    final rawList = await ref
        .read(vaultFileIoApiProvider)
        .listDirectory(widget.container, targetDir);
    final caseSensitive = FilesystemRules.of(
      resolveFilesystemType(widget.container),
    ).caseSensitive;
    String foldName(String n) => caseSensitive ? n : n.toLowerCase();
    final existingNames = RawEntry.parseAll(
      rawList ?? const [],
    ).map((e) => foldName(e.name)).toSet();

    if (existingNames.contains(foldName(entry.name))) {
      if (newFullPath == fullPath) {
        final uniqueName = _generateDuplicateName(
          entry.name,
          existingNames,
          caseSensitive,
        );
        newFullPath =
            targetDir.isEmpty ? uniqueName : '$targetDir/$uniqueName';
      } else {
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
        if (overwrite != true || !mounted) return;
      }
    }

    final ok = await _copyRecursive(fullPath, newFullPath, entry.isDir);
    if (!mounted) return;
    if (ok) {
      setState(() => _loadDirectory(refresh: true));
      showAppSnackBar(
        context,
        message: context.l10n.textEditorCopiedSuccessfully,
        tone: AppBannerTone.success,
      );
    } else {
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
        isCopy: false,
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
      widget.onSyncRenamedPath(fullPath, newFullPath, entry.isDir);
      setState(() => _loadDirectory(refresh: true));
    } else if (mounted) {
      showAppSnackBar(
        context,
        message: context.l10n.saveFailedWithError(''),
        tone: AppBannerTone.error,
      );
    }
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
      widget.onSyncRenamedPath(fullPath, newFullPath, entry.isDir);
      setState(() => _loadDirectory(refresh: true));
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
      widget.onCloseTabsForDeletedPath(fullPath, entry.isDir);
      setState(() => _loadDirectory(refresh: true));
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
              leading: const Icon(Icons.copy_rounded),
              title: Text(ctx.l10n.textEditorCopyToMenuItem),
              onTap: () {
                Navigator.of(ctx).pop();
                _copyDrawerItem(entry, fullPath);
              },
            ),
            ListTile(
              leading: const Icon(Icons.control_point_duplicate_rounded),
              title: Text(ctx.l10n.textEditorDuplicateMenuItem),
              onTap: () {
                Navigator.of(ctx).pop();
                _duplicateDrawerItem(entry, fullPath);
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

  Future<void> _createNewFileTab() async {
    final newFilePath = await _promptAndCreateEmptyFile(
      context: context,
      ref: ref,
      container: widget.container,
      parentDir: _projectDirPath,
    );
    if (newFilePath == null || !mounted) return;
    setState(() => _loadDirectory(refresh: true));
    widget.onOpenFile(newFilePath);
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
      setState(() => _loadDirectory(refresh: true));
    } else if (mounted) {
      showAppSnackBar(
        context,
        message: context.l10n.saveFailedWithError(''),
        tone: AppBannerTone.error,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final settingsUri =
        widget.container.volId < 0 ? null : widget.container.uri;
    final skin = ref
        .watch(fileManagerToolbarSettingsProvider(settingsUri))
        .config
        .skin;

    return Drawer(
      backgroundColor: widget.chrome?.panelBackground ?? cs.surfaceContainer,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 4, 12),
              decoration: BoxDecoration(
                color: widget.chrome?.panelBackground ?? cs.surfaceContainer,
              ),
              child: Row(
                children: [
                  Icon(Icons.inventory_2_outlined, size: 20, color: cs.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      widget.container.displayName,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: Icon(
                      _drawerSearchOpen
                          ? Icons.search_off_rounded
                          : Icons.search_rounded,
                      size: 20,
                    ),
                    visualDensity: VisualDensity.compact,
                    tooltip: context.l10n.search,
                    onPressed: () {
                      setState(() {
                        _drawerSearchOpen = !_drawerSearchOpen;
                        if (!_drawerSearchOpen) {
                          _drawerSearchController.clear();
                          _drawerSearchQuery = '';
                        }
                      });
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.refresh_rounded, size: 20),
                    visualDensity: VisualDensity.compact,
                    tooltip: context.l10n.refreshListButton,
                    onPressed: () => setState(() => _loadDirectory(refresh: true)),
                  ),
                  IconButton(
                    icon: const Icon(Icons.note_add_outlined, size: 20),
                    visualDensity: VisualDensity.compact,
                    tooltip: context.l10n.textEditorNewFileTooltip,
                    onPressed: _createNewFileTab,
                  ),
                  IconButton(
                    icon: const Icon(
                      Icons.create_new_folder_outlined,
                      size: 20,
                    ),
                    visualDensity: VisualDensity.compact,
                    tooltip: context.l10n.textEditorNewFolderTooltip,
                    onPressed: _createDrawerFolder,
                  ),
                ],
              ),
            ),
            Container(
              decoration: BoxDecoration(
                color: widget.chrome?.panelBackground ?? cs.surfaceContainer,
              ),
              child: BreadcrumbBar(
                stack: _drawerPathStack,
                backgroundColor: Colors.transparent,
                onTap: (index) {
                  final target = _drawerPathStack[index];
                  setState(() {
                    _projectDirPath = target.fatPath;
                    _drawerSearchQuery = '';
                    _drawerSearchController.clear();
                    _loadDirectory();
                  });
                },
              ),
            ),
            if (_drawerSearchOpen)
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.search_rounded,
                      size: 16,
                      color: cs.onSurfaceVariant,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _drawerSearchController,
                        autofocus: true,
                        style: const TextStyle(fontSize: 13),
                        decoration: InputDecoration(
                          hintText: context.l10n.textEditorSearchFilesHint,
                          hintStyle: TextStyle(
                            fontSize: 13,
                            color: cs.onSurfaceVariant,
                          ),
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding:
                              const EdgeInsets.symmetric(vertical: 8),
                        ),
                      ),
                    ),
                    if (_drawerSearchQuery.isNotEmpty)
                      IconButton(
                        icon: const Icon(Icons.clear_rounded, size: 16),
                        visualDensity: VisualDensity.compact,
                        onPressed: () {
                          _drawerSearchController.clear();
                          setState(() => _drawerSearchQuery = '');
                        },
                      ),
                  ],
                ),
              ),
            Expanded(
              child: FutureBuilder<List<String>?>(
                future: _directoryFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  final rawEntries = snapshot.data ?? [];
                  var entries = RawEntry.parseAll(rawEntries)
                    ..sort((a, b) {
                      if (a.isDir != b.isDir) return a.isDir ? -1 : 1;
                      return a.name
                          .toLowerCase()
                          .compareTo(b.name.toLowerCase());
                    });

                  if (_drawerSearchQuery.isNotEmpty) {
                    entries = entries
                        .where(
                          (e) => e.name.toLowerCase().contains(
                                _drawerSearchQuery,
                              ),
                        )
                        .toList();
                  }

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
                            _drawerSearchQuery.isNotEmpty
                                ? context.l10n.noResultsTitle
                                : context.l10n.filesEmptyMessage,
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
                      final isOpen = widget.isTabOpen(fullPath);
                      final isCurrentActive = fullPath == widget.activeFilePath;
                      final isUnsupported = widget.isUnsupportedBinaryFile(
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
                            contentPadding: const EdgeInsets.only(
                              left: 8,
                              right: 2,
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
                            subtitle: !entry.isDir && entry.sizeBytes > 0
                                ? Text(
                                    formatBytes(entry.sizeBytes),
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: cs.onSurfaceVariant
                                          .withValues(alpha: 0.8),
                                    ),
                                  )
                                : null,
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (isCurrentActive)
                                  Icon(
                                    Icons.edit_note_rounded,
                                    size: 18,
                                    color: cs.primary,
                                  )
                                else if (isOpen)
                                  Container(
                                    width: 6,
                                    height: 6,
                                    margin: const EdgeInsets.only(right: 4),
                                    decoration: BoxDecoration(
                                      color: cs.primary,
                                      shape: BoxShape.circle,
                                    ),
                                  )
                                else if (entry.isDir)
                                  Icon(
                                    Icons.chevron_right_rounded,
                                    size: 18,
                                    color: cs.onSurfaceVariant,
                                  ),
                              ],
                            ),
                            onTap: () {
                              if (entry.isDir) {
                                setState(() {
                                  _projectDirPath = fullPath;
                                  _drawerSearchQuery = '';
                                  _drawerSearchController.clear();
                                  _loadDirectory();
                                });
                              } else if (widget.isImageFile(entry.name)) {
                                Navigator.of(context).pop();
                                widget.onShowImagePreview(fullPath, entry.name);
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
                                widget.onOpenFile(fullPath);
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
}
