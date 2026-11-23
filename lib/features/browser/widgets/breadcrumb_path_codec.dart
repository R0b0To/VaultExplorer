import 'package:vaultexplorer/core/utils/storage_uri_path.dart';

/// Where a typed path points, relative to the storage the file browser is in.
class BreadcrumbPathTarget {
  /// A place inside the storage. [relative] is the browser's own form of a
  /// folder path: `/`-separated, no leading slash, `''` for the storage root.
  const BreadcrumbPathTarget.inside(String this.relative) : outside = false;

  /// A well-formed path that leads out of the storage (another drive, above
  /// the storage root). The browser cannot go there from this storage.
  const BreadcrumbPathTarget.outside() : relative = null, outside = true;

  final String? relative;
  final bool outside;

  @override
  String toString() => outside ? 'outside' : 'inside($relative)';
}

/// Converts between the folder paths the file browser keeps (`a/b`, relative
/// to the storage root, `/`-separated) and the text a person reads and types
/// in the editable address field of the breadcrumb bar.
///
///  * A device, SD card or drive is a real folder, so its text is the real
///    path: `/storage/emulated/0/Download`, `/media/me/DISK/x`,
///    `C:\Users\me\Documents`. Typing accepts either slash on Windows.
///  * A vault's contents only exist inside the container, so its text is the
///    in-vault path: `/Documents/Taxes`, with `/` as the vault root. The same
///    holds for a storage whose root has no filesystem path (a cloud
///    provider's SAF tree), since gluing a path onto a URI would not make one.
///
/// Relative input (`Documents`, `..`, `../x`) is taken from the folder the
/// person is in, like a shell's `cd`.
class BreadcrumbPathCodec {
  const BreadcrumbPathCodec._({
    required this.style,
    this.rootSegments = const [],
  });

  /// A vault, or any storage without a real filesystem path.
  const BreadcrumbPathCodec.vault() : this._(style: BreadcrumbPathStyle.vault);

  /// Codec for a storage rooted at [rootUri] (the container's `uri`).
  /// [isLocalStorage] is false for every vault.
  factory BreadcrumbPathCodec.forStorage({
    required String rootUri,
    required bool isLocalStorage,
  }) {
    if (!isLocalStorage) return const BreadcrumbPathCodec.vault();
    var root = readablePathFromUri(rootUri);

    // `file:///C:/Users/me` comes back as `/C:/Users/me`.
    if (RegExp(r'^/[A-Za-z]:(/|$)').hasMatch(root)) root = root.substring(1);

    if (_driveStart.hasMatch(root)) {
      final segments = root
          .split(RegExp(r'[\\/]'))
          .where((s) => s.isNotEmpty)
          .toList();
      // Drive letters compare and show upper-case, as Explorer does.
      segments[0] = segments[0].toUpperCase();
      return BreadcrumbPathCodec._(
        style: BreadcrumbPathStyle.windows,
        rootSegments: segments,
      );
    }
    if (root.startsWith('/')) {
      return BreadcrumbPathCodec._(
        style: BreadcrumbPathStyle.posix,
        rootSegments: root.split('/').where((s) => s.isNotEmpty).toList(),
      );
    }
    return const BreadcrumbPathCodec.vault();
  }

  static final RegExp _driveStart = RegExp(r'^[A-Za-z]:([\\/]|$)');
  static final RegExp _driveSegment = RegExp(r'^[A-Za-z]:$');

  final BreadcrumbPathStyle style;

  /// The storage root as path segments (`['storage', 'emulated', '0']`,
  /// `['C:', 'Users', 'me']`); empty for a vault or a `/` root.
  final List<String> rootSegments;

  bool get isRealPath => style != BreadcrumbPathStyle.vault;

  /// The text for the folder [relative] (the browser's own path, `''` for the
  /// storage root).
  String format(String relative) {
    final parts = relative.split('/').where((s) => s.isNotEmpty).toList();
    switch (style) {
      case BreadcrumbPathStyle.vault:
        return '/${parts.join('/')}';
      case BreadcrumbPathStyle.posix:
        return '/${[...rootSegments, ...parts].join('/')}';
      case BreadcrumbPathStyle.windows:
        final all = [...rootSegments, ...parts];
        // A drive root keeps its trailing backslash: `C:\`, not `C:`.
        return all.length == 1 ? '${all.first}\\' : all.join('\\');
    }
  }

  /// Resolves what the person typed. [currentRelative] is the folder they are
  /// in now. Returns null for blank input.
  BreadcrumbPathTarget? resolve(String input, String currentRelative) {
    var text = _stripQuotes(input.trim());
    if (text.isEmpty) return null;

    if (style == BreadcrumbPathStyle.windows) {
      text = text.replaceAll('\\', '/');
    } else if (style == BreadcrumbPathStyle.posix) {
      text = _expandAndroidAlias(text);
    }

    final typed = text.split('/').where((s) => s.isNotEmpty).toList();
    final rooted = text.startsWith('/');
    final currentParts = currentRelative
        .split('/')
        .where((s) => s.isNotEmpty)
        .toList();

    // The segments of the target below the storage root, or null when the
    // path leaves the storage.
    List<String>? relative;

    switch (style) {
      case BreadcrumbPathStyle.vault:
        relative = _collapse([if (!rooted) ...currentParts, ...typed]);
      case BreadcrumbPathStyle.posix:
        relative = rooted
            ? _below(_collapse(typed), caseSensitive: true)
            : _collapse([...currentParts, ...typed]);
      case BreadcrumbPathStyle.windows:
        if (typed.isNotEmpty && _driveSegment.hasMatch(typed.first)) {
          // `C:` alone and `C:\...` are both absolute here; a bare `C:` would
          // mean "the current folder on C" to Windows, which has no meaning
          // in a browser, so it is read as the drive root.
          final drive = typed.first.toUpperCase();
          final collapsed = _collapse(typed.sublist(1));
          relative = collapsed == null
              ? null
              : _below([drive, ...collapsed], caseSensitive: false);
        } else if (rooted) {
          // `\Documents` is relative to the storage root, which is the drive
          // root for a drive and the start of the visible tree otherwise.
          relative = _collapse(typed);
        } else {
          relative = _collapse([...currentParts, ...typed]);
        }
    }

    return relative == null
        ? const BreadcrumbPathTarget.outside()
        : BreadcrumbPathTarget.inside(relative.join('/'));
  }

  /// [absolute] (root segments included) minus the storage root, or null when
  /// it is not inside the root.
  List<String>? _below(
    List<String>? absolute, {
    required bool caseSensitive,
  }) {
    if (absolute == null) return null;
    if (absolute.length < rootSegments.length) return null;
    for (var i = 0; i < rootSegments.length; i++) {
      final a = absolute[i];
      final r = rootSegments[i];
      final same = caseSensitive ? a == r : a.toLowerCase() == r.toLowerCase();
      if (!same) return null;
    }
    return absolute.sublist(rootSegments.length);
  }

  /// Resolves `.` and `..`; null when a `..` would climb above the start.
  static List<String>? _collapse(List<String> parts) {
    final out = <String>[];
    for (final part in parts) {
      if (part == '.') continue;
      if (part == '..') {
        if (out.isEmpty) return null;
        out.removeLast();
        continue;
      }
      out.add(part);
    }
    return out;
  }

  /// Explorer's "Copy as path" wraps the path in double quotes.
  static String _stripQuotes(String s) {
    if (s.length >= 2 &&
        ((s.startsWith('"') && s.endsWith('"')) ||
            (s.startsWith("'") && s.endsWith("'")))) {
      return s.substring(1, s.length - 1).trim();
    }
    return s;
  }

  /// `/sdcard` and `/storage/self/primary` are how Android apps and `adb` name
  /// the shared storage that is really `/storage/emulated/0`.
  String _expandAndroidAlias(String text) {
    final isSharedStorage =
        rootSegments.length == 3 &&
        rootSegments[0] == 'storage' &&
        rootSegments[1] == 'emulated' &&
        rootSegments[2] == '0';
    if (!isSharedStorage) return text;
    for (final alias in const ['/sdcard', '/storage/self/primary']) {
      if (text == alias || text.startsWith('$alias/')) {
        return '/storage/emulated/0${text.substring(alias.length)}';
      }
    }
    return text;
  }
}

enum BreadcrumbPathStyle { vault, posix, windows }
