import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:vaultexplorer/core/api/vault_engine_types.dart';
import 'package:vaultexplorer/core/api/vault_lifecycle_api.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';

mixin KeyfilePickerMixin<T extends StatefulWidget> on State<T> {
  VaultLifecycleApi get vaultLifecycleApi;

  final List<KeyfileRef> keyfiles = [];
  bool pickingKeyfiles = false;

  /// Called with a user-facing message when picking keyfiles fails.
  /// Override to route it into whatever error field/banner this screen
  /// already uses, e.g. `setState(() => _error = message)`.
  void onKeyfilePickError(String message);

  Future<void> pickKeyfiles() async {
    setState(() => pickingKeyfiles = true);
    try {
      final picked = await vaultLifecycleApi.pickKeyfiles();
      if (!mounted) return;
      setState(() {
        for (final k in picked) {
          if (!keyfiles.any((existing) => existing.uri == k.uri)) {
            keyfiles.add(k);
          }
        }
      });
    } on PlatformException catch (e) {
      if (mounted)
        onKeyfilePickError(e.message ?? context.l10n.couldNotPickKeyfiles);
    } finally {
      if (mounted) setState(() => pickingKeyfiles = false);
    }
  }

  void removeKeyfile(KeyfileRef k) {
    // Keyed on uri (not full record equality) — matches the identity
    // already used for de-duplication in pickKeyfiles above.
    setState(() => keyfiles.removeWhere((existing) => existing.uri == k.uri));
  }
}

class KeyfilePickerController {
  KeyfilePickerController({
    required VaultLifecycleApi lifecycleApi,
    required this.notify,
    required this.onError,
  }) : _lifecycleApi = lifecycleApi;

  final VaultLifecycleApi _lifecycleApi;

  /// Called after every state change (pick started/finished, list
  /// mutated) so the owning State can rebuild. The controller itself never
  /// calls `setState` — write this as shown above so a pick that resolves
  /// after the owning widget is disposed can't throw.
  ///
  /// Not `final`: a caller that hosts this controller's [KeyfilesPicker]
  /// inside a modal bottom sheet (e.g. a wizard's "hidden volume details"
  /// sheet) can temporarily point this at the sheet's own `StatefulBuilder`
  /// setState for the sheet's lifetime — the sheet is a separate route from
  /// the owning State's subtree, so the original callback alone wouldn't
  /// refresh what's visibly inside the sheet — then restore the original
  /// callback once the sheet closes.
  VoidCallback notify;

  /// Called with a user-facing message when picking keyfiles fails, or
  /// `null` if the platform didn't provide one — callers should fall back
  /// to a localized message (e.g. `context.l10n.couldNotPickKeyfiles`) since
  /// this controller has no [BuildContext] of its own. Same mounted-guard
  /// responsibility as [notify].
  final void Function(String? message) onError;

  final List<KeyfileRef> keyfiles = [];
  bool picking = false;

  Future<void> pick() async {
    picking = true;
    notify();
    try {
      final picked = await _lifecycleApi.pickKeyfiles();
      for (final k in picked) {
        if (!keyfiles.any((existing) => existing.uri == k.uri)) {
          keyfiles.add(k);
        }
      }
    } on PlatformException catch (e) {
      onError(e.message);
    } finally {
      picking = false;
      notify();
    }
  }

  void remove(KeyfileRef k) {
    // Keyed on uri (not full record equality) — matches pick()'s own
    // de-duplication identity above, and KeyfilePickerMixin.removeKeyfile.
    keyfiles.removeWhere((existing) => existing.uri == k.uri);
    notify();
  }
}
