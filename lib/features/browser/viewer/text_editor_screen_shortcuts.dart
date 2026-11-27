part of 'text_editor_screen.dart';

/// The keyboard shortcut handlers and the link, comment and read-only toggles.
///
/// Moved out of [_TextEditorScreenState] as is: an extension in the
/// same library reads and writes the state's private fields exactly as the
/// class did.
extension _TextEditorShortcuts on _TextEditorScreenState {
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
}
