// Shared loader for the context a payslip PDF needs (employee, company
// info, logo bytes, pay period, attendance rows). Extracted from
// `payslip_preview_screen.dart` so the Lark-approval send flow can generate
// PDFs for bulk dispatch using the same plumbing — no duplicate context
// wiring, no drift between "Preview" output and what employees see in Lark.

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/pdf/signature_png.dart';
import '../../../data/models/calendar_event.dart';
import '../../../data/models/employee.dart';
import '../../../data/models/hiring_entity.dart';
import '../../../data/models/payslip.dart';
import '../../../data/models/shift_template.dart';
import '../../../data/repositories/attendance_repository.dart';
import '../../../data/repositories/employee_repository.dart';
import '../../../data/repositories/hiring_entity_repository.dart';
import '../../../data/repositories/holiday_repository.dart';
import '../../../data/repositories/payroll_repository.dart';
import '../../../data/repositories/role_scorecard_repository.dart';
import '../../../data/repositories/shift_template_repository.dart';
import '../../attendance/attendance_row_vm.dart';
import '../../auth/profile_provider.dart';
import 'payslip_pdf.dart';

/// Generate payslip PDFs for [payslipIds] and return them base64-encoded,
/// keyed by payslip id. Used by the Lark-approval send flow to hand the
/// edge function the attachment bytes it needs to upload to Lark.
///
/// Failures on individual payslips are re-thrown so the caller can surface
/// the specific error (rather than silently dropping one employee's PDF).
/// Call sites run this before invoking `sendPayslipApprovals`, then pass
/// the resulting map as `pdfsByPayslipId`.
Future<Map<String, String>> buildPayslipPdfsBase64ForIds(
  WidgetRef ref,
  List<String> payslipIds,
) async {
  final byId = await buildPayslipPdfBytesForIds(ref, payslipIds);
  return {for (final e in byId.entries) e.key: base64Encode(e.value)};
}

/// Same as [buildPayslipPdfsBase64ForIds] but returns raw PDF bytes plus
/// the loaded employee + period context — used by the ZIP-of-payslips
/// exporter, which needs both the bytes (to add to the archive) and the
/// employee details (to build per-file names).
class PayslipPdfBuildResult {
  final Uint8List bytes;
  final Employee employee;
  final DateTime periodStart;
  final DateTime periodEnd;
  const PayslipPdfBuildResult({
    required this.bytes,
    required this.employee,
    required this.periodStart,
    required this.periodEnd,
  });
}

Future<Map<String, Uint8List>> buildPayslipPdfBytesForIds(
  WidgetRef ref,
  List<String> payslipIds,
) async {
  final results = await buildPayslipPdfsForIds(ref, payslipIds);
  return {for (final e in results.entries) e.key: e.value.bytes};
}

Future<Map<String, PayslipPdfBuildResult>> buildPayslipPdfsForIds(
  WidgetRef ref,
  List<String> payslipIds,
) async {
  final repo = ref.read(payrollRepositoryProvider);
  final out = <String, PayslipPdfBuildResult>{};
  for (final id in payslipIds) {
    final ps = await repo.payslipById(id);
    if (ps == null) {
      throw Exception('Payslip $id not found when building PDF');
    }
    final ctx = await loadPayslipPdfContext(ref, ps);
    final bytes = await buildPayslipPdf(PayslipPdfInput(
      payslip: ps,
      employee: ctx.employee,
      companyName: ctx.companyName,
      companyTradeName: ctx.companyTradeName,
      companyAddress: ctx.companyAddress,
      companyLogoBytes: ctx.companyLogoBytes,
      companyLogoHeight: ctx.companyLogoHeight,
      periodStart: ctx.periodStart,
      periodEnd: ctx.periodEnd,
      payDate: ctx.payDate,
      attendanceRows: ctx.attendanceRows,
      hrSignatoryName: ctx.hrSignatoryName,
      hrSignatoryTitle: ctx.hrSignatoryTitle,
      hrSignaturePng: ctx.hrSignaturePng,
    ));
    out[id] = PayslipPdfBuildResult(
      bytes: bytes,
      employee: ctx.employee,
      periodStart: ctx.periodStart,
      periodEnd: ctx.periodEnd,
    );
  }
  return out;
}

class PayslipPdfContext {
  final Employee employee;
  final String companyName;
  final String? companyTradeName;
  final String? companyAddress;
  final Uint8List? companyLogoBytes;
  final double companyLogoHeight;
  final DateTime periodStart;
  final DateTime periodEnd;
  final DateTime payDate;
  final List<AttendanceRowVm> attendanceRows;
  final String? hrSignatoryName;
  final String? hrSignatoryTitle;
  final Uint8List? hrSignaturePng;
  const PayslipPdfContext({
    required this.employee,
    required this.companyName,
    this.companyTradeName,
    this.companyAddress,
    this.companyLogoBytes,
    this.companyLogoHeight = 48,
    required this.periodStart,
    required this.periodEnd,
    required this.payDate,
    required this.attendanceRows,
    this.hrSignatoryName,
    this.hrSignatoryTitle,
    this.hrSignaturePng,
  });
}

/// Build a [PayslipPdfContext] for the given payslip. All the dependent
/// repos (employee, attendance, holidays, shifts, scorecards, hiring
/// entity) are read via [ref]. Parallelizable calls are awaited together.
Future<PayslipPdfContext> loadPayslipPdfContext(
    WidgetRef ref, Payslip ps) async {
  final empRepo = ref.read(employeeRepositoryProvider);
  final emp = await empRepo.byId(ps.employeeId);
  if (emp == null) {
    throw Exception('Employee not found for payslip ${ps.id}');
  }
  Employee? hrSig;
  try {
    hrSig = await empRepo.signatoryFor(hr: true);
  } catch (_) {
    hrSig = null; // pre-migration DB / transient failure → entity fallback
  }

  final period = await _loadPeriod(ps.payrollRunId);
  // Period dates drive both the PDF header and the attendance page; fall
  // back to `createdAt` so the PDF still renders when the join fails
  // (page 2 simply skips when no attendance rows come back).
  final periodStart = period?.startDate ?? ps.createdAt;
  final periodEnd = period?.endDate ?? ps.createdAt;
  final payDate = period?.payDate ?? ps.createdAt;

  final attendanceFuture =
      ref.read(attendanceRepositoryProvider).listByRange(
            start: periodStart,
            end: periodEnd,
            employeeId: emp.id,
          );
  // onlyActive:false — a shift or scorecard deactivated AFTER this payslip was
  // released must still resolve, or page 2's attendance recomputes zero
  // late/OT and the PDF silently disagrees with the amounts that were actually
  // paid. ComputeService loads both without an is_active filter for the same
  // reason.
  final shiftsFuture =
      ref.read(shiftTemplateRepositoryProvider).list(onlyActive: false);
  final scorecardsFuture =
      ref.read(roleScorecardRepositoryProvider).list(onlyActive: false);

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
    // Include future days so the grid looks intact even when we render a
    // payslip before the period closes.
    skipFutureDays: false,
  );

  final profile = await ref.read(userProfileProvider.future);
  HiringEntity? entity;
  if (profile != null && emp.hiringEntityId != null) {
    final entities = await ref
        .read(hiringEntityRepositoryProvider)
        .list(profile.companyId);
    for (final e in entities) {
      if (e.id == emp.hiringEntityId) {
        entity = e;
        break;
      }
    }
  }

  final logoSpec = _logoFor(entity?.code);
  final logoBytes = await _loadLogoBytes(logoSpec.path);
  final companyName = entity?.name ?? 'Luxium Trading Inc.';
  final companyTradeName = entity?.tradeName;
  final companyAddress = entity == null
      ? null
      : [
          entity.addressLine1,
          entity.addressLine2,
          [entity.city, entity.province, entity.zipCode]
              .where((s) => s != null && s.isNotEmpty)
              .join(', '),
        ].where((s) => s != null && s.isNotEmpty).join(' · ');

  return PayslipPdfContext(
    employee: emp,
    companyName: companyName,
    companyTradeName: companyTradeName,
    companyAddress:
        companyAddress == null || companyAddress.isEmpty ? null : companyAddress,
    companyLogoBytes: logoBytes,
    companyLogoHeight: logoSpec.height,
    periodStart: periodStart,
    periodEnd: periodEnd,
    payDate: payDate,
    attendanceRows: attendanceRows,
    hrSignatoryName: hrSig?.fullName ?? entity?.hrManagerName,
    hrSignatoryTitle: hrSig != null
        ? ((hrSig.signatoryTitle?.isNotEmpty ?? false)
            ? hrSig.signatoryTitle
            : 'HR Manager')
        : ((entity?.hrManagerName?.isNotEmpty ?? false) ? 'HR Manager' : null),
    hrSignaturePng: decodeSignaturePngB64(hrSig?.signaturePngB64),
  );
}

/// Per-brand logo asset + render height. Codes come from
/// `supabase/seed/01_company.sql` — GameCove = `GC`, Luxium = `LX`.
/// Height is tuned per-asset because the Luxium PNG bakes in ~40%
/// transparent padding that shrinks the visible mark at a given container
/// height, so we give it a larger container to compensate. Unknown code
/// → Luxium fallback.
({String path, double height}) _logoFor(String? hiringEntityCode) {
  switch ((hiringEntityCode ?? '').toUpperCase()) {
    case 'GC':
      return (path: 'assets/GameCove Logo.png', height: 48);
    case 'LX':
    default:
      return (path: 'assets/Luxium Logo.png', height: 80);
  }
}

Future<Uint8List?> _loadLogoBytes(String assetPath) async {
  try {
    final data = await rootBundle.load(assetPath);
    return data.buffer.asUint8List();
  } catch (_) {
    // Asset missing or couldn't decode — the PDF header gracefully skips
    // the logo block when bytes are null.
    return null;
  }
}

class _Period {
  final DateTime startDate;
  final DateTime endDate;
  final DateTime payDate;
  _Period({
    required this.startDate,
    required this.endDate,
    required this.payDate,
  });
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
