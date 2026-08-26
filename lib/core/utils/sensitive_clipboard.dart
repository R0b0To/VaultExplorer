import 'dart:async';

import 'package:flutter/services.dart';
import 'package:vaultexplorer/data/services/vault_engine/vault_explorer_api.dart';

/// Copies vault secrets to the OS clipboard without leaving them there
/// indefinitely.
///
/// Three mitigations, all best-effort (the OS clipboard is inherently shared
/// state we don't fully control):
/// * Marks the clip as sensitive via [ClipDescription.EXTRA_IS_SENSITIVE]
///   on Android 13+, so system clipboard preview/history UIs redact it.
/// * Auto-clears the clipboard a short time after copying, but only if it
///   still holds exactly what we put there (never clobbers something the
///   user copied afterward from elsewhere).
/// * Clears via native `clearPrimaryClip()` rather than
///   `Clipboard.setData('')`, so the silent background clear doesn't itself
///   surface Android 13's clipboard preview overlay — see
///   [VaultExplorerApi.clearSensitiveClipboardText].
class SensitiveClipboard {
  SensitiveClipboard._();

  static const Duration _clearAfter = Duration(seconds: 30);
  static Timer? _clearTimer;

  static Future<void> copy(String value) async {
    _clearTimer?.cancel();
    final markedSensitive =
        await vaultExplorerApi.setSensitiveClipboardText(value);
    if (!markedSensitive) {
      // Older Android version or platform-channel failure — still copy,
      // just without the sensitive flag.
      await Clipboard.setData(ClipboardData(text: value));
    }
    _clearTimer = Timer(_clearAfter, () async {
      final cleared = await vaultExplorerApi.clearSensitiveClipboardText(
        expectedText: value,
      );
      if (!cleared) {
        // Older Android version or platform-channel failure — fall back to
        // the plain Flutter clipboard API. The compare-and-clear check
        // moves back to Dart since the native side never got to do it.
        final current = await Clipboard.getData(Clipboard.kTextPlain);
        if (current?.text == value) {
          await Clipboard.setData(const ClipboardData(text: ''));
        }
      }
    });
  }
}
