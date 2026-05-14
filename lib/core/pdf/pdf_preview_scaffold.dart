import 'dart:io' show Platform;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';

/// Reusable wrapper around `printing.PdfPreview` configured with the
/// app's house style: max 820px page width, no built-in print/share/debug
/// buttons, and explicit Download + Print actions.
///
/// The Print action is hidden on web (browser PDF printing is unreliable
/// across engines) and shown on every other platform that has a native
/// print dialog.
class PdfPreviewScaffold extends StatelessWidget {
  final Future<Uint8List> Function(PdfPageFormat format) buildPdf;
  final String filename;
  final bool enabled;

  /// Optional override for the platform-detected `canPrint`. Tests
  /// inject `true` so the print action is exercised regardless of host.
  final bool? canPrintOverride;

  /// Fired after a successful export action. `action` is either
  /// `'download'` (Save dialog completed) or `'print'` (system print
  /// dialog completed). Callers wire this to an audit-log write — the
  /// widget itself stays UI-only and doesn't touch Riverpod / repos so
  /// it can be embedded anywhere a PDF preview is needed.
  final void Function(String action)? onExported;

  const PdfPreviewScaffold({
    super.key,
    required this.buildPdf,
    required this.filename,
    this.enabled = true,
    this.canPrintOverride,
    this.onExported,
  });

  @override
  Widget build(BuildContext context) {
    if (!enabled) {
      return Center(
        child: Text(
          'Complete required fields',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontSize: 14,
          ),
        ),
      );
    }
    final canPrint = canPrintOverride ??
        (!kIsWeb &&
            (Platform.isLinux ||
                Platform.isMacOS ||
                Platform.isWindows ||
                Platform.isAndroid ||
                Platform.isIOS));
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
          onPressed: (ctx, b, fmt) async {
            try {
              final bytes = await b(fmt);
              await Printing.sharePdf(bytes: bytes, filename: filename);
              onExported?.call('download');
            } catch (e) {
              if (ctx.mounted) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  const SnackBar(
                    content: Text(
                        "Couldn't open save dialog — try again."),
                  ),
                );
              }
            }
          },
        ),
        if (canPrint)
          PdfPreviewAction(
            icon: const Icon(Icons.print),
            onPressed: (ctx, b, fmt) async {
              try {
                await Printing.layoutPdf(
                  onLayout: (format) => b(format),
                  name: filename,
                );
                onExported?.call('print');
              } catch (e) {
                if (ctx.mounted) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(
                      content: Text(
                          "Couldn't open print dialog — try again."),
                    ),
                  );
                }
              }
            },
          ),
      ],
      build: (format) async => buildPdf(format),
    );
  }
}
