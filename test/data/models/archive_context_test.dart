import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/core/api/vault_archive_api.dart';
import 'package:vaultexplorer/data/models/archive_context.dart';
import 'package:vaultexplorer/data/models/archive_models.dart';

class _CountingArchiveApi extends VaultArchiveApi {
  int extractCalls = 0;

  _CountingArchiveApi() : super(const MethodChannel('test'));

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
}
