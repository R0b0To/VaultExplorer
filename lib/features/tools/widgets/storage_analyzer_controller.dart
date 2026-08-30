// StorageAnalyzerScreen was a StatefulWidget owning both UI-adjacent state
// (which container is selected) and the actual async scan/breakdown
// results directly. All of it moves here -- there's no TextEditingController
// or similar Flutter-lifecycle object forcing anything to stay local, unlike
// the vault_item edit/detail screens.
//
// The widget still owns `widget.mountedContainers` (a ValueListenable<List
// <MountedContainer>> passed down from the app shell) since that's shared
// infrastructure well beyond this one screen's scope -- this controller
// just reacts to it via [onMountedListChanged], called from the widget's
// listener.
import 'package:vaultexplorer/core/utils/raw_entry.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/data/services/vault_engine/vault_explorer_api.dart';
import 'package:vaultexplorer/features/tools/models/tool_models.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'storage_analyzer_controller.g.dart';

class _CategoryAcc {
  int bytes = 0;
  int count = 0;
}

class StorageAnalyzerState {
  final MountedContainer? selected;
  final bool loading;
  final int? totalBytes;
  final int? freeBytes;
  final List<StorageEntry> heaviest;
  final List<StorageCategoryBreakdown> breakdown;
  final bool truncated;
  final int scannedCount;

  const StorageAnalyzerState({
    this.selected,
    this.loading = false,
    this.totalBytes,
    this.freeBytes,
    this.heaviest = const [],
    this.breakdown = const [],
    this.truncated = false,
    this.scannedCount = 0,
  });
}

@riverpod
class StorageAnalyzer extends _$StorageAnalyzer {
  static const _maxEntries = 5000;
  static const _maxDepth = 16;
  static const _heaviestLimit = 10;

  @override
  StorageAnalyzerState build() => const StorageAnalyzerState();

  /// Reacts to the shared mounted-container list changing: clears results
  /// if nothing is mounted anymore, or re-targets (and rescans) if the
  /// currently selected container was the one that unmounted.
  void onMountedListChanged(List<MountedContainer> list) {
    final selected = state.selected;
    if (list.isEmpty) {
      state = const StorageAnalyzerState();
    } else if (selected == null ||
        !list.any((c) => c.volId == selected.volId)) {
      selectTarget(list.first);
    }
  }

  Future<void> selectTarget(MountedContainer container) async {
    state = StorageAnalyzerState(selected: container);
    await load();
  }

  static String _categorize(String name) {
    final dot = name.lastIndexOf('.');
    if (dot < 0 || dot == name.length - 1) return 'other';
    final ext = name.substring(dot + 1).toLowerCase();
    const images = {'jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp', 'heic', 'svg'};
    const videos = {'mp4', 'mov', 'mkv', 'avi', 'webm', 'm4v', '3gp'};
    const audio = {'mp3', 'wav', 'flac', 'aac', 'ogg', 'm4a', 'wma'};
    const documents = {
      'pdf',
      'doc',
      'docx',
      'xls',
      'xlsx',
      'ppt',
      'pptx',
      'txt',
      'md',
      'odt',
      'csv',
    };
    const archives = {'zip', 'rar', '7z', 'tar', 'gz', 'bz2', 'xz'};

    if (images.contains(ext)) return 'images';
    if (videos.contains(ext)) return 'videos';
    if (audio.contains(ext)) return 'audio';
    if (documents.contains(ext)) return 'documents';
    if (archives.contains(ext)) return 'archives';
    return 'other';
  }

  Future<void> load() async {
    final target = state.selected;
    if (target == null) return;

    state = StorageAnalyzerState(selected: target, loading: true);

    var total = target.totalSpace;
    var free = target.freeSpace;

    try {
      final space = await vaultExplorerApi.getSpaceInfo(target);
      if (space != null && space.length > 1) {
        if (space[0] >= 0) total = space[0];
        if (space[1] >= 0) free = space[1];
      }
    } catch (_) {
      // total/free above already default to target.totalSpace/freeSpace;
      // a failure here just means the analyzer falls back to those instead
      // of the (possibly more precise) native-reported figures.
    }

    final entries = <StorageEntry>[];
    final categoryTotals = <String, _CategoryAcc>{};
    var truncated = false;

    Future<void> walk(String dirPath, int depth) async {
      if (truncated || depth > _maxDepth) return;
      List<String>? raw;
      try {
        raw = await vaultExplorerApi.listDirectory(target, dirPath);
      } catch (_) {
        return;
      }
      if (raw == null) return;

      for (final entry in RawEntry.parseAll(raw)) {
        if (entries.length >= _maxEntries) {
          truncated = true;
          return;
        }
        final fullPath = dirPath.isEmpty
            ? entry.name
            : '$dirPath/${entry.name}';
        if (entry.isDir) {
          await walk(fullPath, depth + 1);
          if (truncated) return;
        } else {
          entries.add(
            StorageEntry(
              path: fullPath,
              name: entry.name,
              sizeBytes: entry.sizeBytes,
            ),
          );
          final acc = categoryTotals.putIfAbsent(
            _categorize(entry.name),
            () => _CategoryAcc(),
          );
          acc.bytes += entry.sizeBytes;
          acc.count += 1;
        }
      }
    }

    await walk('', 0);

    entries.sort((a, b) => b.sizeBytes.compareTo(a.sizeBytes));
    final breakdown =
        categoryTotals.entries
            .map(
              (e) => StorageCategoryBreakdown(
                category: e.key,
                sizeBytes: e.value.bytes,
                fileCount: e.value.count,
              ),
            )
            .toList()
          ..sort((a, b) => b.sizeBytes.compareTo(a.sizeBytes));

    // If ref is gone, or a newer selectTarget/load call has already
    // replaced `selected` while this walk was in flight, drop this scan's
    // results rather than let a stale walk clobber a newer one.
    if (!ref.mounted || state.selected?.volId != target.volId) return;

    state = StorageAnalyzerState(
      selected: target,
      loading: false,
      totalBytes: total,
      freeBytes: free,
      heaviest: entries.take(_heaviestLimit).toList(),
      breakdown: breakdown,
      truncated: truncated,
      scannedCount: entries.length,
    );
  }
}
