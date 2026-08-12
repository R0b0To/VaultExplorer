import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/data/services/vault_engine/vault_explorer_api.dart';

/// Renders PDFs with the OS's own `android.graphics.pdf.PdfRenderer`.
class PdfViewerBase extends StatefulWidget {
  final MountedContainer? container;
  final String? pdfPath;
  final String? localUri;
  final Map<String, dynamic>? creationParams;
  final String title;
  final bool isLocked;
  final VoidCallback? onPrint;
  final Widget Function(Widget child)? titleBuilder;
  final Widget Function(Widget child)? pageCounterBuilder;
  final List<Widget> Function()? extraActionsBuilder;

  const PdfViewerBase({
    super.key,
    this.container,
    this.pdfPath,
    this.localUri,
    this.creationParams,
    required this.title,
    this.isLocked = false,
    this.onPrint,
    this.titleBuilder,
    this.pageCounterBuilder,
    this.extraActionsBuilder,
  });

  @override
  State<PdfViewerBase> createState() => _PdfViewerBaseState();
}

class _PdfViewerBaseState extends State<PdfViewerBase> {
  static const _chromeAnimationDuration = Duration(milliseconds: 220);
  static const _chromeAutoHideDelay = Duration(seconds: 3);
  static const _pageHorizontalMargin = 14.0;
  static const _pageSpacing = 16.0;

  bool _isLoading = true;
  bool _hasError = false;
  String _errorMessage = '';

  int? _handle;
  int _pageCount = 0;
  int _currentPage = 1;

  bool _showChrome = true;
  Timer? _hideTimer;
  bool _isUserDraggingSlider = false;

  final ScrollController _scrollController = ScrollController();
  late final TransformationController _zoomController;
  TapDownDetails? _doubleTapDetails;

  final Map<int, PdfPageSize> _pageSizes = {};
  final _PdfImageCache _imageCache = _PdfImageCache();

  MountedContainer? _effectiveContainer;
  String? _effectivePdfPath;
  String? _effectiveLocalUri;

  double _lastLayoutWidth = 0.0;

  @override
  void initState() {
    super.initState();
    _zoomController = TransformationController();
    _scrollController.addListener(_onScroll);
    _resolveSourceAndOpen();
  }

  void _onScroll() {
    if (!_scrollController.hasClients || _isUserDraggingSlider) return;
    if (_lastLayoutWidth <= 0 || _pageCount <= 0) return;

    final offset = _scrollController.offset;
    final pageWidth = (_lastLayoutWidth - _pageHorizontalMargin * 2)
        .clamp(80.0, _lastLayoutWidth)
        .toDouble();

    double accumulated = 0;
    int page = 1;

    for (int i = 0; i < _pageCount; i++) {
      final size = _pageSizes[i];
      double ar = 0.707;
      if (size != null && size.width > 0 && size.height > 0) {
        ar = size.width / size.height;
      }
      final pageHeight = (pageWidth / ar) + _pageSpacing;

      if (offset < accumulated + pageHeight / 2) {
        page = i + 1;
        break;
      }
      accumulated += pageHeight;
      page = i + 1;
    }

    if (_currentPage != page) {
      setState(() => _currentPage = page);
    }
  }

  void _scrollToPage(int targetPage, {bool animate = false}) {
    if (!_scrollController.hasClients || _lastLayoutWidth <= 0) return;
    final targetIndex = (targetPage - 1).clamp(0, _pageCount - 1);
    final pageWidth = (_lastLayoutWidth - _pageHorizontalMargin * 2)
        .clamp(80.0, _lastLayoutWidth)
        .toDouble();

    double targetOffset = 0;
    for (int i = 0; i < targetIndex; i++) {
      final size = _pageSizes[i];
      double ar = 0.707;
      if (size != null && size.width > 0 && size.height > 0) {
        ar = size.width / size.height;
      }
      targetOffset += (pageWidth / ar) + _pageSpacing;
    }

    final maxScroll = _scrollController.position.maxScrollExtent;
    final finalOffset = targetOffset.clamp(0.0, maxScroll);

    if (animate) {
      _scrollController.animateTo(
        finalOffset,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeInOut,
      );
    } else {
      _scrollController.jumpTo(finalOffset);
    }
  }

  void _resolveSourceAndOpen() {
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
      _openVaultPdf();
    } else if (_effectiveLocalUri != null && _effectiveLocalUri!.isNotEmpty) {
      _openLocalPdf();
    } else {
      setState(() {
        _isLoading = false;
        _hasError = true;
        _errorMessage = context.l10n.pdfViewerNoSourceProvided;
      });
    }
  }

  Future<void> _openVaultPdf() async {
    try {
      final result = await vaultExplorerApi.openPdf(
        _effectiveContainer!,
        _effectivePdfPath!,
      );
      if (!mounted) return;
      if (result.pageCount <= 0) {
        setState(() {
          _isLoading = false;
          _hasError = true;
          _errorMessage = context.l10n.pdfViewerFileEmpty;
        });
        return;
      }
      setState(() {
        _handle = result.handle;
        _pageCount = result.pageCount;
        _isLoading = false;
      });
      _scheduleAutoHideChrome();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _hasError = true;
        _errorMessage = context.l10n.pdfViewerFailedToInspectSize('$e');
      });
    }
  }

  Future<void> _openLocalPdf() async {
    try {
      final result = await vaultExplorerApi.openLocalPdf(_effectiveLocalUri!);
      if (!mounted) return;
      if (result.pageCount <= 0) {
        setState(() {
          _isLoading = false;
          _hasError = true;
          _errorMessage = context.l10n.pdfViewerFileEmpty;
        });
        return;
      }
      setState(() {
        _handle = result.handle;
        _pageCount = result.pageCount;
        _isLoading = false;
      });
      _scheduleAutoHideChrome();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _hasError = true;
        _errorMessage = '${context.l10n.pdfViewerFailedToLoad}: $e';
      });
    }
  }

  Future<void> _showGoToPageDialog() async {
    if (_pageCount <= 0) return;
    _hideTimer?.cancel();
    final targetPageStr = await showDialog<String>(
      context: context,
      builder: (dialogCtx) => _GoToPageDialog(
        currentPage: _currentPage,
        pageCount: _pageCount,
      ),
    );
    _scheduleAutoHideChrome();
    if (targetPageStr == null || targetPageStr.trim().isEmpty) return;
    final targetPage = int.tryParse(targetPageStr.trim());
    if (targetPage != null && targetPage >= 1 && targetPage <= _pageCount) {
      _scrollToPage(targetPage, animate: true);
    }
  }

  void _toggleChrome() {
    HapticFeedback.lightImpact();
    setState(() => _showChrome = !_showChrome);
    if (_showChrome) {
      _scheduleAutoHideChrome();
    } else {
      _hideTimer?.cancel();
    }
  }

  void _scheduleAutoHideChrome() {
    _hideTimer?.cancel();
    _hideTimer = Timer(_chromeAutoHideDelay, () {
      if (mounted && _showChrome) {
        setState(() => _showChrome = false);
      }
    });
  }

  void _handleDoubleTap() {
    HapticFeedback.lightImpact();
    final currentScale = _zoomController.value.getMaxScaleOnAxis();
    if (currentScale > 1.05) {
      _zoomController.value = Matrix4.identity();
      return;
    }
    const targetScale = 2.5;
    final position = _doubleTapDetails?.localPosition;
    if (position != null) {
      final x = -position.dx * (targetScale - 1);
      final y = -position.dy * (targetScale - 1);
      _zoomController.value = Matrix4.identity()
        ..translate(x, y)
        ..scale(targetScale);
    } else {
      _zoomController.value = Matrix4.identity()..scale(targetScale);
    }
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _zoomController.dispose();
    final handle = _handle;
    if (handle != null) {
      vaultExplorerApi.closePdf(handle);
    }
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
    final isReady =
        !_isLoading && !_hasError && _handle != null && _pageCount > 0;

    if (!isReady) {
      return Scaffold(
        appBar: AppBar(title: _buildPlainTitle()),
        body: _buildStatusBody(cs),
      );
    }

    final topPadding = MediaQuery.paddingOf(context).top;
    final bottomPadding = MediaQuery.paddingOf(context).bottom;

    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: _canvasColor(context),
      body: Stack(
        fit: StackFit.expand,
        children: [
          _buildDocumentView(),
          AnimatedPositioned(
            duration: _chromeAnimationDuration,
            curve: Curves.easeOut,
            top: _showChrome ? 0 : -140,
            left: 0,
            right: 0,
            child: IgnorePointer(
              ignoring: !_showChrome,
              child: _buildTopBar(context),
            ),
          ),
          if (_pageCount > 1)
            AnimatedPositioned(
              duration: _chromeAnimationDuration,
              curve: Curves.easeOut,
              top: topPadding + 70,
              bottom: bottomPadding + 80,
              right: _showChrome ? 12 : -80,
              child: IgnorePointer(
                ignoring: !_showChrome,
                child: _buildVerticalScrubber(context, cs),
              ),
            ),
          AnimatedPositioned(
            duration: _chromeAnimationDuration,
            curve: Curves.easeOut,
            left: 0,
            right: 0,
            bottom: _showChrome ? 0 : -120,
            child: IgnorePointer(
              ignoring: !_showChrome,
              child: _buildBottomBar(context),
            ),
          ),
        ],
      ),
    );
  }

  Color _canvasColor(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFF161616)
        : const Color(0xFFE6E6EA);
  }

  Widget _buildPlainTitle() {
    final title = Text(widget.title, overflow: TextOverflow.ellipsis);
    return widget.titleBuilder?.call(title) ?? title;
  }

  Widget _buildTopBar(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final title = Text(
      widget.title,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: textTheme.titleMedium?.copyWith(
        color: Colors.white,
        fontWeight: FontWeight.w600,
      ),
    );

    return Container(
      padding: EdgeInsets.only(
        top: MediaQuery.paddingOf(context).top + 8,
        bottom: 20,
        left: 12,
        right: 12,
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.black.withValues(alpha: 0.80),
            Colors.transparent,
          ],
        ),
      ),
      child: Row(
        children: [
          _PdfChromeButton(
            icon: Icons.arrow_back_rounded,
            tooltip: context.l10n.backTooltip,
            onPressed: () {
              HapticFeedback.lightImpact();
              Navigator.of(context).maybePop();
            },
          ),
          const SizedBox(width: 12),
          Expanded(child: widget.titleBuilder?.call(title) ?? title),
          if (widget.onPrint != null) ...[
            const SizedBox(width: 8),
            _PdfChromeButton(
              icon: Icons.print_rounded,
              tooltip: 'Print',
              onPressed: widget.onPrint!,
            ),
          ],
          ...?widget.extraActionsBuilder?.call(),
        ],
      ),
    );
  }

  Widget _buildBottomBar(BuildContext context) {
    final bottomPadding = MediaQuery.paddingOf(context).bottom;
    final cs = Theme.of(context).colorScheme;

    final counterPill = InkWell(
      onTap: _showGoToPageDialog,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        decoration: BoxDecoration(
          color: cs.inverseSurface.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(20),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Text(
          context.l10n.xOfYCounter(_currentPage, _pageCount),
          style: TextStyle(
            color: cs.onInverseSurface,
            fontWeight: FontWeight.w600,
            fontSize: 13,
          ),
        ),
      ),
    );

    return Container(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 16,
        bottom: bottomPadding + 14,
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [
            Colors.black.withValues(alpha: 0.80),
            Colors.transparent,
          ],
        ),
      ),
      child: Center(
        child: widget.pageCounterBuilder?.call(counterPill) ?? counterPill,
      ),
    );
  }

  Widget _buildVerticalScrubber(BuildContext context, ColorScheme cs) {
    return ListenableBuilder(
      listenable: _scrollController,
      builder: (context, _) {
        return LayoutBuilder(
          builder: (context, constraints) {
            final trackHeight = constraints.maxHeight;
            const thumbHeight = 44.0;
            const thumbWidth = 8.0;
            const railWidth = 32.0;

            if (trackHeight <= thumbHeight) {
              return const SizedBox.shrink();
            }

            final maxTravel =
                (trackHeight - thumbHeight).clamp(0.0, double.infinity);

            double scrollFraction = 0.0;
            if (_scrollController.hasClients &&
                _scrollController.position.hasContentDimensions &&
                _scrollController.position.maxScrollExtent > 0) {
              scrollFraction = (_scrollController.offset /
                      _scrollController.position.maxScrollExtent)
                  .clamp(0.0, 1.0);
            }

            final thumbTop = scrollFraction * maxTravel;

            return SizedBox(
              width: railWidth,
              height: trackHeight,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onVerticalDragStart: (details) {
                  _isUserDraggingSlider = true;
                  _hideTimer?.cancel();
                  _updateScrubFromDrag(
                      details.localPosition.dy, maxTravel, thumbHeight);
                },
                onVerticalDragUpdate: (details) {
                  _updateScrubFromDrag(
                      details.localPosition.dy, maxTravel, thumbHeight);
                },
                onVerticalDragEnd: (_) {
                  _isUserDraggingSlider = false;
                  _scheduleAutoHideChrome();
                },
                onVerticalDragCancel: () {
                  _isUserDraggingSlider = false;
                  _scheduleAutoHideChrome();
                },
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned(
                      left: (railWidth - 2) / 2,
                      top: thumbHeight / 2,
                      height: maxTravel,
                      width: 2,
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0),
                          borderRadius: BorderRadius.circular(1),
                        ),
                      ),
                    ),
                    if (_isUserDraggingSlider)
                      Positioned(
                        top: thumbTop + (thumbHeight - 28) / 2,
                        right: railWidth + 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: cs.inverseSurface.withValues(alpha: 0.94),
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.3),
                                blurRadius: 6,
                              ),
                            ],
                          ),
                          child: Text(
                            '$_currentPage / $_pageCount',
                            style: TextStyle(
                              color: cs.onInverseSurface,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    Positioned(
                      top: thumbTop,
                      left: (railWidth - thumbWidth) / 2,
                      width: thumbWidth,
                      height: thumbHeight,
                      child: Container(
                        decoration: BoxDecoration(
                          color: cs.primary.withValues(
                              alpha: _isUserDraggingSlider ? 1.0 : 0.85),
                          borderRadius: BorderRadius.circular(thumbWidth / 2),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.35),
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _updateScrubFromDrag(
      double localY, double maxTravel, double thumbHeight) {
    if (!_scrollController.hasClients ||
        !_scrollController.position.hasContentDimensions ||
        maxTravel <= 0) {
      return;
    }
    final clampedY = (localY - thumbHeight / 2).clamp(0.0, maxTravel);
    final fraction = clampedY / maxTravel;
    final targetOffset =
        fraction * _scrollController.position.maxScrollExtent;

    _scrollController.jumpTo(targetOffset);
    _onScroll();
  }

  Widget _buildStatusBody(ColorScheme cs) {
    if (_hasError) {
      return Container(
        color: cs.surface,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.error_outline_rounded, color: cs.error, size: 48),
                const SizedBox(height: 16),
                Text(
                  context.l10n.pdfViewerCannotOpenTitle,
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
                  label: Text(context.l10n.goBack),
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
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(strokeWidth: 2.5),
              const SizedBox(height: 16),
              Text(context.l10n.pdfViewerLoadingDocument),
            ],
          ),
        ),
      );
    }

    return Container(
      color: cs.surface,
      child: Center(child: Text(context.l10n.pdfViewerNoDocumentLoaded)),
    );
  }

  Widget _buildDocumentView() {
    final handle = _handle!;

    return LayoutBuilder(
      builder: (context, constraints) {
        _lastLayoutWidth = constraints.maxWidth;
        final pageWidth = (constraints.maxWidth - _pageHorizontalMargin * 2)
            .clamp(80.0, constraints.maxWidth)
            .toDouble();
        final dpr = MediaQuery.of(context).devicePixelRatio;
        final renderWidthPx = (pageWidth * dpr).clamp(1, 2200).round();

        final topInset = MediaQuery.paddingOf(context).top + 60;
        final bottomInset = MediaQuery.paddingOf(context).bottom + 60;

        return GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: _toggleChrome,
          onDoubleTapDown: (d) => _doubleTapDetails = d,
          onDoubleTap: _handleDoubleTap,
          child: InteractiveViewer(
            transformationController: _zoomController,
            minScale: 1.0,
            maxScale: 4.0,
            child: ListView.builder(
              controller: _scrollController,
              padding: EdgeInsets.only(
                top: topInset,
                bottom: bottomInset,
                left: _pageHorizontalMargin,
                right: _pageHorizontalMargin,
              ),
              itemCount: _pageCount,
              itemBuilder: (context, index) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: _pageSpacing),
                  child: RepaintBoundary(
                    child: Center(
                      child: _PdfPageView(
                        key: ValueKey('pdf_page_${handle}_$index'),
                        handle: handle,
                        pageIndex: index,
                        pageWidth: pageWidth,
                        renderWidthPx: renderWidthPx,
                        pageSizeCache: _pageSizes,
                        imageCache: _imageCache,
                        onSizeKnown: () {
                          if (mounted) setState(() {});
                        },
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }
}

class _PdfImageCache {
  _PdfImageCache() : capacity = 8;
  final int capacity;
  final Map<String, Uint8List> _entries = {};
  final List<String> _order = [];

  Uint8List? get(String key) => _entries[key];

  void put(String key, Uint8List bytes) {
    if (_entries.containsKey(key)) {
      _order.remove(key);
    } else if (_entries.length >= capacity) {
      final oldest = _order.removeAt(0);
      _entries.remove(oldest);
    }
    _entries[key] = bytes;
    _order.add(key);
  }
}

class _PdfPageView extends StatefulWidget {
  const _PdfPageView({
    super.key,
    required this.handle,
    required this.pageIndex,
    required this.pageWidth,
    required this.renderWidthPx,
    required this.pageSizeCache,
    required this.imageCache,
    this.onSizeKnown,
  });

  final int handle;
  final int pageIndex;
  final double pageWidth;
  final int renderWidthPx;
  final Map<int, PdfPageSize> pageSizeCache;
  final _PdfImageCache imageCache;
  final VoidCallback? onSizeKnown;

  @override
  State<_PdfPageView> createState() => _PdfPageViewState();
}

class _PdfPageViewState extends State<_PdfPageView> {
  Uint8List? _bytes;
  bool _hasError = false;
  double _aspectRatio = 0.707;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant _PdfPageView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.renderWidthPx != widget.renderWidthPx ||
        oldWidget.pageIndex != widget.pageIndex ||
        oldWidget.handle != widget.handle) {
      _bytes = null;
      _hasError = false;
      _load();
    }
  }

  Future<void> _load() async {
    PdfPageSize size;
    final cachedSize = widget.pageSizeCache[widget.pageIndex];
    try {
      if (cachedSize != null) {
        size = cachedSize;
      } else {
        size = await vaultExplorerApi.getPdfPageSize(
          widget.handle,
          widget.pageIndex,
        );
        widget.pageSizeCache[widget.pageIndex] = size;
        widget.onSizeKnown?.call();
      }
    } catch (_) {
      if (mounted) setState(() => _hasError = true);
      return;
    }
    if (!mounted) return;
    setState(() {
      if (size.width > 0 && size.height > 0) {
        _aspectRatio = size.width / size.height;
      } else {
        _aspectRatio = 0.707;
      }
    });

    final renderHeightPx = (widget.renderWidthPx / _aspectRatio).round();
    final cacheKey =
        '${widget.handle}:${widget.pageIndex}:${widget.renderWidthPx}';
    final cached = widget.imageCache.get(cacheKey);
    if (cached != null) {
      if (mounted) setState(() => _bytes = cached);
      return;
    }
    try {
      final png = await vaultExplorerApi.renderPdfPage(
        widget.handle,
        widget.pageIndex,
        widget.renderWidthPx,
        renderHeightPx,
      );
      widget.imageCache.put(cacheKey, png);
      if (mounted) setState(() => _bytes = png);
    } catch (_) {
      if (mounted) setState(() => _hasError = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    double ar = _aspectRatio;
    if (ar <= 0 || ar.isNaN || ar.isInfinite) {
      ar = 0.707;
    }
    final pageHeight = (widget.pageWidth / ar).clamp(10.0, 20000.0);

    Widget inner;
    if (_hasError) {
      inner = Center(
        child: Icon(Icons.broken_image_outlined, color: cs.error, size: 40),
      );
    } else if (_bytes == null) {
      inner = const Center(
        child: CircularProgressIndicator(strokeWidth: 2.5),
      );
    } else {
      inner = Image.memory(
        _bytes!,
        key: ValueKey(
            'pdf_bytes_${widget.handle}_${widget.pageIndex}_${_bytes.hashCode}'),
        width: widget.pageWidth,
        height: pageHeight,
        fit: BoxFit.contain,
        gaplessPlayback: false,
      );
    }

    return Container(
      width: widget.pageWidth,
      height: pageHeight,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(3),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.28),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: inner,
    );
  }
}

class _PdfChromeButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  const _PdfChromeButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.white.withValues(alpha: 0.14),
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Icon(icon, size: 20, color: Colors.white),
          ),
        ),
      ),
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
      title: Text(context.l10n.pdfViewerGoToPageTitle),
      content: TextField(
        controller: _controller,
        keyboardType: TextInputType.number,
        autofocus: true,
        decoration: InputDecoration(
          hintText: context.l10n.pdfViewerPageNumberHint(widget.pageCount),
          labelText: context.l10n.pdfViewerPageLabel,
        ),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.l10n.cancel),
        ),
        TextButton(
          onPressed: _submit,
          child: Text(context.l10n.pdfViewerGoButton),
        ),
      ],
    );
  }
}