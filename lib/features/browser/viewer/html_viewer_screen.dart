import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/core/widgets/common_widgets.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/features/browser/viewer/html_viewer_controller.dart';

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
class HtmlViewerScreen extends ConsumerStatefulWidget {
  final MountedContainer container;
  final String filePath;

  const HtmlViewerScreen({
    super.key,
    required this.container,
    required this.filePath,
  });

  @override
  ConsumerState<HtmlViewerScreen> createState() => _HtmlViewerScreenState();
}

class _HtmlViewerScreenState extends ConsumerState<HtmlViewerScreen> {
  // Bound to one AndroidView instance's onPlatformViewCreated callback --
  // not swappable/injectable, so this stays widget-owned (see
  // html_viewer_controller.dart's header comment).
  MethodChannel? _method;
  StreamSubscription<dynamic>? _eventSub;

  String get _fileName => widget.filePath.split('/').last;

  void _onPlatformViewCreated(int id) {
    final method = MethodChannel('$_kHtmlViewerViewType/$id');
    final events = EventChannel('$_kHtmlViewerViewType/events/$id');
    _eventSub = events.receiveBroadcastStream().listen(_onEvent, onError: (_) {});
    setState(() => _method = method);
  }

  void _onEvent(dynamic raw) {
    if (raw is! Map) return;
    if (!mounted) return;
    final controller = ref.read(htmlViewerProvider(widget.container.volId).notifier);
    switch (raw['event']) {
      case 'pageFinished':
        controller.onPageFinished(
          title: (raw['title'] as String?) ?? '',
          canGoBack: raw['canGoBack'] as bool? ?? false,
          canGoForward: raw['canGoForward'] as bool? ?? false,
        );
      case 'error':
        controller.onPageError((raw['message'] as String?) ?? context.l10n.htmlViewerLoadFailedMessage);
    }
  }

  Future<void> _toggleJavaScript(bool currentJsEnabled) async {
    if (!currentJsEnabled) {
      final confirm = await showAppConfirmDialog(
        context,
        title: context.l10n.enableJavaScriptDialogTitle,
        message: context.l10n.enableJavaScriptDialogMessage,
        confirmLabel: context.l10n.enable,
      );
      if (!confirm) return;
    }
    final enabled = !currentJsEnabled;
    await ref.read(htmlViewerProvider(widget.container.volId).notifier).applyJavaScriptToggle(enabled);
    await _method?.invokeMethod('setJavaScriptEnabled', {'enabled': enabled});
  }

  void _toggleFullscreen(bool currentlyFullscreen) {
    final entering = !currentlyFullscreen;
    ref.read(htmlViewerProvider(widget.container.volId).notifier).setFullscreen(entering);
    if (entering) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    } else {
      SystemChrome.setEnabledSystemUIMode(
        SystemUiMode.manual,
        overlays: SystemUiOverlay.values,
      );
    }
  }

  @override
  void dispose() {
    _eventSub?.cancel();
    // Note: original also force-exited fullscreen system UI mode here if
    // _isFullscreen was true. isFullscreen now lives in the controller,
    // which may already be disposed by the time this widget disposes (ref
    // access after dispose isn't safe) -- so this reads the last-known
    // value captured in build() via a local field instead.
    if (_lastIsFullscreen) {
      SystemChrome.setEnabledSystemUIMode(
        SystemUiMode.manual,
        overlays: SystemUiOverlay.values,
      );
    }
    super.dispose();
  }

  bool _lastIsFullscreen = false;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(htmlViewerProvider(widget.container.volId));
    _lastIsFullscreen = state.isFullscreen;

    if (state.isContainerLocked) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: SizedBox.expand(),
      );
    }

    final cs = Theme.of(context).colorScheme;

    return PopScope(
      canPop: !state.isFullscreen,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && state.isFullscreen) _toggleFullscreen(state.isFullscreen);
      },
      child: Scaffold(
        appBar: state.isFullscreen
            ? null
            : AppBar(
                title: Text(
                  state.title.isNotEmpty ? state.title : _fileName,
                  overflow: TextOverflow.ellipsis,
                ),
                actions: [
                  IconButton(
                    icon: const Icon(Icons.chevron_left_rounded),
                    tooltip: context.l10n.backTooltip,
                    onPressed: state.canGoBack ? () => _method?.invokeMethod('goBack') : null,
                  ),
                  IconButton(
                    icon: const Icon(Icons.chevron_right_rounded),
                    tooltip: context.l10n.forwardTooltip,
                    onPressed: state.canGoForward ? () => _method?.invokeMethod('goForward') : null,
                  ),
                  IconButton(
                    icon: const Icon(Icons.refresh_rounded),
                    tooltip: context.l10n.reloadTooltip,
                    onPressed: _method == null
                        ? null
                        : () {
                            ref.read(htmlViewerProvider(widget.container.volId).notifier).setLoading();
                            _method?.invokeMethod('reload');
                          },
                  ),
                  PopupMenuButton<String>(
                    tooltip: context.l10n.optionsTooltip,
                    onSelected: (value) {
                      switch (value) {
                        case 'js':
                          _toggleJavaScript(state.jsEnabled);
                          break;
                        case 'fullscreen':
                          _toggleFullscreen(state.isFullscreen);
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
                              state.jsEnabled ? Icons.code_off_rounded : Icons.code_rounded,
                              color: cs.onSurface,
                            ),
                            const SizedBox(width: 12),
                            Text(
                              state.jsEnabled
                                  ? context.l10n.disableJavaScriptMenu
                                  : context.l10n.enableJavaScriptMenu,
                            ),
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
                            Text(context.l10n.enterFullscreenMenu),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
        body: !state.isSettingsLoaded
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
                        'javaScriptEnabled': state.jsEnabled,
                      },
                      creationParamsCodec: const StandardMessageCodec(),
                      onPlatformViewCreated: _onPlatformViewCreated,
                    ),
                  ),
            if (state.isLoading)
              Container(
                color: cs.surface,
                child: const Center(child: CircularProgressIndicator(strokeWidth: 2.5)),
              ),
            if (state.hasError)
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
                          context.l10n.htmlViewerErrorTitle,
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          state.errorMessage,
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