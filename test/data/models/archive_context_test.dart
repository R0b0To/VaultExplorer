import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/core/api/vault_archive_api.dart';
import 'package:vaultexplorer/data/models/archive_context.dart';
import 'package:vaultexplorer/data/models/archive_models.dart';

class _CountingArchiveApi extends VaultArchiveApi {
  int extractCalls = 0;

  /// Paths handed to [discardBrowseFile], in order.
  final List<String> discarded = [];

  _CountingArchiveApi() : super(const MethodChannel('test'));

  @override
  Future<bool> discardBrowseFile(String path) async {
    discarded.add(path);
    return true;
  }

  @override
  Future<ArchiveEntryExtractResult> extractVaultArchiveEntry({
    required String filePath,
    required String vaultPath,
    required int targetIndex,
    String? passphrase,
  }) async {
    extractCalls++;
    return ArchiveEntryExtractResult(
      status: ArchiveOpenStatus.ok,
      data: Uint8List.fromList([1, 2, 3]),
      errorMessage: '',
    );
  }
}

ArchiveEntryInfo _entry(String path, int size, int index) => ArchiveEntryInfo(
  path: path,
  uncompressedSize: size,
  compressedSize: size,
  modTime: DateTime(2026, 1, 1),
  isEncrypted: false,
  isDirectory: false,
  index: index,
);

ArchiveEntryInfo _dir(String path, int index) => ArchiveEntryInfo(
  path: path,
  uncompressedSize: 0,
  compressedSize: 0,
  modTime: DateTime(2026, 1, 1),
  isEncrypted: false,
  isDirectory: true,
  index: index,
);

/// A scanned archive holding one file; [parent] / [source] make it nested.
ArchiveContext _context(
  _CountingArchiveApi api, {
  String name = 'a.zip',
  int pathStackEntryIndex = 0,
  ArchiveContext? parent,
  StagedArchiveSource? source,
}) => ArchiveContext.fromScanResult(
  archivePathInContainer: name,
  pathStackEntryIndex: pathStackEntryIndex,
  api: api,
  localPathOrUri: source?.path,
  parent: parent,
  stagedSource: source,
  indexResult: ArchiveIndexResult(
    status: ArchiveOpenStatus.ok,
    isSolid: false,
    errorMessage: '',
    entries: [_entry('file.txt', 3, 0)],
  ),
);

void main() {
  test('the root record of an ISO/cpio ("." / "./") is not listed as a folder', () {
    final context = ArchiveContext.fromScanResult(
      archivePathInContainer: 'disc.iso',
      pathStackEntryIndex: 0,
      indexResult: ArchiveIndexResult(
        status: ArchiveOpenStatus.ok,
        isSolid: false,
        errorMessage: '',
        entries: [
          _dir('.', 0),
          _dir('docs', 1),
          _entry('docs/a.txt', 10, 2),
          _entry('readme.txt', 5, 3),
        ],
      ),
    );

    final root = context.listDirectory('');
    expect(root.where((e) => e.endsWith('|.')), isEmpty);
    expect(root.where((e) => e.startsWith('D|') && e.endsWith('|docs')), hasLength(1));
    expect(root.where((e) => e.startsWith('F|') && e.endsWith('|readme.txt')), hasLength(1));
    expect(
      context.listDirectory('docs').where((e) => e.endsWith('|a.txt')),
      hasLength(1),
    );

    final dotSlash = ArchiveContext.fromScanResult(
      archivePathInContainer: 'x.cpio',
      pathStackEntryIndex: 0,
      indexResult: ArchiveIndexResult(
        status: ArchiveOpenStatus.ok,
        isSolid: false,
        errorMessage: '',
        entries: [_dir('./', 0), _entry('only.txt', 1, 1)],
      ),
    );
    expect(dotSlash.listDirectory('').where((e) => e.endsWith('|.')), isEmpty);
  });

  test('entries above the in-memory cap are refused without a native call', () async {
    final api = _CountingArchiveApi();
    final context = ArchiveContext.fromScanResult(
      archivePathInContainer: 'a.zip',
      pathStackEntryIndex: 0,
      api: api,
      vaultFilePath: 'vault-uri',
      vaultPath: 'a.zip',
      indexResult: ArchiveIndexResult(
        status: ArchiveOpenStatus.ok,
        isSolid: false,
        errorMessage: '',
        entries: [
          _entry('big.bin', ArchiveContext.maxInMemoryEntryBytes + 1, 0),
          _entry('small.txt', 1024, 1),
        ],
      ),
    );

    final big = await context.extractEntryResult('big.bin');
    expect(big.status, ArchiveOpenStatus.ioError);
    expect(big.data, isNull);
    expect(api.extractCalls, 0);

    final small = await context.extractEntryResult('small.txt');
    expect(small.status, ArchiveOpenStatus.ok);
    expect(small.data, Uint8List.fromList([1, 2, 3]));
    expect(api.extractCalls, 1);
  });
  group('nested archives', () {
    test('an archive that lives in a container is not nested', () {
      final context = _context(_CountingArchiveApi());

      expect(context.isNested, isFalse);
      expect(context.nestingDepth, 0);
      expect(context.outermost, same(context));
    });

    test('a nested archive knows its parent, depth and outermost archive', () {
      final api = _CountingArchiveApi();
      final top = _context(api);
      final middle = _context(
        api,
        name: 'b.zip',
        pathStackEntryIndex: 1,
        parent: top,
        source: StagedArchiveSource('/cache/archive_browse_1_b.zip', api),
      );
      final inner = _context(
        api,
        name: 'c.zip',
        pathStackEntryIndex: 2,
        parent: middle,
        source: StagedArchiveSource('/cache/archive_browse_2_c.zip', api),
      );

      expect(inner.isNested, isTrue);
      expect(inner.parent, same(middle));
      expect(inner.nestingDepth, 2);
      expect(inner.outermost, same(top));
      expect(middle.outermost, same(top));
    });

    test('a nested archive is read from its temporary copy', () {
      final api = _CountingArchiveApi();
      final source = StagedArchiveSource('/cache/archive_browse_1_b.zip', api);
      final nested = _context(api, parent: _context(api), source: source);

      expect(nested.localPathOrUri, '/cache/archive_browse_1_b.zip');
      expect(nested.stagedSource, same(source));
    });

    test('a password retry keeps the parent and the temporary copy', () {
      final api = _CountingArchiveApi();
      final top = _context(api);
      final source = StagedArchiveSource('/cache/archive_browse_1_b.zip', api);
      final nested = _context(api, parent: top, source: source);

      final retried = nested.withPassphrase('secret');

      expect(retried.passphrase, 'secret');
      expect(retried.parent, same(top));
      expect(retried.stagedSource, same(source));
    });

    test('the temporary copy is wiped only when its last owner lets go', () {
      final api = _CountingArchiveApi();
      final source = StagedArchiveSource('/cache/archive_browse_1_b.zip', api);

      source.retain(); // e.g. the clipboard
      source.release();
      expect(api.discarded, isEmpty);
      expect(source.isReleased, isFalse);

      source.release(); // the archive view
      expect(api.discarded, ['/cache/archive_browse_1_b.zip']);
      expect(source.isReleased, isTrue);

      source.release();
      source.retain(); // too late: the file is gone
      source.release();
      expect(api.discarded, hasLength(1));
    });

    test('closing a nested archive wipes its copy once, however often it is disposed', () {
      final api = _CountingArchiveApi();
      final nested = _context(
        api,
        parent: _context(api),
        source: StagedArchiveSource('/cache/archive_browse_1_b.zip', api),
      );

      nested.dispose();
      nested.dispose();

      expect(api.discarded, ['/cache/archive_browse_1_b.zip']);
    });

    test('closing a nested archive leaves its parent usable', () {
      final api = _CountingArchiveApi();
      final parentSource = StagedArchiveSource('/cache/archive_browse_1_b.zip', api);
      final parent = _context(
        api,
        name: 'b.zip',
        pathStackEntryIndex: 1,
        parent: _context(api),
        source: parentSource,
      );
      final nested = _context(
        api,
        name: 'c.zip',
        pathStackEntryIndex: 2,
        parent: parent,
        source: StagedArchiveSource('/cache/archive_browse_2_c.zip', api),
      );

      nested.dispose();

      expect(api.discarded, ['/cache/archive_browse_2_c.zip']);
      expect(parentSource.isReleased, isFalse);
    });

    test('disposeChain wipes the copy of every archive in the chain', () {
      final api = _CountingArchiveApi();
      final middle = _context(
        api,
        name: 'b.zip',
        pathStackEntryIndex: 1,
        parent: _context(api),
        source: StagedArchiveSource('/cache/archive_browse_1_b.zip', api),
      );
      final inner = _context(
        api,
        name: 'c.zip',
        pathStackEntryIndex: 2,
        parent: middle,
        source: StagedArchiveSource('/cache/archive_browse_2_c.zip', api),
      );

      inner.disposeChain();

      expect(api.discarded, [
        '/cache/archive_browse_2_c.zip',
        '/cache/archive_browse_1_b.zip',
      ]);
    });

    test('a hold taken with retainSource outlives dispose', () {
      final api = _CountingArchiveApi();
      final nested = _context(
        api,
        parent: _context(api),
        source: StagedArchiveSource('/cache/archive_browse_1_b.zip', api),
      );

      nested.retainSource(); // e.g. an extraction still running
      nested.dispose();
      expect(api.discarded, isEmpty);

      nested.releaseSource();
      expect(api.discarded, ['/cache/archive_browse_1_b.zip']);
    });

    test('disposing an archive that is not nested touches no file', () {
      final api = _CountingArchiveApi();

      _context(api).disposeChain();

      expect(api.discarded, isEmpty);
    });
  });
}
