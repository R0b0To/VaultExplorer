import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/data/services/vault_engine/vault_explorer_api.dart';

/// Must match PDF_VIEWER_VIEW_TYPE in
/// kotlin/.../pdfviewer/PdfViewerPlugin.kt
const String _kPdfViewerViewType = 'com.aeidolon.vaultexplorer/pdf_viewer';

/// In-app viewer for `.pdf` files stored in the vault.
///
/// Renders the PDF using Mozilla pdf.js inside a security-hardened WebView
/// (no network, no file access, vault bytes streamed in-process).
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
  MethodChannel? _method;
  StreamSubscription<dynamic>? _eventSub;

  bool _isLoading = true;
  bool _hasError = false;
  String _errorMessage = '';
  int _currentPage = 1;
  int _pageCount = 0;
  bool _isContainerLocked = false;

  bool _isSearching = false;
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  Timer? _searchDebounce;
  int _searchCurrent = 0;
  int _searchTotal = 0;

  String get _fileName => widget.filePath.split('/').last;

  void _onContainerLockedEvent(int volId) {
    if (volId == widget.container.volId && mounted) {
      setState(() => _isContainerLocked = true);
    }
  }

  @override
  void initState() {
    super.initState();
    VaultExplorerApi.addContainerLockedListener(_onContainerLockedEvent);
  }

  void _onPlatformViewCreated(int id) {
    final method = MethodChannel('$_kPdfViewerViewType/$id');
    final events = EventChannel('$_kPdfViewerViewType/events/$id');
    _eventSub =
        events.receiveBroadcastStream().listen(_onEvent, onError: (_) {});
    setState(() => _method = method);
  }

  void _onEvent(dynamic raw) {
    if (raw is! Map) return;
    if (!mounted) return;
    switch (raw['event']) {
      case 'documentLoaded':
        setState(() {
          _isLoading = false;
          _hasError = false;
          _pageCount = (raw['pageCount'] as int?) ?? 0;
        });
      case 'pageChanged':
        setState(() {
          _currentPage = (raw['page'] as int?) ?? 1;
        });
      case 'error':
        setState(() {
          _isLoading = false;
          _hasError = true;
          _errorMessage =
              (raw['message'] as String?) ?? 'Failed to load PDF';
        });
      case 'searchResult':
        setState(() {
          _searchCurrent = (raw['current'] as int?) ?? 0;
          _searchTotal = (raw['total'] as int?) ?? 0;
        });
    }
  }

  void _onSearchChanged(String query) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 300), () {
      _method?.invokeMethod('search', {'query': query});
    });
  }

  void _startSearch() {
    setState(() => _isSearching = true);
    _searchFocusNode.requestFocus();
  }

  void _stopSearch() {
    _searchDebounce?.cancel();
    _searchController.clear();
    _method?.invokeMethod('clearSearch');
    setState(() {
      _isSearching = false;
      _searchCurrent = 0;
      _searchTotal = 0;
    });
  }

  @override
  void dispose() {
    VaultExplorerApi.removeContainerLockedListener(_onContainerLockedEvent);
    _eventSub?.cancel();
    _searchDebounce?.cancel();
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isContainerLocked) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: SizedBox.expand(),
      );
    }
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: _isSearching
            ? TextField(
                controller: _searchController,
                focusNode: _searchFocusNode,
                autofocus: true,
                textInputAction: TextInputAction.search,
                decoration: const InputDecoration(
                  hintText: 'Search in document',
                  border: InputBorder.none,
                ),
                onChanged: _onSearchChanged,
                onSubmitted: (_) => _method?.invokeMethod('findNext'),
              )
            : Text(_fileName),
        leading: _isSearching
            ? IconButton(
                icon: const Icon(Icons.arrow_back_rounded),
                onPressed: _stopSearch,
              )
            : null,
        actions: _isSearching
            ? [
                if (_searchTotal > 0)
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Text(
                        '$_searchCurrent / $_searchTotal',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                      ),
                    ),
                  ),
                IconButton(
                  icon: const Icon(Icons.keyboard_arrow_up_rounded),
                  tooltip: 'Previous match',
                  onPressed: _searchTotal > 0
                      ? () => _method?.invokeMethod('findPrevious')
                      : null,
                ),
                IconButton(
                  icon: const Icon(Icons.keyboard_arrow_down_rounded),
                  tooltip: 'Next match',
                  onPressed: _searchTotal > 0
                      ? () => _method?.invokeMethod('findNext')
                      : null,
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  tooltip: 'Close search',
                  onPressed: _stopSearch,
                ),
              ]
            : [
                IconButton(
                  icon: const Icon(Icons.search_rounded),
                  tooltip: 'Search',
                  onPressed: _pageCount > 0 ? _startSearch : null,
                ),
                if (_pageCount > 0)
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Text(
                        '$_currentPage / $_pageCount',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                      ),
                    ),
                  ),
              ],
      ),
      body: _buildBody(cs),
    );
  }

  Widget _buildBody(ColorScheme cs) {
    return Stack(
      children: [
        Positioned.fill(
          child: AndroidView(
            viewType: _kPdfViewerViewType,
            creationParams: {
              'volId': widget.container.volId,
              'pdfPath': widget.filePath,
            },
            creationParamsCodec: const StandardMessageCodec(),
            onPlatformViewCreated: _onPlatformViewCreated,
          ),
        ),
        if (_isLoading)
          Container(
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
          ),
        if (_hasError)
          Container(
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
          ),
      ],
    );
  }
}