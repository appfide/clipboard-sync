import 'package:flutter/material.dart';

/// Design tokens for Clipboard Sync.
///
/// Direction: minimal, professional developer utility. Inter typeface, slate
/// neutrals, one blue primary, green reserved for "live/synced", subtle 1px
/// borders instead of heavy elevation, 12–16 px radii, 200 ms transitions.
/// Both schemes are explicit (not seeded) so contrast is controlled:
/// body text ≥ 4.5:1, muted text ≥ 4.5:1 on surfaces.
abstract final class AppTokens {
  /// Brand blue (light primary).
  static const Color blue600 = Color(0xFF2563EB);

  /// Brand blue (dark primary).
  static const Color blue400 = Color(0xFF60A5FA);

  /// Success / live sync.
  static const Color green500 = Color(0xFF22C55E);

  /// Success on light surfaces (AA on white).
  static const Color green700 = Color(0xFF15803D);

  /// Warning.
  static const Color amber600 = Color(0xFFD97706);

  /// Error (light).
  static const Color red600 = Color(0xFFDC2626);

  /// Error (dark).
  static const Color red400 = Color(0xFFF87171);

  // Slate scale.
  static const Color slate50 = Color(0xFFF8FAFC);
  static const Color slate100 = Color(0xFFF1F5F9);
  static const Color slate200 = Color(0xFFE2E8F0);
  static const Color slate300 = Color(0xFFCBD5E1);
  static const Color slate400 = Color(0xFF94A3B8);
  static const Color slate500 = Color(0xFF64748B);
  static const Color slate600 = Color(0xFF475569);
  static const Color slate700 = Color(0xFF334155);
  static const Color slate800 = Color(0xFF1E293B);
  static const Color slate900 = Color(0xFF0F172A);
  static const Color slate950 = Color(0xFF0B1220);

  /// Card / control radius.
  static const double radius = 12;

  /// Section radius.
  static const double radiusLg = 16;

  /// Micro-interaction duration.
  static const Duration fast = Duration(milliseconds: 200);

  /// Desktop breakpoint: navigation rail + wide layout.
  static const double desktopBreakpoint = 900;

  /// Max content width on wide screens.
  static const double contentMaxWidth = 760;
}

/// Extra semantic colours not covered by [ColorScheme].
@immutable
class AppColors extends ThemeExtension<AppColors> {
  /// Creates the extension.
  const AppColors({
    required this.success,
    required this.warning,
    required this.muted,
    required this.border,
    required this.surfaceRaised,
    required this.surfaceSunken,
  });

  /// Live / synced.
  final Color success;

  /// Pending / degraded.
  final Color warning;

  /// Secondary text (≥ 4.5:1 on surface).
  final Color muted;

  /// Hairline borders.
  final Color border;

  /// Cards.
  final Color surfaceRaised;

  /// Inputs, code blocks.
  final Color surfaceSunken;

  @override
  AppColors copyWith({
    Color? success,
    Color? warning,
    Color? muted,
    Color? border,
    Color? surfaceRaised,
    Color? surfaceSunken,
  }) => AppColors(
    success: success ?? this.success,
    warning: warning ?? this.warning,
    muted: muted ?? this.muted,
    border: border ?? this.border,
    surfaceRaised: surfaceRaised ?? this.surfaceRaised,
    surfaceSunken: surfaceSunken ?? this.surfaceSunken,
  );

  @override
  AppColors lerp(AppColors? other, double t) {
    if (other == null) return this;
    return AppColors(
      success: Color.lerp(success, other.success, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      muted: Color.lerp(muted, other.muted, t)!,
      border: Color.lerp(border, other.border, t)!,
      surfaceRaised: Color.lerp(surfaceRaised, other.surfaceRaised, t)!,
      surfaceSunken: Color.lerp(surfaceSunken, other.surfaceSunken, t)!,
    );
  }

  /// Light values.
  static const AppColors light = AppColors(
    success: AppTokens.green700,
    warning: AppTokens.amber600,
    muted: AppTokens.slate600,
    border: AppTokens.slate200,
    surfaceRaised: Colors.white,
    surfaceSunken: AppTokens.slate100,
  );

  /// Dark values.
  static const AppColors dark = AppColors(
    success: AppTokens.green500,
    warning: Color(0xFFFBBF24),
    muted: AppTokens.slate400,
    border: AppTokens.slate700,
    surfaceRaised: AppTokens.slate800,
    surfaceSunken: AppTokens.slate950,
  );
}

/// Builds the light and dark [ThemeData].
abstract final class AppTheme {
  /// Light theme.
  static ThemeData light() => _build(
    brightness: Brightness.light,
    scheme: const ColorScheme(
      brightness: Brightness.light,
      primary: AppTokens.blue600,
      onPrimary: Colors.white,
      primaryContainer: Color(0xFFDBEAFE),
      onPrimaryContainer: Color(0xFF1E3A8A),
      secondary: AppTokens.slate700,
      onSecondary: Colors.white,
      secondaryContainer: AppTokens.slate100,
      onSecondaryContainer: AppTokens.slate900,
      tertiary: AppTokens.green700,
      onTertiary: Colors.white,
      tertiaryContainer: Color(0xFFDCFCE7),
      onTertiaryContainer: Color(0xFF14532D),
      error: AppTokens.red600,
      onError: Colors.white,
      errorContainer: Color(0xFFFEE2E2),
      onErrorContainer: Color(0xFF7F1D1D),
      surface: AppTokens.slate50,
      onSurface: AppTokens.slate900,
      onSurfaceVariant: AppTokens.slate600,
      surfaceContainerLowest: Colors.white,
      surfaceContainerLow: Colors.white,
      surfaceContainer: AppTokens.slate100,
      surfaceContainerHigh: AppTokens.slate200,
      surfaceContainerHighest: AppTokens.slate200,
      outline: AppTokens.slate300,
      outlineVariant: AppTokens.slate200,
      inverseSurface: AppTokens.slate900,
      onInverseSurface: AppTokens.slate50,
      inversePrimary: AppTokens.blue400,
      shadow: Colors.black,
      scrim: Colors.black,
    ),
    colors: AppColors.light,
  );

  /// Dark theme.
  static ThemeData dark() => _build(
    brightness: Brightness.dark,
    scheme: const ColorScheme(
      brightness: Brightness.dark,
      primary: AppTokens.blue400,
      onPrimary: AppTokens.slate950,
      primaryContainer: Color(0xFF1E3A8A),
      onPrimaryContainer: Color(0xFFDBEAFE),
      secondary: AppTokens.slate300,
      onSecondary: AppTokens.slate900,
      secondaryContainer: AppTokens.slate700,
      onSecondaryContainer: AppTokens.slate100,
      tertiary: AppTokens.green500,
      onTertiary: AppTokens.slate950,
      tertiaryContainer: Color(0xFF14532D),
      onTertiaryContainer: Color(0xFFDCFCE7),
      error: AppTokens.red400,
      onError: AppTokens.slate950,
      errorContainer: Color(0xFF7F1D1D),
      onErrorContainer: Color(0xFFFEE2E2),
      surface: AppTokens.slate950,
      onSurface: AppTokens.slate100,
      onSurfaceVariant: AppTokens.slate400,
      surfaceContainerLowest: AppTokens.slate950,
      surfaceContainerLow: AppTokens.slate900,
      surfaceContainer: AppTokens.slate800,
      surfaceContainerHigh: AppTokens.slate700,
      surfaceContainerHighest: AppTokens.slate700,
      outline: AppTokens.slate600,
      outlineVariant: AppTokens.slate700,
      inverseSurface: AppTokens.slate100,
      onInverseSurface: AppTokens.slate900,
      inversePrimary: AppTokens.blue600,
      shadow: Colors.black,
      scrim: Colors.black,
    ),
    colors: AppColors.dark,
  );

  static ThemeData _build({
    required Brightness brightness,
    required ColorScheme scheme,
    required AppColors colors,
  }) {
    final base = ThemeData(
      brightness: brightness,
      colorScheme: scheme,
      useMaterial3: true,
      fontFamily: 'Inter',
      scaffoldBackgroundColor: scheme.surface,
      splashFactory: InkSparkle.splashFactory,
      visualDensity: VisualDensity.standard,
    );
    final text = base.textTheme.apply(
      bodyColor: scheme.onSurface,
      displayColor: scheme.onSurface,
    );
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppTokens.radius),
      borderSide: BorderSide(color: colors.border),
    );
    return base.copyWith(
      extensions: [colors],
      textTheme: text.copyWith(
        headlineMedium: text.headlineMedium?.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: -0.5,
        ),
        headlineSmall: text.headlineSmall?.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: -0.3,
        ),
        titleLarge: text.titleLarge?.copyWith(
          fontWeight: FontWeight.w600,
          letterSpacing: -0.2,
        ),
        titleMedium: text.titleMedium?.copyWith(fontWeight: FontWeight.w600),
        titleSmall: text.titleSmall?.copyWith(fontWeight: FontWeight.w600),
        bodyLarge: text.bodyLarge?.copyWith(height: 1.5),
        bodyMedium: text.bodyMedium?.copyWith(height: 1.5),
        bodySmall: text.bodySmall?.copyWith(color: colors.muted, height: 1.4),
        labelLarge: text.labelLarge?.copyWith(fontWeight: FontWeight.w600),
        labelMedium: text.labelMedium?.copyWith(
          fontWeight: FontWeight.w600,
          letterSpacing: 0.4,
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: text.titleLarge?.copyWith(
          fontWeight: FontWeight.w600,
          letterSpacing: -0.2,
          color: scheme.onSurface,
        ),
      ),
      cardTheme: CardThemeData(
        color: colors.surfaceRaised,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTokens.radiusLg),
          side: BorderSide(color: colors.border),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: colors.border,
        thickness: 1,
        space: 1,
      ),
      listTileTheme: ListTileThemeData(
        iconColor: colors.muted,
        titleTextStyle: text.bodyLarge?.copyWith(
          fontWeight: FontWeight.w500,
          color: scheme.onSurface,
        ),
        subtitleTextStyle: text.bodySmall?.copyWith(color: colors.muted),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        minVerticalPadding: 10,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colors.surfaceRaised,
        border: border,
        enabledBorder: border,
        focusedBorder: border.copyWith(
          borderSide: BorderSide(color: scheme.primary, width: 1.5),
        ),
        errorBorder: border.copyWith(
          borderSide: BorderSide(color: scheme.error),
        ),
        focusedErrorBorder: border.copyWith(
          borderSide: BorderSide(color: scheme.error, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 14,
        ),
        hintStyle: text.bodyMedium?.copyWith(color: colors.muted),
        helperStyle: text.bodySmall?.copyWith(color: colors.muted),
        labelStyle: text.bodyMedium?.copyWith(color: colors.muted),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(44, 48),
          padding: const EdgeInsets.symmetric(horizontal: 20),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTokens.radius),
          ),
          textStyle: text.labelLarge?.copyWith(fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(44, 48),
          padding: const EdgeInsets.symmetric(horizontal: 20),
          side: BorderSide(color: colors.border),
          foregroundColor: scheme.onSurface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTokens.radius),
          ),
          textStyle: text.labelLarge?.copyWith(fontWeight: FontWeight.w600),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(44, 44),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTokens.radius),
          ),
          textStyle: text.labelLarge?.copyWith(fontWeight: FontWeight.w600),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          minimumSize: const Size(44, 44),
          foregroundColor: colors.muted,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? Colors.white : colors.muted,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected)
              ? scheme.primary
              : colors.surfaceSunken,
        ),
        trackOutlineColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected)
              ? Colors.transparent
              : colors.border,
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: colors.surfaceSunken,
        side: BorderSide(color: colors.border),
        labelStyle: text.labelMedium?.copyWith(color: scheme.onSurface),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: scheme.inverseSurface,
        contentTextStyle: text.bodyMedium?.copyWith(
          color: scheme.onInverseSurface,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTokens.radius),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: colors.surfaceRaised,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTokens.radiusLg),
        ),
        titleTextStyle: text.titleLarge?.copyWith(
          fontWeight: FontWeight.w600,
          color: scheme.onSurface,
        ),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: scheme.surface,
        indicatorColor: scheme.primaryContainer,
        selectedIconTheme: IconThemeData(color: scheme.onPrimaryContainer),
        unselectedIconTheme: IconThemeData(color: colors.muted),
        selectedLabelTextStyle: text.labelMedium?.copyWith(
          color: scheme.onSurface,
        ),
        unselectedLabelTextStyle: text.labelMedium?.copyWith(
          color: colors.muted,
        ),
        labelType: NavigationRailLabelType.all,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: colors.surfaceRaised,
        indicatorColor: scheme.primaryContainer,
        elevation: 0,
        height: 68,
        iconTheme: WidgetStateProperty.resolveWith(
          (s) => IconThemeData(
            color: s.contains(WidgetState.selected)
                ? scheme.onPrimaryContainer
                : colors.muted,
          ),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (s) => text.labelMedium?.copyWith(
            color: s.contains(WidgetState.selected)
                ? scheme.onSurface
                : colors.muted,
          ),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: colors.surfaceRaised,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTokens.radius),
          side: BorderSide(color: colors.border),
        ),
        textStyle: text.bodyMedium?.copyWith(color: scheme.onSurface),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: scheme.inverseSurface,
          borderRadius: BorderRadius.circular(8),
        ),
        textStyle: text.bodySmall?.copyWith(color: scheme.onInverseSurface),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: scheme.primary),
    );
  }
}

/// Convenience accessor for [AppColors].
extension AppColorsX on BuildContext {
  /// Semantic colours for the current theme.
  AppColors get colors => Theme.of(this).extension<AppColors>()!;
}
