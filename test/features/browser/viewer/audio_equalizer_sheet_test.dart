import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/data/models/audio_equalizer_settings.dart';
import 'package:vaultexplorer/features/browser/viewer/widgets/audio_equalizer_sheet.dart';
import 'package:vaultexplorer/l10n/generated/app_localizations.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    // The sheet gives haptic feedback; swallow the platform call.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async => null);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  late List<AudioEqualizerSettings> changes;
  late List<AudioEqualizerSettings> commits;

  Future<void> pumpSheet(
    WidgetTester tester, {
    AudioEqualizerSettings? initial,
  }) async {
    changes = [];
    commits = [];
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: AudioEqualizerSheet(
            initial: initial ?? AudioEqualizerSettings.defaults,
            onChanged: changes.add,
            onCommit: commits.add,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('AudioEqualizerSheet', () {
    testWidgets('shows the title, every preset and ten band sliders plus the preamp',
        (tester) async {
      await pumpSheet(tester);

      expect(find.text('Equalizer'), findsOneWidget);
      expect(find.byType(Slider), findsNWidgets(kEqualizerBandCount + 1));
      for (final preset in EqualizerPreset.values) {
        expect(find.text(_label(preset)), findsOneWidget, reason: '$preset');
      }
      expect(find.text('31'), findsOneWidget);
      expect(find.text('1k'), findsOneWidget);
      expect(find.text('16k'), findsOneWidget);
      expect(find.text('Preamp'), findsOneWidget);
      expect(find.text('Prevent clipping'), findsOneWidget);
    });

    testWidgets('the master switch reports a committed change', (tester) async {
      await pumpSheet(tester);

      await tester.tap(find.byType(Switch).first);
      await tester.pumpAndSettle();

      expect(changes.last.enabled, isTrue);
      expect(commits, hasLength(1));
      expect(commits.single.enabled, isTrue);
    });

    testWidgets('picking a preset applies it, switches the equalizer on and commits',
        (tester) async {
      await pumpSheet(tester);

      await tester.tap(find.text('Rock'));
      await tester.pumpAndSettle();

      expect(changes.last.bandGainsDb, EqualizerPreset.rock.bandGainsDb);
      expect(changes.last.enabled, isTrue);
      expect(commits, hasLength(1));
      expect(commits.single, changes.last);
    });

    testWidgets('the Flat preset does not switch the equalizer on by itself',
        (tester) async {
      await pumpSheet(tester);

      await tester.tap(find.text('Flat'));
      await tester.pumpAndSettle();

      expect(changes.last.enabled, isFalse);
      expect(commits, hasLength(1));
    });

    testWidgets('dragging a band reports each change but commits once, on release',
        (tester) async {
      await pumpSheet(tester);

      // Band 5 is 1 kHz. The sliders are rotated, so up is louder.
      await tester.drag(find.byType(Slider).at(5), const Offset(0, -40));
      await tester.pumpAndSettle();

      expect(changes, isNotEmpty);
      expect(changes.last.bandGainsDb[5], greaterThan(0));
      expect(changes.last.enabled, isTrue);
      expect(commits, hasLength(1));
      expect(commits.single, changes.last);
      // Nothing but the dragged band moved.
      for (var i = 0; i < kEqualizerBandCount; i++) {
        if (i != 5) expect(changes.last.bandGainsDb[i], 0);
      }
    });

    testWidgets('a hand-made curve is shown as Custom', (tester) async {
      await pumpSheet(tester);
      expect(find.text('Custom'), findsNothing);

      await tester.drag(find.byType(Slider).at(2), const Offset(0, -30));
      await tester.pumpAndSettle();

      expect(find.text('Custom'), findsOneWidget);
    });

    testWidgets('reset flattens the bands and preamp but leaves it switched on',
        (tester) async {
      await pumpSheet(
        tester,
        initial: AudioEqualizerSettings(
          enabled: true,
          preampDb: 3,
          bandGainsDb: EqualizerPreset.rock.bandGainsDb,
        ),
      );

      await tester.tap(find.byTooltip('Reset to defaults'));
      await tester.pumpAndSettle();

      expect(changes.last.isFlat, isTrue);
      expect(changes.last.enabled, isTrue);
      expect(commits, hasLength(1));
    });

    testWidgets('reset is unavailable while everything is already flat',
        (tester) async {
      await pumpSheet(tester);

      final button = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.restart_alt_rounded),
      );
      expect(button.onPressed, isNull);
    });

    testWidgets('the clipping guard toggles without switching the equalizer on',
        (tester) async {
      await pumpSheet(tester);

      await tester.tap(find.byType(SwitchListTile));
      await tester.pumpAndSettle();

      expect(changes.last.preventClipping, isFalse);
      expect(changes.last.enabled, isFalse);
      expect(commits, hasLength(1));
    });

    testWidgets('starts from the settings it is given', (tester) async {
      await pumpSheet(
        tester,
        initial: AudioEqualizerSettings(
          enabled: true,
          preampDb: -2,
          bandGainsDb: EqualizerPreset.bassBoost.bandGainsDb,
        ),
      );

      expect(find.text('+6'), findsOneWidget); // the 31 Hz band
      expect(find.text('-2 dB'), findsOneWidget); // the preamp readout
      expect(tester.widget<Switch>(find.byType(Switch).first).value, isTrue);
    });
  });

  group('formatting', () {
    test('formatDb gives signed values without the unit', () {
      expect(AudioEqualizerSheet.formatDb(0), '0');
      expect(AudioEqualizerSheet.formatDb(0.04), '0');
      expect(AudioEqualizerSheet.formatDb(-0.04), '0');
      expect(AudioEqualizerSheet.formatDb(3), '+3');
      expect(AudioEqualizerSheet.formatDb(12), '+12');
      expect(AudioEqualizerSheet.formatDb(-6.5), '-6.5');
      expect(AudioEqualizerSheet.formatDb(2.5), '+2.5');
    });

    test('bandLabel is short and in kHz from 1000 Hz up', () {
      expect(AudioEqualizerSheet.bandLabel(31.25), '31');
      expect(AudioEqualizerSheet.bandLabel(125), '125');
      expect(AudioEqualizerSheet.bandLabel(1000), '1k');
      expect(AudioEqualizerSheet.bandLabel(1500), '1.5k');
      expect(AudioEqualizerSheet.bandLabel(16000), '16k');
    });
  });
}

String _label(EqualizerPreset preset) => switch (preset) {
  EqualizerPreset.flat => 'Flat',
  EqualizerPreset.bassBoost => 'Bass boost',
  EqualizerPreset.trebleBoost => 'Treble boost',
  EqualizerPreset.voice => 'Voice',
  EqualizerPreset.rock => 'Rock',
  EqualizerPreset.pop => 'Pop',
  EqualizerPreset.jazz => 'Jazz',
  EqualizerPreset.classical => 'Classical',
  EqualizerPreset.electronic => 'Electronic',
  EqualizerPreset.loudness => 'Loudness',
};
