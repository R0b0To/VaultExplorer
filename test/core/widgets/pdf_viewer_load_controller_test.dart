import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/core/api/vault_pdf_api.dart';
import 'package:vaultexplorer/core/providers/vault_engine_providers.dart';
import 'package:vaultexplorer/core/widgets/pdf_viewer_load_controller.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/l10n/generated/app_localizations_en.dart';

MountedContainer _testContainer() => MountedContainer(
  volId: 1,
  uri: 'file:///vault.hc',
  displayName: 'Vault',
  rootFiles: const [],
  mountedAt: DateTime(2026, 1, 1),
  totalSpace: 1000000,
  freeSpace: 500000,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.aeidolon.vaultexplorer/engine');
  final l10n = AppLocalizationsEn();
  late ProviderContainer container;

  final calls = <MethodCall>[];
  Object? nextResult;
  Object? nextError;

  setUp(() {
    calls.clear();
    nextResult = null;
    nextError = null;

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          if (nextError != null) throw nextError!;
          return nextResult;
        });

    container = ProviderContainer(
      overrides: [
        vaultPdfApiProvider.overrideWithValue(VaultPdfApi(channel)),
      ],
    );
  });

  tearDown(() {
    container.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  group('PdfViewerLoad controller', () {
    test('initial state is loading and not ready', () {
      final state = container.read(pdfViewerLoadProvider('key-1'));
      expect(state.isLoading, isTrue);
      expect(state.hasError, isFalse);
      expect(state.handle, isNull);
      expect(state.pageCount, 0);
      expect(state.isReady, isFalse);
    });

    test('openVaultPdf succeeds and sets ready state', () async {
      nextResult = <String, dynamic>{'handle': 42, 'pageCount': 5};

      final notifier =
          container.read(pdfViewerLoadProvider('key-1').notifier);
      await notifier.openVaultPdf(_testContainer(), 'manual.pdf', l10n);

      final state = container.read(pdfViewerLoadProvider('key-1'));
      expect(state.isLoading, isFalse);
      expect(state.hasError, isFalse);
      expect(state.handle, 42);
      expect(state.pageCount, 5);
      expect(state.isReady, isTrue);
    });

    test('openVaultPdf with zero pages sets empty error', () async {
      nextResult = <String, dynamic>{'handle': 42, 'pageCount': 0};

      final notifier =
          container.read(pdfViewerLoadProvider('key-1').notifier);
      await notifier.openVaultPdf(_testContainer(), 'empty.pdf', l10n);

      final state = container.read(pdfViewerLoadProvider('key-1'));
      expect(state.isLoading, isFalse);
      expect(state.hasError, isTrue);
      expect(state.errorMessage, l10n.pdfViewerFileEmpty);
      expect(state.isReady, isFalse);
    });

    test('openVaultPdf when API throws sets error message', () async {
      nextError = PlatformException(code: 'CORRUPTED', message: 'Bad header');

      final notifier =
          container.read(pdfViewerLoadProvider('key-1').notifier);
      await notifier.openVaultPdf(_testContainer(), 'bad.pdf', l10n);

      final state = container.read(pdfViewerLoadProvider('key-1'));
      expect(state.isLoading, isFalse);
      expect(state.hasError, isTrue);
      expect(state.isReady, isFalse);
    });

    test('openLocalPdf succeeds and sets ready state', () async {
      nextResult = <String, dynamic>{'handle': 99, 'pageCount': 12};

      final notifier =
          container.read(pdfViewerLoadProvider('key-2').notifier);
      await notifier.openLocalPdf('/path/to/local.pdf', l10n);

      final state = container.read(pdfViewerLoadProvider('key-2'));
      expect(state.isLoading, isFalse);
      expect(state.hasError, isFalse);
      expect(state.handle, 99);
      expect(state.pageCount, 12);
      expect(state.isReady, isTrue);
    });

    test('openLocalPdf with zero pages sets empty error', () async {
      nextResult = <String, dynamic>{'handle': 99, 'pageCount': 0};

      final notifier =
          container.read(pdfViewerLoadProvider('key-2').notifier);
      await notifier.openLocalPdf('/path/to/empty.pdf', l10n);

      final state = container.read(pdfViewerLoadProvider('key-2'));
      expect(state.isLoading, isFalse);
      expect(state.hasError, isTrue);
      expect(state.errorMessage, l10n.pdfViewerFileEmpty);
    });

    test('setNoSourceError sets error message', () {
      final notifier =
          container.read(pdfViewerLoadProvider('key-3').notifier);
      notifier.setNoSourceError('No PDF source provided');

      final state = container.read(pdfViewerLoadProvider('key-3'));
      expect(state.isLoading, isFalse);
      expect(state.hasError, isTrue);
      expect(state.errorMessage, 'No PDF source provided');
    });

    test('disposing the provider closes the native pdf handle', () async {
      nextResult = <String, dynamic>{'handle': 77, 'pageCount': 3};

      final notifier =
          container.read(pdfViewerLoadProvider('key-dispose').notifier);
      await notifier.openVaultPdf(_testContainer(), 'doc.pdf', l10n);

      calls.clear();
      container.dispose();
      container = ProviderContainer(
        overrides: [
          vaultPdfApiProvider.overrideWithValue(VaultPdfApi(channel)),
        ],
      );

      expect(calls.any((call) => call.method == 'closePdf'), isTrue);
      expect(
        calls.firstWhere((call) => call.method == 'closePdf').arguments,
        {'handle': 77},
      );
    });
  });
}
