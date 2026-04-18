import 'package:flutter/material.dart';

/// Luxium brand tokens — single source of truth for all colors, radii, and
/// status palettes. Values mirror `.impeccable.md` and the canonical website
/// (`luxium-website/src/app/globals.css`).
///
/// Don't write `Color(0xFF...)` literals in feature code. Pull from
/// `Theme.of(context).colorScheme.*`, `LuxiumColors.of(context).*`, or a
/// `StatusPalette` token below.

class LuxiumPalette {
  final Brightness brightness;
  final Color background;
  final Color surface;
  final Color muted;
  final Color foreground;
  final Color subdued;
  final Color soft;
  final Color cta;
  final Color ctaTint;
  final Color ctaBorder;
  final Color accentGreen;
  final Color border;
  final Color inputBg;

  const LuxiumPalette({
    required this.brightness,
    required this.background,
    required this.surface,
    required this.muted,
    required this.foreground,
    required this.subdued,
    required this.soft,
    required this.cta,
    required this.ctaTint,
    required this.ctaBorder,
    required this.accentGreen,
    required this.border,
    required this.inputBg,
  });

  ColorScheme toColorScheme() => ColorScheme(
        brightness: brightness,
        primary: cta,
        onPrimary: Colors.white,
        primaryContainer: ctaTint,
        onPrimaryContainer: cta,
        secondary: accentGreen,
        onSecondary: Colors.white,
        secondaryContainer: accentGreen.withValues(alpha: 0.15),
        onSecondaryContainer: brightness == Brightness.light ? const Color(0xFF0B7B66) : accentGreen,
        tertiary: const Color(0xFFFF6118),
        onTertiary: Colors.white,
        error: brightness == Brightness.light ? const Color(0xFF991B1B) : const Color(0xFFFF8A8A),
        onError: brightness == Brightness.light ? Colors.white : const Color(0xFF1A0000),
        errorContainer: brightness == Brightness.light ? const Color(0xFFFEE2E2) : const Color(0x2EDC2626),
        onErrorContainer: brightness == Brightness.light ? const Color(0xFF991B1B) : const Color(0xFFFF8A8A),
        surface: surface,
        onSurface: foreground,
        surfaceContainerLowest: background,
        surfaceContainerLow: background,
        surfaceContainer: muted,
        surfaceContainerHigh: muted,
        surfaceContainerHighest: muted,
        onSurfaceVariant: subdued,
        outline: border,
        outlineVariant: ctaBorder,
        shadow: Colors.black,
        scrim: Colors.black54,
        inverseSurface: brightness == Brightness.light ? LuxiumColors.dark.surface : LuxiumColors.light.surface,
        onInverseSurface: brightness == Brightness.light ? LuxiumColors.dark.foreground : LuxiumColors.light.foreground,
        inversePrimary: brightness == Brightness.light ? LuxiumColors.dark.cta : LuxiumColors.light.cta,
      );
}

class LuxiumColors {
  /// Light-mode palette — verbatim from luxium-website globals.css.
  static const light = LuxiumPalette(
    brightness: Brightness.light,
    background: Color(0xFFF7FAFC),
    surface: Color(0xFFFFFFFF),
    muted: Color(0xFFF5F5F5),
    foreground: Color(0xFF0A2540),
    subdued: Color(0xFF3C4F69),
    soft: Color(0xFF425466),
    cta: Color(0xFF635BFF),
    ctaTint: Color(0xFFE8E9FF),
    ctaBorder: Color(0xFFD6D9FC),
    accentGreen: Color(0xFF00D4AA),
    border: Color(0xFFD0D9E4),
    inputBg: Color(0xFFE5EDF5),
  );

  /// Dark-mode palette — Luxium-tinted (deep navy + lifted purple CTA).
  static const dark = LuxiumPalette(
    brightness: Brightness.dark,
    background: Color(0xFF0A1628),
    surface: Color(0xFF0F1F35),
    muted: Color(0xFF1A2C45),
    foreground: Color(0xFFF7FAFC),
    subdued: Color(0xFFC7D1DD),
    soft: Color(0xFF9AA8BC),
    cta: Color(0xFF7F7DFC),
    ctaTint: Color(0x2E7F7DFC),
    ctaBorder: Color(0xFF2A3F66),
    accentGreen: Color(0xFF00D4AA),
    border: Color(0xFF1F3354),
    inputBg: Color(0xFF1A2C45),
  );

  /// Convenience: pick the active palette from context.
  static LuxiumPalette of(BuildContext context) =>
      Theme.of(context).brightness == Brightness.light ? light : dark;
}

class LuxiumRadius {
  static const double sm = 4;
  static const double md = 5;
  static const double lg = 6;
  static const double xl = 8;
  static const double xxl = 11;
  static const double pill = 999;
}

class LuxiumSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
  static const double xxxl = 48;
  static const double huge = 64;
}

/// Display-layer helpers — keep underlying math in `double` / `Decimal`; only
/// the rendered string changes. Shared across every attendance / payroll view
/// so a minute value reads identically wherever it appears.

/// Format a minute count inline — for table cells, calendar chips, and
/// anywhere else the value has no dedicated "unit" slot. Keeps three
/// decimals so what the admin sees on screen matches exactly what the
/// payroll engine stores (fractional seconds matter for reconciliation).
///   - `< 0.001`  → `—`
///   - otherwise  → `N.NNNm`  (minutes, 3 decimals, compact "m" suffix)
String fmtDuration(double mins) {
  if (mins < 0.001) return '—';
  return '${mins.toStringAsFixed(3)}m';
}

/// Same value as [fmtDuration] but without the "m" suffix — use when the
/// rendering widget already has a dedicated "mins" label slot (e.g. the
/// primary stat tiles). Keeps the big number clean and the unit consistent
/// with the rest of the tile grid.
String fmtMinutes(double mins) {
  if (mins < 0.001) return '—';
  return mins.toStringAsFixed(3);
}
