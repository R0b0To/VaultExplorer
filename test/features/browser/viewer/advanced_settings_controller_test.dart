import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/features/browser/viewer/widgets/advanced_settings_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ProviderContainer container;

  setUp(() {
    container = ProviderContainer();
  });

  tearDown(() {
    container.dispose();
  });

  group('AdvancedSettingsController Tests', () {
    const params = AdvancedSettingsParams(
      initialRotation: 0,
      initialImageFit: BoxFit.contain,
      initialSlideshowDelaySeconds: 4,
      initialPlaybackSpeed: 1.0,
      initialSubtitlesEnabled: true,
      initialSubtitleFontSize: 15.0,
      initialSubtitleVerticalPosition: 0.0,
    );
    final provider = advancedSettingsControllerProvider(params);

    test('initializes with baseline parameters in main page', () {
      final state = container.read(provider);

      expect(state.sheetPage, 'main');
      expect(state.rotation, 0);
      expect(state.imageFit, BoxFit.contain);
      expect(state.slideshowDelaySeconds, 4);
      expect(state.playbackSpeed, 1.0);
      expect(state.subtitlesEnabled, isTrue);
      expect(state.subtitleFontSize, 15.0);
      expect(state.subtitleVerticalPosition, 0.0);
    });

    test('rotate increments rotation modulo 4 and calls callback', () {
      final controller = container.read(provider.notifier);
      int? reportedRotation;

      controller.rotate((r) => reportedRotation = r);
      expect(container.read(provider).rotation, 1);
      expect(reportedRotation, 1);

      controller.rotate((r) => reportedRotation = r);
      controller.rotate((r) => reportedRotation = r);
      controller.rotate((r) => reportedRotation = r);
      expect(container.read(provider).rotation, 0); // 4 % 4 == 0
      expect(reportedRotation, 0);
    });

    test('setSheetPage navigates to submenus', () {
      final controller = container.read(provider.notifier);

      controller.setSheetPage('playbackSpeed');
      expect(container.read(provider).sheetPage, 'playbackSpeed');

      controller.setSheetPage('audioTracks');
      expect(container.read(provider).sheetPage, 'audioTracks');

      controller.setSheetPage('main');
      expect(container.read(provider).sheetPage, 'main');
    });

    test('setImageFit, setSlideshowDelay, and setPlaybackSpeed reset sheetPage to main', () {
      final controller = container.read(provider.notifier);

      controller.setSheetPage('imageFit');
      controller.setImageFit(BoxFit.cover, (_) {});
      expect(container.read(provider).imageFit, BoxFit.cover);
      expect(container.read(provider).sheetPage, 'main');

      controller.setSheetPage('slideshowDelay');
      controller.setSlideshowDelay(8, (_) {});
      expect(container.read(provider).slideshowDelaySeconds, 8);
      expect(container.read(provider).sheetPage, 'main');

      controller.setSheetPage('playbackSpeed');
      controller.setPlaybackSpeed(1.5, (_) {});
      expect(container.read(provider).playbackSpeed, 1.5);
      expect(container.read(provider).sheetPage, 'main');
    });

    test('subtitle sizing and positioning mutators update state', () {
      final controller = container.read(provider.notifier);

      controller.setSubtitleFontSize(19.0, (_) {});
      expect(container.read(provider).subtitleFontSize, 19.0);

      controller.setSubtitleVerticalPosition(0.5, (_) {});
      expect(container.read(provider).subtitleVerticalPosition, 0.5);

      controller.setSubtitlesEnabled(false, (_) {});
      expect(container.read(provider).subtitlesEnabled, isFalse);
    });
  });
}