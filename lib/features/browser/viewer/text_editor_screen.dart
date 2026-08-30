import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/core/theme/app_theme.dart';
import 'package:vaultexplorer/core/widgets/common_widgets.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/features/browser/viewer/text_editor_controller.dart';

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
  final TextEditingController _textController = TextEditingController();
  late final UndoHistoryController _undoController;

  // Genuinely ephemeral UI state -- tied to the TextField's own listener,
  // not domain data. Load/save/error state lives in TextEditorLoad.
  bool _isSaving = false;
  bool _isAutosaving = false;
  bool _isDirty = false;
  int _lineCount = 0;
  int _charCount = 0;
  DateTime? _lastSavedAt;
  bool _appliedInitialText = false;

  Timer? _autosaveTimer;
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _undoController = UndoHistoryController();
    _textController.addListener(_onTextChanged);
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
    _textController.removeListener(_onTextChanged);
    _textController.dispose();
    _undoController.dispose();
    _focusNode.dispose();
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

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final loadState = ref.watch(textEditorLoadProvider(widget.container.volId, widget.filePath));

    ref.listen(textEditorLoadProvider(widget.container.volId, widget.filePath), (previous, next) {
      // Apply loaded text to the TextEditingController exactly once, the
      // moment it goes from null to non-null -- matches the original
      // synchronous `_textController.text = text` inside _loadFile.
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
    return GestureDetector(
      onTap: () {
        if (!_focusNode.hasFocus) {
          _focusNode.requestFocus();
        }
      },
      child: Container(
        color: Colors.transparent,
        height: double.infinity,
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: SingleChildScrollView(
          child: TextField(
            controller: _textController,
            undoController: _undoController,
            focusNode: _focusNode,
            maxLines: null,
            keyboardType: TextInputType.multiline,
            decoration: const InputDecoration(
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              contentPadding: EdgeInsets.zero,
            ),
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 14,
              height: 1.5,
            ),
          ),
        ),
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