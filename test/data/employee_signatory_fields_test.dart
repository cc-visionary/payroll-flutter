import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/data/models/employee.dart';

Map<String, dynamic> _baseRow() => {
      'id': 'E1',
      'company_id': 'C1',
      'employee_number': 'EMP-001',
      'first_name': 'Brixter',
      'last_name': 'Del Mundo',
      'employment_type': 'REGULAR',
      'employment_status': 'ACTIVE',
      'hire_date': '2024-01-01',
    };

void main() {
  test('fromRow parses signatory fields', () {
    final e = Employee.fromRow({
      ..._baseRow(),
      'is_hr_signatory': true,
      'is_legal_signatory': false,
      'signatory_title': 'HR Manager',
      'signature_png': 'QUJD',
    });
    expect(e.isHrSignatory, isTrue);
    expect(e.isLegalSignatory, isFalse);
    expect(e.signatoryTitle, 'HR Manager');
    expect(e.signaturePngB64, 'QUJD');
  });

  test('fromRow defaults signatory fields when columns are absent', () {
    final e = Employee.fromRow(_baseRow());
    expect(e.isHrSignatory, isFalse);
    expect(e.isLegalSignatory, isFalse);
    expect(e.signatoryTitle, isNull);
    expect(e.signaturePngB64, isNull);
  });
}
