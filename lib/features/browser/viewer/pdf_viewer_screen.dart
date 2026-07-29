import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:vaultexplorer/core/widgets/common_widgets.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/data/services/vault_engine/vault_explorer_api.dart';

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
  File? _tempFile;
  int _reloadToken = 0;
  bool _isLoading = true;
  bool _isSaving = false;
  bool _isDirty = false;
  bool _hasError = false;
  bool _isContainerLocked = false;
  String _errorMessage = '';
  bool _isEditMode = false;

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

  Future<bool> _saveFile() async {
    if (_tempFile == null) return false;
    setState(() => _isSaving = true);
    try {
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

  Future<void> _rotateCurrentPage() async {
    await _mutatePages((doc, pageIndex) {
      final pages = List<PdfPage>.from(doc.pages);
      if (pageIndex >= 0 && pageIndex < pages.length) {
        pages[pageIndex] = pages[pageIndex].rotatedCW90();
        doc.pages = pages;
      }
    });
  }

  Future<void> _deleteCurrentPage() async {
    final pageCount = _controller.pageCount;
    final currentPage = _controller.pageNumber ?? 1;
    if (pageCount <= 1) {
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
        content: Text('Remove page $currentPage? This cannot be undone.'),
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
      final pages = List<PdfPage>.from(doc.pages);
      if (pageIndex >= 0 && pageIndex < pages.length) {
        pages.removeAt(pageIndex);
        doc.pages = pages;
      }
    });
  }

  Future<void> _mutatePages(
    void Function(PdfDocument doc, int pageIndex) mutate,
  ) async {
    if (_tempFile == null) return;
    setState(() => _isSaving = true);
    try {
      final doc = await PdfDocument.openFile(_tempFile!.path);
      final currentPageNumber = _controller.pageNumber ?? 1;
      final pageIndex = (currentPageNumber - 1).clamp(0, doc.pages.length - 1);
      mutate(doc, pageIndex);
      final List<int> newBytes = await doc.encodePdf();
      doc.dispose();

      final tempDir = await getTemporaryDirectory();
      final newTempFile = File(
        '${tempDir.path}/vx_pdf_${DateTime.now().microsecondsSinceEpoch}_${++_reloadToken}.pdf',
      );
      await newTempFile.writeAsBytes(newBytes, flush: true);
      final oldTempFile = _tempFile;
      _tempFile = newTempFile;

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
        showAppSnackBar(
          context,
          message: 'Edit failed: $e',
          tone: AppBannerTone.error,
        );
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
        bottomNavigationBar:
            (!_isLoading && !_hasError && _isEditMode && !_isReadOnly)
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
        PdfViewer.file(
          _tempFile!.path,
          key: ValueKey(_reloadToken),
          controller: _controller,
          params: const PdfViewerParams(
            textSelectionParams: PdfTextSelectionParams(
              enabled: true,
            ),
          ),
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
    return SafeArea(
      child: Container(
        decoration: BoxDecoration(
          color: cs.surfaceContainerLow,
          border: Border(top: BorderSide(color: cs.outlineVariant, width: 0.5)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            TextButton.icon(
              icon: const Icon(Icons.rotate_right_rounded),
              label: const Text('Rotate Page'),
              onPressed: _rotateCurrentPage,
            ),
            TextButton.icon(
              icon: Icon(Icons.delete_outline_rounded, color: cs.error),
              label: Text('Delete Page', style: TextStyle(color: cs.error)),
              onPressed: _deleteCurrentPage,
            ),
          ],
        ),
      ),
    );
  }
}