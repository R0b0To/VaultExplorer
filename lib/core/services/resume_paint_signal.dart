import 'package:flutter/widgets.dart';
import 'package:vaultexplorer/core/api/vault_file_io_api.dart';

/// Pairs with `PrivacyCurtain` on the native side (see MainActivity.kt).
///
/// Native shows an opaque curtain the instant the Activity is paused
/// (screen off, device lock, task switch, ...) because Flutter's own
/// `SchedulerBinding` stops producing frames as soon as the app leaves
/// `resumed`, so it can't reliably paint over anything sensitive itself
/// before the display freezes. On the way back up native can't just guess
/// how long Flutter needs to catch up and repaint - a fixed delay is either
/// too short (content still flashes on slower resumes) or wastefully long.
/// Instead, this observer pings native the moment the *next real frame*
/// after a resume has actually been painted, which is exactly the signal
/// native needs to drop the curtain at the earliest safe moment.
class ResumePaintSignal with WidgetsBindingObserver {
  static ResumePaintSignal? _instance;

  final VaultFileIoApi _fileIoApi;

  ResumePaintSignal._(this._fileIoApi);

  /// Registers the singleton observer with [WidgetsBinding.instance].
  static void register(VaultFileIoApi fileIoApi) {
    if (_instance != null) return;
    _instance = ResumePaintSignal._(fileIoApi);
    WidgetsBinding.instance.addObserver(_instance!);
  }

  /// Unregisters the observer if active.
  static void unregister() {
    if (_instance == null) return;
    WidgetsBinding.instance.removeObserver(_instance!);
    _instance = null;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fileIoApi.notifyResumedFramePainted();
    });
  }
}
