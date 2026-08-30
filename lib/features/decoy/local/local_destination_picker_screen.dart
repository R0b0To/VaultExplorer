import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/utils/raw_entry.dart';
import 'package:vaultexplorer/features/browser/file_browser_screen.dart' show PathSegment;
import 'package:vaultexplorer/features/browser/widgets/breadcrumb_bar.dart';
import 'package:vaultexplorer/features/browser/widgets/directory_tile.dart';
import 'package:vaultexplorer/features/decoy/local/decoy_local_repository.dart';

/// Folder picker pushed by the decoy local explorer's Copy/Move actions.
/// Deliberately its own tiny screen rather than a mode of the main
/// explorer, since it only ever needs to show folders and return a path.
class LocalDestinationPickerScreen extends StatefulWidget {
  final DecoyLocalRepository repository;
  final String rootPath;
  final String rootLabel;

  /// True for "Move here", false for "Copy here" -- only changes the
  /// floating action button's label/icon.
  final bool confirmMove;

  const LocalDestinationPickerScreen({
    super.key,
    required this.repository,
    required this.rootPath,
    required this.rootLabel,
    required this.confirmMove,
  });

  @override
  State<LocalDestinationPickerScreen> createState() => _LocalDestinationPickerScreenState();
}

class _LocalDestinationPickerScreenState extends State<LocalDestinationPickerScreen> {
  late List<PathSegment> _stack;
  List<RawEntry> _folders = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _stack = [PathSegment(widget.rootLabel, widget.rootPath)];
    _load(widget.rootPath);
  }

  String get _currentPath => _stack.last.fatPath;

  Future<void> _load(String path) async {
    setState(() => _loading = true);
    final entries = await widget.repository.listDirectory(path);
    entries.removeWhere((e) => !e.isDir);
    entries.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    if (!mounted) return;
    setState(() {
      _folders = entries;
      _loading = false;
    });
  }

  void _enter(RawEntry entry) {
    final newPath = p.join(_currentPath, entry.name);
    setState(() => _stack.add(PathSegment(entry.name, newPath)));
    _load(newPath);
  }

  void _jumpTo(int index) {
    if (index == _stack.length - 1) return;
    setState(() => _stack.removeRange(index + 1, _stack.length));
    _load(_currentPath);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _stack.length <= 1,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _jumpTo(_stack.length - 2);
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(context.l10n.filesChooseDestinationTitle),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(40),
            child: BreadcrumbBar(stack: _stack, onTap: _jumpTo),
          ),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView.builder(
                itemCount: _folders.length,
                itemBuilder: (context, index) {
                  final entry = _folders[index];
                  return DirectoryTile(
                    entry: entry,
                    isSelectionMode: false,
                    isSelected: false,
                    onTap: () => _enter(entry),
                    onLongPress: () {},
                  );
                },
              ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => Navigator.of(context).pop(_currentPath),
          icon: Icon(widget.confirmMove ? Icons.drive_file_move_outline : Icons.copy_outlined),
          label: Text(widget.confirmMove ? context.l10n.filesMoveHere : context.l10n.filesCopyHere),
        ),
      ),
    );
  }
}
