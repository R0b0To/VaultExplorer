import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart' as sfpdf;
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/data/services/vault_engine/vault_explorer_api.dart';
import 'package:vaultexplorer/core/widgets/common_widgets.dart';

/// Which annotation tool (if any) is currently active while in edit mode.
/// Only [note] needs a persistent "armed" state (tap-to-place); the markup
/// tools act immediately on whatever text is currently selected.
enum _PdfTool { none, note }

/// In-app viewer/editor for PDF files stored in a vault.
///
/// Mirrors [TextEditorScreen]'s decrypt-to-temp / edit / write-back pattern:
/// the encrypted file is decrypted into a scratch temp file, viewed and
/// annotated there via Syncfusion's PDF viewer, and only written back into
/// the vault when the user saves. Page rotate/delete go through the
/// standalone `syncfusion_flutter_pdf` document engine, since those aren't
/// exposed by the viewer's annotation API.
class PdfViewerScreen extends StatefulWidget {
  final MountedContainer container;
  final String filePath;

  const PdfViewerScreen({
    super.key,
    required this.container,
    required this.filePath,
  });

  @override
  State<PdfViewerScreen> createState() => _PdfViewerScreenState();
}

class _PdfViewerScreenState extends State<PdfViewerScreen> {
  final PdfViewerController _controller = PdfViewerController();
  final GlobalKey<SfPdfViewerState> _viewerKey = GlobalKey();

  File? _tempFile;
  int _reloadToken = 0;

  bool _isLoading = true;
  bool _isSaving = false;
  bool _isDirty = false;
  bool _hasError = false;
  bool _isContainerLocked = false;
  String _errorMessage = '';

  bool _isEditMode = false;
  _PdfTool _activeTool = _PdfTool.none;
  bool _hasTextSelection = false;

  // Simple in-session undo/redo over annotations added via the toolbar.
  final List<Annotation> _undoStack = [];
  final List<Annotation> _redoStack = [];

  bool get _isReadOnly => widget.container.readOnly;

  void _onContainerLockedEvent(int volId) {
    if (volId == widget.container.volId && mounted) {
      setState(() => _isContainerLocked = true);
    }
  }


  @override
  void initState() {
    super.initState();
    VaultExplorerApi.addContainerLockedListener(_onContainerLockedEvent);
    _loadFile();
  }

  @override
  void dispose() {
    VaultExplorerApi.removeContainerLockedListener(_onContainerLockedEvent);
    _cleanTempFile();
    super.dispose();
  }

  Future<void> _cleanTempFile() async {
    if (_tempFile != null && await _tempFile!.exists()) {
      try {
        await _tempFile!.delete();
      } catch (e) {
        debugPrint('Error deleting temp PDF file: $e');
      }
    }
  }

  Future<void> _loadFile() async {
    setState(() {
      _isLoading = true;
      _hasError = false;
      _errorMessage = '';
    });

    try {
      final tempDir = await getTemporaryDirectory();
      _tempFile = File(
        '${tempDir.path}/vx_pdf_${DateTime.now().microsecondsSinceEpoch}.pdf',
      );

      final ok = await vaultExplorerApi.decryptFile(
        widget.container,
        widget.filePath,
        _tempFile!.path,
      );

      if (!ok) {
        throw Exception('Failed to decrypt file from vault.');
      }

      setState(() {
        _isLoading = false;
        _isDirty = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _hasError = true;
        _errorMessage = e.toString();
      });
    }
  }

  /// Bakes any pending viewer annotations into the on-disk temp file so
  /// subsequent page-level edits (via the standalone [sfpdf.PdfDocument]
  /// engine) and the final vault write-back both see the latest state.
  Future<void> _flushAnnotationsToTempFile() async {
    if (_tempFile == null) return;
    final bytes = await _controller.saveDocument();
    await _tempFile!.writeAsBytes(bytes, flush: true);
  }

  Future<bool> _saveFile() async {
    if (_tempFile == null) return false;
    setState(() => _isSaving = true);

    try {
      await _flushAnnotationsToTempFile();

      final ok = await vaultExplorerApi.writeBackFile(
        widget.container,
        widget.filePath,
        _tempFile!.path,
      );

      if (!ok) {
        throw Exception('Failed to write file back to vault.');
      }

      setState(() {
        _isSaving = false;
        _isDirty = false;
      });

      if (mounted) {
        showAppSnackBar(
          context,
          message: 'Changes saved successfully',
          tone: AppBannerTone.success,
        );
      }
      return true;
    } catch (e) {
      setState(() => _isSaving = false);
      if (mounted) {
        showAppSnackBar(
          context,
          message: 'Save failed: $e',
          tone: AppBannerTone.error,
        );
      }
      return false;
    }
  }

  Future<bool> _onWillPop() async {
    if (!_isDirty) return true;

    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Unsaved Changes'),
        content: const Text(
          'You have unsaved edits to this PDF. Would you like to save before closing?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop('discard'),
            child: Text(
              'Discard',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop('cancel'),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop('save'),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (result == 'save') return _saveFile();
    if (result == 'discard') return true;
    return false;
  }

  // ── Text-markup annotations (highlight / underline / strikethrough) ──────

  void _onTextSelectionChanged(PdfTextSelectionChangedDetails details) {
    final hasSelection = details.selectedText != null;
    if (hasSelection != _hasTextSelection) {
      setState(() => _hasTextSelection = hasSelection);
    }
  }

  void _applyMarkup(String kind) {
    final textLines = _viewerKey.currentState?.getSelectedTextLines();
    if (textLines == null || textLines.isEmpty) return;

    final Annotation annotation = switch (kind) {
      'underline' => UnderlineAnnotation(textBoundsCollection: textLines),
      'strikethrough' => StrikethroughAnnotation(textBoundsCollection: textLines),
      _ => HighlightAnnotation(textBoundsCollection: textLines),
    };

    _controller.addAnnotation(annotation);
    _controller.clearSelection();
    _undoStack.add(annotation);
    _redoStack.clear();
    setState(() {
      _isDirty = true;
      _hasTextSelection = false;
    });
  }

  void _onTap(PdfGestureDetails details) {
    if (!_isEditMode || _activeTool != _PdfTool.note) return;

    final note = StickyNoteAnnotation(
      pageNumber: details.pageNumber,
      position: details.pagePosition,
      icon: PdfStickyNoteIcon.comment,
      text: 'Note',
    );
    _controller.addAnnotation(note);
    _undoStack.add(note);
    _redoStack.clear();
    setState(() => _isDirty = true);
  }

  void _undo() {
    if (_undoStack.isEmpty) return;
    final annotation = _undoStack.removeLast();
    _controller.removeAnnotation(annotation);
    _redoStack.add(annotation);
    setState(() => _isDirty = true);
  }

  void _redo() {
    if (_redoStack.isEmpty) return;
    final annotation = _redoStack.removeLast();
    _controller.addAnnotation(annotation);
    _undoStack.add(annotation);
    setState(() => _isDirty = true);
  }

  // ── Page management (rotate / delete current page) ───────────────────────

  Future<void> _rotateCurrentPage() async {
    await _mutatePages((doc, pageIndex) {
      doc.pages[pageIndex].rotation = switch (doc.pages[pageIndex].rotation) {
        sfpdf.PdfPageRotateAngle.rotateAngle0 => sfpdf.PdfPageRotateAngle.rotateAngle90,
        sfpdf.PdfPageRotateAngle.rotateAngle90 => sfpdf.PdfPageRotateAngle.rotateAngle180,
        sfpdf.PdfPageRotateAngle.rotateAngle180 => sfpdf.PdfPageRotateAngle.rotateAngle270,
        sfpdf.PdfPageRotateAngle.rotateAngle270 => sfpdf.PdfPageRotateAngle.rotateAngle0,
      };
    });
  }

  Future<void> _deleteCurrentPage() async {
    if (_controller.pageCount <= 1) {
      showAppSnackBar(
        context,
        message: 'Cannot delete the only page in this document',
        tone: AppBannerTone.error,
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Page'),
        content: Text('Remove page ${_controller.pageNumber}? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await _mutatePages((doc, pageIndex) {
      doc.pages.removeAt(pageIndex);
    });
  }

  /// Flushes pending viewer annotations, applies [mutate] to the current
  /// page via the standalone PDF document engine, writes the result back to
  /// the temp file, then forces the viewer to reload it.
  Future<void> _mutatePages(
    void Function(sfpdf.PdfDocument doc, int pageIndex) mutate,
  ) async {
    if (_tempFile == null) return;
    setState(() => _isSaving = true);
    try {
      await _flushAnnotationsToTempFile();

      final bytes = await _tempFile!.readAsBytes();
      final doc = sfpdf.PdfDocument(inputBytes: bytes);
      final pageIndex = _controller.pageNumber - 1;
      mutate(doc, pageIndex);
      final List<int> newBytes = await doc.save();
      doc.dispose();

      final tempDir = await getTemporaryDirectory();
      final newTempFile = File(
        '${tempDir.path}/vx_pdf_${DateTime.now().microsecondsSinceEpoch}_${++_reloadToken}.pdf',
      );
      await newTempFile.writeAsBytes(newBytes, flush: true);

      final oldTempFile = _tempFile;
      _tempFile = newTempFile;
      _undoStack.clear();
      _redoStack.clear();
      if (oldTempFile != null && await oldTempFile.exists()) {
        try {
          await oldTempFile.delete();
        } catch (e) {
          debugPrint('Error deleting stale temp PDF file: $e');
        }
      }

      setState(() {
        _isDirty = true;
        _isSaving = false;
      });
    } catch (e) {
      setState(() => _isSaving = false);
      if (mounted) {
        showAppSnackBar(context, message: 'Edit failed: $e', tone: AppBannerTone.error);
      }
    }
  }

  String get _fileName => widget.filePath.split('/').last;

  @override
  Widget build(BuildContext context) {
    if (_isContainerLocked) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: SizedBox.expand(),
      );
    }

    final cs = Theme.of(context).colorScheme;

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
            if (!_isLoading && !_hasError) ...[
              if (!_isReadOnly)
                IconButton(
                  icon: Icon(
                    _isEditMode ? Icons.edit_rounded : Icons.edit_outlined,
                    color: _isEditMode ? cs.primary : null,
                  ),
                  tooltip: _isEditMode ? 'Exit edit mode' : 'Edit PDF',
                  onPressed: () => setState(() {
                    _isEditMode = !_isEditMode;
                    if (!_isEditMode) _activeTool = _PdfTool.none;
                  }),
                ),
              if (!_isReadOnly)
                IconButton(
                  icon: _isSaving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(
                          Icons.save_rounded,
                          color: _isDirty ? cs.primary : cs.outline,
                        ),
                  tooltip: 'Save changes',
                  onPressed: (_isDirty && !_isSaving) ? _saveFile : null,
                ),
              IconButton(
                icon: const Icon(Icons.share_outlined),
                tooltip: 'Open in another app',
                onPressed: () async {
                  await vaultExplorerApi.openWithApp(
                    widget.container,
                    widget.filePath,
                    mimeType: 'application/pdf',
                  );
                },
              ),
            ],
          ],
        ),
        body: _buildBody(cs),
        bottomNavigationBar: (!_isLoading && !_hasError && _isEditMode && !_isReadOnly)
            ? _buildEditToolbar(cs)
            : null,
      ),
    );
  }

  Widget _buildBody(ColorScheme cs) {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(strokeWidth: 2.5),
            SizedBox(height: 16),
            Text('Decrypting document...'),
          ],
        ),
      );
    }

    if (_hasError) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline_rounded, color: cs.error, size: 48),
              const SizedBox(height: 16),
              Text(
                'Cannot open file',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 8),
              Text(
                _errorMessage,
                textAlign: TextAlign.center,
                style: TextStyle(color: cs.onSurfaceVariant),
              ),
              const SizedBox(height: 24),
              OutlinedButton.icon(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.arrow_back_rounded),
                label: const Text('Go back'),
              ),
            ],
          ),
        ),
      );
    }

    return Stack(
      children: [
        SfPdfViewer.file(
          _tempFile!,
          key: _viewerKey,
          controller: _controller,
          canShowScrollHead: true,
          canShowScrollStatus: true,
          enableTextSelection: true,
          onTextSelectionChanged: _onTextSelectionChanged,
          onTap: _onTap,
        ),
        if (_isSaving)
          Container(
            color: Colors.black26,
            child: const Center(child: CircularProgressIndicator()),
          ),
      ],
    );
  }

  Widget _buildEditToolbar(ColorScheme cs) {
    Widget markupButton(String kind, IconData icon, String label) {
      return IconButton(
        icon: Icon(icon, color: _hasTextSelection ? cs.primary : cs.onSurfaceVariant),
        tooltip: label,
        onPressed: _hasTextSelection ? () => _applyMarkup(kind) : null,
      );
    }

    final noteActive = _activeTool == _PdfTool.note;

    return SafeArea(
      child: Container(
        decoration: BoxDecoration(
          color: cs.surfaceContainerLow,
          border: Border(top: BorderSide(color: cs.outlineVariant, width: 0.5)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            markupButton('highlight', Icons.border_color_rounded, 'Highlight selected text'),
            markupButton('underline', Icons.format_underlined_rounded, 'Underline selected text'),
            markupButton('strikethrough', Icons.strikethrough_s_rounded, 'Strikethrough selected text'),
            IconButton(
              icon: Icon(
                Icons.sticky_note_2_outlined,
                color: noteActive ? cs.primary : cs.onSurfaceVariant,
              ),
              tooltip: noteActive ? 'Cancel sticky note' : 'Tap a page to add a sticky note',
              onPressed: () => setState(() {
                _activeTool = noteActive ? _PdfTool.none : _PdfTool.note;
              }),
            ),
            IconButton(
              icon: const Icon(Icons.undo_rounded),
              tooltip: 'Undo last annotation',
              onPressed: _undoStack.isEmpty ? null : _undo,
            ),
            IconButton(
              icon: const Icon(Icons.redo_rounded),
              tooltip: 'Redo',
              onPressed: _redoStack.isEmpty ? null : _redo,
            ),
            IconButton(
              icon: const Icon(Icons.rotate_right_rounded),
              tooltip: 'Rotate page',
              onPressed: _rotateCurrentPage,
            ),
            IconButton(
              icon: Icon(Icons.delete_outline_rounded, color: cs.error),
              tooltip: 'Delete page',
              onPressed: _deleteCurrentPage,
            ),
          ],
        ),
      ),
    );
  }
}
