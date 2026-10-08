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

/// Lower-case extensions (no dot) shown with the music/audio icon.
///
/// Single source of truth for [iconForFile], [colorForFile] and
/// `SkinIcons.glyphForFile`, so the three can never disagree about what
/// counts as music. Deliberately independent of the in-app player's
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
/// `ts` is intentionally absent: MPEG transport streams share it with
/// TypeScript source files, and a code file must not get a video icon.
const Set<String> videoFileExtensions = {
  'mp4', 'm4v', 'webm', 'mov', 'qt', 'avi', 'mkv', 'mpeg', 'mpg', 'mpe',
  'flv', 'f4v', 'wmv', 'asf', '3gp', '3g2', 'vob', 'ogv', 'ogm', 'divx',
  'm2ts', 'mts', 'm2v', 'rm', 'rmvb', 'mxf',
};

/// Returns the appropriate [IconData] for a file based on its extension.
IconData iconForFile(String name) {
  final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
  if (videoFileExtensions.contains(ext)) return Icons.ondemand_video_outlined;
  if (audioFileExtensions.contains(ext)) return Icons.audio_file_outlined;
  switch (ext) {
    case 'pdf':
      return Icons.picture_as_pdf_outlined;
    case 'jpg':
    case 'jpeg':
    case 'png':
    case 'gif':
    case 'avif':
    case 'heic':
    case 'webp':
      return Icons.image_outlined;
    case 'txt':
    case 'md':
    case 'csv':
      return Icons.article_outlined;
    case 'html':
    case 'htm':
      return Icons.language_rounded;
    case 'zip':
    case 'gz':
    case 'tar':
    case '7z':
    case 'rar':
      return Icons.archive_outlined;
    case 'apk':
      return Icons.android_rounded;
    default:
      return Icons.insert_drive_file_outlined;
  }
}

/// Returns the accent [Color] for a file based on its extension.
Color colorForFile(String name) {
  final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
  if (videoFileExtensions.contains(ext)) return const Color(0xFF7E57C2);
  if (audioFileExtensions.contains(ext)) return const Color(0xFF66BB6A);
  switch (ext) {
    case 'pdf':
      return const Color(0xFFEF5350);
    case 'jpg':
    case 'jpeg':
    case 'png':
    case 'gif':
    case 'avif':
    case 'webp':
      return const Color(0xFF26C6DA);
    case 'txt':
    case 'md':
    case 'csv':
      return const Color(0xFF78909C);
    case 'html':
    case 'htm':
      return const Color(0xFFFF7043);
    case 'zip':
    case 'gz':
    case 'tar':
    case '7z':
    case 'rar':
    case 'bz2':
    case 'xz':
      return const Color(0xFFFF8F00); // Amber for archives
    case 'apk':
      return const Color(0xFF8BC34A); // Android green
    default:
      return const Color(0xFF546E7A);
  }
}

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