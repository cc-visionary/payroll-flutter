import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/data/models/employee.dart';
import 'package:payroll_flutter/data/models/hiring_entity.dart';
import 'package:payroll_flutter/data/repositories/employee_repository.dart';
import 'package:payroll_flutter/data/repositories/hiring_entity_repository.dart';
import 'package:payroll_flutter/features/documents/forms/nte_form.dart';
import 'package:payroll_flutter/features/documents/forms/nod_form.dart';
import 'package:payroll_flutter/features/documents/inputs/image_attachment_field.dart';
import 'package:payroll_flutter/features/documents/providers.dart';
import 'package:payroll_flutter/features/documents/templates/nte_inputs.dart';
import 'package:payroll_flutter/features/documents/templates/nod_inputs.dart';

NteInputs _nte() => NteInputs(
      employeeId: 'e1',
      employeeFullName: 'Jane Doe',
      employeeFirstName: 'Jane',
      employeeLastName: 'Doe',
      employeePosition: 'Clerk',
      employeeDepartment: 'Ops',
      companyId: 'c1',
      companyName: 'Acme',
      dateIssued: DateTime(2026, 1, 1),
      responseDeadline: DateTime(2026, 1, 6),
      subjectSubtopic: '',
      charges: const [],
      applicableViolations: const [],
    );

NodInputs _nod() => NodInputs(
      employeeId: 'e1',
      employeeFullName: 'Jane Doe',
      companyId: 'c1',
      companyName: 'Acme',
      effectiveDate: DateTime(2026, 2, 1),
      issueDate: DateTime(2026, 1, 15),
    );

/// Wraps [child] with a tall viewport (4 000 px) so every ListView child is
/// laid out at once, matching the project's existing form-test pattern.
Widget _host(WidgetTester t, Widget child) {
  t.view.physicalSize = const Size(1200, 4000);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
  return ProviderScope(
    overrides: [
      employeeListProvider(const EmployeeListQuery())
          .overrideWith((ref) => const <Employee>[]),
      hiringEntityListProvider.overrideWith((ref) => const <HiringEntity>[]),
      ntesByEmployeeProvider('e1')
          .overrideWith((ref) => const <EmployeeDocumentSummary>[]),
    ],
    child: MaterialApp(home: Scaffold(body: child)),
  );
}

void main() {
  testWidgets('NteForm shows the attachment field', (t) async {
    await t.pumpWidget(_host(t, NteForm(
      initial: _nte(),
      employeeLocked: true,
      onChanged: (_) {},
      onEmployeeChanged: (_) {},
      onCompanyChanged: (_) {},
    )));
    await t.pump();
    expect(find.text('Attachment (optional)'), findsOneWidget);
    expect(find.byType(ImageAttachmentField), findsOneWidget);
  });

  testWidgets('NodForm shows the attachment field', (t) async {
    await t.pumpWidget(_host(t, NodForm(
      initial: _nod(),
      employeeLocked: true,
      onChanged: (_) {},
      onEmployeeChanged: (_) {},
      onCompanyChanged: (_) {},
    )));
    await t.pump();
    expect(find.text('Attachment (optional)'), findsOneWidget);
    expect(find.byType(ImageAttachmentField), findsOneWidget);
  });
}
