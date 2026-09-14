import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:vaultexplorer/core/api/vault_file_io_api.dart';
import 'package:vaultexplorer/core/providers/vault_engine_providers.dart';
import 'package:vaultexplorer/core/utils/bounded_semaphore.dart';
import 'package:vaultexplorer/core/utils/cancellation_token.dart';
import 'package:vaultexplorer/core/utils/raw_entry.dart';
import 'package:vaultexplorer/core/utils/ve_log.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/features/browser/file_browser_predicates.dart';
import 'package:vaultexplorer/features/browser/mixins/sort_mixin.dart';

part 'media_scan_service.g.dart';

/// Recursion-depth guard for [MediaScanService.scan]'s directory-tree walk.
const mediaScanMaxDepth = 20;

/// Bounded concurrency for [MediaScanService.scan] -- an unthrottled
/// `Future.wait` fan-out let a wide/deep tree spawn one concurrent
/// [VaultFileIoApi.listDirectory] call per subdirectory at every level,
/// which is what actually froze the app on a large tree (worst case: a
/// decoy-mode scan starting from the real device storage root -- see
/// local_storage_container.dart) rather than depth alone.
const mediaScanMaxConcurrency = 6;

/// Hard cap on directories visited during a single scan, so a folder tree
/// with little or no media can't turn into an unbounded whole-storage walk.
const mediaScanMaxFolders = 4000;

/// Stop collecting more matches once there's already plenty to populate
/// the media viewer -- continuing to walk the rest of the tree past this
/// point is diminishing returns for real cost.
const mediaScanMaxResults = 500;

/// How often (in folders checked) [MediaScanService.scan]'s [onProgress]
/// fires with a live count, so a caller's status banner isn't rebuilding
/// on every single directory.
const mediaScanProgressInterval = 20;

class MediaScanResult {
  /// Full paths of every matched media file found before the scan stopped
  /// (completed, cancelled, or hit a limit).
  final List<String> mediaPaths;
  final int foldersChecked;
  final bool limitReached;
  final bool cancelled;

  const MediaScanResult({
    required this.mediaPaths,
    required this.foldersChecked,
    required this.limitReached,
    required this.cancelled,
  });
}

/// No internal mutable state of its own -> pure keep-alive provider per the
/// migration plan's Phase 3 rule, matching [FolderDocumentProviderService]'s
/// shape. Constructor-injected with [VaultFileIoApi] through
/// [vaultFileIoApiProvider] rather than each call site reading the provider
/// itself.
@Riverpod(keepAlive: true)
MediaScanService mediaScanService(Ref ref) =>
    MediaScanService(ref.watch(vaultFileIoApiProvider));

/// Recursively walks a container's directory tree collecting media files,
/// for the file browser's "play media here" action when the current folder
/// itself has none.
///
/// Extracted from `_FileBrowserScreenState` (previously the private
/// `_scanMediaRecursively`/`_ScanSemaphore`/the `_maxScan*` constants, all
/// living directly in file_browser_screen.dart) as part of the
/// file-browser-screen decomposition (tech-debt audit, Sept 2026).
///
/// This logic had zero test coverage in its widget-trapped form, and its
/// cancellation handling -- re-checking the token *after* the semaphore
/// queue, not just before entering [walk] -- is exactly the kind of
/// state-transition detail a real bug already slipped through on: the
/// "scanning subfolders for media" cancel action used to only stop the
/// viewer from *opening*, not the scan itself, on a thousands-of-subfolders
/// tree (see the media-scan-cancel bugfix). Depends only on
/// [VaultFileIoApi] and a [CancellationToken] -- no BuildContext, no widget
/// state -- so it's exercisable with a fake API and a synchronously
/// cancellable token, which is the main point of this extraction: the
/// FileBrowserScreen decomposition report flagged this as the cluster with
/// concrete regression history and zero coverage.
///
/// Callers create a fresh [CancellationToken] per scan attempt (matching
/// the old generation-counter idiom one-for-one: a new token per
/// "start scan" call, cancelled to abandon it) rather than reusing one
/// long-lived token.
class MediaScanService {
  final VaultFileIoApi _fileIoApi;

  MediaScanService(this._fileIoApi);

  Future<MediaScanResult> scan({
    required MountedContainer container,
    required String startPath,
    required CancellationToken token,
    required bool showHiddenFiles,
    required SortBy sortBy,
    required bool sortAscending,
    required Set<String> pinnedPaths,
    required bool Function(String fileName) isSupportedMedia,
    void Function(int foldersChecked)? onProgress,
  }) async {
    var foldersChecked = 0;
    var resultsFound = 0;
    final semaphore = BoundedSemaphore(mediaScanMaxConcurrency);

    Future<List<String>> walk(String dirPath, int depth) async {
      if (token.isCancelled ||
          depth > mediaScanMaxDepth ||
          foldersChecked >= mediaScanMaxFolders ||
          resultsFound >= mediaScanMaxResults) {
        return [];
      }
      final foundFiles = <String>[];
      final matchedEntries = <RawEntry>[];
      final subdirNames = <String>[];
      await semaphore.acquire();
      // A wide directory (e.g. Android/data with hundreds/thousands of
      // per-app folders) fans this call out once per sibling well before
      // any of them reach the semaphore, so most sit queued in acquire()
      // long after the top-of-function cancellation check already passed.
      // Without re-checking here, every queued sibling still pays for a
      // real listDirectory() call after cancellation -- draining that
      // backlog is what made cancel appear to do nothing until the whole
      // tree finished.
      if (token.isCancelled) {
        semaphore.release();
        return [];
      }
      try {
        final items = await _fileIoApi.listDirectory(container, dirPath);
        if (token.isCancelled) return [];
        if (items != null) {
          for (final item in items) {
            if (token.isCancelled) return [];
            if (item.startsWith('System:')) continue;
            final e = RawEntry.parse(item);
            if (!showHiddenFiles && isHiddenEntryName(e.name)) continue;
            if (e.isDir) {
              subdirNames.add(e.name);
            } else if (isSupportedMedia(e.name)) {
              matchedEntries.add(e);
            }
          }
          matchedEntries.sort(
            (a, b) => compareEntriesWithPinned(
              a,
              b,
              sortBy: sortBy,
              sortAscending: sortAscending,
              pinnedPaths: pinnedPaths,
              parentPath: dirPath,
            ),
          );
          foundFiles.addAll(
            matchedEntries.map((e) => dirPath.isEmpty ? e.name : '$dirPath/${e.name}'),
          );
          resultsFound += matchedEntries.length;
        }
      } catch (e) {
        VeLog.e('MediaScanService', 'Media scan failed at ${VeLog.censorUri(dirPath)}', e);
      } finally {
        // Release before recursing into children, not after -- holding
        // this directory's slot for the entire subtree's duration would
        // leave most of the semaphore's concurrency budget idle on deep
        // trees.
        semaphore.release();
        foldersChecked++;
        if (foldersChecked % mediaScanProgressInterval == 0) {
          onProgress?.call(foldersChecked);
        }
      }
      if (subdirNames.isNotEmpty &&
          !token.isCancelled &&
          foldersChecked < mediaScanMaxFolders &&
          resultsFound < mediaScanMaxResults) {
        final nested = await Future.wait(
          subdirNames.map((name) {
            final subPath = dirPath.isEmpty ? name : '$dirPath/$name';
            return walk(subPath, depth + 1);
          }),
        );
        for (final list in nested) {
          foundFiles.addAll(list);
        }
      }
      return foundFiles;
    }

    final results = await walk(startPath, 0);
    return MediaScanResult(
      mediaPaths: results,
      foldersChecked: foldersChecked,
      limitReached: foldersChecked >= mediaScanMaxFolders,
      cancelled: token.isCancelled,
    );
  }
}
