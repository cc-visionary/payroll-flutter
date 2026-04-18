import 'package:decimal/decimal.dart';

/// PHP money helpers. Never use `double` for payroll math.
class Money {
  static final Decimal zero = Decimal.zero;
  static final Decimal _hundred = Decimal.fromInt(100);

  /// Round to 2 decimal places, half-up (matches payrollos default rounding).
  static Decimal round2(Decimal value) {
    final scaled = (value * _hundred).round(scale: 0);
    return (scaled / _hundred).toDecimal(scaleOnInfinitePrecision: 2);
  }

  static Decimal parse(String s) => Decimal.parse(s);
  static Decimal fromInt(int i) => Decimal.fromInt(i);

  /// Convert to string with 2dp, grouping.
  static String fmtPhp(Decimal d) {
    final rounded = round2(d);
    final parts = rounded.toString().split('.');
    final whole = parts[0];
    final frac = parts.length > 1 ? parts[1].padRight(2, '0').substring(0, 2) : '00';
    final buf = StringBuffer();
    final digits = whole.replaceFirst('-', '');
    for (int i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) buf.write(',');
      buf.write(digits[i]);
    }
    final sign = whole.startsWith('-') ? '-' : '';
    return '$sign₱${buf.toString()}.$frac';
  }

  /// Same as [fmtPhp] but uses the "PHP" ASCII prefix instead of the ₱ glyph —
  /// safe for contexts (PDFs with default Helvetica) where U+20B1 is missing.
  static String fmtPhpAscii(Decimal d) {
    final rounded = round2(d);
    final parts = rounded.toString().split('.');
    final whole = parts[0];
    final frac = parts.length > 1 ? parts[1].padRight(2, '0').substring(0, 2) : '00';
    final buf = StringBuffer();
    final digits = whole.replaceFirst('-', '');
    for (int i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) buf.write(',');
      buf.write(digits[i]);
    }
    final sign = whole.startsWith('-') ? '-' : '';
    return '${sign}PHP ${buf.toString()}.$frac';
  }
}
