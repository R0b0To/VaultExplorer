import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/widgets/feedback/app_feedback.dart';
import 'package:vaultexplorer/core/widgets/feedback/inline_banner.dart'
    show AppBannerTone;
import 'package:vaultexplorer/data/services/logcat_service.dart';

enum LogFilterMode {
  appOnly,
  all,
}

class LogcatScreen extends StatefulWidget {
  const LogcatScreen({super.key});

  @override
  State<LogcatScreen> createState() => _LogcatScreenState();
}

class _LogcatScreenState extends State<LogcatScreen> {
  final List<String> _lines = [];
  final ScrollController _scrollCtrl = ScrollController();
  final TextEditingController _searchCtrl = TextEditingController();
  StreamSubscription<String>? _sub;

  LogFilterMode _filterMode = LogFilterMode.appOnly;
  bool _isSearching = false;
  String _searchQuery = '';
  bool _saving = false;
  bool _clearing = false;
  bool _streamError = false;
  bool _userScrolledUp = false;

  static const List<String> _noisyTags = [
    'ImeTracker',
    'InsetsController',
    'ViewRootImpl',
    'BLASTBufferQueue',
    'OpenGLRenderer',
    'DecorView',
    'InputMethodManager',
    'SurfaceView',
    'CompatibilityChangeReporter',
    'WindowOnBackDispatcher',
    'SurfaceSyncGroup',
    'Choreographer',
    'AutofillManager',
    'TextInputPlugin',
    'FlutterView',
    'AccessibilityBridge',
    'ProfileInstaller',
    'DynamicColors',
    'HandwritingMode',
    'RenderThread',
    'GraphicBuffer',
    'BufferQueue',
  ];

  static const List<String> _appKeywords = [
    'VaultExplorer',
    'UnlockSheet',
    'SplitFuseCallback',
    'SafSplitResolver',
    'ContainerEngine',
    'Cryptomator',
    'Gocryptfs',
    'Cryfs',
    'VeraCrypt',
    'Luks',
    'BitLocker',
    'VeLog',
    'FAT',
    'NTFS',
    'EXT4',
    'EXFAT',
    'E/',
    'F/',
  ];

  @override
  void initState() {
    super.initState();
    _scrollCtrl.addListener(_onScroll);
    _startStream();
  }

  @override
  void dispose() {
    _scrollCtrl.removeListener(_onScroll);
    _sub?.cancel();
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

  void _startStream() {
    _sub?.cancel();
    setState(() {
      _streamError = false;
      _lines.clear();
    });

    _sub = LogcatService.stream.listen(
      (line) {
        if (!mounted) return;
        setState(() => _lines.add(line));

        // Automatically maintain scroll at bottom unless user intentionally scrolled up
        if (!_userScrolledUp) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (_scrollCtrl.hasClients && !_userScrolledUp) {
              _scrollCtrl.jumpTo(_scrollCtrl.position.maxScrollExtent);
            }
          });
        }
      },
      onError: (_) {
        if (mounted) setState(() => _streamError = true);
      },
    );
  }

  bool _isLineAccepted(String line) {
    if (_filterMode == LogFilterMode.appOnly) {
      // 1. Drop noisy tags
      for (final noise in _noisyTags) {
        if (line.contains(noise)) return false;
      }
      // 2. Drop generic Flutter engine chatter unless it has app identifiers or errors
      final isGenericFlutter =
          RegExp(r'\b[DI]/Flutter\b').hasMatch(line) ||
          RegExp(r'\b[DI]/flutter\b').hasMatch(line);
      if (isGenericFlutter) {
        final hasAppKeyword = _appKeywords.any((k) => line.contains(k));
        if (!hasAppKeyword) return false;
      } else {
        // Must contain an app keyword or error tag
        final matchesApp = _appKeywords.any((k) => line.contains(k));
        if (!matchesApp) return false;
      }
    }

    if (_searchQuery.isNotEmpty) {
      if (!line.toLowerCase().contains(_searchQuery.toLowerCase())) {
        return false;
      }
    }

    return true;
  }

  List<String> get _filteredLines {
    return _lines.where(_isLineAccepted).toList();
  }

  Future<void> _clearLog() async {
    if (_clearing) return;
    setState(() => _clearing = true);

    try {
      await LogcatService.clear();
      if (!mounted) return;
      setState(() => _lines.clear());
      showAppSnackBar(
        context,
        message: context.l10n.logcatClearedMessage,
        tone: AppBannerTone.info,
        icon: Icons.delete_sweep_rounded,
      );
    } finally {
      if (mounted) setState(() => _clearing = false);
    }
  }

  Future<void> _saveLog() async {
    if (_saving) return;
    setState(() => _saving = true);

    try {
      final content = _filteredLines.isNotEmpty
          ? _filteredLines.join('\n')
          : (await LogcatService.captureSnapshot() ?? '');

      if (!mounted) return;
      if (content.isEmpty) {
        showAppSnackBar(
          context,
          message: context.l10n.logcatSaveErrorMessage,
          tone: AppBannerTone.error,
        );
        return;
      }

      final path = await LogcatService.saveToFile(content);
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
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _copyLog() async {
    final linesToCopy = _filteredLines;
    if (linesToCopy.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: linesToCopy.join('\n')));
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
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final filtered = _filteredLines;

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
                  hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.5)),
                  border: InputBorder.none,
                ),
                onChanged: (val) {
                  setState(() => _searchQuery = val.trim());
                  WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom(animate: false));
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
          // Search toggle
          IconButton(
            icon: Icon(_isSearching ? Icons.close_rounded : Icons.search_rounded),
            tooltip: _isSearching ? 'Close search' : 'Search',
            onPressed: () {
              setState(() {
                if (_isSearching) {
                  _isSearching = false;
                  _searchCtrl.clear();
                  _searchQuery = '';
                } else {
                  _isSearching = true;
                }
              });
            },
          ),
          // Copy
          IconButton(
            icon: const Icon(Icons.copy_rounded),
            tooltip: context.l10n.logcatCopyTooltip,
            onPressed: filtered.isEmpty ? null : _copyLog,
          ),
          // Clear
          IconButton(
            icon: const Icon(Icons.delete_sweep_rounded),
            tooltip: context.l10n.logcatClearTooltip,
            onPressed: _lines.isEmpty || _clearing ? null : _clearLog,
          ),
          // Save
          if (_saving)
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
              onPressed: filtered.isEmpty ? null : _saveLog,
            ),
        ],
      ),
      body: Column(
        children: [
          // Filter Tabs Bar
          _buildFilterBar(cs),
          // Log List or States
          Expanded(
            child: _streamError
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

  Widget _buildFilterBar(ColorScheme cs) {
    return Container(
      color: const Color(0xFF141414),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        children: [
          // App Only Filter Chip
          ChoiceChip(
            label: Text(context.l10n.logcatFilterAppOnly),
            selected: _filterMode == LogFilterMode.appOnly,
            selectedColor: cs.primary.withValues(alpha: 0.25),
            backgroundColor: const Color(0xFF222222),
            labelStyle: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: _filterMode == LogFilterMode.appOnly ? cs.primary : Colors.white70,
            ),
            side: BorderSide(
              color: _filterMode == LogFilterMode.appOnly
                  ? cs.primary.withValues(alpha: 0.6)
                  : Colors.transparent,
            ),
            onSelected: (selected) {
              if (selected) {
                setState(() => _filterMode = LogFilterMode.appOnly);
                WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom(animate: false));
              }
            },
          ),
          const SizedBox(width: 8),
          // All Logs Filter Chip
          ChoiceChip(
            label: Text(context.l10n.logcatFilterAll),
            selected: _filterMode == LogFilterMode.all,
            selectedColor: cs.primary.withValues(alpha: 0.25),
            backgroundColor: const Color(0xFF222222),
            labelStyle: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: _filterMode == LogFilterMode.all ? cs.primary : Colors.white70,
            ),
            side: BorderSide(
              color: _filterMode == LogFilterMode.all
                  ? cs.primary.withValues(alpha: 0.6)
                  : Colors.transparent,
            ),
            onSelected: (selected) {
              if (selected) {
                setState(() => _filterMode = LogFilterMode.all);
                WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom(animate: false));
              }
            },
          ),
          const Spacer(),
          // Line count indicator
          Text(
            '${_filteredLines.length} lines',
            style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.4)),
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
          Icon(Icons.receipt_long_rounded,
              size: 48, color: Colors.white.withValues(alpha: 0.3)),
          const SizedBox(height: 12),
          Text(
            context.l10n.logcatEmptyMessage,
            style: textTheme.bodyMedium
                ?.copyWith(color: Colors.white.withValues(alpha: 0.5)),
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
            Icon(Icons.error_outline_rounded,
                size: 48, color: cs.error.withValues(alpha: 0.8)),
            const SizedBox(height: 12),
            Text(
              context.l10n.logcatUnavailableMessage,
              textAlign: TextAlign.center,
              style: textTheme.bodyMedium
                  ?.copyWith(color: Colors.white.withValues(alpha: 0.7)),
            ),
            const SizedBox(height: 20),
            OutlinedButton.icon(
              onPressed: _startStream,
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
        return const Color(0xFFFF5555); // red
      case 'W':
        return const Color(0xFFFFB86C); // orange
      case 'I':
        return const Color(0xFF50FA7B); // green
      case 'D':
        return const Color(0xFF8BE9FD); // cyan
      case 'V':
        return Colors.white38;
      default:
        return Colors.white70;
    }
  }
}
