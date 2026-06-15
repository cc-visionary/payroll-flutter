import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/features/employees/profile/tabs/documents_tab.dart';

Widget _host(Map<String, dynamic> row) => MaterialApp(
      home: Scaffold(
        body: DocRow(row: row),
      ),
    );

// The View/Download action is the only IconButton in a DocRow.
Finder _viewAction() => find.byType(IconButton);

void main() {
  testWidgets('renders the status as a chip with a friendly label',
      (tester) async {
    await tester.pumpWidget(_host({
      'title': 'Certificate of Employment',
      'document_type': 'COE',
      'status': 'ISSUED',
      'file_path': 'emp-1/doc-1.pdf',
    }));
    await tester.pumpAndSettle();

    expect(find.text('Issued'), findsOneWidget);
    expect(find.text('Certificate of Employment'), findsOneWidget);
  });

  testWidgets('PENDING_APPROVAL chip renders its friendly label',
      (tester) async {
    await tester.pumpWidget(_host({
      'title': 'NTE',
      'status': 'PENDING_APPROVAL',
      'file_path': 'emp-1/doc-2.pdf',
    }));
    await tester.pumpAndSettle();

    expect(find.text('Pending Approval'), findsOneWidget);
  });

  testWidgets('shows the View/Download action when file_path is present',
      (tester) async {
    await tester.pumpWidget(_host({
      'title': 'COE',
      'status': 'ISSUED',
      'file_path': 'emp-1/doc-1.pdf',
    }));
    await tester.pumpAndSettle();

    expect(_viewAction(), findsOneWidget);
  });

  testWidgets('hides the View/Download action when file_path is null',
      (tester) async {
    await tester.pumpWidget(_host({
      'title': 'Legacy doc',
      'status': 'ISSUED',
      'file_path': null,
    }));
    await tester.pumpAndSettle();

    expect(_viewAction(), findsNothing);
  });

  testWidgets('hides the View/Download action when file_path is blank',
      (tester) async {
    await tester.pumpWidget(_host({
      'title': 'Legacy doc',
      'status': 'ISSUED',
      'file_path': '   ',
    }));
    await tester.pumpAndSettle();

    expect(_viewAction(), findsNothing);
  });

  testWidgets('falls back to file_name when title is absent', (tester) async {
    await tester.pumpWidget(_host({
      'file_name': 'coe_2026.pdf',
      'status': 'SIGNED',
      'file_path': 'emp-1/doc-3.pdf',
    }));
    await tester.pumpAndSettle();

    expect(find.text('coe_2026.pdf'), findsOneWidget);
    expect(find.text('Signed'), findsOneWidget);
  });
}
