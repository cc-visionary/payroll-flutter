import 'package:flutter_quill/quill_delta.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../core/pdf/pdf_theme.dart';

/// Walk a Quill [Delta] document and produce a `pw.Widget` tree suitable
/// for embedding inside a PDF block list.
///
/// Supported attributes (v1):
/// - Inline: `bold`, `italic`, `underline`
/// - Block: `list: bullet`, `list: ordered`, `indent: N` (nested lists)
///
/// Unsupported attributes (e.g., image embeds, color, font) are silently
/// stripped — the v1 Quill toolbar is locked to the supported subset, so
/// this is a defense-in-depth guardrail rather than a UX path.
pw.Widget deltaToPdf(Delta delta, PdfTheme theme) {
  // Group ops by their trailing newline; each "line" is one paragraph
  // whose block-level attributes (e.g., list type) come from the newline
  // op itself.
  final lines = <_QuillLine>[];
  var current = <_QuillRun>[];
  for (final op in delta.toList()) {
    final data = op.data;
    if (data is String) {
      // Split on newlines so each block-level segment ends a line.
      final pieces = data.split('\n');
      for (var i = 0; i < pieces.length; i++) {
        if (pieces[i].isNotEmpty) {
          current.add(_QuillRun(pieces[i], op.attributes ?? const {}));
        }
        if (i < pieces.length - 1) {
          lines.add(_QuillLine(current, op.attributes ?? const {}));
          current = <_QuillRun>[];
        }
      }
    }
    // Embeds (Map data) are silently skipped.
  }
  if (current.isNotEmpty) {
    lines.add(_QuillLine(current, const {}));
  }

  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      for (var i = 0; i < lines.length; i++)
        _renderLine(lines[i], i, lines, theme),
    ],
  );
}

class _QuillRun {
  final String text;
  final Map<String, dynamic> attributes;
  _QuillRun(this.text, this.attributes);
}

class _QuillLine {
  final List<_QuillRun> runs;
  final Map<String, dynamic> blockAttrs;
  _QuillLine(this.runs, this.blockAttrs);
}

pw.Widget _renderLine(
  _QuillLine line,
  int index,
  List<_QuillLine> all,
  PdfTheme theme,
) {
  final list = line.blockAttrs['list'] as String?;
  final indent = (line.blockAttrs['indent'] as int?) ?? 0;
  final richText = pw.RichText(
    text: pw.TextSpan(
      style: pw.TextStyle(fontSize: theme.bodySize, color: theme.textColor),
      children: [for (final r in line.runs) _runToSpan(r, theme)],
    ),
  );

  if (list == null) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 4),
      child: richText,
    );
  }

  // Compute the index of this item within its (list-type, indent) run
  // so ordered lists number correctly even when interleaved with bullets.
  var n = 1;
  for (var j = index - 1; j >= 0; j--) {
    final prev = all[j];
    final prevList = prev.blockAttrs['list'] as String?;
    final prevIndent = (prev.blockAttrs['indent'] as int?) ?? 0;
    if (prevList == list && prevIndent == indent) {
      n++;
    } else {
      break;
    }
  }

  final marker = list == 'ordered' ? '$n.' : '•';
  return pw.Padding(
    padding: pw.EdgeInsets.only(left: 12.0 * indent, bottom: 4),
    child: pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.SizedBox(
          width: list == 'ordered' ? 22 : 14,
          child: pw.Text(
            marker,
            style: pw.TextStyle(
              fontSize: theme.bodySize,
              color: theme.textColor,
            ),
          ),
        ),
        pw.Expanded(child: richText),
      ],
    ),
  );
}

pw.TextSpan _runToSpan(_QuillRun run, PdfTheme theme) {
  final attrs = run.attributes;
  final bold = attrs['bold'] == true;
  final italic = attrs['italic'] == true;
  final underline = attrs['underline'] == true;
  return pw.TextSpan(
    text: run.text,
    style: pw.TextStyle(
      fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
      fontStyle: italic ? pw.FontStyle.italic : pw.FontStyle.normal,
      decoration: underline ? pw.TextDecoration.underline : null,
    ),
  );
}
