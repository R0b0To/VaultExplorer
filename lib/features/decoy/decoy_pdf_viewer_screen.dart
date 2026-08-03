import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:vaultexplorer/core/theme/app_theme.dart';
import 'package:vaultexplorer/data/services/discrete_mode_repository.dart';
import 'package:vaultexplorer/features/decoy/widgets/hidden_vault_trigger.dart';

/// Must match PDF_VIEWER_VIEW_TYPE in
/// kotlin/.../pdfviewer/PdfViewerPlugin.kt
const String _kPdfViewerViewType = 'com.aeidolon.vaultexplorer/pdf_viewer';

/// Discrete Mode's decoy reader viewer (docs/architecture.md §8, ADR-026).
///
/// Deliberately a separate widget from `PdfViewerScreen` (the in-vault
/// viewer) rather than a generalization of it: this one has no container/volId
/// and carries the hidden vault-unlock trigger on its title.
/// Supports page navigation, text search, page jumping, and printing.
class DecoyPdfViewerScreen extends StatefulWidget {
  final String uri;
  final String displayName;

  const DecoyPdfViewerScreen({
    super.key,
    required this.uri,
    required this.displayName,
  });

  @override
  State<DecoyPdfViewerScreen> createState() => _DecoyPdfViewerScreenState();
}

class _DecoyPdfViewerScreenState extends State<DecoyPdfViewerScreen> {
  MethodChannel? _method;
  StreamSubscription<dynamic>? _eventSub;

  bool _isLoading = true;
  bool _hasError = false;
  String _errorMessage = '';
  int _currentPage = 1;
  int _pageCount = 0;

  // Search & Find features
  bool _isSearching = false;
  final TextEditingController _searchController = TextEditingController();
  int _activeMatch = 0;
  int _numberOfMatches = 0;

  @override
  void initState() {
    super.initState();
    unawaited(
      DiscreteModeRepository.recordOpened(
        DecoyRecentFile(
          uri: widget.uri,
          displayName: widget.displayName,
          openedAt: DateTime.now(),
        ),
      ),
    );
  }

  void _onPlatformViewCreated(int id) {
    final method = MethodChannel('$_kPdfViewerViewType/$id');
    final events = EventChannel('$_kPdfViewerViewType/events/$id');
    _eventSub = events.receiveBroadcastStream().listen(_onEvent, onError: (_) {});
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
      case 'findResult':
        setState(() {
          _activeMatch = (raw['activeMatch'] as int?) ?? 0;
          _numberOfMatches = (raw['numberOfMatches'] as int?) ?? 0;
        });
      case 'error':
        setState(() {
          _isLoading = false;
          _hasError = true;
          _errorMessage = (raw['message'] as String?) ?? 'Failed to load document';
        });
    }
  }

  @override
  void dispose() {
    _eventSub?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _showGoToPageDialog() async {
    if (_pageCount <= 0) return;
    final controller = TextEditingController(text: _currentPage.toString());
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
  }

  void _startSearch() {
    setState(() {
      _isSearching = true;
    });
  }

  void _closeSearch() {
    _searchController.clear();
    unawaited(_method?.invokeMethod('clearMatches'));
    setState(() {
      _isSearching = false;
      _activeMatch = 0;
      _numberOfMatches = 0;
    });
  }

  void _onSearchQueryChanged(String query) {
    unawaited(_method?.invokeMethod('findInPage', {'query': query}));
  }

  void _findNext({required bool forward}) {
    unawaited(_method?.invokeMethod('findNext', {'forward': forward}));
  }

  Future<void> _printDocument() async {
    try {
      await _method?.invokeMethod('printDocument');
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    return Scaffold(
      appBar: _isSearching
          ? AppBar(
              leading: IconButton(
                icon: const Icon(Icons.arrow_back_rounded),
                onPressed: _closeSearch,
              ),
              title: TextField(
                controller: _searchController,
                autofocus: true,
                style: TextStyle(color: cs.onSurface),
                decoration: const InputDecoration(
                  hintText: 'Search in document…',
                  border: InputBorder.none,
                ),
                onChanged: _onSearchQueryChanged,
              ),
              actions: [
                if (_searchController.text.isNotEmpty)
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Text(
                        _numberOfMatches > 0
                            ? '$_activeMatch / $_numberOfMatches'
                            : 'No matches',
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: cs.onSurfaceVariant),
                      ),
                    ),
                  ),
                IconButton(
                  icon: const Icon(Icons.keyboard_arrow_up_rounded),
                  tooltip: 'Previous match',
                  onPressed: _numberOfMatches > 0
                      ? () => _findNext(forward: false)
                      : null,
                ),
                IconButton(
                  icon: const Icon(Icons.keyboard_arrow_down_rounded),
                  tooltip: 'Next match',
                  onPressed: _numberOfMatches > 0
                      ? () => _findNext(forward: true)
                      : null,
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  tooltip: 'Close search',
                  onPressed: _closeSearch,
                ),
              ],
            )
          : AppBar(
              title: HiddenVaultTrigger(
                child: Text(widget.displayName, overflow: TextOverflow.ellipsis),
              ),
              actions: [
                if (_pageCount > 0) ...[
                  HiddenVaultTrigger(
                    child: InkWell(
                      onTap: _showGoToPageDialog,
                      borderRadius: BorderRadius.circular(16),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.sm, vertical: 6),
                        child: Text(
                          '$_currentPage / $_pageCount',
                          style: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(color: cs.onSurfaceVariant),
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.search_rounded),
                    tooltip: 'Search in page',
                    onPressed: _startSearch,
                  ),
                  IconButton(
                    icon: const Icon(Icons.print_rounded),
                    tooltip: 'Print document',
                    onPressed: _printDocument,
                  ),
                ],
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
            creationParams: {'localUri': widget.uri},
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
                  SizedBox(height: AppSpacing.md),
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
                    Icon(Icons.error_outline_rounded, color: cs.error, size: AppIconSize.feature),
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      'Cannot open document',
                      style: Theme.of(
                        context,
                      ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      _errorMessage,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: cs.onSurfaceVariant),
                    ),
                    const SizedBox(height: AppSpacing.lg),
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
