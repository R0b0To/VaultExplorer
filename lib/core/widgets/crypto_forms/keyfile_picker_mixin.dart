import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
      if (mounted) onKeyfilePickError(e.message ?? 'Could not pick keyfiles');
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
