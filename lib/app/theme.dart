import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'tokens.dart';

class AppTheme {
  static ThemeData light() => _build(LuxiumColors.light);
  static ThemeData dark() => _build(LuxiumColors.dark);

  static ThemeData _build(LuxiumPalette p) {
    final scheme = p.toColorScheme();
    final textTheme = _luxiumTextTheme(scheme.onSurface);

    return ThemeData(
      useMaterial3: true,
      brightness: scheme.brightness,
      colorScheme: scheme,
      visualDensity: VisualDensity.compact,
      scaffoldBackgroundColor: p.background,
      canvasColor: p.background,
      dividerColor: p.border,
      textTheme: textTheme,
      primaryTextTheme: textTheme,
      fontFamily: 'Satoshi',

      appBarTheme: AppBarTheme(
        backgroundColor: p.surface,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 1,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: textTheme.titleLarge,
      ),

      cardTheme: CardThemeData(
        color: p.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(LuxiumRadius.lg),
          side: BorderSide(color: p.border, width: 1),
        ),
      ),

      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: p.cta,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(LuxiumRadius.lg)),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          textStyle: textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
        ),
      ),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: p.cta,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(LuxiumRadius.lg)),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: scheme.onSurface,
          side: BorderSide(color: p.border),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(LuxiumRadius.lg)),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: p.cta,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(LuxiumRadius.lg)),
        ),
      ),

      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(foregroundColor: scheme.onSurfaceVariant),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: p.inputBg,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(LuxiumRadius.lg),
          borderSide: BorderSide(color: p.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(LuxiumRadius.lg),
          borderSide: BorderSide(color: p.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(LuxiumRadius.lg),
          borderSide: BorderSide(color: p.cta, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        labelStyle: textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
        hintStyle: textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
      ),

      chipTheme: ChipThemeData(
        backgroundColor: p.muted,
        labelStyle: textTheme.labelSmall?.copyWith(color: scheme.onSurface),
        side: BorderSide.none,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
      ),

      dividerTheme: DividerThemeData(color: p.border, thickness: 1, space: 1),

      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: p.surface,
        indicatorColor: p.cta.withValues(alpha: 0.12),
        selectedIconTheme: IconThemeData(color: p.cta),
        selectedLabelTextStyle: textTheme.labelMedium?.copyWith(color: p.cta, fontWeight: FontWeight.w600),
        unselectedIconTheme: IconThemeData(color: scheme.onSurfaceVariant),
        unselectedLabelTextStyle: textTheme.labelMedium?.copyWith(color: scheme.onSurfaceVariant),
      ),

      drawerTheme: DrawerThemeData(
        backgroundColor: p.surface,
        surfaceTintColor: Colors.transparent,
      ),

      dialogTheme: DialogThemeData(
        backgroundColor: p.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(LuxiumRadius.xl)),
      ),

      snackBarTheme: SnackBarThemeData(
        backgroundColor: scheme.inverseSurface,
        contentTextStyle: textTheme.bodyMedium?.copyWith(color: scheme.onInverseSurface),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(LuxiumRadius.lg)),
      ),

      dataTableTheme: DataTableThemeData(
        headingTextStyle: textTheme.labelMedium?.copyWith(
          color: scheme.onSurfaceVariant,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.2,
        ),
        dataTextStyle: textTheme.bodyMedium,
        dividerThickness: 1,
        headingRowColor: WidgetStateProperty.all(p.muted),
      ),
    );
  }

  /// Type scale ported from Luxium-website Stripe-HDS scale. All headings
  /// use Satoshi 700 with tight negative tracking; body uses Satoshi 400.
  static TextTheme _luxiumTextTheme(Color onSurface) {
    TextStyle h(double size, double tracking) => TextStyle(
          fontFamily: 'Satoshi',
          fontSize: size,
          fontWeight: FontWeight.w700,
          letterSpacing: tracking,
          color: onSurface,
          height: 1.15,
        );
    TextStyle b(double size, {FontWeight w = FontWeight.w400, double ls = 0}) => TextStyle(
          fontFamily: 'Satoshi',
          fontSize: size,
          fontWeight: w,
          letterSpacing: ls,
          color: onSurface,
          height: 1.5,
        );
    return TextTheme(
      displayLarge: h(56, -1.12),
      displayMedium: h(48, -0.96),
      displaySmall: h(36, -0.72),
      headlineLarge: h(36, -0.72),
      headlineMedium: h(28, -0.56),
      headlineSmall: h(20, -0.40),
      titleLarge: h(20, -0.40),
      titleMedium: h(16, -0.16),
      titleSmall: b(14, w: FontWeight.w600),
      bodyLarge: b(16),
      bodyMedium: b(14),
      bodySmall: b(12, ls: 0.1),
      labelLarge: b(14, w: FontWeight.w600),
      labelMedium: b(12, w: FontWeight.w500),
      labelSmall: b(11, w: FontWeight.w500, ls: 0.2),
    );
  }

  /// Monospace for tabular/numeric/ID text. Brand spec calls for Geist Mono;
  /// google_fonts doesn't ship Geist yet, so we use JetBrains Mono — visually
  /// closest substitute with similar metrics. Switch when Geist lands or when
  /// the team decides to bundle Geist locally.
  ///
  /// Usage: `Text(value, style: AppTheme.mono(context))`
  static TextStyle mono(BuildContext context, {double? fontSize, FontWeight? fontWeight, Color? color}) {
    return GoogleFonts.jetBrainsMono(
      fontSize: fontSize ?? 13,
      fontWeight: fontWeight ?? FontWeight.w400,
      color: color ?? Theme.of(context).colorScheme.onSurface,
      height: 1.4,
    );
  }
}
