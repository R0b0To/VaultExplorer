import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/utils/responsive.dart';

/// Scale applied to switches on wide (desktop / popup-style) layouts, where
/// Material 3's touch-sized switch looks chunky next to 13-14px text.
const double kDesktopSwitchScale = 0.85;

/// A [SwitchListTile] drop-in whose switch is scaled down on wide layouts so
/// it feels native to a mouse-driven UI. On narrow (touch) layouts it is
/// rendered at the normal Material size.
///
/// Supports the subset of [SwitchListTile] parameters the settings screens use.
class CompactSwitchListTile extends StatelessWidget {
  const CompactSwitchListTile({
    super.key,
    required this.title,
    required this.value,
    required this.onChanged,
    this.subtitle,
    this.secondary,
    this.contentPadding,
  });

  final Widget title;
  final Widget? subtitle;
  final Widget? secondary;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final EdgeInsetsGeometry? contentPadding;

  @override
  Widget build(BuildContext context) {
    if (!context.screen.useWideLayout) {
      return SwitchListTile(
        title: title,
        subtitle: subtitle,
        secondary: secondary,
        value: value,
        onChanged: onChanged,
        contentPadding: contentPadding,
      );
    }
    final enabled = onChanged != null;
    return MergeSemantics(
      child: ListTile(
        contentPadding: contentPadding,
        title: title,
        subtitle: subtitle,
        leading: secondary,
        enabled: enabled,
        onTap: enabled ? () => onChanged!(!value) : null,
        trailing: Transform.scale(
          scale: kDesktopSwitchScale,
          alignment: Alignment.centerRight,
          child: Switch(value: value, onChanged: onChanged),
        ),
      ),
    );
  }
}
