import 'package:flutter/services.dart';
import 'package:vaultexplorer/core/api/vault_engine_types.dart';

enum DisguiseMode {
  vault,
  decoy;

  static DisguiseMode fromWire(String? raw) =>
      raw == 'decoy' ? DisguiseMode.decoy : DisguiseMode.vault;

  String get wireValue => switch (this) {
    DisguiseMode.vault => 'vault',
    DisguiseMode.decoy => 'decoy',
  };
}

typedef PickedLocalPdf = ({String uri, String displayName});

/// Result of [DisguiseModeApi.importSharedUrisToLocal].
typedef LocalShareImportResult = ({int savedCount, int failedCount});

const _channel = MethodChannel('com.aeidolon.vaultexplorer/disguise_channel');

void _logSwallowed(String method, Object error) {}

class DisguiseModeApi {
  const DisguiseModeApi();

  Future<DisguiseMode> getMode() async {
    try {
      final result = await _channel.invokeMethod<String>('getMode');
      return DisguiseMode.fromWire(result);
    } catch (e) {
      _logSwallowed('getMode', e);
      return DisguiseMode.vault;
    }
  }

  Future<void> setMode(DisguiseMode mode) async {
    await _channel.invokeMethod<void>('setMode', {'mode': mode.wireValue});
  }

  Future<PickedLocalPdf?> consumePendingOpenRequest() async {
    try {
      final result = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'consumePendingOpenRequest',
      );
      if (result == null) return null;

      final uri = result['uri'] as String?;
      if (uri == null || uri.isEmpty) return null;

      return (
        uri: uri,
        displayName: (result['displayName'] as String?) ?? 'Document.pdf',
      );
    } catch (e) {
      _logSwallowed('consumePendingOpenRequest', e);
      return null;
    }
  }

  Future<String?> cacheContentUri(String uri) async {
    try {
      return await _channel.invokeMethod<String>('cacheContentUri', {'uri': uri});
    } catch (e) {
      _logSwallowed('cacheContentUri', e);
      return null;
    }
  }

  void setExternalOpenRequestListener(void Function(PickedLocalPdf) onRequest) {
    _channel.setMethodCallHandler((call) async {
      if (call.method != 'externalOpenRequest') return null;

      final args = call.arguments;
      if (args is! Map) return null;

      final uri = args['uri'] as String?;
      if (uri == null || uri.isEmpty) return null;

      onRequest((
        uri: uri,
        displayName: (args['displayName'] as String?) ?? 'Document.pdf',
      ));
      return null;
    });
  }

  // --- Decoy-identity share receipt -----------------------------------
  //
  // Counterpart of VaultFileIoApi's checkPendingShareRequest/
  // cancelPendingShareRequest/prepareShareImport, for a share that
  // arrived while Mask Mode's decoy identity was active (see
  // ShareIntentHandlers.kt/LocalIncomingShareBridge.kt and
  // lib/features/decoy/local/decoy_share_import_flow.dart). Deliberately
  // routed through this disguise_channel rather than the main engine
  // one -- see LocalIncomingShareBridge.kt's doc comment for why.

  /// Mirrors `VaultFileIoApi.checkPendingShareRequest`'s pull -- see its
  /// doc comment. Same wire shape (`{"items": [...]}`), reused here via
  /// [incomingShareItemFromWire] rather than duplicated.
  Future<IncomingShareRequest?> checkPendingLocalShareRequest() async {
    try {
      final result = await _channel.invokeMethod<Map<Object?, Object?>>(
        'checkPendingLocalShareRequest',
      );
      if (result == null) return null;
      final rawItems = (result['items'] as List?) ?? const [];
      final items = rawItems
          .map((it) => incomingShareItemFromWire(it as Map<Object?, Object?>))
          .whereType<IncomingShareItem>()
          .toList();
      if (items.isEmpty) return null;
      return (items: items);
    } catch (e) {
      _logSwallowed('checkPendingLocalShareRequest', e);
      return null;
    }
  }

  /// Atomically retrieves and consumes whatever's currently buffered in
  /// `LocalIncomingShareBridge`, clearing the pending buffer.
  Future<IncomingShareRequest?> takePendingLocalShareRequest() async {
    try {
      final result = await _channel.invokeMethod<Map<Object?, Object?>>(
        'takePendingLocalShareRequest',
      );
      if (result == null) return null;
      final rawItems = (result['items'] as List?) ?? const [];
      final items = rawItems
          .map((it) => incomingShareItemFromWire(it as Map<Object?, Object?>))
          .whereType<IncomingShareItem>()
          .toList();
      if (items.isEmpty) return null;
      return (items: items);
    } catch (e) {
      _logSwallowed('takePendingLocalShareRequest', e);
      return null;
    }
  }

  /// Mirrors `VaultFileIoApi.cancelPendingShareRequest` -- call when the
  /// person backs out of the decoy's destination-folder picker before
  /// confirming a save location.
  Future<void> cancelPendingLocalShareRequest() async {
    try {
      await _channel.invokeMethod<void>('cancelPendingLocalShareRequest');
    } catch (e) {
      _logSwallowed('cancelPendingLocalShareRequest', e);
    }
  }

  /// Streams whatever's currently buffered in `LocalIncomingShareBridge`
  /// straight to plain files under [destDirPath] (an absolute filesystem
  /// path, already resolved via `LocalFileIoBackend.resolve` -- there's
  /// no container/relativePath split to preserve here the way there is
  /// for a real vault). No two-phase pick/conflict-resolution step: the
  /// destination is always an ordinary folder on device storage a person
  /// just browsed to, so a same-name collision is resolved by appending
  /// " (1)" the way most file managers do, natively, rather than asking.
  Future<LocalShareImportResult> importSharedUrisToLocal(
    String destDirPath,
  ) async {
    try {
      final result = await _channel.invokeMapMethod<String, dynamic>(
        'importSharedUrisToLocal',
        {'destDirPath': destDirPath},
      );
      return (
        savedCount: (result?['savedCount'] as num?)?.toInt() ?? 0,
        failedCount: (result?['failedCount'] as num?)?.toInt() ?? 0,
      );
    } catch (e) {
      _logSwallowed('importSharedUrisToLocal', e);
      return (savedCount: 0, failedCount: 0);
    }
  }

  /// Moves whatever's currently buffered for the decoy identity over to
  /// the real vault's share-import buffer, so it's waiting once (if) the
  /// person authenticates -- see `ShareIntentHandlers
  /// .handleHandoffLocalShareToVault`'s doc comment for the full
  /// reasoning, in particular why this is a move, not a copy. Returns
  /// whether there was actually anything to hand off.
  Future<bool> handoffLocalShareToVault() async {
    try {
      return await _channel.invokeMethod<bool>('handoffLocalShareToVault') ?? false;
    } catch (e) {
      _logSwallowed('handoffLocalShareToVault', e);
      return false;
    }
  }

  /// Mirrors `VaultEngineEvents`' `onIncomingShareRequest` push handler,
  /// scoped to this one channel. Pass `null` to unregister (e.g. from a
  /// `dispose()`) -- this channel only ever has one handler installed at
  /// a time, matching [setExternalOpenRequestListener] above; the two
  /// aren't meant to be registered simultaneously.
  void setLocalIncomingShareRequestListener(
    void Function(IncomingShareRequest)? onRequest,
  ) {
    if (onRequest == null) {
      _channel.setMethodCallHandler(null);
      return;
    }
    _channel.setMethodCallHandler((call) async {
      if (call.method != 'onLocalIncomingShareRequest') return null;
      final args = call.arguments;
      if (args is! Map) return null;
      final rawItems = (args['items'] as List?) ?? const [];
      final items = rawItems
          .map((it) => incomingShareItemFromWire(it as Map<Object?, Object?>))
          .whereType<IncomingShareItem>()
          .toList();
      if (items.isEmpty) return null;
      onRequest((items: items));
      return null;
    });
  }
}

DisguiseModeApi disguiseModeApi = const DisguiseModeApi();