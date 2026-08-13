import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/data/models/leave_type.dart';
import 'package:payroll_flutter/data/repositories/leave_type_repository.dart';
import 'package:payroll_flutter/features/settings/leave_types/leave_types_settings_screen.dart';

import '../../support/supabase_stub.dart';

LeaveType _t({
  String id = 'lt-1',
  String name = 'Personal leave',
  bool isPaid = false,
  bool isActive = true,
  String? larkId = 'lark-1',
}) => LeaveType(
  id: id,
  companyId: 'c',
  code: 'PERSONAL_LEAVE',
  name: name,
  isPaid: isPaid,
  isActive: isActive,
  larkLeaveTypeId: larkId,
);

/// Records the single-column writes so a test can assert WHICH column moved,
/// not merely that something was saved.
class _FakeRepo implements LeaveTypeRepository {
  final paidCalls = <({String id, bool value})>[];
  final activeCalls = <({String id, bool value})>[];

  @override
  Future<List<LeaveType>> list(String companyId) async => const [];

  @override
  Future<void> setPaid(String id, bool isPaid) async =>
      paidCalls.add((id: id, value: isPaid));

  @override
  Future<void> setActive(String id, bool isActive) async =>
      activeCalls.add((id: id, value: isActive));
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await initSupabaseStub();
  });

  Future<_FakeRepo> pump(WidgetTester tester, List<LeaveType> types) async {
    final repo = _FakeRepo();
    tester.view.physicalSize = const Size(1400, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          leaveTypeRepositoryProvider.overrideWithValue(repo),
          leaveTypeListProvider.overrideWith((ref) async => types),
        ],
        child: const MaterialApp(home: Scaffold(body: LeaveTypesSettingsScreen())),
      ),
    );
    await tester.pumpAndSettle();
    return repo;
  }

  testWidgets('a Lark-imported type renders unpaid and says where it came from',
      (tester) async {
    await pump(tester, [_t()]);
    expect(find.text('Personal leave'), findsOneWidget);
    expect(find.text('Lark'), findsOneWidget);
    final paidSwitch = tester.widgetList<Switch>(find.byType(Switch)).first;
    expect(paidSwitch.value, isFalse);
  });

  testWidgets('marking a type paid asks first, because it costs money', (
    tester,
  ) async {
    final repo = await pump(tester, [_t()]);
    await tester.tap(find.byType(Switch).first);
    await tester.pumpAndSettle();

    expect(find.text('Pay for Personal leave?'), findsOneWidget);
    expect(
      repo.paidCalls,
      isEmpty,
      reason: 'nothing may be written before the confirmation is accepted',
    );

    await tester.tap(find.widgetWithText(FilledButton, 'Mark as paid'));
    await tester.pumpAndSettle();
    expect(repo.paidCalls, [(id: 'lt-1', value: true)]);
  });

  testWidgets('cancelling the confirmation writes nothing', (tester) async {
    final repo = await pump(tester, [_t()]);
    await tester.tap(find.byType(Switch).first);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();
    expect(repo.paidCalls, isEmpty);
  });

  testWidgets('turning a paid type OFF does not ask — unpaid is the safe way',
      (tester) async {
    // A confirmation here would only train people to dismiss the dialog that
    // actually matters, the one guarding the direction that costs money.
    final repo = await pump(tester, [_t(isPaid: true)]);
    await tester.tap(find.byType(Switch).first);
    await tester.pumpAndSettle();
    expect(find.textContaining('Pay for'), findsNothing);
    expect(repo.paidCalls, [(id: 'lt-1', value: false)]);
  });

  testWidgets('the Active switch moves active, never paid', (tester) async {
    // Two switches in one row is exactly where a positional mix-up hides, and
    // this one would silently start paying for a type nobody marked paid.
    final repo = await pump(tester, [_t()]);
    await tester.tap(find.byType(Switch).last);
    await tester.pumpAndSettle();
    expect(repo.activeCalls, [(id: 'lt-1', value: false)]);
    expect(repo.paidCalls, isEmpty);
  });
}
