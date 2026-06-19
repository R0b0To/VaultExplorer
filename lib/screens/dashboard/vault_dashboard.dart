import 'package:flutter/material.dart';

import '../../models/mounted_container.dart';
import '../../services/saved_containers.dart';
import '../unlock/unlock_sheet.dart';
import 'widgets/container_card.dart';
import 'widgets/empty_state.dart';

class VaultDashboard extends StatefulWidget {
  const VaultDashboard({Key? key}) : super(key: key);

  @override
  State<VaultDashboard> createState() => _VaultDashboardState();
}

class _VaultDashboardState extends State<VaultDashboard> {
  final List<MountedContainer> _mounted = [];
  List<Map<String, String>> _saved = [];

  @override
  void initState() {
    super.initState();
    _loadSaved();
  }

  Future<void> _loadSaved() async {
    final saved = await SavedContainerService.loadContainers();
    if (mounted) setState(() => _saved = saved);
  }

  void _onContainerMounted(MountedContainer container) {
    setState(() => _mounted.add(container));
  }

  void _onContainerLocked(int volId) {
    setState(() => _mounted.removeWhere((c) => c.volId == volId));
  }

  Future<void> _showUnlockSheet({String? uri, String? name}) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => UnlockSheet(
        onMounted: _onContainerMounted,
        initialUri: uri,
        initialName: name,
      ),
    );
    _loadSaved(); // Refresh to catch if a new container was remembered
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final atLimit = _mounted.length >= 4;

    // Combine mounted and unmounted/saved items for the dashboard
    final displayItems = <dynamic>[];
    displayItems.addAll(_mounted);
    for (final s in _saved) {
      if (!_mounted.any((m) => m.uri == s['uri'])) {
        displayItems.add(s);
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Icon(Icons.lock_outline, size: 16, color: cs.primary),
            const SizedBox(width: 8),
            const Text('vaultexplorer'),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: atLimit
                ? Tooltip(
                    message: 'Maximum 4 containers mounted',
                    child: Icon(Icons.add, color: cs.outline),
                  )
                : IconButton(
                    onPressed: () => _showUnlockSheet(),
                    icon: const Icon(Icons.add),
                    tooltip: 'Mount container',
                  ),
          ),
        ],
      ),
      body: displayItems.isEmpty
          ? EmptyState(onAdd: () => _showUnlockSheet())
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: displayItems.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (_, i) {
                final item = displayItems[i];
                if (item is MountedContainer) {
                  return ContainerCard(
                    container: item,
                    onLocked: _onContainerLocked,
                  );
                } else {
                  return SavedContainerCard(
                    name: item['name'] as String,
                    uri: item['uri'] as String,
                    onUnlock: () => _showUnlockSheet(
                      uri: item['uri'] as String,
                      name: item['name'] as String,
                    ),
                    onForget: () async {
                      await SavedContainerService.removeContainer(
                          item['uri'] as String);
                      _loadSaved();
                    },
                  );
                }
              },
            ),
    );
  }
}