import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/core/widgets/crypto_forms/keyfile_picker_mixin.dart';
import 'package:vaultexplorer/data/services/vault_engine/vault_explorer_api.dart';

/// A fake that can either return a canned list of keyfiles or throw, to
/// exercise both of KeyfilePickerController.pick()'s paths — the same
/// pattern documented on [vaultExplorerApi] itself.
class _FakeVaultExplorerApi extends VaultExplorerApi {
  List<KeyfileRef> toReturn = const [];
  Object? toThrow;

  @override
  Future<List<KeyfileRef>> pickKeyfiles() async {
    if (toThrow != null) throw toThrow!;
    return toReturn;
  }
}

void main() {
  late _FakeVaultExplorerApi fake;
  late int notifyCount;
  late List<String> errors;
  late KeyfilePickerController controller;

  setUp(() {
    fake = _FakeVaultExplorerApi();
    vaultExplorerApi = fake;
    notifyCount = 0;
    errors = [];
    controller = KeyfilePickerController(
      notify: () => notifyCount++,
      onError: (msg) => errors.add(msg),
    );
  });

  tearDown(() => vaultExplorerApi = const VaultExplorerApi());

  test('starts empty and not picking', () {
    expect(controller.keyfiles, isEmpty);
    expect(controller.picking, isFalse);
  });

  test('pick() adds returned keyfiles and notifies at start and end', () async {
    fake.toReturn = const [
      (uri: 'content://a', displayName: 'a.key'),
      (uri: 'content://b', displayName: 'b.key'),
    ];

    final future = controller.pick();
    expect(controller.picking, isTrue, reason: 'should flip true synchronously before awaiting');
    await future;

    expect(controller.picking, isFalse);
    expect(controller.keyfiles, hasLength(2));
    expect(errors, isEmpty);
    // At least a start-notify and an end-notify.
    expect(notifyCount, greaterThanOrEqualTo(2));
  });

  test('pick() de-duplicates by uri', () async {
    controller.keyfiles.add((uri: 'content://a', displayName: 'a.key'));
    fake.toReturn = const [
      (uri: 'content://a', displayName: 'a-renamed.key'), // same uri, ignored
      (uri: 'content://b', displayName: 'b.key'),
    ];

    await controller.pick();

    expect(controller.keyfiles, hasLength(2));
    expect(controller.keyfiles.first.displayName, 'a.key'); // original kept
  });

  test(
      'pick() routes a PlatformException to onError instead of throwing — '
      'this is the exact bug class that was previously missing in one of '
      'the hand-duplicated copies this controller replaced', () async {
    fake.toThrow = PlatformException(code: 'x', message: 'permission denied');

    await controller.pick(); // must not throw

    expect(errors, ['permission denied']);
    expect(controller.picking, isFalse, reason: 'finally{} must still reset picking');
  });

  test('pick() still resets picking to false even on an unexpected error type', () async {
    fake.toThrow = StateError('boom');

    await expectLater(controller.pick(), throwsStateError);

    expect(controller.picking, isFalse);
  });

  test('remove() removes by uri, ignoring other fields', () {
    controller.keyfiles.addAll(const [
      (uri: 'content://a', displayName: 'a.key'),
      (uri: 'content://b', displayName: 'b.key'),
    ]);

    controller.remove((uri: 'content://a', displayName: 'different display name'));

    expect(controller.keyfiles, hasLength(1));
    expect(controller.keyfiles.single.uri, 'content://b');
  });

  test('remove() notifies', () {
    controller.keyfiles.add((uri: 'content://a', displayName: 'a.key'));
    final before = notifyCount;

    controller.remove((uri: 'content://a', displayName: 'a.key'));

    expect(notifyCount, greaterThan(before));
  });
}
