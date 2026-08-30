import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/features/browser/widgets/breadcrumb_bar.dart';
import 'package:vaultexplorer/features/browser/widgets/directory_tile.dart';
import 'package:vaultexplorer/features/decoy/local/local_destination_picker_controller.dart';

/// Folder picker pushed by the decoy local explorer's Copy/Move actions.
/// Deliberately its own tiny screen rather than a mode of the main
/// explorer, since it only ever needs to show folders and return a path.
class LocalDestinationPickerScreen extends ConsumerWidget {
  final String rootPath;
  final String rootLabel;

  /// True for "Move here", false for "Copy here" -- only changes the
  /// floating action button's label/icon.
  final bool confirmMove;

  const LocalDestinationPickerScreen({
    super.key,
    required this.rootPath,
    required this.rootLabel,
    required this.confirmMove,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(
      localDestinationPickerProvider(rootLabel, rootPath),
    );
    final notifier = ref.read(
      localDestinationPickerProvider(rootLabel, rootPath).notifier,
    );

    return PopScope(
      canPop: state.stack.length <= 1,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        notifier.jumpTo(state.stack.length - 2);
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(context.l10n.filesChooseDestinationTitle),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(40),
            child: BreadcrumbBar(stack: state.stack, onTap: notifier.jumpTo),
          ),
        ),
        body: state.loading
            ? const Center(child: CircularProgressIndicator())
            : ListView.builder(
                itemCount: state.folders.length,
                itemBuilder: (context, index) {
                  final entry = state.folders[index];
                  return DirectoryTile(
                    entry: entry,
                    isSelectionMode: false,
                    isSelected: false,
                    onTap: () => notifier.enter(entry),
                    onLongPress: () {},
                  );
                },
              ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => Navigator.of(context).pop(state.currentPath),
          icon: Icon(
            confirmMove ? Icons.drive_file_move_outline : Icons.copy_outlined,
          ),
          label: Text(
            confirmMove
                ? context.l10n.filesMoveHere
                : context.l10n.filesCopyHere,
          ),
        ),
      ),
    );
  }
}