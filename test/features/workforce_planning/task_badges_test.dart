import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/app/status_colors.dart';
import 'package:payroll_flutter/features/workforce_planning/task_badges.dart';

void main() {
  test('criticalityTone maps each level, null for unset/unknown', () {
    expect(criticalityTone('CRITICAL'), StatusTone.danger);
    expect(criticalityTone('HIGH'), StatusTone.warning);
    expect(criticalityTone('MEDIUM'), StatusTone.info);
    expect(criticalityTone('LOW'), StatusTone.neutral);
    expect(criticalityTone(null), isNull);
    expect(criticalityTone('BOGUS'), isNull);
  });

  test('criticalityLabel title-cases the level', () {
    expect(criticalityLabel('CRITICAL'), 'Critical');
    expect(criticalityLabel(null), isNull);
  });
}
