import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/core/api/vault_engine_events.dart';
import 'package:vaultexplorer/core/api/vault_engine_types.dart';
import 'package:vaultexplorer/core/api/vault_lifecycle_api.dart';
import 'package:vaultexplorer/core/widgets/crypto_forms/keyfile_picker_mixin.dart';

class _FakeLifecycleApi extends VaultLifecycleApi {
  List<KeyfileRef> toReturn = const [];
  Object? toThrow;

  _FakeLifecycleApi() : super(const MethodChannel('test'), VaultEngineEvents());

  @override
  Future<List<KeyfileRef>> pickKeyfiles() async {
    if (toThrow != null) throw toThrow!;
    return toReturn;
  }
}

void main() {
  late int notifyCount;
  late List<String?> errors;
  late _FakeLifecycleApi lifecycleApi;
  late KeyfilePickerController controller;

  setUp(() {
    notifyCount = 0;
    errors = [];
    lifecycleApi = _FakeLifecycleApi();
    controller = KeyfilePickerController(
      lifecycleApi: lifecycleApi,
      notify: () => notifyCount++,
      onError: (msg) => errors.add(msg),
    );
  });

  test('starts empty and not picking', () {
    expect(controller.keyfiles, isEmpty);
    expect(controller.picking, isFalse);
  });

  test('loads selected keyfiles through the injected lifecycle API', () async {
    lifecycleApi.toReturn = const [
      (uri: 'content://selected', displayName: 'selected.key'),
    ];

    await controller.pick();

    expect(controller.keyfiles, lifecycleApi.toReturn);
    expect(controller.picking, isFalse);
    expect(notifyCount, greaterThanOrEqualTo(2));
  });

  test('remove() removes by uri, ignoring other fields', () {
    controller.keyfiles.addAll(const [
      (uri: 'content://a', displayName: 'a.key'),
      (uri: 'content://b', displayName: 'b.key'),
    ]);

    controller.remove((
      uri: 'content://a',
      displayName: 'different display name',
    ));

    expect(controller.keyfiles, hasLength(1));
    expect(controller.keyfiles.single.uri, 'content://b');
  });

  test('remove() notifies listener', () {
    controller.keyfiles.add((uri: 'content://a', displayName: 'a.key'));
    final before = notifyCount;

    controller.remove((uri: 'content://a', displayName: 'a.key'));

    expect(notifyCount, greaterThan(before));
  });
}
