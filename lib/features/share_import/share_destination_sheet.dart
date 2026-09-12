import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/data/models/vault_list_item.dart';
import 'package:vaultexplorer/data/services/container_repository.dart';
import 'package:vaultexplorer/features/dashboard/vault_dashboard_controller.dart';
import 'package:vaultexplorer/features/tools/models/tool_models.dart';
import 'package:vaultexplorer/features/tools/widgets/vault_folder_picker_sheet.dart';
import 'package:vaultexplorer/features/unlock/unlock_sheet.dart';
import 'package:vaultexplorer/features/unlock/usb_unlock_sheet.dart';

class ShareDestinationSheet extends ConsumerStatefulWidget {
  const ShareDestinationSheet({super.key});

  @override
  ConsumerState<ShareDestinationSheet> createState() =>
      _ShareDestinationSheetState();
}

class _ShareDestinationSheetState
    extends ConsumerState<ShareDestinationSheet> with WidgetsBindingObserver {
  bool _initialLoadCompleted = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadVaults();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadVaults();
    }
  }

  Future<void> _loadVaults() async {
    try {
      await ref.read(vaultDashboardControllerProvider.notifier).loadAll();
    } catch (_) {
      // Keep error from leaving the loading indicator hung forever
    } finally {
      if (mounted) {
        setState(() {
          _initialLoadCompleted = true;
        });
      }
    }
  }

  Future<void> _unlockAndContinue(ContainerRecord record) async {
    final dashState = ref.read(vaultDashboardControllerProvider);
    if (dashState.actionInFlight) return;
    final notifier = ref.read(vaultDashboardControllerProvider.notifier);
    notifier.setActionInFlight(true);

    String? rememberedPassword;
    if (record.unlockMethod == ContainerUnlockMethod.rememberPassword) {
      rememberedPassword = await ref
          .read(containerRepositoryProvider)
          .getPassword(record.uri);
    }
    final autoMountFolders = record.documentProviderFolders
        .where((f) => f.autoMount)
        .map((f) => f.path)
        .toList();
    final mountedUris = dashState.mounted.map((c) => c.uri).toList();

    MountedContainer? newlyMounted;
    try {
      if (!mounted) return;
      await Navigator.push<void>(
        context,
        MaterialPageRoute(
          builder: (_) => record.isUsbSource
              ? UsbUnlockSheet(
                  existingRecord: record,
                  prefillPassword: rememberedPassword,
                  documentProvider: record.documentProvider,
                  autoMountFolders: autoMountFolders,
                  mountedUris: mountedUris,
                  onMounted: (container, {record}) {
                    notifier.onContainerMounted(container, record: record);
                    newlyMounted = container;
                  },
                  onReconnected: (container, migratedRecord, oldUri) {
                    notifier.onUsbContainerReconnected(
                      container,
                      migratedRecord,
                      oldUri,
                    );
                    newlyMounted = container;
                  },
                )
              : UnlockSheet(
                  initialUri: record.uri,
                  initialName: record.label.isNotEmpty ? record.label : null,
                  prefillPassword: rememberedPassword,
                  documentProvider: record.documentProvider,
                  autoMountFolders: autoMountFolders,
                  mountedUris: mountedUris,
                  onMounted: (container, {record}) {
                    notifier.onContainerMounted(container, record: record);
                    newlyMounted = container;
                  },
                ),
        ),
      );
    } finally {
      if (mounted) notifier.setActionInFlight(false);
    }
    if (!mounted) return;
    await notifier.loadAll();
    final mountedContainer = newlyMounted;
    if (mountedContainer == null) return;
    if (!mounted) return;
    notifier.refreshContainerSpace(mountedContainer.volId);
    if (!mounted) return;
    await _pickFolderAndPop(mountedContainer);
  }

  Future<void> _pickFolderAndPop(MountedContainer container) async {
    final destination = await Navigator.push<CryptoDestination>(
      context,
      MaterialPageRoute(
        builder: (_) =>
            VaultFolderPickerSheet(mountedContainers: [container]),
      ),
    );
    if (destination != null && mounted) {
      Navigator.pop(context, destination);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dashboardState = ref.watch(vaultDashboardControllerProvider);
    final items = ref
        .read(vaultDashboardControllerProvider.notifier)
        .getDisplayItems();
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final showLoading = (items.isEmpty && !_initialLoadCompleted) ||
        (items.isEmpty && dashboardState.isLoading);

    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.saveToVaultTitle)),
      body: showLoading
          ? const Center(child: CircularProgressIndicator(strokeWidth: 2.5))
          : items.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  context.l10n.noVaultsAvailableAddFromDashboardPrompt,
                  textAlign: TextAlign.center,
                  style: textTheme.bodyMedium?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: items.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final item = items[index];
                return ListTile(
                  leading: Icon(
                    item.isMounted
                        ? Icons.lock_open_rounded
                        : Icons.lock_rounded,
                    color: item.isMounted ? cs.primary : cs.onSurfaceVariant,
                  ),
                  title: Text(item.name),
                  subtitle: Text(
                    item.isMounted
                        ? context.l10n.vaultStatusUnlocked
                        : context.l10n.vaultStatusLocked,
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () async {
                    switch (item) {
                      case MountedVaultItem(:final container):
                        await _pickFolderAndPop(container);
                      case LockedVaultItem(:final record):
                        await _unlockAndContinue(record);
                    }
                  },
                );
              },
            ),
    );
  }
}