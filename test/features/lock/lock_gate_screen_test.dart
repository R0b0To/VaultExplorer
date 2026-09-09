import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/data/services/app_settings_service.dart';
import 'package:vaultexplorer/features/lock/lock_gate_controller.dart';
import 'package:vaultexplorer/features/lock/lock_gate_screen.dart';
import 'package:vaultexplorer/l10n/generated/app_localizations.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.aeidolon.vaultexplorer/engine');

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      switch (call.method) {
        case 'readSecure':
          return null;
        case 'writeSecure':
          return true;
        case 'deleteSecure':
          return true;
        default:
          return null;
      }
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  testWidgets('LockGateScreen with popOnSuccess: true pops with true on unlock', (tester) async {
    bool? popResult;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          lockGateProvider.overrideWith(
            () => _FakeLockGate(),
          ),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () async {
                  popResult = await Navigator.of(context).push<bool>(
                    MaterialPageRoute(
                      builder: (_) => const LockGateScreen(popOnSuccess: true),
                    ),
                  );
                },
                child: const Text('Open Gate'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // Tap to push LockGateScreen
    await tester.tap(find.text('Open Gate'));
    await tester.pumpAndSettle();

    // Verify LockGateScreen is mounted
    expect(find.byType(LockGateScreen), findsOneWidget);

    // Tap unlock button to trigger unlock on fake notifier
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();

    // Gate should have popped with true
    expect(find.byType(LockGateScreen), findsNothing);
    expect(popResult, isTrue);
  });
}

class _FakeLockGate extends LockGate {
  @override
  LockGateState build() {
    return LockGateState(
      loading: false,
      settings: AppSettings(masterUnlockMethod: MasterUnlockMethod.password),
    );
  }

  @override
  Future<bool> checkPassword(String candidate, AppLocalizations l10n) async {
    // Unlock succeeds by incrementing navigateTick
    state = LockGateState(
      loading: false,
      settings: state.settings,
      navigateTick: state.navigateTick + 1,
    );
    return false;
  }
}
