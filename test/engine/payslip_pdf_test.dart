import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/data/models/employee.dart';
import 'package:payroll_flutter/data/models/payslip.dart';
import 'package:payroll_flutter/features/payroll/payslips/payslip_pdf.dart';

Decimal _d(String s) => Decimal.parse(s);

void main() {
  test('payslip PDF: builds a non-empty byte stream', () async {
    final emp = Employee(
      id: 'E1',
      companyId: 'C1',
      employeeNumber: 'EMP-001',
      firstName: 'Juan',
      lastName: 'Dela Cruz',
      jobTitle: 'Software Engineer',
      employmentType: 'REGULAR',
      employmentStatus: 'ACTIVE',
      hireDate: DateTime.utc(2024, 1, 1),
      isRankAndFile: true,
      isOtEligible: true,
      isNdEligible: true,
      isHolidayPayEligible: true,
      taxOnFullEarnings: false,
    );

    final ps = Payslip(
      id: 'PS-1',
      payrollRunId: 'PR-1',
      employeeId: 'E1',
      payslipNumber: 'EMP-001-2026-01-001',
      grossPay: _d('15000.00'),
      totalEarnings: _d('15000.00'),
      totalDeductions: _d('1800.00'),
      netPay: _d('13200.00'),
      sssEe: _d('500.00'),
      philhealthEe: _d('250.00'),
      pagibigEe: _d('100.00'),
      withholdingTax: _d('950.00'),
      ytdGrossPay: _d('15000.00'),
      ytdTaxableIncome: _d('14150.00'),
      ytdTaxWithheld: _d('950.00'),
      approvalStatus: 'APPROVED',
      createdAt: DateTime.utc(2026, 1, 20),
      lines: [
        PayslipLine(
          id: 'L1',
          payslipId: 'PS-1',
          category: 'BASIC_PAY',
          description: 'Basic Pay (Semi-Monthly)',
          amount: _d('15000.00'),
          sortOrder: 100,
        ),
        PayslipLine(
          id: 'L2',
          payslipId: 'PS-1',
          category: 'SSS_EE',
          description: 'SSS Employee Share',
          amount: _d('500.00'),
          sortOrder: 1100,
        ),
        PayslipLine(
          id: 'L3',
          payslipId: 'PS-1',
          category: 'PHILHEALTH_EE',
          description: 'PhilHealth Employee Share',
          amount: _d('250.00'),
          sortOrder: 1110,
        ),
        PayslipLine(
          id: 'L4',
          payslipId: 'PS-1',
          category: 'PAGIBIG_EE',
          description: 'Pag-IBIG Employee Share',
          amount: _d('100.00'),
          sortOrder: 1120,
        ),
        PayslipLine(
          id: 'L5',
          payslipId: 'PS-1',
          category: 'TAX_WITHHOLDING',
          description: 'Withholding Tax',
          amount: _d('950.00'),
          sortOrder: 1200,
        ),
      ],
    );

    final bytes = await buildPayslipPdf(PayslipPdfInput(
      payslip: ps,
      employee: emp,
      companyName: 'Luxium Philippines Inc.',
      companyTradeName: 'GameCove',
      companyAddress: 'Makati City, Metro Manila',
      periodStart: DateTime.utc(2026, 1, 1),
      periodEnd: DateTime.utc(2026, 1, 15),
      payDate: DateTime.utc(2026, 1, 20),
    ));

    // Valid PDF starts with "%PDF" magic bytes.
    expect(bytes.length, greaterThan(500));
    expect(String.fromCharCodes(bytes.sublist(0, 4)), '%PDF');
  });
}
