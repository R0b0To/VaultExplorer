import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/data/models/media_viewer_action.dart';

/// What stands for a [MediaViewerAction] wherever the viewer draws it: its
/// icon, except for the A-B repeat action, which is drawn as the text "A-B".
///
/// Every place that shows an action's icon (the bars, the More menu, the
/// toolbar customisation screen, the advanced settings sheet) goes through
/// this, so the A-B label is the same in all of them. Colour and size follow
/// the ambient [IconTheme] unless given, so it drops in wherever an [Icon]
/// was.
class MediaViewerActionGlyph extends StatelessWidget {
  const MediaViewerActionGlyph({
    super.key,
    required this.action,
    this.icon,
    this.size,
    this.color,
  });

  final MediaViewerAction action;

  /// Drawn instead of [MediaViewerAction.icon] for actions that show an icon.
  final IconData? icon;
  final double? size;
  final Color? color;

  static const String abLoopLabel = 'A-B';

  @override
  Widget build(BuildContext context) {
    if (action != MediaViewerAction.abLoop) {
      return Icon(icon ?? action.icon, size: size, color: color);
    }

    final iconTheme = IconTheme.of(context);
    final iconSize = size ?? iconTheme.size ?? 24.0;
    return Text(
      abLoopLabel,
      maxLines: 1,
      softWrap: false,
      style: TextStyle(
        color: color ?? iconTheme.color,
        fontSize: iconSize * 0.6,
        fontWeight: FontWeight.w800,
        height: 1.0,
      ),
    );
  }
}
