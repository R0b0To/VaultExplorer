import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

const String _kPdfViewerViewType = 'com.aeidolon.vaultexplorer/pdf_viewer';

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
  final Map<String, dynamic> creationParams;
  final String title;
  final bool isLocked;
  final Widget Function(Widget child)? titleBuilder;
  final Widget Function(Widget child)? pageCounterBuilder;
  final List<Widget> Function(MethodChannel? method)? extraActionsBuilder;
  final PdfSearchConfig searchConfig;

  const PdfViewerBase({
    super.key,
    required this.creationParams,
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
  MethodChannel? _method;
  StreamSubscription<dynamic>? _eventSub;

  bool _isLoading = true;
  bool _hasError = false;
  String _errorMessage = '';
  int _currentPage = 1;
  int _pageCount = 0;

  bool _isSearching = false;
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  Timer? _searchDebounce;
  int _searchCurrent = 0;
  int _searchTotal = 0;

  void _onPlatformViewCreated(int id) {
    if (!mounted) return;
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
        break;
      case 'pageChanged':
        setState(() {
          _currentPage = (raw['page'] as int?) ?? 1;
        });
        break;
      case 'error':
        setState(() {
          _isLoading = false;
          _hasError = true;
          _errorMessage =
              (raw['message'] as String?) ?? 'Failed to load PDF';
        });
        break;
      case 'findResult':
      case 'searchResult':
        setState(() {
          _searchCurrent = (raw['activeMatch'] as int?) ??
              (raw['current'] as int?) ??
              0;
          _searchTotal = (raw['numberOfMatches'] as int?) ??
              (raw['total'] as int?) ??
              0;
        });
        break;
    }
  }

  void _onSearchChanged(String query) {
    _searchDebounce?.cancel();
    final cfg = widget.searchConfig;
    if (cfg.debounceDuration > Duration.zero) {
      _searchDebounce = Timer(cfg.debounceDuration, () {
        unawaited(_method?.invokeMethod(cfg.searchMethod, {'query': query}));
      });
    } else {
      unawaited(_method?.invokeMethod(cfg.searchMethod, {'query': query}));
    }
  }

  void _startSearch() {
    setState(() => _isSearching = true);
    _searchFocusNode.requestFocus();
  }

  void _stopSearch() {
    _searchDebounce?.cancel();
    _searchController.clear();
    unawaited(_method?.invokeMethod(widget.searchConfig.clearMethod));
    setState(() {
      _isSearching = false;
      _searchCurrent = 0;
      _searchTotal = 0;
    });
  }

  void _findNext() {
    final cfg = widget.searchConfig;
    if (cfg.findPrevMethod == null) {
      unawaited(_method?.invokeMethod(cfg.findNextMethod, {'forward': true}));
    } else {
      unawaited(_method?.invokeMethod(cfg.findNextMethod));
    }
  }

  void _findPrevious() {
    final cfg = widget.searchConfig;
    if (cfg.findPrevMethod == null) {
      unawaited(_method?.invokeMethod(cfg.findNextMethod, {'forward': false}));
    } else {
      unawaited(_method?.invokeMethod(cfg.findPrevMethod!));
    }
  }

  Future<void> _showGoToPageDialog() async {
    if (_pageCount <= 0) return;
    final controller = TextEditingController(text: _currentPage.toString());
    try {
      final targetPageStr = await showDialog<String>(
        context: context,
        builder: (dialogCtx) => AlertDialog(
          title: const Text('Go to page'),
          content: TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            autofocus: true,
            decoration: InputDecoration(
              hintText: 'Page number (1 - $_pageCount)',
              labelText: 'Page',
            ),
            onSubmitted: (val) => Navigator.of(dialogCtx).pop(val),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogCtx).pop(),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogCtx).pop(controller.text),
              child: const Text('Go'),
            ),
          ],
        ),
      );
      if (targetPageStr == null || targetPageStr.trim().isEmpty) return;
      final targetPage = int.tryParse(targetPageStr.trim());
      if (targetPage != null && targetPage >= 1 && targetPage <= _pageCount) {
        unawaited(_method?.invokeMethod('goToPage', {'page': targetPage}));
      }
    } finally {
      controller.dispose();
    }
  }

  Future<void> _printDocument() async {
    try {
      await _method?.invokeMethod('printDocument');
    } catch (_) {}
  }

  @override
  void dispose() {
    _eventSub?.cancel();
    _searchDebounce?.cancel();
    _searchController.dispose();
    _searchFocusNode.dispose();
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
        IconButton(
          icon: const Icon(Icons.print_rounded),
          tooltip: 'Print document',
          onPressed: _printDocument,
        ),
        ...?widget.extraActionsBuilder?.call(_method),
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
    return Stack(
      children: [
        Positioned.fill(
          child: PlatformViewLink(
            viewType: _kPdfViewerViewType,
            surfaceFactory: (context, controller) {
              return AndroidViewSurface(
                controller: controller as AndroidViewController,
                gestureRecognizers:
                    const <Factory<OneSequenceGestureRecognizer>>{},
                hitTestBehavior: PlatformViewHitTestBehavior.opaque,
              );
            },
            onCreatePlatformView: (PlatformViewCreationParams params) {
              return PlatformViewsService.initExpensiveAndroidView(
                id: params.id,
                viewType: _kPdfViewerViewType,
                layoutDirection: TextDirection.ltr,
                creationParams: widget.creationParams,
                creationParamsCodec: const StandardMessageCodec(),
                onFocus: () => params.onFocusChanged(true),
              )
                ..addOnPlatformViewCreatedListener(
                    params.onPlatformViewCreated)
                ..addOnPlatformViewCreatedListener(_onPlatformViewCreated)
                ..create();
            },
          ),
        ),
        if (_isLoading)
          IgnorePointer(
            child: AnimatedOpacity(
              opacity: _isLoading ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 200),
              child: Container(
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