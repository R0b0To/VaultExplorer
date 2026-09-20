import 'package:vaultexplorer/features/sync/domain/models/sync_state_record.dart';
import 'package:vaultexplorer/features/sync/domain/sync_cancellation.dart';
import 'package:vaultexplorer/features/sync/domain/sync_ignore_matcher.dart';

/// One side of a sync pair: a folder inside a vault, on device storage, in
/// an SAF tree, or inside another unlocked vault.
///
/// Deliberately *not* a byte-stream interface. Bytes of a vault never
/// cross into Dart's own logic in this app -- the engine copies them
/// natively (`VaultFileIoApi.copyFile`) or, for pairings the native call
/// can't do, in short chunked read/write hops. So the interface is
/// expressed in terms of whole-file operations, and [copyFrom] is where an
/// implementation picks the fastest route for its source/destination
/// combination.
///
/// All paths are relative to the endpoint's root, `/`-separated, without a
/// leading slash.
abstract class SyncEndpoint {
  /// Short name for status text ("Documents").
  String get label;

  /// Whether files on this side are encrypted at rest (vaults). Copying
  /// from an encrypted to a non-encrypted endpoint writes plaintext.
  bool get isEncrypted;

  /// Lists every file under the root.
  ///
  /// Folders that fail to list end up in [SyncSnapshot.unreadableDirs]
  /// instead of being treated as empty. Files matching [ignore] are
  /// omitted, except the engine's own `*.vexp_tmp` / `*.vexp_old`
  /// leftovers, which are reported in [SyncSnapshot.leftovers].
  Future<SyncSnapshot> scan({
    required SyncIgnoreMatcher ignore,
    required SyncCancellationToken token,
  });

  /// Current size/mtime of each of [relPaths] that exists; missing files
  /// are absent from the result.
  Future<Map<String, SyncSideState>> stat(Iterable<String> relPaths);

  /// Lowercase hex SHA-256 of the file, or null if it can't be read.
  /// Cancellation surfaces as [SyncCancelledException].
  Future<String?> hash(String relPath, SyncCancellationToken token);

  /// Creates [relDir] and any missing parents. True if it exists after.
  Future<bool> ensureDirectory(String relDir);

  /// Writes [destRel] on this endpoint with the contents of [sourceRel] on
  /// [source]. Writes to exactly [destRel] -- the *executor* is
  /// responsible for making that a temp name and swapping it into place.
  ///
  /// [opId] identifies the operation to the native cancellation plumbing.
  /// Returns false on failure; throws [SyncCancelledException] when
  /// [token] is cancelled mid-copy.
  Future<bool> copyFrom(
    SyncEndpoint source,
    String sourceRel,
    String destRel, {
    required int opId,
    required SyncCancellationToken token,
  });

  /// Renames within this endpoint. Fails (returns false) rather than
  /// replacing when [toRel] already exists -- the engine relies on that
  /// being the storage layer's rule, and never depends on replace-on-rename.
  Future<bool> rename(String fromRel, String toRel);

  /// Deletes a file. False if it couldn't be deleted.
  Future<bool> delete(String relPath);

  /// Best-effort: give [relPath] the modified time [mtimeSecs] so copies
  /// keep their source's timestamp. False where unsupported (SAF).
  Future<bool> setModified(String relPath, int mtimeSecs);
}
