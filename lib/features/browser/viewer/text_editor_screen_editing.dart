part of 'text_editor_screen.dart';

/// Markdown and image helpers, go-to-line, revert, format and file-type checks.
///
/// Moved out of [_TextEditorScreenState] as is: an extension in the
/// same library reads and writes the state's private fields exactly as the
/// class did.
extension _TextEditorEditing on _TextEditorScreenState {
  Future<void> _insertImageTemplate() async {
    final currentTab = _activeTab;
    final selectedImagePath = await showMarkdownImagePicker(
      context: context,
      container: widget.container,
      markdownFilePath: currentTab.filePath,
    );

    if (!mounted || selectedImagePath == null) return;

    final selectedImage = selectedImagePath.split('/').last;
    final relativePath = relativeMarkdownImagePath(
      currentTab.filePath,
      selectedImagePath,
    );
    final template = markdownImageTemplate(
      alt: selectedImage,
      path: relativePath,
    );
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

  String? Function(String)? get _formatter => formatterFor(_activeTab.filePath);

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

  bool _isImageFile(String fileName) {
    final dot = fileName.lastIndexOf('.');
    if (dot < 0) return false;
    return _TextEditorScreenState._imageExtensions.contains(
      fileName.substring(dot + 1).toLowerCase(),
    );
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
                final currentTab = _activeTab;
                final relativePath = relativeMarkdownImagePath(
                  currentTab.filePath,
                  fullPath,
                );
                Navigator.of(ctx).pop();
                final template = markdownImageTemplate(
                  alt: fileName,
                  path: relativePath,
                );
                currentTab.codeController.replaceSelection(template);
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

  bool _isUnsupportedBinaryFile(String fileName) {
    final dot = fileName.lastIndexOf('.');
    if (dot < 0) return false;
    return _TextEditorScreenState._unsupportedBinaryExtensions.contains(
      fileName.substring(dot + 1).toLowerCase(),
    );
  }
}
