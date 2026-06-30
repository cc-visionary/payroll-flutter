import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/features/documents/inputs/image_attachment_field.dart';

Widget _host(Widget child) =>
    MaterialApp(home: Scaffold(body: SingleChildScrollView(child: child)));

// Valid 1×1 PNG — required so Image.memory can decode without logging errors.
final validPng = Uint8List.fromList([
  0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a,
  0x00, 0x00, 0x00, 0x0d, 0x49, 0x48, 0x44, 0x52,
  0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x02, 0x00, 0x00, 0x00, 0x90, 0x77, 0x53, 0xde,
  0x00, 0x00, 0x00, 0x0c, 0x49, 0x44, 0x41, 0x54,
  0x78, 0x9c, 0x63, 0xf8, 0xff, 0xff, 0x3f, 0x00,
  0x05, 0xfe, 0x02, 0xfe, 0x0d, 0xef, 0x46, 0xb8,
  0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4e, 0x44,
  0xae, 0x42, 0x60, 0x82,
]);

void main() {
  testWidgets('empty state shows an Add image button, no Remove', (t) async {
    await t.pumpWidget(_host(ImageAttachmentField(
      bytes: null,
      caption: null,
      onPicked: (_, __) {},
      onRemoved: () {},
      onCaptionChanged: (_) {},
    )));
    expect(find.text('Add image'), findsOneWidget);
    expect(find.text('Remove'), findsNothing);
    expect(find.byType(TextFormField), findsNothing);
  });

  testWidgets('attached state shows thumbnail, Remove, and caption field',
      (t) async {
    await t.pumpWidget(_host(ImageAttachmentField(
      bytes: validPng,
      caption: 'cap',
      onPicked: (_, __) {},
      onRemoved: () {},
      onCaptionChanged: (_) {},
    )));
    await t.pump();
    expect(find.text('Add image'), findsNothing);
    expect(find.text('Remove'), findsOneWidget);
    expect(find.byType(TextFormField), findsOneWidget);
  });

  testWidgets('Remove triggers onRemoved', (t) async {
    var removed = false;
    await t.pumpWidget(_host(ImageAttachmentField(
      bytes: validPng,
      caption: null,
      onPicked: (_, __) {},
      onRemoved: () => removed = true,
      onCaptionChanged: (_) {},
    )));
    await t.pump();
    await t.tap(find.text('Remove'));
    await t.pump();
    expect(removed, isTrue);
  });

  testWidgets('editing the caption triggers onCaptionChanged', (t) async {
    String? captured;
    await t.pumpWidget(_host(ImageAttachmentField(
      bytes: validPng,
      caption: null,
      onPicked: (_, __) {},
      onRemoved: () {},
      onCaptionChanged: (v) => captured = v,
    )));
    await t.pump();
    await t.enterText(find.byType(TextFormField), 'CCTV still');
    expect(captured, 'CCTV still');
  });
}
