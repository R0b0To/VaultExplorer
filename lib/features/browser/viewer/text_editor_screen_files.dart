part of 'text_editor_screen.dart';

/// Choosing the encoding and saving a tab back to its file.
///
/// Moved out of [_TextEditorScreenState] as is: an extension in the
/// same library reads and writes the state's private fields exactly as the
/// class did.
extension _TextEditorFiles on _TextEditorScreenState {
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
}
