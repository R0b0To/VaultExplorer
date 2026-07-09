import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../services/vaultexplorer_api.dart';

/// Owns the "attached keyfiles" list and the async picker call shared by
/// every unlock/config surface that offers keyfile-based unlock
/// (UnlockSheet, UsbUnlockSheet, ContainerConfigScreen's
/// _RealPasswordGateDialog). Mix in to get [keyfiles]/[pickingKeyfiles]
/// plus [pickKeyfiles]/[removeKeyfile] for free instead of re-declaring
/// the same four members per screen.
mixin KeyfilePickerMixin<T extends StatefulWidget> on State<T> {
  final List<KeyfileRef> keyfiles = [];
  bool pickingKeyfiles = false;

  /// Called on a picker failure; override to surface it (e.g. set an
  /// `_error` field). Default is a no-op so mixing in doesn't force every
  /// host to have an `_error` field of a particular shape.
  void onKeyfilePickError(String message) {}

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

  void removeKeyfile(KeyfileRef keyfile) {
    setState(() => keyfiles.removeWhere((k) => k.uri == keyfile.uri));
  }
}