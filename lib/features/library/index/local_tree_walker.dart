import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:path/path.dart' as p;
import 'package:vaultexplorer/core/utils/cancellation_token.dart';
import 'package:vaultexplorer/features/library/index/library_scanner.dart';

/// Folder names (lower case) that are skipped wherever they appear: they hold
/// no music anyone wants indexed, and can hold hundreds of thousands of files.
const Set<String> kLocalWalkSkippedAnywhere = {
  'node_modules',
  r'$recycle.bin',
  'system volume information',
  '__pycache__',
};

/// Folder names (lower case) skipped only directly under the container root:
/// the application data of a home folder, and Android's per-app folders.
const Set<String> kLocalWalkSkippedAtRoot = {'appdata', 'android'};

/// Finds the audio files under [startPaths] of a plain local folder tree
/// ([rootPath] is its real path; the paths handed in and out are relative to
/// it, `/`-separated).
///
/// The generic scanner lists one folder per engine call, and for local storage
/// each such call starts an isolate and stats every file and folder in it.
/// That is minutes for a home folder. This walks the whole tree in a single
/// background isolate and stats only the audio files, which is all the scanner
/// needs. [onProgress] is called now and then with the folders visited and
/// audio files found so far.
///
/// Returns null when the walk could not be started (the caller falls back to
/// listing folder by folder). If [token] is cancelled the isolate is stopped
/// and what had been found is not reported.
Future<LibraryWalkResult?> walkLocalAudioTree({
  required String rootPath,
  required List<String> startPaths,
  required bool Function(String fileName) isAudioFile,
  required CancellationToken token,
  required void Function(int foldersChecked, int audioFilesFound) onProgress,
  int maxDepth = 40,
  int maxFolders = 200000,
}) async {
  if (token.isCancelled) return null;
  final port = ReceivePort();
  final done = Completer<LibraryWalkResult?>();
  Isolate? isolate;
  Timer? cancelWatch;

  void finish(LibraryWalkResult? result) {
    if (done.isCompleted) return;
    cancelWatch?.cancel();
    port.close();
    isolate?.kill(priority: Isolate.immediate);
    done.complete(result);
  }

  port.listen((Object? message) {
    final m = message as List<Object?>;
    switch (m[0]) {
      case 'progress':
        onProgress(m[1] as int, m[2] as int);
      case 'done':
        final paths = (m[1] as List).cast<String>();
        final sizes = (m[2] as List).cast<int>();
        final mtimes = (m[3] as List).cast<int>();
        finish(
          LibraryWalkResult(
            files: [
              for (var i = 0; i < paths.length; i++)
                LibraryFoundFile(paths[i], sizes[i], mtimes[i]),
            ],
            foldersChecked: m[4] as int,
            listFailures: m[5] as int,
            limitReached: m[6] as bool,
          ),
        );
      default:
        finish(null);
    }
  });

  try {
    isolate = await Isolate.spawn(
      _walkMain,
      _WalkRequest(
        port.sendPort,
        rootPath,
        List<String>.of(startPaths),
        isAudioFile,
        maxDepth,
        maxFolders,
      ),
      onError: port.sendPort,
      debugName: 've-library-walk',
    );
  } catch (_) {
    // The isolate could not be started (or [isAudioFile] cannot be sent to
    // it): the scanner lists folder by folder instead.
    finish(null);
    return done.future;
  }
  cancelWatch = Timer.periodic(const Duration(milliseconds: 150), (_) {
    if (token.isCancelled) finish(null);
  });
  return done.future;
}

class _WalkRequest {
  final SendPort port;
  final String root;
  final List<String> startPaths;
  final bool Function(String) isAudio;
  final int maxDepth;
  final int maxFolders;

  const _WalkRequest(
    this.port,
    this.root,
    this.startPaths,
    this.isAudio,
    this.maxDepth,
    this.maxFolders,
  );
}

void _walkMain(_WalkRequest r) {
  final paths = <String>[];
  final sizes = <int>[];
  final mtimes = <int>[];
  final seen = <String>{};
  var folders = 0;
  var failures = 0;
  var limit = false;

  void walk(String rel, int depth) {
    if (depth > r.maxDepth || folders >= r.maxFolders) {
      limit = true;
      return;
    }
    final abs = rel.isEmpty ? r.root : p.join(r.root, rel);
    final List<FileSystemEntity> items;
    try {
      items = Directory(abs).listSync(followLinks: false);
    } catch (_) {
      failures++;
      folders++;
      return;
    }
    folders++;
    if (folders % 200 == 0) {
      r.port.send(<Object?>['progress', folders, paths.length]);
    }
    final subdirs = <String>[];
    for (final item in items) {
      final name = p.basename(item.path);
      if (name.isEmpty || name.startsWith('.')) continue;
      final relPath = rel.isEmpty ? name : '$rel/$name';
      if (item is Directory) {
        final lower = name.toLowerCase();
        if (kLocalWalkSkippedAnywhere.contains(lower)) continue;
        if (rel.isEmpty && kLocalWalkSkippedAtRoot.contains(lower)) continue;
        subdirs.add(relPath);
      } else if (item is File && r.isAudio(name)) {
        if (!seen.add(relPath)) continue;
        try {
          final stat = item.statSync();
          paths.add(relPath);
          sizes.add(stat.size);
          // The same value the folder listing reports, so tracks already in
          // the saved index still count as unchanged.
          mtimes.add(stat.modified.millisecondsSinceEpoch ~/ 1000);
        } catch (_) {
          failures++;
        }
      }
    }
    for (final s in subdirs) {
      walk(s, depth + 1);
    }
  }

  for (final start in r.startPaths) {
    walk(start, 0);
  }
  r.port.send(<Object?>[
    'done',
    paths,
    sizes,
    mtimes,
    folders,
    failures,
    limit,
  ]);
}
