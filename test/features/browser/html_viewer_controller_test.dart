import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/features/browser/viewer/html_viewer_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.aeidolon.vaultexplorer/engine');
  late ProviderContainer container;
  late ProviderSubscription subscription;

  const volId = 1;
  final provider = htmlViewerProvider(volId);

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async => null);

    container = ProviderContainer();
    subscription = container.listen(provider, (_, __) {});
  });

  tearDown(() {
    subscription.close();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    container.dispose();
  });

  group('HtmlViewerController Tests', () {
    test('initializes with default loading and navigation state', () {
      final state = container.read(provider);

      expect(state.isLoading, isTrue);
      expect(state.hasError, isFalse);
      expect(state.canGoBack, isFalse);
      expect(state.canGoForward, isFalse);
      expect(state.isFullscreen, isFalse);
      expect(state.isContainerLocked, isFalse);
    });

    test('onPageFinished updates title and navigation capability flags', () {
      final controller = container.read(provider.notifier);

      controller.onPageFinished(
        title: 'Decrypted Page',
        canGoBack: true,
        canGoForward: false,
      );

      final state = container.read(provider);
      expect(state.isLoading, isFalse);
      expect(state.hasError, isFalse);
      expect(state.title, 'Decrypted Page');
      expect(state.canGoBack, isTrue);
      expect(state.canGoForward, isFalse);
    });

    test('onPageError records error message and clears loading', () {
      final controller = container.read(provider.notifier);

      controller.onPageError('Network failure');

      final state = container.read(provider);
      expect(state.isLoading, isFalse);
      expect(state.hasError, isTrue);
      expect(state.errorMessage, 'Network failure');
    });

    test('setLoading and setFullscreen update respective flags', () {
      final controller = container.read(provider.notifier);

      controller.setLoading();
      expect(container.read(provider).isLoading, isTrue);

      controller.setFullscreen(true);
      expect(container.read(provider).isFullscreen, isTrue);
    });
  });
}