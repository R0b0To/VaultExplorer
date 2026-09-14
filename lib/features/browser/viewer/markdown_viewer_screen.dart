import 'dart:async';

import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/providers/vault_engine_providers.dart';
import 'package:vaultexplorer/core/theme/app_theme.dart';
import 'package:vaultexplorer/core/widgets/common_widgets.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/features/browser/viewer/markdown/markdown_body_view.dart';
import 'package:vaultexplorer/features/browser/viewer/text_editor_controller.dart';

class SearchableTextEditingController extends TextEditingController {
  String? searchQuery;
  int currentMatchIndex = 0;

  SearchableTextEditingController({super.text});

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final query = searchQuery?.trim();
    if (query == null || query.isEmpty) {
      return super.buildTextSpan(context: context, style: style, withComposing: withComposing);
    }

    final fullText = text;
    final lowerFull = fullText.toLowerCase();
    final lowerQuery = query.toLowerCase();

    final spans = <InlineSpan>[];
    int start = 0;
    int matchCount = 0;

    final baseStyle = style ?? const TextStyle(fontFamily: 'monospace', fontSize: 14, height: 1.5);

    while (true) {
      final index = lowerFull.indexOf(lowerQuery, start);
      if (index == -1) {
        spans.add(TextSpan(text: fullText.substring(start), style: baseStyle));
        break;
      }

      if (index > start) {
        spans.add(TextSpan(text: fullText.substring(start, index), style: baseStyle));
      }

      final isCurrent = matchCount == currentMatchIndex;
      matchCount++;

      spans.add(
        TextSpan(
          text: fullText.substring(index, index + query.length),
          style: baseStyle.copyWith(
            backgroundColor: isCurrent ? Colors.orange : Colors.yellow.withValues(alpha: 0.7),
            color: Colors.black,
            fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      );

      start = index + query.length;
    }

    return TextSpan(style: style, children: spans);
  }
}

class MarkdownViewerScreen extends ConsumerStatefulWidget {
  final MountedContainer container;
  final String filePath;

  const MarkdownViewerScreen({
    super.key,
    required this.container,
    required this.filePath,
  });

  @override
  ConsumerState<MarkdownViewerScreen> createState() => _MarkdownViewerScreenState();
}

class _MarkdownViewerScreenState extends ConsumerState<MarkdownViewerScreen> {
  final SearchableTextEditingController _textController = SearchableTextEditingController();
  late final UndoHistoryController _undoController;

  final ScrollController _previewScrollController = ScrollController();
  final ScrollController _editScrollController = ScrollController();
  final GlobalKey<MarkdownBodyViewState> _previewKey = GlobalKey<MarkdownBodyViewState>();

  static const TextStyle _editorTextStyle = TextStyle(
    fontFamily: 'monospace',
    fontSize: 14,
    height: 1.5,
  );

  bool _isPreview = true;
  bool _isSaving = false;
  bool _isAutosaving = false;
  bool _isDirty = false;
  int _lineCount = 0;
  int _charCount = 0;
  DateTime? _lastSavedAt;
  bool _appliedInitialText = false;

  Timer? _autosaveTimer;
  final FocusNode _focusNode = FocusNode();

  // Find in page state
  bool _showFindBar = false;
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  String _searchQuery = '';
  int _currentMatchIndex = 0;
  int _totalMatches = 0;
  final List<int> _editMatchIndices = [];

  @override
  void initState() {
    super.initState();
    _undoController = UndoHistoryController();
    _textController.addListener(_onTextChanged);
    _searchController.addListener(_onSearchChanged);
    Future.microtask(_loadFile);
  }

  Future<void> _loadFile() {
    return ref
        .read(textEditorLoadProvider(widget.container.volId, widget.filePath).notifier)
        .load(
          widget.container,
          context.l10n.textEditorDecryptFailedMessage,
          context.l10n.textEditorInvalidTextFileMessage,
        );
  }

  @override
  void dispose() {
    _autosaveTimer?.cancel();
    _textController.removeListener(_onTextChanged);
    _searchController.removeListener(_onSearchChanged);
    _textController.dispose();
    _searchController.dispose();
    _searchFocusNode.dispose();
    _undoController.dispose();
    _focusNode.dispose();
    _previewScrollController.dispose();
    _editScrollController.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    final text = _textController.text;
    final lines = text.isEmpty ? 0 : text.split('\n').length;

    setState(() {
      _isDirty = true;
      _lineCount = lines;
      _charCount = text.length;
    });

    if (_showFindBar && _searchQuery.isNotEmpty) {
      _updateEditMatches();
    }

    _autosaveTimer?.cancel();
    final loadState = ref.read(textEditorLoadProvider(widget.container.volId, widget.filePath));
    if (!loadState.isLoading && !loadState.hasError) {
      _autosaveTimer = Timer(const Duration(milliseconds: 2500), () {
        if (mounted && _isDirty && !_isSaving && !_isAutosaving) {
          _saveFile(isAutosave: true);
        }
      });
    }
  }

  void _onSearchChanged() {
    final query = _searchController.text;
    setState(() {
      _searchQuery = query;
      _currentMatchIndex = 0;
      _textController.searchQuery = query;
      _textController.currentMatchIndex = 0;
    });

    if (!_isPreview) {
      _updateEditMatches();
    }
  }

  void _updateEditMatches() {
    _editMatchIndices.clear();
    if (_searchQuery.trim().isEmpty) {
      setState(() => _totalMatches = 0);
      return;
    }

    final fullText = _textController.text.toLowerCase();
    final query = _searchQuery.toLowerCase();
    int start = 0;

    while (true) {
      final index = fullText.indexOf(query, start);
      if (index == -1) break;
      _editMatchIndices.add(index);
      start = index + query.length;
    }

    setState(() {
      _totalMatches = _editMatchIndices.length;
      if (_currentMatchIndex >= _totalMatches) {
        _currentMatchIndex = 0;
      }
      _textController.currentMatchIndex = _currentMatchIndex;
    });

    if (_editMatchIndices.isNotEmpty) {
      _jumpToEditMatch(_currentMatchIndex);
    }
  }

  RenderEditable? _getRenderEditable() {
    final renderObject = _focusNode.context?.findRenderObject();
    if (renderObject is RenderEditable) {
      return renderObject;
    }
    RenderEditable? found;
    void visitor(RenderObject child) {
      if (child is RenderEditable) {
        found = child;
        return;
      }
      child.visitChildren(visitor);
    }
    renderObject?.visitChildren(visitor);
    return found;
  }

  double _getEditorContentWidth() {
    final box = context.findRenderObject() as RenderBox?;
    if (box != null && box.hasSize && box.size.width > 32) {
      return box.size.width - 32;
    }
    return MediaQuery.sizeOf(context).width - 32;
  }

  double _getEditorYForCharOffset(int charOffset) {
    if (_textController.text.isEmpty) return 0.0;
    final safeOffset = charOffset.clamp(0, _textController.text.length);
    final currentScroll = _editScrollController.hasClients ? _editScrollController.offset : 0.0;

    final renderEditable = _getRenderEditable();
    if (renderEditable != null) {
      final caretRect = renderEditable.getLocalRectForCaret(TextPosition(offset: safeOffset));
      return caretRect.top + currentScroll;
    }

    final width = _getEditorContentWidth();
    final painter = TextPainter(
      text: TextSpan(text: _textController.text, style: _editorTextStyle),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    );
    painter.layout(maxWidth: width);

    final endOffset = (safeOffset + 1).clamp(0, _textController.text.length);
    final boxes = painter.getBoxesForSelection(
      TextSelection(baseOffset: safeOffset, extentOffset: endOffset),
    );

    if (boxes.isNotEmpty) {
      return boxes.first.top;
    }

    final caret = painter.getOffsetForCaret(
      TextPosition(offset: safeOffset),
      const Rect.fromLTWH(0, 0, 2, 21),
    );
    return caret.dy;
  }

  int _getEditorVisibleSourceLine(double scrollY) {
    if (_textController.text.isEmpty) return 0;

    int charOffset = 0;
    final renderEditable = _getRenderEditable();
    if (renderEditable != null) {
      final globalPoint = renderEditable.localToGlobal(const Offset(16.0, 10.0));
      final position = renderEditable.getPositionForPoint(globalPoint);
      charOffset = position.offset.clamp(0, _textController.text.length);
    } else {
      final width = _getEditorContentWidth();
      final painter = TextPainter(
        text: TextSpan(text: _textController.text, style: _editorTextStyle),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
      );
      painter.layout(maxWidth: width);
      final position = painter.getPositionForOffset(Offset(16.0, scrollY));
      charOffset = position.offset.clamp(0, _textController.text.length);
    }

    final textBefore = _textController.text.substring(0, charOffset);
    return textBefore.split('\n').length - 1;
  }

  double _getEditorScrollYForSourceLine(int line) {
    if (_textController.text.isEmpty || line <= 0) return 0.0;
    final lines = _textController.text.split('\n');
    int charOffset = 0;
    for (int i = 0; i < line && i < lines.length; i++) {
      charOffset += lines[i].length + 1;
    }
    final textY = _getEditorYForCharOffset(charOffset);
    final maxScroll = _editScrollController.hasClients
        ? _editScrollController.position.maxScrollExtent
        : textY;
    return textY.clamp(0.0, maxScroll);
  }

  void _jumpToEditMatch(int matchIdx) {
    if (matchIdx < 0 || matchIdx >= _editMatchIndices.length) return;
    final charOffset = _editMatchIndices[matchIdx];
    final matchY = _getEditorYForCharOffset(charOffset);

    final viewportHeight = _editScrollController.hasClients
        ? _editScrollController.position.viewportDimension
        : 400.0;
    final maxScroll = _editScrollController.hasClients
        ? _editScrollController.position.maxScrollExtent
        : matchY;

    final targetScroll = (matchY - (viewportHeight / 3)).clamp(0.0, maxScroll);

    if (_editScrollController.hasClients) {
      _editScrollController.animateTo(
        targetScroll,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeInOut,
      );
    }
  }

  void _nextMatch() {
    if (_totalMatches == 0) return;
    setState(() {
      _currentMatchIndex = (_currentMatchIndex + 1) % _totalMatches;
      _textController.currentMatchIndex = _currentMatchIndex;
    });
    if (!_isPreview) {
      _jumpToEditMatch(_currentMatchIndex);
    }
  }

  void _previousMatch() {
    if (_totalMatches == 0) return;
    setState(() {
      _currentMatchIndex = (_currentMatchIndex - 1 + _totalMatches) % _totalMatches;
      _textController.currentMatchIndex = _currentMatchIndex;
    });
    if (!_isPreview) {
      _jumpToEditMatch(_currentMatchIndex);
    }
  }

  void _toggleFindBar() {
    setState(() {
      _showFindBar = !_showFindBar;
      if (_showFindBar) {
        _searchFocusNode.requestFocus();
        _onSearchChanged();
      } else {
        _searchController.clear();
        _searchQuery = '';
        _totalMatches = 0;
        _currentMatchIndex = 0;
        _textController.searchQuery = '';
      }
    });
  }

  void _togglePreviewMode() {
    if (_isPreview) {
      final visibleLine = _previewKey.currentState?.getFirstVisibleLine() ?? 0;
      setState(() => _isPreview = false);

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_editScrollController.hasClients) {
          final target = _getEditorScrollYForSourceLine(visibleLine);
          _editScrollController.jumpTo(target);
        }
        if (_showFindBar && _searchQuery.isNotEmpty) {
          _updateEditMatches();
        }
      });
    } else {
      final scrollY = _editScrollController.hasClients ? _editScrollController.offset : 0.0;
      final sourceLine = _getEditorVisibleSourceLine(scrollY);
      setState(() => _isPreview = true);

      WidgetsBinding.instance.addPostFrameCallback((_) {
        _previewKey.currentState?.scrollToLine(sourceLine);
      });
    }
  }

  void _insertImageTemplate() {
    final text = _textController.text;
    final selection = _textController.selection;
    final placeholder = context.l10n.mimeTypeImage;
    final template = '![$placeholder](image.png)';

    if (!selection.isValid || selection.baseOffset < 0) {
      _textController.text = '$text\n$template\n';
      return;
    }

    final newText = text.replaceRange(selection.start, selection.end, template);
    _textController.value = TextEditingValue(
      text: newText,
      selection: TextSelection(
        baseOffset: selection.start + 2,
        extentOffset: selection.start + 2 + placeholder.length,
      ),
    );
    _focusNode.requestFocus();
  }

  Future<bool> _saveFile({bool isAutosave = false}) async {
    _autosaveTimer?.cancel();

    setState(() {
      if (isAutosave) {
        _isAutosaving = true;
      } else {
        _isSaving = true;
      }
    });

    final content = _textController.text;
    final error = await ref
        .read(textEditorLoadProvider(widget.container.volId, widget.filePath).notifier)
        .save(widget.container, content, context.l10n.textEditorWriteBackFailedMessage);

    if (error == null) {
      if (mounted) {
        setState(() {
          _isSaving = false;
          _isAutosaving = false;
          _isDirty = false;
          _lastSavedAt = DateTime.now();
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
          _isSaving = false;
          _isAutosaving = false;
        });

        if (!isAutosave) {
          showAppSnackBar(
            context,
            message: context.l10n.saveFailedWithError(error),
            tone: AppBannerTone.error,
          );
        }
      }
      return false;
    }
  }

  Future<bool> _onWillPop() async {
    if (!_isDirty) return true;

    final saved = await _saveFile(isAutosave: true);
    if (saved) return true;

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
      return await _saveFile();
    } else if (result == 'discard') {
      return true;
    }
    return false;
  }

  Future<void> _handleLinkTap(String url) async {
    try {
      final ok = await ref.read(vaultFileIoApiProvider).launchUrl(url);
      if (!ok && mounted) {
        showAppSnackBar(context, message: context.l10n.couldNotOpenLinkMessage, tone: AppBannerTone.error);
      }
    } catch (_) {
      if (mounted) {
        showAppSnackBar(context, message: context.l10n.couldNotOpenLinkMessage, tone: AppBannerTone.error);
      }
    }
  }

  String get _fileName => widget.filePath.split('/').last;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final loadState = ref.watch(textEditorLoadProvider(widget.container.volId, widget.filePath));

    ref.listen(textEditorLoadProvider(widget.container.volId, widget.filePath), (previous, next) {
      if (!_appliedInitialText && next.loadedText != null) {
        _appliedInitialText = true;
        _textController.text = next.loadedText!;
        _autosaveTimer?.cancel();
        final lines = next.loadedText!.isEmpty ? 0 : next.loadedText!.split('\n').length;
        setState(() {
          _isDirty = false;
          _lineCount = lines;
          _charCount = next.loadedText!.length;
        });
      }
    });

    return PopScope(
      canPop: !_isDirty,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final shouldPop = await _onWillPop();
        if (shouldPop && context.mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(_fileName),
          actions: [
            if (!loadState.isLoading && !loadState.hasError) ...[
              IconButton(
                icon: Icon(_showFindBar ? Icons.search_off_rounded : Icons.search_rounded),
                tooltip: context.l10n.search,
                onPressed: _toggleFindBar,
              ),
              if (!_isPreview) ...[
                IconButton(
                  icon: const Icon(Icons.add_photo_alternate_outlined),
                  tooltip: context.l10n.addFile,
                  onPressed: _insertImageTemplate,
                ),
                ValueListenableBuilder<UndoHistoryValue>(
                  valueListenable: _undoController,
                  builder: (context, value, _) {
                    return Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.undo_rounded),
                          tooltip: context.l10n.undoTooltip,
                          onPressed: value.canUndo ? () => _undoController.undo() : null,
                        ),
                        IconButton(
                          icon: const Icon(Icons.redo_rounded),
                          tooltip: context.l10n.redoTooltip,
                          onPressed: value.canRedo ? () => _undoController.redo() : null,
                        ),
                      ],
                    );
                  },
                ),
              ],
              IconButton(
                icon: Icon(_isPreview ? Icons.edit_note_rounded : Icons.visibility_outlined),
                tooltip: _isPreview
                    ? context.l10n.markdownViewerEditTooltip
                    : context.l10n.markdownViewerPreviewTooltip,
                onPressed: _togglePreviewMode,
              ),
              IconButton(
                icon: (_isSaving || _isAutosaving)
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(
                        Icons.save_rounded,
                        color: _isDirty ? cs.primary : cs.outline,
                      ),
                tooltip: context.l10n.saveChangesTooltip,
                onPressed: (_isDirty && !_isSaving && !_isAutosaving) ? () => _saveFile() : null,
              ),
            ],
          ],
        ),
        body: _buildBody(cs, Theme.of(context).textTheme, loadState),
        bottomNavigationBar: loadState.isLoading || loadState.hasError ? null : _buildBottomBar(cs),
      ),
    );
  }

  Widget _buildBody(ColorScheme cs, TextTheme textTheme, TextEditorLoadState loadState) {
    if (loadState.isLoading) {
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
    if (loadState.hasError) {
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
                style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                loadState.errorMessage,
                textAlign: TextAlign.center,
                style: textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
              ),
              const SizedBox(height: 24),
              OutlinedButton.icon(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.arrow_back_rounded),
                label: Text(context.l10n.goBack),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      children: [
        if (_showFindBar) _buildFindBar(cs),
        Expanded(
          child: IndexedStack(
            index: _isPreview ? 0 : 1,
            children: [
              SelectionArea(
                child: MarkdownBodyView(
                  key: _previewKey,
                  source: _textController.text,
                  container: widget.container,
                  currentFilePath: widget.filePath,
                  onLinkTap: _handleLinkTap,
                  scrollController: _previewScrollController,
                  searchQuery: _showFindBar ? _searchQuery : null,
                  searchMatchIndex: _currentMatchIndex,
                  onMatchesFound: (count) {
                    if (_isPreview && mounted && _totalMatches != count) {
                      setState(() => _totalMatches = count);
                    }
                  },
                ),
              ),
              GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: () {
                  if (!_focusNode.hasFocus) {
                    _focusNode.requestFocus();
                  }
                },
                child: TextField(
                  controller: _textController,
                  scrollController: _editScrollController,
                  focusNode: _focusNode,
                  undoController: _undoController,
                  maxLines: null,
                  minLines: null,
                  expands: true,
                  keyboardType: TextInputType.multiline,
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  ),
                  style: _editorTextStyle,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildFindBar(ColorScheme cs) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        border: Border(bottom: BorderSide(color: cs.outlineVariant, width: 0.5)),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _searchController,
              focusNode: _searchFocusNode,
              decoration: InputDecoration(
                hintText: context.l10n.pdfViewerSearchHint,
                isDense: true,
                border: InputBorder.none,
                hintStyle: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
              ),
              style: const TextStyle(fontSize: 13),
            ),
          ),
          if (_searchQuery.isNotEmpty)
            Text(
              _totalMatches == 0
                  ? context.l10n.pdfViewerNoMatches
                  : context.l10n.xOfYCounter(_currentMatchIndex + 1, _totalMatches),
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
            ),
          IconButton(
            icon: const Icon(Icons.keyboard_arrow_up_rounded, size: 20),
            tooltip: context.l10n.pdfViewerPreviousMatch,
            onPressed: _totalMatches > 0 ? _previousMatch : null,
          ),
          IconButton(
            icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 20),
            tooltip: context.l10n.pdfViewerNextMatch,
            onPressed: _totalMatches > 0 ? _nextMatch : null,
          ),
          IconButton(
            icon: const Icon(Icons.close_rounded, size: 18),
            tooltip: context.l10n.closeSearchTooltip,
            onPressed: _toggleFindBar,
          ),
        ],
      ),
    );
  }

  Widget _buildBottomBar(ColorScheme cs) {
    final timeStr = _lastSavedAt != null
        ? '${_lastSavedAt!.hour.toString().padLeft(2, '0')}:${_lastSavedAt!.minute.toString().padLeft(2, '0')}'
        : null;

    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        border: Border(top: BorderSide(color: cs.outlineVariant, width: 0.5)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Text(
            '${context.l10n.linesCount(_lineCount)}  |  ${context.l10n.charsCount(_charCount)}',
            style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
          ),
          const Spacer(),
          if (_isAutosaving) ...[
            SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(strokeWidth: 1.8, color: cs.primary),
            ),
            const SizedBox(width: 6),
            Text(
              context.l10n.autosavingLabel,
              style: TextStyle(color: cs.primary, fontSize: 12, fontWeight: FontWeight.w500),
            ),
          ] else if (_isSaving) ...[
            Text(
              context.l10n.savingLabel,
              style: TextStyle(color: cs.primary, fontSize: 12, fontWeight: FontWeight.w500),
            ),
          ] else if (_isDirty) ...[
            Text(
              context.l10n.unsavedChangesLabel,
              style: TextStyle(
                color: context.semanticColors.warning,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ] else ...[
            Icon(Icons.check_circle_outline_rounded, size: 14, color: context.semanticColors.success),
            const SizedBox(width: 4),
            Text(
              timeStr != null ? context.l10n.autosavedAtLabel(timeStr) : context.l10n.savedToVault,
              style: TextStyle(
                color: context.semanticColors.success,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ],
      ),
    );
  }
}