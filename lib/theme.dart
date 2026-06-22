import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

ThemeData buildTheme() {
  const bg             = Color(0xFF0A0C0F);
  const surface        = Color(0xFF141820);
  const surfaceVariant = Color(0xFF1C2130);
  const border         = Color(0xFF252D3D);
  const accent         = Color(0xFF4FC3F7);
  const accentDim      = Color(0xFF142230);
  const textPrimary    = Color(0xFFECF0F5);
  const textSecondary  = Color(0xFF8896AA);
  const errorColor     = Color(0xFFEF5350);
  const warningColor   = Color(0xFFFFA726);

  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: bg,

    colorScheme: const ColorScheme.dark(
      brightness: Brightness.dark,
      surface: surface,
      surfaceContainerHighest: surfaceVariant,
      primary: accent,
      primaryContainer: accentDim,
      onPrimary: bg,
      onSurface: textPrimary,
      onSurfaceVariant: textSecondary,
      outline: border,
      outlineVariant: Color(0xFF1E2535),
      error: errorColor,
      onError: Colors.white,
      secondary: warningColor,
      tertiary: Color(0xFF66BB6A),
    ),

    fontFamily: 'monospace',

    appBarTheme: const AppBarTheme(
      backgroundColor: bg,
      foregroundColor: textPrimary,
      elevation: 0,
      scrolledUnderElevation: 1,
      shadowColor: Colors.black54,
      titleTextStyle: TextStyle(
        fontFamily: 'monospace',
        fontSize: 15,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.4,
        color: textPrimary,
      ),
      iconTheme: IconThemeData(color: textSecondary, size: 22),
      actionsIconTheme: IconThemeData(color: textSecondary),
      systemOverlayStyle: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        systemNavigationBarColor: bg,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
    ),

    cardTheme: CardThemeData(
      color: surface,
      elevation: 0,
      shadowColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: border, width: 1),
      ),
      margin: EdgeInsets.zero,
    ),

    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: surfaceVariant,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: accent, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: errorColor, width: 1.5),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: errorColor, width: 1.5),
      ),
      labelStyle: const TextStyle(color: textSecondary, fontSize: 13),
      hintStyle: const TextStyle(color: Color(0xFF3D4A5C), fontSize: 13),
      prefixIconColor: textSecondary,
      suffixIconColor: textSecondary,
    ),

    dividerTheme: const DividerThemeData(
      color: border,
      thickness: 1,
      space: 0,
    ),

    listTileTheme: const ListTileThemeData(
      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      minLeadingWidth: 24,
    ),

    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return accent;
        return Colors.transparent;
      }),
      checkColor: WidgetStateProperty.all(bg),
      side: const BorderSide(color: border, width: 1.5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
    ),

    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: accent,
        foregroundColor: bg,
        disabledBackgroundColor: border,
        disabledForegroundColor: textSecondary,
        textStyle: const TextStyle(
          fontFamily: 'monospace',
          fontSize: 14,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.3,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        minimumSize: const Size(double.infinity, 48),
      ),
    ),

    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: accent,
        textStyle: const TextStyle(
          fontFamily: 'monospace',
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),

    popupMenuTheme: PopupMenuThemeData(
      color: surfaceVariant,
      elevation: 8,
      shadowColor: Colors.black54,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: border, width: 1),
      ),
      textStyle: const TextStyle(
        color: textPrimary,
        fontFamily: 'monospace',
        fontSize: 13,
      ),
    ),

    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: surface,
      modalBackgroundColor: surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      showDragHandle: false,
      elevation: 0,
    ),

    snackBarTheme: SnackBarThemeData(
      backgroundColor: surfaceVariant,
      contentTextStyle: const TextStyle(
        color: textPrimary,
        fontSize: 13,
        fontFamily: 'monospace',
      ),
      actionTextColor: accent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: border),
      ),
      behavior: SnackBarBehavior.floating,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    ),

    dialogTheme: DialogThemeData(
      backgroundColor: surface,
      elevation: 16,
      shadowColor: Colors.black54,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: border, width: 1),
      ),
      titleTextStyle: const TextStyle(
        color: textPrimary,
        fontFamily: 'monospace',
        fontSize: 15,
        fontWeight: FontWeight.w600,
      ),
      contentTextStyle: const TextStyle(
        color: textSecondary,
        fontFamily: 'monospace',
        fontSize: 13,
      ),
    ),

    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: accent,
      linearTrackColor: border,
    ),

    textTheme: const TextTheme(
      bodyLarge:   TextStyle(color: textPrimary,   fontSize: 14, height: 1.5),
      bodyMedium:  TextStyle(color: textPrimary,   fontSize: 13, height: 1.5),
      bodySmall:   TextStyle(color: textSecondary, fontSize: 12, height: 1.4),
      labelLarge:  TextStyle(
        color: textPrimary, fontSize: 13,
        fontWeight: FontWeight.w600, letterSpacing: 0.3,
      ),
      labelMedium: TextStyle(color: textSecondary, fontSize: 12, letterSpacing: 0.2),
      titleMedium: TextStyle(
        color: textPrimary, fontSize: 14,
        fontWeight: FontWeight.w600, letterSpacing: 0.1,
      ),
      titleSmall:  TextStyle(
        color: textPrimary, fontSize: 13,
        fontWeight: FontWeight.w600,
      ),
    ),
  );
}