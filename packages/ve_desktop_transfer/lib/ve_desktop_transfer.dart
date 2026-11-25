import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:ve_desktop_transfer/src/transfer_models.dart';

export 'src/desktop_drop_zone.dart';
export 'src/transfer_models.dart';

typedef DesktopDropListener = void Function(DesktopDropEvent event);

/// Flutter interface to the native Windows (Win32 OLE) and Linux (GTK3 X11 /
/// Wayland) drag-and-drop & clipboard plugin.
class VeDesktopTransfer {
  VeDesktopTransfer._();

  static final VeDesktopTransfer instance = VeDesktopTransfer._();

  static const MethodChannel _channel = MethodChannel(
    'vaultexplorer/desktop_transfer',
  );

  bool _handlerBound = false;
  bool _initialized = false;
  bool _supported = false;
  String _backend = 'unsupported';
  Future<bool>? _initFuture;

  final Set<DesktopDropListener> _dropListeners = <DesktopDropListener>{};
  final Map<int, int> _viewRefCounts = <int, int>{};

  /// Fired when native lazy decryption materializes files into a staging
  /// directory on disk (either during `GetData(CF_HDROP)`, GTK `drag-data-get`,
  /// or OS clipboard paste).
  void Function(String batchId, List<String> stagedPaths)? onBatchRealized;

  /// Fired when an OS drag operation finishes (`EndOperation` / `drag-end` /
  /// `drag-failed`). [immediateIfUnused] is true when the OS target confirmed
  /// completion (e.g., Windows `IDataObjectAsyncCapability::EndOperation`).
  void Function(String batchId, bool success, bool immediateIfUnused)?
  onBatchTransferFinished;

  /// Fired when another application claims the OS clipboard, replacing our
  /// staged file/image payload.
  void Function(String batchId)? onClipboardOwnershipLost;

  bool get isSupportedPlatform =>
      !kIsWeb && (Platform.isWindows || Platform.isLinux);

  bool get isInitialized => _initialized;
  bool get isSupported => _supported;
  String get backend => _backend;

  void _ensureChannelHandler() {
    if (_handlerBound) return;
    _handlerBound = true;
    _channel.setMethodCallHandler(_handlePlatformCall);
  }

  /// Initializes the native transfer plugin and optionally binds the C engine
  /// library at [engineLibraryPath]. Safe to call repeatedly.
  Future<bool> initialize({String? engineLibraryPath}) {
    if (!isSupportedPlatform) return Future<bool>.value(false);
    if (_initialized) return Future<bool>.value(_supported);
    return _initFuture ??= _doInitialize(engineLibraryPath: engineLibraryPath);
  }

  Future<bool> _doInitialize({String? engineLibraryPath}) async {
    _ensureChannelHandler();
    try {
      final result = await _channel.invokeMapMethod<Object?, Object?>(
        'initialize',
        <String, Object?>{
          if (engineLibraryPath != null && engineLibraryPath.isNotEmpty)
            'engineLibraryPath': engineLibraryPath,
        },
      );
      _initialized = true;
      _supported = result?['supported'] == true;
      _backend = (result?['backend'] as String?) ?? 'unknown';
      return _supported;
    } on MissingPluginException {
      _initialized = true;
      _supported = false;
      return false;
    } catch (e) {
      debugPrint('[ve_desktop_transfer] initialize failed: $e');
      _initialized = true;
      _supported = false;
      return false;
    }
  }

  void addDropListener(DesktopDropListener listener) {
    _ensureChannelHandler();
    _dropListeners.add(listener);
  }

  void removeDropListener(DesktopDropListener listener) {
    _dropListeners.remove(listener);
  }

  /// Increments the registration refcount for [viewId] and attaches native drop
  /// and pointer hooks on the first retain.
  Future<bool> retainView(int viewId) async {
    if (!isSupportedPlatform) return false;
    await initialize();
    final count = (_viewRefCounts[viewId] ?? 0) + 1;
    _viewRefCounts[viewId] = count;
    if (count > 1) return true;
    try {
      return (await _channel.invokeMethod<bool>('registerView', {
            'viewId': viewId,
          })) ??
          false;
    } catch (e) {
      debugPrint('[ve_desktop_transfer] registerView($viewId) failed: $e');
      return false;
    }
  }

  /// Decrements the registration refcount for [viewId] and detaches native
  /// hooks when zero.
  Future<void> releaseView(int viewId) async {
    if (!isSupportedPlatform) return;
    final count = _viewRefCounts[viewId];
    if (count == null) return;
    if (count > 1) {
      _viewRefCounts[viewId] = count - 1;
      return;
    }
    _viewRefCounts.remove(viewId);
    try {
      await _channel.invokeMethod<void>('unregisterView', {'viewId': viewId});
    } catch (_) {}
  }

  /// Starts a native OS outbound drag-and-drop operation from [viewId].
  /// Returns `"copied"`, `"cancelled"`, `"error"`, or `"unsupported"`.
  Future<String> startDrag({
    required int viewId,
    required TransferManifest manifest,
  }) async {
    if (!isSupportedPlatform) return 'unsupported';
    await initialize();
    if (!_supported) return 'unsupported';
    try {
      return (await _channel.invokeMethod<String>('startDrag', {
            'viewId': viewId,
            'manifest': manifest.toMap(),
          })) ??
          'error';
    } on MissingPluginException {
      return 'unsupported';
    } catch (e) {
      debugPrint('[ve_desktop_transfer] startDrag failed: $e');
      return 'error';
    }
  }

  /// Populates the OS clipboard with lazy file references described by
  /// [manifest].
  Future<bool> setClipboardFiles({required TransferManifest manifest}) async {
    if (!isSupportedPlatform) return false;
    await initialize();
    if (!_supported) return false;
    try {
      return (await _channel.invokeMethod<bool>('setClipboardFiles', {
            'manifest': manifest.toMap(),
          })) ??
          false;
    } catch (e) {
      debugPrint('[ve_desktop_transfer] setClipboardFiles failed: $e');
      return false;
    }
  }

  /// Populates the OS clipboard with an in-memory image (PNG + DIB/BMP).
  Future<bool> setClipboardImage(ClipboardImagePayload payload) async {
    if (!isSupportedPlatform) return false;
    await initialize();
    if (!_supported) return false;
    try {
      return (await _channel.invokeMethod<bool>('setClipboardImage', {
            'pngBytes': payload.pngBytes,
            'rgbaBytes': payload.rgbaBytes,
            'width': payload.width,
            'height': payload.height,
            'sensitive': payload.sensitive,
          })) ??
          false;
    } catch (e) {
      debugPrint('[ve_desktop_transfer] setClipboardImage failed: $e');
      return false;
    }
  }

  /// Copies sensitive text to the OS clipboard with platform history/cloud
  /// exclusion hints where supported.
  Future<bool> setSensitiveClipboardText(String text) async {
    if (!isSupportedPlatform) return false;
    await initialize();
    if (!_supported) return false;
    try {
      return (await _channel.invokeMethod<bool>('setSensitiveClipboardText', {
            'text': text,
          })) ??
          false;
    } catch (_) {
      return false;
    }
  }

  /// Clears the OS clipboard if it still holds [expectedText] (or always when
  /// [expectedText] is null and the app holds the clip).
  Future<bool> clearSensitiveClipboardText({String? expectedText}) async {
    if (!isSupportedPlatform) return false;
    await initialize();
    if (!_supported) return false;
    try {
      return (await _channel.invokeMethod<bool>(
            'clearSensitiveClipboardText',
            {'expectedText': expectedText},
          )) ??
          false;
    } catch (_) {
      return false;
    }
  }

  /// Clears the OS clipboard if it currently belongs to [batchId] or [volId],
  /// or clears an owned copied image when [clearImage] is true.
  Future<bool> clearClipboardIfBatch({
    String? batchId,
    int? volId,
    bool clearImage = false,
  }) async {
    if (!isSupportedPlatform || !_supported) return false;
    try {
      return (await _channel.invokeMethod<bool>('clearClipboardIfBatch', {
            'batchId': batchId,
            'volId': volId,
            'clearImage': clearImage,
          })) ??
          false;
    } catch (_) {
      return false;
    }
  }

  /// Inspects whether the OS clipboard currently contains external files, our
  /// own copied files, or an image.
  Future<ClipboardInspectResult> inspectClipboard() async {
    if (!isSupportedPlatform) {
      return const ClipboardInspectResult(
        hasFiles: false,
        isOwnFiles: false,
        ownBatchId: null,
        filePaths: <String>[],
        hasImage: false,
      );
    }
    await initialize();
    if (!_supported) {
      return const ClipboardInspectResult(
        hasFiles: false,
        isOwnFiles: false,
        ownBatchId: null,
        filePaths: <String>[],
        hasImage: false,
      );
    }
    try {
      final raw = await _channel.invokeMapMethod<Object?, Object?>(
        'inspectClipboard',
      );
      return ClipboardInspectResult.fromMap(raw);
    } catch (e) {
      debugPrint('[ve_desktop_transfer] inspectClipboard failed: $e');
      return const ClipboardInspectResult(
        hasFiles: false,
        isOwnFiles: false,
        ownBatchId: null,
        filePaths: <String>[],
        hasImage: false,
      );
    }
  }

  /// Reads an image currently on the OS clipboard encoded as PNG bytes, or null.
  Future<Uint8List?> readClipboardImagePng() async {
    if (!isSupportedPlatform) return null;
    await initialize();
    if (!_supported) return null;
    try {
      final raw = await _channel.invokeMapMethod<Object?, Object?>(
        'readClipboardImageData',
      );
      if (raw == null) return null;
      final format = raw['format'] as String?;
      final bytes = raw['bytes'] as Uint8List?;
      if (bytes == null || bytes.isEmpty) return null;
      if (format == 'png') return bytes;
      // BMP / DIB fallback: decode via Flutter codec and re-encode as PNG.
      final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      try {
        final descriptor = await ui.ImageDescriptor.encoded(buffer);
        try {
          final codec = await descriptor.instantiateCodec();
          try {
            final frame = await codec.getNextFrame();
            try {
              final png = await frame.image.toByteData(
                format: ui.ImageByteFormat.png,
              );
              return png?.buffer.asUint8List(
                png.offsetInBytes,
                png.lengthInBytes,
              );
            } finally {
              frame.image.dispose();
            }
          } finally {
            codec.dispose();
          }
        } finally {
          descriptor.dispose();
        }
      } finally {
        buffer.dispose();
      }
    } catch (e) {
      debugPrint('[ve_desktop_transfer] readClipboardImagePng failed: $e');
      return null;
    }
  }

  /// Applies OS-level directory hardening (owner-only DACL / disable indexing).
  Future<bool> hardenStagingDir(String dirPath) async {
    if (!isSupportedPlatform) return false;
    await initialize();
    if (!_supported) return false;
    try {
      return (await _channel.invokeMethod<bool>('hardenStagingDir', {
            'path': dirPath,
          })) ??
          false;
    } catch (_) {
      return false;
    }
  }

  /// Checks whether any external OS process still holds an open read handle to
  /// a file inside [dirPath].
  Future<bool> isStagingBatchInUse(String dirPath) async {
    if (!isSupportedPlatform || !_supported) return false;
    try {
      return (await _channel.invokeMethod<bool>('isStagingBatchInUse', {
            'path': dirPath,
          })) ??
          false;
    } catch (_) {
      return false;
    }
  }

  /// Cancels any active native export/staging operation for [batchId].
  Future<void> cancelBatch(String batchId) async {
    if (!isSupportedPlatform || !_supported) return;
    try {
      await _channel.invokeMethod<void>('cancelBatch', {'batchId': batchId});
    } catch (_) {}
  }

  Future<Object?> _handlePlatformCall(MethodCall call) async {
    final args = call.arguments is Map
        ? Map<Object?, Object?>.from(call.arguments as Map)
        : const <Object?, Object?>{};
    switch (call.method) {
      case 'onDropEntered':
      case 'onDropUpdated':
      case 'onDropExited':
      case 'onDropReceived':
        final kind = switch (call.method) {
          'onDropEntered' => DesktopDropEventKind.entered,
          'onDropUpdated' => DesktopDropEventKind.updated,
          'onDropExited' => DesktopDropEventKind.exited,
          _ => DesktopDropEventKind.dropped,
        };
        final viewId = (args['viewId'] as num?)?.toInt() ?? 0;
        final x = (args['x'] as num?)?.toDouble() ?? 0.0;
        final y = (args['y'] as num?)?.toDouble() ?? 0.0;
        final paths = [
          for (final p in (args['paths'] as List<Object?>?) ?? const [])
            if (p is String && p.isNotEmpty) p,
        ];
        final event = DesktopDropEvent(
          kind: kind,
          viewId: viewId,
          location: ui.Offset(x, y),
          paths: paths,
        );
        for (final listener in List<DesktopDropListener>.of(_dropListeners)) {
          listener(event);
        }
        return null;

      case 'onBatchRealized':
        final batchId = args['batchId'] as String?;
        if (batchId != null) {
          final paths = [
            for (final p in (args['paths'] as List<Object?>?) ?? const [])
              if (p is String && p.isNotEmpty) p,
          ];
          onBatchRealized?.call(batchId, paths);
        }
        return null;

      case 'onBatchTransferFinished':
        final batchId = args['batchId'] as String?;
        if (batchId != null) {
          onBatchTransferFinished?.call(
            batchId,
            args['success'] == true,
            args['immediateIfUnused'] == true,
          );
        }
        return null;

      case 'onClipboardOwnershipLost':
        final batchId = args['batchId'] as String?;
        if (batchId != null) {
          onClipboardOwnershipLost?.call(batchId);
        }
        return null;

      default:
        return null;
    }
  }
}
