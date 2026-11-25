import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:vaultexplorer/core/engine/desktop/desktop_staging_manager.dart';

void main() {
  late Directory tempRoot;

  setUp(() async {
    tempRoot = await Directory.systemTemp.createTemp('ve_staging_mgr_test_');
  });

  tearDown(() async {
    if (await tempRoot.exists()) {
      await tempRoot.delete(recursive: true);
    }
  });

  test('createBatch allocates empty locked batch and calls hardener', () async {
    final hardenedPaths = <String>[];
    final mgr = DesktopStagingManager(
      baseDirOverride: tempRoot,
      hardenDir: (dir) async => hardenedPaths.add(dir),
      pidOverride: 4242,
    );

    final batch = await mgr.createBatch(volId: 3, isClipboard: false);
    expect(await Directory(batch.dirPath).exists(), isTrue);
    expect(hardenedPaths, [batch.dirPath]);
    final lockFile = File(p.join(batch.dirPath, DesktopStagingManager.lockFileName));
    expect(await lockFile.exists(), isTrue);

    // Only batch.lock exists; zero payload files were decrypted upfront.
    final entries = await Directory(batch.dirPath).list().toList();
    expect(entries.length, 1);
    expect(p.basename(entries.single.path), DesktopStagingManager.lockFileName);

    await mgr.cleanupAll();
    expect(await Directory(batch.dirPath).exists(), isFalse);
  });

  test('onDragTransferFinished wipes unrealized batch immediately', () async {
    final cancelledIds = <String>[];
    final mgr = DesktopStagingManager(
      baseDirOverride: tempRoot,
      cancelNativeBatch: (id) async => cancelledIds.add(id),
      pidOverride: 1001,
    );

    final batch = await mgr.createBatch(volId: 1, isClipboard: false);
    expect(await Directory(batch.dirPath).exists(), isTrue);

    await mgr.onDragTransferFinished(batch.batchId, immediateIfUnused: true);
    expect(cancelledIds, [batch.batchId]);
    expect(await Directory(batch.dirPath).exists(), isFalse);
    expect(mgr.activeBatches, isEmpty);
  });

  test('realized batch waits while external reader holds file open', () async {
    var inUse = true;
    var probeCalls = 0;
    final mgr = DesktopStagingManager(
      baseDirOverride: tempRoot,
      isBatchInUse: (_) async {
        probeCalls++;
        return inUse;
      },
      defaultGracePeriod: const Duration(milliseconds: 20),
      drainPollInterval: const Duration(milliseconds: 20),
      pidOverride: 2002,
    );

    final batch = await mgr.createBatch(volId: 2, isClipboard: false);
    final payload = File(p.join(batch.dirPath, 'secret.txt'));
    await payload.writeAsString('top secret');
    mgr.markRealized(batch.batchId, isDrag: true);

    await mgr.onDragTransferFinished(batch.batchId, immediateIfUnused: true);
    // Still in use -> directory survives immediate cleanup check.
    expect(await Directory(batch.dirPath).exists(), isTrue);
    expect(probeCalls, greaterThanOrEqualTo(1));

    inUse = false;
    await Future<void>.delayed(const Duration(milliseconds: 90));
    expect(await Directory(batch.dirPath).exists(), isFalse);
  });

  test('purgeStaleAtStartup deletes unlocked orphans and skips locked sibling', () async {
    final orphan = Directory(p.join(tempRoot.path, '${DesktopStagingManager.batchDirPrefix}999_1'));
    await orphan.create(recursive: true);
    await File(p.join(orphan.path, 'leaked.bin')).writeAsBytes([1, 2, 3, 4]);
    await File(p.join(orphan.path, DesktopStagingManager.lockFileName)).writeAsString('999\n');

    final activeSibling = Directory(
      p.join(tempRoot.path, '${DesktopStagingManager.batchDirPrefix}888_1'),
    );
    await activeSibling.create(recursive: true);
    final siblingFile = File(p.join(activeSibling.path, 'in_flight.bin'));
    await siblingFile.writeAsBytes([9, 8, 7]);
    final siblingLock = await File(
      p.join(activeSibling.path, DesktopStagingManager.lockFileName),
    ).open(mode: FileMode.write);
    await siblingLock.lock(FileLock.exclusive);

    try {
      final mgr = DesktopStagingManager(baseDirOverride: tempRoot, pidOverride: 777);
      final purged = await mgr.purgeStaleAtStartup();

      expect(purged, 1);
      expect(await orphan.exists(), isFalse);
      expect(await activeSibling.exists(), isTrue);
      expect(await siblingFile.exists(), isTrue);
    } finally {
      await siblingLock.unlock();
      await siblingLock.close();
    }
  });

  test('cleanupVolume wipes only matching volId batches', () async {
    final released = <String>[];
    final mgr = DesktopStagingManager(
      baseDirOverride: tempRoot,
      releaseClipboardBatch: (id) async => released.add(id),
      pidOverride: 3003,
    );

    final b1 = await mgr.createBatch(volId: 10, isClipboard: true);
    final b2 = await mgr.createBatch(volId: 20, isClipboard: true);

    await mgr.cleanupVolume(10);

    expect(released, [b1.batchId]);
    expect(await Directory(b1.dirPath).exists(), isFalse);
    expect(await Directory(b2.dirPath).exists(), isTrue);

    await mgr.cleanupAll();
    expect(await Directory(b2.dirPath).exists(), isFalse);
  });
}
