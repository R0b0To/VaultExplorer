import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:vaultexplorer/core/api/vault_engine_types.dart';
import 'package:vaultexplorer/core/filesystem/local_storage_container.dart';
import 'package:vaultexplorer/core/providers/vault_engine_providers.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/data/services/vault_engine/channel_methods.dart';

/// What a book is opened as. A comic hands back its page list; an e-book hands
/// back its parsed package (reading order, table of contents, metadata).
enum BookKind { comic, epub }

/// Why a file could not be opened as a book. [notZip], [encrypted] and
/// [unsupported] mean "the full archive browser may still be able to": the
/// reader here only handles plain stored/deflated ZIPs.
enum BookOpenStatus {
  ok,
  notZip,
  encrypted,
  unsupported,
  tooLarge,
  corrupt,
  invalid;

  static BookOpenStatus fromWire(String? wire) {
    for (final status in BookOpenStatus.values) {
      if (status.name == wire) return status;
    }
    return BookOpenStatus.corrupt;
  }

  /// True when falling back to the archive browser is worth trying.
  bool get archiveBrowserMayHelp =>
      this == notZip || this == encrypted || this == unsupported;
}

class BookEntry {
  final String name;
  final int size;
  const BookEntry(this.name, this.size);
}

class EpubTocEntry {
  final String title;

  /// Zip entry path of the chapter file.
  final String path;
  final String fragment;
  final int level;
  const EpubTocEntry({
    required this.title,
    required this.path,
    required this.fragment,
    required this.level,
  });
}

class EpubSpineEntry {
  final String path;
  final bool linear;
  const EpubSpineEntry(this.path, this.linear);
}

class EpubInfo {
  final String title;
  final String author;
  final String language;

  /// `rtl`, `ltr`, or empty when the book does not say.
  final String direction;
  final String coverPath;
  final int coverSize;
  final bool fixedLayout;
  final List<EpubSpineEntry> spine;
  final List<EpubTocEntry> toc;
  const EpubInfo({
    required this.title,
    required this.author,
    required this.language,
    required this.direction,
    required this.coverPath,
    this.coverSize = 0,
    this.fixedLayout = false,
    required this.spine,
    required this.toc,
  });

  factory EpubInfo.fromMap(Map<Object?, Object?> map) {
    final spine = (map['spine'] as List? ?? const [])
        .whereType<Map>()
        .map((e) => EpubSpineEntry(e['path'] as String, e['linear'] as bool? ?? true))
        .toList(growable: false);
    final toc = (map['toc'] as List? ?? const [])
        .whereType<Map>()
        .map(
          (e) => EpubTocEntry(
            title: e['title'] as String? ?? '',
            path: e['path'] as String? ?? '',
            fragment: e['fragment'] as String? ?? '',
            level: (e['level'] as num?)?.toInt() ?? 0,
          ),
        )
        .toList(growable: false);
    return EpubInfo(
      title: map['title'] as String? ?? '',
      author: map['author'] as String? ?? '',
      language: map['language'] as String? ?? '',
      direction: map['direction'] as String? ?? '',
      coverPath: map['coverPath'] as String? ?? '',
      coverSize: (map['coverSize'] as num?)?.toInt() ?? 0,
      fixedLayout: map['fixedLayout'] as bool? ?? false,
      spine: spine,
      toc: toc,
    );
  }
}

class BookOpenResult {
  final BookOpenStatus status;

  /// Session handle; pass it to [VaultBookApi.readEntry] / [VaultBookApi.close].
  final String? token;
  final List<BookEntry> entries;
  final bool hasEncryptedEntries;
  final EpubInfo? epub;

  const BookOpenResult({
    required this.status,
    this.token,
    this.entries = const [],
    this.hasEncryptedEntries = false,
    this.epub,
  });

  factory BookOpenResult.fromMap(Map<Object?, Object?> map) {
    final status = BookOpenStatus.fromWire(map['status'] as String?);
    if (status != BookOpenStatus.ok) return BookOpenResult(status: status);
    final epub = map['epub'];
    return BookOpenResult(
      status: status,
      token: map['token'] as String?,
      entries: (map['entries'] as List? ?? const [])
          .whereType<Map>()
          .map((e) => BookEntry(e['name'] as String, (e['size'] as num?)?.toInt() ?? 0))
          .toList(growable: false),
      hasEncryptedEntries: map['encrypted'] as bool? ?? false,
      epub: epub is Map ? EpubInfo.fromMap(epub) : null,
    );
  }
}

/// Channel client for the comic and e-book readers.
///
/// A book is read in place -- decompressed in memory from ranged reads of the
/// decrypted file -- so nothing is staged on disk and it behaves the same on
/// every vault format and on Local Storage.
class VaultBookApi {
  final MethodChannel _channel;
  const VaultBookApi(this._channel);

  String _localStoragePath(MountedContainer container, String path) {
    if (container.isSafStorage) {
      final root = Uri.parse(container.uri);
      final childSegments = path
          .split('/')
          .where((segment) => segment.isNotEmpty);
      return root
          .replace(pathSegments: [...root.pathSegments, ...childSegments])
          .toString();
    }

    // Local Storage paths describe the device filesystem, whose separator is
    // independent of the OS running a Dart test or desktop build.
    final isWindowsPath = RegExp(
      r'^(?:[A-Za-z]:[\\/]|\\\\)',
    ).hasMatch(container.uri);
    final context = isWindowsPath ? p.windows : p.posix;
    return context.join(container.uri, path);
  }

  Future<BookOpenResult> open({
    required MountedContainer container,
    required String path,
    required BookKind kind,
  }) async {
    final args = <String, Object?>{'kind': kind.name};
    if (container.isLocalStorage) {
      // Same raw-path / SAF-URI string the local archive scan takes.
      args['localPathOrUri'] = _localStoragePath(container, path);
    } else {
      args['volId'] = container.volId;
      args['vaultPath'] = path;
    }
    try {
      final res = await _channel.invokeMethod<Map<Object?, Object?>>(
        ChannelMethods.bookOpen,
        args,
      );
      if (res == null) return const BookOpenResult(status: BookOpenStatus.corrupt);
      return BookOpenResult.fromMap(res);
    } on PlatformException {
      rethrow;
    } catch (e) {
      logSwallowed('bookOpen', e);
      return const BookOpenResult(status: BookOpenStatus.corrupt);
    }
  }

  /// Bytes of one entry. Throws [PlatformException] (codes `BOOK_*`,
  /// `NO_SESSION`, `OUT_OF_MEMORY`) when it cannot be read.
  Future<Uint8List> readEntry(String token, String name) async {
    final bytes = await _channel.invokeMethod<Uint8List>(
      ChannelMethods.bookReadEntry,
      {'token': token, 'name': name},
    );
    if (bytes == null) {
      throw PlatformException(code: 'BOOK_EMPTY', message: 'No data for $name');
    }
    return bytes;
  }

  Future<void> close(String token) async {
    try {
      await _channel.invokeMethod<void>(ChannelMethods.bookClose, {'token': token});
    } catch (e) {
      logSwallowed('bookClose', e);
    }
  }
}

final vaultBookApiProvider = Provider<VaultBookApi>(
  (ref) => VaultBookApi(ref.watch(vaultEngineChannelProvider)),
);
