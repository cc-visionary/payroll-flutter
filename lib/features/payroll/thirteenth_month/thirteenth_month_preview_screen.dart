import 'dart:io' show Platform;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:printing/printing.dart';

import '../../../data/models/employee.dart';
import '../../../data/models/hiring_entity.dart';
import '../../../data/repositories/audit_repository.dart';
import '../../../data/repositories/hiring_entity_repository.dart';
import '../../../data/repositories/payroll_repository.dart';
import '../../auth/profile_provider.dart';
import 'thirteenth_month_pdf.dart';

/// Full-screen preview of the 13th-month accrual breakdown PDF for a single
/// employee + date range. Mirrors the payslip preview UX (Download / Print
/// actions, fit-width zoom). Pushed via Navigator from the export button on
/// the employee profile's Payslips tab.
class ThirteenthMonthPreviewScreen extends ConsumerStatefulWidget {
  final Employee employee;
  final DateTime from;
  final DateTime to;
  const ThirteenthMonthPreviewScreen({
    super.key,
    required this.employee,
    required this.from,
    required this.to,
  });

  @override
  ConsumerState<ThirteenthMonthPreviewScreen> createState() =>
      _ThirteenthMonthPreviewScreenState();
}

class _ThirteenthMonthPreviewScreenState
    extends ConsumerState<ThirteenthMonthPreviewScreen> {
  // Cache the future so FutureBuilder doesn't re-fire on every rebuild —
  // a fresh future per build rebinds PdfPreview's internal ScrollController
  // mid-paint and trips the Scrollbar single-position assertion.
  late final Future<ThirteenthMonthPdfInput> _future = _loadInput();

  @override
  Widget build(BuildContext context) {
    final employee = widget.employee;
    final from = widget.from;
    final to = widget.to;
    return Scaffold(
      appBar: AppBar(title: Text('13th Month — ${employee.fullName}')),
      body: FutureBuilder<ThirteenthMonthPdfInput>(
        future: _future,
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Failed to load 13th-month context: ${snap.error}',
                  style: const TextStyle(color: Colors.red),
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final input = snap.data!;
          if (input.breakdown.contributions.isEmpty) {
            return const Center(
              child: Text('No released payslips in this date range.'),
            );
          }
          final canPrint =
              !kIsWeb &&
              (Platform.isLinux ||
                  Platform.isMacOS ||
                  Platform.isWindows ||
                  Platform.isAndroid ||
                  Platform.isIOS);
          final filename = _filename(employee, from, to);
          return PdfPreview(
            allowPrinting: false,
            allowSharing: false,
            canChangeOrientation: false,
            canChangePageFormat: false,
            canDebug: false,
            maxPageWidth: 820,
            actions: [
              PdfPreviewAction(
                icon: const Icon(Icons.download),
                onPressed: (ctx, build, pageFormat) async {
                  final bytes = await build(pageFormat);
                  await Printing.sharePdf(bytes: bytes, filename: filename);
                  _log13thMonth('download', employee, filename);
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
                    _log13thMonth('print', employee, filename);
                  },
                ),
            ],
            build: (format) => buildThirteenthMonthPdf(input),
          );
        },
      ),
    );
  }

  Future<ThirteenthMonthPdfInput> _loadInput() async {
    final employee = widget.employee;
    final from = widget.from;
    final to = widget.to;
    final breakdown = await ref
        .read(payrollRepositoryProvider)
        .thirteenthMonthBreakdownForEmployee(employee.id, from: from, to: to);

    final profile = await ref.read(userProfileProvider.future);
    HiringEntity? entity;
    if (profile != null && employee.hiringEntityId != null) {
      final entities = await ref
          .read(hiringEntityRepositoryProvider)
          .list(profile.companyId);
      for (final e in entities) {
        if (e.id == employee.hiringEntityId) {
          entity = e;
          break;
        }
      }
    }

    final logoSpec = _logoFor(entity?.code);
    final logoBytes = await _loadLogoBytes(logoSpec.path);
    final companyName = entity?.name ?? 'Luxium Trading Inc.';
    final companyTradeName = entity?.tradeName;
    final addrParts = entity == null
        ? const <String>[]
        : [
            entity.addressLine1,
            entity.addressLine2,
            [
              entity.city,
              entity.province,
              entity.zipCode,
            ].where((s) => s != null && s.isNotEmpty).join(', '),
          ].where((s) => s != null && s.isNotEmpty).cast<String>().toList();
    final companyAddress = addrParts.isEmpty ? null : addrParts.join(' · ');

    return ThirteenthMonthPdfInput(
      employee: employee,
      breakdown: breakdown,
      from: from,
      to: to,
      companyName: companyName,
      companyTradeName: companyTradeName,
      companyAddress: companyAddress,
      companyLogoBytes: logoBytes,
      companyLogoHeight: logoSpec.height,
    );
  }

  void _log13thMonth(String action, Employee employee, String filename) {
    ref
        .read(auditRepositoryProvider)
        .logExport(
          description: '13th-month PDF $action: ${employee.fullName}',
          entityType: '13th_month',
          entityId: employee.id,
          metadata: {
            'employee_id': employee.id,
            'employee_number': employee.employeeNumber,
            'from': widget.from.toIso8601String(),
            'to': widget.to.toIso8601String(),
            'file_name': filename,
            'action': action,
          },
        );
  }
}

({String path, double height}) _logoFor(String? code) {
  switch ((code ?? '').toUpperCase()) {
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
    return null;
  }
}

String _filename(Employee e, DateTime from, DateTime to) {
  String d(DateTime x) =>
      '${x.year}${x.month.toString().padLeft(2, '0')}${x.day.toString().padLeft(2, '0')}';
  return '${e.employeeNumber}-13THMONTH-${d(from)}-${d(to)}.pdf';
}
