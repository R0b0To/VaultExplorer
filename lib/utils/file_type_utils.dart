import 'package:flutter/material.dart';

/// Returns the appropriate [IconData] for a file based on its extension.
IconData iconForFile(String name) {
  final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
  switch (ext) {
    case 'pdf':
      return Icons.picture_as_pdf_outlined;
    case 'jpg':
    case 'jpeg':
    case 'png':
    case 'gif':
    case 'webp':
      return Icons.image_outlined;
    case 'mp4':
    case 'mov':
    case 'avi':
    case 'mkv':
    case 'webm':
    case 'm4v':
    case 'mpeg':
    case 'mpg':
      return Icons.ondemand_video_outlined;
    case 'mp3':
    case 'flac':
    case 'wav':
    case 'm4a':
      return Icons.audio_file_outlined;
    case 'txt':
    case 'md':
    case 'csv':
      return Icons.article_outlined;
    case 'zip':
    case 'gz':
    case 'tar':
    case '7z':
    case 'rar':
      return Icons.archive_outlined;
    default:
      return Icons.insert_drive_file_outlined;
  }
}

/// Returns the accent [Color] for a file based on its extension.
Color colorForFile(String name) {
  final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
  switch (ext) {
    case 'pdf':
      return const Color(0xFFEF5350);
    case 'jpg':
    case 'jpeg':
    case 'png':
    case 'gif':
    case 'webp':
      return const Color(0xFF26C6DA);
    case 'mp4':
    case 'mov':
    case 'avi':
    case 'mkv':
    case 'webm':
    case 'm4v':
    case 'mpeg':
    case 'mpg':
      return const Color(0xFF7E57C2);
    case 'mp3':
    case 'flac':
    case 'wav':
    case 'm4a':
      return const Color(0xFF66BB6A);
    case 'txt':
    case 'md':
    case 'csv':
      return const Color(0xFF78909C);
    case 'zip':
    case 'gz':
    case 'tar':
    case '7z':
    case 'rar':
    case 'bz2':
    case 'xz':
      return const Color(0xFFFF8F00); // Amber for archives
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
  _                 => null,
};