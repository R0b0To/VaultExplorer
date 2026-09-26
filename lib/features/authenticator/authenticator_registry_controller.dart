// Built-in TOTP authenticator's cross-vault aggregation: watches which
// vaults are currently mounted (dashboard's own state -- see
// vaultDashboardControllerProvider) and, for each one, walks its
// filesystem for vault-item files carrying a non-empty `totp_secret`
// field -- whether that's a dedicated VaultItemType.authenticator entry or
// an ordinary `password` item with its optional 2FA field filled in. Both
// feed the same registry with no type-specific branching, since both use
// the identical field key (see VaultItemTemplate.fieldsFor).
//
// This is what backs the AppBar's dynamic Authenticator icon
// (AppBarAuthenticatorButton) and the aggregated AuthenticatorScreen list.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:vaultexplorer/core/providers/vault_engine_providers.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/data/models/vault_item.dart';
import 'package:vaultexplorer/data/services/vault_items_service.dart';
import 'package:vaultexplorer/features/dashboard/vault_dashboard_controller.dart';
import 'package:vaultexplorer/features/settings/app_settings_controller.dart';
import 'package:vaultexplorer/features/tools/services/vault_file_scanner.dart';

part 'authenticator_registry_controller.g.dart';

/// One TOTP-capable vault item, plus enough context (which vault, which
/// path) to reload, edit, or delete it later.
@immutable
class TotpVaultEntry {
  final MountedContainer container;

  /// Vault-relative path (see [VaultFile.relativePath]) -- needed to
  /// reload or navigate to the underlying item.
  final String relativePath;

  final VaultItem item;

  const TotpVaultEntry({
    required this.container,
    required this.relativePath,
    required this.item,
  });

  /// Stable identity across rescans -- a given file within a given mounted
  /// vault. (Not across lock/unlock: a volume slot can be reused by a
  /// different vault, same as everywhere else volId is treated as
  /// ephemeral.)
  String get id => '${container.volId}:$relativePath';

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is TotpVaultEntry && other.id == id);

  @override
  int get hashCode => id.hashCode;
}

@immutable
class AuthenticatorRegistryState {
  /// Every TOTP-capable item found so far, across every currently mounted
  /// vault. Populated incrementally as each vault's scan completes, so the
  /// AppBar icon/screen can show entries from a fast-scanning small vault
  /// before a much larger one finishes.
  final List<TotpVaultEntry> entries;

  /// Vaults whose scan is currently in flight -- lets the UI show a subtle
  /// per-vault loading state instead of pretending a vault has zero codes
  /// while it's still being walked.
  final Set<int> scanningVolIds;

  const AuthenticatorRegistryState({
    this.entries = const [],
    this.scanningVolIds = const {},
  });

  bool get hasAnyEntry => entries.isNotEmpty;
}

@Riverpod(keepAlive: true)
class AuthenticatorRegistry extends _$AuthenticatorRegistry {
  // Keyed by volId rather than flattened into `state.entries` directly so
  // a rescan of one vault (refreshContainer) can replace just that
  // vault's slice without disturbing entries from every other mounted
  // vault -- and so a lock/unlock of vault A can't accidentally touch
  // vault B's already-scanned results.
  final Map<int, List<TotpVaultEntry>> _byVolId = {};
  final Set<int> _scanning = {};

 @override
  AuthenticatorRegistryState build() {
    final mounted = ref.watch(
      vaultDashboardControllerProvider.select((s) => s.mounted),
    );
    final enabled = ref.watch(
      appSettingsControllerProvider.select((s) => s.settings.enableAuthenticator),
    );

    if (!enabled) {
      _byVolId.clear();
      _scanning.clear();
      return const AuthenticatorRegistryState();
    }

    _syncWithMounted(mounted);
    return AuthenticatorRegistryState(
      entries: _flatten(),
      scanningVolIds: Set.unmodifiable(_scanning),
    );
  }

  void _syncWithMounted(List<MountedContainer> mounted) {
    final enabled = ref.read(appSettingsControllerProvider).settings.enableAuthenticator;
    if (!enabled) return;

    final currentVolIds = mounted.map((c) => c.volId).toSet();

    _byVolId.removeWhere((volId, _) => !currentVolIds.contains(volId));

    for (final container in mounted) {
      if (!_byVolId.containsKey(container.volId) && !_scanning.contains(container.volId)) {
        _scanning.add(container.volId);
        scheduleMicrotask(() => _runAndPublish(container));
      }
    }
  }

  List<TotpVaultEntry> _flatten() {
    final all = <TotpVaultEntry>[];
    for (final list in _byVolId.values) {
      all.addAll(list);
    }
    return all;
  }

  void _publish() {
    state = AuthenticatorRegistryState(
      entries: _flatten(),
      scanningVolIds: Set.unmodifiable(_scanning),
    );
  }

  /// Runs a scan whose "now scanning" flag was already claimed by the
  /// caller (both callers below claim it synchronously first) and
  /// publishes the result. The only difference between the two callers is
  /// *when* this runs relative to the current build() -- see their own
  /// comments.
  Future<void> _runAndPublish(MountedContainer container) async {
    final results = await _scan(container);
    _scanning.remove(container.volId);
    if (!ref.mounted) return;
    _byVolId[container.volId] = results;
    _publish();
  }

  /// Used by [refreshContainer]/[refreshAll] -- callers reached from a user
  /// action or another controller's hook, never from within this
  /// Notifier's own build(), so publishing the "now scanning" flag
  /// immediately (rather than deferring, as _syncWithMounted must) is safe
  /// and gives the UI an instant loading indicator.
  Future<void> _scheduleScan(MountedContainer container) async {
    _scanning.add(container.volId);
    _publish();
    await _runAndPublish(container);
  }

  Future<List<TotpVaultEntry>> _scan(MountedContainer container) async {
    final fileIo = ref.read(vaultFileIoApiProvider);
    final itemsService = ref.read(vaultItemsServiceProvider);
    final scanner = VaultFileScanner(fileIo);
    final results = <TotpVaultEntry>[];
    try {
      await for (final file in scanner.scan(container)) {
        if (!ref.mounted) break;
        if (!_looksLikeVaultItem(file.name)) continue;
        VaultItem? item;
        try {
          item = await itemsService.loadItem(container, file.relativePath);
        } catch (_) {
          // A single unreadable/corrupt item shouldn't abort the whole
          // vault's scan -- skip it, same tolerance VaultFileScanner
          // itself applies to a directory that fails to list.
          continue;
        }
        if (item == null) continue;
        if ((item.fields['totp_secret'] ?? '').trim().isEmpty) continue;
        results.add(TotpVaultEntry(container: container, relativePath: file.relativePath, item: item));
      }
    } catch (_) {
      // Vault became unavailable mid-scan (e.g. lost USB connection) --
      // return whatever was found before the error rather than losing it.
    }
    return results;
  }

  /// Same file-extension check used elsewhere for Item Vault entries
  /// (see file_browser_predicates.dart's isVaultItemFileName /
  /// password_interchange_service.dart's private _typeForFileName) --
  /// kept as its own small copy here rather than importing across from
  /// the browser feature, consistent with how those two already duplicate
  /// it rather than share one helper.
  bool _looksLikeVaultItem(String fileName) {
    final dot = fileName.lastIndexOf('.');
    if (dot < 0 || dot == fileName.length - 1) return false;
    final ext = fileName.substring(dot + 1).toLowerCase();
    return VaultItemType.values.any((t) => t.name.toLowerCase() == ext);
  }

  /// Re-scans a single already-mounted vault -- call after a vault item is
  /// saved or deleted so the Authenticator screen and AppBar icon reflect
  /// the change immediately, without waiting for a lock/unlock cycle. Safe
  /// to call for a vault this registry doesn't currently know about, or
  /// one that's since been locked (a no-op either way -- guards against
  /// resurrecting a stale entry under a volId a different vault may have
  /// since reused).
  Future<void> refreshContainer(MountedContainer container) async {
    if (!ref.read(appSettingsControllerProvider).settings.enableAuthenticator) return;
    if (_scanning.contains(container.volId)) return;
    final stillMounted = ref
        .read(vaultDashboardControllerProvider)
        .mounted
        .any((c) => c.volId == container.volId);
    if (!stillMounted) return;
    await _scheduleScan(container);
  }

  /// Full manual re-scan of every currently mounted vault -- backs
  /// pull-to-refresh on the Authenticator screen.
  Future<void> refreshAll() async {
    if (!ref.read(appSettingsControllerProvider).settings.enableAuthenticator) return;
    final mounted = ref.read(vaultDashboardControllerProvider).mounted;
    await Future.wait(mounted.map(_scheduleScan));
  }
}
