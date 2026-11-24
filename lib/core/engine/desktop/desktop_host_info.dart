// Small host-level answers of the engine channel that need no engine: the app version, the size of a
// container file and the free space next to it, a raw storage path, and the settings/skin export and
// import files. Android answers these in Kotlin (PackageManager, ContentResolver, the document pickers);
// desktop answers them with `dart:io` and `file_selector`.
import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

/// The app version reported by `getAppVersion` on desktop (Android reads it from the package manager).
///
/// Must equal the version name in pubspec.yaml; test/core/engine/desktop/desktop_method_coverage_test.dart
/// fails when they drift, so bumping the version in pubspec.yaml means bumping it here too.
const String desktopAppVersion = '1.67.1';

/// Free bytes on the volume holding [path], or null when it cannot be determined. Best effort: a null
/// only means "unknown", and every caller treats it that way.
typedef FreeSpaceProbe = Future<int?> Function(String path);

/// Parses `df -Pk <path>` output (POSIX format, 1024-byte blocks) into available bytes.
///
/// The data row is matched from its numeric columns instead of by splitting on spaces, so a file system
/// or mount point name containing spaces cannot shift the columns.
int? parseDfAvailableBytes(String output) {
  final lines = output.trim().split('\n');
  if (lines.length < 2) return null;
  final row = RegExp(r'^(.*?)\s+(\d+)\s+(\d+)\s+(\d+)\s+(?:\d+%|-)\s+(.+)$').firstMatch(lines.last.trim());
  if (row == null) return null;
  final availableKiB = int.tryParse(row.group(4)!);
  return availableKiB == null ? null : availableKiB * 1024;
}

/// Parses the single number PowerShell prints for `(Get-PSDrive -Name X).Free`.
int? parseWindowsFreeBytes(String output) {
  final bytes = int.tryParse(output.trim());
  return bytes == null || bytes < 0 ? null : bytes;
}

/// Free space via the operating system's own tools. There is no portable Dart API for it, and spawning
/// the tool only happens on demand (the Expand tool's size screen), never in a hot path.
Future<int?> probeFreeBytes(String path) async {
  const limit = Duration(seconds: 5);
  try {
    if (Platform.isWindows) {
      final drive = RegExp(r'^([A-Za-z]):').firstMatch(path)?.group(1);
      if (drive == null) return null; // UNC and device paths: unknown
      final r = await Process.run(
        'powershell',
        ['-NoProfile', '-NonInteractive', '-Command', '(Get-PSDrive -Name $drive).Free'],
      ).timeout(limit);
      return r.exitCode == 0 ? parseWindowsFreeBytes('${r.stdout}') : null;
    }
    final r = await Process.run('df', ['-Pk', '--', path]).timeout(limit);
    return r.exitCode == 0 ? parseDfAvailableBytes('${r.stdout}') : null;
  } on Object {
    return null; // tool missing, timed out, or unreadable output
  }
}

/// `getContainerSizeInfo`: current size of the container file and the free space on the storage holding it.
/// On desktop the container "URI" is its filesystem path.
Future<Map<String, Object?>> desktopContainerSizeInfo(Object? uri, {FreeSpaceProbe freeSpace = probeFreeBytes}) async {
  if (uri is! String || uri.isEmpty) {
    throw PlatformException(code: 'INVALID_ARGS', message: 'uri is required');
  }
  final int size;
  try {
    size = await File(uri).length();
  } on FileSystemException catch (e) {
    throw PlatformException(code: 'IO_ERROR', message: e.message);
  }
  return {'sizeBytes': size, 'freeBytes': await freeSpace(p.dirname(uri))};
}

/// `resolveRawStoragePath`: Android turns document/tree URIs into a path; a desktop location already is one.
String? desktopRawStoragePath(Object? uri) {
  if (uri is! String || uri.isEmpty) return null;
  if (p.isAbsolute(uri)) return uri;
  if (uri.startsWith('file:')) {
    try {
      return Uri.parse(uri).toFilePath();
    } on UnsupportedError {
      return null;
    }
  }
  return null;
}

const XTypeGroup _jsonFiles = XTypeGroup(label: 'JSON', extensions: ['json'], mimeTypes: ['application/json']);

/// `exportAppSettingsFile`: a "save as" dialog, then the settings/skin bundle written to the chosen file.
/// False when the dialog was cancelled or the write failed (the same contract as Android).
Future<bool> desktopExportSettingsFile(Object? contents, Object? fileName) async {
  if (contents is! String || fileName is! String) {
    throw PlatformException(code: 'INVALID_ARGS', message: 'contents and fileName required');
  }
  final location = await getSaveLocation(suggestedName: fileName, acceptedTypeGroups: const [_jsonFiles]);
  if (location == null) return false;
  try {
    await File(location.path).writeAsBytes(utf8.encode(contents), flush: true);
    return true;
  } on FileSystemException {
    return false;
  }
}

/// `importAppSettingsFile`: an "open" dialog, then the file's text. Null when the dialog was cancelled.
Future<String?> desktopImportSettingsFile() async {
  final file = await openFile(acceptedTypeGroups: const [_jsonFiles]);
  if (file == null) return null;
  try {
    return utf8.decode(await file.readAsBytes());
  } on FileSystemException catch (e) {
    throw PlatformException(code: 'IO_ERROR', message: e.message);
  } on FormatException {
    // Not UTF-8 text: let the caller's "not a valid settings export" path report it.
    return '';
  }
}
