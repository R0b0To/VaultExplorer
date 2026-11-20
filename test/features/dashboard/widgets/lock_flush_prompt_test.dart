import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/api/vault_engine_events.dart';
import 'package:vaultexplorer/core/api/vault_engine_types.dart';
import 'package:vaultexplorer/core/api/vault_lifecycle_api.dart';
import 'package:vaultexplorer/features/dashboard/widgets/lock_flush_prompt.dart';
import 'package:vaultexplorer/l10n/generated/app_localizations.dart';

/// Answers each lock attempt from a script and records whether it was forced.
class _ScriptedLifecycleApi extends VaultLifecycleApi {
  _ScriptedLifecycleApi(this._script)
    : super(const MethodChannel('test/lock_prompt'), VaultEngineEvents());

  final List<LockResult> _script;
  final List<bool> forced = [];

  @override
  Future<LockResult> lockContainerDetailed(
    String filePath, {
    bool force = false,
  }) async {
    forced.add(force);
    return _script.removeAt(0);
  }
}

void main() {
  const refused = LockResult.flushRefused;

  Future<void> pumpHost(
    WidgetTester tester,
    Future<void> Function(BuildContext context) onStart,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => onStart(context),
                child: const Text('start'),
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('shows no dialog when the lock simply succeeds', (tester) async {
    final api = _ScriptedLifecycleApi([LockResult.locked]);
    LockResult? outcome;
    await pumpHost(tester, (context) async {
      outcome = await lockWithFlushPrompt(
        context: context,
        lifecycle: api,
        uri: 'content://vault',
        displayName: 'Backup Drive',
      );
    });

    await tester.tap(find.text('start'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
    expect(outcome, LockResult.locked);
    expect(api.forced, [false]);
  });

  testWidgets('a plain failure is returned without asking anything', (tester) async {
    final api = _ScriptedLifecycleApi([LockResult.failed]);
    LockResult? outcome;
    await pumpHost(tester, (context) async {
      outcome = await lockWithFlushPrompt(
        context: context,
        lifecycle: api,
        uri: 'content://vault',
        displayName: 'Backup Drive',
      );
    });

    await tester.tap(find.text('start'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
    expect(outcome, LockResult.failed);
    expect(api.forced, [false]);
  });

  testWidgets('Retry tries again without forcing', (tester) async {
    final api = _ScriptedLifecycleApi([refused, LockResult.locked]);
    LockResult? outcome;
    await pumpHost(tester, (context) async {
      outcome = await lockWithFlushPrompt(
        context: context,
        lifecycle: api,
        uri: 'content://vault',
        displayName: 'Backup Drive',
      );
    });

    await tester.tap(find.text('start'));
    await tester.pumpAndSettle();

    expect(find.text("Couldn't write to the device"), findsOneWidget);
    expect(find.textContaining('Backup Drive'), findsOneWidget);

    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(outcome, LockResult.locked);
    expect(api.forced, [false, false]);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('keeps asking while the device keeps refusing', (tester) async {
    final api = _ScriptedLifecycleApi([refused, refused, LockResult.locked]);
    LockResult? outcome;
    await pumpHost(tester, (context) async {
      outcome = await lockWithFlushPrompt(
        context: context,
        lifecycle: api,
        uri: 'content://vault',
        displayName: 'Backup Drive',
      );
    });

    await tester.tap(find.text('start'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    // Second refusal: the dialog is offered again.
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(outcome, LockResult.locked);
    expect(api.forced, [false, false, false]);
  });

  testWidgets('Lock anyway forces the lock', (tester) async {
    final api = _ScriptedLifecycleApi([refused, LockResult.locked]);
    LockResult? outcome;
    await pumpHost(tester, (context) async {
      outcome = await lockWithFlushPrompt(
        context: context,
        lifecycle: api,
        uri: 'content://vault',
        displayName: 'Backup Drive',
      );
    });

    await tester.tap(find.text('start'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lock anyway'));
    await tester.pumpAndSettle();

    expect(outcome, LockResult.locked);
    expect(api.forced, [false, true]);
  });

  testWidgets('Cancel leaves the container open and never forces', (tester) async {
    final api = _ScriptedLifecycleApi([refused]);
    LockResult? outcome;
    await pumpHost(tester, (context) async {
      outcome = await lockWithFlushPrompt(
        context: context,
        lifecycle: api,
        uri: 'content://vault',
        displayName: 'Backup Drive',
      );
    });

    await tester.tap(find.text('start'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(outcome, refused);
    expect(api.forced, [false]);
  });

  testWidgets('firstResult skips the initial attempt', (tester) async {
    final api = _ScriptedLifecycleApi([LockResult.locked]);
    LockResult? outcome;
    await pumpHost(tester, (context) async {
      outcome = await lockWithFlushPrompt(
        context: context,
        lifecycle: api,
        uri: 'content://vault',
        displayName: 'Backup Drive',
        firstResult: refused,
      );
    });

    await tester.tap(find.text('start'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(outcome, LockResult.locked);
    // Only the retry hit the API; the refused attempt was made by the caller.
    expect(api.forced, [false]);
  });
}
