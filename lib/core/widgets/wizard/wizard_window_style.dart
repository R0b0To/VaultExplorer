import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/theme/app_theme.dart';

/// Marks the part of the tree that is a creation wizard shown in a native
/// desktop window (see `WizardScaffold`).
///
/// The wizard's steps are built from shared pieces ([SectionCard],
/// [WizardSelectionCard]) that are also used on phones, where grouped cards
/// and large rounded tiles are right. Inside a window they look at this to
/// draw themselves flat instead: no card behind a group, a hairline border and
/// a tight corner radius.
class WizardWindowStyle extends InheritedWidget {
  const WizardWindowStyle({super.key, required super.child});

  /// Whether [context] is inside a wizard window.
  static bool isActive(BuildContext context) =>
      context.getInheritedWidgetOfExactType<WizardWindowStyle>() != null;

  @override
  bool updateShouldNotify(WizardWindowStyle oldWidget) => false;
}

/// Corner radius of fields, tiles and buttons in the window layout.
const double kWizardWindowRadius = AppRadius.sm;

/// Hairline colour of fields and tiles when idle.
Color wizardWindowOutline(ColorScheme cs) => cs.onSurface.withValues(alpha: 0.12);

/// The text-field look of the window layout: a 1px hairline border that turns
/// to the accent colour on focus, over a barely tinted fill, with tight
/// padding.
InputDecorationTheme wizardWindowInputDecorationTheme(ColorScheme cs) {
  OutlineInputBorder border(Color color, [double width = 1]) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(kWizardWindowRadius),
        borderSide: BorderSide(color: color, width: width),
      );
  return InputDecorationTheme(
    isDense: true,
    filled: true,
    fillColor: cs.onSurface.withValues(alpha: 0.04),
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    border: border(wizardWindowOutline(cs)),
    enabledBorder: border(wizardWindowOutline(cs)),
    focusedBorder: border(cs.primary, 1.5),
    disabledBorder: border(cs.onSurface.withValues(alpha: 0.06)),
    errorBorder: border(cs.error),
    focusedErrorBorder: border(cs.error, 1.5),
  );
}
