import 'dart:async';

import 'package:flutter/services.dart';
import 'package:vaultexplorer/core/api/vault_file_io_api.dart';
import 'package:vaultexplorer/core/filesystem/local_storage_container.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';

import 'camera_vault_service.dart';

/// Calls into the native camera plugin for the steps that turn a finished
/// recording into a vault file.
///
/// These are deliberately static and independent of any
/// [VaultCameraController] instance: a background save keeps running after
/// the capture screen (and with it the controller) has been disposed, and none
/// of these calls need a camera session.
abstract final class CapturedVideoChannel {
  static const MethodChannel _channel = MethodChannel(
    'com.aeidolon.vaultexplorer/camera',
  );

  /// Trims [videoPath] and returns the path of the trimmed file, or the
  /// original path when trimming failed (the native side keeps the source
  /// in that case).
  static Future<String> trim({
    required String videoPath,
    required int startMs,
    required int endMs,
  }) async {
    try {
      final res = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'trimVideo',
        {'videoPath': videoPath, 'startMs': startMs, 'endMs': endMs},
      );
      return res?['videoPath'] as String? ?? videoPath;
    } catch (_) {
      return videoPath;
    }
  }

  /// Streams [videoPath] into the vault. [opId] ties the write to a
  /// FileOperation so native progress events and cancellation reach it.
  static Future<({bool success, bool cancelled})> saveToVault({
    required String videoPath,
    required int volId,
    required String virtualPath,
    required int opId,
  }) async {
    try {
      final res = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'saveVideoToVault',
        {
          'videoPath': videoPath,
          'volId': volId,
          'virtualPath': virtualPath,
          'opId': opId,
        },
      );
      return (
        success: res?['success'] as bool? ?? false,
        cancelled: res?['cancelled'] as bool? ?? false,
      );
    } catch (_) {
      return (success: false, cancelled: false);
    }
  }

  /// Zero-fills and deletes a plaintext recording.
  static Future<void> discard(String videoPath) async {
    try {
      await _channel.invokeMethod('discardVideo', {'videoPath': videoPath});
    } catch (_) {
      // Best effort: anything left behind is wiped by the orphan sweep at the
      // next app start.
    }
  }
}

/// Saves one recorded video into the vault after the capture screen has
/// already been closed.
///
/// [run] is the `performImport` callback of a FileOperation, so the save shows
/// up in the same transfer feedback as any other import: a placeholder in the
/// folder, the app-bar transfer button, the progress notification and the
/// operations sheet, with cancel support.
///
/// Everything it needs is captured at construction: it must not touch a
/// `BuildContext`, a `WidgetRef` or the capture screen's state, all of which
/// are gone by the time it runs.
class BackgroundVideoSave {
  const BackgroundVideoSave({
    required this.container,
    required this.vaultService,
    required this.fileIoApi,
    required this.videoPath,
    required this.virtualPath,
    required this.trimStartMs,
    required this.trimEndMs,
    required this.durationMs,
    required this.failureMessage,
  });

  final MountedContainer container;
  final CameraVaultService vaultService;
  final VaultFileIoApi fileIoApi;
  final String videoPath;
  final String virtualPath;
  final int trimStartMs;
  final int trimEndMs;
  final int durationMs;

  /// Shown in the operation's error summary when the write fails.
  final String failureMessage;

  bool get needsTrim =>
      trimStartMs > 0 || (trimEndMs > 0 && trimEndMs < durationMs);

  /// Rough size of the finished file, for the placeholder entry and the
  /// up-front free-space check. A trimmed clip is scaled by the kept share of
  /// the duration; the real size is reported by native once the write starts.
  static int estimateBytes({
    required int sourceBytes,
    required int trimStartMs,
    required int trimEndMs,
    required int durationMs,
  }) {
    if (sourceBytes <= 0 || durationMs <= 0) return sourceBytes;
    final end = (trimEndMs > 0 && trimEndMs < durationMs)
        ? trimEndMs
        : durationMs;
    final kept = (end - trimStartMs).clamp(0, durationMs);
    return (sourceBytes * kept / durationMs).ceil();
  }

  /// Trims (if asked), writes the video into the vault, finalizes the write
  /// and wipes the plaintext recording.
  ///
  /// Returns 1 on success. Throws [PlatformException] with code `CANCELLED`
  /// when the user cancelled, or `SAVE_FAILED` otherwise, which the file
  /// operation service maps to the cancelled / failed status.
  Future<int> run(int opId) async {
    var path = videoPath;
    try {
      if (needsTrim) {
        path = await CapturedVideoChannel.trim(
          videoPath: path,
          startMs: trimStartMs,
          endMs: trimEndMs,
        );
      }

      var cancelled = false;
      final bool written;
      if (container.isLocalStorage) {
        written = await fileIoApi.writeFileFromLocalPath(
          container,
          virtualPath,
          path,
          opId: opId,
        );
      } else {
        final res = await CapturedVideoChannel.saveToVault(
          videoPath: path,
          volId: container.volId,
          virtualPath: virtualPath,
          opId: opId,
        );
        written = res.success;
        cancelled = res.cancelled;
      }

      if (!written || !await vaultService.finalizeVaultWrite(virtualPath)) {
        // Never leave a truncated file behind under the final name.
        await vaultService.deleteFile(virtualPath);
        if (cancelled) {
          throw PlatformException(code: 'CANCELLED');
        }
        throw PlatformException(code: 'SAVE_FAILED', message: failureMessage);
      }
      return 1;
    } finally {
      // Success, failure and cancel all end the same way: the plaintext copy
      // is wiped. This plain file must not outlive the operation.
      await CapturedVideoChannel.discard(path);
    }
  }
}
