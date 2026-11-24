import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/utils/responsive.dart';

/// Frames the content that sits beside the docked sidebar.
///
/// The content only has the width beside the sidebar. Telling it so keeps
/// every width-based decision inside (dual pane, grid columns, two-column
/// pages) honest instead of counting the sidebar's room as its own. The
/// sidebar already consumed the left system inset. This is its own widget so
/// that depending on the full `MediaQuery` (keyboard, insets) rebuilds only
/// this thin frame, never the whole shell.
class DockedContentFrame extends StatelessWidget {
  const DockedContentFrame({
    super.key,
    required this.consumedWidth,
    required this.child,
  });

  final double consumedWidth;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    return MediaQuery(
      data: mq.copyWith(
        size: Size(mq.size.width - consumedWidth, mq.size.height),
        padding: mq.padding.copyWith(left: 0),
        viewPadding: mq.viewPadding.copyWith(left: 0),
      ),
      child: DockedSidebarScope(child: child),
    );
  }
}
