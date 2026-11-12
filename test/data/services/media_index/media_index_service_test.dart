import 'dart:async';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/data/services/media_index/media_index.dart';
import 'package:vaultexplorer/data/services/media_index/media_index_codec.dart';
import 'package:vaultexplorer/data/services/media_index/media_index_service.dart';

MountedContainer _c(String uri) => MountedContainer(
  uri: uri,
  displayName: uri,
  volId: 1,
  rootFiles: const [],
  mountedAt: DateTime(2026),
  totalSpace: 0,
  freeSpace: 0,
);

class _FakeStorage implements MediaIndexStorage {
  Uint8List? stored;
  bool throwOnRead = false;
  bool failWrites = false;
  int reads = 0;
  int writes = 0;
  Completer<void>? holdReads;

  @override
  Future<Uint8List?> read(MountedContainer container) async {
    reads++;
    await holdReads?.future;
    if (throwOnRead) throw StateError('cannot read');
    return stored;
  }

  @override
  Future<bool> write(MountedContainer container, Uint8List bytes) async {
    writes++;
    if (failWrites) return false;
    stored = bytes;
    return true;
  }
}

Uint8List _indexWith(Map<int, (int, int, int, int)> entries) {
  final index = MediaIndex();
  entries.forEach((hash, e) => index.record(hash, e.$1, e.$2, e.$3, e.$4));
  return MediaIndexCodec.encode(index.compact());
}

Future<void> main() async {
  final vault = _c('content://vault/a');

  MediaIndexService make(_FakeStorage storage, {List<String>? warnings}) =>
      MediaIndexService(
        storage: storage,
        flushDelay: const Duration(milliseconds: 15),
        maxFlushWait: const Duration(milliseconds: 80),
        onWarning: (m, e) => warnings?.add(m),
      );

  test('loads the stored index and validates entries against size and mtime', () async {
    final storage = _FakeStorage()
      ..stored = _indexWith({11: (500, 100, 4000, 3000)});
    final service = make(storage);
    expect(service.isReady(vault), isFalse);
    await service.attach(vault, MediaIndexAccess.readWrite);
    expect(service.isReady(vault), isTrue);
    final hit = service.lookup(vault, 11, 500, 100);
    expect(MediaIndex.widthOf(hit), 4000);
    expect(service.lookup(vault, 11, 501, 100), 0);
    expect(service.lookup(vault, 11, 500, 101), 0);
    service.dispose();
  });

  test('concurrent attaches share one read', () async {
    final storage = _FakeStorage()..holdReads = Completer<void>();
    final service = make(storage);
    final a = service.attach(vault, MediaIndexAccess.readWrite);
    final b = service.attach(vault, MediaIndexAccess.readWrite);
    storage.holdReads!.complete();
    await Future.wait([a, b]);
    expect(storage.reads, 1);
    service.dispose();
  });

  test('new measurements are saved in the background and survive a restart', () async {
    final storage = _FakeStorage();
    final service = make(storage);
    await service.attach(vault, MediaIndexAccess.readWrite);
    service.record(vault, 1, 10, 20, 640, 480);
    service.record(vault, 2, 11, 21, 480, 640);
    expect(storage.writes, 0, reason: 'batched, not per record');
    await Future<void>.delayed(const Duration(milliseconds: 80));
    expect(storage.writes, 1);

    // "Restart": a new service reads what was written.
    final again = make(storage);
    await again.attach(vault, MediaIndexAccess.readWrite);
    expect(MediaIndex.widthOf(again.lookup(vault, 1, 10, 20)), 640);
    expect(MediaIndex.heightOf(again.lookup(vault, 2, 11, 21)), 640);
    service.dispose();
    again.dispose();
  });

  test('recording what is already known does not rewrite the file', () async {
    final storage = _FakeStorage();
    final service = make(storage);
    await service.attach(vault, MediaIndexAccess.readWrite);
    service.record(vault, 1, 10, 20, 640, 480);
    await service.flush(vault);
    expect(storage.writes, 1);
    for (var i = 0; i < 50; i++) {
      service.record(vault, 1, 10, 20, 640, 480); // a tile rebuilt
    }
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(storage.writes, 1);
    service.dispose();
  });

  test('a steady stream of records is still saved within the max wait', () async {
    final storage = _FakeStorage();
    final service = make(storage);
    await service.attach(vault, MediaIndexAccess.readWrite);
    final end = DateTime.now().add(const Duration(milliseconds: 140));
    var i = 0;
    while (DateTime.now().isBefore(end)) {
      service.record(vault, i, 1, 1, 10 + i, 10); // keeps resetting the debounce
      i++;
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(storage.writes >= 1, isTrue, reason: 'writes: ${storage.writes}');
    service.dispose();
  });

  test('read-only access uses a stored index but never writes', () async {
    final storage = _FakeStorage()..stored = _indexWith({5: (1, 1, 100, 50)});
    final service = make(storage);
    await service.attach(vault, MediaIndexAccess.readOnly);
    expect(MediaIndex.widthOf(service.lookup(vault, 5, 1, 1)), 100);
    service.record(vault, 6, 1, 1, 7, 7);
    expect(MediaIndex.widthOf(service.lookup(vault, 6, 1, 1)), 7, reason: 'kept for the session');
    await service.flush(vault);
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(storage.writes, 0);
    service.dispose();
  });

  test('memory-only access touches no storage at all', () async {
    final storage = _FakeStorage()..stored = _indexWith({5: (1, 1, 100, 50)});
    final service = make(storage);
    await service.attach(vault, MediaIndexAccess.memoryOnly);
    expect(service.lookup(vault, 5, 1, 1), 0);
    service.record(vault, 6, 1, 1, 7, 7);
    await service.flush(vault);
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(storage.reads, 0);
    expect(storage.writes, 0);
    expect(MediaIndex.widthOf(service.lookup(vault, 6, 1, 1)), 7);
    service.dispose();
  });

  test('a damaged stored index starts empty and is replaced by the next save', () async {
    final storage = _FakeStorage()..stored = Uint8List.fromList([1, 2, 3, 4, 5]);
    final warnings = <String>[];
    final service = make(storage, warnings: warnings);
    await service.attach(vault, MediaIndexAccess.readWrite);
    expect(warnings, isNotEmpty);
    service.record(vault, 1, 1, 1, 9, 9);
    await service.flush(vault);
    expect(storage.writes, 1);
    expect(MediaIndexCodec.decode(storage.stored!), isNotNull);
    service.dispose();
  });

  test('an index that exists but cannot be read is never saved over', () async {
    final storage = _FakeStorage()..throwOnRead = true;
    final warnings = <String>[];
    final service = make(storage, warnings: warnings);
    await service.attach(vault, MediaIndexAccess.readWrite);
    expect(warnings, isNotEmpty);
    service.record(vault, 1, 1, 1, 9, 9);
    await service.flush(vault);
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(storage.writes, 0);
    expect(MediaIndex.widthOf(service.lookup(vault, 1, 1, 1)), 9, reason: 'still usable this session');
    service.dispose();
  });

  test('failed writes are retried a few times and then given up on', () async {
    final storage = _FakeStorage()..failWrites = true;
    final service = MediaIndexService(
      storage: storage,
      flushDelay: const Duration(milliseconds: 2),
      maxFlushWait: const Duration(milliseconds: 2),
    );
    await service.attach(vault, MediaIndexAccess.readWrite);
    service.record(vault, 1, 1, 1, 9, 9);
    await Future<void>.delayed(const Duration(milliseconds: 150));
    expect(storage.writes <= 3, isTrue, reason: 'writes ${storage.writes}');
    expect(storage.writes >= 1, isTrue);
    service.dispose();
  });

  test('flushForUri saves what is pending before a lock, forgetForUri drops it after', () async {
    final storage = _FakeStorage();
    final service = make(storage);
    MediaIndexService.current = service;
    await service.attach(vault, MediaIndexAccess.readWrite);
    service.record(vault, 1, 1, 1, 9, 9);
    await MediaIndexService.flushForUri(vault.uri);
    expect(storage.writes, 1);
    MediaIndexService.forgetForUri(vault.uri);
    expect(service.isReady(vault), isFalse);
    expect(service.lookup(vault, 1, 1, 1), 0);
    // Unknown containers and a missing service are harmless.
    await MediaIndexService.flushForUri('nope');
    MediaIndexService.current = null;
    await MediaIndexService.flushForUri(vault.uri);
    MediaIndexService.forgetForUri(vault.uri);
    service.dispose();
  });

  test('containers are independent', () async {
    final storage = _FakeStorage();
    final service = make(storage);
    final other = _c('content://vault/b');
    await service.attach(vault, MediaIndexAccess.readWrite);
    await service.attach(other, MediaIndexAccess.readWrite);
    service.record(vault, 1, 1, 1, 9, 9);
    expect(service.lookup(other, 1, 1, 1), 0);
    service.dispose();
  });
}
