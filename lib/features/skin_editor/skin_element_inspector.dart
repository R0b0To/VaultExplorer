import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:material_ui/material_ui.dart';
import 'package:re_editor/re_editor.dart' show CodeTextColorProbe;
import 'package:vaultexplorer/core/theme/file_manager_skin_scope.dart';
import 'package:vaultexplorer/core/theme/skin/skin_area.dart';
import 'package:vaultexplorer/core/theme/skin/skin_area_scope.dart';
import 'package:vaultexplorer/core/widgets/feedback/inline_banner.dart';
import 'package:vaultexplorer/data/models/custom_app_skin.dart';
import 'package:vaultexplorer/data/models/file_manager_skin.dart';
import 'package:vaultexplorer/features/browser/widgets/grid_card_shell.dart';
import 'package:vaultexplorer/features/browser/widgets/tile_selection_style.dart';
import 'package:vaultexplorer/features/skin_editor/skin_target.dart';

/// What a painted layer is, which decides which colors it can be.
enum SkinLayerKind { text, fill, line }

/// One thing painted at the tapped point (a piece of text, a card fill, a
/// divider, ...) together with the skin colors it could be coming from.
@immutable
class SkinLayer {
  final SkinLayerKind kind;

  /// The color that was actually painted.
  final Color color;

  /// Where it was painted, in global coordinates.
  final Rect rect;

  /// The skin colors this layer matches, most likely first. Never empty.
  final List<SkinTarget> candidates;

  /// True when no skin color matched exactly and [candidates] are only the
  /// nearest ones (a tinted or translucent paint, for example).
  final bool approximate;

  const SkinLayer({
    required this.kind,
    required this.color,
    required this.rect,
    required this.candidates,
    required this.approximate,
  });
}

/// The outcome of tapping a point in the app.
@immutable
class SkinPickResult {
  /// The page the tap landed on, or null for a screen that uses the shared
  /// palette (unlock, camera, ...).
  final SkinArea? area;

  /// What is painted there, most specific first. Empty when nothing painted
  /// there maps to a skin color.
  final List<SkinLayer> layers;

  const SkinPickResult({required this.area, required this.layers});

  static const empty = SkinPickResult(area: null, layers: []);
}

/// Finds out which skin colors are painted at [globalPosition].
///
/// This is the same idea as Flutter's widget inspector, but it asks "which
/// color is this?" instead of "which widget is this?". It hit-tests the app
/// (not the picker's own controls), looks at what each hit element paints
/// (text color, box fill, border) and matches those colors against every
/// color the skin can set. Nothing in the app has to be tagged, and new
/// screens work automatically as long as they take their colors from the
/// theme.
///
/// [appContext] is the context of the subtree that holds the whole app. The
/// skin colors are compared as they currently look ([skin] in [base]), so an
/// element that was just recolored is still recognized.
SkinPickResult inspectSkinElementAt({
  required BuildContext appContext,
  required Offset globalPosition,
  required ThemeData base,
  required CustomAppSkin skin,
  required bool dark,
}) {
  final root = appContext as Element;
  final appBox = root.renderObject;
  if (appBox is! RenderBox || !appBox.hasSize || !appBox.attached) {
    return SkinPickResult.empty;
  }

  final hit = BoxHitTestResult();
  appBox.hitTest(hit, position: appBox.globalToLocal(globalPosition));

  final owners = _renderObjectOwners(root);
  Element? deepest;
  var sawEditorCanvas = false;
  final raws = <_RawLayer>[];
  for (final entry in hit.path) {
    final target = entry.target;
    if (target is! RenderBox || !target.attached || !target.hasSize) continue;
    final owner = owners[target];
    if (owner == null) continue;
    deepest ??= owner;
    final rect = target.localToGlobal(Offset.zero) & target.size;
    _collectLayers(owner, rect, raws);
  // The code canvas and its line numbers paint straight onto a canvas, so
    // their text color has to be asked for rather than read from a widget.
    if (target case final CodeTextColorProbe probe) {
      final color = probe.textColorAt(globalPosition);
      if (color != null && color.a != 0) {
        sawEditorCanvas = true;
        raws.add(_RawLayer(SkinLayerKind.text, color, rect, owner));
      }
    }
  }
  if (deepest == null) return SkinPickResult.empty;

  var area =
      SkinAreaHint.peek(deepest) ?? SkinAreaScope.peekColorsOf(deepest)?.area;
  if (sawEditorCanvas) area ??= SkinArea.editor;
  final table = <(SkinTarget, Color)>[
    for (final target in skinMatchTargets(area))
      (target, target.current(skin, base, dark: dark)),
  ];

  final layers = <SkinLayer>[];
  final seen = <String>{};
  final perKind = <SkinLayerKind, int>{};
  const limits = {
    SkinLayerKind.text: 1,
    SkinLayerKind.fill: 4,
    SkinLayerKind.line: 1,
  };
  for (final raw in raws) {
    final key = '${raw.kind.index}:${raw.color.toARGB32()}';
    if (!seen.add(key)) continue;
    if ((perKind[raw.kind] ?? 0) >= limits[raw.kind]!) continue;
    final match = matchSkinColor(
      color: raw.color,
      kind: raw.kind,
      table: table,
      hints: _ancestorHints(raw.element),
    );
    // Inside a file or folder row the icon, the name and the date/size line
    // each have a color of their own in the skin, which a plain color match
    // could not tell apart from the page's text colors.
    final fileItem = _fileItemOf(raw.element);
    final forced = fileItem == null
        ? const <SkinTarget>[]
        : _fileItemTargets(raw, fileItem);
    final targets = [
      ...forced,
      ...match.targets.where((target) => !forced.contains(target)),
    ];
    if (targets.isEmpty) continue;
    perKind[raw.kind] = (perKind[raw.kind] ?? 0) + 1;
    layers.add(
      SkinLayer(
        kind: raw.kind,
        color: raw.color,
        rect: raw.rect,
        candidates: targets,
        approximate: forced.isEmpty && match.approximate,
      ),
    );
  }

  // Text first (what the person most likely pointed at), then borders, then
  // the stack of fills from the most specific container outwards.
  int order(SkinLayerKind kind) => switch (kind) {
    SkinLayerKind.text => 0,
    SkinLayerKind.line => 1,
    SkinLayerKind.fill => 2,
  };
  final indexed = layers.indexed.toList()
    ..sort((a, b) {
      final byKind = order(a.$2.kind).compareTo(order(b.$2.kind));
      return byKind != 0 ? byKind : a.$1.compareTo(b.$1);
    });
  return SkinPickResult(area: area, layers: [for (final e in indexed) e.$2]);
}

/// The result of matching one painted color against the skin's colors.
typedef SkinColorMatch = ({List<SkinTarget> targets, bool approximate});

/// Matches [color] against [table] (every skin color with its current value).
///
/// An exact match wins; otherwise the same color with a different opacity;
/// otherwise the nearest colors, flagged as approximate. Ties are broken by
/// what makes sense for [kind] (text colors before fills for a glyph, and so
/// on) and by [hints] from the surrounding widgets.
SkinColorMatch matchSkinColor({
  required Color color,
  required SkinLayerKind kind,
  required List<(SkinTarget, Color)> table,
  Set<SkinToken> hints = const {},
}) {
  final argb = color.toARGB32();
  List<SkinTarget> ranked(Iterable<SkinTarget> targets) {
    final list = targets.toList();
    final scores = {for (final t in list) t: _rank(t, kind, hints)};
    list.sort((a, b) => scores[a]!.compareTo(scores[b]!));
    return list;
  }

  final exact = [
    for (final (target, value) in table)
      if (value.toARGB32() == argb) target,
  ];
  if (exact.isNotEmpty) return (targets: ranked(exact), approximate: false);

  final rgb = argb & 0xFFFFFF;
  final sameHue = [
    for (final (target, value) in table)
      if ((value.toARGB32() & 0xFFFFFF) == rgb) target,
  ];
  if (sameHue.isNotEmpty) {
    return (targets: ranked(sameHue), approximate: true);
  }

  final scored = [
    for (final (target, value) in table) (target, _distance(color, value)),
  ]..sort((a, b) => a.$2.compareTo(b.$2));
  if (scored.isEmpty || scored.first.$2 > _nearThreshold) {
    return (targets: const <SkinTarget>[], approximate: true);
  }
  final cutoff = math.min(_nearThreshold, scored.first.$2 + 4);
  return (
    targets: ranked([
      for (final (target, distance) in scored)
        if (distance <= cutoff) target,
    ]),
    approximate: true,
  );
}

/// How far (in 0-255 RGB units) a painted color may be from a skin color and
/// still be offered as "closest match".
const double _nearThreshold = 28;

double _distance(Color a, Color b) {
  final x = a.toARGB32();
  final y = b.toARGB32();
  final dr = ((x >> 16) & 0xFF) - ((y >> 16) & 0xFF);
  final dg = ((x >> 8) & 0xFF) - ((y >> 8) & 0xFF);
  final db = (x & 0xFF) - (y & 0xFF);
  return math.sqrt((dr * dr + dg * dg + db * db).toDouble());
}

// Which page tokens are the likely owner of a color, per kind of layer. Used
// only to order tied candidates, never to exclude one. Because the picker
// identifies a token by the color it sees, two tokens that happen to share a
// default color are told apart only by this order and by [_ancestorHints].
const _textOrder = [
  SkinToken.contentPrimary,
  SkinToken.contentSecondary,
  SkinToken.contentIcon,
  SkinToken.chromeOnTopBar,
  SkinToken.actionOnPrimary,
  SkinToken.actionOnTonal,
  SkinToken.actionText,
  SkinToken.selectionOn,
  SkinToken.choiceOnSelected,
  SkinToken.controlOnActive,
  SkinToken.floatingOnFab,
  SkinToken.overlayOnMenu,
  SkinToken.overlayOnDialog,
  SkinToken.overlayOnSheet,
  SkinToken.floatingOnToast,
  SkinToken.floatingOnTooltip,
  SkinToken.accentPrimary,
  SkinToken.accentSecondary,
  SkinToken.accentTertiary,
  SkinToken.accentOnTertiaryContainer,
  SkinToken.statusDanger,
  SkinToken.statusOnDanger,
  SkinToken.statusOnDangerContainer,
  SkinToken.statusOnInfo,
];
const _fillOrder = [
  SkinToken.surfaceCard,
  SkinToken.surfacePage,
  SkinToken.chromeTopBar,
  SkinToken.surfaceTile,
  SkinToken.surfaceField,
  SkinToken.selectionFill,
  SkinToken.surfaceCardActive,
  SkinToken.actionPrimary,
  SkinToken.actionTonal,
  SkinToken.choiceBackground,
  SkinToken.choiceSelected,
  SkinToken.controlActive,
  SkinToken.controlTrack,
  SkinToken.overlayMenu,
  SkinToken.overlayDialog,
  SkinToken.overlaySheet,
  SkinToken.floatingFab,
  SkinToken.floatingToast,
  SkinToken.floatingTooltip,
  SkinToken.surfacePanel,
  SkinToken.chromeBar,
  SkinToken.accentTertiaryContainer,
  SkinToken.statusDangerContainer,
  SkinToken.statusInfo,
];
const _lineOrder = [
  SkinToken.borderDivider,
  SkinToken.borderOutline,
  SkinToken.borderFocus,
  SkinToken.choiceBorder,
  SkinToken.controlInactive,
];

int _rank(SkinTarget target, SkinLayerKind kind, Set<SkinToken> hints) {
  if (target is AreaTokenTarget) {
    final order = switch (kind) {
      SkinLayerKind.text => _textOrder,
      SkinLayerKind.fill => _fillOrder,
      SkinLayerKind.line => _lineOrder,
    };
    final index = order.indexOf(target.token);
    var rank = index < 0 ? 40 : index;
    if (hints.contains(target.token)) rank -= 30;
    return rank;
  }
  return switch (target) {
    EditorRoleTarget() => 60,
    SchemeRoleTarget() => 70,
    ComponentRoleTarget() => 80,
    SemanticRoleTarget() => 90,
    FileItemTarget() => 20,
    AreaTokenTarget() => 40,
  };
}

/// Page tokens that the widgets around [element] make more likely, e.g. text
/// inside an app bar is far more likely "text on the app bar" than "text".
Set<SkinToken> _ancestorHints(Element element) {
  final hints = <SkinToken>{};
  var depth = 0;
  element.visitAncestorElements((ancestor) {
    final widget = ancestor.widget;
    if (widget is AppBar || widget is SliverAppBar) {
      hints.addAll(const {SkinToken.chromeTopBar, SkinToken.chromeOnTopBar});
    } else if (widget is FloatingActionButton) {
      hints.addAll(const {SkinToken.floatingFab, SkinToken.floatingOnFab});
    } else if (widget is FilledButton) {
      hints.addAll(const {SkinToken.actionPrimary, SkinToken.actionOnPrimary});
    } else if (widget is ElevatedButton) {
      hints.addAll(const {SkinToken.actionTonal, SkinToken.actionOnTonal});
    } else if (widget is TextButton || widget is OutlinedButton) {
      hints.addAll(const {SkinToken.actionText, SkinToken.borderOutline});
    } else if (widget is Switch ||
        widget is Checkbox ||
        widget is Radio ||
        widget is Slider ||
        widget is LinearProgressIndicator ||
        widget is CircularProgressIndicator) {
      hints.addAll(const {
        SkinToken.controlActive,
        SkinToken.controlOnActive,
        SkinToken.controlTrack,
      });
    } else if (widget is Chip ||
        widget is ChoiceChip ||
        widget is FilterChip ||
        widget is SegmentedButton) {
      hints.addAll(const {
        SkinToken.choiceBackground,
        SkinToken.choiceSelected,
        SkinToken.choiceOnSelected,
      });
    } else if (widget is TextField || widget is InputDecorator) {
      hints.addAll(const {SkinToken.surfaceField, SkinToken.borderFocus});
    } else if (widget is Dialog) {
      hints.addAll(const {SkinToken.overlayDialog, SkinToken.overlayOnDialog});
    } else if (widget is BottomSheet) {
      hints.addAll(const {SkinToken.overlaySheet, SkinToken.overlayOnSheet});
    } else if (widget is PopupMenuButton || widget is MenuAnchor) {
      hints.addAll(const {SkinToken.overlayMenu, SkinToken.overlayOnMenu});
    } else if (widget is Card) {
      hints.add(SkinToken.surfacePanel);
    } else if (widget is NavigationBar || widget is BottomAppBar) {
      hints.add(SkinToken.chromeBar);
    } else if (widget is InlineBanner) {
      hints.addAll(const {
        SkinToken.statusInfo,
        SkinToken.statusDangerContainer,
      });
    } else if (widget is Tooltip) {
      hints.addAll(const {
        SkinToken.floatingTooltip,
        SkinToken.floatingOnTooltip,
      });
    } else if (widget is SnackBar) {
      hints.addAll(const {SkinToken.floatingToast, SkinToken.floatingOnToast});
    }
    depth++;
    return depth < 30 && hints.length < 4;
  });
  return hints;
}

class _RawLayer {
  final SkinLayerKind kind;
  final Color color;
  final Rect rect;
  final Element element;

  /// A text layer that is really an icon glyph.
  final bool isIcon;

  const _RawLayer(
    this.kind,
    this.color,
    this.rect,
    this.element, {
    this.isIcon = false,
  });
}

void _collectLayers(Element element, Rect rect, List<_RawLayer> out) {
  void add(SkinLayerKind kind, Color? color, {bool isIcon = false}) {
    if (color == null || color.a == 0) return;
    out.add(_RawLayer(kind, color, rect, element, isIcon: isIcon));
  }

  final widget = element.widget;
  if (widget is RichText) {
    final span = widget.text;
    add(SkinLayerKind.text, span.style?.color, isIcon: _isIconGlyph(span));
  } else if (widget is DecoratedBox) {
    final decoration = widget.decoration;
    if (decoration is BoxDecoration) {
      add(SkinLayerKind.fill, decoration.color);
      final border = decoration.border;
      if (border is Border) {
        for (final side in [
          border.bottom,
          border.top,
          border.left,
          border.right,
        ]) {
          if (side.style != BorderStyle.none && side.width > 0) {
            add(SkinLayerKind.line, side.color);
            break;
          }
        }
      }
    } else if (decoration is ShapeDecoration) {
      add(SkinLayerKind.fill, decoration.color);
    }
  } else if (widget is ColoredBox) {
    add(SkinLayerKind.fill, widget.color);
  } else if (widget is PhysicalModel) {
    add(SkinLayerKind.fill, widget.color);
  } else if (widget is PhysicalShape) {
    add(SkinLayerKind.fill, widget.color);
  }
}

/// Icons are drawn as one private-use character in an icon font.
bool _isIconGlyph(InlineSpan span) {
  if (span is! TextSpan) return false;
  final text = span.text;
  if (text == null || text.isEmpty || span.style?.fontFamily == null) {
    return false;
  }
  final runes = text.runes;
  if (runes.length != 1) return false;
  final rune = runes.first;
  return (rune >= 0xE000 && rune <= 0xF8FF) || rune >= 0xF0000;
}

/// The file or folder row (list, grid or masonry) that an element is part of.
class _FileItemContext {
  final bool isDir;
  final String name;
  final FileManagerSkin skin;
  final ColorScheme scheme;

  const _FileItemContext({
    required this.isDir,
    required this.name,
    required this.skin,
    required this.scheme,
  });
}

_FileItemContext? _fileItemOf(Element element) {
  bool? isDir;
  String? name;
  var depth = 0;
  element.visitAncestorElements((ancestor) {
    final widget = ancestor.widget;
    if (widget is FileRowShell) {
      isDir = widget.entry.isDir;
      name = widget.entry.name;
      return false;
    }
    if (widget is GridCardShell) {
      isDir = widget.isFolder;
      name = widget.label;
      return false;
    }
    depth++;
    return depth < 40;
  });
  final dir = isDir;
  final label = name;
  if (dir == null || label == null) return null;
  return _FileItemContext(
    isDir: dir,
    name: label,
    skin: FileManagerSkinScope.peek(element) ?? FileManagerSkin.classic,
    scheme: Theme.of(element).colorScheme,
  );
}

/// The file manager skin colors a painted layer inside a row can be: the icon
/// when it has exactly the color the skin gives this entry's icon, otherwise
/// the date/size line when it matches the details color, otherwise the name.
List<SkinTarget> _fileItemTargets(_RawLayer raw, _FileItemContext item) {
  if (raw.kind != SkinLayerKind.text) return const [];
  if (raw.isIcon) {
    final expected = item.isDir
        ? item.skin.folderIconColor(item.scheme)
        : item.skin.fileIconColor(item.scheme, item.name);
    if (expected.toARGB32() != raw.color.toARGB32()) return const [];
    return [
      FileItemTarget(
        item.isDir ? FileItemPart.folderIcon : FileItemPart.fileIcon,
      ),
    ];
  }
  final details =
      (item.skin.detailsColor ?? item.scheme.onSurfaceVariant).toARGB32() &
      0xFFFFFF;
  if ((raw.color.toARGB32() & 0xFFFFFF) == details) {
    return const [FileItemTarget(FileItemPart.details)];
  }
  return [
    FileItemTarget(
      item.isDir ? FileItemPart.folderName : FileItemPart.fileName,
    ),
  ];
}

/// Maps every render object under [root] to the element that owns it, so a
/// hit-test result (which only knows render objects) can be turned back into
/// widgets. One walk per tap; nothing is kept between taps.
Map<RenderObject, Element> _renderObjectOwners(Element root) {
  final owners = <RenderObject, Element>{};
  final stack = <Element>[root];
  while (stack.isNotEmpty) {
    final element = stack.removeLast();
    if (element is RenderObjectElement) {
      owners[element.renderObject] = element;
    }
    element.visitChildren(stack.add);
  }
  return owners;
}
