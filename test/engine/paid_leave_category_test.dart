import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/features/payroll/engine/types.dart';

void main() {
  test('PAID_LEAVE enum value exists and serializes to the DB label', () {
    expect(PayslipLineCategory.PAID_LEAVE.name, 'PAID_LEAVE');
  });
}
