// Cross-domain typedefs and helpers shared by the VaultXxxApi classes in
// lib/core/api/. Extracted from the legacy `part of` files under
// lib/data/services/vault_engine/ during the Riverpod migration (Phase 2).
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

typedef SplitJoinProgress = ({int opId, int bytesDone, int bytesTotal});

typedef CopyProgress = ({int opId, int bytesDelta});

typedef HashProgress = ({int opId, int bytesDone, int bytesTotal});

typedef RepairLogLine = ({int opId, String message});

String hashAlgorithmName(int hashId) => HashAlgo.nameFor(hashId);
String cipherAlgorithmName(int cipherId) => CipherAlgo.nameFor(cipherId);

/// No-op error sink kept from the pre-migration code (see git history on
/// the old VaultExplorerApi._logSwallowed) -- callers pass the failed
/// method name + error so a future implementation can wire in real
/// logging without touching every call site again.
void logSwallowed(String method, Object error, {bool expected = false}) {}
