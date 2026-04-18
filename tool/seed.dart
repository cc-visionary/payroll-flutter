// Dart-native seeder for the payroll-flutter Supabase project.
//
// One command, idempotent, replaces: psql -f *.sql + npx tsx create_admin_users.ts
//
//   dart run tool/seed.dart --env env/prod.json
//
// Options:
//   --env <path>                  Env JSON file (default: env/prod.json)
//   --dry-run                     Log what would change, don't write
//   --allow-default-passwords     Permit built-in dev passwords (NOT FOR PROD)
//   -v, --verbose                 Extra logging
//
// Requires the following keys in the env file:
//   SUPABASE_URL                  e.g. https://<ref>.supabase.co
//   SUPABASE_SERVICE_ROLE_KEY     server-side only; bypasses RLS
//   ADMIN_PASSWORD, HR_PASSWORD, PAYROLL_PASSWORD, FINANCE_PASSWORD
//     (unless --allow-default-passwords is passed)
//
// Exit codes:
//   0  success
//   1  invalid args / missing env
//   2  Supabase API failure

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:supabase/supabase.dart';

import 'seed_data.dart';

Future<void> main(List<String> argv) async {
  final parser = ArgParser()
    ..addOption('env', defaultsTo: 'env/prod.json', help: 'Env JSON file')
    ..addFlag('dry-run', defaultsTo: false, help: "Don't write — log only")
    ..addFlag(
      'allow-default-passwords',
      defaultsTo: false,
      help: 'Permit built-in dev passwords (NOT FOR PROD)',
    )
    ..addFlag(
      'print-credentials',
      defaultsTo: false,
      help: 'Print seeded user emails + passwords at the end (dev only; logs secrets)',
    )
    ..addFlag('verbose', abbr: 'v', defaultsTo: false)
    ..addFlag('help', abbr: 'h', negatable: false);

  late final ArgResults args;
  try {
    args = parser.parse(argv);
  } on FormatException catch (e) {
    stderr.writeln('Error: ${e.message}\n\n${parser.usage}');
    exit(1);
  }

  if (args['help'] as bool) {
    stdout.writeln('payroll-flutter seed tool\n\n${parser.usage}');
    exit(0);
  }

  final envPath = args['env'] as String;
  final env = _loadEnv(envPath);

  // ── Validation ───────────────────────────────────────────────────────────
  final url = env['SUPABASE_URL'];
  final serviceRoleKey = env['SUPABASE_SERVICE_ROLE_KEY'];
  if (url == null || url.isEmpty) {
    _fail('Missing SUPABASE_URL in $envPath');
  }
  if (serviceRoleKey == null || serviceRoleKey.isEmpty) {
    _fail('Missing SUPABASE_SERVICE_ROLE_KEY in $envPath');
  }
  if (!url.startsWith('https://') || !url.endsWith('.supabase.co')) {
    _warn('SUPABASE_URL "$url" does not look like a Supabase URL. Continuing anyway.');
  }
  if (!_looksLikeServiceRoleJwt(serviceRoleKey)) {
    _fail(
      'SUPABASE_SERVICE_ROLE_KEY does not look like a service_role JWT.\n'
      '  Get it from: Dashboard → Project Settings → API → service_role secret\n'
      '  NOT the anon key — the seeder needs admin privileges.',
    );
  }

  final allowDefaults = args['allow-default-passwords'] as bool;
  if (!allowDefaults) {
    final missing = seedUsers
        .where((u) => (env[u.passwordEnvKey] ?? '').isEmpty)
        .map((u) => u.passwordEnvKey)
        .toList();
    if (missing.isNotEmpty) {
      _fail(
        'Missing passwords in $envPath: ${missing.join(', ')}\n'
        'Set each to a strong password, or pass --allow-default-passwords for local dev only.',
      );
    }
    // Also reject weak / known-default passwords if user did set them.
    for (final u in seedUsers) {
      final pw = env[u.passwordEnvKey]!;
      if (pw == u.defaultPassword) {
        _fail(
          '${u.passwordEnvKey} is set to the built-in default. '
          'Change it or pass --allow-default-passwords (dev only).',
        );
      }
      if (pw.length < 12) {
        _fail('${u.passwordEnvKey} must be at least 12 characters.');
      }
    }
  }

  // ── Connect ──────────────────────────────────────────────────────────────
  final dryRun = args['dry-run'] as bool;
  final verbose = args['verbose'] as bool;
  final runner = _SeedRunner(
    SupabaseClient(url, serviceRoleKey, authOptions: const AuthClientOptions(autoRefreshToken: false)),
    dryRun: dryRun,
    verbose: verbose,
  );

  final masked = '${serviceRoleKey.substring(0, 20)}…';
  stdout.writeln('Target: $url');
  stdout.writeln('Service role: $masked');
  stdout.writeln(dryRun ? 'Mode: DRY RUN (no writes)' : 'Mode: apply');
  stdout.writeln('');

  try {
    await runner.companies();
    await runner.roles();
    await runner.departments();
    // Shift templates are sourced from Lark (sync from the Settings → Shift
    // Templates screen). The seeder no longer pre-populates them.
    await runner.roleScorecards();
    await runner.employees();
    // payroll_calendars + pay_periods tables were dropped in
    // migration 20260418000001 — period fields now live on payroll_runs.
    await runner.adminUsers(env, allowDefaults: allowDefaults);
  } on AuthException catch (e) {
    _apiFail('Auth admin API failed', e.message);
  } on PostgrestException catch (e) {
    _apiFail('Postgrest failed', '${e.code ?? ''} ${e.message}');
  } catch (e, st) {
    _apiFail('Unexpected failure', '$e\n$st');
  }

  stdout.writeln('\nSeed complete.');

  if (args['print-credentials'] as bool) {
    _printCredentials(env, allowDefaults: allowDefaults);
  } else {
    stdout.writeln('(pass --print-credentials to print the test user emails + passwords)');
  }

  exit(0);
}

void _printCredentials(Map<String, String> env, {required bool allowDefaults}) {
  const divider = '═══════════════════════════════════════════════════════════════════════════';
  const thin = '───────────────────────────────────────────────────────────────────────────';
  stdout
    ..writeln('')
    ..writeln(divider)
    ..writeln('  TEST USER ACCOUNTS')
    ..writeln(divider)
    ..writeln('');
  for (final u in seedUsers) {
    final pw = env[u.passwordEnvKey]?.isNotEmpty == true
        ? env[u.passwordEnvKey]!
        : (allowDefaults ? u.defaultPassword : '(set in env/prod.json)');
    stdout
      ..writeln('  📧 ${u.email}')
      ..writeln('     Password: $pw')
      ..writeln('     Role:     ${u.roleCode}')
      ..writeln('     App role: ${u.appRole}')
      ..writeln(thin);
  }
  stdout
    ..writeln('')
    ..writeln('  ⚠️  Never commit passwords or share this output in chat / tickets.')
    ..writeln(divider)
    ..writeln('');
}

// -----------------------------------------------------------------------------
// Runner
// -----------------------------------------------------------------------------

class _SeedRunner {
  final SupabaseClient db;
  final bool dryRun;
  final bool verbose;
  _SeedRunner(this.db, {required this.dryRun, required this.verbose});

  Future<void> companies() async {
    await _upsert('companies', [seedCompany], onConflict: 'code');
    await _upsert('hiring_entities', seedHiringEntities, onConflict: 'id');
  }

  Future<void> roles() async {
    await _upsert('roles', seedRoles, onConflict: 'code');
  }

  Future<void> departments() async {
    await _upsert('departments', seedDepartments, onConflict: 'company_id,code');
  }

  Future<void> roleScorecards() async {
    await _upsert('role_scorecards', loadRoleScorecards(),
        onConflict: 'company_id,job_title,effective_date');
  }

  Future<void> employees() async {
    await _upsert('employees', loadEmployees(), onConflict: 'company_id,employee_number');
    // Replace any existing statutory IDs for seeded employees to stay idempotent
    // (employee_statutory_ids has no stable natural key — delete-and-reinsert pattern).
    final stat = loadEmployeeStatutoryIds();
    if (stat.isEmpty) return;
    final empIds = stat.map((r) => r['employee_id']).toSet().toList();
    if (!dryRun) {
      await db.from('employee_statutory_ids').delete().inFilter('employee_id', empIds);
      await db.from('employee_statutory_ids').insert(stat);
    }
    stdout.writeln('  ✓ employee_statutory_ids: ${stat.length} row(s)');
  }

  Future<void> adminUsers(Map<String, String> env, {required bool allowDefaults}) async {
    // Pre-load role id map
    final roleRows = await db.from('roles').select('id, code') as List<dynamic>;
    final roleIdByCode = {
      for (final r in roleRows.cast<Map<String, dynamic>>()) r['code'] as String: r['id'] as String,
    };

    for (final u in seedUsers) {
      final password = env[u.passwordEnvKey] ?? (allowDefaults ? u.defaultPassword : null);
      if (password == null) {
        _warn('Skipping ${u.email}: no password provided.');
        continue;
      }
      await _seedOneUser(u, password, roleIdByCode);
    }
  }

  Future<void> _seedOneUser(
    SeedUser u,
    String password,
    Map<String, String> roleIdByCode,
  ) async {
    if (dryRun) {
      stdout.writeln('  auth user ${u.email} (${u.appRole})  [dry-run]');
      return;
    }

    final appMetadata = {
      'app_role': u.appRole,
      'company_id': seedCompanyId,
    };

    String userId;
    try {
      final created = await db.auth.admin.createUser(
        AdminUserAttributes(
          email: u.email,
          password: password,
          emailConfirm: true,
          appMetadata: appMetadata,
        ),
      );
      userId = created.user!.id;
      stdout.writeln('  ✓ created auth user ${u.email} (${u.appRole})');
    } on AuthException catch (e) {
      // Already exists → look up + update
      final existing = await _findAuthUserByEmail(u.email);
      if (existing == null) rethrow;
      userId = existing;
      await db.auth.admin.updateUserById(
        userId,
        attributes: AdminUserAttributes(
          password: password,
          appMetadata: appMetadata,
        ),
      );
      if (verbose) stdout.writeln('    (update path: ${e.message})');
      stdout.writeln('  ✓ updated auth user ${u.email} (${u.appRole})');
    }

    // Profile row
    await db.from('users').upsert({
      'id': userId,
      'company_id': seedCompanyId,
      'status': 'ACTIVE',
    });

    // Role link
    final roleId = roleIdByCode[u.roleCode];
    if (roleId == null) {
      _warn('    role "${u.roleCode}" not found; skipping link.');
      return;
    }
    await db.from('user_roles').upsert(
      {'user_id': userId, 'role_id': roleId},
      onConflict: 'user_id,role_id',
    );
  }

  Future<String?> _findAuthUserByEmail(String email) async {
    // GoTrue listUsers is paginated; search by email via filter isn't stable
    // across server versions, so page through up to 10,000 users.
    var page = 1;
    while (page <= 10) {
      final users = await db.auth.admin.listUsers(page: page, perPage: 1000);
      for (final u in users) {
        if (u.email?.toLowerCase() == email.toLowerCase()) return u.id;
      }
      if (users.length < 1000) break;
      page++;
    }
    return null;
  }

  // -------------------------------------------------------------------------
  // Helpers
  // -------------------------------------------------------------------------

  Future<void> _upsert(
    String table,
    List<Map<String, Object?>> rows, {
    required String onConflict,
  }) async {
    if (rows.isEmpty) return;
    if (dryRun) {
      stdout.writeln('  $table: ${rows.length} row(s)  [dry-run]');
      return;
    }
    await db.from(table).upsert(rows, onConflict: onConflict);
    stdout.writeln('  ✓ $table: ${rows.length} row(s)');
  }
}

// -----------------------------------------------------------------------------
// Helpers
// -----------------------------------------------------------------------------

Map<String, String> _loadEnv(String path) {
  final file = File(path);
  if (!file.existsSync()) {
    _fail(
      'Env file not found: $path\n'
      '  Copy env/example.json → env/prod.json and fill it in, or pass --env <path>.',
    );
  }
  final raw = file.readAsStringSync();
  final dynamic parsed;
  try {
    parsed = jsonDecode(raw);
  } on FormatException catch (e) {
    _fail('Env file $path is not valid JSON: ${e.message}');
  }
  if (parsed is! Map) _fail('Env file $path must be a JSON object.');
  return {
    for (final e in parsed.entries)
      e.key as String: e.value?.toString() ?? '',
  };
}

bool _looksLikeServiceRoleJwt(String s) {
  // Shape check only — we do NOT try to validate the signature client-side.
  if (!s.startsWith('eyJ')) return false;
  final parts = s.split('.');
  if (parts.length != 3) return false;
  try {
    final padded = parts[1] + ('=' * ((4 - parts[1].length % 4) % 4));
    final payload = jsonDecode(utf8.decode(base64.decode(padded.replaceAll('-', '+').replaceAll('_', '/'))));
    return payload is Map && payload['role'] == 'service_role';
  } catch (_) {
    return false;
  }
}

Never _fail(String msg) {
  stderr.writeln('Error: $msg');
  exit(1);
}

Never _apiFail(String what, String detail) {
  stderr.writeln('\n$what:\n  $detail');
  exit(2);
}

void _warn(String msg) => stderr.writeln('Warning: $msg');
