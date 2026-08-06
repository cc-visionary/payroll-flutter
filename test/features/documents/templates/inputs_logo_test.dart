import 'dart:typed_data';
import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/features/documents/templates/salary_adjustment_inputs.dart';

void main() {
  final logo = Uint8List.fromList(const [1, 2, 3]);

  test('salary_adjustment copyWith carries logoBytes; toJson omits it', () {
    final i = SalaryAdjustmentInputs(
      employeeId: 'e',
      employeeFullName: 'B',
      companyId: 'c',
      companyName: 'Co',
      effectiveDate: DateTime(2026, 7, 1),
      issueDate: DateTime(2026, 6, 5),
      oldSalary: Decimal.parse('1'),
      newSalary: Decimal.parse('2'),
    );
    final withLogo = i.copyWith(logoBytes: logo);
    expect(withLogo.logoBytes, logo);
    expect(withLogo.toJson().containsKey('logoBytes'), isFalse);
    // copyWith without the arg preserves the existing logo
    expect(withLogo.copyWith(reason: 'x').logoBytes, logo);
  });
}
