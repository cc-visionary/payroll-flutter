import 'dart:typed_data';

import 'package:decimal/decimal.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/models/employee.dart';
import '../../data/models/hiring_entity.dart';
import '../../data/models/role_scorecard.dart';
import '../../data/repositories/employee_repository.dart';
import '../../data/repositories/hiring_entity_repository.dart';
import '../../data/repositories/role_scorecard_repository.dart';

/// Single hiring entity by id, or null when soft-deleted / not found.
/// Uses a direct single-row fetch that includes logo columns, so
/// [loadCompanyLogoBytes] receives the uploaded logo rather than falling
/// back to the bundled asset every time.
final hiringEntityByIdProvider = FutureProvider.family<HiringEntity?, String>((
  ref,
  id,
) async {
  return ref.watch(hiringEntityRepositoryProvider).byId(id);
});

/// Single employee by id.
final documentEmployeeProvider = FutureProvider.family<Employee?, String>((
  ref,
  id,
) {
  return ref.watch(employeeRepositoryProvider).byId(id);
});

/// Single role scorecard by id (the employee's assigned scorecard), or
/// null when none / not found. Used by the Employment Contract autofill
/// to populate Annex A (responsibilities, KPIs, work hours, salary).
final roleScorecardByIdProvider = FutureProvider.family<RoleScorecard?, String>(
  (ref, id) {
    return ref.watch(roleScorecardRepositoryProvider).byId(id);
  },
);

/// Latest event of [eventType] for [employeeId], or null when none
/// exists. Quitclaim/COE call this for SEPARATION; COE also calls for
/// HIRE.
final latestEmploymentEventProvider =
    FutureProvider.family<
      Map<String, dynamic>?,
      ({String employeeId, String eventType})
    >((ref, key) async {
      final client = Supabase.instance.client;
      final rows = await client
          .from('employment_events')
          .select()
          .eq('employee_id', key.employeeId)
          .eq('event_type', key.eventType)
          .order('event_date', ascending: false)
          .limit(1);
      final list = (rows as List<dynamic>).cast<Map<String, dynamic>>();
      return list.isEmpty ? null : list.first;
    });

/// Final-pay breakdown for the Quitclaim template. Aggregates
/// 13th-month accrual, last-cutoff net pay, unused-leave conversion (if
/// computed), and outstanding cash-advance balance.
class FinalPayBreakdown {
  final Decimal thirteenthMonth;
  final Decimal lastNetPay;
  final Decimal unusedLeaveConversion;
  final Decimal outstandingCashAdvance;
  final bool thirteenthMonthAvailable;
  const FinalPayBreakdown({
    required this.thirteenthMonth,
    required this.lastNetPay,
    required this.unusedLeaveConversion,
    required this.outstandingCashAdvance,
    required this.thirteenthMonthAvailable,
  });
  Decimal get total =>
      thirteenthMonth +
      lastNetPay +
      unusedLeaveConversion -
      outstandingCashAdvance;
}

final finalPayBreakdownProvider =
    FutureProvider.family<FinalPayBreakdown, String>((ref, employeeId) async {
      final client = Supabase.instance.client;

      Decimal asDecimal(Object? v) {
        if (v == null) return Decimal.zero;
        if (v is num) return Decimal.parse(v.toString());
        if (v is String) {
          try {
            return Decimal.parse(v);
          } catch (_) {
            return Decimal.zero;
          }
        }
        return Decimal.zero;
      }

      // 13th-month accrual lives on `employees.accrued_thirteenth_month_basis`
      // (per migration 20260421000001 — provision model: column already
      // stores the payable amount). No separate accruals table exists.
      Decimal thirteenthMonth = Decimal.zero;
      bool thirteenthMonthAvailable = false;
      try {
        final empRow = await client
            .from('employees')
            .select('accrued_thirteenth_month_basis')
            .eq('id', employeeId)
            .maybeSingle();
        if (empRow != null &&
            empRow['accrued_thirteenth_month_basis'] != null) {
          thirteenthMonth = asDecimal(empRow['accrued_thirteenth_month_basis']);
          thirteenthMonthAvailable = true;
        }
      } catch (_) {
        thirteenthMonthAvailable = false;
      }

      // Last released payslip net pay.
      Decimal lastNetPay = Decimal.zero;
      try {
        final psRow = await client
            .from('payslips')
            .select('net_pay')
            .eq('employee_id', employeeId)
            .order('created_at', ascending: false)
            .limit(1)
            .maybeSingle();
        if (psRow != null) lastNetPay = asDecimal(psRow['net_pay']);
      } catch (_) {}

      // Unused leave conversion not stored as a single field — left at zero
      // until the leave-conversion feature exists. HR overrides via the
      // breakdown form when applicable.
      final unusedLeaveConversion = Decimal.zero;

      // Outstanding cash-advance balance. The `cash_advances` table has no
      // `outstanding_balance` column — we sum `amount` for rows that haven't
      // been deducted yet (per migration 20260414000010).
      Decimal outstandingCashAdvance = Decimal.zero;
      try {
        final caRows = await client
            .from('cash_advances')
            .select('amount, is_deducted')
            .eq('employee_id', employeeId)
            .eq('is_deducted', false);
        for (final r
            in (caRows as List<dynamic>).cast<Map<String, dynamic>>()) {
          outstandingCashAdvance += asDecimal(r['amount']);
        }
      } catch (_) {}

      return FinalPayBreakdown(
        thirteenthMonth: thirteenthMonth,
        lastNetPay: lastNetPay,
        unusedLeaveConversion: unusedLeaveConversion,
        outstandingCashAdvance: outstandingCashAdvance,
        thirteenthMonthAvailable: thirteenthMonthAvailable,
      );
    });

// --- Company-wide documents registry --------------------------------------

/// One row of the company-wide documents registry. Maps a non-deleted
/// `employee_documents` row with the owning employee's resolved name.
class DocumentRegistryEntry {
  final String id;
  final String employeeId;
  final String employeeName;
  final String documentType;
  final String title;
  final String status;
  final DateTime? createdAt;
  const DocumentRegistryEntry({
    required this.id,
    required this.employeeId,
    required this.employeeName,
    required this.documentType,
    required this.title,
    required this.status,
    required this.createdAt,
  });
}

/// All non-deleted employee_documents across the company, newest first,
/// with the employee's display name resolved via the embedded join.
final allDocumentsProvider =
    FutureProvider.autoDispose<List<DocumentRegistryEntry>>((ref) async {
      final client = Supabase.instance.client;
      final rows = await client
          .from('employee_documents')
          .select(
            'id, employee_id, document_type, title, status, created_at, '
            'employees!inner(first_name, middle_name, last_name)',
          )
          .isFilter('deleted_at', null)
          .order('created_at', ascending: false);
      final list = (rows as List<dynamic>).cast<Map<String, dynamic>>();
      String nameOf(Map<String, dynamic> r) {
        final e = r['employees'] as Map<String, dynamic>?;
        if (e == null) return '';
        return [
          e['first_name'],
          e['middle_name'],
          e['last_name'],
        ].where((s) => s != null && (s as String).trim().isNotEmpty).join(' ');
      }

      return [
        for (final r in list)
          DocumentRegistryEntry(
            id: r['id'] as String,
            employeeId: r['employee_id'] as String,
            employeeName: nameOf(r),
            documentType: (r['document_type'] as String?) ?? '',
            title:
                (r['title'] as String?) ??
                (r['document_type'] as String? ?? 'Document'),
            status: (r['status'] as String?) ?? 'ISSUED',
            createdAt: r['created_at'] == null
                ? null
                : DateTime.tryParse(r['created_at'] as String),
          ),
      ];
    });

/// A single `employee_documents` row by id (null if missing/deleted). Backs the
/// document viewer, which re-renders the PDF from the row's `generation_options`.
final documentByIdProvider =
    FutureProvider.autoDispose.family<Map<String, dynamic>?, String>((
      ref,
      id,
    ) async {
      final row = await Supabase.instance.client
          .from('employee_documents')
          .select()
          .eq('id', id)
          .isFilter('deleted_at', null)
          .maybeSingle();
      return row;
    });

class EmployeeDocumentSummary {
  final String id;
  final String title;
  final DateTime createdAt;
  const EmployeeDocumentSummary({
    required this.id,
    required this.title,
    required this.createdAt,
  });
  factory EmployeeDocumentSummary.fromRow(Map<String, dynamic> r) =>
      EmployeeDocumentSummary(
        id: r['id'] as String,
        title: r['title'] as String? ?? '(untitled NTE)',
        createdAt: DateTime.parse(r['created_at'] as String),
      );
}

/// Returns all NTE documents stored for [employeeId], newest first.
/// Used by the NOD form's optional NTE picker.
final ntesByEmployeeProvider =
    FutureProvider.family<List<EmployeeDocumentSummary>, String>((
      ref,
      employeeId,
    ) async {
      final client = Supabase.instance.client;
      final rows = await client
          .from('employee_documents')
          .select('id, title, created_at')
          .eq('employee_id', employeeId)
          .eq('document_type', 'NTE')
          .isFilter('deleted_at', null)
          .order('created_at', ascending: false);
      return (rows as List)
          .map(
            (r) => EmployeeDocumentSummary.fromRow(r as Map<String, dynamic>),
          )
          .toList();
    });

/// Decoded logo bytes for one hiring entity, or null when none is set.
final hiringEntityLogoProvider =
    FutureProvider.family<Uint8List?, String>((ref, entityId) async {
  final logo = await ref
      .watch(hiringEntityRepositoryProvider)
      .logoFor(entityId);
  return decodeLogoBytes(logo?.base64);
});
