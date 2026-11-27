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
import 'package:vaultexplorer/core/theme/skin/skin_area.dart';
import 'package:vaultexplorer/core/theme/skin/skin_area_scope.dart';
import 'package:vaultexplorer/core/utils/format_utils.dart';
import 'package:vaultexplorer/core/utils/raw_entry.dart';
import 'package:vaultexplorer/core/widgets/common_widgets.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/data/models/file_operation.dart';
import 'package:vaultexplorer/data/services/text_editor_appearance_service.dart';
import 'package:vaultexplorer/features/browser/viewer/close_on_container_lock.dart';
import 'package:vaultexplorer/features/browser/viewer/markdown/markdown_body_view.dart';
import 'package:vaultexplorer/features/browser/viewer/markdown/markdown_image_picker_dialog.dart';
import 'package:vaultexplorer/features/browser/viewer/markdown/markdown_link_syntax.dart';
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

part 'text_editor_screen_editing.dart';
part 'text_editor_screen_files.dart';
part 'text_editor_screen_shortcuts.dart';
part 'text_editor_screen_tabs.dart';
part 'text_editor_screen_ui.dart';

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
    with
        WidgetsBindingObserver,
        TickerProviderStateMixin,
        CloseOnContainerLock<TextEditorScreen> {
  @override
  int get watchedVolId => widget.container.volId;

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
    startClosingOnContainerLock();

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
    stopClosingOnContainerLock();
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
    final opService = ref.read(fileOperationServiceProvider);
    final ok = await ref
        .read(vaultFileIoApiProvider)
        .writeWholeFile(widget.container, newFilePath, encodedContent);

    if (ok) opService.notifyVolumeContentChanged(widget.container.volId);
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

  void _toggleReadOnly() {
    if (widget.container.readOnly) return;
    setState(() => _readOnly = !_readOnly);
    if (_readOnly) {
      _focusNode.unfocus();
    }
  }

  void _toggleWordWrap() => setState(() => _wordWrap = !_wordWrap);

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

  bool get _isJsonFile {
    final dot = _activeTab.filePath.lastIndexOf('.');
    if (dot < 0) return false;
    return _jsonExtensions.contains(
      _activeTab.filePath.substring(dot + 1).toLowerCase(),
    );
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

  @override
  Widget build(BuildContext context) => SkinAreaHint(
    area: SkinArea.editor,
    child: _buildEditorScreen(context),
  );
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
  final opService = ref.read(fileOperationServiceProvider);
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
  if (ok) {
    opService.notifyVolumeContentChanged(container.volId);
    return newFilePath;
  }

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

    final opService = ref.read(fileOperationServiceProvider);
    final ok = await _copyRecursive(fullPath, newFullPath, entry.isDir);
    opService.notifyVolumeContentChanged(widget.container.volId);
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

    final opService = ref.read(fileOperationServiceProvider);
    final ok = await _copyRecursive(fullPath, newFullPath, entry.isDir);
    opService.notifyVolumeContentChanged(widget.container.volId);
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

    final opService = ref.read(fileOperationServiceProvider);
    final ok = await ref
        .read(vaultFileIoApiProvider)
        .renameFile(widget.container, fullPath, newFullPath);

    if (ok) opService.notifyVolumeContentChanged(widget.container.volId);
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

    final opService = ref.read(fileOperationServiceProvider);
    final ok = await ref
        .read(vaultFileIoApiProvider)
        .renameFile(widget.container, fullPath, newFullPath);

    if (ok) opService.notifyVolumeContentChanged(widget.container.volId);
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

    final opService = ref.read(fileOperationServiceProvider);
    final ok = await ref
        .read(vaultFileIoApiProvider)
        .deleteFile(widget.container, fullPath);

    if (ok) opService.notifyVolumeContentChanged(widget.container.volId);
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

    final opService = ref.read(fileOperationServiceProvider);
    final ok = await ref
        .read(vaultFileIoApiProvider)
        .createDirectory(widget.container, newDirPath);

    if (ok) opService.notifyVolumeContentChanged(widget.container.volId);
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
                rootLabel: widget.container.displayName,
                rootIcon: breadcrumbRootIconFor(widget.container),
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
