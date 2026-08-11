import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/features/workforce_planning/removal_lifecycle.dart';

void main() {
  group('task', () {
    test('an unassigned task can be deleted outright', () {
      expect(removalActionForTask(assignmentCount: 0), RemovalAction.delete);
    });

    test('an assigned task archives instead, keeping the row addressable', () {
      expect(removalActionForTask(assignmentCount: 1), RemovalAction.archive);
      expect(removalActionForTask(assignmentCount: 4), RemovalAction.archive);
    });
  });

  group('role to KPI link', () {
    test('deletes while no logs exist', () {
      // True throughout Spec A — kpi_logs arrives with Spec B.
      expect(removalActionForKpiLink(hasLogs: false), RemovalAction.delete);
    });

    test('archives once a period has been logged against it', () {
      expect(removalActionForKpiLink(hasLogs: true), RemovalAction.archive);
    });
  });

  group('library KPI', () {
    test('deletes only when it is on no role and has no logs', () {
      expect(
        removalActionForLibraryKpi(roleLinkCount: 0, hasLogs: false),
        RemovalAction.delete,
      );
    });

    test('deactivates when a role still links it', () {
      // Includes the vacant-role case: nobody tracks it, but a card shows it.
      expect(
        removalActionForLibraryKpi(roleLinkCount: 1, hasLogs: false),
        RemovalAction.archive,
      );
    });

    test('deactivates when logs exist, even with no role links left', () {
      expect(
        removalActionForLibraryKpi(roleLinkCount: 0, hasLogs: true),
        RemovalAction.archive,
      );
    });
  });
}
