import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/core/api/vault_repair_api.dart';
import 'package:vaultexplorer/core/providers/vault_engine_providers.dart';
import 'package:vaultexplorer/features/tools/models/tool_models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('com.aeidolon.vaultexplorer/engine');
  const api = VaultRepairApi(channel);

  final calls = <MethodCall>[];
  Object? nextResult;
  Object? nextError;

  setUp(() {
    calls.clear();
    nextResult = null;
    nextError = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          if (nextError != null) throw nextError!;
          return nextResult;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('vaultRepairApiProvider resolves from ProviderContainer', () {
    final containerRef = ProviderContainer();
    addTearDown(containerRef.dispose);

    final resolvedApi = containerRef.read(vaultRepairApiProvider);
    expect(resolvedApi, isA<VaultRepairApi>());
  });

  group('diagnoseUnmountedContainerFile', () {
    test('sends uri and opId, parses diagnosisCode and format', () async {
      nextResult = <String, dynamic>{'diagnosisCode': 2, 'format': 'luks2'};

      final result = await api.diagnoseUnmountedContainerFile('content://c', opId: 5);

      expect(calls.single.method, 'diagnoseUnmountedContainerFile');
      expect(calls.single.arguments['uri'], 'content://c');
      expect(calls.single.arguments['opId'], 5);
      expect(result.diagnosisCode, 2);
      expect(result.format, 'luks2');
    });

    test('defaults opId to -1 (no live logging) when omitted', () async {
      nextResult = <String, dynamic>{'diagnosisCode': 0, 'format': 'veracrypt'};
      await api.diagnoseUnmountedContainerFile('content://c');
      expect(calls.single.arguments['opId'], -1);
    });

    test(
      'defaults diagnosisCode to 1 (headerCorrupted) when native returns nothing -- '
      'a fail-pessimistic default, not fail-healthy',
      () async {
        nextResult = null;
        final result = await api.diagnoseUnmountedContainerFile('content://c');
        expect(result.diagnosisCode, 1);
        expect(result.format, isNull);
      },
    );
  });

  group('diagnoseMountedVolumeFilesystem', () {
    test('sends volId and opId, parses diagnosisCode, format always null', () async {
      nextResult = <String, dynamic>{'diagnosisCode': 2};

      final result = await api.diagnoseMountedVolumeFilesystem(7, opId: 3);

      expect(calls.single.method, 'diagnoseMountedVolumeFilesystem');
      expect(calls.single.arguments['volId'], 7);
      expect(calls.single.arguments['opId'], 3);
      expect(result.diagnosisCode, 2);
      expect(result.format, isNull);
    });

    test(
      'defaults diagnosisCode to 0 (healthy) when native returns nothing -- '
      'the OPPOSITE default from diagnoseUnmountedContainerFile, since this '
      'variant only runs against an already-successfully-mounted volume',
      () async {
        nextResult = null;
        final result = await api.diagnoseMountedVolumeFilesystem(7);
        expect(result.diagnosisCode, 0);
      },
    );
  });

  group('repairFolderVault', () {
    final target = const FolderVaultTarget(
      treeUri: 'content://vault',
      displayName: 'My Vault',
      format: 'gocryptfs',
      mountedVolId: null,
    );

    test('sends uri/format/password/volId/opId and parses the report', () async {
      nextResult = <String, dynamic>{
        'format': 'gocryptfs',
        'fixedCount': 2,
        'recoveredCount': 1,
        'removedCount': 0,
        'remainingIssues': <Object?>[],
      };

      final result = await api.repairFolderVault(target, password: 'pw', opId: 9);

      expect(calls.single.method, 'repairFolderVault');
      expect(calls.single.arguments['uri'], 'content://vault');
      expect(calls.single.arguments['format'], 'gocryptfs');
      expect(calls.single.arguments['password'], 'pw');
      expect(calls.single.arguments['volId'], isNull);
      expect(calls.single.arguments['opId'], 9);
      expect(result.fixedCount, 2);
      expect(result.recoveredCount, 1);
      expect(result.healthy, isTrue);
    });

    test('throws FolderVaultInvalidException when native returns null', () async {
      nextResult = null;
      await expectLater(
        () => api.repairFolderVault(target),
        throwsA(isA<FolderVaultInvalidException>()),
      );
    });

    test('maps INVALID_VAULT to FolderVaultInvalidException with native message', () async {
      nextError = PlatformException(code: 'INVALID_VAULT', message: 'not a vault');
      await expectLater(
        api.repairFolderVault(target),
        throwsA(
          isA<FolderVaultInvalidException>().having((e) => e.message, 'message', 'not a vault'),
        ),
      );
    });

    test('maps PASSWORD_INCORRECT to RepairIncorrectPasswordException', () async {
      nextError = PlatformException(code: 'PASSWORD_INCORRECT');
      await expectLater(
        () => api.repairFolderVault(target),
        throwsA(isA<RepairIncorrectPasswordException>()),
      );
    });

    test('rethrows unmapped PlatformException codes as-is', () async {
      nextError = PlatformException(code: 'IO_ERROR');
      await expectLater(
        () => api.repairFolderVault(target),
        throwsA(isA<PlatformException>().having((e) => e.code, 'code', 'IO_ERROR')),
      );
    });
  });

  group('restoreBackupHeaderUnmounted', () {
    test('sends all fields and returns success', () async {
      nextResult = true;
      final result = await api.restoreBackupHeaderUnmounted(
        uri: 'content://c',
        password: 'pw',
        pim: 4,
        cipherId: 1,
        hashId: 2,
        opId: 11,
      );
      expect(calls.single.method, 'restoreBackupHeaderUnmounted');
      expect(calls.single.arguments['uri'], 'content://c');
      expect(calls.single.arguments['password'], 'pw');
      expect(calls.single.arguments['pim'], 4);
      expect(calls.single.arguments['cipherId'], 1);
      expect(calls.single.arguments['hashId'], 2);
      expect(calls.single.arguments['opId'], 11);
      expect(result, isTrue);
    });

    test('defaults pim/cipherId/hashId/opId and treats null password as "not supplied yet"', () async {
      nextResult = false;
      await api.restoreBackupHeaderUnmounted(uri: 'content://c');
      expect(calls.single.arguments['password'], isNull);
      expect(calls.single.arguments['pim'], 0);
      expect(calls.single.arguments['cipherId'], 255);
      expect(calls.single.arguments['hashId'], 255);
      expect(calls.single.arguments['opId'], -1);
    });

    test('maps PASSWORD_REQUIRED to RepairPasswordRequiredException', () async {
      nextError = PlatformException(code: 'PASSWORD_REQUIRED');
      await expectLater(
        () => api.restoreBackupHeaderUnmounted(uri: 'content://c'),
        throwsA(isA<RepairPasswordRequiredException>()),
      );
    });

    test('maps PASSWORD_INCORRECT to RepairIncorrectPasswordException', () async {
      nextError = PlatformException(code: 'PASSWORD_INCORRECT');
      await expectLater(
        () => api.restoreBackupHeaderUnmounted(uri: 'content://c', password: 'wrong'),
        throwsA(isA<RepairIncorrectPasswordException>()),
      );
    });

    test('maps UNSUPPORTED_FORMAT to RepairUnsupportedFormatException', () async {
      nextError = PlatformException(code: 'UNSUPPORTED_FORMAT');
      await expectLater(
        () => api.restoreBackupHeaderUnmounted(uri: 'content://c'),
        throwsA(isA<RepairUnsupportedFormatException>()),
      );
    });

    test('rethrows unmapped PlatformException codes as-is', () async {
      nextError = PlatformException(code: 'IO_ERROR');
      await expectLater(
        () => api.restoreBackupHeaderUnmounted(uri: 'content://c'),
        throwsA(isA<PlatformException>().having((e) => e.code, 'code', 'IO_ERROR')),
      );
    });
  });

  group('runMountedVolumeFilesystemCheck', () {
    test('sends volId and opId, returns success', () async {
      nextResult = true;
      final result = await api.runMountedVolumeFilesystemCheck(3, opId: 8);
      expect(calls.single.method, 'runMountedVolumeFilesystemCheck');
      expect(calls.single.arguments['volId'], 3);
      expect(calls.single.arguments['opId'], 8);
      expect(result, isTrue);
    });

    test('null result defaults to false', () async {
      nextResult = null;
      final result = await api.runMountedVolumeFilesystemCheck(3);
      expect(result, isFalse);
    });
  });

  group('pickFolderVaultForRepair', () {
    test('parses uri/displayName/looksLikeVault/format', () async {
      nextResult = <String, dynamic>{
        'uri': 'content://vault',
        'displayName': 'My Vault',
        'looksLikeVault': true,
        'format': 'cryfs',
      };
      final result = await api.pickFolderVaultForRepair();
      expect(calls.single.method, 'pickFolderVaultForRepair');
      expect(result, isNotNull);
      expect(result!.uri, 'content://vault');
      expect(result.looksLikeVault, isTrue);
      expect(result.format, 'cryfs');
    });

    test('returns null when the user cancels the folder picker', () async {
      nextResult = null;
      final result = await api.pickFolderVaultForRepair();
      expect(result, isNull);
    });

    test('swallows PlatformException to null rather than throwing', () async {
      nextError = PlatformException(code: 'PICK_FAILED');
      final result = await api.pickFolderVaultForRepair();
      expect(result, isNull);
    });
  });

  group('checkFolderVault', () {
    final target = const FolderVaultTarget(
      treeUri: 'content://vault',
      displayName: 'My Vault',
      format: 'cryptomator',
      mountedVolId: 4,
    );

    test('sends fields (including mountedVolId) and parses the report', () async {
      nextResult = <String, dynamic>{
        'format': 'cryptomator',
        'filesScanned': 42,
        'deepScanPerformed': true,
        'issues': <Object?>[
          {'severity': 2, 'path': '/foo', 'message': 'bad'},
        ],
      };

      final result = await api.checkFolderVault(target, password: 'pw', opId: 1);

      expect(calls.single.arguments['volId'], 4);
      expect(calls.single.arguments['password'], 'pw');
      expect(result.filesScanned, 42);
      expect(result.deepScanPerformed, isTrue);
      expect(result.healthy, isFalse);
      expect(result.issues.single.severity, FolderVaultIssueSeverity.critical);
    });

    test('throws FolderVaultInvalidException when native returns null', () async {
      nextResult = null;
      await expectLater(
        () => api.checkFolderVault(target),
        throwsA(isA<FolderVaultInvalidException>()),
      );
    });

    test('maps PASSWORD_INCORRECT to RepairIncorrectPasswordException, never PasswordRequired', () async {
      nextError = PlatformException(code: 'PASSWORD_INCORRECT');
      await expectLater(
        () => api.checkFolderVault(target, password: 'wrong'),
        throwsA(isA<RepairIncorrectPasswordException>()),
      );
    });
  });

  group('exportContainerHeader', () {
    test('sends uri/opId, parses format and bytes', () async {
      final bytes = Uint8List.fromList([1, 2, 3]);
      nextResult = <String, dynamic>{'format': 'luks2', 'bytes': bytes};

      final result = await api.exportContainerHeader('content://c', opId: 6);

      expect(calls.single.method, 'exportContainerHeader');
      expect(calls.single.arguments['uri'], 'content://c');
      expect(calls.single.arguments['opId'], 6);
      expect(result.format, 'luks2');
      expect(result.bytes, bytes);
    });

    test('throws HeaderBackupUnrecognizedFileException when native returns null', () async {
      nextResult = null;
      await expectLater(
        () => api.exportContainerHeader('content://c'),
        throwsA(isA<HeaderBackupUnrecognizedFileException>()),
      );
    });

    test('maps UNRECOGNIZED_FILE / UNSUPPORTED_FORMAT / HEADER_UNREADABLE', () async {
      nextError = PlatformException(code: 'UNRECOGNIZED_FILE');
      await expectLater(
        () => api.exportContainerHeader('content://c'),
        throwsA(isA<HeaderBackupUnrecognizedFileException>()),
      );

      nextError = PlatformException(code: 'UNSUPPORTED_FORMAT');
      await expectLater(
        () => api.exportContainerHeader('content://c'),
        throwsA(isA<RepairUnsupportedFormatException>()),
      );

      nextError = PlatformException(code: 'HEADER_UNREADABLE');
      await expectLater(
        () => api.exportContainerHeader('content://c'),
        throwsA(isA<HeaderBackupUnreadableException>()),
      );
    });
  });

  group('restoreContainerHeaderRegion', () {
    final bytes = Uint8List.fromList([9, 9, 9]);

    test('sends every field and returns success', () async {
      nextResult = true;
      final result = await api.restoreContainerHeaderRegion(
        uri: 'content://c',
        format: 'veracrypt',
        bytes: bytes,
        password: 'pw',
        pim: 2,
        cipherId: 1,
        hashId: 3,
        opId: 4,
      );
      expect(calls.single.method, 'restoreContainerHeaderRegion');
      expect(calls.single.arguments['format'], 'veracrypt');
      expect(calls.single.arguments['bytes'], bytes);
      expect(result, isTrue);
    });

    test('defaults pim to 0 and cipherId/hashId to 255 (auto-detect)', () async {
      nextResult = true;
      await api.restoreContainerHeaderRegion(uri: 'content://c', format: 'luks2', bytes: bytes);
      expect(calls.single.arguments['pim'], 0);
      expect(calls.single.arguments['cipherId'], 255);
      expect(calls.single.arguments['hashId'], 255);
    });

    test('maps every documented error code to its typed exception', () async {
      final cases = {
        'PASSWORD_REQUIRED': isA<RepairPasswordRequiredException>(),
        'PASSWORD_INCORRECT': isA<RepairIncorrectPasswordException>(),
        'BACKUP_INVALID': isA<HeaderBackupInvalidException>(),
        'SIZE_MISMATCH': isA<HeaderBackupSizeMismatchException>(),
        'UNSUPPORTED_FORMAT': isA<RepairUnsupportedFormatException>(),
      };
      for (final entry in cases.entries) {
        nextError = PlatformException(code: entry.key, message: 'native msg');
        await expectLater(
          api.restoreContainerHeaderRegion(uri: 'content://c', format: 'veracrypt', bytes: bytes),
          throwsA(entry.value),
          reason: 'code ${entry.key} should map to ${entry.value}',
        );
      }
    });

    test('BACKUP_INVALID carries the native message through', () async {
      nextError = PlatformException(code: 'BACKUP_INVALID', message: 'checksum mismatch');
      await expectLater(
        api.restoreContainerHeaderRegion(uri: 'content://c', format: 'veracrypt', bytes: bytes),
        throwsA(
          isA<HeaderBackupInvalidException>().having((e) => e.message, 'message', 'checksum mismatch'),
        ),
      );
    });
  });

  group('resolveFolderVaultConfigFile', () {
    test('sends uri/format, parses fileName/uri/exists', () async {
      nextResult = <String, dynamic>{
        'fileName': 'gocryptfs.conf',
        'uri': 'content://config',
        'exists': true,
      };
      final result = await api.resolveFolderVaultConfigFile(uri: 'content://vault', format: 'gocryptfs');
      expect(calls.single.method, 'resolveFolderVaultConfigFile');
      expect(result.fileName, 'gocryptfs.conf');
      expect(result.uri, 'content://config');
      expect(result.exists, isTrue);
    });

    test('missing config file still returns fileName with uri null and exists false', () async {
      nextResult = <String, dynamic>{'fileName': 'gocryptfs.conf'};
      final result = await api.resolveFolderVaultConfigFile(uri: 'content://vault', format: 'gocryptfs');
      expect(result.fileName, 'gocryptfs.conf');
      expect(result.uri, isNull);
      expect(result.exists, isFalse);
    });

    test('throws RepairUnsupportedFormatException when native returns null', () async {
      nextResult = null;
      await expectLater(
        () => api.resolveFolderVaultConfigFile(uri: 'content://vault', format: 'unknown'),
        throwsA(isA<RepairUnsupportedFormatException>()),
      );
    });
  });

  group('restoreFolderVaultConfig', () {
    final bytes = Uint8List.fromList([4, 5, 6]);

    test('sends uri/format/bytes and completes without error', () async {
      nextResult = null;
      await api.restoreFolderVaultConfig(uri: 'content://vault', format: 'cryfs', bytes: bytes);
      expect(calls.single.method, 'restoreFolderVaultConfig');
      expect(calls.single.arguments['format'], 'cryfs');
      expect(calls.single.arguments['bytes'], bytes);
    });

    test('maps BACKUP_INVALID / UNSUPPORTED_FORMAT, rethrows anything else', () async {
      nextError = PlatformException(code: 'BACKUP_INVALID', message: 'bad file');
      await expectLater(
        api.restoreFolderVaultConfig(uri: 'content://vault', format: 'cryfs', bytes: bytes),
        throwsA(isA<HeaderBackupInvalidException>()),
      );

      nextError = PlatformException(code: 'UNSUPPORTED_FORMAT');
      await expectLater(
        api.restoreFolderVaultConfig(uri: 'content://vault', format: 'cryfs', bytes: bytes),
        throwsA(isA<RepairUnsupportedFormatException>()),
      );

      nextError = PlatformException(code: 'IO_ERROR');
      await expectLater(
        api.restoreFolderVaultConfig(uri: 'content://vault', format: 'cryfs', bytes: bytes),
        throwsA(isA<PlatformException>().having((e) => e.code, 'code', 'IO_ERROR')),
      );
    });
  });
}
