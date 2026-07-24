import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/data/services/vault_engine/vault_explorer_api.dart';

/// A minimal fake proving the pattern documented on [vaultExplorerApi]
/// actually works: extend the concrete class, override only what a test
/// needs. No abstract interface, no mockito/mocktail — VaultExplorerApi's
/// state is entirely `static`, so there's nothing else to fake.
class _FakeVaultExplorerApi extends VaultExplorerApi {
  List<KeyfileRef> keyfilesToReturn = const [];

  @override
  Future<List<KeyfileRef>> pickKeyfiles() async => keyfilesToReturn;
}

void main() {
  // vaultExplorerApi is a single top-level variable shared process-wide, so
  // every test that swaps it must put the real implementation back —
  // otherwise a later test (in this file or, if tests ever share an
  // isolate, another file) would silently run against the fake.
  tearDown(() => vaultExplorerApi = const VaultExplorerApi());

  test('vaultExplorerApi can be swapped for a fake', () {
    final fake = _FakeVaultExplorerApi();
    vaultExplorerApi = fake;
    expect(vaultExplorerApi, same(fake));
  });

  test('code that calls through vaultExplorerApi observes the fake', () async {
    final fake = _FakeVaultExplorerApi()
      ..keyfilesToReturn = const [(uri: 'content://a', displayName: 'a.key')];
    vaultExplorerApi = fake;

    final result = await vaultExplorerApi.pickKeyfiles();

    expect(result, hasLength(1));
    expect(result.single.displayName, 'a.key');
  });

  test('tearDown above restores the real implementation for other tests', () {
    expect(vaultExplorerApi, isA<VaultExplorerApi>());
    expect(vaultExplorerApi, isNot(isA<_FakeVaultExplorerApi>()));
  });
}
