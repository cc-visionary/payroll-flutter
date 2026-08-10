import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/features/settings/about/update_service.dart';

void main() {
  group('UpdateService.isNewer', () {
    test('a higher patch is newer', () {
      expect(UpdateService.isNewer('1.0.1', '1.0.0'), isTrue);
    });

    test('an equal version is not newer', () {
      expect(UpdateService.isNewer('1.0.0', '1.0.0'), isFalse);
    });

    test('a lower version is not newer', () {
      expect(UpdateService.isNewer('1.0.0', '1.0.1'), isFalse);
    });

    test('ignores a build suffix', () {
      expect(UpdateService.isNewer('1.0.0+7', '1.0.0+6'), isFalse);
      expect(UpdateService.isNewer('1.0.1+1', '1.0.0+9'), isTrue);
    });

    test('treats a missing component as zero', () {
      expect(UpdateService.isNewer('1.1', '1.0.0'), isTrue);
      expect(UpdateService.isNewer('1.0', '1.0.0'), isFalse);
    });

    // The dismissal gate depends on this: a manifest that rolls back below a
    // version the user already dismissed must NOT resurrect the banner.
    test('a rolled-back manifest is not newer than the dismissal', () {
      expect(UpdateService.isNewer('1.0.0', '1.0.1'), isFalse);
    });
  });
}
