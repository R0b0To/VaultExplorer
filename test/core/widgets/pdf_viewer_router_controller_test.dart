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

  // Mutable per-test so individual tests can flip these before the
  // controller's build() kicks off its async probe/registration.
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

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    container.dispose();
  });

  group('PdfViewerRouterController Tests', () {
    test('starts in probing mode', () {
      final state = container.read(
        pdfViewerRouterControllerProvider(_testContainer(), 'doc.pdf', null),
      );
      expect(state.mode, PdfViewerMode.probing);
    });

    test('registers a jetpack session when supported and a container+path are given', () async {
      final sub = container.listen(
        pdfViewerRouterControllerProvider(_testContainer(), 'doc.pdf', null),
        (_, __) {},
      );
      addTearDown(sub.close);

      // Let the fire-and-forget _start()/_registerSession() chain settle.
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      final state = container.read(
        pdfViewerRouterControllerProvider(_testContainer(), 'doc.pdf', null),
      );
      expect(state.mode, PdfViewerMode.jetpack);
      expect(state.contentUri, 'content://fake/doc');
      expect(state.sessionToken, 'tok-1');
      expect(state.jetpackLoaded, isFalse);
    });

    test('falls back when jetpack is unsupported, without registering a session', () async {
      jetpackSupported = false;
      final sub = container.listen(
        pdfViewerRouterControllerProvider(_testContainer(), 'doc.pdf', null),
        (_, __) {},
      );
      addTearDown(sub.close);

      await Future<void>.delayed(Duration.zero);

      final state = container.read(
        pdfViewerRouterControllerProvider(_testContainer(), 'doc.pdf', null),
      );
      expect(state.mode, PdfViewerMode.fallback);
      expect(state.contentUri, isNull);
      expect(state.sessionToken, isNull);
    });

    test('falls back when registration throws', () async {
      throwOnRegister = true;
      final sub = container.listen(
        pdfViewerRouterControllerProvider(_testContainer(), 'doc.pdf', null),
        (_, __) {},
      );
      addTearDown(sub.close);

      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      final state = container.read(
        pdfViewerRouterControllerProvider(_testContainer(), 'doc.pdf', null),
      );
      expect(state.mode, PdfViewerMode.fallback);
    });

    test('falls back with neither container+path nor localUri', () async {
      final sub = container.listen(
        pdfViewerRouterControllerProvider(null, null, null),
        (_, __) {},
      );
      addTearDown(sub.close);

      await Future<void>.delayed(Duration.zero);

      final state = container.read(pdfViewerRouterControllerProvider(null, null, null));
      expect(state.mode, PdfViewerMode.fallback);
    });

    test('registers a local session when only localUri is given', () async {
      final sub = container.listen(
        pdfViewerRouterControllerProvider(null, null, '/local/doc.pdf'),
        (_, __) {},
      );
      addTearDown(sub.close);

      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      final state = container.read(
        pdfViewerRouterControllerProvider(null, null, '/local/doc.pdf'),
      );
      expect(state.mode, PdfViewerMode.jetpack);
      expect(state.contentUri, 'content://fake/doc');
    });

    test('onJetpackLoaded flips jetpackLoaded', () async {
      final providerArg = pdfViewerRouterControllerProvider(_testContainer(), 'doc.pdf', null);
      final sub = container.listen(providerArg, (_, __) {});
      addTearDown(sub.close);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      container.read(providerArg.notifier).onJetpackLoaded();

      expect(container.read(providerArg).jetpackLoaded, isTrue);
    });

    test('onJetpackError before first load revokes the session and falls back', () async {
      final providerArg = pdfViewerRouterControllerProvider(_testContainer(), 'doc.pdf', null);
      final sub = container.listen(providerArg, (_, __) {});
      addTearDown(sub.close);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(container.read(providerArg).mode, PdfViewerMode.jetpack);

      container.read(providerArg.notifier).onJetpackError();
      await Future<void>.delayed(Duration.zero);

      final state = container.read(providerArg);
      expect(state.mode, PdfViewerMode.fallback);
      expect(state.contentUri, isNull);
      expect(state.sessionToken, isNull);
      expect(revokeInvoked, isTrue);
      expect(lastRevokedToken, 'tok-1');
    });

    test('onJetpackError after a successful load is a no-op (treated as transient)', () async {
      final providerArg = pdfViewerRouterControllerProvider(_testContainer(), 'doc.pdf', null);
      final sub = container.listen(providerArg, (_, __) {});
      addTearDown(sub.close);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      container.read(providerArg.notifier).onJetpackLoaded();

      container.read(providerArg.notifier).onJetpackError();

      final state = container.read(providerArg);
      expect(state.mode, PdfViewerMode.jetpack);
      expect(revokeInvoked, isFalse);
    });

    test('disposing the provider revokes an active session', () async {
      final providerArg = pdfViewerRouterControllerProvider(_testContainer(), 'doc.pdf', null);
      final sub = container.listen(providerArg, (_, __) {});
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(container.read(providerArg).sessionToken, 'tok-1');

      sub.close();
      container.dispose();
      // Recreate so tearDown's own container.dispose() has a live target.
      container = ProviderContainer();

      expect(revokeInvoked, isTrue);
      expect(lastRevokedToken, 'tok-1');
    });

    test('pdfJetpackSupported is probed once and reused across two documents', () async {
      final subA = container.listen(
        pdfViewerRouterControllerProvider(_testContainer(), 'a.pdf', null),
        (_, __) {},
      );
      addTearDown(subA.close);
      final subB = container.listen(
        pdfViewerRouterControllerProvider(_testContainer(), 'b.pdf', null),
        (_, __) {},
      );
      addTearDown(subB.close);

      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(
        container.read(pdfViewerRouterControllerProvider(_testContainer(), 'a.pdf', null)).mode,
        PdfViewerMode.jetpack,
      );
      expect(
        container.read(pdfViewerRouterControllerProvider(_testContainer(), 'b.pdf', null)).mode,
        PdfViewerMode.jetpack,
      );
    });
  });
}
