import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/widgets/feedback/app_feedback.dart';
import 'package:vaultexplorer/core/widgets/feedback/inline_banner.dart'
    show AppBannerTone;
import 'package:vaultexplorer/features/browser/widgets/fast_scrollbar.dart';
import 'package:vaultexplorer/features/settings/logcat_controller.dart';

class LogcatScreen extends ConsumerStatefulWidget {
  const LogcatScreen({super.key});

  @override
  ConsumerState<LogcatScreen> createState() => _LogcatScreenState();
}

class _LogcatScreenState extends ConsumerState<LogcatScreen> {
  final ScrollController _scrollCtrl = ScrollController();
  final ScrollController _horizontalScrollCtrl = ScrollController();
  final TextEditingController _searchCtrl = TextEditingController();
  final Map<int, Offset> _pinchPointers = {};
  final Set<int> _selectedLogIndices = {};
  final GlobalKey _logListKey = GlobalKey();

  bool _isSearching = false;
  bool _userScrolledUp = false;
  double? _initialPinchDistance;
  double _pinchStartFontSize = 11.5;
  double _fontSize = 11.5;
  double _logRowExtent = 32;
  int _visibleLineCount = 0;
  int? _selectionDragAnchor;

  @override
  void initState() {
    super.initState();
    _scrollCtrl.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollCtrl.removeListener(_onScroll);
    _scrollCtrl.dispose();
    _horizontalScrollCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollCtrl.hasClients) return;
    final pos = _scrollCtrl.position;
    final isNearBottom = pos.pixels >= pos.maxScrollExtent - 80;
    if (_userScrolledUp == isNearBottom) {
      setState(() {
        _userScrolledUp = !isNearBottom;
      });
    }
  }

  void _scrollToBottom({bool animate = true}) {
    if (!_scrollCtrl.hasClients) return;
    final max = _scrollCtrl.position.maxScrollExtent;
    if (animate) {
      _scrollCtrl.animateTo(
        max,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    } else {
      _scrollCtrl.jumpTo(max);
    }
    setState(() => _userScrolledUp = false);
  }

  void _toggleLogLine(int index) {
    setState(() {
      if (!_selectedLogIndices.add(index)) {
        _selectedLogIndices.remove(index);
      }
    });
  }

  int? _lineIndexAt(Offset globalPosition) {
    if (!_scrollCtrl.hasClients) return null;
    final renderBox =
        _logListKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return null;

    final localPosition = renderBox.globalToLocal(globalPosition);
    if (localPosition.dx > 56 ||
        localPosition.dy < 8 ||
        localPosition.dy > renderBox.size.height - 8) {
      return null;
    }
    final index =
        ((localPosition.dy - 8 + _scrollCtrl.offset) / _logRowExtent).floor();
    if (index < 0 || index >= _visibleLineCount) return null;
    return index;
  }

  void _selectLogRange(int anchor, int index) {
    final first = anchor < index ? anchor : index;
    final last = anchor > index ? anchor : index;
    var changed = false;
    for (var i = first; i <= last; i++) {
      changed = _selectedLogIndices.add(i) || changed;
    }
    if (changed) setState(() {});
  }

  void _handleRowRangeDragStart(int index) {
    if (_pinchPointers.length > 1) return;
    _selectionDragAnchor = index;
    _selectLogRange(index, index);
  }

  void _handleRowRangeDragUpdate(DragUpdateDetails details) {
    if (_pinchPointers.length > 1) return;
    final anchor = _selectionDragAnchor;
    final index = _lineIndexAt(details.globalPosition);
    if (anchor != null && index != null) {
      _selectLogRange(anchor, index);
    }
  }

  void _handleRowRangeDragEnd() => _selectionDragAnchor = null;

  void _clearLogSelection() {
    if (_selectedLogIndices.isEmpty) return;
    setState(_selectedLogIndices.clear);
  }

  void _handlePinchPointerDown(PointerDownEvent event) {
    _pinchPointers[event.pointer] = event.position;
    if (_pinchPointers.length == 2) {
      final points = _pinchPointers.values.toList();
      _initialPinchDistance = (points[0] - points[1]).distance;
      _pinchStartFontSize = _fontSize;
    }
  }

  void _handlePinchPointerMove(PointerMoveEvent event) {
    if (_pinchPointers.containsKey(event.pointer)) {
      _pinchPointers[event.pointer] = event.position;
    }
    final initialDistance = _initialPinchDistance;
    if (_pinchPointers.length != 2 ||
        initialDistance == null ||
        initialDistance <= 10) {
      return;
    }

    final points = _pinchPointers.values.toList();
    final currentDistance = (points[0] - points[1]).distance;
    final newSize = (_pinchStartFontSize * currentDistance / initialDistance)
        .clamp(10.0, 24.0);
    final roundedSize = (newSize * 2).round() / 2.0;
    if ((roundedSize - _fontSize).abs() >= 0.5) {
      setState(() => _fontSize = roundedSize);
    }
  }

  void _handlePinchPointerEnd(PointerEvent event) {
    _pinchPointers.remove(event.pointer);
    if (_pinchPointers.length < 2) {
      _initialPinchDistance = null;
    }
  }

  Future<void> _clearLog() async {
    await ref.read(logcatControllerProvider.notifier).clearLog();
    if (mounted) {
      showAppSnackBar(
        context,
        message: context.l10n.logcatClearedMessage,
        tone: AppBannerTone.info,
        icon: Icons.delete_sweep_rounded,
      );
    }
  }

  Future<void> _saveLog(List<String> filteredLines) async {
    final result = await ref
        .read(logcatControllerProvider.notifier)
        .saveLog(filteredLines);
    if (!mounted) return;
    // null means the user cancelled the system "Save As" picker -- a
    // deliberate choice, not a failure, so stay quiet rather than showing
    // an error snackbar.
    if (result == null) return;
    if (!result.success) {
      showAppSnackBar(
        context,
        message: context.l10n.logcatSaveErrorMessage,
        tone: AppBannerTone.error,
      );
    } else {
      showAppSnackBar(
        context,
        message: context.l10n.logcatSavedMessage(result.displayName),
        tone: AppBannerTone.success,
        icon: Icons.save_rounded,
      );
    }
  }

  Future<void> _copyLog(List<String> filteredLines) async {
    if (filteredLines.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: filteredLines.join('\n')));
    if (mounted) {
      showAppSnackBar(
        context,
        message: context.l10n.logcatCopiedMessage,
        tone: AppBannerTone.success,
        icon: Icons.copy_rounded,
      );
    }
  }

  Future<void> _copySelectedLog(List<String> filteredLines) async {
    if (_selectedLogIndices.isEmpty) return;
    final selectedLines = _selectedLogIndices.toList()..sort();
    final text = selectedLines
        .where((index) => index >= 0 && index < filteredLines.length)
        .map((index) => filteredLines[index])
        .join('\n');
    if (text.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) {
      showAppSnackBar(
        context,
        message: context.l10n.logcatCopiedMessage,
        tone: AppBannerTone.success,
        icon: Icons.copy_rounded,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final logState = ref.watch(logcatControllerProvider);
    // Auto-scroll to bottom whenever a new line arrives, unless the user
    // deliberately scrolled up to read earlier output.
    ref.listen<LogcatState>(logcatControllerProvider, (previous, next) {
      if (next.lines.length < (previous?.lines.length ?? 0)) {
        _clearLogSelection();
      }
      if (next.lines.length > (previous?.lines.length ?? 0) &&
          !_userScrolledUp) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scrollCtrl.hasClients && !_userScrolledUp) {
            _scrollCtrl.jumpTo(_scrollCtrl.position.maxScrollExtent);
          }
        });
      }
    });

    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final filtered = logState.filteredLines;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A1A1A),
        foregroundColor: Colors.white,
        title: _isSearching
            ? TextField(
                controller: _searchCtrl,
                autofocus: true,
                style: const TextStyle(color: Colors.white, fontSize: 14),
                cursorColor: cs.primary,
                decoration: InputDecoration(
                  hintText: context.l10n.logcatSearchHint,
                  hintStyle: TextStyle(
                    color: Colors.white.withValues(alpha: 0.5),
                  ),
                  border: InputBorder.none,
                ),
                onChanged: (val) {
                  _clearLogSelection();
                  ref
                      .read(logcatControllerProvider.notifier)
                      .setSearchQuery(val);
                  WidgetsBinding.instance.addPostFrameCallback(
                    (_) => _scrollToBottom(animate: false),
                  );
                },
              )
            : Text(
                context.l10n.logcatTitle,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
        actions: [
          IconButton(
            icon: Icon(
              _isSearching ? Icons.close_rounded : Icons.search_rounded,
            ),
            tooltip: _isSearching ? context.l10n.closeSearchTooltip : context.l10n.search,
            onPressed: () {
              setState(() {
                if (_isSearching) {
                  _isSearching = false;
                  _searchCtrl.clear();
                } else {
                  _isSearching = true;
                }
              });
              _clearLogSelection();
              if (_isSearching == false) {
                ref.read(logcatControllerProvider.notifier).setSearchQuery('');
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.copy_rounded),
            tooltip: context.l10n.logcatCopyTooltip,
            onPressed: filtered.isEmpty ? null : () => _copyLog(filtered),
          ),
          IconButton(
            icon: const Icon(Icons.delete_sweep_rounded),
            tooltip: context.l10n.logcatClearTooltip,
            onPressed: logState.lines.isEmpty || logState.clearing
                ? null
                : _clearLog,
          ),
          if (logState.saving)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 14),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  valueColor: AlwaysStoppedAnimation(Colors.white),
                ),
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.save_alt_rounded),
              tooltip: context.l10n.logcatSaveTooltip,
              onPressed: filtered.isEmpty ? null : () => _saveLog(filtered),
            ),
        ],
      ),
      body: Column(
        children: [
          _buildFilterBar(cs, logState, filtered.length),
          Expanded(
            child: logState.streamError
                ? _buildError(cs, textTheme)
                : filtered.isEmpty
                ? _buildEmpty(cs, textTheme)
                : _buildLogList(filtered, textTheme),
          ),
        ],
      ),
      bottomNavigationBar: _selectedLogIndices.isEmpty
          ? null
          : SafeArea(
              top: false,
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF1A1A1A),
                  border: Border(
                    top: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
                  ),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.checklist_rounded,
                      color: Colors.white70,
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        context.l10n.logcatLinesCount(
                          _selectedLogIndices.length,
                        ),
                        style: const TextStyle(color: Colors.white70),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () => _copySelectedLog(filtered),
                      icon: const Icon(Icons.copy_rounded),
                      label: Text(context.l10n.filesCopy),
                    ),
                    IconButton(
                      tooltip: context.l10n.clearSelectionTooltip,
                      onPressed: _clearLogSelection,
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),
            ),
      floatingActionButton: _userScrolledUp
          ? FloatingActionButton.small(
              backgroundColor: const Color(0xFF2C2C2C),
              foregroundColor: Colors.white,
              tooltip: context.l10n.logcatScrollToBottomTooltip,
              onPressed: () => _scrollToBottom(),
              child: const Icon(Icons.arrow_downward_rounded),
            )
          : null,
    );
  }

  Widget _buildFilterBar(ColorScheme cs, LogcatState logState, int count) {
    void selectMode(LogFilterMode mode) {
      _clearLogSelection();
      ref.read(logcatControllerProvider.notifier).setFilterMode(mode);
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _scrollToBottom(animate: false),
      );
    }

    return Container(
      color: const Color(0xFF141414),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        children: [
          ChoiceChip(
            label: Text(context.l10n.logcatFilterAppOnly),
            selected: logState.filterMode == LogFilterMode.appOnly,
            selectedColor: cs.primary.withValues(alpha: 0.25),
            backgroundColor: const Color(0xFF222222),
            labelStyle: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: logState.filterMode == LogFilterMode.appOnly
                  ? cs.primary
                  : Colors.white70,
            ),
            side: BorderSide(
              color: logState.filterMode == LogFilterMode.appOnly
                  ? cs.primary.withValues(alpha: 0.6)
                  : Colors.transparent,
            ),
            onSelected: (selected) {
              if (selected) selectMode(LogFilterMode.appOnly);
            },
          ),
          const SizedBox(width: 8),
          ChoiceChip(
            label: Text(context.l10n.logcatFilterAll),
            selected: logState.filterMode == LogFilterMode.all,
            selectedColor: cs.primary.withValues(alpha: 0.25),
            backgroundColor: const Color(0xFF222222),
            labelStyle: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: logState.filterMode == LogFilterMode.all
                  ? cs.primary
                  : Colors.white70,
            ),
            side: BorderSide(
              color: logState.filterMode == LogFilterMode.all
                  ? cs.primary.withValues(alpha: 0.6)
                  : Colors.transparent,
            ),
            onSelected: (selected) {
              if (selected) selectMode(LogFilterMode.all);
            },
          ),
          const Spacer(),
          Text(
            context.l10n.logcatLinesCount(count),
            style: TextStyle(
              fontSize: 11,
              color: Colors.white.withValues(alpha: 0.4),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLogList(List<String> lines, TextTheme textTheme) {
    const horizontalPadding = 16.0;
    final longestLineLength = lines.fold<int>(
      0,
      (longest, line) => line.length > longest ? line.length : longest,
    );
    final contentWidth =
        longestLineLength * _fontSize + horizontalPadding + 40;
    _logRowExtent = (_fontSize * 1.55 + 8).clamp(32.0, 64.0).roundToDouble();
    _visibleLineCount = lines.length;

    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (event) {
        _handlePinchPointerDown(event);
      },
      onPointerMove: _handlePinchPointerMove,
      onPointerUp: _handlePinchPointerEnd,
      onPointerCancel: _handlePinchPointerEnd,
      child: FastScrollbar(
        controller: _scrollCtrl,
        child: FastScrollbar(
          controller: _horizontalScrollCtrl,
          axis: Axis.horizontal,
          child: LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              controller: _horizontalScrollCtrl,
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: contentWidth > constraints.maxWidth
                    ? contentWidth
                    : constraints.maxWidth,
                height: constraints.maxHeight,
                child: ListView.builder(
                  key: _logListKey,
                  controller: _scrollCtrl,
                  itemExtent: _logRowExtent,
                  padding: const EdgeInsets.symmetric(
                    horizontal: horizontalPadding / 2,
                    vertical: 8,
                  ),
                  itemCount: lines.length,
                  itemBuilder: (context, index) {
                    final line = lines[index];
                    final isSelected = _selectedLogIndices.contains(index);
                    final color = _lineColor(line);
                    return Container(
                      height: _logRowExtent,
                      color: isSelected
                          ? Theme.of(context).colorScheme.primary.withValues(
                              alpha: 0.16,
                            )
                      : null,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          SizedBox(
                            width: 40,
                            height: _logRowExtent,
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onVerticalDragStart: (_) =>
                                  _handleRowRangeDragStart(index),
                              onVerticalDragUpdate: _handleRowRangeDragUpdate,
                              onVerticalDragEnd: (_) =>
                                  _handleRowRangeDragEnd(),
                              onVerticalDragCancel: _handleRowRangeDragEnd,
                              child: Center(
                                child: Transform.scale(
                                  scale: 0.8,
                                  child: Checkbox(
                                    value: isSelected,
                                    visualDensity: VisualDensity.compact,
                                    materialTapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                    onChanged: (_) => _toggleLogLine(index),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          Expanded(
                            child: SelectableText(
                              line,
                              style: textTheme.bodySmall?.copyWith(
                                fontFamily: 'monospace',
                                fontSize: _fontSize,
                                height: 1.55,
                                color: color,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmpty(ColorScheme cs, TextTheme textTheme) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.receipt_long_rounded,
            size: 48,
            color: Colors.white.withValues(alpha: 0.3),
          ),
          const SizedBox(height: 12),
          Text(
            context.l10n.logcatEmptyMessage,
            style: textTheme.bodyMedium?.copyWith(
              color: Colors.white.withValues(alpha: 0.5),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildError(ColorScheme cs, TextTheme textTheme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline_rounded,
              size: 48,
              color: cs.error.withValues(alpha: 0.8),
            ),
            const SizedBox(height: 12),
            Text(
              context.l10n.logcatUnavailableMessage,
              textAlign: TextAlign.center,
              style: textTheme.bodyMedium?.copyWith(
                color: Colors.white.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: 20),
            OutlinedButton.icon(
              onPressed: () =>
                  ref.read(logcatControllerProvider.notifier).restartStream(),
              icon: const Icon(Icons.refresh_rounded, color: Colors.white70),
              label: Text(
                context.l10n.retryButton,
                style: const TextStyle(color: Colors.white70),
              ),
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: Colors.white.withValues(alpha: 0.3)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _lineColor(String line) {
    final levelMatch = RegExp(r'\b([VDIWEF])/').firstMatch(line);
    if (levelMatch == null) return Colors.white70;
    switch (levelMatch.group(1)) {
      case 'E':
      case 'F':
        return const Color(0xFFFF5555);
      case 'W':
        return const Color(0xFFFFB86C);
      case 'I':
        return const Color(0xFF50FA7B);
      case 'D':
        return const Color(0xFF8BE9FD);
      case 'V':
        return Colors.white38;
      default:
        return Colors.white70;
    }
  }
}
