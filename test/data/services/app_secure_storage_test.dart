import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/data/services/app_secure_storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.aeidolon.vaultexplorer/engine');
  const storage = AppSecureStorage.instance;

  final calls = <MethodCall>[];
  Object? nextResult;

  setUp(() {
    calls.clear();
    nextResult = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return nextResult;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('read sends readSecure with the key and returns the value', () async {
    nextResult = 'the-secret';

    final result = await storage.read(key: 'master_password_hash');

    expect(calls.single.method, 'readSecure');
    expect(calls.single.arguments['key'], 'master_password_hash');
    expect(result, 'the-secret');
  });

  test('write with a non-null value sends writeSecure with key and value', () async {
    await storage.write(key: 'k', value: 'v');

    expect(calls, hasLength(1));
    expect(calls.single.method, 'writeSecure');
    expect(calls.single.arguments['key'], 'k');
    expect(calls.single.arguments['value'], 'v');
  });

  test('write with a null value deletes instead of writing null', () async {
    await storage.write(key: 'k', value: null);

    // This is the behavior most worth locking in: writeSecure is never
    // called with a null value; a null write is routed to deleteSecure.
    expect(calls, hasLength(1));
    expect(calls.single.method, 'deleteSecure');
    expect(calls.single.arguments['key'], 'k');
  });

  test('delete sends deleteSecure with the key', () async {
    await storage.delete(key: 'k');

    expect(calls.single.method, 'deleteSecure');
    expect(calls.single.arguments['key'], 'k');
  });

  test('deleteAll sends deleteAllSecure', () async {
    await storage.deleteAll();

    expect(calls.single.method, 'deleteAllSecure');
  });

  test('readAll returns the map from the channel', () async {
    nextResult = <String, String>{'a': '1', 'b': '2'};

    final result = await storage.readAll();

    expect(calls.single.method, 'readAllSecure');
    expect(result, {'a': '1', 'b': '2'});
  });

  test('readAll returns an empty map when the channel returns null', () async {
    nextResult = null;

    final result = await storage.readAll();

    expect(result, isEmpty);
  });

  test('containsKey sends containsKeySecure and returns the bool result', () async {
    nextResult = true;

    final result = await storage.containsKey(key: 'k');

    expect(calls.single.method, 'containsKeySecure');
    expect(calls.single.arguments['key'], 'k');
    expect(result, isTrue);
  });

  test('containsKey defaults to false when the channel returns null', () async {
    nextResult = null;

    final result = await storage.containsKey(key: 'k');

    expect(result, isFalse);
  });
}
