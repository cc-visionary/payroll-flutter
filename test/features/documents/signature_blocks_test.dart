import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:payroll_flutter/core/pdf/pdf_theme.dart';
import 'package:payroll_flutter/core/pdf/signature_png.dart';
import 'package:payroll_flutter/features/documents/blocks/block.dart';
import 'package:payroll_flutter/features/documents/blocks/multi_signature_block.dart';
import 'package:payroll_flutter/features/documents/blocks/signature_block.dart';
import 'package:payroll_flutter/features/documents/blocks/signature_image_block.dart';
import 'package:payroll_flutter/features/documents/blocks/signature_line_block.dart';

/// 1x1 fully-transparent PNG.
const kTransparentPng1x1B64 =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=';

Future<List<int>> _render(Block block) async {
  final theme = PdfTheme.testStub();
  final doc = pw.Document();
  doc.addPage(pw.Page(build: (_) => block.toPdf(theme)));
  return doc.save();
}

void main() {
  final png = base64Decode(kTransparentPng1x1B64);

  test('decodeSignaturePngB64 decodes, and nulls on garbage/empty', () {
    expect(decodeSignaturePngB64(kTransparentPng1x1B64), isNotNull);
    expect(decodeSignaturePngB64(null), isNull);
    expect(decodeSignaturePngB64(''), isNull);
    expect(decodeSignaturePngB64('!!!not-base64!!!'), isNull);
  });

  test('SignatureBlock renders with and without signature image', () async {
    expect(
        (await _render(SignatureBlock(
                name: 'Brixter Del Mundo',
                role: 'HR Manager',
                signatureImage: png)))
            .length,
        greaterThan(500));
    expect(
        (await _render(const SignatureBlock(name: 'Brixter Del Mundo')))
            .length,
        greaterThan(500));
  });

  test('MultiSignatureBlock renders a signed party', () async {
    final bytes = await _render(MultiSignatureBlock([
      SignatoryParty(name: 'Brixter', role: 'HR Manager', signatureImage: png),
      const SignatoryParty(name: 'Juan', role: 'Employee (Acknowledged)'),
    ]));
    expect(bytes.length, greaterThan(500));
  });

  test('SignatureLineBlock renders a signed line', () async {
    final bytes = await _render(SignatureLineBlock(
      [
        SignatoryLine(
            header: 'For the Company',
            name: 'Clinton Xu',
            role: 'CEO',
            signatureImage: png),
        const SignatoryLine(header: 'Recipient', name: 'Juan'),
      ],
      row: true,
      showDate: true,
    ));
    expect(bytes.length, greaterThan(500));
  });

  test('SignatureImageBlock renders', () async {
    expect((await _render(SignatureImageBlock(png))).length, greaterThan(500));
  });
}
