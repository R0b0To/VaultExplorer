import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/api/vault_book_api.dart';
import 'package:vaultexplorer/core/api/vault_engine_events.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/providers/vault_engine_providers.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/features/browser/viewer/books/epub_style.dart';

/// Must match HTML_VIEWER_VIEW_TYPE in kotlin/.../htmlviewer/HtmlViewerPlugin.kt
/// (the e-book reader is that same locked-down WebView in "book mode").
const String _kHtmlViewerViewType = 'com.aeidolon.vaultexplorer/html_viewer';

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
  final String token;
  final EpubInfo info;

  const EpubReaderScreen({
    super.key,
    required this.container,
    required this.fallbackTitle,
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
    for (var i = 0; i < widget.info.spine.length; i++) widget.info.spine[i].path: i,
  };

  int _current = 0;
  bool _loading = true;
  bool _locked = false;
  double _fraction = 0;
  int _textZoom = kEpubTextZoomDefault;
  EpubTheme? _theme;

  String get _title =>
      widget.info.title.trim().isNotEmpty ? widget.info.title.trim() : widget.fallbackTitle;

  @override
  void initState() {
    super.initState();
    _api = ref.read(vaultBookApiProvider);
    _events = ref.read(vaultEngineEventsProvider);
    _events.addContainerLockedListener(_onContainerLocked);
  }

  @override
  void dispose() {
    _events.removeContainerLockedListener(_onContainerLocked);
    _eventSub?.cancel();
    unawaited(_api.close(widget.token));
    super.dispose();
  }

  void _onContainerLocked(int volId) {
    if (volId != widget.container.volId || !mounted) return;
    // Dropping the WebView (below) is what stops it reading the book.
    setState(() => _locked = true);
  }

  void _onPlatformViewCreated(int id) {
    final method = MethodChannel('$_kHtmlViewerViewType/$id');
    final events = EventChannel('$_kHtmlViewerViewType/events/$id');
    _eventSub = events.receiveBroadcastStream().listen(_onEvent, onError: (_) {});
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
      case 'scroll':
        setState(() => _fraction = (raw['fraction'] as num?)?.toDouble() ?? 0);
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

  Future<void> _openChapter(int index, {String fragment = ''}) async {
    if (index < 0 || index >= widget.info.spine.length) return;
    setState(() {
      _current = index;
      _loading = true;
      _fraction = 0;
    });
    await _invoke('loadEntry', {
      'entry': widget.info.spine[index].path,
      'fragment': fragment,
    });
  }

  Future<void> _setTextZoom(int percent) async {
    final next = percent.clamp(kEpubTextZoomMin, kEpubTextZoomMax);
    if (next == _textZoom) return;
    setState(() => _textZoom = next);
    await _invoke('setTextZoom', {'percent': next});
  }

  Future<void> _setTheme(EpubTheme theme) async {
    if (theme == _theme) return;
    setState(() => _theme = theme);
    await _invoke('setBookStyle', {
      'css': epubStyleCss(theme),
      'backgroundColor': epubBackgroundFor(theme).toARGB32(),
    });
  }

  Future<void> _showContents() async {
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
    final picked = await showModalBottomSheet<EpubTocEntry>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        maxChildSize: 0.95,
        builder: (context, scroll) => ListView.builder(
          controller: scroll,
          itemCount: entries.length,
          itemBuilder: (context, i) {
            final entry = entries[i];
            return ListTile(
              contentPadding: EdgeInsetsDirectional.only(
                start: 16.0 + 16.0 * entry.level.clamp(0, 5),
                end: 16,
              ),
              selected: _spineIndexByPath[entry.path] == _current,
              title: Text(entry.title, maxLines: 2, overflow: TextOverflow.ellipsis),
              onTap: () => Navigator.of(sheetContext).pop(entry),
            );
          },
        ),
      ),
    );
    if (picked == null || !mounted) return;
    final index = _spineIndexByPath[picked.path];
    if (index != null) await _openChapter(index, fragment: picked.fragment);
  }

  Future<void> _showAppearance(EpubTheme currentTheme) {
    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) {
          final l10n = context.l10n;
          final theme = _theme ?? currentTheme;
          return Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.epubTextSize, style: Theme.of(context).textTheme.titleSmall),
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.text_decrease),
                      onPressed: _textZoom > kEpubTextZoomMin
                          ? () async {
                              await _setTextZoom(_textZoom - kEpubTextZoomStep);
                              setSheetState(() {});
                            }
                          : null,
                    ),
                    Expanded(
                      child: Center(child: Text('$_textZoom%')),
                    ),
                    IconButton(
                      icon: const Icon(Icons.text_increase),
                      onPressed: _textZoom < kEpubTextZoomMax
                          ? () async {
                              await _setTextZoom(_textZoom + kEpubTextZoomStep);
                              setSheetState(() {});
                            }
                          : null,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    for (final option in EpubTheme.values)
                      ChoiceChip(
                        label: Text(_themeLabel(l10n, option)),
                        selected: theme == option,
                        onSelected: (_) async {
                          await _setTheme(option);
                          setSheetState(() {});
                        },
                      ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  String _themeLabel(AppLocalizations l10n, EpubTheme theme) => switch (theme) {
        EpubTheme.original => l10n.epubThemeOriginal,
        EpubTheme.light => l10n.skinLight,
        EpubTheme.dark => l10n.skinDark,
        EpubTheme.sepia => l10n.textEditorBackgroundSepia,
      };

  @override
  Widget build(BuildContext context) {
    if (_locked) {
      return const Scaffold(backgroundColor: Colors.black, body: SizedBox.expand());
    }

    final l10n = context.l10n;
    final theme = _theme ??=
        Theme.of(context).brightness == Brightness.dark ? EpubTheme.dark : EpubTheme.light;
    final chapters = widget.info.spine.length;
    final overall = chapters == 0 ? 0.0 : ((_current + _fraction) / chapters).clamp(0.0, 1.0);

    return Scaffold(
      appBar: AppBar(
        title: Text(_title, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: l10n.contentsLabel,
            icon: const Icon(Icons.toc),
            onPressed: _showContents,
          ),
          IconButton(
            tooltip: l10n.epubTextSize,
            icon: const Icon(Icons.text_fields),
            onPressed: () => _showAppearance(theme),
          ),
        ],
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: AndroidView(
              viewType: _kHtmlViewerViewType,
              creationParams: <String, Object?>{
                'volId': widget.container.volId,
                'htmlPath': '',
                'javaScriptEnabled': false,
                'bookToken': widget.token,
                'bookEntry': widget.info.spine[_current].path,
                'bookCss': epubStyleCss(theme),
                'textZoom': _textZoom,
                'backgroundColor': epubBackgroundFor(theme).toARGB32(),
              },
              creationParamsCodec: const StandardMessageCodec(),
              onPlatformViewCreated: _onPlatformViewCreated,
            ),
          ),
          if (_loading)
            const Positioned(top: 0, left: 0, right: 0, child: LinearProgressIndicator()),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            children: [
              IconButton(
                tooltip: l10n.previousTooltip,
                icon: const Icon(Icons.chevron_left),
                onPressed: _current > 0 ? () => _openChapter(_current - 1) : null,
              ),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    LinearProgressIndicator(value: overall),
                    const SizedBox(height: 4),
                    Text(
                      '${_current + 1} / $chapters',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: l10n.nextTooltip,
                icon: const Icon(Icons.chevron_right),
                onPressed:
                    _current < chapters - 1 ? () => _openChapter(_current + 1) : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
