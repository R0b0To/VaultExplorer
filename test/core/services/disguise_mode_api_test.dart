import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/core/services/disguise_mode_api.dart';

/// A minimal fake proving the pattern documented on [disguiseModeApi]
/// actually works, mirroring `_FakeVaultExplorerApi` in
/// vault_explorer_api_test.dart: extend the concrete class, override only
/// what a test needs.
class _FakeDisguiseModeApi extends DisguiseModeApi {
  DisguiseMode modeToReturn = DisguiseMode.vault;
  DisguiseMode? lastSetMode;
  PickedLocalPdf? pickResult;

  @override
  Future<DisguiseMode> getMode() async => modeToReturn;

  @override
  Future<void> setMode(DisguiseMode mode) async {
    lastSetMode = mode;
    modeToReturn = mode;
  }

  @override
  Future<PickedLocalPdf?> pickLocalPdfFile() async => pickResult;
}

void main() {
  // disguiseModeApi is a single top-level variable shared process-wide, so
  // every test that swaps it must put the real implementation back.
  tearDown(() => disguiseModeApi = const DisguiseModeApi());

  test('disguiseModeApi can be swapped for a fake', () {
    final fake = _FakeDisguiseModeApi();
    disguiseModeApi = fake;
    expect(disguiseModeApi, same(fake));
  });

  test('DisguiseMode.fromWire maps unknown/null to vault, never decoy by default', () {
    expect(DisguiseMode.fromWire(null), DisguiseMode.vault);
    expect(DisguiseMode.fromWire('vault'), DisguiseMode.vault);
    expect(DisguiseMode.fromWire('decoy'), DisguiseMode.decoy);
    expect(DisguiseMode.fromWire('garbage'), DisguiseMode.vault);
  });

  test('wireValue round-trips through fromWire', () {
    for (final mode in DisguiseMode.values) {
      expect(DisguiseMode.fromWire(mode.wireValue), mode);
    }
  });

  test('code that calls through disguiseModeApi observes the fake', () async {
    final fake = _FakeDisguiseModeApi()..modeToReturn = DisguiseMode.decoy;
    disguiseModeApi = fake;

    final mode = await disguiseModeApi.getMode();

    expect(mode, DisguiseMode.decoy);
  });

  test('setMode is observable on the fake', () async {
    final fake = _FakeDisguiseModeApi();
    disguiseModeApi = fake;

    await disguiseModeApi.setMode(DisguiseMode.decoy);

    expect(fake.lastSetMode, DisguiseMode.decoy);
  });

  test('pickLocalPdfFile returns null when the user cancels', () async {
    final fake = _FakeDisguiseModeApi()..pickResult = null;
    disguiseModeApi = fake;

    final result = await disguiseModeApi.pickLocalPdfFile();

    expect(result, isNull);
  });

  test('pickLocalPdfFile returns the picked file', () async {
    final fake = _FakeDisguiseModeApi()
      ..pickResult = (uri: 'content://x/doc.pdf', displayName: 'doc.pdf');
    disguiseModeApi = fake;

    final result = await disguiseModeApi.pickLocalPdfFile();

    expect(result?.displayName, 'doc.pdf');
  });

  test('tearDown above restores the real implementation for other tests', () {
    expect(disguiseModeApi, isA<DisguiseModeApi>());
    expect(disguiseModeApi, isNot(isA<_FakeDisguiseModeApi>()));
  });
}
