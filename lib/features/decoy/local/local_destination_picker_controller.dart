import 'package:path/path.dart' as p;
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:vaultexplorer/core/utils/raw_entry.dart';
import 'package:vaultexplorer/features/browser/file_browser_screen.dart'
    show PathSegment;
import 'package:vaultexplorer/features/decoy/local/decoy_local_repository_provider.dart';

part 'local_destination_picker_controller.g.dart';

class LocalDestinationPickerState {
  final List<PathSegment> stack;
  final List<RawEntry> folders;
  final bool loading;

  const LocalDestinationPickerState({
    required this.stack,
    this.folders = const [],
    this.loading = true,
  });

  String get currentPath => stack.last.fatPath;
}

@riverpod
class LocalDestinationPicker extends _$LocalDestinationPicker {
  @override
  LocalDestinationPickerState build(String rootLabel, String rootPath) {
    final initial = LocalDestinationPickerState(
      stack: [PathSegment(rootLabel, rootPath)],
    );
    Future.microtask(() => _load(rootPath));
    return initial;
  }

  Future<void> _load(String path) async {
    if (!ref.mounted) return;
    state = LocalDestinationPickerState(
      stack: state.stack,
      folders: state.folders,
      loading: true,
    );
    final entries = await ref
        .read(decoyLocalRepositoryProvider)
        .listDirectory(path);
    entries.removeWhere((e) => !e.isDir);
    entries.sort(
      (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
    );
    if (!ref.mounted) return;
    state = LocalDestinationPickerState(
      stack: state.stack,
      folders: entries,
      loading: false,
    );
  }

  void enter(RawEntry entry) {
    final newPath = p.join(state.currentPath, entry.name);
    state = LocalDestinationPickerState(
      stack: [...state.stack, PathSegment(entry.name, newPath)],
      folders: state.folders,
      loading: state.loading,
    );
    _load(newPath);
  }

  void jumpTo(int index) {
    if (index == state.stack.length - 1) return;
    state = LocalDestinationPickerState(
      stack: state.stack.sublist(0, index + 1),
      folders: state.folders,
      loading: state.loading,
    );
    _load(state.currentPath);
  }
}