import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/data/services/vault_engine/vault_explorer_api.dart';
import 'package:vaultexplorer/features/tools/models/hash_verifier_models.dart';
import 'package:vaultexplorer/features/tools/models/tool_models.dart';
import 'package:vaultexplorer/features/tools/services/hash_verifier_service.dart';

/// Fakes the native incremental hash session
/// ([VaultExplorerApi.beginHashSession] and friends) plus [readFileChunk]/
/// [getFileSize], so [HashVerifierService.computeHashes]'s vault-source
/// path can be exercised without a real mounted container or platform
/// channel. Deliberately not a real digest (see
/// [keyfile_passphrase_generator_service_test.dart]'s fake for the same
/// reasoning): these tests check that the service feeds the right bytes
/// through the session API in the right order and cleans up correctly on
/// every exit path, not that the underlying algorithm is cryptographically
/// correct -- that's `java.security.MessageDigest`'s job.
class _FakeHashSessionApi extends VaultExplorerApi {
  _FakeHashSessionApi(this.fileBytes);

  final Uint8List fileBytes;
  final Map<int, Map<String, List<int>>> _sessions = {};
  final List<int> discardedOpIds = [];
  final List<int> finishedOpIds = [];
  final List<int> updateCallCount = [];
  final Set<int> failingOffsets = {};

  @override
  Future<int> getFileSize(MountedContainer container, String fileName) async => fileBytes.length;

  @override
  Future<Uint8List?> readFileChunk(MountedContainer container, String fileName, int offset, int length) async {
    if (failingOffsets.contains(offset)) return null;
    return Uint8List.sublistView(fileBytes, offset, (offset + length).clamp(0, fileBytes.length));
  }

  @override
  Future<void> beginHashSession(int opId, List<String> algorithms) async {
    _sessions[opId] = {for (final a in algorithms) a: <int>[]};
  }

  @override
  Future<void> updateHashSession(int opId, Uint8List bytes) async {
    updateCallCount.add(opId);
    final session = _sessions[opId];
    if (session == null) throw StateError('updateHashSession with no open session for opId $opId');
    for (final buf in session.values) {
      buf.addAll(bytes);
    }
  }

  @override
  Future<Map<String, String>> finishHashSession(int opId) async {
    final session = _sessions.remove(opId);
    if (session == null) throw StateError('finishHashSession with no open session for opId $opId');
    finishedOpIds.add(opId);
    return session.map((algo, bytes) => MapEntry(algo, _fakeDigest(bytes)));
  }

  @override
  Future<void> discardHashSession(int opId) async {
    _sessions.remove(opId);
    discardedOpIds.add(opId);
  }

  String _fakeDigest(List<int> bytes) {
    var acc = bytes.length;
    for (final b in bytes) {
      acc = (acc * 31 + b) & 0x7fffffff;
    }
    return acc.toRadixString(16).padLeft(8, '0');
  }
}

MountedContainer _container() => MountedContainer(
      uri: 'file:///test.vault',
      displayName: 'Test Vault',
      volId: 1,
      rootFiles: const [],
      mountedAt: DateTime(2026, 1, 1),
      totalSpace: 100000000,
      freeSpace: 50000000,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() => vaultExplorerApi = const VaultExplorerApi());

  group('HashVerifierService.computeHashes (vault source)', () {
    test('computes every requested algorithm over the full file contents', () async {
      final bytes = Uint8List.fromList(List.generate(600 * 1024, (i) => i % 256)); // > one chunk
      final api = _FakeHashSessionApi(bytes);
      vaultExplorerApi = api;

      final source = CryptoSourceItem.vault(
        displayName: 'big.bin',
        container: _container(),
        relativePath: 'big.bin',
      );

      final result = await HashVerifierService().computeHashes(
        source: source,
        algorithms: {HashAlgorithm.sha256, HashAlgorithm.md5},
      );

      expect(result.keys, containsAll([HashAlgorithm.sha256, HashAlgorithm.md5]));
      // Both algorithms were fed the same byte stream, so with this fake's
      // length+checksum digest they land on the same value -- what matters
      // here is that both were actually computed (not e.g. one silently
      // dropped) and finished cleanly.
      expect(api.finishedOpIds, hasLength(1));
      expect(api.discardedOpIds, isEmpty);
    });

    test('reports byte progress as it reads', () async {
      final bytes = Uint8List.fromList(List.generate(600 * 1024, (i) => i % 256));
      vaultExplorerApi = _FakeHashSessionApi(bytes);

      final source = CryptoSourceItem.vault(
        displayName: 'big.bin',
        container: _container(),
        relativePath: 'big.bin',
      );

      final progressCalls = <int>[];
      await HashVerifierService().computeHashes(
        source: source,
        algorithms: {HashAlgorithm.sha256},
        onProgress: (done, total) => progressCalls.add(done),
      );

      expect(progressCalls, isNotEmpty);
      expect(progressCalls.last, equals(bytes.length));
      expect(progressCalls, orderedEquals(progressCalls.toList()..sort()));
    });

    test('a cancelled token discards the session and throws', () async {
      final bytes = Uint8List.fromList(List.generate(600 * 1024, (i) => i));
      final api = _FakeHashSessionApi(bytes);
      vaultExplorerApi = api;

      final source = CryptoSourceItem.vault(
        displayName: 'big.bin',
        container: _container(),
        relativePath: 'big.bin',
      );

      final token = HashCancellationToken();
      var calls = 0;
      await expectLater(
        HashVerifierService().computeHashes(
          source: source,
          algorithms: {HashAlgorithm.sha256},
          cancelToken: token,
          onProgress: (done, total) {
            calls++;
            if (calls == 1) token.cancel(); // cancel partway through
          },
        ),
        throwsA(isA<HashOperationCancelledException>()),
      );

      expect(api.discardedOpIds, hasLength(1));
      expect(api.finishedOpIds, isEmpty);
    });

    test('a failed chunk read discards the session and throws', () async {
      final bytes = Uint8List.fromList(List.generate(600 * 1024, (i) => i));
      final api = _FakeHashSessionApi(bytes)..failingOffsets.add(0);
      vaultExplorerApi = api;

      final source = CryptoSourceItem.vault(
        displayName: 'big.bin',
        container: _container(),
        relativePath: 'big.bin',
      );

      await expectLater(
        HashVerifierService().computeHashes(source: source, algorithms: {HashAlgorithm.sha256}),
        throwsException,
      );

      expect(api.discardedOpIds, hasLength(1));
      expect(api.finishedOpIds, isEmpty);
    });

    test('an empty algorithms set does not open a session at all', () async {
      final bytes = Uint8List.fromList([1, 2, 3]);
      final api = _FakeHashSessionApi(bytes);
      vaultExplorerApi = api;

      final source = CryptoSourceItem.vault(
        displayName: 'f.bin',
        container: _container(),
        relativePath: 'f.bin',
      );

      final result = await HashVerifierService().computeHashes(source: source, algorithms: {});
      expect(result, isEmpty);
      expect(api.finishedOpIds, isEmpty);
      expect(api.discardedOpIds, isEmpty);
    });
  });

  group('HashVerifierService.parseManifest', () {
    test('parses GNU coreutils text-mode lines and infers the algorithm from hex length', () {
      const manifest = 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855  file.txt\n'
          '9e107d9d372bb6826bd81d3542a419d6  other.bin\n';
      final entries = HashVerifierService().parseManifest(manifest);

      expect(entries, hasLength(2));
      expect(entries[0].algorithm, equals(HashAlgorithm.sha256));
      expect(entries[0].fileName, equals('file.txt'));
      expect(entries[1].algorithm, equals(HashAlgorithm.md5));
    });

    test('parses BSD-tagged lines using the explicit algorithm tag', () {
      const manifest = 'SHA256 (archive.zip) = e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855\n';
      final entries = HashVerifierService().parseManifest(manifest);

      expect(entries, hasLength(1));
      expect(entries.single.algorithm, equals(HashAlgorithm.sha256));
      expect(entries.single.fileName, equals('archive.zip'));
    });

    test('skips blank lines and comments', () {
      const manifest = '# generated by sha256sum\n'
          '\n'
          'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855  file.txt\n';
      final entries = HashVerifierService().parseManifest(manifest);
      expect(entries, hasLength(1));
    });

    test('a GNU-style line whose hex length matches no supported algorithm '
        'is silently skipped rather than producing a mis-attributed entry',
        () {
      // 40 hex chars would be SHA-1; 44 matches nothing this tool computes
      // (e.g. a truncated/corrupted line, or an algorithm this app doesn't
      // support) -- fromHexLength returns null and the line is dropped.
      const manifest =
          'abababababababababababababababababababababab  file.txt\n'; // 44 hex chars
      final entries = HashVerifierService().parseManifest(manifest);
      expect(entries, isEmpty);
    });

    test('a BSD-style tag outside the four supported algorithms (e.g. '
        'SHA384) does not match the BSD pattern at all -- it falls through '
        'to the GNU check, which also fails to match a line starting with '
        'letters, so the line is dropped the same way any unrecognized '
        'line is: silently, without throwing', () {
      const manifest = 'SHA384 (archive.zip) = '
          'abababababababababababababababababababababababababababababababababababababababababababababababab\n'; // 96 hex chars
      final entries = HashVerifierService().parseManifest(manifest);
      expect(entries, isEmpty);
    });

    test('a line matching neither the GNU nor BSD format is skipped '
        'without throwing -- a genuinely corrupted or truncated manifest '
        'line must never crash parsing of the rest of the file', () {
      const manifest = 'this is not a checksum line at all\n'
          'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855  good.txt\n';
      final entries = HashVerifierService().parseManifest(manifest);
      expect(entries, hasLength(1));
      expect(entries.single.fileName, equals('good.txt'));
    });

    test('a hex digest shorter than the GNU pattern\'s minimum length '
        '(e.g. a digest truncated mid-write) fails to match the line '
        'shape entirely and is dropped, the same as any other '
        'unrecognized line', () {
      const manifest = 'abcdef0123  truncated.txt\n'; // 10 hex chars, < 32
      final entries = HashVerifierService().parseManifest(manifest);
      expect(entries, isEmpty);
    });

    test('a GNU-style line whose hex length is inside the 32-128 pattern '
        'range but matches no supported algorithm exact length is '
        'parsed as a line, then dropped by fromHexLength -- this is the '
        'one case that actually exercises the null-algorithm branch, as '
        'opposed to the regex simply failing to match', () {
      // 96 hex chars (SHA-384's own length) is inside {32,128} but isn't
      // 32/40/64/128 -- the only lengths this tool's algorithms produce.
      const manifest =
          'abababababababababababababababababababababababababababababababababababababababababababababababab  file.txt\n';
      final entries = HashVerifierService().parseManifest(manifest);
      expect(entries, isEmpty);
    });

    test('an empty manifest produces no entries', () {
      final entries = HashVerifierService().parseManifest('');
      expect(entries, isEmpty);
    });
  });
}