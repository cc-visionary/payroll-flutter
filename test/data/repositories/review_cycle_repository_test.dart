import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:payroll_flutter/data/repositories/review_cycle_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Covers `ReviewCycleRepository.callerSeesAllReviews()` against the actual
/// `auth_app_role()` RPC response, for the two roles the final fix wave's
/// CRITICAL finding turned on: PAYROLL_ADMIN (must NOT certify full
/// visibility) and HR_ADMIN (must). `profile_provider_test.dart` covers the
/// other half of the same seam -- `UserProfile.isPerformanceAdmin`, which
/// gates whether a PAYROLL_ADMIN can even reach the `/kpi-results` route
/// this method is read from. Together they are the two ends that used to
/// disagree: the route guard let PAYROLL_ADMIN in, this check silently
/// returned false for them, and "Recompute" overwrote every review-sourced
/// KPI result with NO_DATA as a result.
///
/// A recording [MockClient] stands in for Postgrest's HTTP transport --
/// same technique as `role_scorecard_kpi_links_test.dart` -- returning
/// whichever role string the test wires for the `auth_app_role` RPC.
SupabaseClient _clientReturningRole(String role) {
  final mock = MockClient((request) async {
    if (request.url.path.endsWith('/rpc/auth_app_role')) {
      return http.Response(jsonEncode(role), 200, request: request);
    }
    return http.Response('[]', 200, request: request);
  });
  return SupabaseClient(
    'https://stub.supabase.co',
    'stub-anon-key',
    httpClient: mock,
    authOptions: const AuthClientOptions(autoRefreshToken: false),
  );
}

void main() {
  group('ReviewCycleRepository.callerSeesAllReviews', () {
    test(
      'PAYROLL_ADMIN does not certify full review visibility -- the exact '
      'role that used to pass the /kpi-results route guard while failing '
      'here, which is what let Recompute silently overwrite good rows',
      () async {
        final repo = ReviewCycleRepository(
          _clientReturningRole('PAYROLL_ADMIN'),
        );
        expect(await repo.callerSeesAllReviews(), isFalse);
      },
    );

    test('HR_ADMIN certifies full review visibility', () async {
      final repo = ReviewCycleRepository(_clientReturningRole('HR_ADMIN'));
      expect(await repo.callerSeesAllReviews(), isTrue);
    });

    test('SUPER_ADMIN certifies full review visibility', () async {
      final repo = ReviewCycleRepository(_clientReturningRole('SUPER_ADMIN'));
      expect(await repo.callerSeesAllReviews(), isTrue);
    });

    test(
      'FINANCE_MANAGER does not certify full review visibility -- the '
      'same payroll-scoped-not-performance-scoped rule as PAYROLL_ADMIN',
      () async {
        final repo = ReviewCycleRepository(
          _clientReturningRole('FINANCE_MANAGER'),
        );
        expect(await repo.callerSeesAllReviews(), isFalse);
      },
    );
  });
}
