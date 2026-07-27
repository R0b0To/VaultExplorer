import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/data/services/app_settings_service.dart';
import 'package:vaultexplorer/core/widgets/common_widgets.dart';

/// Must match HTML_VIEWER_VIEW_TYPE in
/// kotlin/.../htmlviewer/HtmlViewerPlugin.kt
const String _kHtmlViewerViewType = 'com.aeidolon.vaultexplorer/html_viewer';

/// In-app viewer for `.html`/`.htm` files and their local assets
/// (css/js/images/fonts) found alongside them in the vault.
///
/// This is a *local-only* viewer: the underlying WebView has all real
/// network access disabled, and every request it makes — including the
/// page itself — is served in-process from decrypted vault bytes. Nothing
/// ever leaves the device and nothing is ever written to plaintext disk.
class HtmlViewerScreen extends StatefulWidget {
  final MountedContainer container;
  final String filePath;

  const HtmlViewerScreen({
    super.key,
    required this.container,
    required this.filePath,
  });

  @override
  State<HtmlViewerScreen> createState() => _HtmlViewerScreenState();
}

class _HtmlViewerScreenState extends State<HtmlViewerScreen> {
  MethodChannel? _method;
  StreamSubscription<dynamic>? _eventSub;

  bool _isLoading = true;
  bool _hasError = false;
  String _errorMessage = '';
  String _title = '';
  bool _canGoBack = false;
  bool _canGoForward = false;
  bool _jsEnabled = false;
  bool _isFullscreen = false;
  bool _isSettingsLoaded = false;
  String get _fileName => widget.filePath.split('/').last;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final settings = await AppSettingsService.loadSettings();
    if (mounted) {
      setState(() {
        _jsEnabled = settings.htmlEnableJavaScript;
        _isSettingsLoaded = true;
      });
    }
  }

  void _onPlatformViewCreated(int id) {
    final method = MethodChannel('$_kHtmlViewerViewType/$id');
    final events = EventChannel('$_kHtmlViewerViewType/events/$id');
    _eventSub = events.receiveBroadcastStream().listen(_onEvent, onError: (_) {});
    setState(() => _method = method);
  }

  void _onEvent(dynamic raw) {
    if (raw is! Map) return;
    if (!mounted) return;
    switch (raw['event']) {
      case 'pageFinished':
        setState(() {
          _isLoading = false;
          _hasError = false;
          _title = (raw['title'] as String?) ?? '';
          _canGoBack = raw['canGoBack'] as bool? ?? false;
          _canGoForward = raw['canGoForward'] as bool? ?? false;
        });
      case 'error':
        setState(() {
          _isLoading = false;
          _hasError = true;
          _errorMessage = (raw['message'] as String?) ?? 'Failed to load file';
        });
    }
  }

 Future<void> _toggleJavaScript() async {
    if (!_jsEnabled) {
      final confirm = await showAppConfirmDialog(
        context,
        title: 'Enable JavaScript?',
        message: 'The page will be allowed to run its own local scripts. '
            'It still has no network access — nothing in this vault can be '
            'sent or received over the internet.',
        confirmLabel: 'Enable',
      );
      if (!confirm) return;
    }
    final enabled = !_jsEnabled;
    setState(() {
      _jsEnabled = enabled;
      _isLoading = true;
    });
    final settings = await AppSettingsService.loadSettings();
    await AppSettingsService.saveSettings(
      settings.copyWith(htmlEnableJavaScript: enabled),
    );
    await _method?.invokeMethod('setJavaScriptEnabled', {'enabled': enabled});
  }

  void _toggleFullscreen() {
    final entering = !_isFullscreen;
    setState(() => _isFullscreen = entering);
    SystemChrome.setEnabledSystemUIMode(
      entering ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge,
    );
  }

  @override
  void dispose() {
    _eventSub?.cancel();
    if (_isFullscreen) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return PopScope(
      canPop: !_isFullscreen,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _isFullscreen) _toggleFullscreen();
      },
      child: Scaffold(
        appBar: _isFullscreen
            ? null
            : AppBar(
                title: Text(
                  _title.isNotEmpty ? _title : _fileName,
                  overflow: TextOverflow.ellipsis,
                ),
                actions: [
                  IconButton(
                    icon: const Icon(Icons.chevron_left_rounded),
                    tooltip: 'Back',
                    onPressed: _canGoBack ? () => _method?.invokeMethod('goBack') : null,
                  ),
                  IconButton(
                    icon: const Icon(Icons.chevron_right_rounded),
                    tooltip: 'Forward',
                    onPressed: _canGoForward ? () => _method?.invokeMethod('goForward') : null,
                  ),
                  IconButton(
                    icon: const Icon(Icons.refresh_rounded),
                    tooltip: 'Reload',
                    onPressed: _method == null
                        ? null
                        : () {
                            setState(() => _isLoading = true);
                            _method?.invokeMethod('reload');
                          },
                  ),
                  PopupMenuButton<String>(
                    tooltip: 'Options',
                    onSelected: (value) {
                      switch (value) {
                        case 'js':
                          _toggleJavaScript();
                          break;
                        case 'fullscreen':
                          _toggleFullscreen();
                          break;
                      }
                    },
                    itemBuilder: (context) => [
                      PopupMenuItem(
                        value: 'js',
                        enabled: _method != null,
                        child: Row(
                          children: [
                            Icon(
                              _jsEnabled ? Icons.code_off_rounded : Icons.code_rounded,
                              color: cs.onSurface,
                            ),
                            const SizedBox(width: 12),
                            Text(_jsEnabled ? 'Disable JavaScript' : 'Enable JavaScript'),
                          ],
                        ),
                      ),
                      const PopupMenuDivider(),
                      PopupMenuItem(
                        value: 'fullscreen',
                        child: Row(
                          children: [
                            Icon(Icons.fullscreen_rounded, color: cs.onSurface),
                            const SizedBox(width: 12),
                            const Text('Enter Fullscreen'),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
        body: !_isSettingsLoaded
            ? Container(
                color: cs.surface,
                child: const Center(
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                ),
              )
            : Stack(
                children: [
                  Positioned.fill(
                    child: AndroidView(
                      viewType: _kHtmlViewerViewType,
                      creationParams: {
                        'volId': widget.container.volId,
                        'htmlPath': widget.filePath,
                        'javaScriptEnabled': _jsEnabled,
                      },
                      creationParamsCodec: const StandardMessageCodec(),
                      onPlatformViewCreated: _onPlatformViewCreated,
                    ),
                  ),
            if (_isLoading)
              Container(
                color: cs.surface,
                child: const Center(child: CircularProgressIndicator(strokeWidth: 2.5)),
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
                        Icon(Icons.error_outline_rounded, color: cs.error, size: 48),
                        const SizedBox(height: 16),
                        Text(
                          'Cannot display this page',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _errorMessage,
                          textAlign: TextAlign.center,
                          style: TextStyle(color: cs.onSurfaceVariant),
                        ),
                      ],
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