import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/utils/file_type_utils.dart';
import 'package:vaultexplorer/data/models/file_manager_skin.dart';

/// Every kind of glyph the file manager can show for an entry, independent of
/// which [SkinIconFamily] draws it.
enum FileGlyph {
  folder,
  pdf,
  image,
  video,
  audio,
  text,
  web,
  archive,
  apk,
  generic,
  // Vault-item types (see [vaultIconForExt]).
  key,
  card,
  identity,
  note,
  bank,
  license,
  authenticator,
}

/// The four Material variants of one glyph.
class _IconSet {
  final IconData filled;
  final IconData rounded;
  final IconData outlined;
  final IconData sharp;

  const _IconSet(this.filled, this.rounded, this.outlined, this.sharp);

  IconData forFamily(SkinIconFamily family) => switch (family) {
        SkinIconFamily.filled => filled,
        SkinIconFamily.rounded => rounded,
        SkinIconFamily.outlined => outlined,
        SkinIconFamily.sharp => sharp,
        // Classic is resolved by the callers below before they get here.
        // Rounded is only a defensive fallback.
        SkinIconFamily.classic => rounded,
      };
}

/// Resolves the icon to draw for a file or folder under a given
/// [SkinIconFamily].
///
/// [SkinIconFamily.classic] deliberately delegates to the pre-existing
/// [iconForFile]/[vaultIconForExt] helpers rather than to the tables below, so
/// the default skin stays identical to what the app always showed.
abstract final class SkinIcons {
  static const Map<FileGlyph, _IconSet> _sets = {
    FileGlyph.folder: _IconSet(
      Icons.folder,
      Icons.folder_rounded,
      Icons.folder_outlined,
      Icons.folder_sharp,
    ),
    FileGlyph.pdf: _IconSet(
      Icons.picture_as_pdf,
      Icons.picture_as_pdf_rounded,
      Icons.picture_as_pdf_outlined,
      Icons.picture_as_pdf_sharp,
    ),
    FileGlyph.image: _IconSet(
      Icons.image,
      Icons.image_rounded,
      Icons.image_outlined,
      Icons.image_sharp,
    ),
    FileGlyph.video: _IconSet(
      Icons.ondemand_video,
      Icons.ondemand_video_rounded,
      Icons.ondemand_video_outlined,
      Icons.ondemand_video_sharp,
    ),
    FileGlyph.audio: _IconSet(
      Icons.audio_file,
      Icons.audio_file_rounded,
      Icons.audio_file_outlined,
      Icons.audio_file_sharp,
    ),
    FileGlyph.text: _IconSet(
      Icons.article,
      Icons.article_rounded,
      Icons.article_outlined,
      Icons.article_sharp,
    ),
    FileGlyph.web: _IconSet(
      Icons.language,
      Icons.language_rounded,
      Icons.language_outlined,
      Icons.language_sharp,
    ),
    FileGlyph.archive: _IconSet(
      Icons.archive,
      Icons.archive_rounded,
      Icons.archive_outlined,
      Icons.archive_sharp,
    ),
    FileGlyph.apk: _IconSet(
      Icons.android,
      Icons.android_rounded,
      Icons.android_outlined,
      Icons.android_sharp,
    ),
    FileGlyph.generic: _IconSet(
      Icons.insert_drive_file,
      Icons.insert_drive_file_rounded,
      Icons.insert_drive_file_outlined,
      Icons.insert_drive_file_sharp,
    ),
    FileGlyph.key: _IconSet(
      Icons.key,
      Icons.key_rounded,
      Icons.key_outlined,
      Icons.key_sharp,
    ),
    FileGlyph.card: _IconSet(
      Icons.credit_card,
      Icons.credit_card_rounded,
      Icons.credit_card_outlined,
      Icons.credit_card_sharp,
    ),
    FileGlyph.identity: _IconSet(
      Icons.badge,
      Icons.badge_rounded,
      Icons.badge_outlined,
      Icons.badge_sharp,
    ),
    FileGlyph.note: _IconSet(
      Icons.sticky_note_2,
      Icons.sticky_note_2_rounded,
      Icons.sticky_note_2_outlined,
      Icons.sticky_note_2_sharp,
    ),
    FileGlyph.bank: _IconSet(
      Icons.account_balance,
      Icons.account_balance_rounded,
      Icons.account_balance_outlined,
      Icons.account_balance_sharp,
    ),
    FileGlyph.license: _IconSet(
      Icons.computer,
      Icons.computer_rounded,
      Icons.computer_outlined,
      Icons.computer_sharp,
    ),
    FileGlyph.authenticator: _IconSet(
      Icons.verified_user,
      Icons.verified_user_rounded,
      Icons.verified_user_outlined,
      Icons.verified_user_sharp,
    ),
  };

  /// Every variant of [glyph] -- used by tests to check that [glyphForFile]
  /// and [iconForFile] agree about which glyph a file gets.
  static List<IconData> variantsOf(FileGlyph glyph) {
    final set = _sets[glyph]!;
    return [set.filled, set.rounded, set.outlined, set.sharp];
  }

  static IconData _glyph(SkinIconFamily family, FileGlyph glyph) =>
      _sets[glyph]!.forFamily(family);

  /// The glyph for a folder.
  static IconData folder(SkinIconFamily family) => family ==
          SkinIconFamily.classic
      ? Icons.folder_rounded
      : _glyph(family, FileGlyph.folder);

  /// The glyph for a file, including the vault-item file types
  /// (`.password`, `.paymentCard`, ...).
  static IconData file(SkinIconFamily family, String name) {
    // Same extension the browser views use to recognise vault items: the
    // text after the last dot, case-sensitive (`paymentCard` is camelCase).
    final ext = name.split('.').last;
    if (family == SkinIconFamily.classic) {
      return vaultIconForExt(ext) ?? iconForFile(name);
    }
    return _glyph(family, vaultGlyphForExt(ext) ?? glyphForFile(name));
  }

  /// Mirrors [iconForFile]'s extension groups exactly, so switching icon
  /// family changes only the *style* of a file's icon, never which kind of
  /// icon it gets.
  static FileGlyph glyphForFile(String name) {
    final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
    if (videoFileExtensions.contains(ext)) return FileGlyph.video;
    if (audioFileExtensions.contains(ext)) return FileGlyph.audio;
    switch (ext) {
      case 'pdf':
        return FileGlyph.pdf;
      case 'jpg':
      case 'jpeg':
      case 'png':
      case 'gif':
      case 'avif':
      case 'heic':
      case 'webp':
        return FileGlyph.image;
      case 'txt':
      case 'md':
      case 'csv':
        return FileGlyph.text;
      case 'html':
      case 'htm':
        return FileGlyph.web;
      case 'zip':
      case 'gz':
      case 'tar':
      case '7z':
      case 'rar':
        return FileGlyph.archive;
      case 'apk':
        return FileGlyph.apk;
      default:
        return FileGlyph.generic;
    }
  }

  /// Mirrors [vaultIconForExt]; null when [ext] is not a vault-item type.
  static FileGlyph? vaultGlyphForExt(String ext) => switch (ext) {
        'password' => FileGlyph.key,
        'paymentCard' => FileGlyph.card,
        'identity' => FileGlyph.identity,
        'secureNote' => FileGlyph.note,
        'bankAccount' => FileGlyph.bank,
        'softwareLicense' => FileGlyph.license,
        'authenticator' => FileGlyph.authenticator,
        _ => null,
      };
}
