import 'package:flutter/services.dart';
import 'package:vaultexplorer/core/api/vault_engine_types.dart';
import 'package:vaultexplorer/data/services/vault_engine/channel_methods.dart';

typedef QuickCaptureSettingsSnapshot = ({bool tileEnabled});

typedef ScratchpadSession = ({String sessionToken, String scratchpadPath});

typedef ScratchpadFinalizeResult = ({bool success, String? error});

/// Everything Dart needs for the Quick Capture flow (see
/// docs/architecture.md, "Capture-First + Encrypted Scratchpad"):
/// settings + the pending-request pull for the Quick Settings tile /
/// pinned shortcut entry point (over the shared engine channel, handled
/// by QuickCaptureSettingsHandlers.kt), and opening/finalizing/discarding
/// an ephemeral-key scratchpad session (over its own dedicated channel,
/// handled by QuickCaptureScratchpadPlugin.kt -- mirrors how
/// VaultCameraController owns its own 'com.aeidolon.vaultexplorer/camera'
/// channel rather than riding the shared one).
///
/// The raw AES key for a session never appears here, or anywhere else in
/// Dart: [openSession] returns only an opaque token,
/// [VaultCameraController.takePhotoToScratchpad]/[VaultCameraController.startVideoRecordingToScratchpad]
/// pass that token straight back to the native camera plugin, which
/// resolves it to the actual key itself (ScratchpadKeyStore, same
/// process, no channel round trip). This class only ever moves the
/// token and the scratchpad file's path.
class QuickCaptureApi {
  final MethodChannel _channel;
  const QuickCaptureApi(this._channel);

  static const MethodChannel _scratchpadChannel = MethodChannel(
    'com.aeidolon.vaultexplorer/quickcapture',
  );

  /// Falls back to disabled on any failure, same reasoning as
  /// VaultPanicApi.getPanicSettings: a read failure must never make the
  /// tile look more enabled than it actually is.
  Future<QuickCaptureSettingsSnapshot> getQuickCaptureSettings() async {
    try {
      final result = await _channel.invokeMapMethod<String, dynamic>(
        ChannelMethods.getQuickCaptureSettings,
      );
      return (tileEnabled: result?['tileEnabled'] as bool? ?? false);
    } catch (e) {
      logSwallowed('getQuickCaptureSettings', e);
      return (tileEnabled: false);
    }
  }

  /// Also pushes/removes the dynamic launcher shortcut to match (see
  /// QuickCaptureShortcuts.kt) -- Settings only needs to flip this one
  /// switch, not two.
  Future<bool> setQuickCaptureTileEnabled(bool enabled) async {
    try {
      final success = await _channel.invokeMethod<bool>(
        ChannelMethods.setQuickCaptureTileEnabled,
        {'enabled': enabled},
      );
      return success ?? false;
    } catch (e) {
      logSwallowed('setQuickCaptureTileEnabled', e);
      return false;
    }
  }

  /// Asks the launcher to pin a Quick Capture icon to the home screen.
  /// The person still has to accept a system dialog this call gets no
  /// result from -- a `true` return only means the request could be
  /// made at all (a launcher that doesn't support pinning returns
  /// false immediately).
  Future<bool> requestPinQuickCaptureShortcut() async {
    try {
      final success = await _channel.invokeMethod<bool>(
        ChannelMethods.requestPinQuickCaptureShortcut,
      );
      return success ?? false;
    } catch (e) {
      logSwallowed('requestPinQuickCaptureShortcut', e);
      return false;
    }
  }

  /// Consumes and returns whether a Quick Capture request (tile tap or
  /// shortcut tap) was already pending before Dart's engine finished
  /// starting up -- see QuickCaptureBridge.kt's doc comment for the
  /// cold-start race this covers. Call once from MainShell.initState,
  /// mirroring VaultFileIoApi.checkPendingShareRequest.
  Future<bool> checkPendingQuickCaptureRequest() async {
    try {
      final pending = await _channel.invokeMethod<bool>(
        ChannelMethods.checkPendingQuickCaptureRequest,
      );
      return pending ?? false;
    } catch (e) {
      logSwallowed('checkPendingQuickCaptureRequest', e);
      return false;
    }
  }

  /// Opens a new scratchpad session: a fresh ephemeral AES-256 key (held
  /// natively, see ScratchpadKeyStore.kt) paired with a not-yet-created
  /// ciphertext file path under the app's cache directory. Returns null
  /// on failure -- callers should treat that the same as the person
  /// cancelling before ever reaching the camera.
  Future<ScratchpadSession?> openSession() async {
    try {
      final result = await _scratchpadChannel.invokeMapMethod<String, dynamic>(
        'openSession',
      );
      final token = result?['sessionToken'] as String?;
      final path = result?['scratchpadPath'] as String?;
      if (token == null || path == null) return null;
      return (sessionToken: token, scratchpadPath: path);
    } catch (e) {
      logSwallowed('openSession', e);
      return null;
    }
  }

  /// Decrypts the scratchpad for [sessionToken] and writes it into the
  /// already-mounted vault at [virtualPath] (see
  /// ScratchpadTransfer.finalizeIntoVault). The scratchpad file is wiped
  /// and the key forgotten either way, success or failure. The caller
  /// still needs to call VaultLifecycleApi.finishWrite/
  /// CameraVaultService.finalizeVaultWrite afterward on success -- this
  /// only performs the write, matching how the in-vault camera path
  /// already splits those two steps.
  Future<ScratchpadFinalizeResult> finalizeSession({
    required String sessionToken,
    required int volId,
    required String virtualPath,
  }) async {
    try {
      final result = await _scratchpadChannel.invokeMapMethod<String, dynamic>(
        'finalizeSession',
        {
          'sessionToken': sessionToken,
          'volId': volId,
          'virtualPath': virtualPath,
        },
      );
      return (
        success: result?['success'] as bool? ?? false,
        error: result?['error'] as String?,
      );
    } catch (e) {
      logSwallowed('finalizeSession', e);
      return (success: false, error: e.toString());
    }
  }

  /// Wipes the scratchpad for [sessionToken] unread and forgets its key.
  /// Safe to call even if the session already expired or was already
  /// finalized -- ScratchpadTransfer.discard is a no-op on a missing
  /// file.
  Future<void> discardSession(String sessionToken) async {
    try {
      await _scratchpadChannel.invokeMethod<void>('discardSession', {
        'sessionToken': sessionToken,
      });
    } catch (e) {
      logSwallowed('discardSession', e, expected: true);
    }
  }
}
