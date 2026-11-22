// The computer's drives, for the "Local storage" section of the drawer.
//
// Android answers `getStorageVolumes` with the SD cards / USB drives StorageManager knows about, and the
// app lists each one as its own browsable location (see ExternalStorageLocationsNotifier). Desktop has
// no StorageManager, so this builds the same answer from what the OS exposes:
//   * Linux:   /proc/self/mounts (real block devices and network mounts), labelled from
//              /dev/disk/by-label, plus the root file system;
//   * Windows: every drive letter the system reports (kernel32), with its volume label;
//   * macOS:   the entries of /Volumes.
// Total and free space come from `df` on Linux/macOS and from GetDiskFreeSpaceExW on Windows.
//
// Each volume is a map with the keys the Dart side reads: id, isPrimary, isRemovable, state, path and
// description, plus totalBytes / freeBytes when the size is known. `isRemovable` is only the flag that lets a volume through the app's filter ("add every
// mounted drive that is not the built-in local storage"); on desktop it does not mean hot-pluggable.
import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

class DesktopStorage {
  const DesktopStorage();

  Future<List<Map<String, Object?>>> volumes() async {
    try {
      if (Platform.isLinux) return await _withSizes(await _linuxVolumes());
      // Off the UI isolate: asking about an unreachable network drive can block for several seconds.
      if (Platform.isWindows) return await Isolate.run(_windowsVolumesSync);
      if (Platform.isMacOS) return await _withSizes(_macVolumes());
    } catch (e) {
      debugPrint('[desktop-engine] could not list drives: $e');
    }
    return const [];
  }

  static Map<String, Object?> _volume(String path, String description) => {
    'id': path,
    'isPrimary': false,
    'isRemovable': true,
    'state': 'mounted',
    'path': path,
    'description': description,
  };

  // ── sizes (Linux, macOS) ────────────────────────────────────────────────

  /// Adds `totalBytes` / `freeBytes` to each volume using `df`. Only the listed mount points are asked
  /// about, so an unrelated hung mount cannot stall it; if `df` is missing or too slow the volumes are
  /// returned as they were, just without sizes.
  Future<List<Map<String, Object?>>> _withSizes(List<Map<String, Object?>> volumes) async {
    if (volumes.isEmpty) return volumes;
    final out = await _run('df', ['-Pk', '--', for (final v in volumes) v['path']! as String]);
    return out == null ? volumes : withDfSizes(volumes, out);
  }

  static Future<String?> _run(String exe, List<String> args) async {
    try {
      final proc = await Process.start(exe, args);
      final stdout = proc.stdout.transform(utf8.decoder).join();
      unawaited(proc.stderr.drain<void>());
      final code = await proc.exitCode.timeout(
        const Duration(seconds: 4),
        onTimeout: () {
          proc.kill();
          return -1;
        },
      );
      // df exits non-zero when it could not read one of the mounts but still prints the others.
      return code == -1 ? null : await stdout;
    } catch (_) {
      return null;
    }
  }

  /// `df -Pk` lines: `Filesystem 1024-blocks Used Available Capacity Mounted-on`. The file system and the
  /// mount point may both contain spaces, so only the four numbers in the middle are anchored.
  static final RegExp _dfLine = RegExp(r'^(.*?)\s+(\d+)\s+(\d+)\s+(\d+)\s+\d+%\s+(/.*)$');

  /// [volumes] with `totalBytes` / `freeBytes` filled in from the output of `df -Pk`. Public for tests.
  @visibleForTesting
  static List<Map<String, Object?>> withDfSizes(List<Map<String, Object?>> volumes, String dfOutput) {
    final sizes = <String, ({int total, int free})>{};
    for (final line in const LineSplitter().convert(dfOutput)) {
      final m = _dfLine.firstMatch(line);
      if (m == null) continue;
      sizes[m[5]!] = (total: int.parse(m[2]!) * 1024, free: int.parse(m[4]!) * 1024);
    }
    return [
      for (final v in volumes)
        if (sizes[v['path']] case final size?)
          {...v, 'totalBytes': size.total, 'freeBytes': size.free}
        else
          v,
    ];
  }

  // ── Linux ───────────────────────────────────────────────────────────────

  Future<List<Map<String, Object?>>> _linuxVolumes() async {
    // openRead: /proc files report a length of 0, which readAsString can trip over.
    final mounts = await File('/proc/self/mounts').openRead().transform(utf8.decoder).join();
    return linuxVolumesFromMounts(mounts, _linuxLabels());
  }

  /// Device node -> file system label (from /dev/disk/by-label), e.g. `/dev/sdb1` -> `BACKUP`.
  Map<String, String> _linuxLabels() {
    final labels = <String, String>{};
    try {
      final dir = Directory('/dev/disk/by-label');
      if (!dir.existsSync()) return labels;
      for (final entry in dir.listSync(followLinks: false)) {
        if (entry is! Link) continue;
        final device = entry.resolveSymbolicLinksSync();
        labels[device] = _unescapeLabel(p.basename(entry.path));
      }
    } catch (_) {
      // Labels are a nicety; fall back to the mount point's name.
    }
    return labels;
  }

  /// /dev/disk/by-label escapes unusual characters as `\xNN` (a space is `\x20`).
  static String _unescapeLabel(String raw) => raw.replaceAllMapped(
    RegExp(r'\\x([0-9a-fA-F]{2})'),
    (m) => String.fromCharCode(int.parse(m[1]!, radix: 16)),
  );

  /// /proc/self/mounts escapes space, tab, newline and backslash as three-digit octal (`\040`).
  static String _unescapeMountField(String raw) => raw.replaceAllMapped(
    RegExp(r'\\([0-7]{3})'),
    (m) => String.fromCharCode(int.parse(m[1]!, radix: 8)),
  );

  static const _hiddenFileSystems = {
    'tmpfs', 'devtmpfs', 'proc', 'sysfs', 'cgroup', 'cgroup2', 'overlay', 'squashfs', 'devpts', 'securityfs',
    'debugfs', 'tracefs', 'configfs', 'fusectl', 'pstore', 'bpf', 'mqueue', 'hugetlbfs', 'autofs',
    'binfmt_misc', 'efivarfs', 'ramfs', 'nsfs', 'rpc_pipefs', 'fuse.portal', 'fuse.gvfsd-fuse',
  };

  static const _networkFileSystems = {'cifs', 'smb3', 'nfs', 'nfs4', 'fuse.sshfs', 'fuse.rclone', 'davfs'};

  /// Mount points that belong to the operating system itself rather than being a place the person
  /// keeps files. `/home` is left out because the home folder is what "Local storage" already opens.
  static const _systemMountPrefixes = [
    '/boot', '/efi', '/home', '/var', '/usr', '/etc', '/snap', '/sys', '/proc', '/dev', '/tmp',
    '/run/user', '/run/snapd', '/run/lock', '/run/credentials',
  ];

  static const _userMountPrefixes = ['/media/', '/run/media/', '/mnt/'];

  /// The drives in a `/proc/self/mounts` listing, in the order they appear, with the root file
  /// system first. [labels] maps a device node to its file system label. Public for tests.
  @visibleForTesting
  static List<Map<String, Object?>> linuxVolumesFromMounts(String mounts, Map<String, String> labels) {
    final out = <Map<String, Object?>>[_volume('/', 'File system')];
    final seen = <String>{'/'};
    String? rootDevice;

    for (final line in const LineSplitter().convert(mounts)) {
      final f = line.split(' ');
      if (f.length < 3) continue;
      if (_unescapeMountField(f[1]) == '/') rootDevice ??= _unescapeMountField(f[0]);
    }

    for (final line in const LineSplitter().convert(mounts)) {
      final f = line.split(' ');
      if (f.length < 3) continue;
      final source = _unescapeMountField(f[0]);
      final mountPoint = _unescapeMountField(f[1]);
      final fsType = f[2];

      if (mountPoint == '/' || !seen.add(mountPoint)) continue;
      if (_hiddenFileSystems.contains(fsType)) continue;
      final isNetwork = _networkFileSystems.contains(fsType);
      final isDevice = source.startsWith('/dev/') && !source.startsWith('/dev/loop');
      if (!isNetwork && !isDevice) continue;

      final underUserPrefix = _userMountPrefixes.any(mountPoint.startsWith);
      if (!underUserPrefix && _systemMountPrefixes.any((s) => mountPoint == s || mountPoint.startsWith('$s/'))) {
        continue;
      }
      // Another mount of the device the system is installed on (sub-volumes, bind mounts) is not a
      // separate drive, unless it sits where drives are mounted.
      if (!underUserPrefix && isDevice && source == rootDevice) continue;

      final label = labels[source];
      final name = (label != null && label.isNotEmpty)
          ? label
          : (p.basename(mountPoint).isNotEmpty ? p.basename(mountPoint) : mountPoint);
      out.add(_volume(mountPoint, name));
    }
    return out;
  }

  // ── macOS ───────────────────────────────────────────────────────────────

  List<Map<String, Object?>> _macVolumes() {
    final dir = Directory('/Volumes');
    if (!dir.existsSync()) return const [];
    return [
      for (final entry in dir.listSync(followLinks: false))
        if (!p.basename(entry.path).startsWith('.')) _volume(entry.path, p.basename(entry.path)),
    ];
  }
}

// ── Windows ───────────────────────────────────────────────────────────────

typedef _GetLogicalDrivesC = Uint32 Function();
typedef _GetLogicalDrivesD = int Function();
typedef _GetDriveTypeC = Uint32 Function(Pointer<Utf16>);
typedef _GetDriveTypeD = int Function(Pointer<Utf16>);
typedef _GetVolumeInformationC =
    Int32 Function(
      Pointer<Utf16>,
      Pointer<Utf16>,
      Uint32,
      Pointer<Uint32>,
      Pointer<Uint32>,
      Pointer<Uint32>,
      Pointer<Utf16>,
      Uint32,
    );
typedef _GetVolumeInformationD =
    int Function(
      Pointer<Utf16>,
      Pointer<Utf16>,
      int,
      Pointer<Uint32>,
      Pointer<Uint32>,
      Pointer<Uint32>,
      Pointer<Utf16>,
      int,
    );
typedef _GetDiskFreeSpaceExC =
    Int32 Function(Pointer<Utf16>, Pointer<Uint64>, Pointer<Uint64>, Pointer<Uint64>);
typedef _GetDiskFreeSpaceExD =
    int Function(Pointer<Utf16>, Pointer<Uint64>, Pointer<Uint64>, Pointer<Uint64>);
typedef _SetErrorModeC = Uint32 Function(Uint32);
typedef _SetErrorModeD = int Function(int);

/// Every drive letter with its label and sizes, as `"D: SSD Space"` (just `"C:"` when it has no label).
/// Runs in its own isolate (see [DesktopStorage.volumes]).
List<Map<String, Object?>> _windowsVolumesSync() {
  const maxPath = 261; // MAX_PATH + 1: the longest a volume label can be, in UTF-16 units
  const driveRemote = 4;
  final k32 = DynamicLibrary.open('kernel32.dll');
  final getLogicalDrives = k32.lookupFunction<_GetLogicalDrivesC, _GetLogicalDrivesD>('GetLogicalDrives');
  final getDriveType = k32.lookupFunction<_GetDriveTypeC, _GetDriveTypeD>('GetDriveTypeW');
  final getVolumeInformation = k32.lookupFunction<_GetVolumeInformationC, _GetVolumeInformationD>(
    'GetVolumeInformationW',
  );
  final getDiskFreeSpaceEx = k32.lookupFunction<_GetDiskFreeSpaceExC, _GetDiskFreeSpaceExD>(
    'GetDiskFreeSpaceExW',
  );
  final setErrorMode = k32.lookupFunction<_SetErrorModeC, _SetErrorModeD>('SetErrorMode');

  // SEM_FAILCRITICALERRORS: an empty card reader answers "no" instead of showing a "no disk" dialog.
  setErrorMode(0x0001);

  final labelBuffer = calloc<Uint16>(maxPath);
  final labelPtr = labelBuffer.cast<Utf16>();
  final freeToCaller = calloc<Uint64>();
  final total = calloc<Uint64>();
  final totalFree = calloc<Uint64>();
  final out = <Map<String, Object?>>[];
  try {
    final mask = getLogicalDrives();
    for (var i = 0; i < 26; i++) {
      if (mask & (1 << i) == 0) continue;
      final letter = String.fromCharCode(0x41 + i);
      final root = '$letter:\\';
      final rootPtr = root.toNativeUtf16(allocator: calloc);
      try {
        final type = getDriveType(rootPtr);
        if (type < 2) continue; // 0 = unknown, 1 = no such root

        var label = '';
        labelBuffer.value = 0;
        if (getVolumeInformation(rootPtr, labelPtr, maxPath, nullptr, nullptr, nullptr, nullptr, 0) != 0) {
          label = labelPtr.toDartString().trim();
        }
        final hasSize = getDiskFreeSpaceEx(rootPtr, freeToCaller, total, totalFree) != 0;
        // A drive with nothing in it (empty card reader or disc drive) is not worth listing; a network
        // drive that is currently unreachable still is, as in Explorer.
        if (!hasSize && type != driveRemote) continue;

        out.add({
          'id': root,
          'isPrimary': false,
          'isRemovable': true,
          'state': 'mounted',
          'path': root,
          'description': label.isEmpty ? '$letter:' : '$letter: $label',
          'label': label,
          if (hasSize) 'totalBytes': total.value,
          if (hasSize) 'freeBytes': freeToCaller.value,
        });
      } finally {
        calloc.free(rootPtr);
      }
    }
  } finally {
    calloc.free(labelBuffer);
    calloc.free(freeToCaller);
    calloc.free(total);
    calloc.free(totalFree);
  }
  return out;
}
