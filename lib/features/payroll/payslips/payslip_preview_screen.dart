import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:printing/printing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../data/models/calendar_event.dart';
import '../../../data/models/employee.dart';
import '../../../data/models/payslip.dart';
import '../../../data/models/shift_template.dart';
import '../../../data/repositories/attendance_repository.dart';
import '../../../data/repositories/employee_repository.dart';
import '../../../data/repositories/holiday_repository.dart';
import '../../../data/repositories/payroll_repository.dart';
import '../../../data/repositories/role_scorecard_repository.dart';
import '../../../data/repositories/shift_template_repository.dart';
import '../../attendance/attendance_row_vm.dart';
import '../../auth/profile_provider.dart';
import 'payslip_pdf.dart';

final _payslipProvider = FutureProvider.family<Payslip?, String>((ref, id) {
  return ref.watch(payrollRepositoryProvider).payslipById(id);
});

class PayslipPreviewScreen extends ConsumerWidget {
  final String payslipId;
  const PayslipPreviewScreen({super.key, required this.payslipId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(_payslipProvider(payslipId));

    return Scaffold(
      appBar: AppBar(title: const Text('Payslip')),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Text('Error: $e', style: const TextStyle(color: Colors.red)),
        ),
        data: (ps) {
          if (ps == null) return const Center(child: Text('Payslip not found.'));
          return FutureBuilder<_PdfContext>(
            future: _loadContext(ref, ps),
            builder: (context, snap) {
              if (snap.hasError) {
                return Center(
                  child: Text(
                    'Failed to load payslip context: ${snap.error}',
                    style: const TextStyle(color: Colors.red),
                  ),
                );
              }
              if (!snap.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final ctx = snap.data!;
              // Printing is only genuinely useful where the host OS has a
              // print dialog. On web we skip it (browser printing of
              // embedded PDFs is inconsistent across engines). Desktop +
              // iOS/Android all get it.
              final canPrint =
                  !kIsWeb && (Platform.isLinux ||
                      Platform.isMacOS ||
                      Platform.isWindows ||
                      Platform.isAndroid ||
                      Platform.isIOS);
              final filename = _filenameForPayslip(ps, ctx.employee.employeeNumber);
              return PdfPreview(
                // Disable built-in buttons so only our two custom actions
                // show. `canChange*` flags already hide their dropdowns;
                // turning off printing + sharing swaps their default icons
                // out for our explicit "Download" / "Print" actions below.
                allowPrinting: false,
                allowSharing: false,
                canChangeOrientation: false,
                canChangePageFormat: false,
                canDebug: false,
                actions: [
                  PdfPreviewAction(
                    icon: const Icon(Icons.download),
                    onPressed: (ctx, build, pageFormat) async {
                      final bytes = await build(pageFormat);
                      await Printing.sharePdf(bytes: bytes, filename: filename);
                    },
                  ),
                  if (canPrint)
                    PdfPreviewAction(
                      icon: const Icon(Icons.print),
                      onPressed: (ctx, build, pageFormat) async {
                        await Printing.layoutPdf(
                          onLayout: (format) => build(format),
                          name: filename,
                        );
                      },
                    ),
                ],
                build: (format) async => buildPayslipPdf(PayslipPdfInput(
                  payslip: ps,
                  employee: ctx.employee,
                  companyName: ctx.companyName,
                  periodStart: ctx.periodStart,
                  periodEnd: ctx.periodEnd,
                  payDate: ctx.payDate,
                  attendanceRows: ctx.attendanceRows,
                )),
              );
            },
          );
        },
      ),
    );
  }
}

/// Suggested filename shown in the Save / Share dialog. Prefer the payslip's
/// human-readable number (e.g. EMP-001-2026-01-001); fall back to employee +
/// first 8 of the uuid so files still sort sensibly when the number is null.
String _filenameForPayslip(Payslip ps, String employeeNumber) {
  final base = ps.payslipNumber ??
      '$employeeNumber-${ps.id.substring(0, 8).toUpperCase()}';
  return '$base.pdf';
}

class _PdfContext {
  final Employee employee;
  final String companyName;
  final DateTime periodStart;
  final DateTime periodEnd;
  final DateTime payDate;
  final List<AttendanceRowVm> attendanceRows;
  _PdfContext({
    required this.employee,
    required this.companyName,
    required this.periodStart,
    required this.periodEnd,
    required this.payDate,
    required this.attendanceRows,
  });
}

Future<_PdfContext> _loadContext(WidgetRef ref, Payslip ps) async {
  final empRepo = ref.read(employeeRepositoryProvider);
  final emp = await empRepo.byId(ps.employeeId);
  if (emp == null) throw Exception('Employee not found for payslip ${ps.id}');

  final period = await _loadPeriod(ps.payrollRunId);
  // Period dates drive both the PDF header and the attendance page. If the
  // join failed, fall back to the payslip's createdAt so the PDF still
  // renders (page 2 is skipped when no attendance rows come back).
  final periodStart = period?.startDate ?? ps.createdAt;
  final periodEnd = period?.endDate ?? ps.createdAt;
  final payDate = period?.payDate ?? ps.createdAt;

  // Fetch attendance + shifts + holidays + scorecard in parallel — page 2
  // needs all four and they have no dependencies between them.
  final attendanceFuture = ref.read(attendanceRepositoryProvider).listByRange(
        start: periodStart,
        end: periodEnd,
        employeeId: emp.id,
      );
  final shiftsFuture = ref.read(shiftTemplateRepositoryProvider).list();
  final scorecardsFuture = ref.read(roleScorecardRepositoryProvider).list();

  final holidays = await _loadHolidaysForRange(ref, periodStart, periodEnd);
  final records = await attendanceFuture;
  final shiftList = await shiftsFuture;
  final scorecards = await scorecardsFuture;

  final shifts = {for (final s in shiftList) s.id: s};
  final holidayByDate = <String, CalendarEvent>{
    for (final h in holidays) isoDate(h.date): h,
  };

  ShiftTemplate? defaultShift;
  String? workDaysPerWeek;
  final scId = emp.roleScorecardId;
  if (scId != null) {
    for (final c in scorecards) {
      if (c.id == scId) {
        workDaysPerWeek = c.workDaysPerWeek;
        if (c.shiftTemplateId != null) {
          defaultShift = shifts[c.shiftTemplateId];
        }
        break;
      }
    }
  }

  final attendanceRows = buildAttendanceRows(
    start: periodStart,
    end: periodEnd,
    records: records,
    shifts: shifts,
    holidays: holidayByDate,
    defaultShift: defaultShift,
    workDaysPerWeek: workDaysPerWeek,
    // Payslip covers the full period regardless of "today" — include future
    // days in the table so the grid looks intact even when we preview a
    // payslip before the period closes.
    skipFutureDays: false,
  );

  // Prefer hiring-entity trade name if available; fall back to plain "Company"
  // until the companies table fetch is wired through to this screen.
  final companyName = 'Company';

  return _PdfContext(
    employee: emp,
    companyName: companyName,
    periodStart: periodStart,
    periodEnd: periodEnd,
    payDate: payDate,
    attendanceRows: attendanceRows,
  );
}

class _Period {
  final DateTime startDate;
  final DateTime endDate;
  final DateTime payDate;
  _Period({required this.startDate, required this.endDate, required this.payDate});
}

/// Look up the pay period for a payroll run. Period fields live on
/// payroll_runs directly after migration 20260418000001.
Future<_Period?> _loadPeriod(String runId) async {
  try {
    final row = await Supabase.instance.client
        .from('payroll_runs')
        .select('period_start, period_end, pay_date')
        .eq('id', runId)
        .maybeSingle();
    if (row == null) return null;
    return _Period(
      startDate: DateTime.parse(row['period_start'] as String),
      endDate: DateTime.parse(row['period_end'] as String),
      payDate: DateTime.parse(row['pay_date'] as String),
    );
  } catch (_) {
    return null;
  }
}

/// Fetch holiday events for every year the period touches (periods can
/// straddle Dec→Jan). Returns a flat list; dedup isn't needed because each
/// year's calendar has its own events keyed by date.
Future<List<CalendarEvent>> _loadHolidaysForRange(
  WidgetRef ref,
  DateTime start,
  DateTime end,
) async {
  final repo = ref.read(holidayRepositoryProvider);
  final profile = await ref.read(userProfileProvider.future);
  if (profile == null) return const [];
  final companyId = profile.companyId;
  final years = <int>{for (var y = start.year; y <= end.year; y++) y};
  final out = <CalendarEvent>[];
  for (final y in years) {
    final cal = await repo.byYear(companyId, y);
    if (cal == null) continue;
    out.addAll(await repo.events(cal.id));
  }
  return out;
}
