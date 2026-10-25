import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/utils/file_type_utils.dart';
import 'package:vaultexplorer/core/utils/skin_icons.dart';
import 'package:vaultexplorer/data/models/file_manager_skin.dart';

/// Font family used for [FileManagerSkin.monospaceNames]. Bundled in
/// pubspec.yaml and already used by the text editor.
const String kSkinMonospaceFontFamily = 'JetBrains Mono';

/// Makes a [FileManagerSkin] available to every file and folder tile below it.
///
/// A scope, rather than one more constructor argument on each of the list,
/// grid, masonry, tile and shell widgets, so the skin reaches all of them from
/// a single place and only the tiles that actually read it rebuild when it
/// changes.
///
/// Tiles shown outside any scope (for example the decoy destination picker)
/// simply get [FileManagerSkin.classic], i.e. the look they always had.
class FileManagerSkinScope extends InheritedWidget {
  final FileManagerSkin skin;

  const FileManagerSkinScope({
    super.key,
    required this.skin,
    required super.child,
  });

  static FileManagerSkin of(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<FileManagerSkinScope>()
          ?.skin ??
      FileManagerSkin.classic;

  /// The skin in effect above [context] without subscribing to it, or null
  /// outside any scope. For tools that inspect an element once.
  static FileManagerSkin? peek(BuildContext context) => context
      .getInheritedWidgetOfExactType<FileManagerSkinScope>()
      ?.skin;

  @override
  bool updateShouldNotify(FileManagerSkinScope oldWidget) =>
      skin != oldWidget.skin;
}

Color _resolveIconColor(SkinItemStyle style, ColorScheme cs, Color autoColor) =>
    switch (style.iconColorMode) {
      SkinIconColorMode.auto => autoColor,
      SkinIconColorMode.primary => cs.primary,
      SkinIconColorMode.neutral => cs.onSurfaceVariant,
      SkinIconColorMode.custom => style.customIconColor ?? autoColor,
    };

/// Turns a skin's stored choices into the concrete icon, color and text style
/// a tile should paint.
extension FileManagerSkinResolution on FileManagerSkin {
  /// The style that applies to folders ([isDir]) or files.
  SkinItemStyle styleFor({required bool isDir}) => isDir ? folders : files;

  IconData get folderIcon => SkinIcons.folder(folders.iconFamily);

  IconData fileIcon(String name) => SkinIcons.file(files.iconFamily, name);

  /// Resting (unselected) color of a folder icon.
  Color folderIconColor(ColorScheme cs) =>
      _resolveIconColor(folders, cs, cs.secondary);

  /// Resting (unselected) color of the icon for the file called [name].
  Color fileIconColor(ColorScheme cs, String name) {
    final ext = name.split('.').last;
    final auto = vaultColorForExt(ext) ?? colorForFile(name);
    return _resolveIconColor(files, cs, auto);
  }

  /// [base] with this skin's name color and font applied. Fields the skin
  /// leaves unset keep whatever [base] already had.
  TextStyle? nameStyle(TextStyle? base, {required bool isDir}) {
    if (base == null) return null;
    return base.copyWith(
      color: styleFor(isDir: isDir).nameColor,
      fontFamily: monospaceNames ? kSkinMonospaceFontFamily : null,
    );
  }
}
