import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/theme/skin/skin_area.dart';
import 'package:vaultexplorer/data/models/custom_app_skin.dart';
import 'package:vaultexplorer/data/models/file_manager_skin.dart';
import 'package:vaultexplorer/features/skin_editor/skin_element_inspector.dart';
import 'package:vaultexplorer/features/skin_editor/skin_target.dart';

void main() {
  const red = Color(0xFFAA0000);
  const blue = Color(0xFF0000AA);
  const skin = CustomAppSkin();

  group('SkinTarget identity', () {
    test('targets with the same id are equal, different kinds never are', () {
      expect(
        const AreaTokenTarget(SkinArea.files, SkinToken.surfaceCard),
        const AreaTokenTarget(SkinArea.files, SkinToken.surfaceCard),
      );
      expect(
        const AreaTokenTarget(SkinArea.files, SkinToken.surfaceCard),
        isNot(const AreaTokenTarget(SkinArea.tools, SkinToken.surfaceCard)),
      );
      expect(
        const SchemeRoleTarget('primary'),
        isNot(const SemanticRoleTarget('primary')),
      );
    });
  });

  group('SkinTarget.write', () {
    test('a page token is written to one palette and one page only', () {
      const card = AreaTokenTarget(SkinArea.files, SkinToken.surfaceCard);
      final edited = card.write(skin, red, dark: false);
      expect(card.customValue(edited, dark: false), red);
      expect(card.customValue(edited, dark: true), isNull);
      expect(
        const AreaTokenTarget(SkinArea.tools, SkinToken.surfaceCard)
            .customValue(edited, dark: false),
        isNull,
      );
      expect(card.isCustom(edited, dark: false), isTrue);
    });

    test('writing null puts a page token back to inheriting', () {
      const card = AreaTokenTarget(SkinArea.files, SkinToken.surfaceCard);
      final edited = card.write(skin, red, dark: true);
      final reset = card.write(edited, null, dark: true);
      expect(card.isCustom(reset, dark: true), isFalse);
      expect(reset.darkAreaColors, isEmpty);
    });

    test('a shared palette role follows the selected brightness', () {
      const primary = SchemeRoleTarget('primary');
      final edited = primary.write(skin, red, dark: true);
      expect(edited.darkColors['primary'], red.toARGB32());
      expect(edited.lightColors, isEmpty);
      expect(primary.write(edited, null, dark: true).darkColors, isEmpty);
    });

    test('status and shared component colors have their own maps', () {
      final semantic = const SemanticRoleTarget(
        'success',
      ).write(skin, red, dark: false);
      expect(semantic.lightSemanticColors['success'], red.toARGB32());
      final component = const ComponentRoleTarget(
        'fabBackground',
      ).write(skin, blue, dark: false);
      expect(component.lightComponentColors['fabBackground'], blue.toARGB32());
    });

    test('light editor colors keep the legacy flat fields in step', () {
      const background = EditorRoleTarget('background');
      final light = background.write(skin, red, dark: false);
      expect(light.lightEditorColors['background'], red.toARGB32());
      expect(light.editorBackground, red.toARGB32());

      final dark = background.write(skin, red, dark: true);
      expect(dark.darkEditorColors['background'], red.toARGB32());
      expect(dark.editorBackground, skin.editorBackground);
    });

    test('only editor roles with a theme default can be reset', () {
      expect(const EditorRoleTarget('panel').canReset, isTrue);
      expect(const EditorRoleTarget('keyword').canReset, isTrue);
      expect(const EditorRoleTarget('background').canReset, isFalse);
    });
  });

  group('FileItemTarget', () {
    test('an icon color only counts once the skin says custom', () {
      const folderIcon = FileItemTarget(FileItemPart.folderIcon);
      expect(folderIcon.isCustom(skin, dark: false), isFalse);

      final edited = folderIcon.write(skin, red, dark: false);
      expect(
        edited.fileManagerSkin.folders.iconColorMode,
        SkinIconColorMode.custom,
      );
      expect(folderIcon.customValue(edited, dark: false), red);
      // Files are styled independently of folders.
      expect(
        const FileItemTarget(FileItemPart.fileIcon)
            .isCustom(edited, dark: false),
        isFalse,
      );
    });

    test('resetting an icon returns it to the automatic color', () {
      const fileIcon = FileItemTarget(FileItemPart.fileIcon);
      final reset = fileIcon.write(
        fileIcon.write(skin, red, dark: false),
        null,
        dark: false,
      );
      expect(reset.fileManagerSkin.files.iconColorMode, SkinIconColorMode.auto);
      expect(reset.fileManagerSkin.files.customIconColor, isNull);
    });

    test('names and the details line are set and cleared separately', () {
      const folderName = FileItemTarget(FileItemPart.folderName);
      const fileName = FileItemTarget(FileItemPart.fileName);
      const details = FileItemTarget(FileItemPart.details);

      var edited = folderName.write(skin, red, dark: false);
      edited = details.write(edited, blue, dark: false);
      expect(edited.fileManagerSkin.folders.nameColor, red);
      expect(edited.fileManagerSkin.files.nameColor, isNull);
      expect(edited.fileManagerSkin.detailsColor, blue);
      expect(fileName.isCustom(edited, dark: false), isFalse);

      edited = details.write(edited, null, dark: false);
      expect(edited.fileManagerSkin.detailsColor, isNull);
      expect(edited.fileManagerSkin.folders.nameColor, red);
    });

    test('file manager colors are the same in the light and dark palette', () {
      const fileName = FileItemTarget(FileItemPart.fileName);
      final edited = fileName.write(skin, red, dark: true);
      expect(fileName.customValue(edited, dark: false), red);
      expect(fileName.customValue(edited, dark: true), red);
    });

    test('they are offered on the Files page and nowhere else', () {
      expect(
        skinTargetsForArea(SkinArea.files).whereType<FileItemTarget>().length,
        FileItemPart.values.length,
      );
      expect(
        skinTargetsForArea(SkinArea.tools).whereType<FileItemTarget>(),
        isEmpty,
      );
    });
  });

  group('matchSkinColor', () {
    final table = <(SkinTarget, Color)>[
      (
        const AreaTokenTarget(SkinArea.files, SkinToken.chromeOnTopBar),
        const Color(0xFF111111),
      ),
      (
        const AreaTokenTarget(SkinArea.files, SkinToken.contentPrimary),
        const Color(0xFF111111),
      ),
      (
        const AreaTokenTarget(SkinArea.files, SkinToken.surfaceCard),
        const Color(0xFFEEEEEE),
      ),
      (const SchemeRoleTarget('surface'), const Color(0xFFEEEEEE)),
      (
        const AreaTokenTarget(SkinArea.files, SkinToken.actionPrimary),
        const Color(0xFF3366CC),
      ),
    ];

    test('an exact match is not approximate, page tokens before the palette', () {
      final match = matchSkinColor(
        color: const Color(0xFFEEEEEE),
        kind: SkinLayerKind.fill,
        table: table,
      );
      expect(match.approximate, isFalse);
      expect(match.targets, [
        const AreaTokenTarget(SkinArea.files, SkinToken.surfaceCard),
        const SchemeRoleTarget('surface'),
      ]);
    });

    test('tied text colors prefer plain text unless an app bar is around', () {
      final plain = matchSkinColor(
        color: const Color(0xFF111111),
        kind: SkinLayerKind.text,
        table: table,
      );
      expect(plain.targets.first, const AreaTokenTarget(SkinArea.files, SkinToken.contentPrimary));

      final inAppBar = matchSkinColor(
        color: const Color(0xFF111111),
        kind: SkinLayerKind.text,
        table: table,
        hints: const {SkinToken.chromeTopBar, SkinToken.chromeOnTopBar},
      );
      expect(
        inAppBar.targets.first,
        const AreaTokenTarget(SkinArea.files, SkinToken.chromeOnTopBar),
      );
    });

    test('the same color at another opacity matches, flagged approximate', () {
      final match = matchSkinColor(
        color: const Color(0x803366CC),
        kind: SkinLayerKind.fill,
        table: table,
      );
      expect(match.approximate, isTrue);
      expect(match.targets, [
        const AreaTokenTarget(SkinArea.files, SkinToken.actionPrimary),
      ]);
    });

    test('a slightly different color offers the nearest one', () {
      final match = matchSkinColor(
        color: const Color(0xFF3468CE),
        kind: SkinLayerKind.fill,
        table: table,
      );
      expect(match.approximate, isTrue);
      expect(match.targets, [
        const AreaTokenTarget(SkinArea.files, SkinToken.actionPrimary),
      ]);
    });

    test('a color far from everything matches nothing', () {
      final match = matchSkinColor(
        color: const Color(0xFF00FF00),
        kind: SkinLayerKind.fill,
        table: table,
      );
      expect(match.targets, isEmpty);
    });
  });
}
