// PdfViewerRouter was a plain StatefulWidget holding the probe/session
// state machine directly as State fields, plus a *static* `_supportedCache`
// field shared across every instance (a de-facto app-lifetime cache that
// happened to live on the class rather than anywhere principled).
//
// Split into two providers:
//   - `pdfJetpackSupported`: a keepAlive Future provider replacing the old
//     static cache -- probed once for the app's lifetime, reused by every
//     PDF this session opens, exactly like the original `??=` cache did.
//   - `PdfViewerRouterController`: family-keyed by (container, pdfPath,
//     localUri) -- identifies *which document* this session belongs to.
//     `MountedContainer` doesn't override `==` (identity equality), which
//     is fine here: this widget only ever watches its own constructor-given
//     instance, so identity equality is exactly "same document."
//
// `_viewerKey` (GlobalKey<JetpackPdfViewerViewState>, used to imperatively
// call `toggleSearch()` on the native platform view) stays in the widget --
// it's tied to the widget tree/PlatformView instance, not domain data, and
// has no meaningful representation as Riverpod state.
import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:vaultexplorer/core/api/vault_pdf_api.dart';
import 'package:vaultexplorer/core/providers/vault_engine_providers.dart';
import 'package:vaultexplorer/core/utils/ve_log.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';

part 'pdf_viewer_router_controller.g.dart';

@Riverpod(keepAlive: true)
Future<bool> pdfJetpackSupported(Ref ref) async {
  try {
    return await ref.read(vaultPdfApiProvider).isJetpackPdfViewerSupported();
  } catch (_) {
    return false;
  }
}

enum PdfViewerMode { probing, jetpack, fallback }

class PdfViewerRouterState {
  final PdfViewerMode mode;
  final String? contentUri;
  final String? sessionToken;
  final bool jetpackLoaded;

  const PdfViewerRouterState({
    this.mode = PdfViewerMode.probing,
    this.contentUri,
    this.sessionToken,
    this.jetpackLoaded = false,
  });

  PdfViewerRouterState _copy({PdfViewerMode? mode, bool? jetpackLoaded}) =>
      PdfViewerRouterState(
        mode: mode ?? this.mode,
        contentUri: contentUri,
        sessionToken: sessionToken,
        jetpackLoaded: jetpackLoaded ?? this.jetpackLoaded,
      );
}

@riverpod
class PdfViewerRouterController extends _$PdfViewerRouterController {
  @override
  PdfViewerRouterState build(
    MountedContainer? container,
    String? pdfPath,
    String? localUri,
  ) {
    ref.onDispose(() {
      // Fire-and-forget, matching the original's dispose-time behavior --
      // by teardown time there's nothing left to await into.
      final token = state.sessionToken;
      if (token != null) {
        unawaited(ref.read(vaultPdfApiProvider).revokeJetpackPdfSession(token));
      }
    });
    _start();
    return const PdfViewerRouterState();
  }

  Future<void> _start() async {
    bool supported;
    try {
      supported = await ref.read(pdfJetpackSupportedProvider.future);
    } catch (_) {
      supported = false;
    }
    if (!ref.mounted) return;
    if (!supported) {
      VeLog.d('JetpackPdfViewer', 'Not supported on this device, falling back');
      state = state._copy(mode: PdfViewerMode.fallback);
      return;
    }
    await _registerSession();
  }

  Future<void> _registerSession() async {
    final api = ref.read(vaultPdfApiProvider);
    try {
      final JetpackPdfSession session;
      if (container != null && pdfPath != null) {
        session = await api.registerVaultJetpackPdfSession(container!, pdfPath!);
      } else if (localUri != null && localUri!.isNotEmpty) {
        session = await api.registerLocalJetpackPdfSession(localUri!);
      } else {
        if (ref.mounted) state = state._copy(mode: PdfViewerMode.fallback);
        return;
      }
      if (!ref.mounted) {
        // Provider was torn down mid-registration (e.g. the screen was
        // popped while we were awaiting) -- revoke immediately rather than
        // leaking a live native session that nothing will ever release.
        unawaited(api.revokeJetpackPdfSession(session.token));
        return;
      }
      state = PdfViewerRouterState(
        mode: PdfViewerMode.jetpack,
        contentUri: session.contentUri,
        sessionToken: session.token,
      );
    } catch (_) {
      if (ref.mounted) state = state._copy(mode: PdfViewerMode.fallback);
    }
  }

  void onJetpackLoaded() {
    if (!ref.mounted) return;
    state = state._copy(jetpackLoaded: true);
  }

  /// Only falls back on error *before* the first successful load -- an
  /// error after the viewer has already rendered is treated as transient
  /// rather than fatal, same as the original.
  void onJetpackError() {
    if (!ref.mounted || state.jetpackLoaded) return;
    final token = state.sessionToken;
    if (token != null) {
      unawaited(ref.read(vaultPdfApiProvider).revokeJetpackPdfSession(token));
    }
    state = PdfViewerRouterState(mode: PdfViewerMode.fallback);
  }
}
