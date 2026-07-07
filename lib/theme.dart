import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// ─────────────────────────────────────────────────────────────────────────────
// DESIGN TOKENS
// ─────────────────────────────────────────────────────────────────────────────
//
// Single source of truth for spacing / radius / icon-size / motion values.

abstract final class AppRadius {
  static const sm = 8.0; // chips, small controls
  static const md = 12.0; // cards, tiles, standard containers, dialogs' children
  static const lg = 20.0; // icon badges, prominent hero containers
  static const sheet = 28.0; // bottom sheets, dialogs (MD3 large)
  static const full = 100.0; // pill shapes (buttons, progress bars, badges)
}

abstract final class AppIconSize {
  static const inline = 14.0; // stat rows, meta text icons
  static const small = 18.0; // input prefix icons, dense list icons
  static const standard = 20.0; // toggle rows, section leading icons
  static const action = 24.0; // AppBar / default IconButton
  static const feature = 40.0; // empty-state / error-state illustrations
  static const hero = 56.0; // large empty states
}

abstract final class AppSpacing {
  // Step scale — prefer these over ad hoc SizedBox literals in new code.
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 16.0;
  static const lg = 24.0;
  static const xl = 32.0;

  static const pagePadding = EdgeInsets.fromLTRB(16, 12, 16, 32);
  static const sheetPadding = EdgeInsets.fromLTRB(24, 8, 24, 24);
}

/// Material 3 motion tokens (durations follow the M3 "easing & duration"
/// spec — short for micro-interactions, medium for local transitions).
abstract final class AppMotion {
  static const short1 = Duration(milliseconds: 100);
  static const short2 = Duration(milliseconds: 150);
  static const medium1 = Duration(milliseconds: 250);
  static const medium2 = Duration(milliseconds: 300);
  static const long1 = Duration(milliseconds: 400);
  static const long2 = Duration(milliseconds: 500);

  /// M3 "emphasized" easing — use for hero-ish, attention-worthy motion.
  static const emphasized = Curves.easeInOutCubicEmphasized;

  /// M3 "standard" easing — use for everyday enter/exit transitions.
  static const standard = Curves.easeOutCubic;
}

// ─────────────────────────────────────────────────────────────────────────────
// SEMANTIC COLORS (ThemeExtension)
// ─────────────────────────────────────────────────────────────────────────────


@immutable
class AppSemanticColors extends ThemeExtension<AppSemanticColors> {
  final Color success;
  final Color onSuccess;
  final Color successContainer;
  final Color onSuccessContainer;
  final Color warning;
  final Color onWarning;
  final Color warningContainer;
  final Color onWarningContainer;

  const AppSemanticColors({
    required this.success,
    required this.onSuccess,
    required this.successContainer,
    required this.onSuccessContainer,
    required this.warning,
    required this.onWarning,
    required this.warningContainer,
    required this.onWarningContainer,
  });

  static const dark = AppSemanticColors(
    success: Color(0xFF7DDA91),
    onSuccess: Color(0xFF00391A),
    successContainer: Color(0xFF00522A),
    onSuccessContainer: Color(0xFF98F8AC),
    warning: Color(0xFFF7C654),
    onWarning: Color(0xFF412D00),
    warningContainer: Color(0xFF5D4200),
    onWarningContainer: Color(0xFFFFDEA1),
  );

  static const light = AppSemanticColors(
    success: Color(0xFF176B33),
    onSuccess: Color(0xFFFFFFFF),
    successContainer: Color(0xFFA6F5AF),
    onSuccessContainer: Color(0xFF002107),
    warning: Color(0xFF7A5700),
    onWarning: Color(0xFFFFFFFF),
    warningContainer: Color(0xFFFFDEA1),
    onWarningContainer: Color(0xFF271900),
  );

  @override
  AppSemanticColors copyWith({
    Color? success,
    Color? onSuccess,
    Color? successContainer,
    Color? onSuccessContainer,
    Color? warning,
    Color? onWarning,
    Color? warningContainer,
    Color? onWarningContainer,
  }) {
    return AppSemanticColors(
      success: success ?? this.success,
      onSuccess: onSuccess ?? this.onSuccess,
      successContainer: successContainer ?? this.successContainer,
      onSuccessContainer: onSuccessContainer ?? this.onSuccessContainer,
      warning: warning ?? this.warning,
      onWarning: onWarning ?? this.onWarning,
      warningContainer: warningContainer ?? this.warningContainer,
      onWarningContainer: onWarningContainer ?? this.onWarningContainer,
    );
  }

  @override
  AppSemanticColors lerp(ThemeExtension<AppSemanticColors>? other, double t) {
    if (other is! AppSemanticColors) return this;
    return AppSemanticColors(
      success: Color.lerp(success, other.success, t)!,
      onSuccess: Color.lerp(onSuccess, other.onSuccess, t)!,
      successContainer: Color.lerp(successContainer, other.successContainer, t)!,
      onSuccessContainer: Color.lerp(onSuccessContainer, other.onSuccessContainer, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      onWarning: Color.lerp(onWarning, other.onWarning, t)!,
      warningContainer: Color.lerp(warningContainer, other.warningContainer, t)!,
      onWarningContainer: Color.lerp(onWarningContainer, other.onWarningContainer, t)!,
    );
  }
}

/// Convenience accessors so call sites can write `context.colors.primary`
/// instead of `Theme.of(context).colorScheme.primary`.
extension AppThemeX on BuildContext {
  ColorScheme get colors => Theme.of(this).colorScheme;
  TextTheme get typography => Theme.of(this).textTheme;
  AppSemanticColors get semanticColors =>
      Theme.of(this).extension<AppSemanticColors>() ?? AppSemanticColors.dark;
}

// ─────────────────────────────────────────────────────────────────────────────
// COLOR SCHEMES
// ─────────────────────────────────────────────────────────────────────────────

/// Seed used when dynamic color (Material You) isn't available/enabled.
const Color _seedColor = Color(0xFF0B57D0); // Google Blue

ColorScheme _darkColorScheme() => const ColorScheme(
      brightness: Brightness.dark,

      primary: Color(0xFFA8C7FA),
      onPrimary: Color(0xFF062E6F),
      primaryContainer: Color(0xFF0842A0),
      onPrimaryContainer: Color(0xFFD3E3FD),

      secondary: Color(0xFFBEC6DC),
      onSecondary: Color(0xFF283141),
      secondaryContainer: Color(0xFF3C4858),
      onSecondaryContainer: Color(0xFFDAE2F9),

      tertiary: Color(0xFFCFBCFF),
      onTertiary: Color(0xFF34275B),
      tertiaryContainer: Color(0xFF4B3D74),
      onTertiaryContainer: Color(0xFFEADDFF),

      error: Color(0xFFFFB4AB),
      onError: Color(0xFF690005),
      errorContainer: Color(0xFF93000A),
      onErrorContainer: Color(0xFFFFDAD6),

      surface: Color(0xFF111318),
      onSurface: Color(0xFFE2E2E9),
      onSurfaceVariant: Color(0xFFC2C7CF),

      surfaceContainerLowest: Color(0xFF0C0E13),
      surfaceContainerLow: Color(0xFF191C20),
      surfaceContainer: Color(0xFF1D2024),
      surfaceContainerHigh: Color(0xFF272A2F),
      surfaceContainerHighest: Color(0xFF32353A),

      outline: Color(0xFF8C9199),
      outlineVariant: Color(0xFF42474E),

      inverseSurface: Color(0xFFE2E2E9),
      onInverseSurface: Color(0xFF2E3135),
      inversePrimary: Color(0xFF3A5D92),

      shadow: Color(0xFF000000),
      scrim: Color(0xFF000000),
      surfaceTint: Color(0xFFA8C7FA),
    );

// ─────────────────────────────────────────────────────────────────────────────
// THEME BUILDERS
// ─────────────────────────────────────────────────────────────────────────────

ThemeData buildDarkTheme([ColorScheme? dynamicScheme]) =>
    _buildTheme(dynamicScheme ?? _darkColorScheme(), Brightness.dark);

ThemeData buildLightTheme([ColorScheme? dynamicScheme]) => _buildTheme(
      dynamicScheme ??
          ColorScheme.fromSeed(seedColor: _seedColor, brightness: Brightness.light),
      Brightness.light,
    );

/// Retained for any older call sites — prefer [buildDarkTheme] explicitly.
@Deprecated('Use buildDarkTheme() (or buildLightTheme()) instead.')
ThemeData buildTheme() => buildDarkTheme();

ThemeData _buildTheme(ColorScheme cs, Brightness brightness) {
  final isDark = brightness == Brightness.dark;

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: cs,
    scaffoldBackgroundColor: cs.surface,
    visualDensity: VisualDensity.adaptivePlatformDensity,

    // Android's "wet ink" ripple (Android 12+) instead of the classic
    // circular splash — a small but noticeable native-feel upgrade.
    splashFactory: InkSparkle.splashFactory,

    // Predictive back on Android 14+/16, standard slide on iOS.
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
      },
    ),

    extensions: [isDark ? AppSemanticColors.dark : AppSemanticColors.light],

    appBarTheme: AppBarTheme(
      backgroundColor: cs.surface,
      foregroundColor: cs.onSurface,
      elevation: 0,
      scrolledUnderElevation: 3,
      surfaceTintColor: cs.surfaceTint,
      centerTitle: false, // Native Android left-aligns titles
      titleTextStyle: TextStyle(
        fontSize: 22,
        fontWeight: FontWeight.w400,
        color: cs.onSurface,
      ),
      iconTheme: IconThemeData(color: cs.onSurface, size: AppIconSize.action),
      actionsIconTheme: IconThemeData(color: cs.onSurfaceVariant),
      systemOverlayStyle: isDark
          ? const SystemUiOverlayStyle(
              statusBarColor: Colors.transparent,
              statusBarIconBrightness: Brightness.light,
              systemNavigationBarColor: Colors.transparent,
              systemNavigationBarIconBrightness: Brightness.light,
            )
          : const SystemUiOverlayStyle(
              statusBarColor: Colors.transparent,
              statusBarIconBrightness: Brightness.dark,
              systemNavigationBarColor: Colors.transparent,
              systemNavigationBarIconBrightness: Brightness.dark,
            ),
    ),

    cardTheme: CardThemeData(
      color: cs.surfaceContainerLow,
      elevation: 0,
      shadowColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      margin: EdgeInsets.zero,
    ),

    inputDecorationTheme: InputDecorationTheme(
      filled: false,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(4), // MD3 standard input radius
        borderSide: BorderSide(color: cs.outline),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(4),
        borderSide: BorderSide(color: cs.outline),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(4),
        borderSide: BorderSide(color: cs.primary, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(4),
        borderSide: BorderSide(color: cs.error),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(4),
        borderSide: BorderSide(color: cs.error, width: 2),
      ),
      labelStyle: TextStyle(color: cs.onSurfaceVariant, fontSize: 16),
      floatingLabelStyle: TextStyle(color: cs.primary, fontSize: 12),
      hintStyle: TextStyle(color: cs.onSurfaceVariant, fontSize: 16),
      prefixIconColor: cs.onSurfaceVariant,
      suffixIconColor: cs.onSurfaceVariant,
    ),

    dividerTheme: DividerThemeData(
      color: cs.outlineVariant,
      thickness: 1,
      space: 1,
    ),

    listTileTheme: ListTileThemeData(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      iconColor: cs.onSurfaceVariant,
      textColor: cs.onSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
    ),

    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return cs.primary;
        return Colors.transparent;
      }),
      checkColor: WidgetStateProperty.all(cs.onPrimary),
      side: BorderSide(color: cs.onSurfaceVariant, width: 2),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(2)),
    ),

    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return cs.onPrimary;
        return cs.outline;
      }),
      trackColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return cs.primary;
        return cs.surfaceContainerHighest;
      }),
      trackOutlineColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return Colors.transparent;
        return cs.outline;
      }),
    ),

    radioTheme: RadioThemeData(
      fillColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return cs.primary;
        return cs.outline;
      }),
    ),

    sliderTheme: SliderThemeData(
      activeTrackColor: cs.primary,
      inactiveTrackColor: cs.surfaceContainerHighest,
      thumbColor: cs.primary,
      overlayColor: cs.primary.withValues(alpha: 0.12),
    ),

    // Buttons — pill-shaped, 48dp minimum touch target across the board.
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: cs.primary,
        foregroundColor: cs.onPrimary,
        disabledBackgroundColor: cs.onSurface.withValues(alpha: 0.12),
        disabledForegroundColor: cs.onSurface.withValues(alpha: 0.38),
        textStyle: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w500,
          letterSpacing: 0.1,
        ),
        shape: const StadiumBorder(),
        minimumSize: const Size(double.infinity, 48),
      ),
    ),

    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: cs.surfaceContainerHigh,
        foregroundColor: cs.primary,
        elevation: 0,
        textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
        shape: const StadiumBorder(),
        minimumSize: const Size(0, 48),
      ),
    ),

    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: cs.primary,
        side: BorderSide(color: cs.outline),
        textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
        shape: const StadiumBorder(),
        minimumSize: const Size(0, 48),
      ),
    ),

    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: cs.primary,
        textStyle: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w500,
          letterSpacing: 0.1,
        ),
        shape: const StadiumBorder(),
        minimumSize: const Size(0, 48),
      ),
    ),

    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(foregroundColor: cs.onSurfaceVariant),
    ),

    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: cs.primaryContainer,
      foregroundColor: cs.onPrimaryContainer,
      elevation: 1,
      focusElevation: 1,
      hoverElevation: 2,
      highlightElevation: 3,
      extendedTextStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
    ),

    chipTheme: ChipThemeData(
      backgroundColor: cs.surfaceContainerHigh,
      selectedColor: cs.secondaryContainer,
      disabledColor: cs.onSurface.withValues(alpha: 0.12),
      labelStyle: TextStyle(color: cs.onSurface, fontSize: 13),
      secondaryLabelStyle: TextStyle(color: cs.onSecondaryContainer, fontSize: 13),
      side: BorderSide(color: cs.outlineVariant),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.full)),
      padding: const EdgeInsets.symmetric(horizontal: 8),
    ),

    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(
        backgroundColor: cs.surfaceContainerHigh,
        foregroundColor: cs.onSurfaceVariant,
        selectedBackgroundColor: cs.secondaryContainer,
        selectedForegroundColor: cs.onSecondaryContainer,
        side: BorderSide(color: cs.outlineVariant),
      ),
    ),

    navigationBarTheme: NavigationBarThemeData(
      height: 80,
      elevation: 0,
      backgroundColor: cs.surfaceContainer,
      surfaceTintColor: Colors.transparent,
      indicatorColor: cs.secondaryContainer,
      indicatorShape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.full),
      ),
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return TextStyle(
          fontSize: 12,
          fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
          color: selected ? cs.onSurface : cs.onSurfaceVariant,
        );
      }),
      iconTheme: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return IconThemeData(
          color: selected ? cs.onSecondaryContainer : cs.onSurfaceVariant,
          size: AppIconSize.action,
        );
      }),
    ),

    popupMenuTheme: PopupMenuThemeData(
      color: cs.surfaceContainer,
      elevation: 3,
      shadowColor: Colors.black,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.sm * 2),
      ),
      textStyle: TextStyle(color: cs.onSurface, fontSize: 14),
    ),

    menuTheme: MenuThemeData(
      style: MenuStyle(
        backgroundColor: WidgetStateProperty.all(cs.surfaceContainer),
        elevation: WidgetStateProperty.all(3),
        surfaceTintColor: WidgetStateProperty.all(Colors.transparent),
        shape: WidgetStateProperty.all(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.sm * 2),
          ),
        ),
      ),
    ),

    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: cs.surfaceContainerLow,
      modalBackgroundColor: cs.surfaceContainerLow,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.sheet)),
      ),
      showDragHandle: true, // Native Android drag pill
      dragHandleColor: cs.onSurfaceVariant.withValues(alpha: 0.4),
      elevation: 1,
      modalElevation: 1,
    ),

    snackBarTheme: SnackBarThemeData(
      backgroundColor: cs.inverseSurface,
      contentTextStyle: TextStyle(color: cs.onInverseSurface, fontSize: 14),
      actionTextColor: cs.inversePrimary,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
      behavior: SnackBarBehavior.floating,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    ),

    dialogTheme: DialogThemeData(
      backgroundColor: cs.surfaceContainerHigh,
      surfaceTintColor: Colors.transparent,
      elevation: 6,
      shadowColor: Colors.black45,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.sheet),
      ),
      titleTextStyle: TextStyle(
        color: cs.onSurface,
        fontSize: 24,
        fontWeight: FontWeight.w400,
      ),
      contentTextStyle: TextStyle(color: cs.onSurfaceVariant, fontSize: 14),
    ),

    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: cs.inverseSurface,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      textStyle: TextStyle(color: cs.onInverseSurface, fontSize: 12),
    ),

    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: cs.primary,
      linearTrackColor: cs.surfaceContainerHighest,
      circularTrackColor: cs.surfaceContainerHighest,
    ),

    textTheme: TextTheme(
      headlineSmall: TextStyle(
        color: cs.onSurface,
        fontSize: 24,
        fontWeight: FontWeight.bold,
        letterSpacing: -0.2,
      ),
      titleLarge: TextStyle(
        color: cs.onSurface,
        fontSize: 22,
        fontWeight: FontWeight.w400,
        letterSpacing: 0,
      ),
      bodyLarge: TextStyle(
        color: cs.onSurface,
        fontSize: 16,
        height: 1.5,
        letterSpacing: 0.5,
      ),
      bodyMedium: TextStyle(
        color: cs.onSurface,
        fontSize: 14,
        height: 1.4,
        letterSpacing: 0.25,
      ),
      bodySmall: TextStyle(
        color: cs.onSurfaceVariant,
        fontSize: 12,
        height: 1.3,
        letterSpacing: 0.4,
      ),
      labelLarge: TextStyle(
        color: cs.onSurface,
        fontSize: 14,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.1,
      ),
      labelMedium: TextStyle(
        color: cs.onSurfaceVariant,
        fontSize: 12,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.5,
      ),
      labelSmall: TextStyle(
        color: cs.onSurfaceVariant,
        fontSize: 11,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.5,
      ),
      titleMedium: TextStyle(
        color: cs.onSurface,
        fontSize: 16,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.15,
      ),
      titleSmall: TextStyle(
        color: cs.onSurface,
        fontSize: 14,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.1,
      ),
    ),
  );
}