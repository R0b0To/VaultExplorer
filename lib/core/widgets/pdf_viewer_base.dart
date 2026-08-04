import 'dart:async';
import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/data/services/vault_engine/vault_explorer_api.dart';

class PdfSearchConfig {
  final String searchMethod;
  final String clearMethod;
  final String findNextMethod;
  final String? findPrevMethod;
  final Duration debounceDuration;

  const PdfSearchConfig({
    this.searchMethod = 'search',
    this.clearMethod = 'clearSearch',
    this.findNextMethod = 'findNext',
    this.findPrevMethod = 'findPrevious',
    this.debounceDuration = const Duration(milliseconds: 300),
  });

  const PdfSearchConfig.decoy()
      : searchMethod = 'findInPage',
        clearMethod = 'clearMatches',
        findNextMethod = 'findNext',
        findPrevMethod = null,
        debounceDuration = Duration.zero;
}

class PdfViewerBase extends StatefulWidget {
  final MountedContainer? container;
  final String? pdfPath;
  final String? localUri;
  final Map<String, dynamic>? creationParams;
  final String title;
  final bool isLocked;
  final Widget Function(Widget child)? titleBuilder;
  final Widget Function(Widget child)? pageCounterBuilder;
  final List<Widget> Function(PdfViewerController? controller)? extraActionsBuilder;
  final PdfSearchConfig searchConfig;

  const PdfViewerBase({
    super.key,
    this.container,
    this.pdfPath,
    this.localUri,
    this.creationParams,
    required this.title,
    this.isLocked = false,
    this.titleBuilder,
    this.pageCounterBuilder,
    this.extraActionsBuilder,
    this.searchConfig = const PdfSearchConfig(),
  });

  @override
  State<PdfViewerBase> createState() => _PdfViewerBaseState();
}

class _PdfViewerBaseState extends State<PdfViewerBase> {
  late final PdfViewerController _controller = PdfViewerController();
  PdfTextSearcher? _textSearcher;

  bool _isLoading = true;
  bool _hasError = false;
  String _errorMessage = '';
  int _currentPage = 1;
  int _pageCount = 0;
  int? _vaultFileSize;

  bool _isSearching = false;
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  Timer? _searchDebounce;
  int _searchCurrent = 0;
  int _searchTotal = 0;

  MountedContainer? _effectiveContainer;
  String? _effectivePdfPath;
  String? _effectiveLocalUri;

  @override
  void initState() {
    super.initState();
    _resolveSource();
  }

  void _resolveSource() {
    _effectiveContainer = widget.container;
    _effectivePdfPath = widget.pdfPath;
    _effectiveLocalUri = widget.localUri;

    if (_effectiveContainer == null &&
        _effectivePdfPath == null &&
        _effectiveLocalUri == null &&
        widget.creationParams != null) {
      _effectiveLocalUri = widget.creationParams!['localUri'] as String?;
      _effectivePdfPath = widget.creationParams!['pdfPath'] as String?;
    }

    if (_effectiveContainer != null && _effectivePdfPath != null) {
      _fetchVaultFileSize();
    } else if (_effectiveLocalUri != null && _effectiveLocalUri!.isNotEmpty) {
      setState(() {
        _isLoading = false;
      });
    } else {
      setState(() {
        _isLoading = false;
        _hasError = true;
        _errorMessage = 'No PDF source provided.';
      });
    }
  }

  Future<void> _fetchVaultFileSize() async {
    try {
      final size = await vaultExplorerApi.getFileSize(
        _effectiveContainer!,
        _effectivePdfPath!,
      );
      if (!mounted) return;
      if (size <= 0) {
        setState(() {
          _isLoading = false;
          _hasError = true;
          _errorMessage = 'PDF file is empty or unreadable.';
        });
        return;
      }
      setState(() {
        _vaultFileSize = size;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _hasError = true;
        _errorMessage = 'Failed to inspect PDF file size: $e';
      });
    }
  }

  void _onSearchUpdated() {
    if (!mounted) return;
    setState(() {
      _searchTotal = _textSearcher?.matches.length ?? 0;
      final idx = _textSearcher?.currentIndex;
      _searchCurrent = (idx != null && _searchTotal > 0) ? idx + 1 : 0;
    });
  }

  void _onSearchChanged(String query) {
    _searchDebounce?.cancel();
    final cfg = widget.searchConfig;
    void executeSearch() {
      final trimmed = query.trim();
      if (trimmed.isEmpty) {
        _textSearcher?.resetTextSearch();
        if (mounted) {
          setState(() {
            _searchCurrent = 0;
            _searchTotal = 0;
          });
        }
      } else {
        _textSearcher?.startTextSearch(trimmed, caseInsensitive: true);
      }
    }

    if (cfg.debounceDuration > Duration.zero) {
      _searchDebounce = Timer(cfg.debounceDuration, executeSearch);
    } else {
      executeSearch();
    }
  }

  void _startSearch() {
    setState(() => _isSearching = true);
    _searchFocusNode.requestFocus();
  }

  void _stopSearch() {
    _searchDebounce?.cancel();
    _searchController.clear();
    _textSearcher?.resetTextSearch();
    setState(() {
      _isSearching = false;
      _searchCurrent = 0;
      _searchTotal = 0;
    });
  }

  void _findNext() {
    _textSearcher?.goToNextMatch();
  }

  void _findPrevious() {
    _textSearcher?.goToPrevMatch();
  }

  Future<void> _showGoToPageDialog() async {
    if (_pageCount <= 0) return;
    final targetPageStr = await showDialog<String>(
      context: context,
      builder: (dialogCtx) => _GoToPageDialog(
        currentPage: _currentPage,
        pageCount: _pageCount,
      ),
    );
    if (targetPageStr == null || targetPageStr.trim().isEmpty) return;
    final targetPage = int.tryParse(targetPageStr.trim());
    if (targetPage != null && targetPage >= 1 && targetPage <= _pageCount) {
      if (_controller.isReady) {
        await _controller.goToPage(pageNumber: targetPage);
      }
    }
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    _searchFocusNode.dispose();
    _textSearcher?.removeListener(_onSearchUpdated);
    _textSearcher?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isLocked) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: SizedBox.expand(),
      );
    }
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: _isSearching ? _buildSearchField(cs) : _buildTitle(),
        leading: _isSearching
            ? IconButton(
                icon: const Icon(Icons.arrow_back_rounded),
                onPressed: _stopSearch,
              )
            : null,
        actions:
            _isSearching ? _buildSearchActions(cs) : _buildNormalActions(cs),
      ),
      body: _buildBody(cs),
    );
  }

  Widget _buildTitle() {
    final title = Text(widget.title, overflow: TextOverflow.ellipsis);
    return widget.titleBuilder?.call(title) ?? title;
  }

  Widget _buildSearchField(ColorScheme cs) {
    return TextField(
      controller: _searchController,
      focusNode: _searchFocusNode,
      autofocus: true,
      textInputAction: TextInputAction.search,
      style: TextStyle(color: cs.onSurface),
      decoration: const InputDecoration(
        hintText: 'Search in document',
        border: InputBorder.none,
      ),
      onChanged: _onSearchChanged,
      onSubmitted: (_) => _findNext(),
    );
  }

  List<Widget> _buildSearchActions(ColorScheme cs) {
    return [
      if (_searchController.text.isNotEmpty)
        Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              _searchTotal > 0
                  ? '$_searchCurrent / $_searchTotal'
                  : 'No matches',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
            ),
          ),
        ),
      IconButton(
        icon: const Icon(Icons.keyboard_arrow_up_rounded),
        tooltip: 'Previous match',
        onPressed: _searchTotal > 0 ? _findPrevious : null,
      ),
      IconButton(
        icon: const Icon(Icons.keyboard_arrow_down_rounded),
        tooltip: 'Next match',
        onPressed: _searchTotal > 0 ? _findNext : null,
      ),
      IconButton(
        icon: const Icon(Icons.close_rounded),
        tooltip: 'Close search',
        onPressed: _stopSearch,
      ),
    ];
  }

  List<Widget> _buildNormalActions(ColorScheme cs) {
    return [
      if (_pageCount > 0) ...[
        _buildPageCounter(cs),
        IconButton(
          icon: const Icon(Icons.search_rounded),
          tooltip: 'Search',
          onPressed: _startSearch,
        ),
        ...?widget.extraActionsBuilder?.call(_controller),
      ],
    ];
  }

  Widget _buildPageCounter(ColorScheme cs) {
    final counter = InkWell(
      onTap: _showGoToPageDialog,
      borderRadius: BorderRadius.circular(16),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Text(
            '$_currentPage / $_pageCount',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
          ),
        ),
      ),
    );
    return widget.pageCounterBuilder?.call(counter) ?? counter;
  }

  Widget _buildBody(ColorScheme cs) {
    if (_hasError) {
      return Container(
        color: cs.surface,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.error_outline_rounded,
                    color: cs.error, size: 48),
                const SizedBox(height: 16),
                Text(
                  'Cannot open PDF',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold),
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
        ),
      );
    }

    if (_isLoading) {
      return Container(
        color: cs.surface,
        child: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(strokeWidth: 2.5),
              SizedBox(height: 16),
              Text('Loading document…'),
            ],
          ),
        ),
      );
    }

    final params = PdfViewerParams(
      pagePaintCallbacks: [
        (canvas, pageRect, page) {
          _textSearcher?.pageTextMatchPaintCallback(canvas, pageRect, page);
        }
      ],
      onViewerReady: (document, controller) {
        if (mounted) {
          _textSearcher ??= PdfTextSearcher(controller)..addListener(_onSearchUpdated);
          setState(() {
            _isLoading = false;
            _hasError = false;
            _pageCount = document.pages.length;
            _currentPage = controller.pageNumber ?? 1;
          });
        }
      },
      onPageChanged: (pageNumber) {
        if (mounted && pageNumber != null) {
          setState(() => _currentPage = pageNumber);
        }
      },
      errorBannerBuilder: (context, error, stackTrace, documentRef) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.error_outline_rounded,
                    color: cs.error, size: 48),
                const SizedBox(height: 16),
                Text(
                  'Error loading PDF',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  error.toString(),
                  textAlign: TextAlign.center,
                  style: TextStyle(color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (_effectiveContainer != null && _effectivePdfPath != null && _vaultFileSize != null) {
      return PdfViewer.custom(
        fileSize: _vaultFileSize!,
        read: (buffer, position, size) async {
          final chunk = await vaultExplorerApi.readFileChunk(
            _effectiveContainer!,
            _effectivePdfPath!,
            position,
            size,
          );
          if (chunk == null || chunk.isEmpty) return 0;
          buffer.setRange(0, chunk.length, chunk);
          return chunk.length;
        },
        sourceName: _effectivePdfPath!,
        controller: _controller,
        params: params,
      );
    }

    if (_effectiveLocalUri != null && _effectiveLocalUri!.isNotEmpty) {
      final uri = Uri.parse(_effectiveLocalUri!);
      final isSchemeFile = uri.scheme == 'file' || uri.scheme.isEmpty;
      if (isSchemeFile) {
        return PdfViewer.file(
          uri.path,
          controller: _controller,
          params: params,
        );
      } else {
        return PdfViewer.uri(
          uri,
          controller: _controller,
          params: params,
        );
      }
    }

    return Container(
      color: cs.surface,
      child: const Center(child: Text('No PDF document loaded.')),
    );
  }
}

class _GoToPageDialog extends StatefulWidget {
  final int currentPage;
  final int pageCount;

  const _GoToPageDialog({
    required this.currentPage,
    required this.pageCount,
  });

  @override
  State<_GoToPageDialog> createState() => _GoToPageDialogState();
}

class _GoToPageDialogState extends State<_GoToPageDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.currentPage.toString());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    Navigator.of(context).pop(_controller.text);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Go to page'),
      content: TextField(
        controller: _controller,
        keyboardType: TextInputType.number,
        autofocus: true,
        decoration: InputDecoration(
          hintText: 'Page number (1 - ${widget.pageCount})',
          labelText: 'Page',
        ),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: _submit,
          child: const Text('Go'),
        ),
      ],
    );
  }
}