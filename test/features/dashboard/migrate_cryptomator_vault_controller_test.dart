import 'dart:ui';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/core/api/vault_lifecycle_api.dart';
import 'package:vaultexplorer/core/providers/vault_engine_providers.dart';
import 'package:vaultexplorer/features/dashboard/widgets/migrate_cryptomator_vault_controller.dart';
import 'package:vaultexplorer/l10n/generated/app_localizations.dart';

class _FakeMigrateApi implements VaultLifecycleApi {
  final List<(String, String)> calls = [];
  Object? error;
  bool result = true;

  @override
  Future<bool> migrateCryptomatorVault(String folderUri, String password) async {
    calls.add((folderUri, password));
    if (error != null) throw error!;
    return result;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  const uri = 'content://tree/vault';
  final l10n = lookupAppLocalizations(const Locale('en'));

  late _FakeMigrateApi api;
  late ProviderContainer container;

  MigrateCryptomatorVaultState read() => container.read(migrateCryptomatorVaultProvider(uri));
  MigrateCryptomatorVault notifier() => container.read(migrateCryptomatorVaultProvider(uri).notifier);

  setUp(() {
    api = _FakeMigrateApi();
    container = ProviderContainer(
      overrides: [vaultLifecycleApiProvider.overrideWith((ref) => api)],
    );
    addTearDown(container.dispose);
    container.listen(migrateCryptomatorVaultProvider(uri), (_, __) {});
  });

  test('cannot submit until a password is typed AND the warning is confirmed', () {
    expect(read().canSubmit, isFalse);
    notifier().setPasswordFilled(true);
    expect(read().canSubmit, isFalse);
    notifier().setConfirmed(true);
    expect(read().canSubmit, isTrue);
    notifier().setPasswordFilled(false);
    expect(read().canSubmit, isFalse);
  });

  test('submit does nothing while it cannot submit', () async {
    notifier().setPasswordFilled(true); // not confirmed
    await notifier().submit(password: 'pw', l10n: l10n);
    expect(api.calls, isEmpty);
    expect(read().successTick, 0);
  });

  test('success bumps successTick and calls the api once with uri and password', () async {
    notifier().setPasswordFilled(true);
    notifier().setConfirmed(true);
    await notifier().submit(password: 'secret', l10n: l10n);
    expect(api.calls, [(uri, 'secret')]);
    expect(read().successTick, 1);
    expect(read().isProcessing, isFalse);
    expect(read().errorMsg, isNull);
  });

  test('wrong password shows the standard incorrect-password message', () async {
    api.error = PlatformException(code: 'AUTH_FAIL', message: 'Incorrect password');
    notifier().setPasswordFilled(true);
    notifier().setConfirmed(true);
    await notifier().submit(password: 'bad', l10n: l10n);
    expect(read().errorMsg, l10n.incorrectPasswordError);
    expect(read().successTick, 0);
    expect(read().isProcessing, isFalse);
  });

  test('an unlocked vault gets the lock-first message', () async {
    api.error = PlatformException(code: 'VAULT_UNLOCKED', message: 'native text');
    notifier().setPasswordFilled(true);
    notifier().setConfirmed(true);
    await notifier().submit(password: 'pw', l10n: l10n);
    expect(read().errorMsg, l10n.cryptomatorUpgradeUnlockedError);
  });

  test('INVALID_VAULT shows the engine message; an empty one falls back', () async {
    api.error = PlatformException(code: 'INVALID_VAULT', message: 'Could not back up masterkey.cryptomator');
    notifier().setPasswordFilled(true);
    notifier().setConfirmed(true);
    await notifier().submit(password: 'pw', l10n: l10n);
    expect(read().errorMsg, 'Could not back up masterkey.cryptomator');

    api.error = PlatformException(code: 'INVALID_VAULT');
    await notifier().submit(password: 'pw', l10n: l10n);
    expect(read().errorMsg, l10n.cryptomatorUpgradeFailedMessage);
  });

  test('a retry after an error clears the error first', () async {
    api.error = PlatformException(code: 'AUTH_FAIL');
    notifier().setPasswordFilled(true);
    notifier().setConfirmed(true);
    await notifier().submit(password: 'bad', l10n: l10n);
    expect(read().errorMsg, isNotNull);

    api.error = null;
    await notifier().submit(password: 'good', l10n: l10n);
    expect(read().errorMsg, isNull);
    expect(read().successTick, 1);
  });
}
