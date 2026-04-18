import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/money.dart';
import '../../../../data/models/employee.dart';
import '../../../auth/profile_provider.dart';

class ProfileTab extends ConsumerWidget {
  final Employee employee;
  const ProfileTab({super.key, required this.employee});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(userProfileProvider).asData?.value;
    final isAdmin = profile?.isAdmin ?? false;

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 16),
      children: [
        _Section(
          title: 'Personal Information',
          child: _KVGrid(items: [
            _KV('First Name', employee.firstName),
            _KV('Middle Name', employee.middleName ?? '—'),
            _KV('Last Name', employee.lastName),
            _KV('Work Email', employee.workEmail ?? '—'),
            _KV('Mobile Number', employee.mobileNumber ?? '—'),
            _KV('Lark User ID', employee.larkUserId ?? '—'),
          ]),
        ),
        const SizedBox(height: 16),
        _Section(
          title: 'Employment Summary',
          child: _KVGrid(items: [
            _KV('Employee #', employee.employeeNumber),
            _KV('Employment Type',
                employee.employmentType.replaceAll('_', ' ')),
            _KV('Employment Status',
                employee.employmentStatus.replaceAll('_', ' ')),
            _KV('Hire Date', _fmtDate(employee.hireDate)),
            _KV(
              'Regularization Date',
              employee.regularizationDate == null
                  ? '—'
                  : _fmtDate(employee.regularizationDate!),
            ),
            _KV('Job Title', employee.jobTitle ?? '—'),
          ]),
        ),
        const SizedBox(height: 16),
        _Section(
          title: 'Payroll Eligibility',
          child: Wrap(
            spacing: 16,
            runSpacing: 12,
            children: [
              _FlagTile(
                label: 'Rank & File',
                value: employee.isRankAndFile,
              ),
              _FlagTile(
                label: 'OT Eligible',
                value: employee.isOtEligible,
              ),
              _FlagTile(
                label: 'Night Diff. Eligible',
                value: employee.isNdEligible,
              ),
              _FlagTile(
                label: 'Holiday Pay Eligible',
                value: employee.isHolidayPayEligible,
              ),
            ],
          ),
        ),
        if (isAdmin) ...[
          const SizedBox(height: 16),
          _Section(
            title: 'Payroll Overrides',
            subtitle: 'Admin-only — statutory / tax overrides',
            child: _KVGrid(items: [
              _KV(
                'Tax Calculation Mode',
                employee.taxOnFullEarnings ? 'Gross Pay' : 'Basic Pay Only',
              ),
              _KV(
                'Declared Wage Override',
                employee.declaredWageOverride == null
                    ? '—'
                    : Money.fmtPhp(employee.declaredWageOverride!),
              ),
              _KV(
                'Wage Type',
                employee.declaredWageType ?? '—',
              ),
              _KV(
                'Effective',
                employee.declaredWageEffectiveAt == null
                    ? '—'
                    : _fmtDate(employee.declaredWageEffectiveAt!),
              ),
              _KV(
                'Set At',
                employee.declaredWageSetAt == null
                    ? '—'
                    : _fmtDate(employee.declaredWageSetAt!),
              ),
              _KV(
                'Reason',
                employee.declaredWageReason ?? '—',
              ),
            ]),
          ),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------------------

class _Section extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget child;
  const _Section({required this.title, this.subtitle, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(16, 14, 16, subtitle == null ? 14 : 4),
            child: Text(
              title,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          if (subtitle != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
              child: Text(
                subtitle!,
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          Divider(height: 1, color: Theme.of(context).dividerColor),
          Padding(
            padding: const EdgeInsets.all(16),
            child: child,
          ),
        ],
      ),
    );
  }
}

class _KV {
  final String label;
  final String value;
  const _KV(this.label, this.value);
}

class _KVGrid extends StatelessWidget {
  final List<_KV> items;
  const _KVGrid({required this.items});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (ctx, c) {
      final cols = c.maxWidth >= 900
          ? 3
          : c.maxWidth >= 500
              ? 2
              : 1;
      final rowGap = 16.0;
      final colGap = 24.0;
      final itemWidth = (c.maxWidth - colGap * (cols - 1)) / cols;
      return Wrap(
        spacing: colGap,
        runSpacing: rowGap,
        children: [
          for (final kv in items)
            SizedBox(
              width: itemWidth,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    kv.label,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      letterSpacing: 0.3,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    kv.value,
                    style: const TextStyle(fontSize: 14),
                  ),
                ],
              ),
            ),
        ],
      );
    });
  }
}

class _FlagTile extends StatelessWidget {
  final String label;
  final bool value;
  const _FlagTile({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final color =
        value ? const Color(0xFF16A34A) : const Color(0xFF9CA3AF);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          value ? Icons.check_circle : Icons.remove_circle_outline,
          size: 18,
          color: color,
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            color: value ? null : Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

String _fmtDate(DateTime d) {
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  return '${months[d.month - 1]} ${d.day}, ${d.year}';
}
