import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/core/pdf/pdf_theme.dart';
import 'package:payroll_flutter/features/documents/blocks/key_value_block.dart';

void main() {
  test('KeyValueBlock stores rows in order', () {
    const block = KeyValueBlock([
      KeyValueRow('Name', 'Donald'),
      KeyValueRow('Date', '2026-05-05'),
    ]);
    expect(block.rows.length, 2);
    expect(block.rows[0].label, 'Name');
    expect(block.rows[1].value, '2026-05-05');
  });

  test('renders without throwing', () async {
    final theme = await PdfTheme.defaults();
    expect(
      () => const KeyValueBlock([KeyValueRow('A', 'B')]).toPdf(theme),
      returnsNormally,
    );
  });
}
