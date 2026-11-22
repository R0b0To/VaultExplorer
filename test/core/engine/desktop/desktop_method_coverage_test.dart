import 'dart:io';

import 'package:test/test.dart';
import 'package:vaultexplorer/core/engine/desktop/desktop_host_info.dart';
import 'package:vaultexplorer/core/engine/desktop/desktop_method_support.dart';

// Keeps the desktop engine host honest. `ChannelMethods` is the contract Android answers in Kotlin; the
// desktop host answers the same names (desktop_engine_host.dart + desktop_crypto.dart), plus a table of
// harmless Android-only defaults. Everything else answers null, and desktop_method_support.dart says, per
// method, whether that is permanent (Android-only) or planned (pending). This test fails when:
//
//   * a method is added to `ChannelMethods` and put nowhere (nobody decided what desktop does with it),
//   * a method is implemented but still listed as unsupported (the lists would rot), or
//   * a listed method no longer exists.
//
// It reads the sources as text because the host cannot be built without the native engine library.

const _registryFile = 'lib/data/services/vault_engine/channel_methods.dart';
const _hostFile = 'lib/core/engine/desktop/desktop_engine_host.dart';
const _cryptoFile = 'lib/core/engine/desktop/desktop_crypto.dart';

String _read(String path) => File(path).readAsStringSync();

/// Wire name of every method in `ChannelMethods`, and the identifier -> wire name map used to resolve
/// `case ChannelMethods.<identifier>:` in the host.
({Set<String> wire, Map<String, String> byIdentifier}) _registry() {
  final byIdentifier = <String, String>{};
  for (final m in RegExp(r"static const (?:String )?(\w+)\s*=\s*'(\w+)'").allMatches(_read(_registryFile))) {
    byIdentifier[m.group(1)!] = m.group(2)!;
  }
  return (wire: byIdentifier.values.toSet(), byIdentifier: byIdentifier);
}

Set<String> _hostCases(Map<String, String> byIdentifier) {
  final unknown = <String>[];
  final wire = <String>{};
  for (final m in RegExp(r'case ChannelMethods\.(\w+):').allMatches(_read(_hostFile))) {
    final name = byIdentifier[m.group(1)!];
    if (name == null) {
      unknown.add(m.group(1)!);
    } else {
      wire.add(name);
    }
  }
  expect(unknown, isEmpty, reason: 'the host switches on ChannelMethods constants that do not exist');
  return wire;
}

Set<String> _cryptoCases() => {
      for (final m in RegExp(r"case '(\w+)':").allMatches(_read(_cryptoFile))) m.group(1)!,
    };

Set<String> _androidOnlyDefaults() {
  final body = RegExp(r'_androidOnlyDefaults = \{(.*?)\n  \};', dotAll: true).firstMatch(_read(_hostFile));
  expect(body, isNotNull, reason: '_androidOnlyDefaults table not found in the host');
  return {for (final m in RegExp(r"'(\w+)':").allMatches(body!.group(1)!)) m.group(1)!};
}

void main() {
  late final Set<String> registry;
  late final Set<String> handled;
  late final Set<String> defaults;

  setUpAll(() {
    final r = _registry();
    registry = r.wire;
    handled = {..._hostCases(r.byIdentifier), ..._cryptoCases()};
    defaults = _androidOnlyDefaults();
  });

  group('desktop method coverage', () {
    test('the registry was read (guards the text scan itself)', () {
      expect(registry.length, greaterThan(200));
      expect(handled.length, greaterThan(80));
      expect(defaults, isNotEmpty);
      expect(registry, containsAll(handled));
      expect(registry, containsAll(defaults));
    });

    test('every engine-channel method is answered, defaulted, or explicitly unsupported', () {
      final classified = {...handled, ...defaults, ...desktopAndroidOnlyMethods, ...desktopPendingMethods};
      final missing = registry.difference(classified).toList()..sort();
      expect(
        missing,
        isEmpty,
        reason: 'These ChannelMethods are not handled by the desktop host and are in neither '
            'desktopAndroidOnlyMethods nor desktopPendingMethods (desktop_method_support.dart). '
            'Implement them in DesktopEngineHost, or say why desktop does not.',
      );
    });

    test('the two unsupported sets do not overlap', () {
      expect(desktopAndroidOnlyMethods.intersection(desktopPendingMethods), isEmpty);
    });

    test('a method that is answered is not also listed as unsupported', () {
      final answered = {...handled, ...defaults};
      final stale = [
        ...desktopAndroidOnlyMethods.intersection(answered),
        ...desktopPendingMethods.intersection(answered),
      ]..sort();
      expect(stale, isEmpty, reason: 'Implemented on desktop: remove it from desktop_method_support.dart.');
    });

    test('every listed method still exists in ChannelMethods', () {
      final gone = [
        ...desktopAndroidOnlyMethods.difference(registry),
        ...desktopPendingMethods.difference(registry),
      ]..sort();
      expect(gone, isEmpty, reason: 'Listed in desktop_method_support.dart but not in ChannelMethods.');
    });

    test('the Phase 0 methods are really answered on desktop', () {
      const phase0 = [
        'getAppVersion',
        'getContainerSizeInfo',
        'resolveRawStoragePath',
        'exportAppSettingsFile',
        'importAppSettingsFile',
        'writeBackFile',
        'setSensitiveClipboardText',
        'clearSensitiveClipboardText',
        'setKeepScreenOn',
      ];
      final answered = {...handled, ...defaults};
      expect(phase0.where((m) => !answered.contains(m)), isEmpty);
    });

    test('the Phase 1a browsing and extraction methods are really answered on desktop', () {
      const archives = [
        'archiveScanVault',
        'archiveScanLocal',
        'archiveExtractVaultEntry',
        'archiveExtractLocalEntry',
        'archiveExtractVaultAll',
        'archiveStageBrowseEntry',
        'archiveDiscardBrowseFile',
        'pickArchiveFile',
        'pickExtractFolder',
      ];
      expect(archives.where((m) => !handled.contains(m)), isEmpty);
    });

    test('summary', () {
      final answered = {...handled, ...defaults};
      final line = 'desktop coverage: ${registry.length} methods, ${handled.length} handled, '
          '${defaults.difference(handled).length} defaulted, ${desktopAndroidOnlyMethods.length} Android-only, '
          '${desktopPendingMethods.length} pending (${answered.length} answered in total)';
      printOnFailure(line);
      expect(
        handled.length + defaults.difference(handled).length + desktopAndroidOnlyMethods.length + desktopPendingMethods.length,
        registry.length,
        reason: line,
      );
    });
  });

  group('desktop app version', () {
    test('desktopAppVersion matches the version name in pubspec.yaml', () {
      final match = RegExp(r'^version:\s*([^+\s]+)', multiLine: true).firstMatch(_read('pubspec.yaml'));
      expect(match, isNotNull);
      expect(desktopAppVersion, match!.group(1), reason: 'Bump desktopAppVersion in desktop_host_info.dart too.');
    });
  });

  group('free-space parsing', () {
    test('df -Pk output', () {
      const out = 'Filesystem     1024-blocks      Used Available Capacity Mounted on\n'
          '/dev/nvme0n1p2   244529656 118392140 113645600      51% /\n';
      expect(parseDfAvailableBytes(out), 113645600 * 1024);
    });

    test('a file system or mount point containing spaces does not shift the columns', () {
      const out = 'Filesystem     1024-blocks Used Available Capacity Mounted on\n'
          'My Disk 2        1000   400       600      40% /media/me/My Disk 2\n';
      expect(parseDfAvailableBytes(out), 600 * 1024);
    });

    test('a pseudo file system with no capacity percentage', () {
      const out = 'Filesystem 1024-blocks Used Available Capacity Mounted on\n'
          'none                0    0         0        - /mnt/x\n';
      expect(parseDfAvailableBytes(out), 0);
    });

    test('garbage and short output are unknown, not zero', () {
      expect(parseDfAvailableBytes(''), isNull);
      expect(parseDfAvailableBytes('df: /nope: No such file or directory'), isNull);
      expect(parseDfAvailableBytes('Filesystem 1024-blocks Used Available Capacity Mounted on\n'), isNull);
    });

    test('PowerShell free-space output', () {
      expect(parseWindowsFreeBytes('123456789\r\n'), 123456789);
      expect(parseWindowsFreeBytes(''), isNull);
      expect(parseWindowsFreeBytes('Get-PSDrive : Cannot find drive.'), isNull);
    });
  });

  group('container size info', () {
    late Directory tmp;
    setUp(() => tmp = Directory.systemTemp.createTempSync('ve_size_info_'));
    tearDown(() => tmp.deleteSync(recursive: true));

    test('reports the file size and asks for free space next to the file', () async {
      final f = File('${tmp.path}/vault.hc')..writeAsBytesSync(List<int>.filled(4096, 7));
      String? probed;
      final info = await desktopContainerSizeInfo(f.path, freeSpace: (path) async {
        probed = path;
        return 12345;
      });
      expect(info, {'sizeBytes': 4096, 'freeBytes': 12345});
      expect(probed, tmp.path);
    });

    test('free space is optional', () async {
      final f = File('${tmp.path}/vault.hc')..writeAsBytesSync([1, 2, 3]);
      final info = await desktopContainerSizeInfo(f.path, freeSpace: (_) async => null);
      expect(info['sizeBytes'], 3);
      expect(info['freeBytes'], isNull);
    });

    test('a missing file and a missing argument are errors, as on Android', () async {
      await expectLater(
        desktopContainerSizeInfo('${tmp.path}/nope.hc', freeSpace: (_) async => null),
        throwsA(isA<Exception>().having((e) => '$e', 'text', contains('IO_ERROR'))),
      );
      await expectLater(
        desktopContainerSizeInfo(null),
        throwsA(isA<Exception>().having((e) => '$e', 'text', contains('INVALID_ARGS'))),
      );
    });
  });

  group('raw storage path', () {
    test('an absolute path is its own raw path', () {
      expect(desktopRawStoragePath('/home/me/vault.hc'), '/home/me/vault.hc');
    });

    test('a file:// URI resolves to a path', () {
      expect(desktopRawStoragePath(Uri.file('/home/me/vault.hc').toString()), '/home/me/vault.hc');
    }, skip: Platform.isWindows ? 'POSIX path form' : false);

    test('anything else is unknown', () {
      expect(desktopRawStoragePath('content://com.android.providers/tree/primary%3AVaults'), isNull);
      expect(desktopRawStoragePath(''), isNull);
      expect(desktopRawStoragePath(null), isNull);
    });
  });
}
