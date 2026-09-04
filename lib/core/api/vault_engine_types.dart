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
