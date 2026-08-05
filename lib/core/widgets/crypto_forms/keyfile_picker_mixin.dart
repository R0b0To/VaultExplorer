import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/data/services/vault_engine/vault_explorer_api.dart';


mixin KeyfilePickerMixin<T extends StatefulWidget> on State<T> {
  final List<KeyfileRef> keyfiles = [];
  bool pickingKeyfiles = false;

  /// Called with a user-facing message when picking keyfiles fails.
  /// Override to route it into whatever error field/banner this screen
  /// already uses, e.g. `setState(() => _error = message)`.
  void onKeyfilePickError(String message);

  Future<void> pickKeyfiles() async {
    setState(() => pickingKeyfiles = true);
    try {
      final picked = await vaultExplorerApi.pickKeyfiles();
      if (!mounted) return;
      setState(() {
        for (final k in picked) {
          if (!keyfiles.any((existing) => existing.uri == k.uri)) {
            keyfiles.add(k);
          }
        }
      });
    } on PlatformException catch (e) {
      if (mounted) onKeyfilePickError(e.message ?? context.l10n.couldNotPickKeyfiles);
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
  KeyfilePickerController({required this.notify, required this.onError});

  /// Called after every state change (pick started/finished, list
  /// mutated) so the owning State can rebuild. The controller itself never
  /// calls `setState` — write this as shown above so a pick that resolves
  /// after the owning widget is disposed can't throw.
  final VoidCallback notify;

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
      final picked = await vaultExplorerApi.pickKeyfiles();
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
