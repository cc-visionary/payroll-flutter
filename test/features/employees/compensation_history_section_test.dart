import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/app/status_colors.dart';
import 'package:payroll_flutter/features/employees/profile/widgets/compensation_history_section.dart';

void main() {
  group('statusToneFor', () {
    test('SCHEDULED is a warning tone', () {
      expect(statusToneFor('SCHEDULED'), StatusTone.warning);
    });
    test('APPLIED is a success tone', () {
      expect(statusToneFor('APPLIED'), StatusTone.success);
    });
    test('CANCELLED is a danger tone', () {
      expect(statusToneFor('CANCELLED'), StatusTone.danger);
    });
  });
}
