import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/api/vault_book_api.dart';
import 'package:vaultexplorer/core/api/vault_engine_events.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/providers/vault_engine_providers.dart';
import 'package:vaultexplorer/core/theme/app_theme.dart';
import 'package:vaultexplorer/core/widgets/common_widgets.dart';
import 'package:vaultexplorer/core/widgets/inputs/slider_setting_tile.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/data/services/book_reader_state_store.dart';
import 'package:vaultexplorer/features/browser/viewer/books/epub_style.dart';

/// Must match HTML_VIEWER_VIEW_TYPE in kotlin/.../htmlviewer/HtmlViewerPlugin.kt
/// (the e-book reader is that same locked-down WebView in "book mode").
const String _kHtmlViewerViewType = 'com.aeidolon.vaultexplorer/html_viewer';

typedef _BookLocation = ({int position, double fraction, String fragment});

/// In-app EPUB reader.
///
/// The book is a book session on the native side (see [VaultBookApi]); the
/// WebView asks that session for each chapter, stylesheet, image and font as it
/// needs them, so nothing is extracted to disk and nothing touches the
/// network. JavaScript stays off: an EPUB is a document, not an app.
///
/// The reading order (spine) plays the role a playlist plays in the media
/// viewer: previous/next chapter buttons, a progress readout, and a contents
/// list to jump anywhere. The reader owns the book session and closes it when
/// it goes away.
class EpubReaderScreen extends ConsumerStatefulWidget {
  final MountedContainer container;
  final String fallbackTitle;
  final String filePath;
  final String token;
  final EpubInfo info;

  const EpubReaderScreen({
    super.key,
    required this.container,
    required this.fallbackTitle,
    required this.filePath,
    required this.token,
    required this.info,
  });

  @override
  ConsumerState<EpubReaderScreen> createState() => _EpubReaderScreenState();
}

class _EpubReaderScreenState extends ConsumerState<EpubReaderScreen> {
  late final VaultBookApi _api;
  late final VaultEngineEvents _events;
  MethodChannel? _method;
  StreamSubscription<dynamic>? _eventSub;

  late final Map<String, int> _spineIndexByPath = {
    for (var i = 0; i < widget.info.spine.length; i++)
      widget.info.spine[i].path: i,
  };

  int _current = 0;
  bool _loading = true;
  bool _ready = false;
  bool _locked = false;
  bool _controlsVisible = true;
  double _fraction = 0;
  bool _paged = true;
  bool _javascriptEnabled = false;
  bool _atStart = true;
  bool _atEnd = false;
  int _chapterPage = 1;
  int _chapterPages = 1;
  double? _pendingRestoreFraction;
  Timer? _saveTimer;
  Timer? _hideControlsTimer;
  int? _tapPointer;
  Offset? _tapStart;
  List<BookReaderBookmark> _bookmarks = const [];
  Uint8List? _coverThumbnail;
  late final String _documentId = bookReaderStateStore.documentId(
    widget.container,
    widget.filePath,
  );
  int _textZoom = kEpubTextZoomDefault;
  EpubTheme? _theme;
  bool _rtl = false;
  EpubFontFace _fontFace = EpubFontFace.publisher;
  EpubTextAlignment _textAlignment = EpubTextAlignment.publisher;
  int _fontWeight = 400;
  double _lineHeight = 1.0;
  bool _pageMargins = true;
  bool _twoPageLandscape = false;
  bool _isLandscape = false;
  bool _sliderDragging = false;

  bool get _twoPageSpreadActive => _twoPageLandscape && _isLandscape;

  String get _title => widget.info.title.trim().isNotEmpty
      ? widget.info.title.trim()
      : widget.fallbackTitle;

  @override
  void initState() {
    super.initState();
    _api = ref.read(vaultBookApiProvider);
    _events = ref.read(vaultEngineEventsProvider);
    _events.addContainerLockedListener(_onContainerLocked);
    unawaited(_restoreState());
    unawaited(_loadCoverThumbnail());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final landscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;
    if (landscape == _isLandscape) return;
    _isLandscape = landscape;
    if (_ready) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_applyBookStyle());
      });
    }
  }

  Future<void> _loadCoverThumbnail() async {
    if (widget.info.coverPath.isEmpty ||
        widget.info.coverSize <= 0 ||
        widget.info.coverSize > 2 * 1024 * 1024) {
      return;
    }
    try {
      final bytes = await _api.readEntry(widget.token, widget.info.coverPath);
      if (!mounted || _locked) return;
      setState(() => _coverThumbnail = bytes);
    } catch (_) {
      // The cover is optional. Keep the reading flow available if it is malformed.
    }
  }

  Future<void> _restoreState() async {
    final saved = await bookReaderStateStore.load(_documentId);
    if (!mounted) return;
    final settings = saved.epubSettings;
    setState(() {
      _current = saved.position.clamp(0, widget.info.spine.length - 1).toInt();
      _fraction = saved.fraction;
      _paged = saved.mode != 'scroll';
      _bookmarks = saved.bookmarks
          .where(
            (bookmark) =>
                bookmark.position >= 0 &&
                bookmark.position < widget.info.spine.length,
          )
          .toList(growable: false);
      _pendingRestoreFraction = saved.fraction > 0 ? saved.fraction : null;
      _rtl = settings['rtl'] as bool? ?? widget.info.direction == 'rtl';
      _textZoom =
          ((settings['textZoom'] as num?)?.toInt() ?? kEpubTextZoomDefault)
              .clamp(kEpubTextZoomMin, kEpubTextZoomMax)
              .toInt();
      final savedTheme = settings['theme'];
      _theme = savedTheme is String
          ? EpubTheme.values.firstWhere(
              (value) => value.name == savedTheme,
              orElse: () => EpubTheme.light,
            )
          : null;
      _fontFace = EpubFontFace.values.firstWhere(
        (value) => value.name == settings['fontFace'],
        orElse: () => EpubFontFace.publisher,
      );
      _textAlignment = EpubTextAlignment.values.firstWhere(
        (value) => value.name == settings['textAlignment'],
        orElse: () => EpubTextAlignment.publisher,
      );
      _fontWeight = (settings['fontWeight'] as num?)?.toInt() ?? 400;
      _lineHeight = (settings['lineHeight'] as num?)?.toDouble() ?? 1.0;
      _pageMargins = settings['pageMargins'] as bool? ?? true;
      _twoPageLandscape = settings['twoPageLandscape'] as bool? ?? false;
      _ready = true;
    });
    _scheduleControlsHide();
  }

  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 700), () {
      if (mounted) unawaited(_saveState());
    });
  }

  void _scheduleControlsHide() {
    _hideControlsTimer?.cancel();
    _hideControlsTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _controlsVisible = false);
    });
  }

  void _toggleReaderControls() {
    _hideControlsTimer?.cancel();
    if (_controlsVisible) {
      setState(() => _controlsVisible = false);
    } else {
      setState(() => _controlsVisible = true);
      _scheduleControlsHide();
    }
  }

  void _onReaderPointerDown(PointerDownEvent event) {
    _tapPointer = event.pointer;
    _tapStart = event.position;
  }

  void _onReaderPointerMove(PointerMoveEvent event) {
    final start = _tapStart;
    if (event.pointer == _tapPointer &&
        start != null &&
        (event.position - start).distance > 18) {
      _tapStart = null;
    }
  }

  void _onReaderPointerUp(PointerUpEvent event) {
    final start = _tapStart;
    final isTap =
        event.pointer == _tapPointer &&
        start != null &&
        (event.position - start).distance <= 18;
    _tapPointer = null;
    _tapStart = null;
    if (isTap) _toggleReaderControls();
  }

  Future<void> _saveState() => bookReaderStateStore.save(
    _documentId,
    BookReaderState(
      position: _current,
      fraction: _fraction,
      mode: _paged ? 'paged' : 'scroll',
      bookmarks: _bookmarks,
      epubSettings: {
        'rtl': _rtl,
        'textZoom': _textZoom,
        'theme': (_theme ?? EpubTheme.light).name,
        'fontFace': _fontFace.name,
        'fontWeight': _fontWeight,
        'lineHeight': _lineHeight,
        'textAlignment': _textAlignment.name,
        'pageMargins': _pageMargins,
        'twoPageLandscape': _twoPageLandscape,
      },
    ),
  );

  @override
  void dispose() {
    _events.removeContainerLockedListener(_onContainerLocked);
    _eventSub?.cancel();
    _saveTimer?.cancel();
    _hideControlsTimer?.cancel();
    unawaited(_saveState());
    unawaited(_api.close(widget.token));
    super.dispose();
  }

  void _onContainerLocked(int volId) {
    if (volId != widget.container.volId || !mounted) return;
    // Dropping the WebView (below) is what stops it reading the book.
    setState(() {
      _locked = true;
      _coverThumbnail = null;
    });
  }

  void _onPlatformViewCreated(int id) {
    final method = MethodChannel('$_kHtmlViewerViewType/$id');
    final events = EventChannel('$_kHtmlViewerViewType/events/$id');
    _eventSub = events.receiveBroadcastStream().listen(
      _onEvent,
      onError: (_) {},
    );
    setState(() => _method = method);
  }

  void _onEvent(dynamic raw) {
    if (raw is! Map || !mounted) return;
    switch (raw['event']) {
      case 'pageFinished':
        final index = _spineIndexByPath[(raw['entry'] as String?) ?? ''];
        setState(() {
          _loading = false;
          if (index != null) _current = index;
        });
        if (_pendingRestoreFraction != null) {
          final fraction = _pendingRestoreFraction!;
          _pendingRestoreFraction = null;
          unawaited(_invoke('setScrollFraction', {'fraction': fraction}));
        }
        _scheduleSave();
      case 'scroll':
        setState(() {
          _fraction = (raw['fraction'] as num?)?.toDouble() ?? 0;
          _chapterPage = (raw['page'] as num?)?.toInt() ?? 1;
          _chapterPages = (raw['pageCount'] as num?)?.toInt() ?? 1;
          _atStart = raw['atStart'] as bool? ?? false;
          _atEnd = raw['atEnd'] as bool? ?? false;
        });
        _scheduleSave();
      case 'chapterEdge':
        _onChapterEdge((raw['direction'] as num?)?.toInt() ?? 0);
      case 'error':
        setState(() => _loading = false);
    }
  }

  Future<void> _invoke(String method, [Object? arguments]) async {
    try {
      await _method?.invokeMethod<Object?>(method, arguments);
    } on PlatformException {
      // The view is going away; nothing useful to do.
    } on MissingPluginException {
      // Same.
    }
  }

  /// Opens spine item [index]. With [atEnd] the chapter opens on its last page
  /// (paging backwards out of the next chapter) instead of its first.
  Future<void> _openChapter(
    int index, {
    String fragment = '',
    double fraction = 0,
    bool atEnd = false,
  }) async {
    if (index < 0 || index >= widget.info.spine.length) return;
    setState(() {
      _current = index;
      _loading = true;
      _fraction = atEnd ? 1 : fraction;
      _atStart = !atEnd && fraction <= 0;
      _atEnd = atEnd;
      _pendingRestoreFraction = !atEnd && fraction > 0 ? fraction : null;
    });
    await _invoke('loadEntry', {
      'entry': widget.info.spine[index].path,
      'fragment': fragment,
      'atEnd': atEnd,
    });
  }

  /// The reader swiped or tapped past the first/last page of the chapter:
  /// carry on into the neighbouring one, like turning the page of a book.
  /// [direction] is in reading order (+1 next, -1 previous).
  void _onChapterEdge(int direction) {
    if (direction == 0 || _loading) return;
    final target = _current + direction;
    if (target < 0 || target >= widget.info.spine.length) return;
    unawaited(_openChapter(target, atEnd: direction < 0));
  }

  Future<void> _turnPage(int direction) async {
    await _invoke('turnPage', {'direction': direction});
  }

  Future<void> _toggleScripts() async {
    if (!_javascriptEnabled) {
      final confirmed = await showAppConfirmDialog(
        context,
        title: context.l10n.enableJavaScriptDialogTitle,
        message: context.l10n.enableJavaScriptDialogMessage,
        confirmLabel: context.l10n.enable,
      );
      if (!confirmed || !mounted) return;
    }
    final enabled = !_javascriptEnabled;
    _pendingRestoreFraction = _fraction > 0 ? _fraction : null;
    setState(() => _javascriptEnabled = enabled);
    await _invoke('setJavaScriptEnabled', {'enabled': enabled});
  }

  Future<void> _setPaged(bool paged) async {
    if (_paged == paged) return;
    setState(() => _paged = paged);
    await _applyBookStyle();
  }

  Future<void> _toggleBookmark() async {
    setState(() {
      if (_bookmarks.any(
        (b) => b.position == _current && (b.fraction - _fraction).abs() < .035,
      )) {
        _bookmarks = _bookmarks
            .where(
              (b) =>
                  !(b.position == _current &&
                      (b.fraction - _fraction).abs() < .035),
            )
            .toList(growable: false);
      } else {
        _bookmarks = [..._bookmarks, BookReaderBookmark(_current, _fraction)];
      }
    });
    await _saveState();
  }

  String _chapterTitle(int index) {
    final path = widget.info.spine[index].path;
    for (final toc in widget.info.toc) {
      if (toc.path == path) return toc.title;
    }
    return context.l10n.epubChapterFallbackTitle(index + 1);
  }

  Future<void> _setTextZoom(int percent) async {
    final next = percent.clamp(kEpubTextZoomMin, kEpubTextZoomMax).toInt();
    if (next == _textZoom) return;
    setState(() => _textZoom = next);
    await _invoke('setTextZoom', {'percent': next});
    _scheduleSave();
  }

  Future<void> _setTheme(EpubTheme theme) async {
    if (theme == _theme) return;
    setState(() => _theme = theme);
    await _applyBookStyle();
  }

  Future<void> _applyBookStyle() async {
    _pendingRestoreFraction = _fraction > 0 ? _fraction : null;
    final theme = _theme ?? EpubTheme.light;
    await _invoke('setBookStyle', {
      'css': epubStyleCss(
        theme,
        fixedLayout: widget.info.fixedLayout,
        paged: _paged,
        rtl: _rtl,
        fontFace: _fontFace,
        fontWeight: _fontWeight,
        lineHeight: _lineHeight,
        textAlignment: _textAlignment,
        pageMargins: _pageMargins,
        twoPageLandscape: _twoPageSpreadActive,
      ),
      'backgroundColor': epubBackgroundFor(theme).toARGB32(),
      'paged': _paged,
      'fixedLayout': widget.info.fixedLayout,
      'rtl': _rtl,
      'twoPageLandscape': _twoPageSpreadActive,
    });
    _scheduleSave();
  }

  Future<void> _showContentsAndBookmarks() async {
    final l10n = context.l10n;
    final entries = widget.info.toc.isNotEmpty
        ? widget.info.toc
        : [
            for (var i = 0; i < widget.info.spine.length; i++)
              EpubTocEntry(
                title: l10n.epubChapterFallbackTitle(i + 1),
                path: widget.info.spine[i].path,
                fragment: '',
                level: 0,
              ),
          ];
    final picked = await showModalBottomSheet<_BookLocation>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => DefaultTabController(
        length: 2,
        child: StatefulBuilder(
          builder: (context, setSheetState) {
            final cs = context.colors;
            final textTheme = context.typography;
            const tilePadding = EdgeInsets.symmetric(horizontal: 16);

            return SafeArea(
              child: SizedBox(
                height: MediaQuery.sizeOf(context).height * .78,
                child: Column(
                  children: [
                    TabBar(
                      tabs: [
                        Tab(text: l10n.contentsLabel),
                        Tab(text: l10n.bookmarkBarSectionHeader),
                      ],
                    ),
                    Expanded(
                      child: TabBarView(
                        children: [
                          ListView.builder(
                            padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
                            itemCount: entries.length,
                            itemBuilder: (context, i) {
                              final entry = entries[i];
                              final index = _spineIndexByPath[entry.path];
                              final selected = index == _current;
                              return ListTile(
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(
                                    AppRadius.md,
                                  ),
                                ),
                                contentPadding: EdgeInsetsDirectional.only(
                                  start: 16.0 + 16.0 * entry.level.clamp(0, 5),
                                  end: 16,
                                ),
                                selected: selected,
                                selectedColor: cs.primary,
                                selectedTileColor: cs.primaryContainer
                                    .withValues(alpha: 0.5),
                                title: Text(
                                  entry.title,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: textTheme.bodyMedium?.copyWith(
                                    fontWeight: selected
                                        ? FontWeight.bold
                                        : FontWeight.w500,
                                  ),
                                ),
                                onTap: index == null
                                    ? null
                                    : () => Navigator.of(sheetContext).pop((
                                        position: index,
                                        fraction: 0.0,
                                        fragment: entry.fragment,
                                      )),
                              );
                            },
                          ),
                          ListView(
                            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                            children: [
                              SectionCard(
                                children: [
                                  ListTile(
                                    contentPadding: tilePadding,
                                    leading: Icon(
                                      Icons.bookmark_add_rounded,
                                      color: cs.primary,
                                    ),
                                    title: Text(
                                      l10n.bookmarkAction,
                                      style: textTheme.bodyMedium?.copyWith(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    subtitle: Text(
                                      _chapterTitle(_current),
                                      style: textTheme.bodySmall?.copyWith(
                                        color: cs.onSurfaceVariant,
                                      ),
                                    ),
                                    onTap: () async {
                                      await _toggleBookmark();
                                      setSheetState(() {});
                                    },
                                  ),
                                  for (final bookmark in _bookmarks)
                                    ListTile(
                                      contentPadding: tilePadding,
                                      leading: Icon(
                                        Icons.bookmark_rounded,
                                        color: context.semanticColors.bookmark,
                                      ),
                                      title: Text(
                                        _chapterTitle(bookmark.position),
                                        style: textTheme.bodyMedium?.copyWith(
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      subtitle: Text(
                                        '${(bookmark.fraction * 100).round()}%',
                                        style: textTheme.bodySmall?.copyWith(
                                          color: cs.onSurfaceVariant,
                                        ),
                                      ),
                                      onTap: () =>
                                          Navigator.of(sheetContext).pop((
                                            position: bookmark.position,
                                            fraction: bookmark.fraction,
                                            fragment: '',
                                          )),
                                    ),
                                ],
                              ),
                              if (_bookmarks.isEmpty)
                                Padding(
                                  padding: const EdgeInsets.all(24),
                                  child: Center(
                                    child: Text(
                                      l10n.noBookmarksYet,
                                      style: textTheme.bodyMedium?.copyWith(
                                        color: cs.onSurfaceVariant,
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
    if (picked == null || !mounted) return;
    await _openChapter(
      picked.position,
      fraction: picked.fraction,
      fragment: picked.fragment,
    );
  }

  /// Reader settings, built from the same pieces as the app's settings
  /// screens (section headers, grouped cards, option pickers, slider tiles)
  /// so it follows the active theme instead of carrying its own palette.
  Future<void> _showAppearance() => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    // No scrim and no sheet surface of its own: while a slider is dragged the
    // whole panel fades so the book underneath is readable.
    barrierColor: Colors.transparent,
    backgroundColor: Colors.transparent,
    elevation: 0,
    builder: (sheetContext) => StatefulBuilder(
      builder: (context, setSheetState) {
        final l10n = context.l10n;
        final cs = context.colors;
        final textTheme = context.typography;
        final theme = _theme ?? EpubTheme.light;

        // Runs [action], then rebuilds the sheet so every control shows the
        // new value.
        Future<void> refresh(Future<void> Function() action) async {
          await action();
          if (sheetContext.mounted) setSheetState(() {});
        }

        Widget switchTile({
          required IconData icon,
          required String title,
          required bool value,
          required ValueChanged<bool> onChanged,
        }) => SwitchListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16),
          value: value,
          onChanged: onChanged,
          secondary: Icon(icon, color: cs.primary),
          title: Text(
            title,
            style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
        );

        void setDragging(bool dragging) {
          _sliderDragging = dragging;
          setSheetState(() {});
        }

        return AnimatedOpacity(
          opacity: _sliderDragging ? .22 : 1,
          duration: const Duration(milliseconds: 150),
          child: Material(
            color: cs.surfaceContainerLow,
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(
                top: Radius.circular(AppRadius.sheet),
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * .85,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 32,
                    height: 4,
                    margin: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: cs.onSurfaceVariant.withValues(alpha: .4),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  Flexible(
                    child: SafeArea(
                      top: false,
                      child: ListView(
                        shrinkWrap: true,
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                        children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
                  child: Text(
                    'Reader settings',
                    style: textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SectionHeader('Page'),
                SectionCard(
                  children: [
                    OptionPickerTile<bool>(
                      label: 'Page flipping',
                      prefixIcon: Icons.swap_horiz_rounded,
                      value: _paged,
                      options: [
                        const SelectOption(value: true, label: 'Horizontal'),
                        SelectOption(
                          value: false,
                          label: l10n.playlistScrollVerticalContinuousLabel,
                        ),
                      ],
                      onChanged: (value) =>
                          unawaited(refresh(() => _setPaged(value))),
                    ),
                    OptionPickerTile<bool>(
                      label: 'Text direction',
                      prefixIcon: _rtl
                          ? Icons.format_textdirection_r_to_l_rounded
                          : Icons.format_textdirection_l_to_r_rounded,
                      value: _rtl,
                      options: [
                        SelectOption(
                          value: false,
                          label: l10n.comicReadingDirectionLtr,
                        ),
                        SelectOption(
                          value: true,
                          label: l10n.comicReadingDirectionRtl,
                        ),
                      ],
                      onChanged: (value) {
                        if (value == _rtl) return;
                        setState(() => _rtl = value);
                        unawaited(refresh(_applyBookStyle));
                      },
                    ),
                    OptionPickerTile<EpubTheme>(
                      label: 'Color mode',
                      prefixIcon: Icons.palette_rounded,
                      value: theme,
                      options: [
                        for (final option in EpubTheme.values)
                          SelectOption(
                            value: option,
                            label: _themeLabel(l10n, option),
                          ),
                      ],
                      onChanged: (value) =>
                          unawaited(refresh(() => _setTheme(value))),
                    ),
                    switchTile(
                      icon: Icons.menu_book_rounded,
                      title: 'Two pages in landscape orientation',
                      value: _twoPageLandscape,
                      onChanged: (value) {
                        setState(() => _twoPageLandscape = value);
                        setSheetState(() {});
                        unawaited(_applyBookStyle());
                      },
                    ),
                    switchTile(
                      icon: Icons.border_outer_rounded,
                      title: 'Page margins',
                      value: _pageMargins,
                      onChanged: (value) {
                        setState(() => _pageMargins = value);
                        setSheetState(() {});
                        unawaited(_applyBookStyle());
                      },
                    ),
                  ],
                ),
                const SectionHeader('Text'),
                SectionCard(
                  children: [
                    OptionPickerTile<EpubFontFace>(
                      label: 'Font face',
                      prefixIcon: Icons.font_download_rounded,
                      value: _fontFace,
                      options: const [
                        SelectOption(
                          value: EpubFontFace.publisher,
                          label: 'Publisher default',
                        ),
                        SelectOption(
                          value: EpubFontFace.serif,
                          label: 'Serif',
                        ),
                        SelectOption(
                          value: EpubFontFace.sansSerif,
                          label: 'Sans serif',
                        ),
                        SelectOption(
                          value: EpubFontFace.monospace,
                          label: 'Monospace',
                        ),
                      ],
                      onChanged: (value) {
                        setState(() => _fontFace = value);
                        unawaited(refresh(_applyBookStyle));
                      },
                    ),
                    SliderSettingTile(
                      label: l10n.epubTextSize,
                      prefixIcon: Icons.format_size_rounded,
                      value: _textZoom,
                      min: kEpubTextZoomMin,
                      max: kEpubTextZoomMax,
                      divisions:
                          (kEpubTextZoomMax - kEpubTextZoomMin) ~/
                          kEpubTextZoomStep,
                      valueLabel: (value) => '$value%',
                      onDragChanged: setDragging,
                      onChangedLive: (value) => unawaited(_setTextZoom(value)),
                      onChanged: (_) => setSheetState(() {}),
                    ),
                    SliderSettingTile(
                      label: 'Font thickness',
                      prefixIcon: Icons.format_bold_rounded,
                      value: _fontWeight,
                      min: 300,
                      max: 700,
                      divisions: 4,
                      valueLabel: (value) => '$value',
                      onDragChanged: setDragging,
                      onChangedLive: (value) {
                        setState(() => _fontWeight = value);
                        unawaited(_applyBookStyle());
                      },
                      onChanged: (_) => setSheetState(() {}),
                    ),
                    SliderSettingTile(
                      label: 'Line spacing',
                      prefixIcon: Icons.format_line_spacing_rounded,
                      value: (_lineHeight * 100).round(),
                      min: 100,
                      max: 200,
                      divisions: 10,
                      valueLabel: (value) => '$value%',
                      onDragChanged: setDragging,
                      onChangedLive: (value) {
                        setState(() => _lineHeight = value / 100);
                        unawaited(_applyBookStyle());
                      },
                      onChanged: (_) => setSheetState(() {}),
                    ),
                    OptionPickerTile<EpubTextAlignment>(
                      label: 'Text align',
                      prefixIcon: Icons.format_align_left_rounded,
                      value: _textAlignment,
                      options: const [
                        SelectOption(
                          value: EpubTextAlignment.publisher,
                          label: 'Publisher default',
                        ),
                        SelectOption(
                          value: EpubTextAlignment.left,
                          label: 'Left',
                        ),
                        SelectOption(
                          value: EpubTextAlignment.justified,
                          label: 'Justified',
                        ),
                        SelectOption(
                          value: EpubTextAlignment.center,
                          label: 'Center',
                        ),
                        SelectOption(
                          value: EpubTextAlignment.right,
                          label: 'Right',
                        ),
                      ],
                      onChanged: (value) {
                        setState(() => _textAlignment = value);
                        unawaited(refresh(_applyBookStyle));
                      },
                    ),
                  ],
                ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    ),
  );

  String _themeLabel(AppLocalizations l10n, EpubTheme theme) => switch (theme) {
    EpubTheme.original => l10n.epubThemeOriginal,
    EpubTheme.light => l10n.skinLight,
    EpubTheme.dark => l10n.skinDark,
    EpubTheme.sepia => l10n.textEditorBackgroundSepia,
  };

  Widget _readerChrome(Widget child) => AnimatedOpacity(
    opacity: _controlsVisible ? 1 : 0,
    duration: const Duration(milliseconds: 220),
    child: IgnorePointer(ignoring: !_controlsVisible, child: child),
  );

  @override
  Widget build(BuildContext context) {
    if (_locked) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: SizedBox.expand(),
      );
    }

    if (!_ready) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final l10n = context.l10n;
    final theme = _theme ??= Theme.of(context).brightness == Brightness.dark
        ? EpubTheme.dark
        : EpubTheme.light;
    final chapters = widget.info.spine.length;
    final overall = chapters == 0
        ? 0.0
        : ((_current + _fraction) / chapters).clamp(0.0, 1.0).toDouble();

    final appBar = AppBar(
      backgroundColor: const Color(0xF0121212),
      foregroundColor: Colors.white,
      title: Row(
        children: [
          if (_coverThumbnail != null) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: Image.memory(
                _coverThumbnail!,
                width: 28,
                height: 38,
                fit: BoxFit.cover,
                cacheWidth: 84,
                gaplessPlayback: true,
              ),
            ),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: Text(_title, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
      actions: [
        PopupMenuButton<String>(
          tooltip: l10n.moreOptionsTooltip,
          icon: const Icon(Icons.more_vert),
          onSelected: (_) => unawaited(_toggleScripts()),
          itemBuilder: (context) => [
            PopupMenuItem(
              value: 'scripts',
              child: Row(
                children: [
                  Icon(
                    _javascriptEnabled
                        ? Icons.code_off_rounded
                        : Icons.code_rounded,
                    size: AppIconSize.small,
                    color: context.colors.onSurfaceVariant,
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Text(
                    _javascriptEnabled
                        ? l10n.disableJavaScriptMenu
                        : l10n.enableJavaScriptMenu,
                  ),
                ],
              ),
            ),
          ],
        ),
        IconButton(
          tooltip: context.l10n.bookmarkAction,
          icon: Icon(
            _bookmarks.any(
                  (b) =>
                      b.position == _current &&
                      (b.fraction - _fraction).abs() < .035,
                )
                ? Icons.bookmark
                : Icons.bookmark_add_outlined,
          ),
          onPressed: _toggleBookmark,
        ),
        IconButton(
          tooltip: l10n.contentsLabel,
          icon: const Icon(Icons.local_library_outlined),
          onPressed: _showContentsAndBookmarks,
        ),
        IconButton(
          tooltip: l10n.epubTextSize,
          icon: const Icon(Icons.text_fields),
          onPressed: _showAppearance,
        ),
      ],
    );

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(
              child: Listener(
                behavior: HitTestBehavior.translucent,
                onPointerDown: _onReaderPointerDown,
                onPointerMove: _onReaderPointerMove,
                onPointerUp: _onReaderPointerUp,
                onPointerCancel: (_) {
                  _tapPointer = null;
                  _tapStart = null;
                },
                child: AndroidView(
                  viewType: _kHtmlViewerViewType,
                  creationParams: <String, Object?>{
                    'volId': widget.container.volId,
                    'htmlPath': '',
                    'javaScriptEnabled': false,
                    'bookToken': widget.token,
                    'bookEntry': widget.info.spine[_current].path,
                    'bookCss': epubStyleCss(
                      theme,
                      fixedLayout: widget.info.fixedLayout,
                      paged: _paged,
                      rtl: _rtl,
                      fontFace: _fontFace,
                      fontWeight: _fontWeight,
                      lineHeight: _lineHeight,
                      textAlignment: _textAlignment,
                      pageMargins: _pageMargins,
                      twoPageLandscape: _twoPageSpreadActive,
                    ),
                    'bookPagedMode': _paged,
                    'bookFixedLayout': widget.info.fixedLayout,
                    'bookRtl': _rtl,
                    'bookTwoPageLandscape': _twoPageSpreadActive,
                    'textZoom': _textZoom,
                    'backgroundColor': epubBackgroundFor(theme).toARGB32(),
                  },
                  creationParamsCodec: const StandardMessageCodec(),
                  onPlatformViewCreated: _onPlatformViewCreated,
                ),
              ),
            ),
            if (_loading)
              const Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: LinearProgressIndicator(),
              ),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: _readerChrome(
                SizedBox(height: kToolbarHeight, child: appBar),
              ),
            ),
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: _readerChrome(
                Material(
                  color: const Color(0xF0121212),
                  child: SizedBox(
                    height: 62,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Row(
                        children: [
                          IconButton(
                            tooltip: l10n.previousTooltip,
                            color: Colors.white,
                            icon: const Icon(Icons.chevron_left),
                            onPressed: _paged
                                ? (_current > 0 || !_atStart
                                      ? () => _turnPage(-1)
                                      : null)
                                : (_current > 0
                                      ? () => _openChapter(_current - 1)
                                      : null),
                          ),
                          Expanded(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                LinearProgressIndicator(
                                  value: _paged ? _fraction : overall,
                                  backgroundColor: Colors.white24,
                                  color: const Color(0xFF8FC8D0),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  _paged
                                      ? '$_chapterPage / $_chapterPages'
                                      : '${_current + 1} / $chapters',
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            tooltip: l10n.nextTooltip,
                            color: Colors.white,
                            icon: const Icon(Icons.chevron_right),
                            onPressed: _paged
                                ? (_current < chapters - 1 || !_atEnd
                                      ? () => _turnPage(1)
                                      : null)
                                : (_current < chapters - 1
                                      ? () => _openChapter(_current + 1)
                                      : null),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}