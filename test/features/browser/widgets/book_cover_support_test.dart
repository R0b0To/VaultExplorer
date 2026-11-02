import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/core/api/vault_book_api.dart';
import 'package:vaultexplorer/core/api/vault_crypto_api.dart';
import 'package:vaultexplorer/core/api/vault_file_io_api.dart';
import 'package:vaultexplorer/core/api/vault_hash_api.dart';
import 'package:vaultexplorer/core/utils/image_preview_exception.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/data/models/thumbnail_cache_mode.dart';
import 'package:vaultexplorer/data/models/thumbnail_quality.dart';
import 'package:vaultexplorer/data/models/thumbnail_with_size.dart';
import 'package:vaultexplorer/data/services/thumbnail_cache_service.dart';
import 'package:vaultexplorer/features/browser/widgets/book_cover_support.dart';

final _coverBytes = Uint8List.fromList([0xFF, 0xD8, 0x01, 0x02, 0xFF, 0xD9]);

/// A [VaultBookApi] whose `getCover` is scripted, to test everything above the
/// channel (the channel itself is covered in vault_book_api_test.dart).
class _FakeBookApi extends VaultBookApi {
  _FakeBookApi() : super(const MethodChannel('test/book-api'));

  int coverCalls = 0;
  Object? error;
  BookKind? lastKind;
  int? lastTargetSize;
  int? lastQuality;

  @override
  Future<ThumbnailWithSize> getCover({
    required MountedContainer container,
    required String path,
    required BookKind kind,
    int targetSize = 180,
    int quality = 70,
  }) async {
    coverCalls++;
    lastKind = kind;
    lastTargetSize = targetSize;
    lastQuality = quality;
    if (error != null) throw error!;
    return ThumbnailWithSize(bytes: _coverBytes, width: 600, height: 900);
  }
}

class _FakeFileIoApi extends VaultFileIoApi {
  _FakeFileIoApi() : super(const MethodChannel('test/file-io-api'));
}

class _FakeCryptoApi extends VaultCryptoApi {
  _FakeCryptoApi() : super(const MethodChannel('test/crypto-api'));
}

class _FakeHashApi extends VaultHashApi {
  _FakeHashApi() : super(const MethodChannel('test/hash-api'));
}

void main() {
  group('bookKindForThumbnail', () {
    test('epub is an e-book, whatever the case', () {
      expect(bookKindForThumbnail('Novel.epub'), BookKind.epub);
      expect(bookKindForThumbnail('NOVEL.EPUB'), BookKind.epub);
    });

    test('cbz and the comic extensions the reader tries are comics', () {
      for (final name in ['a.cbz', 'a.CBZ', 'a.cbr', 'a.cb7', 'a.cbt']) {
        expect(bookKindForThumbnail(name), BookKind.comic, reason: name);
      }
    });

    test('everything else is not a book', () {
      for (final name in ['a.pdf', 'a.mobi', 'a.zip', 'epub', 'a.', 'noext']) {
        expect(bookKindForThumbnail(name), isNull, reason: name);
        expect(isBookWithCover(name), isFalse, reason: name);
      }
    });

    test('works on a full path, and a dot in a folder name is not the extension', () {
      expect(bookKindForThumbnail('Books/Sci-Fi/a.epub'), BookKind.epub);
      expect(bookKindForThumbnail('my.epub/readme'), isNull);
    });
  });

  group('fetchBookCoverForThumbnail', () {
    final container = MountedContainer(
      volId: 1,
      displayName: 'Vault',
      uri: 'vault-uri',
      rootFiles: const [],
      mountedAt: DateTime(2026, 1, 1),
      totalSpace: 1000,
      freeSpace: 500,
    );
    late _FakeBookApi api;
    setUp(() => api = _FakeBookApi());

    Future<ThumbnailWithSize> fetch(String path) => fetchBookCoverForThumbnail(
          bookApi: api,
          container: container,
          filePath: path,
          targetSize: 240,
          quality: 65,
        );

    test('asks for the right kind, size and quality', () async {
      final thumb = await fetch('a/b.cbz');
      expect(thumb.bytes, _coverBytes);
      expect(api.lastKind, BookKind.comic);
      expect(api.lastTargetSize, 240);
      expect(api.lastQuality, 65);

      await fetch('a/b.epub');
      expect(api.lastKind, BookKind.epub);
    });

    test('a file that is not a book never reaches native', () {
      expect(() => fetch('a/b.pdf'), throwsA(isA<BookCoverUnavailable>()));
      expect(api.coverCalls, 0);
    });

    test('"nothing to show" codes become a permanent, do-not-retry failure', () async {
      for (final code in [
        'BOOK_NO_COVER', 'BOOK_NOT_ZIP', 'BOOK_ENCRYPTED', 'BOOK_UNSUPPORTED',
        'BOOK_TOO_LARGE', 'BOOK_CORRUPT', 'BOOK_NOT_FOUND', 'BOOK_EMPTY',
        'FILE_NOT_FOUND', 'DECODE_FAILED', 'IMAGE_TOO_LARGE',
      ]) {
        api.error = PlatformException(code: code);
        await expectLater(
          fetch('a.epub'),
          throwsA(isA<PermanentThumbnailFailure>().having(
            (e) => e,
            'is a BookCoverUnavailable',
            isA<BookCoverUnavailable>(),
          )),
          reason: code,
        );
      }
    });

    test('anything that might pass is rethrown so the loader can retry', () async {
      for (final code in ['OUT_OF_MEMORY', 'NOT_MOUNTED', 'SOMETHING_NEW']) {
        api.error = PlatformException(code: code);
        await expectLater(
          fetch('a.epub'),
          throwsA(isA<PlatformException>().having((e) => e.code, 'code', code)),
          reason: code,
        );
      }
    });

    test('BookCoverUnavailable is not an image-preview refusal', () {
      // Different failure family: it must not be mistaken for the
      // too-large/out-of-memory refusals the image viewers explain to the user.
      const failure = BookCoverUnavailable('x');
      expect(failure, isA<PermanentThumbnailFailure>());
      expect(failure, isNot(isA<ImagePreviewUnavailableException>()));
    });
  });

  group('loadBookCoverThumbnail', () {
    final container = MountedContainer(
      volId: 1,
      displayName: 'Vault',
      uri: 'vault-uri',
      rootFiles: const [],
      mountedAt: DateTime(2026, 1, 1),
      totalSpace: 1000,
      freeSpace: 500,
    );
    late _FakeBookApi api;
    late ThumbnailCacheService cache;

    setUp(() {
      api = _FakeBookApi();
      ThumbnailCacheService.configure(
        fileIoApi: _FakeFileIoApi(),
        cryptoApi: _FakeCryptoApi(),
        hashApi: _FakeHashApi(),
      );
      cache = const ThumbnailCacheService();
    });

    test('a miss asks native once and remembers the cover, size included', () async {
      final thumb = await loadBookCoverThumbnail(
        thumbnailCache: cache,
        bookApi: api,
        container: container,
        path: 'Books/miss.epub',
        mode: ThumbnailCacheMode.disabled,
        quality: ThumbnailQuality.defaultQuality,
      );

      expect(thumb.bytes, _coverBytes);
      expect(api.coverCalls, 1);
      final remembered = cache.peekMemoryWithSize(
        container,
        'Books/miss.epub',
        ThumbnailQuality.defaultQuality,
      );
      expect(remembered?.$1, _coverBytes);
      expect(remembered?.$2, 600);
      expect(remembered?.$3, 900);
    });

    test('a cached cover is served without opening the book', () async {
      cache.cacheInMemory(
        container,
        'Books/hit.cbz',
        _coverBytes,
        ThumbnailQuality.defaultQuality,
        320,
        480,
      );

      final thumb = await loadBookCoverThumbnail(
        thumbnailCache: cache,
        bookApi: api,
        container: container,
        path: 'Books/hit.cbz',
        mode: ThumbnailCacheMode.appCache,
        quality: ThumbnailQuality.defaultQuality,
      );

      expect(api.coverCalls, 0);
      expect(thumb.bytes, _coverBytes);
      expect(thumb.width, 320);
      expect(thumb.height, 480);
    });

    test('a book with no cover leaves nothing in the cache', () async {
      api.error = PlatformException(code: 'BOOK_NO_COVER');

      await expectLater(
        loadBookCoverThumbnail(
          thumbnailCache: cache,
          bookApi: api,
          container: container,
          path: 'Books/none.epub',
          mode: ThumbnailCacheMode.disabled,
          quality: ThumbnailQuality.defaultQuality,
        ),
        throwsA(isA<BookCoverUnavailable>()),
      );
      expect(
        cache.peekMemory(container, 'Books/none.epub', ThumbnailQuality.defaultQuality),
        isNull,
      );
    });
  });
}
