// HtmlViewerScreen was a StatefulWidget mixing platform-view-instance
// plumbing (MethodChannel/EventChannel bound to a specific AndroidView
// callback) with reactive domain state (settings, container-locked,
// page-load/nav state, fullscreen). Family-keyed by volId, same shape as
// VaultItemDetail: a fresh screen instance is pushed per file.
//
// _method/_eventSub/_onPlatformViewCreated stay in the widget -- they're
// inherently tied to one AndroidView instance's onPlatformViewCreated
// callback, not swappable/injectable state, so there's nothing a Notifier
// gains by owning them (same reasoning FileBrowserScreen's Navigation
// Controller was deferred for: don't force an extraction where the pieces
// are genuinely one thing). Everything reactive that those callbacks drive
// -- loading/error/title/nav-buttons/settings/lock/fullscreen -- moves here.
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:vaultexplorer/data/services/app_settings_service.dart';
import 'package:vaultexplorer/core/providers/vault_engine_providers.dart';

part 'html_viewer_controller.g.dart';

class HtmlViewerState {
  final bool isLoading;
  final bool hasError;
  final String errorMessage;
  final String title;
  final bool canGoBack;
  final bool canGoForward;
  final bool jsEnabled;
  final bool isContainerLocked;
  final bool isFullscreen;
  final bool isSettingsLoaded;

  const HtmlViewerState({
    this.isLoading = true,
    this.hasError = false,
    this.errorMessage = '',
    this.title = '',
    this.canGoBack = false,
    this.canGoForward = false,
    this.jsEnabled = false,
    this.isContainerLocked = false,
    this.isFullscreen = false,
    this.isSettingsLoaded = false,
  });

  HtmlViewerState copyWith({
    bool? isLoading,
    bool? hasError,
    String? errorMessage,
    String? title,
    bool? canGoBack,
    bool? canGoForward,
    bool? jsEnabled,
    bool? isContainerLocked,
    bool? isFullscreen,
    bool? isSettingsLoaded,
  }) =>
      HtmlViewerState(
        isLoading: isLoading ?? this.isLoading,
        hasError: hasError ?? this.hasError,
        errorMessage: errorMessage ?? this.errorMessage,
        title: title ?? this.title,
        canGoBack: canGoBack ?? this.canGoBack,
        canGoForward: canGoForward ?? this.canGoForward,
        jsEnabled: jsEnabled ?? this.jsEnabled,
        isContainerLocked: isContainerLocked ?? this.isContainerLocked,
        isFullscreen: isFullscreen ?? this.isFullscreen,
        isSettingsLoaded: isSettingsLoaded ?? this.isSettingsLoaded,
      );
}

@riverpod
class HtmlViewer extends _$HtmlViewer {
  @override
  HtmlViewerState build(int volId) {
    void onContainerLocked(int lockedVolId) {
      if (lockedVolId == volId) {
        state = state.copyWith(isContainerLocked: true);
      }
    }

    final engineEvents = ref.read(vaultEngineEventsProvider);
    engineEvents.addContainerLockedListener(onContainerLocked);
    ref.onDispose(
      () => engineEvents.removeContainerLockedListener(onContainerLocked),
    );

    _loadSettings();
    return const HtmlViewerState();
  }

  Future<void> _loadSettings() async {
    final settings = await ref.read(appSettingsServiceProvider).loadSettings();
    if (ref.mounted) {
      state = state.copyWith(jsEnabled: settings.htmlEnableJavaScript, isSettingsLoaded: true);
    }
  }

  /// Mirrors the original's 'pageFinished' event handling.
  void onPageFinished({required String title, required bool canGoBack, required bool canGoForward}) {
    state = state.copyWith(
      isLoading: false,
      hasError: false,
      title: title,
      canGoBack: canGoBack,
      canGoForward: canGoForward,
    );
  }

  void onPageError(String message) {
    state = state.copyWith(isLoading: false, hasError: true, errorMessage: message);
  }

  void setLoading() {
    state = state.copyWith(isLoading: true);
  }

  /// Applies the confirmed JS toggle: updates state and persists the
  /// setting. The widget calls this after any confirm dialog has already
  /// been shown/accepted, then separately invokes `setJavaScriptEnabled`
  /// on its own MethodChannel (that channel stays widget-owned).
  Future<void> applyJavaScriptToggle(bool enabled) async {
    state = state.copyWith(jsEnabled: enabled, isLoading: true);
    // Resolved once, up front, and reused for both calls below rather than
    // read a second time after the first await (see the note on
    // _upgradeMasterPasswordHashInBackground in lock_gate_controller.dart
    // for why re-reading `ref` post-await is avoided here).
    final appSettingsService = ref.read(appSettingsServiceProvider);
    final settings = await appSettingsService.loadSettings();
    await appSettingsService.saveSettings(
      settings.copyWith(htmlEnableJavaScript: enabled),
    );
  }

  void setFullscreen(bool value) {
    state = state.copyWith(isFullscreen: value);
  }
}
