import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/theme/file_manager_skin_scope.dart';
import 'package:vaultexplorer/core/utils/file_type_utils.dart';
import 'package:vaultexplorer/core/utils/skin_icons.dart';
import 'package:vaultexplorer/data/models/file_manager_skin.dart';

/// Every extension [iconForFile] gives a dedicated icon, plus a few it does
/// not (so the fallback is exercised too).
const _extensions = [
  'pdf',
  'jpg', 'jpeg', 'png', 'gif', 'avif', 'heic', 'webp',
  'mp4', 'mov', 'avi', 'mkv', 'webm', 'm4v', 'mpeg', 'mpg',
  'mp3', 'flac', 'wav', 'm4a',
  'ogg', 'opus', 'wma', 'ac3', 'aiff', 'amr', // added audio
  'wmv', 'flv', '3gp', // added video
  'ts', // deliberately NOT video (TypeScript)
  'txt', 'md', 'csv',
  'html', 'htm',
  'zip', 'gz', 'tar', '7z', 'rar',
  'apk',
  'bz2', 'xz', 'xyz', // no dedicated icon today
];

const _vaultExts = [
  'password',
  'paymentCard',
  'identity',
  'secureNote',
  'bankAccount',
  'softwareLicense',
  'authenticator',
];

void main() {
  group('SkinIcons classic family', () {
    test('folder is the app\'s original rounded folder', () {
      expect(SkinIcons.folder(SkinIconFamily.classic), Icons.folder_rounded);
    });

    test('files resolve exactly as before skins existed', () {
      for (final ext in _extensions) {
        final name = 'file.$ext';
        expect(
          SkinIcons.file(SkinIconFamily.classic, name),
          vaultIconForExt(name.split('.').last) ?? iconForFile(name),
          reason: name,
        );
      }
      for (final ext in _vaultExts) {
        final name = 'item.$ext';
        expect(
          SkinIcons.file(SkinIconFamily.classic, name),
          vaultIconForExt(ext),
          reason: name,
        );
      }
    });
  });

  group('SkinIcons glyph tables', () {
    test('every glyph has four distinct variants', () {
      for (final glyph in FileGlyph.values) {
        final variants = SkinIcons.variantsOf(glyph);
        expect(variants, hasLength(4), reason: glyph.name);
        expect(variants.toSet(), hasLength(4), reason: glyph.name);
      }
    });

    test('glyphForFile agrees with iconForFile on which glyph a file gets', () {
      // Guards against someone teaching iconForFile a new extension without
      // teaching glyphForFile, which would make non-classic skins show a
      // different kind of icon than classic.
      for (final ext in _extensions) {
        final name = 'file.$ext';
        expect(
          SkinIcons.variantsOf(SkinIcons.glyphForFile(name)),
          contains(iconForFile(name)),
          reason: name,
        );
      }
    });

    test('vaultGlyphForExt agrees with vaultIconForExt', () {
      for (final ext in _vaultExts) {
        final glyph = SkinIcons.vaultGlyphForExt(ext);
        expect(glyph, isNotNull, reason: ext);
        expect(
          SkinIcons.variantsOf(glyph!),
          contains(vaultIconForExt(ext)),
          reason: ext,
        );
      }
      expect(SkinIcons.vaultGlyphForExt('pdf'), isNull);
      expect(vaultIconForExt('pdf'), isNull);
    });

    test('extension matching ignores case for files but not vault items', () {
      expect(
        SkinIcons.file(SkinIconFamily.outlined, 'PHOTO.JPG'),
        Icons.image_outlined,
      );
      // Vault item extensions are camelCase enum names; the existing
      // browser code matches them case-sensitively, and so does this.
      expect(
        SkinIcons.file(SkinIconFamily.outlined, 'card.paymentCard'),
        Icons.credit_card_outlined,
      );
      expect(
        SkinIcons.file(SkinIconFamily.outlined, 'card.paymentcard'),
        Icons.insert_drive_file_outlined,
      );
    });

    test('a name with no extension gets the generic file glyph', () {
      expect(SkinIcons.glyphForFile('README'), FileGlyph.generic);
      expect(SkinIcons.glyphForFile(''), FileGlyph.generic);
    });
  });

  group('SkinIcons families', () {
    test('folder icons come from the requested family', () {
      expect(SkinIcons.folder(SkinIconFamily.filled), Icons.folder);
      expect(SkinIcons.folder(SkinIconFamily.rounded), Icons.folder_rounded);
      expect(SkinIcons.folder(SkinIconFamily.outlined), Icons.folder_outlined);
      expect(SkinIcons.folder(SkinIconFamily.sharp), Icons.folder_sharp);
    });

    test('file icons come from the requested family', () {
      expect(
        SkinIcons.file(SkinIconFamily.filled, 'a.pdf'),
        Icons.picture_as_pdf,
      );
      expect(
        SkinIcons.file(SkinIconFamily.rounded, 'a.pdf'),
        Icons.picture_as_pdf_rounded,
      );
      expect(
        SkinIcons.file(SkinIconFamily.outlined, 'a.pdf'),
        Icons.picture_as_pdf_outlined,
      );
      expect(
        SkinIcons.file(SkinIconFamily.sharp, 'a.pdf'),
        Icons.picture_as_pdf_sharp,
      );
    });

    test('switching family changes the style, never the kind of icon', () {
      for (final ext in [..._extensions, ..._vaultExts]) {
        final name = 'file.$ext';
        final glyphs = <FileGlyph>{};
        for (final family in [
          SkinIconFamily.filled,
          SkinIconFamily.rounded,
          SkinIconFamily.outlined,
          SkinIconFamily.sharp,
        ]) {
          final icon = SkinIcons.file(family, name);
          final owner = FileGlyph.values.singleWhere(
            (g) => SkinIcons.variantsOf(g).contains(icon),
            orElse: () => throw StateError('$icon belongs to no glyph'),
          );
          glyphs.add(owner);
        }
        expect(glyphs, hasLength(1), reason: name);
      }
    });
  });

  group('FileManagerSkinResolution', () {
    final cs = ColorScheme.fromSeed(seedColor: const Color(0xFF3366CC));

    test('classic resolves to the pre-skin icons and colors', () {
      const skin = FileManagerSkin.classic;
      expect(skin.folderIcon, Icons.folder_rounded);
      expect(skin.folderIconColor(cs), cs.secondary);
      expect(skin.fileIcon('a.pdf'), iconForFile('a.pdf'));
      expect(skin.fileIconColor(cs, 'a.pdf'), colorForFile('a.pdf'));
      expect(skin.fileIconColor(cs, 'a.zip'), colorForFile('a.zip'));
    });

    test('classic uses the vault palette for vault items', () {
      const skin = FileManagerSkin.classic;
      expect(
        skin.fileIconColor(cs, 'x.password'),
        vaultColorForExt('password'),
      );
      expect(skin.fileIcon('x.password'), vaultIconForExt('password'));
    });

    test('each icon color mode resolves as documented', () {
      FileManagerSkin withMode(SkinIconColorMode mode, {Color? custom}) =>
          FileManagerSkin(
            files: SkinItemStyle(iconColorMode: mode, customIconColor: custom),
            folders:
                SkinItemStyle(iconColorMode: mode, customIconColor: custom),
          );

      final primary = withMode(SkinIconColorMode.primary);
      expect(primary.fileIconColor(cs, 'a.pdf'), cs.primary);
      expect(primary.folderIconColor(cs), cs.primary);

      final neutral = withMode(SkinIconColorMode.neutral);
      expect(neutral.fileIconColor(cs, 'a.pdf'), cs.onSurfaceVariant);
      expect(neutral.folderIconColor(cs), cs.onSurfaceVariant);

      const pink = Color(0xFFEC407A);
      final custom = withMode(SkinIconColorMode.custom, custom: pink);
      expect(custom.fileIconColor(cs, 'a.pdf'), pink);
      expect(custom.folderIconColor(cs), pink);
    });

    test('custom mode with no color chosen falls back to automatic', () {
      const skin = FileManagerSkin(
        files: SkinItemStyle(iconColorMode: SkinIconColorMode.custom),
        folders: SkinItemStyle(iconColorMode: SkinIconColorMode.custom),
      );
      expect(skin.fileIconColor(cs, 'a.pdf'), colorForFile('a.pdf'));
      expect(skin.folderIconColor(cs), cs.secondary);
    });

    test('nameStyle keeps the base style when the skin sets nothing', () {
      const base = TextStyle(color: Color(0xFF010203), fontSize: 14);
      final out = FileManagerSkin.classic.nameStyle(base, isDir: false);
      expect(out?.color, base.color);
      expect(out?.fontSize, 14);
      expect(out?.fontFamily, isNull);
    });

    test('nameStyle applies the per-kind name color and monospace font', () {
      const skin = FileManagerSkin(
        files: SkinItemStyle(nameColor: Color(0xFFAA0000)),
        folders: SkinItemStyle(nameColor: Color(0xFF00AA00)),
        monospaceNames: true,
      );
      const base = TextStyle(color: Color(0xFF010203), fontSize: 14);

      final file = skin.nameStyle(base, isDir: false);
      final folder = skin.nameStyle(base, isDir: true);
      expect(file?.color, const Color(0xFFAA0000));
      expect(folder?.color, const Color(0xFF00AA00));
      expect(file?.fontFamily, kSkinMonospaceFontFamily);
      expect(file?.fontSize, 14);
    });

    test('nameStyle passes a null base through', () {
      expect(FileManagerSkin.classic.nameStyle(null, isDir: true), isNull);
    });
  });
}
