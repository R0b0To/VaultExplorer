import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/utils/responsive.dart';

/// Shows [builder]'s content as a bottom sheet on a phone or small tablet and
/// as a centered modal dialog on a large window (tablet landscape, desktop).
///
/// A drop-in for `showModalBottomSheet` for sheets whose content sizes itself
/// to its contents (a column of options, a short form). The sheet-only
/// options ([showDragHandle], [shape], [enableDrag], [constraints],
/// [isScrollControlled], [useSafeArea]) apply to the bottom sheet only; the
/// dialog draws its own rounded surface and is dismissed with Escape or by
/// tapping outside, as long as [isDismissible] allows it. Leaving
/// [showDragHandle] null keeps the app theme's choice for the bottom sheet.
///
/// Do not use it for a sheet whose content needs the sheet's own height, such
/// as one built on `DraggableScrollableSheet`: keep those on
/// `showModalBottomSheet`.
Future<T?> showAdaptiveSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isScrollControlled = false,
  bool useSafeArea = false,
  bool? showDragHandle,
  bool enableDrag = true,
  bool isDismissible = true,
  Color? backgroundColor,
  ShapeBorder? shape,
  BoxConstraints? constraints,
  double dialogMaxWidth = 560,
}) {
  if (!context.prefersDialogs) {
    return showModalBottomSheet<T>(
      context: context,
      builder: builder,
      isScrollControlled: isScrollControlled,
      useSafeArea: useSafeArea,
      showDragHandle: showDragHandle,
      enableDrag: enableDrag,
      isDismissible: isDismissible,
      backgroundColor: backgroundColor,
      shape: shape,
      constraints: constraints,
    );
  }

  final theme = Theme.of(context);
  final surface =
      backgroundColor ??
      theme.bottomSheetTheme.modalBackgroundColor ??
      theme.bottomSheetTheme.backgroundColor ??
      theme.colorScheme.surfaceContainerLow;
  final windowHeight = MediaQuery.sizeOf(context).height;

  return showDialog<T>(
    context: context,
    barrierDismissible: isDismissible,
    builder: (dialogContext) => Dialog(
      backgroundColor: surface,
      surfaceTintColor: Colors.transparent,
      clipBehavior: Clip.antiAlias,
      insetPadding: const EdgeInsets.all(24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: dialogMaxWidth,
          maxHeight: windowHeight - 48,
        ),
        child: builder(dialogContext),
      ),
    ),
  );
}
