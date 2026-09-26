import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/theme/app_theme.dart';
import 'package:vaultexplorer/core/utils/sensitive_clipboard.dart';
import 'package:vaultexplorer/core/utils/totp_engine.dart';
import 'package:vaultexplorer/core/widgets/common_widgets.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/data/models/vault_item.dart';
import 'package:vaultexplorer/data/services/app_settings_service.dart';
import 'package:vaultexplorer/features/authenticator/authenticator_registry_controller.dart';
import 'package:vaultexplorer/features/authenticator/authenticator_settings_screen.dart';
import 'package:vaultexplorer/features/authenticator/widgets/totp_code_tile.dart';
import 'package:vaultexplorer/features/dashboard/vault_dashboard_controller.dart';
import 'package:vaultexplorer/features/settings/app_settings_controller.dart';
import 'package:vaultexplorer/features/vault_item/vault_item_detail_screen.dart';
import 'package:vaultexplorer/features/vault_item/vault_item_edit_screen.dart';

class AuthenticatorScreen extends ConsumerStatefulWidget {
  const AuthenticatorScreen({super.key});

  @override
  ConsumerState<AuthenticatorScreen> createState() => _AuthenticatorScreenState();
}

class _AuthenticatorScreenState extends ConsumerState<AuthenticatorScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      final query = _searchController.text.trim();
      if (query != _searchQuery) {
        setState(() {
          _searchQuery = query;
        });
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  bool _matchesQuery(TotpVaultEntry entry, String query) {
    if (query.isEmpty) return true;
    final q = query.toLowerCase();
    final title = entry.item.title.toLowerCase();
    final issuer = (entry.item.fields['issuer'] ?? '').toLowerCase();
    final username = (entry.item.fields['username'] ?? '').toLowerCase();
    final account = (entry.item.fields['account'] ?? '').toLowerCase();
    return title.contains(q) ||
        issuer.contains(q) ||
        username.contains(q) ||
        account.contains(q);
  }

  Future<void> _copy(BuildContext context, TotpVaultEntry entry) async {
    final label = context.l10n.authenticatorCodeLabel;
    final code = _generateOrNull(entry.item.fields);
    if (code == null) return;
    await ref.read(sensitiveClipboardProvider).copy(code);
    if (!context.mounted) return;
    showAppSnackBar(context, message: context.l10n.labelCopiedToClipboard(label), tone: AppBannerTone.success);
  }

  Future<void> _copyNext(BuildContext context, TotpVaultEntry entry) async {
    final label = context.l10n.authenticatorNextCodeLabel;
    final code = _generateNextOrNull(entry.item.fields);
    if (code == null) return;
    await ref.read(sensitiveClipboardProvider).copy(code);
    if (!context.mounted) return;
    showAppSnackBar(context, message: context.l10n.labelCopiedToClipboard(label), tone: AppBannerTone.success);
  }

  String? _generateOrNull(Map<String, String> fields) {
    try {
      return TotpEngine.generateCode(TotpConfig.fromFields(fields));
    } on TotpCodeException {
      return null;
    }
  }

  String? _generateNextOrNull(Map<String, String> fields) {
    try {
      return TotpEngine.generateNextCode(TotpConfig.fromFields(fields));
    } on TotpCodeException {
      return null;
    }
  }

  void _open(BuildContext context, TotpVaultEntry entry) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => VaultItemDetailScreen(
          container: entry.container,
          item: entry.item,
          filePath: entry.relativePath,
        ),
      ),
    );
  }

  Future<void> _addNew(BuildContext context, List<MountedContainer> mounted) async {
    final writable = mounted.where((c) => !c.readOnly).toList();
    if (writable.isEmpty) return;

    MountedContainer? target = writable.length == 1 ? writable.first : null;
    target ??= await showModalBottomSheet<MountedContainer>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, AppSpacing.sm),
              child: Text(
                context.l10n.authenticatorChooseVaultTitle,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            for (final container in writable)
              ListTile(
                leading: const Icon(Icons.lock_open_rounded),
                title: Text(container.displayName),
                onTap: () => Navigator.pop(sheetContext, container),
              ),
            const SizedBox(height: AppSpacing.sm),
          ],
        ),
      ),
    );
    if (target == null || !context.mounted) return;

    final resultPath = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => VaultItemEditScreen(
          container: target!,
          type: VaultItemType.authenticator,
          currentDirPath: '',
        ),
      ),
    );
    if (resultPath != null) {
      await ref.read(authenticatorRegistryProvider.notifier).refreshContainer(target);
    }
  }

  Widget _buildSearchBar(ColorScheme cs) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: cs.surface,
      child: TextField(
        controller: _searchController,
        decoration: InputDecoration(
          hintText: context.l10n.search,
          prefixIcon: const Icon(Icons.search_rounded, size: 20),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear_rounded, size: 20),
                  tooltip: context.l10n.closeSearchTooltip,
                  onPressed: () => _searchController.clear(),
                )
              : null,
          filled: true,
          fillColor: cs.surfaceContainerHighest,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadius.xl),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final mounted = ref.watch(vaultDashboardControllerProvider.select((s) => s.mounted));
    final registry = ref.watch(authenticatorRegistryProvider);
    final settings = ref.watch(appSettingsControllerProvider.select((s) => s.settings));
    final cs = context.colors;

    final filteredEntries = _searchQuery.isEmpty
        ? registry.entries
        : registry.entries.where((e) => _matchesQuery(e, _searchQuery)).toList();

    final byVault = <int, List<TotpVaultEntry>>{};
    for (final entry in filteredEntries) {
      (byVault[entry.container.volId] ??= []).add(entry);
    }
    for (final list in byVault.values) {
      list.sort((a, b) => a.item.title.toLowerCase().compareTo(b.item.title.toLowerCase()));
    }
    final orderedVaults = mounted.where((c) => byVault.containsKey(c.volId)).toList();
    final writableMounted = mounted.where((c) => !c.readOnly).toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.authenticatorScreenTitle),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: context.l10n.settingsTooltip,
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AuthenticatorSettingsScreen()),
            ),
          ),
        ],
      ),
      floatingActionButton: writableMounted.isEmpty || !settings.enableAuthenticator
          ? null
          : FloatingActionButton(
              tooltip: context.l10n.authenticatorAddButtonTooltip,
              onPressed: () => _addNew(context, mounted),
              child: const Icon(Icons.add_rounded),
            ),
      body: SafeArea(
        child: Column(
          children: [
            if (settings.authenticatorSearchPlacement == AuthenticatorSearchPlacement.top &&
                registry.hasAnyEntry &&
                settings.enableAuthenticator)
              _buildSearchBar(cs),
            Expanded(
              child: RefreshIndicator(
                onRefresh: () => ref.read(authenticatorRegistryProvider.notifier).refreshAll(),
                child: !settings.enableAuthenticator
                    ? _EmptyState(
                        icon: Icons.shield_outlined,
                        message: context.l10n.authenticatorEnableSubtitle,
                      )
                    : mounted.isEmpty
                    ? _EmptyState(
                        icon: Icons.lock_outline_rounded,
                        message: context.l10n.authenticatorNoVaultsUnlockedMessage,
                      )
                    : registry.entries.isEmpty && registry.scanningVolIds.isNotEmpty
                    ? const Center(child: CircularProgressIndicator())
                    : registry.entries.isEmpty
                    ? _EmptyState(
                        icon: Icons.verified_user_outlined,
                        title: context.l10n.authenticatorEmptyStateTitle,
                        message: context.l10n.authenticatorEmptyStateMessage,
                      )
                    : orderedVaults.isEmpty && _searchQuery.isNotEmpty
                    ? _EmptyState(
                        icon: Icons.search_off_rounded,
                        message: context.l10n.noResultsTitle,
                      )
                    : ListView.builder(
                        padding: AppSpacing.pagePadding,
                        itemCount: orderedVaults.length,
                        itemBuilder: (context, index) {
                          final container = orderedVaults[index];
                          final entries = byVault[container.volId] ?? const [];
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (index > 0) const SizedBox(height: AppSpacing.md),
                              Padding(
                                padding: const EdgeInsets.only(left: 4, bottom: 4),
                                child: Row(
                                  children: [
                                    Icon(Icons.folder_shared_outlined, size: AppIconSize.small, color: cs.primary),
                                    const SizedBox(width: 6),
                                    Text(
                                      container.displayName,
                                      style: Theme.of(context).textTheme.labelLarge?.copyWith(color: cs.primary),
                                    ),
                                    if (registry.scanningVolIds.contains(container.volId)) ...[
                                      const SizedBox(width: 8),
                                      SizedBox(
                                        width: 12,
                                        height: 12,
                                        child: CircularProgressIndicator(strokeWidth: 2, color: cs.primary),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              for (var i = 0; i < entries.length; i++) ...[
                                if (i > 0) const SizedBox(height: 10),
                                TotpCodeTile(
                                  key: ValueKey(entries[i].id),
                                  entry: entries[i],
                                  showNumbers: settings.authenticatorShowNumbers,
                                  onCopy: () => _copy(context, entries[i]),
                                  onCopyNext: () => _copyNext(context, entries[i]),
                                  onOpen: () => _open(context, entries[i]),
                                ),
                              ],
                            ],
                          );
                        },
                      ),
              ),
            ),
            if (settings.authenticatorSearchPlacement == AuthenticatorSearchPlacement.bottom &&
                registry.hasAnyEntry &&
                settings.enableAuthenticator)
              _buildSearchBar(cs),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String? title;
  final String message;

  const _EmptyState({required this.icon, this.title, required this.message});

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: AppIconSize.hero, color: cs.onSurfaceVariant),
                  const SizedBox(height: AppSpacing.md),
                  if (title != null) ...[
                    Text(
                      title!,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                  ],
                  Text(
                    message,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}