import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/utils/raw_entry.dart';
import 'package:vaultexplorer/core/widgets/common_widgets.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/features/browser/file_browser_screen.dart' show PathSegment;
import 'package:vaultexplorer/features/browser/widgets/breadcrumb_bar.dart';
import 'package:vaultexplorer/features/tools/widgets/vault_browser_sheet_controller.dart';

class VaultBrowserScaffold extends ConsumerWidget {
  final VaultBrowserParams params;
  final String Function(BuildContext context, MountedContainer selectedContainer) appBarTitle;
  final String Function(BuildContext context) emptyMessage;
  final List<RawEntry> Function(List<RawEntry> raw) processEntries;
  final Widget Function(BuildContext context, RawEntry entry) buildEntryTile;
  final Widget Function(BuildContext context) buildBottomBar;

  const VaultBrowserScaffold({
    super.key,
    required this.params,
    required this.appBarTitle,
    required this.emptyMessage,
    required this.processEntries,
    required this.buildEntryTile,
    required this.buildBottomBar,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(vaultBrowserControllerProvider(params));
    final notifier = ref.read(vaultBrowserControllerProvider(params).notifier);
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final processed = processEntries(state.rawEntries);

    final segments = state.pathStack.asMap().entries.map((e) {
      final label = e.key == 0
          ? context.l10n.vaultBrowserRootFolderLabel
          : e.value.split('/').last;
      return PathSegment(label, e.value);
    }).toList();

    return Scaffold(
      appBar: AppBar(
        backgroundColor: cs.surfaceContainerHigh,
        title: Text(
          appBarTitle(context, state.selectedContainer),
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        leading: state.pathStack.length > 1
            ? IconButton(
                icon: const Icon(Icons.arrow_back_rounded),
                onPressed: notifier.navigateUp,
              )
            : IconButton(
                icon: const Icon(Icons.close_rounded),
                onPressed: () => Navigator.pop(context),
              ),
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.only(top: 8, bottom: 8),
            color: cs.surfaceContainerLow,
            child: _buildVaultSelector(context, state, notifier),
          ),
          BreadcrumbBar(
            stack: segments,
            onTap: notifier.jumpTo,
          ),
          Expanded(
            child: state.loading
                ? const Center(child: CircularProgressIndicator())
                : processed.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.folder_open_rounded,
                              size: 48,
                              color: cs.onSurfaceVariant.withValues(alpha: 0.5),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              emptyMessage(context),
                              style: textTheme.bodyMedium?.copyWith(
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.separated(
                        itemCount: processed.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (ctx, i) => Material(
                          color: Colors.transparent,
                          child: buildEntryTile(ctx, processed[i]),
                        ),
                      ),
          ),
        ],
      ),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHigh,
          border: Border(top: BorderSide(color: cs.outlineVariant)),
        ),
        child: SafeArea(child: buildBottomBar(context)),
      ),
    );
  }

  Widget _buildVaultSelector(
    BuildContext context,
    VaultBrowserState state,
    VaultBrowserController notifier,
  ) {
    final canSwitch = params.mountedContainers.length > 1;

    return Material(
      color: Colors.transparent,
      child: OptionPickerTile<int>(
        label: context.l10n.hashVerifierVaultPickerLabel,
        value: state.selectedContainer.volId,
        subtitle: state.selectedContainer.displayName,
        prefixIcon: Icons.folder_special_rounded,
        enabled: canSwitch,
        options: params.mountedContainers
            .map((c) => SelectOption(value: c.volId, label: c.displayName))
            .toList(),
        onChanged: (volId) {
          final container = params.mountedContainers.firstWhere(
            (c) => c.volId == volId,
            orElse: () => params.mountedContainers.first,
          );
          notifier.switchVault(container);
        },
      ),
    );
  }
}