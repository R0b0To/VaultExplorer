import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:test/test.dart';
import 'package:vaultexplorer/core/api/vault_storage_api.dart';
import 'package:vaultexplorer/data/services/vault_engine/channel_methods.dart';
import 'package:vaultexplorer/data/services/vault_relocation_gateway.dart';
import 'package:vaultexplorer/data/services/vault_relocation_service.dart';

/// A channel that answers from a script and records every call.
class _FakeChannel extends MethodChannel {
  _FakeChannel() : super('test/vault_storage');
  final List<({String method, Object? args})> calls = [];
  final Map<String, Object? Function(Object? args)> handlers = {};

  @override
  Future<T?> invokeMethod<T>(String method, [dynamic arguments]) async {
    calls.add((method: method, args: arguments));
    final h = handlers[method];
    if (h == null) throw MissingPluginException(method);
    return h(arguments) as T?;
  }
}

const _uri = 'file:///data/user/0/com.aeidolon.vaultexplorer/files/vaults/work.hc';

void main() {
  late _FakeChannel channel;
  late VaultStorageApi api;
  late List<void Function(int, int, int)> listeners;
  late int unsubscribed;
  late List<int> cancelled;
  late VaultRelocationGateway gateway;

  setUp(() {
    channel = _FakeChannel();
    api = VaultStorageApi(channel);
    listeners = [];
    unsubscribed = 0;
    cancelled = [];
    gateway = VaultRelocationGateway(
      storage: api,
      subscribeProgress: (listener) {
        listeners.add(listener);
        return () => unsubscribed++;
      },
      cancelOperation: (id) async => cancelled.add(id),
    );
  });

  group('VaultStorageApi', () {
    test('getAppStorageInfo parses free space and vaults', () async {
      channel.handlers[ChannelMethods.getAppStorageInfo] = (a) => {
        'rootUri': 'file:///data/user/0/app/files/vaults',
        'availableBytes': 123456789,
        'vaults': [
          {'uri': _uri, 'name': 'work.hc', 'isDirectory': false, 'sizeBytes': 10},
          {'uri': 'file:///x/Notes', 'name': 'Notes', 'isDirectory': true, 'sizeBytes': -1},
        ],
      };
      final info = await api.getAppStorageInfo(includeSizes: true);
      expect(channel.calls.single.args, {'includeSizes': true});
      expect(info.availableBytes, 123456789);
      expect(info.vaults.map((v) => v.name).toList(), ['work.hc', 'Notes']);
      expect(info.vaults[1].isDirectory, isTrue);
      expect(info.vaults[1].sizeBytes, -1);
    });

    test('createAppStorageContainer sends the create arguments and returns the new URI', () async {
      channel.handlers[ChannelMethods.createAppStorageContainer] = (a) => {'success': true, 'uri': _uri};
      final r = await api.createAppStorageContainer(
        displayName: 'work.hc',
        sizeBytes: 1024,
        password: 'pw',
        pim: 0,
        fileSystem: 'ext4',
        cipherId: 1,
        hashId: 2,
        keyfilePaths: const [],
        userEntropy: Uint8List.fromList([1, 2, 3]),
      );
      expect(r.success, isTrue);
      expect(r.uri, _uri);
      final args = channel.calls.single.args as Map;
      expect(args['displayName'], 'work.hc');
      expect(args['sizeBytes'], 1024);
      expect(args['hiddenKeyfilePaths'], isEmpty);
    });

    test('createAppStorageContainer lets INSUFFICIENT_SPACE through and flattens other failures', () async {
      channel.handlers[ChannelMethods.createAppStorageContainer] = (a) => throw PlatformException(
        code: 'INSUFFICIENT_SPACE',
        details: {'neededBytes': 10, 'availableBytes': 5},
      );
      await expectLater(
        api.createAppStorageContainer(displayName: 'a', sizeBytes: 1, password: 'p', pim: 0, fileSystem: 'ext4', cipherId: 1, hashId: 1, keyfilePaths: const []),
        throwsA(predicate((e) => e is PlatformException && e.code == 'INSUFFICIENT_SPACE')),
      );
      channel.handlers[ChannelMethods.createAppStorageContainer] = (a) => throw PlatformException(code: 'IO_ERROR');
      final r = await api.createAppStorageContainer(displayName: 'a', sizeBytes: 1, password: 'p', pim: 0, fileSystem: 'ext4', cipherId: 1, hashId: 1, keyfilePaths: const []);
      expect(r.success, isFalse);
      expect(r.uri, isNull);
    });

    test('createAppStorageFolderVault returns the URI, or null on failure', () async {
      channel.handlers[ChannelMethods.createAppStorageFolderVault] = (a) => {'success': true, 'uri': 'file:///x/Notes'};
      expect(await api.createAppStorageFolderVault(format: 'gocryptfs', displayName: 'Notes', password: 'pw'), 'file:///x/Notes');
      expect((channel.calls.single.args as Map)['format'], 'gocryptfs');
      channel.handlers[ChannelMethods.createAppStorageFolderVault] = (a) => throw PlatformException(code: 'CREATE_FAILED');
      expect(await api.createAppStorageFolderVault(format: 'cryfs', displayName: 'N', password: 'pw'), isNull);
    });

    test('relocateFromAppStorage is null when the picker was dismissed', () async {
      channel.handlers[ChannelMethods.relocateFromAppStorage] = (a) => {'success': false, 'uri': null};
      expect(await api.relocateFromAppStorage(sourceUri: _uri, isFolderVault: false, displayName: 'w', opId: 1), isNull);
    });
  });

  group('VaultRelocationGateway', () {
    test('copyIn forwards the arguments and returns the copy', () async {
      channel.handlers[ChannelMethods.relocateToAppStorage] = (a) => {'uri': _uri, 'bytes': 2048, 'files': 5};
      final copy = await gateway.copyIn(sourceUri: 'content://x/doc', isFolderVault: true, displayName: 'Notes', opId: 7);
      expect(copy.uri, _uri);
      expect(copy.bytes, 2048);
      expect(copy.files, 5);
      expect(channel.calls.single.args, {'sourceUri': 'content://x/doc', 'isFolderVault': true, 'displayName': 'Notes', 'opId': 7});
    });

    test('progress is delivered only for its own operation and the listener is removed afterwards', () async {
      channel.handlers[ChannelMethods.relocateToAppStorage] = (a) {
        listeners.single(7, 10, 100); // ours
        listeners.single(8, 99, 100); // someone else's split/join
        listeners.single(7, 100, 100);
        return {'uri': _uri};
      };
      final seen = <(int, int)>[];
      await gateway.copyIn(sourceUri: 's', isFolderVault: false, displayName: 'n', opId: 7, onProgress: (d, t) => seen.add((d, t)));
      expect(seen, [(10, 100), (100, 100)]);
      expect(unsubscribed, 1);
    });

    test('the progress listener is removed even when the copy fails', () async {
      channel.handlers[ChannelMethods.relocateToAppStorage] = (a) => throw PlatformException(code: 'VERIFY_FAILED', message: 'mismatch');
      await expectLater(
        gateway.copyIn(sourceUri: 's', isFolderVault: false, displayName: 'n', opId: 7, onProgress: (_, _) {}),
        throwsA(isA<RelocationException>()),
      );
      expect(unsubscribed, 1);
    });

    test('no listener is registered when nobody asked for progress', () async {
      channel.handlers[ChannelMethods.relocateToAppStorage] = (a) => {'uri': _uri};
      await gateway.copyIn(sourceUri: 's', isFolderVault: false, displayName: 'n', opId: 7);
      expect(listeners, isEmpty);
    });

    test('maps every native error code to its failure', () async {
      const expected = {
        'VAULT_UNLOCKED': RelocationFailure.vaultUnlocked,
        'UNSUPPORTED_SOURCE': RelocationFailure.unsupportedSource,
        'SPLIT_UNSUPPORTED': RelocationFailure.splitContainer,
        'NOT_A_VAULT_FOLDER': RelocationFailure.notAVaultFolder,
        'DESTINATION_NOT_EMPTY': RelocationFailure.destinationNotEmpty,
        'ALREADY_IN_APP_STORAGE': RelocationFailure.alreadyInAppStorage,
        'NOT_IN_APP_STORAGE': RelocationFailure.notInAppStorage,
        'SOURCE_MISSING': RelocationFailure.sourceMissing,
        'INSUFFICIENT_SPACE': RelocationFailure.insufficientSpace,
        'VERIFY_FAILED': RelocationFailure.verifyFailed,
        'CANCELLED': RelocationFailure.cancelled,
        'NO_PICKER': RelocationFailure.noPicker,
        'IO_ERROR': RelocationFailure.io,
        'SOMETHING_NEW': RelocationFailure.io,
      };
      for (final entry in expected.entries) {
        channel.handlers[ChannelMethods.relocateToAppStorage] = (a) => throw PlatformException(code: entry.key);
        await expectLater(
          gateway.copyIn(sourceUri: 's', isFolderVault: false, displayName: 'n', opId: 1),
          throwsA(predicate((e) => e is RelocationException && e.reason == entry.value)),
          reason: entry.key,
        );
      }
    });

    test('insufficient space carries the byte counts', () async {
      channel.handlers[ChannelMethods.relocateToAppStorage] = (a) => throw PlatformException(
        code: 'INSUFFICIENT_SPACE',
        message: 'Not enough free space',
        details: {'neededBytes': 5000000000, 'availableBytes': 1200},
      );
      try {
        await gateway.copyIn(sourceUri: 's', isFolderVault: false, displayName: 'n', opId: 1);
        fail('should have thrown');
      } on RelocationException catch (e) {
        expect(e.reason, RelocationFailure.insufficientSpace);
        expect(e.neededBytes, 5000000000);
        expect(e.availableBytes, 1200);
      }
    });

    test('an empty URI from the platform is an error, not a vault at ""', () async {
      channel.handlers[ChannelMethods.relocateToAppStorage] = (a) => {'bytes': 1};
      await expectLater(
        gateway.copyIn(sourceUri: 's', isFolderVault: false, displayName: 'n', opId: 1),
        throwsA(predicate((e) => e is RelocationException && e.reason == RelocationFailure.io)),
      );
    });

    test('copyOut returns null when the picker is dismissed and the copy otherwise', () async {
      channel.handlers[ChannelMethods.relocateFromAppStorage] = (a) => {'success': false};
      expect(await gateway.copyOut(sourceUri: _uri, isFolderVault: false, displayName: 'n', opId: 1), isNull);
      channel.handlers[ChannelMethods.relocateFromAppStorage] = (a) => {'success': true, 'uri': 'content://x/doc', 'bytes': 9, 'files': 1};
      final copy = await gateway.copyOut(sourceUri: _uri, isFolderVault: false, displayName: 'n', opId: 1);
      expect(copy!.uri, 'content://x/doc');
    });

    test('finalize maps the result and the errors', () async {
      channel.handlers[ChannelMethods.finalizeRelocation] = (a) => {'sourceDeleted': true, 'automationReset': true, 'reason': null};
      final r = await gateway.finalize(oldUri: 'a', newUri: 'b', isFolderVault: false, deleteSource: true);
      expect(r.sourceDeleted, isTrue);
      expect(r.automationReset, isTrue);
      expect(channel.calls.last.args, {'oldUri': 'a', 'newUri': 'b', 'isFolderVault': false, 'deleteSource': true});

      channel.handlers[ChannelMethods.finalizeRelocation] = (a) => throw PlatformException(code: 'IO_ERROR');
      await expectLater(
        gateway.finalize(oldUri: 'a', newUri: 'b', isFolderVault: false, deleteSource: true),
        throwsA(isA<RelocationException>()),
      );
    });

    test('discardCopy calls through and maps errors', () async {
      channel.handlers[ChannelMethods.discardRelocationCopy] = (a) => true;
      await gateway.discardCopy(uri: _uri, isFolderVault: false);
      expect(channel.calls.last.args, {'uri': _uri, 'isFolderVault': false});
      channel.handlers[ChannelMethods.discardRelocationCopy] = (a) => throw PlatformException(code: 'IO_ERROR');
      await expectLater(gateway.discardCopy(uri: _uri, isFolderVault: false), throwsA(isA<RelocationException>()));
    });

    test('cancel delegates to the cancel hook', () async {
      await gateway.cancel(42);
      expect(cancelled, [42]);
    });
  });
}
