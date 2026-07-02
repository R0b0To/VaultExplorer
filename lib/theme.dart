import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// ── Design tokens ────────────────────────────────────────────────────────────
//
// Single source of truth for radius/icon-size values that were previously
// hardcoded as magic numbers scattered across ~15 files. New UI should always
// reference these instead of literal numbers.

abstract final class AppRadius {
  static const sm = 8.0; // chips, small controls
  static const md = 12.0; // cards, tiles, standard containers, dialogs' children
  static const lg = 20.0; // icon badges, prominent hero containers
  static const sheet = 28.0; // bottom sheets, dialogs (MD3 large)
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
  static const pagePadding = EdgeInsets.fromLTRB(16, 12, 16, 32);
  static const sheetPadding = EdgeInsets.fromLTRB(24, 8, 24, 24);
}

ThemeData buildTheme() {
  // Official Material Design 3 Baseline Dark Tokens (Google Blue Seed)
  const surface = Color(0xFF111318);
  const surfaceContainerLow = Color(0xFF191C20);
  const surfaceContainer = Color(0xFF1D2024);
  const surfaceContainerHigh = Color(0xFF272A2F);
  const surfaceContainerHighest = Color(0xFF32353A);

  const onSurface = Color(0xFFE2E2E9);
  const onSurfaceVariant = Color(0xFFC2C7CF);
  const outline = Color(0xFF8C9199);
  const outlineVariant = Color(0xFF42474E);

  const primary = Color(0xFFA8C7FA); // MD3 Pastel Blue
  const onPrimary = Color(0xFF062E6F); // Deep Navy
  const primaryContainer = Color(0xFF0842A0);
  const onPrimaryContainer = Color(0xFFD3E3FD);

  const secondary = Color(0xFFBEC6DC);
  const errorColor = Color(0xFFFFB4AB);
  const onErrorColor = Color(0xFF690005);

  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: surface,

    colorScheme: const ColorScheme.dark(
      brightness: Brightness.dark,
      surface: surface,
      onSurface: onSurface,
      onSurfaceVariant: onSurfaceVariant,
      primary: primary,
      onPrimary: onPrimary,
      primaryContainer: primaryContainer,
      onPrimaryContainer: onPrimaryContainer,
      secondary: secondary,
      onSecondary: Color(0xFF283141),
      outline: outline,
      outlineVariant: outlineVariant,
      error: errorColor,
      onError: onErrorColor,
    ),

    appBarTheme: const AppBarTheme(
      backgroundColor: surface,
      foregroundColor: onSurface,
      elevation: 0,
      scrolledUnderElevation: 3, // Native MD3 tonal tint when scrolling
      centerTitle: false, // Native Android left-aligns titles
      titleTextStyle: TextStyle(
        fontSize: 22,
        fontWeight: FontWeight.w400,
        color: onSurface,
      ),
      iconTheme: IconThemeData(color: onSurface, size: AppIconSize.action),
      actionsIconTheme: IconThemeData(color: onSurfaceVariant),
      systemOverlayStyle: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        systemNavigationBarColor:
            Colors.transparent, // Android 15/16/17 Edge-to-Edge
        systemNavigationBarIconBrightness: Brightness.light,
      ),
    ),

    cardTheme: CardThemeData(
      color: surfaceContainerLow,
      elevation: 0,
      shadowColor: Colors.transparent,
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
        borderSide: const BorderSide(color: outline),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(4),
        borderSide: const BorderSide(color: outline),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(4),
        borderSide: const BorderSide(color: primary, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(4),
        borderSide: const BorderSide(color: errorColor),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(4),
        borderSide: const BorderSide(color: errorColor, width: 2),
      ),
      labelStyle: const TextStyle(color: onSurfaceVariant, fontSize: 16),
      floatingLabelStyle: const TextStyle(color: primary, fontSize: 12),
      hintStyle: const TextStyle(color: onSurfaceVariant, fontSize: 16),
      prefixIconColor: onSurfaceVariant,
      suffixIconColor: onSurfaceVariant,
    ),

    dividerTheme: const DividerThemeData(
      color: outlineVariant,
      thickness: 1,
      space: 1,
    ),

    listTileTheme: const ListTileThemeData(
      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      iconColor: onSurfaceVariant,
      textColor: onSurface,
    ),

    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return primary;
        return Colors.transparent;
      }),
      checkColor: WidgetStateProperty.all(
        onPrimary,
      ), // Navy tick on pastel blue
      side: const BorderSide(color: onSurfaceVariant, width: 2),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(2)),
    ),

    // FIX: minimumSize height was 40, which made primary buttons on
    // AppSettingsScreen (Save / Set Password / Update) render 8dp shorter
    // than every other FilledButton in the app (unlock, create container,
    // lock gate, container config all explicitly overrode to 48). Raising
    // the theme default to 48 means those per-call overrides are now
    // redundant (harmless) and any *new* button automatically matches.
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: primary,
        foregroundColor: onPrimary,
        disabledBackgroundColor: onSurface.withValues(alpha: 0.12),
        disabledForegroundColor: onSurface.withValues(alpha: 0.38),
        textStyle: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w500,
          letterSpacing: 0.1,
        ),
        shape: const StadiumBorder(), // Material You Pill shape
        minimumSize: const Size(double.infinity, 48),
      ),
    ),

    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: primary,
        textStyle: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w500,
          letterSpacing: 0.1,
        ),
        shape: const StadiumBorder(),
      ),
    ),

    popupMenuTheme: PopupMenuThemeData(
      color: surfaceContainer,
      elevation: 3,
      shadowColor: Colors.black,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.sm / 2),
      ),
      textStyle: const TextStyle(color: onSurface, fontSize: 14),
    ),

    menuTheme: MenuThemeData(
      style: MenuStyle(
        backgroundColor: WidgetStateProperty.all(surfaceContainer),
        elevation: WidgetStateProperty.all(3),
        shape: WidgetStateProperty.all(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.sm * 2),
          ),
        ),
      ),
    ),

    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: surfaceContainerLow,
      modalBackgroundColor: surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppRadius.sheet),
        ), // Big MD3 radius
      ),
      showDragHandle: true, // Native Android drag pill
      elevation: 1,
    ),

    snackBarTheme: SnackBarThemeData(
      backgroundColor: const Color(0xFFE2E2E9), // MD3 Snackbars invert to Light
      contentTextStyle: const TextStyle(color: Color(0xFF2E3135), fontSize: 14),
      actionTextColor: primaryContainer,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      behavior: SnackBarBehavior.floating,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    ),

    dialogTheme: DialogThemeData(
      backgroundColor: surfaceContainerHigh,
      elevation: 6,
      shadowColor: Colors.black45,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.sheet),
      ),
      titleTextStyle: const TextStyle(
        color: onSurface,
        fontSize: 24,
        fontWeight: FontWeight.w400,
      ),
      contentTextStyle: const TextStyle(color: onSurfaceVariant, fontSize: 14),
    ),

    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: primary,
      linearTrackColor: surfaceContainerHighest,
    ),

    textTheme: const TextTheme(
      // FIX: previously undefined — LockGateScreen's app title fell back to
      // stock Material headlineSmall (24/w400/0 letterSpacing) instead of
      // this app's design language.
      headlineSmall: TextStyle(
        color: onSurface,
        fontSize: 24,
        fontWeight: FontWeight.bold,
        letterSpacing: -0.2,
      ),
      // FIX: previously undefined — VaultDashboard's AppBar title fell back
      // to stock Material titleLarge instead of matching the rest of the
      // type scale.
      titleLarge: TextStyle(
        color: onSurface,
        fontSize: 22,
        fontWeight: FontWeight.w400,
        letterSpacing: 0,
      ),
      bodyLarge: TextStyle(
        color: onSurface,
        fontSize: 16,
        height: 1.5,
        letterSpacing: 0.5,
      ),
      bodyMedium: TextStyle(
        color: onSurface,
        fontSize: 14,
        height: 1.4,
        letterSpacing: 0.25,
      ),
      bodySmall: TextStyle(
        color: onSurfaceVariant,
        fontSize: 12,
        height: 1.3,
        letterSpacing: 0.4,
      ),
      labelLarge: TextStyle(
        color: onSurface,
        fontSize: 14,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.1,
      ),
      labelMedium: TextStyle(
        color: onSurfaceVariant,
        fontSize: 12,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.5,
      ),
      labelSmall: TextStyle(
        color: onSurfaceVariant,
        fontSize: 11,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.5,
      ),
      titleMedium: TextStyle(
        color: onSurface,
        fontSize: 16,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.15,
      ),
      titleSmall: TextStyle(
        color: onSurface,
        fontSize: 14,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.1,
      ),
    ),
  );
}