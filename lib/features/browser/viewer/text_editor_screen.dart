import 'dart:async';
import 'package:flutter/rendering.dart' show AxisDirection;
import 'package:flutter/scheduler.dart' show SchedulerBinding, SchedulerPhase;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:re_editor/re_editor.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/core/theme/app_theme.dart';
import 'package:vaultexplorer/core/widgets/common_widgets.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/features/browser/viewer/text_editor_controller.dart';
import 'package:vaultexplorer/features/browser/viewer/text_editor_language.dart';
import 'package:vaultexplorer/features/browser/viewer/widgets/editor_accessory_key_bar.dart';

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

class _TextEditorScreenState extends ConsumerState<TextEditorScreen> {
  // re_editor's own controller -- carries the buffer, selection, and undo
  // history (replacing the plain TextEditingController + UndoHistoryController
  // pair the TextField-based editor used). Starts empty and is populated
  // once via `.text =` the moment the file finishes decrypting; see the
  // ref.listen callback in build().
  final CodeLineEditingController _codeController = CodeLineEditingController.fromText('');

  // Genuinely ephemeral UI state -- tied to the controller's own listener,
  // not domain data. Load/save/error state lives in TextEditorLoad.
  bool _isSaving = false;
  bool _isAutosaving = false;
  bool _isDirty = false;
  int _lineCount = 0;
  int _charCount = 0;
  DateTime? _lastSavedAt;
  bool _appliedInitialText = false;
  String _lastKnownText = '';
  Object? _lastCodeLines;

  // Read/inspection-mode lock (Phase 1, item 3). Locking closes the
  // soft-keyboard IME connection outright rather than merely hiding it --
  // see `_toggleReadOnly` -- while still allowing tap-to-select/scroll,
  // since re_editor's readOnly flag only blocks edits, not selection.
  bool _readOnly = false;

  Timer? _autosaveTimer;
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _codeController.addListener(_onTextChanged);
    // context.l10n needs didChangeDependencies to have run first, so defer
    // to a microtask (runs right after initState, before the first build).
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
    _codeController.removeListener(_onTextChanged);
    _codeController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    final codeLines = _codeController.value.codeLines;
    if (identical(codeLines, _lastCodeLines)) {
      return;
    }
    final currentText = _codeController.text;
    if (currentText == _lastKnownText) {
      _lastCodeLines = codeLines;
      return;
    }
    _lastCodeLines = codeLines;
    _lastKnownText = currentText;

    void updateState() {
      if (!mounted) return;
      setState(() {
        _isDirty = true;
        _lineCount = _codeController.lineCount;
        _charCount = currentText.length;
      });
    }

    if (SchedulerBinding.instance.schedulerPhase == SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) => updateState());
    } else {
      updateState();
    }

    // Debounced autosave: triggers 2.5s after user stops typing
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

  Future<bool> _saveFile({bool isAutosave = false}) async {
    _autosaveTimer?.cancel();

    setState(() {
      if (isAutosave) {
        _isAutosaving = true;
      } else {
        _isSaving = true;
      }
    });

    final content = _codeController.text;
    final error = await ref
        .read(textEditorLoadProvider(widget.container.volId, widget.filePath).notifier)
        .save(widget.container, content, context.l10n.textEditorWriteBackFailedMessage);

   if (error == null) {
      if (mounted) {
        _lastKnownText = content;
        _lastCodeLines = _codeController.value.codeLines;
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

    // Flush any pending changes automatically on exit
    final saved = await _saveFile(isAutosave: true);
    if (saved) return true;

    if (!mounted) return true;
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.unsavedChangesTitle),
        content: Text(
          context.l10n.unsavedChangesMessage,
        ),
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

  String get _fileName => widget.filePath.split('/').last;

  void _toggleReadOnly() {
    setState(() => _readOnly = !_readOnly);
    if (_readOnly) {
      // Flipping `readOnly` alone only stops *future* IME connections from
      // opening (see re_editor's `_CodeInputController.readOnly` setter) --
      // it doesn't close one that's already open. Unfocus explicitly so
      // locking the editor dismisses an active soft keyboard right away.
      _focusNode.unfocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final loadState = ref.watch(textEditorLoadProvider(widget.container.volId, widget.filePath));

    ref.listen(textEditorLoadProvider(widget.container.volId, widget.filePath), (previous, next) {
      // Apply loaded text to the controller exactly once, the moment it
      // goes from null to non-null -- matches the original synchronous
      // `_textController.text = text` inside _loadFile. clearHistory()
      // matters here: without it this initial assignment would itself be
      // undoable, letting a fresh, unedited open of the file show a live
      // "Undo" button that reverts it to blank.
      if (!_appliedInitialText && next.loadedText != null) {
        _appliedInitialText = true;
        final initialText = next.loadedText!;
        _lastKnownText = initialText;
        _codeController.text = initialText;
        _lastCodeLines = _codeController.value.codeLines;
        _codeController.clearHistory();
        _autosaveTimer?.cancel();

        void updateInitial() {
          if (!mounted) return;
          setState(() {
            _isDirty = false;
            _lineCount = _codeController.lineCount;
            _charCount = initialText.length;
          });
        }

        if (SchedulerBinding.instance.schedulerPhase == SchedulerPhase.persistentCallbacks) {
          WidgetsBinding.instance.addPostFrameCallback((_) => updateInitial());
        } else {
          updateInitial();
        }
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
                icon: Icon(_readOnly ? Icons.edit_rounded : Icons.lock_outline_rounded),
                tooltip: _readOnly
                    ? context.l10n.textEditorSwitchToEditModeTooltip
                    : context.l10n.textEditorSwitchToReadModeTooltip,
                onPressed: _toggleReadOnly,
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
                onPressed: (_isDirty && !_isSaving && !_isAutosaving)
                    ? () => _saveFile()
                    : null,
              ),
            ],
          ],
        ),
        body: _buildBody(cs, Theme.of(context).textTheme, loadState),
        bottomNavigationBar:
            loadState.isLoading || loadState.hasError ? null : _buildBottomBar(cs),
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
                style: textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                loadState.errorMessage,
                textAlign: TextAlign.center,
                style: textTheme.bodyMedium?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
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

    final syntaxStyle = resolveEditorSyntaxStyle(widget.filePath, Theme.of(context).brightness, cs);
    // The accessory key bar only makes sense while the soft keyboard (and
    // therefore touch typing) is actually up -- it tracks the same inset
    // a hardware keyboard never pushes, so it naturally stays out of the
    // way when one is attached instead of needing separate detection.
    final softKeyboardVisible = MediaQuery.of(context).viewInsets.bottom > 0;

    return Column(
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: CodeEditor(
              controller: _codeController,
              focusNode: _focusNode,
              readOnly: _readOnly,
              showCursorWhenReadOnly: true,
              wordWrap: true,
              autofocus: false,
              // Folding isn't exposed yet (no indicator/UI for it in this
              // pass), so skip the analysis pass that would otherwise run
              // on every edit to support it.
              chunkAnalyzer: const NonCodeChunkAnalyzer(),
              style: CodeEditorStyle(
                fontFamily: 'JetBrains Mono',
                fontFamilyFallback: const ['monospace'],
                fontSize: 14,
                fontHeight: 1.5,
                backgroundColor: syntaxStyle.backgroundColor,
                textColor: syntaxStyle.textColor,
                cursorColor: cs.primary,
                cursorLineColor: cs.primary.withValues(alpha: 0.35),
                selectionColor: cs.primary.withValues(alpha: 0.28),
                codeTheme: syntaxStyle.codeTheme,
              ),
              indicatorBuilder: (context, editingController, chunkController, notifier) {
                return DefaultCodeLineNumber(
                  controller: editingController,
                  notifier: notifier,
                  textStyle: TextStyle(
                    color: syntaxStyle.textColor.withValues(alpha: 0.45),
                    fontFamily: 'JetBrains Mono',
                    fontFamilyFallback: const ['monospace'],
                    fontSize: 13,
                  ),
                  focusedTextStyle: TextStyle(
                    color: cs.primary,
                    fontFamily: 'JetBrains Mono',
                    fontFamilyFallback: const ['monospace'],
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                );
              },
            ),
          ),
        ),
        if (!_readOnly && softKeyboardVisible)
          EditorAccessoryKeyBar(controller: _codeController, editorFocusNode: _focusNode),
      ],
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
          if (_readOnly) ...[
            Icon(Icons.lock_outline_rounded, size: 14, color: cs.onSurfaceVariant),
            const SizedBox(width: 4),
            Text(
              context.l10n.textEditorReadOnlyIndicatorLabel,
              style: TextStyle(
                color: cs.onSurfaceVariant,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ] else if (_isAutosaving) ...[
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
          ] else if (_isSaving) ...[
            Text(
              context.l10n.savingLabel,
              style: TextStyle(
                color: cs.primary,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
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
            Icon(
              Icons.check_circle_outline_rounded,
              size: 14,
              color: context.semanticColors.success,
            ),
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
