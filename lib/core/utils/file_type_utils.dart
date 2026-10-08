import 'package:material_ui/material_ui.dart';

/// True when [name] carries the extension the Single File Crypto tool
/// writes on encrypt -- `.vxenc` (native format) or `.aes` (AES Crypt
/// compatible, see [StandaloneCipher.aesCrypt]). Used to decide whether the
/// file manager's selection toolbar offers "Encrypt" or "Decrypt" for a
/// given file -- see `SingleFileCryptoHandlers.kt`'s `outName` logic, which
/// is the source of truth this mirrors.
bool isAppEncryptedFileName(String name) {
  final lower = name.toLowerCase();
  return lower.endsWith('.vxenc') || lower.endsWith('.aes');
}

/// True for an Android application package (`.apk`) -- used to decide
/// whether a file-manager tile should attempt to show the app's own
/// launcher icon instead of a generic file-type icon. See
/// `apk_icon_support.dart`.
bool isApkFile(String name) {
  final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
  return ext == 'apk';
}

/// Every kind of file the app gives its own icon and accent colour.
///
/// [fileKindOf] is the single place that decides which kind a file is;
/// [iconForFile], [colorForFile] and `SkinIcons.glyphForFile` all switch over
/// it exhaustively, so a new kind or extension can never be taught to one of
/// them and forgotten in another.
enum FileKind {
  pdf,
  image,
  video,
  audio,
  document,
  spreadsheet,
  presentation,
  text,
  code,
  web,
  archive,
  ebook,
  font,
  database,
  keyFile,
  encrypted,
  apk,
  generic,
}

/// Lower-case extensions (no dot) shown with the music/audio icon.
///
/// Deliberately independent of the in-app player's
/// `MediaViewerConstants.audioExtensions`: that list decides what the viewer
/// can *play*, this one decides what *looks* like music.
const Set<String> audioFileExtensions = {
  'mp3', 'mp2', 'm4a', 'm4b', 'aac', 'wav', 'flac', 'ogg', 'oga', 'opus',
  'spx', 'wma', 'ac3', 'eac3', 'ape', 'aiff', 'aif', 'aifc', 'dts', 'amr',
  'awb', 'mka', 'mid', 'midi', 'weba', 'wv', 'mpc', 'au', 'caf',
};

/// Lower-case extensions (no dot) shown with the video icon. See
/// [audioFileExtensions].
///
/// `ts` is absent: it is claimed by TypeScript source ([FileKind.code]), which
/// MPEG transport streams share the extension with.
const Set<String> videoFileExtensions = {
  'mp4', 'm4v', 'webm', 'mov', 'qt', 'avi', 'mkv', 'mpeg', 'mpg', 'mpe',
  'flv', 'f4v', 'wmv', 'asf', '3gp', '3g2', 'vob', 'ogv', 'ogm', 'divx',
  'm2ts', 'mts', 'm2v', 'rm', 'rmvb', 'mxf',
};

/// Lower-case extensions (no dot) for every [FileKind] except
/// [FileKind.generic]. An extension must appear under at most one kind
/// (checked by a test); anything absent is [FileKind.generic].
const Map<FileKind, Set<String>> fileKindExtensions = {
  FileKind.pdf: {'pdf'},
  FileKind.image: {
    'jpg', 'jpeg', 'jpe', 'jfif', 'png', 'gif', 'avif', 'heic', 'heif', 'webp',
    'bmp', 'svg', 'tif', 'tiff', 'ico', 'jxl', 'psd',
    // Camera raw
    'dng', 'cr2', 'cr3', 'nef', 'arw', 'orf', 'rw2', 'raf',
  },
  FileKind.video: videoFileExtensions,
  FileKind.audio: audioFileExtensions,
  FileKind.document: {
    'doc', 'docx', 'docm', 'dot', 'dotx', 'odt', 'ott', 'rtf', 'pages', 'wpd',
    'wps',
  },
  FileKind.spreadsheet: {
    'xls', 'xlsx', 'xlsm', 'xlsb', 'xlt', 'xltx', 'ods', 'ots', 'numbers',
    'csv', 'tsv',
  },
  FileKind.presentation: {
    'ppt', 'pptx', 'pptm', 'pps', 'ppsx', 'pot', 'potx', 'odp', 'otp',
  },
  FileKind.text: {
    'txt', 'md', 'markdown', 'log', 'nfo', 'rst', 'tex', 'lrc',
    // Subtitles
    'srt', 'vtt', 'ass', 'ssa', 'sub',
  },
  FileKind.code: {
    // Data / config / markup
    'json', 'jsonl', 'xml', 'yaml', 'yml', 'toml', 'ini', 'cfg', 'conf',
    'properties', 'ipynb', 'proto',
    // Stylesheets / scripts / source
    'css', 'scss', 'less', 'js', 'mjs', 'cjs', 'jsx', 'ts', 'tsx', 'vue',
    'svelte', 'dart', 'kt', 'kts', 'java', 'gradle', 'c', 'h', 'cpp', 'cc',
    'cxx', 'hpp', 'cs', 'go', 'rs', 'py', 'rb', 'php', 'swift', 'lua', 'pl',
    'r', 'sql', 'sh', 'bash', 'zsh', 'bat', 'cmd', 'ps1',
  },
  FileKind.web: {'html', 'htm', 'xhtml', 'mhtml', 'mht'},
  FileKind.archive: {
    'zip', 'zipx', 'gz', 'tar', '7z', 'rar', 'bz2', 'xz', 'zst', 'tgz', 'tbz',
    'tbz2', 'txz', 'lz', 'lzma', 'lz4', 'z', 'cab', 'arj', 'jar',
  },
  FileKind.ebook: {'epub', 'mobi', 'azw', 'azw3', 'fb2', 'djvu', 'cbz', 'cbr'},
  FileKind.font: {'ttf', 'otf', 'ttc', 'woff', 'woff2', 'eot'},
  FileKind.database: {'db', 'db3', 'sqlite', 'sqlite3', 'mdb', 'accdb'},
  // Certificates, key stores and password databases. `key` is left out on
  // purpose: it is also Apple Keynote's extension.
  FileKind.keyFile: {
    'pem', 'crt', 'cer', 'der', 'pfx', 'p12', 'jks', 'kdbx', 'kdb',
  },
  // Files the Single File Crypto tool writes (`.vxenc`, `.aes`; see
  // [isAppEncryptedFileName]) plus PGP-encrypted files.
  FileKind.encrypted: {'vxenc', 'aes', 'gpg', 'pgp'},
  FileKind.apk: {'apk', 'apks', 'xapk', 'apkm', 'aab'},
};

/// extension -> kind, built once from [fileKindExtensions].
final Map<String, FileKind> _kindByExtension = {
  for (final entry in fileKindExtensions.entries)
    for (final ext in entry.value) ext: entry.key,
};

/// Classifies [name] by its extension, case-insensitively. Names with no
/// extension, or an unrecognised one, are [FileKind.generic].
FileKind fileKindOf(String name) {
  final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
  return _kindByExtension[ext] ?? FileKind.generic;
}

/// Returns the appropriate [IconData] for a file based on its extension.
IconData iconForFile(String name) => switch (fileKindOf(name)) {
  FileKind.pdf => Icons.picture_as_pdf_outlined,
  FileKind.image => Icons.image_outlined,
  FileKind.video => Icons.ondemand_video_outlined,
  FileKind.audio => Icons.audio_file_outlined,
  FileKind.document => Icons.description_outlined,
  FileKind.spreadsheet => Icons.table_chart_outlined,
  FileKind.presentation => Icons.slideshow_outlined,
  FileKind.text => Icons.article_outlined,
  FileKind.code => Icons.code_rounded,
  FileKind.web => Icons.language_rounded,
  FileKind.archive => Icons.archive_outlined,
  FileKind.ebook => Icons.menu_book_outlined,
  FileKind.font => Icons.font_download_outlined,
  FileKind.database => Icons.storage_outlined,
  FileKind.keyFile => Icons.key_outlined,
  FileKind.encrypted => Icons.lock_outlined,
  FileKind.apk => Icons.android_rounded,
  FileKind.generic => Icons.insert_drive_file_outlined,
};

/// Returns the accent [Color] for a file based on its extension.
Color colorForFile(String name) => switch (fileKindOf(name)) {
  FileKind.pdf => const Color(0xFFEF5350),
  FileKind.image => const Color(0xFF26C6DA),
  FileKind.video => const Color(0xFF7E57C2),
  FileKind.audio => const Color(0xFF66BB6A),
  FileKind.document => const Color(0xFF42A5F5),
  FileKind.spreadsheet => const Color(0xFF43A047),
  FileKind.presentation => const Color(0xFFEC407A),
  FileKind.text => const Color(0xFF78909C),
  FileKind.code => const Color(0xFF26A69A),
  FileKind.web => const Color(0xFFFF7043),
  FileKind.archive => const Color(0xFFFF8F00), // Amber for archives
  FileKind.ebook => const Color(0xFF8D6E63),
  FileKind.font => const Color(0xFFAB47BC),
  FileKind.database => const Color(0xFF5C6BC0),
  FileKind.keyFile => const Color(0xFFFFCA28),
  FileKind.encrypted => const Color(0xFFA8C7FA),
  FileKind.apk => const Color(0xFF8BC34A), // Android green
  FileKind.generic => const Color(0xFF546E7A),
};

// ── Vault-item icon / colour helpers ─────────────────────────────────────────
//
// The file extension for a vault item doubles as the [VaultItemType] enum name
// (e.g. "Passwords.password" → VaultItemType.password).  Having a single
// source of truth here means a new item type only needs its icon/colour
// registered in one place, and the grid view, list view, file browser, and
// detail screen all stay in sync automatically.

/// Returns the [IconData] for a vault-item file extension, or `null` when the
/// extension does not correspond to any known vault item type.
IconData? vaultIconForExt(String ext) => switch (ext) {
  'password'        => Icons.key_rounded,
  'paymentCard'     => Icons.credit_card_rounded,
  'identity'        => Icons.badge_rounded,
  'secureNote'      => Icons.sticky_note_2_rounded,
  'bankAccount'     => Icons.account_balance_rounded,
  'softwareLicense' => Icons.computer_rounded,
  'authenticator'   => Icons.verified_user_rounded,
  _                 => null,
};

/// Returns the accent [Color] for a vault-item file extension, or `null` when
/// the extension does not correspond to any known vault item type.
Color? vaultColorForExt(String ext) => switch (ext) {
  'password'        => const Color(0xFFA8C7FA),
  'paymentCard'     => const Color(0xFF80CBC4),
  'identity'        => const Color(0xFFCE93D8),
  'secureNote'      => const Color(0xFFFFCC80),
  'bankAccount'     => const Color(0xFF80DEEA),
  'softwareLicense' => const Color(0xFFA5D6A7),
  'authenticator'   => const Color(0xFFF48FB1),
  _                 => null,
};