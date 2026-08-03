import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Which identity the Android launcher currently shows for this app.
///
/// This is intentionally the *only* representation of Discrete Mode state
/// anywhere in Dart -- there is no `bool discreteModeEnabled` field in
/// [AppSettings] or anywhere else that gets persisted to disk. See
/// [DisguiseModeApi.getMode]'s doc comment and docs/architecture.md ADR-025
/// for why: the native side already has to track this via
/// `PackageManager`'s component-enabled state (that's what the launcher
/// itself reads), so a second, separately persisted copy in Dart would be
/// redundant at best and, at worst, driftable out of sync with the actual
/// launcher icon -- or a plaintext trace of "this app has a hidden mode"
/// sitting in a settings file, which undermines the point of the feature.
enum DisguiseMode {
  /// Real identity: "Vault Explorer" label/icon, boots into [LockGateScreen]
  /// / the vault dashboard.
  vault,

  /// Decoy identity: "Doc Viewer" label/icon, boots into the decoy PDF
  /// reader UI.
  decoy;

  static DisguiseMode fromWire(String? raw) =>
      raw == 'decoy' ? DisguiseMode.decoy : DisguiseMode.vault;

  String get wireValue => switch (this) {
    DisguiseMode.vault => 'vault',
    DisguiseMode.decoy => 'decoy',
  };
}

/// A PDF the user picked from local device storage via SAF, outside any
/// vault. Read-only: Discrete Mode's decoy reader never writes to it.
typedef PickedLocalPdf = ({String uri, String displayName});

const _channel = MethodChannel('com.aeidolon.vaultexplorer/disguise_channel');

void _logSwallowed(String method, Object error) {
  debugPrint('[DisguiseModeApi] $method failed: $error');
}

/// Thin wrapper around the native `disguise_channel` (docs/architecture.md
/// §8.4): querying/setting which launcher identity is active, and picking a
/// local PDF for the decoy reader.
///
/// Deliberately its own small class (not folded into `VaultExplorerApi`)
/// mirroring that class's own precedent of a swappable top-level instance
/// (`disguiseModeApi`) rather than static methods, so screens that use it
/// stay unit-testable the same way `vault_explorer_api_test.dart` tests
/// `VaultExplorerApi` -- see `_FakeDisguiseModeApi` in
/// `test/core/services/disguise_mode_api_test.dart` for the pattern.
class DisguiseModeApi {
  const DisguiseModeApi();

  /// Reads the *actual* launcher component state from
  /// `PackageManager.getComponentEnabledSetting` on the native side -- not
  /// a cached or persisted Dart value. Called once at app start (see
  /// `vault_explorer_app.dart`'s root gate) to decide whether to boot into
  /// the decoy reader or the normal lock gate.
  ///
  /// Falls back to [DisguiseMode.vault] on any channel failure, since a
  /// failure to determine the mode should never accidentally strand the
  /// user in (or out of) the vault UI.
  Future<DisguiseMode> getMode() async {
    try {
      final result = await _channel.invokeMethod<String>('getMode');
      return DisguiseMode.fromWire(result);
    } catch (e) {
      _logSwallowed('getMode', e);
      return DisguiseMode.vault;
    }
  }

  /// Atomically flips both `activity-alias` components on the native side
  /// (see `DisguiseModeHandlers.handleSetMode`) so exactly one of the two
  /// launcher identities is ever enabled. Throws on failure -- callers
  /// (the Settings toggle) need to know if this didn't actually happen, so
  /// they don't tell the user Discrete Mode is on when it isn't.
  Future<void> setMode(DisguiseMode mode) async {
    await _channel.invokeMethod<void>('setMode', {'mode': mode.wireValue});
  }

  /// Launches the SAF document picker filtered to `application/pdf` and
  /// returns the picked file, or `null` if the user cancelled. Used only by
  /// the decoy reader's "Open PDF File" button.
  Future<PickedLocalPdf?> pickLocalPdfFile() async {
    try {
      final result = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'pickLocalPdfFile',
      );
      if (result == null) return null;
      final uri = result['uri'] as String?;
      if (uri == null || uri.isEmpty) return null;
      return (
        uri: uri,
        displayName: (result['displayName'] as String?) ?? 'Document.pdf',
      );
    } catch (e) {
      _logSwallowed('pickLocalPdfFile', e);
      return null;
    }
  }

  /// Docs/architecture.md §8.3 (ADR-029): the decoy reader also registers
  /// as a PDF handler for "Open with..."/Share while active, so it can be
  /// launched cold by an external Open-With/Share intent, before Dart's
  /// even running. [consumePendingOpenRequest] is the *pull* half of that:
  /// called once, right after [getMode] resolves at startup
  /// (`_DisguiseModeGate._resolveMode`), it asks native "was I launched to
  /// open something in particular?" and clears that state so it's only
  /// acted on once. Returns `null` on an ordinary launch.
  Future<PickedLocalPdf?> consumePendingOpenRequest() async {
    try {
      final result = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'consumePendingOpenRequest',
      );
      if (result == null) return null;
      final uri = result['uri'] as String?;
      if (uri == null || uri.isEmpty) return null;
      return (
        uri: uri,
        displayName: (result['displayName'] as String?) ?? 'Document.pdf',
      );
    } catch (e) {
      _logSwallowed('consumePendingOpenRequest', e);
      return null;
    }
  }

  /// The *push* half of the same feature: while the app is already running
  /// (Discrete Mode active) and a second Open-With/Share request arrives
  /// (`MainActivity.onNewIntent`, `singleTop`), native calls this instead of
  /// waiting for another poll. Only one listener may be registered at a
  /// time -- `_DisguiseModeGate` is the sole, permanent owner of this
  /// registration for the app's lifetime, so later callers replacing it is
  /// not a concern in practice.
  void setExternalOpenRequestListener(void Function(PickedLocalPdf) onRequest) {
    _channel.setMethodCallHandler((call) async {
      if (call.method != 'externalOpenRequest') return null;
      final args = call.arguments;
      if (args is! Map) return null;
      final uri = args['uri'] as String?;
      if (uri == null || uri.isEmpty) return null;
      onRequest((
        uri: uri,
        displayName: (args['displayName'] as String?) ?? 'Document.pdf',
      ));
      return null;
    });
  }
}

/// Swappable global instance -- see [DisguiseModeApi]'s doc comment. Tests
/// that need to fake native behavior assign a fake subclass here and must
/// restore `const DisguiseModeApi()` in `tearDown`.
DisguiseModeApi disguiseModeApi = const DisguiseModeApi();