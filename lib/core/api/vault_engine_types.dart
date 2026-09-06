import 'dart:developer' as developer;

import 'package:vaultexplorer/data/models/crypto_algorithms.dart';
import 'package:vaultexplorer/data/models/clipboard_item.dart';

typedef KeyfileRef = ({String uri, String displayName});

typedef UnlockProgress = ({
  int volId,
  int attempted,
  int total,
  int hashId,
  int cipherId,
  String containerFormat,
  int slot,
});

typedef ImportProgress = ({
  int opId,
  int done,
  int total,
  String currentName,
  int transferredBytes,
  int totalBytes,
});

typedef ImportItemFinished = ({
  int opId,
  String sourceName,
  String resolvedName,
  bool isDir,
  bool success,
});

enum CarrierTier {
  high(0, 'Spec-Guaranteed Padding'),
  medium(1, 'Metadata Segment'),
  low(2, 'Trailing Append');

  final int id;
  final String label;
  const CarrierTier(this.id, this.label);

  static CarrierTier fromId(int id) => switch (id) {
        0 => CarrierTier.high,
        1 => CarrierTier.medium,
        _ => CarrierTier.low,
      };
}

typedef CarrierBudget = ({
  int fileIndex,
  String path,
  String detectedFormat,
  int fileSize,
  int payloadOffset,
  int allocatableBytes,
  CarrierTier tier,
});

typedef CapacityProfile = ({
  int totalAllocatableBytes,
  List<CarrierBudget> carriers,
});

/// Export-side counterpart to [ImportProgress] -- see ExportProgressBridge.kt.
typedef ExportProgress = ({
  int opId,
  int done,
  int total,
  String currentName,
  int transferredBytes,
  int totalBytes,
});

/// Export-side counterpart to [ImportItemFinished]. No `resolvedName` --
/// export never renames an entry the way import's conflict resolution can.
typedef ExportItemFinished = ({
  int opId,
  String sourceName,
  bool isDir,
  bool success,
});

typedef ImportPickConflict = ({String name, bool destIsDir});

typedef ImportPickResult = ({
  int pickToken,
  List<ImportPickConflict> conflicts,
  List<ClipboardItem> items,
});

/// One file/item the person shared into the app from another app via the
/// Android Share Sheet (ACTION_SEND/ACTION_SEND_MULTIPLE), before a
/// destination vault/folder has been chosen -- see
/// IncomingShareBridge.kt/ShareIntentHandlers.kt and
/// `lib/features/share_import/`. [uri] is native's content:// URI as a
/// string, opaque to Dart; it's only ever round-tripped back into
/// `VaultFileIoApi.prepareShareImport`'s native counterpart, never parsed
/// here.
typedef IncomingShareItem = ({
  String uri,
  String displayName,
  int sizeBytes,
  String? mimeType,
});

typedef IncomingShareRequest = ({List<IncomingShareItem> items});

/// Shared by [VaultEngineEvents]'s `onIncomingShareRequest` push handler and
/// `VaultFileIoApi.checkPendingShareRequest`'s pull -- both receive the same
/// `{"uri", "displayName", "sizeBytes", "mimeType"}` wire shape from
/// IncomingShareBridge.kt and should parse it identically. Returns `null`
/// for an entry with no usable `uri` rather than throwing, so one
/// unresolvable item doesn't take the rest of the share request down with
/// it.
IncomingShareItem? incomingShareItemFromWire(Map<Object?, Object?> map) {
  final uri = map['uri'] as String?;
  if (uri == null || uri.isEmpty) return null;
  return (
    uri: uri,
    displayName: (map['displayName'] as String?) ?? uri.split('/').last,
    sizeBytes: (map['sizeBytes'] as num?)?.toInt() ?? 0,
    mimeType: map['mimeType'] as String?,
  );
}

typedef SplitJoinProgress = ({int opId, int bytesDone, int bytesTotal});

typedef CopyProgress = ({int opId, int bytesDelta});

typedef HashProgress = ({int opId, int bytesDone, int bytesTotal});

typedef RepairLogLine = ({int opId, String message});

String hashAlgorithmName(int hashId) => HashAlgo.nameFor(hashId);
String cipherAlgorithmName(int cipherId) => CipherAlgo.nameFor(cipherId);

/// Error sink for channel failures that callers deliberately don't
/// surface to the UI (they only need a bool/null/default back, and
/// showing every transient failure would be noise). Was a no-op kept from
/// the pre-migration code (see git history on the old
/// VaultExplorerApi._logSwallowed) -- callers already pass the failed
/// method name + error here specifically so a future implementation could
/// wire in real logging without touching every one of those call sites
/// again. This is that wiring: routes through `dart:developer.log` under
/// the 'swallowed' name so these failures are still visible in
/// `flutter logs`/DevTools and in the app's own in-app log viewer (see
/// LogcatService) instead of vanishing with no trace. [expected] failures
/// (e.g. a picker the user cancelled) log at FINE rather than WARNING so
/// they don't drown out genuine ones when scanning the log.
void logSwallowed(String method, Object error, {bool expected = false}) {
  developer.log(
    '$method: $error',
    name: 'swallowed',
    level: expected ? 500 : 900,
  );
}
