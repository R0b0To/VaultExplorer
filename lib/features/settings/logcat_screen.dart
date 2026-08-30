import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/widgets/feedback/app_feedback.dart';
import 'package:vaultexplorer/core/widgets/feedback/inline_banner.dart'
    show AppBannerTone;
import 'package:vaultexplorer/features/settings/logcat_controller.dart';

class LogcatScreen extends ConsumerStatefulWidget {
  const LogcatScreen({super.key});

  @override
  ConsumerState<LogcatScreen> createState() => _LogcatScreenState();
}

class _LogcatScreenState extends ConsumerState<LogcatScreen> {
  final ScrollController _scrollCtrl = ScrollController();
  final TextEditingController _searchCtrl = TextEditingController();

  bool _isSearching = false;
  bool _userScrolledUp = false;

  @override
  void initState() {
    super.initState();
    _scrollCtrl.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollCtrl.removeListener(_onScroll);
    _scrollCtrl.dispose();
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
    final path = await ref
        .read(logcatControllerProvider.notifier)
        .saveLog(filteredLines);
    if (!mounted) return;
    if (path == null) {
      showAppSnackBar(
        context,
        message: context.l10n.logcatSaveErrorMessage,
        tone: AppBannerTone.error,
      );
    } else {
      showAppSnackBar(
        context,
        message: context.l10n.logcatSavedMessage(path),
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

  @override
  Widget build(BuildContext context) {
    final logState = ref.watch(logcatControllerProvider);
    // Auto-scroll to bottom whenever a new line arrives, unless the user
    // deliberately scrolled up to read earlier output.
    ref.listen<LogcatState>(logcatControllerProvider, (previous, next) {
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
            tooltip: _isSearching ? 'Close search' : 'Search',
            onPressed: () {
              setState(() {
                if (_isSearching) {
                  _isSearching = false;
                  _searchCtrl.clear();
                } else {
                  _isSearching = true;
                }
              });
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
      floatingActionButton: _userScrolledUp
          ? FloatingActionButton.small(
              backgroundColor: const Color(0xFF2C2C2C),
              foregroundColor: Colors.white,
              tooltip: 'Scroll to bottom',
              onPressed: () => _scrollToBottom(),
              child: const Icon(Icons.arrow_downward_rounded),
            )
          : null,
    );
  }

  Widget _buildFilterBar(ColorScheme cs, LogcatState logState, int count) {
    void selectMode(LogFilterMode mode) {
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
            '$count lines',
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
    return ListView.builder(
      controller: _scrollCtrl,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      itemCount: lines.length,
      itemBuilder: (context, index) {
        final line = lines[index];
        final color = _lineColor(line);
        return SelectableText(
          line,
          style: textTheme.bodySmall?.copyWith(
            fontFamily: 'monospace',
            fontSize: 11.5,
            height: 1.55,
            color: color,
          ),
        );
      },
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