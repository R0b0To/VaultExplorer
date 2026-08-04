import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/core/services/disguise_mode_api.dart';

class _FakeDisguiseModeApi extends DisguiseModeApi {
  DisguiseMode modeToReturn = DisguiseMode.vault;
  DisguiseMode? lastSetMode;

  @override
  Future<DisguiseMode> getMode() async => modeToReturn;

  @override
  Future<void> setMode(DisguiseMode mode) async {
    lastSetMode = mode;
    modeToReturn = mode;
  }
}

void main() {
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

  test('tearDown above restores the real implementation for other tests', () {
    expect(disguiseModeApi, isA<DisguiseModeApi>());
    expect(disguiseModeApi, isNot(isA<_FakeDisguiseModeApi>()));
  });
}