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

void main() {
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
