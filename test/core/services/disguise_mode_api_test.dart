import 'package:flutter/services.dart';
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

  test('takePendingLocalShareRequest parses items correctly and handles null', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    const channel = MethodChannel('com.aeidolon.vaultexplorer/disguise_channel');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'takePendingLocalShareRequest') {
        return {
          'items': [
            {
              'uri': 'content://media/123',
              'displayName': 'test.pdf',
              'sizeBytes': 1024,
              'mimeType': 'application/pdf',
            }
          ]
        };
      }
      return null;
    });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    final req = await disguiseModeApi.takePendingLocalShareRequest();
    expect(req, isNotNull);
    expect(req!.items.length, 1);
    expect(req.items.first.displayName, 'test.pdf');
    expect(req.items.first.sizeBytes, 1024);
  });

  test('handoffLocalShareToVault invokes channel method and returns boolean', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    const channel = MethodChannel('com.aeidolon.vaultexplorer/disguise_channel');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'handoffLocalShareToVault') {
        return true;
      }
      return null;
    });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    final handedOff = await disguiseModeApi.handoffLocalShareToVault();
    expect(handedOff, isTrue);
  });
}