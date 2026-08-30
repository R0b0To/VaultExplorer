// VaultInfoScreen was a StatefulWidget owning a load-state enum + the raw
// info map as State fields, loaded once in initState. Family-keyed by uri:
// a fresh screen instance is pushed per vault, same shape as
// VaultItemDetail/FileBrowserSelection scoping to "this screen's session".
// containerFormat isn't part of the state -- it's only used for row-building
// logic in the widget and never changes for a given push, so it stays a
// plain widget-level value like the original `widget.containerFormat`.
import 'package:flutter/services.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:vaultexplorer/core/providers/vault_engine_providers.dart';

part 'vault_info_controller.g.dart';

enum VaultInfoLoadState { loading, unlockRequired, error, loaded }

class VaultInfoState {
  final VaultInfoLoadState loadState;
  final Map<String, dynamic> info;

  const VaultInfoState({
    required this.loadState,
    this.info = const {},
  });
}

@riverpod
class VaultInfo extends _$VaultInfo {
  @override
  VaultInfoState build(String uri) {
    _load(uri);
    return const VaultInfoState(loadState: VaultInfoLoadState.loading);
  }

  Future<void> _load(String uri) async {
    state = const VaultInfoState(loadState: VaultInfoLoadState.loading);
    try {
      final info = await ref.read(vaultFileIoApiProvider).getVaultInfo(uri);
      if (!ref.mounted) return;
      state = VaultInfoState(
        loadState: VaultInfoLoadState.loaded,
        info: info ?? const {},
      );
    } on PlatformException catch (e) {
      if (!ref.mounted) return;
      state = VaultInfoState(
        loadState: e.code == 'NOT_MOUNTED'
            ? VaultInfoLoadState.unlockRequired
            : VaultInfoLoadState.error,
      );
    } catch (_) {
      if (!ref.mounted) return;
      state = const VaultInfoState(loadState: VaultInfoLoadState.error);
    }
  }

  /// Re-runs the load. Exposed for the "unlock required"/"error" screens'
  /// retry action, matching the original's `onAction: _load`.
  void retry() => _load(uri);
}
