import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/core/pdf/pdf_theme.dart';
import 'package:payroll_flutter/features/documents/blocks/table_block.dart';
import 'package:payroll_flutter/features/documents/blocks/fillable_table_block.dart';

void main() {
  test('TableBlock stores headers and rows', () {
    const block = TableBlock(
      headers: ['Item', 'Qty'],
      rows: [
        ['GameCove ID', '1'],
        ['Lanyard', '1'],
      ],
    );
    expect(block.headers.length, 2);
    expect(block.rows.length, 2);
  });

  test('FillableTableBlock generates blank rows', () {
    const block = FillableTableBlock(
      headers: ['Date', 'Explanation', 'Amount Loss (₱)'],
      blankRows: 4,
    );
    expect(block.blankRows, 4);
    expect(block.headers.length, 3);
  });

  test('blocks render without throwing', () async {
    final theme = await PdfTheme.defaults();
    expect(
      () => const TableBlock(
        headers: ['A'],
        rows: [['1']],
      ).toPdf(theme),
      returnsNormally,
    );
    expect(
      () => const FillableTableBlock(headers: ['A'], blankRows: 2).toPdf(theme),
      returnsNormally,
    );
  });
}
