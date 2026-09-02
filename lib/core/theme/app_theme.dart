import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

abstract final class AppRadius {
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 20.0;
  static const xl = 24.0;
  static const sheet = 28.0;
  static const full = 100.0;
}

abstract final class AppSystemUI {
  static const transparentDark = SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    statusBarBrightness: Brightness.dark,
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarDividerColor: Colors.transparent,
    systemNavigationBarIconBrightness: Brightness.light,
    systemNavigationBarContrastEnforced: false,
    systemStatusBarContrastEnforced: false,
  );
}

abstract final class AppIconSize {
  static const inline = 14.0;
  static const small = 18.0;
  static const standard = 20.0;
  static const action = 24.0;
  static const feature = 40.0;
  static const hero = 56.0;
}

abstract final class AppSpacing {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 16.0;
  static const lg = 24.0;
  static const xl = 32.0;
  static const pagePadding = EdgeInsets.fromLTRB(16, 12, 16, 32);
  static const sheetPadding = EdgeInsets.fromLTRB(24, 8, 24, 24);
  static const floatingStackClearance = 112.0;
}

abstract final class AppMotion {
  static const short1 = Duration(milliseconds: 100);
  static const short2 = Duration(milliseconds: 150);
  static const medium1 = Duration(milliseconds: 250);
  static const medium2 = Duration(milliseconds: 300);
  static const long1 = Duration(milliseconds: 400);
  static const long2 = Duration(milliseconds: 500);
  static const emphasized = Curves.easeInOutCubicEmphasized;
  static const standard = Curves.easeOutCubic;
}

/// Relays Android's predictive-back gesture callbacks to [route] so that
/// `route`'s own transition controller (the same controller [buildTransitions]
/// receives as `animation`) tracks the user's finger continuously instead of
/// only jumping to its end value in [PageRoute.handleCommitBackGesture]/
/// [PageRoute.handleCancelBackGesture] after the finger lifts.
///
/// Without this, `animation`/`secondaryAnimation` never change mid-gesture,
/// so any [PageTransitionsBuilder] built purely from those two animations
/// (like [CrossfadePageTransitionsBuilder]) only animates once the gesture
/// commits or cancels on release - there's no live preview while dragging.
class _PredictiveBackForwarder extends StatefulWidget {
  const _PredictiveBackForwarder({required this.route, required this.child});

  final PageRoute<dynamic> route;
  final Widget child;

  @override
  State<_PredictiveBackForwarder> createState() => _PredictiveBackForwarderState();
}

class _PredictiveBackForwarderState extends State<_PredictiveBackForwarder>
    with WidgetsBindingObserver {
  bool get _canHandle => widget.route.isCurrent && widget.route.popGestureEnabled;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  bool handleStartBackGesture(PredictiveBackEvent backEvent) {
    if (backEvent.isButtonEvent || !_canHandle) return false;
    widget.route.handleStartBackGesture(progress: 1 - backEvent.progress);
    return true;
  }

  @override
  void handleUpdateBackGestureProgress(PredictiveBackEvent backEvent) {
    widget.route.handleUpdateBackGestureProgress(progress: 1 - backEvent.progress);
  }

  @override
  void handleCancelBackGesture() => widget.route.handleCancelBackGesture();

  @override
  void handleCommitBackGesture() => widget.route.handleCommitBackGesture();

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Gesture-driven in-app crossfade matching Android's SociaLite predictive back navigation.
class CrossfadePageTransitionsBuilder extends PageTransitionsBuilder {
  const CrossfadePageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final enterTransition = FadeTransition(
      opacity: CurvedAnimation(
        parent: animation,
        curve: Curves.easeOut,
        reverseCurve: Curves.easeIn,
      ),
      child: ScaleTransition(
        scale: Tween<double>(begin: 0.96, end: 1.0).animate(
          CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
            reverseCurve: Curves.easeInCubic,
          ),
        ),
        child: child,
      ),
    );

    final crossfade = FadeTransition(
      opacity: Tween<double>(begin: 1.0, end: 0.0).animate(
        CurvedAnimation(
          parent: secondaryAnimation,
          curve: Curves.easeOut,
          reverseCurve: Curves.easeIn,
        ),
      ),
      child: ScaleTransition(
        scale: Tween<double>(begin: 1.0, end: 0.96).animate(
          CurvedAnimation(
            parent: secondaryAnimation,
            curve: Curves.easeOutCubic,
            reverseCurve: Curves.easeInCubic,
          ),
        ),
        child: enterTransition,
      ),
    );

    // Feed live predictive-back progress into route's own controller so
    // `animation`/`secondaryAnimation` above update on every frame of the
    // drag, not just at commit/cancel.
    return _PredictiveBackForwarder(route: route, child: crossfade);
  }
}

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
  final Color bookmark;

  const AppSemanticColors({
    required this.success,
    required this.onSuccess,
    required this.successContainer,
    required this.onSuccessContainer,
    required this.warning,
    required this.onWarning,
    required this.warningContainer,
    required this.onWarningContainer,
    required this.bookmark,
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
    bookmark: Color(0xFFFFC107),
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
    bookmark: Color(0xFF8F6300),
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
    Color? bookmark,
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
      bookmark: bookmark ?? this.bookmark,
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
      bookmark: Color.lerp(bookmark, other.bookmark, t)!,
    );
  }
}

extension AppThemeX on BuildContext {
  ColorScheme get colors => Theme.of(this).colorScheme;
  TextTheme get typography => Theme.of(this).textTheme;
  AppSemanticColors get semanticColors =>
      Theme.of(this).extension<AppSemanticColors>() ?? AppSemanticColors.dark;
}

const Color _seedColor = Color(0xFF0B57D0);

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

/// Overrides the neutral surface ramp of [cs] with true blacks for an
/// OLED/AMOLED "pure black" look. Accent roles (primary, secondary,
/// tertiary, error, and their "on"/container pairs) are left untouched so
/// Material You dynamic colors still come through on top of the black
/// background.
ColorScheme _applyPureBlack(ColorScheme cs) => cs.copyWith(
      surface: Colors.black,
      surfaceContainerLowest: Colors.black,
      surfaceContainerLow: const Color(0xFF0A0A0A),
      surfaceContainer: const Color(0xFF121212),
      surfaceContainerHigh: const Color(0xFF1C1C1C),
      surfaceContainerHighest: const Color(0xFF242424),
    );

/// [dynamicScheme] is the device's Material You palette (from
/// `DynamicColorBuilder`'s `darkDynamic`), used in place of the hardcoded
/// scheme when the user has enabled the "Use Material You" setting.
///
/// [pureBlack] swaps the dark scheme's surfaces for true blacks (the "OLED
/// theme" setting), which saves battery and reduces glare on OLED panels.
ThemeData buildDarkTheme({ColorScheme? dynamicScheme, bool pureBlack = false}) {
  final cs = dynamicScheme ?? _darkColorScheme();
  return _buildTheme(pureBlack ? _applyPureBlack(cs) : cs, Brightness.dark);
}

/// [dynamicScheme] is the device's Material You palette (from
/// `DynamicColorBuilder`'s `lightDynamic`), used in place of the hardcoded
/// seed-generated scheme when the user has enabled the "Use Material You"
/// setting.
ThemeData buildLightTheme({ColorScheme? dynamicScheme}) => _buildTheme(
      dynamicScheme ??
          ColorScheme.fromSeed(seedColor: _seedColor, brightness: Brightness.light),
      Brightness.light,
    );

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
    splashFactory: InkSparkle.splashFactory,
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: CrossfadePageTransitionsBuilder(),
      },
    ),
    extensions: [isDark ? AppSemanticColors.dark : AppSemanticColors.light],
       appBarTheme: AppBarTheme(
      backgroundColor: cs.surface,
      foregroundColor: cs.onSurface,
      elevation: 0,
      scrolledUnderElevation: 3,
      surfaceTintColor: cs.surfaceTint,
      centerTitle: false,
      titleTextStyle: TextStyle(
        fontSize: 22,
        fontWeight: FontWeight.w400,
        color: cs.onSurface,
      ),
      iconTheme: IconThemeData(color: cs.onSurface, size: AppIconSize.action),
      actionsIconTheme: IconThemeData(color: cs.onSurfaceVariant),
      // Default for standard pages: matches cs.surface
      systemOverlayStyle: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
        statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
        systemNavigationBarColor: cs.surfaceContainer,
        systemNavigationBarDividerColor: Colors.transparent,
        systemNavigationBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
        systemNavigationBarContrastEnforced: false,
        systemStatusBarContrastEnforced: false,
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
      filled: true,
      fillColor: cs.surfaceContainerHigh,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        borderSide: BorderSide(color: cs.primary, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        borderSide: BorderSide(color: cs.error, width: 1.5),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
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
      showDragHandle: true,
      dragHandleColor: cs.onSurfaceVariant.withValues(alpha: 0.4),
      elevation: 1,
      modalElevation: 1,
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: Colors.transparent,
      elevation: 0,
      contentTextStyle: TextStyle(color: cs.onInverseSurface, fontSize: 14),
      actionTextColor: cs.inversePrimary,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.full)),
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