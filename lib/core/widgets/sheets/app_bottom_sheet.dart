import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/theme/app_theme.dart';

/// Standard keyboard-safe, gesture-nav-safe bottom sheet wrapper.
class AppBottomSheet extends StatelessWidget {
  final Widget child;
  const AppBottomSheet({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final mqViewInsets = MediaQuery.viewInsetsOf(context);
    return Padding(
      padding: EdgeInsets.only(bottom: mqViewInsets.bottom),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: AppSpacing.sheetPadding,
          child: child,
        ),
      ),
    );
  }
}
