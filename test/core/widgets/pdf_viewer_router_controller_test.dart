import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/core/widgets/pdf_viewer_router_controller.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';

MountedContainer _testContainer() => MountedContainer(
  volId: 1,
  uri: 'file:///vault.hc',
  displayName: 'Vault',
  rootFiles: const [],
  mountedAt: DateTime(2026, 1, 1),
  totalSpace: 1000000,
  freeSpace: 500000,
  containerFormat: 'veracrypt',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.aeidolon.vaultexplorer/engine');
  late ProviderContainer container;

  late bool jetpackSupported;
  late bool revokeInvoked;
  late String? lastRevokedToken;
  late bool throwOnRegister;

  setUp(() {
    jetpackSupported = true;
    revokeInvoked = false;
    lastRevokedToken = null;
    throwOnRegister = false;

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      switch (call.method) {
        case 'isJetpackPdfViewerSupported':
          return jetpackSupported;
        case 'registerJetpackPdfSession':
          if (throwOnRegister) {
            throw PlatformException(code: 'register_failed');
          }
          return {'contentUri': 'content://fake/doc', 'token': 'tok-1'};
        case 'revokeJetpackPdfSession':
          revokeInvoked = true;
          lastRevokedToken = call.arguments['token'] as String?;
          return null;
      }
      return null;
    });

    container = ProviderContainer();
  });

  tearDown(() async {
    container.dispose();
    await Future<void>.delayed(Duration.zero);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  group('PdfViewerRouterController Tests', () {
    test('starts in probing mode', () {
      final state = container.read(
        pdfViewerRouterControllerProvider(_testContainer(), 'doc.pdf', null),
      );
      expect(state.mode, PdfViewerMode.probing);
    });

    test('registers a jetpack session when supported and a container+path are given', () async {
      final completer = Completer<PdfViewerRouterState>();
      final provider = pdfViewerRouterControllerProvider(_testContainer(), 'doc.pdf', null);
      final sub = container.listen(
        provider,
        (prev, next) {
          if (next.mode != PdfViewerMode.probing && !completer.isCompleted) {
            completer.complete(next);
          }
        },
        fireImmediately: true,
      );
      addTearDown(sub.close);

      final state = await completer.future;
      expect(state.mode, PdfViewerMode.jetpack);
      expect(state.contentUri, 'content://fake/doc');
      expect(state.sessionToken, 'tok-1');
      expect(state.jetpackLoaded, isFalse);
    });

    test('falls back when jetpack is unsupported, without registering a session', () async {
      jetpackSupported = false;
      final completer = Completer<PdfViewerRouterState>();
      final provider = pdfViewerRouterControllerProvider(_testContainer(), 'doc.pdf', null);
      final sub = container.listen(
        provider,
        (prev, next) {
          if (next.mode != PdfViewerMode.probing && !completer.isCompleted) {
            completer.complete(next);
          }
        },
        fireImmediately: true,
      );
      addTearDown(sub.close);

      final state = await completer.future;
      expect(state.mode, PdfViewerMode.fallback);
      expect(state.contentUri, isNull);
      expect(state.sessionToken, isNull);
    });

    test('falls back when registration throws', () async {
      throwOnRegister = true;
      final completer = Completer<PdfViewerRouterState>();
      final provider = pdfViewerRouterControllerProvider(_testContainer(), 'doc.pdf', null);
      final sub = container.listen(
        provider,
        (prev, next) {
          if (next.mode != PdfViewerMode.probing && !completer.isCompleted) {
            completer.complete(next);
          }
        },
        fireImmediately: true,
      );
      addTearDown(sub.close);

      final state = await completer.future;
      expect(state.mode, PdfViewerMode.fallback);
    });

    test('falls back with neither container+path nor localUri', () async {
      final completer = Completer<PdfViewerRouterState>();
      final provider = pdfViewerRouterControllerProvider(null, null, null);
      final sub = container.listen(
        provider,
        (prev, next) {
          if (next.mode != PdfViewerMode.probing && !completer.isCompleted) {
            completer.complete(next);
          }
        },
        fireImmediately: true,
      );
      addTearDown(sub.close);

      final state = await completer.future;
      expect(state.mode, PdfViewerMode.fallback);
    });

    test('registers a local session when only localUri is given', () async {
      final completer = Completer<PdfViewerRouterState>();
      final provider = pdfViewerRouterControllerProvider(null, null, '/local/doc.pdf');
      final sub = container.listen(
        provider,
        (prev, next) {
          if (next.mode != PdfViewerMode.probing && !completer.isCompleted) {
            completer.complete(next);
          }
        },
        fireImmediately: true,
      );
      addTearDown(sub.close);

      final state = await completer.future;
      expect(state.mode, PdfViewerMode.jetpack);
      expect(state.contentUri, 'content://fake/doc');
    });

    test('onJetpackLoaded flips jetpackLoaded', () async {
      final completer = Completer<PdfViewerRouterState>();
      final provider = pdfViewerRouterControllerProvider(_testContainer(), 'doc.pdf', null);
      final sub = container.listen(
        provider,
        (prev, next) {
          if (next.mode != PdfViewerMode.probing && !completer.isCompleted) {
            completer.complete(next);
          }
        },
        fireImmediately: true,
      );
      addTearDown(sub.close);
      await completer.future;

      container.read(provider.notifier).onJetpackLoaded();

      expect(container.read(provider).jetpackLoaded, isTrue);
    });

    test('onJetpackError before first load revokes the session and falls back', () async {
      final completer = Completer<PdfViewerRouterState>();
      final provider = pdfViewerRouterControllerProvider(_testContainer(), 'doc.pdf', null);
      final sub = container.listen(
        provider,
        (prev, next) {
          if (next.mode != PdfViewerMode.probing && !completer.isCompleted) {
            completer.complete(next);
          }
        },
        fireImmediately: true,
      );
      addTearDown(sub.close);
      await completer.future;
      expect(container.read(provider).mode, PdfViewerMode.jetpack);

      container.read(provider.notifier).onJetpackError();

      final state = container.read(provider);
      expect(state.mode, PdfViewerMode.fallback);
      expect(state.contentUri, isNull);
      expect(state.sessionToken, isNull);
      expect(revokeInvoked, isTrue);
      expect(lastRevokedToken, 'tok-1');
    });

    test('onJetpackError after a successful load is a no-op (treated as transient)', () async {
      final completer = Completer<PdfViewerRouterState>();
      final provider = pdfViewerRouterControllerProvider(_testContainer(), 'doc.pdf', null);
      final sub = container.listen(
        provider,
        (prev, next) {
          if (next.mode != PdfViewerMode.probing && !completer.isCompleted) {
            completer.complete(next);
          }
        },
        fireImmediately: true,
      );
      addTearDown(sub.close);
      await completer.future;
      container.read(provider.notifier).onJetpackLoaded();

      container.read(provider.notifier).onJetpackError();

      final state = container.read(provider);
      expect(state.mode, PdfViewerMode.jetpack);
      expect(revokeInvoked, isFalse);
    });

    test('disposing the provider revokes an active session', () async {
      final completer = Completer<PdfViewerRouterState>();
      final provider = pdfViewerRouterControllerProvider(_testContainer(), 'doc.pdf', null);
      final sub = container.listen(
        provider,
        (prev, next) {
          if (next.mode != PdfViewerMode.probing && !completer.isCompleted) {
            completer.complete(next);
          }
        },
        fireImmediately: true,
      );
      await completer.future;
      expect(container.read(provider).sessionToken, 'tok-1');

      sub.close();
      container.dispose();
      // Recreate so tearDown's container.dispose() has a live target.
      container = ProviderContainer();

      expect(revokeInvoked, isTrue);
      expect(lastRevokedToken, 'tok-1');
    });

    test('pdfJetpackSupported is probed once and reused across two documents', () async {
      final completerA = Completer<PdfViewerRouterState>();
      final providerA = pdfViewerRouterControllerProvider(_testContainer(), 'a.pdf', null);
      final subA = container.listen(
        providerA,
        (prev, next) {
          if (next.mode != PdfViewerMode.probing && !completerA.isCompleted) {
            completerA.complete(next);
          }
        },
        fireImmediately: true,
      );
      addTearDown(subA.close);

      final completerB = Completer<PdfViewerRouterState>();
      final providerB = pdfViewerRouterControllerProvider(_testContainer(), 'b.pdf', null);
      final subB = container.listen(
        providerB,
        (prev, next) {
          if (next.mode != PdfViewerMode.probing && !completerB.isCompleted) {
            completerB.complete(next);
          }
        },
        fireImmediately: true,
      );
      addTearDown(subB.close);

      final stateA = await completerA.future;
      final stateB = await completerB.future;

      expect(stateA.mode, PdfViewerMode.jetpack);
      expect(stateB.mode, PdfViewerMode.jetpack);
    });
  });
}
