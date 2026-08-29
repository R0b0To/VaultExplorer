// Compile-time dependency graph for the native vault engine (Phase 2).
// Replaces the old global `vaultExplorerApi` singleton in
// lib/data/services/vault_engine/vault_explorer_api.dart with
// @Riverpod(keepAlive: true) providers over 8 domain-specific API classes,
// each constructor-injected with the shared MethodChannel so tests can
// override them with a mock channel instead of hitting the real platform
// side (see Phase 6 in the migration plan).
//
// NOTE: run `dart run build_runner build --delete-conflicting-outputs`
// locally to generate vault_engine_providers.g.dart -- this file will not
// compile until that's done.
import 'package:flutter/services.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../api/vault_automation_api.dart';
import '../api/vault_crypto_api.dart';
import '../api/vault_engine_events.dart';
import '../api/vault_file_io_api.dart';
import '../api/vault_hash_api.dart';
import '../api/vault_lifecycle_api.dart';
import '../api/vault_pdf_api.dart';
import '../api/vault_repair_api.dart';
import '../api/vault_split_join_api.dart';

part 'vault_engine_providers.g.dart';

const _vaultEngineChannelName = 'com.aeidolon.vaultexplorer/engine';

/// The single platform channel every VaultXxxApi class talks over --
/// matches the `const _channel = MethodChannel(...)` top-level constant the
/// pre-migration VaultExplorerApi used, but resolvable/overridable through
/// Riverpod instead of being a bare global.
@Riverpod(keepAlive: true)
MethodChannel vaultEngineChannel(Ref ref) =>
    const MethodChannel(_vaultEngineChannelName);

/// Cross-cutting native-event listener registries + the method-call
/// dispatch that used to live as static state directly on VaultExplorerApi.
/// `keepAlive: true` + registering the handler exactly once here reproduces
/// the old "single static handler for the process lifetime" behaviour
/// (previously wired up by `VaultExplorerApi.initMethodCallHandler()` in
/// `main()` -- see lib/main.dart, which should call
/// `ref.read(vaultEngineEventsProvider)` once at startup instead once all
/// consumers have migrated off the old static listener methods).
@Riverpod(keepAlive: true)
VaultEngineEvents vaultEngineEvents(Ref ref) {
  final events = VaultEngineEvents();
  events.registerHandler(ref.watch(vaultEngineChannelProvider));
  return events;
}

@Riverpod(keepAlive: true)
VaultCryptoApi vaultCryptoApi(Ref ref) =>
    VaultCryptoApi(ref.watch(vaultEngineChannelProvider));

@Riverpod(keepAlive: true)
VaultFileIoApi vaultFileIoApi(Ref ref) =>
    VaultFileIoApi(ref.watch(vaultEngineChannelProvider));

@Riverpod(keepAlive: true)
VaultHashApi vaultHashApi(Ref ref) =>
    VaultHashApi(ref.watch(vaultEngineChannelProvider));

@Riverpod(keepAlive: true)
VaultLifecycleApi vaultLifecycleApi(Ref ref) => VaultLifecycleApi(
  ref.watch(vaultEngineChannelProvider),
  ref.watch(vaultEngineEventsProvider),
);

@Riverpod(keepAlive: true)
VaultPdfApi vaultPdfApi(Ref ref) =>
    VaultPdfApi(ref.watch(vaultEngineChannelProvider));

@Riverpod(keepAlive: true)
VaultRepairApi vaultRepairApi(Ref ref) =>
    VaultRepairApi(ref.watch(vaultEngineChannelProvider));

@Riverpod(keepAlive: true)
VaultSplitJoinApi vaultSplitJoinApi(Ref ref) =>
    VaultSplitJoinApi(ref.watch(vaultEngineChannelProvider));

@Riverpod(keepAlive: true)
VaultAutomationApi vaultAutomationApi(Ref ref) =>
    VaultAutomationApi(ref.watch(vaultEngineChannelProvider));
