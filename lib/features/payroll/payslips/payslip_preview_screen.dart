import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:printing/printing.dart';

import '../../../data/models/payslip.dart';
import '../../../data/repositories/payroll_repository.dart';
import 'payslip_pdf.dart';
import 'payslip_pdf_context.dart';

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
          return FutureBuilder<PayslipPdfContext>(
            future: loadPayslipPdfContext(ref, ps),
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
                // Fit-width default: cap the rendered page to ~820 CSS
                // pixels so the viewer opens on a "whole page visible"
                // zoom level instead of the library's default 180%ish
                // crop. Users can still scroll-wheel / pinch to zoom in.
                maxPageWidth: 820,
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
                  companyTradeName: ctx.companyTradeName,
                  companyAddress: ctx.companyAddress,
                  companyLogoBytes: ctx.companyLogoBytes,
                  companyLogoHeight: ctx.companyLogoHeight,
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

