import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/data/models/kpi_input.dart';
import 'package:payroll_flutter/features/kpi_results/exception_aggregation.dart';

KpiException _x({
  required String on,
  num qty = 1,
  String? employeeId,
  DateTime? confirmedAt,
}) => KpiException(
  id: 'x-$on-$qty-${employeeId ?? ''}',
  companyId: 'c',
  kpiId: 'k-1',
  employeeId: employeeId,
  occurredOn: DateTime.parse(on),
  quantity: qty,
  reportedVia: ReportedVia.app,
  confirmedAt: confirmedAt,
);

void main() {
  final confirmed = DateTime(2026, 9, 20);

  test('unconfirmed exceptions do not count', () {
    final n = confirmedCountFor(
      exceptions: [_x(on: '2026-08-04'), _x(on: '2026-08-09')],
      period: '2026-08',
    );
    expect(n, 0);
  });

  test('confirmed exceptions sum their quantity, not their row count', () {
    final n = confirmedCountFor(
      exceptions: [
        _x(on: '2026-08-04', qty: 2, confirmedAt: confirmed),
        _x(on: '2026-08-09', qty: 1, confirmedAt: confirmed),
      ],
      period: '2026-08',
    );
    expect(n, 3);
  });

  test('a late confirmation lands in the month it HAPPENED', () {
    // Confirmed in September, occurred in August. August is the answer;
    // bucketing by confirmed_at would quietly move history.
    final n = confirmedCountFor(
      exceptions: [_x(on: '2026-08-31', confirmedAt: DateTime(2026, 9, 15))],
      period: '2026-08',
    );
    expect(n, 1);
  });

  test('other months are excluded', () {
    final n = confirmedCountFor(
      exceptions: [
        _x(on: '2026-07-31', confirmedAt: confirmed),
        _x(on: '2026-09-01', confirmedAt: confirmed),
      ],
      period: '2026-08',
    );
    expect(n, 0);
  });

  test('filtering by employee narrows to that person', () {
    final xs = [
      _x(on: '2026-08-04', employeeId: 'e-1', confirmedAt: confirmed),
      _x(on: '2026-08-05', employeeId: 'e-2', confirmedAt: confirmed),
    ];
    expect(confirmedCountFor(exceptions: xs, period: '2026-08',
        employeeId: 'e-1'), 1);
    expect(confirmedCountFor(exceptions: xs, period: '2026-08'), 2);
  });

  test('zero confirmed is zero, and the caller decides what that means', () {
    // Returning null here would conflate "none happened" with "none
    // confirmed yet"; that distinction belongs to the compute service, which
    // knows whether any exception rows exist at all.
    expect(confirmedCountFor(exceptions: const [], period: '2026-08'), 0);
  });
}
