import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/breakpoints.dart';
import '../../../../data/models/employee.dart';
import '../../../../data/repositories/employee_repository.dart';
import '../../../../data/repositories/role_scorecard_repository.dart';
import '../../../auth/profile_provider.dart';
import '../providers.dart';
import 'info_card.dart';

/// Back link + name/title block + action buttons + four info cards.
/// Pure layout — all data comes in via props so this works in tests too.
class ProfileHeader extends ConsumerWidget {
  final Employee employee;
  const ProfileHeader({super.key, required this.employee});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(userProfileProvider).asData?.value;
    final canManage = profile?.canManageEmployees ?? false;
    final isAdmin = profile?.isAdmin ?? false;

    // Role scorecard is the source of truth for job title + department when
    // an employee is linked to one. Fall back to the employee's own fields
    // for legacy rows that don't have a role linked yet.
    final cardsAsync = ref.watch(roleScorecardListProvider);
    final linkedCard = cardsAsync.asData?.value
        .where((c) => c.id == employee.roleScorecardId)
        .cast<dynamic>()
        .firstOrNull;
    final roleDerivedDeptId = linkedCard?.departmentId as String?;
    final roleDerivedJobTitle = linkedCard?.jobTitle as String?;
    final effectiveDeptId = roleDerivedDeptId ?? employee.departmentId;

    final deptAsync = effectiveDeptId == null
        ? const AsyncValue<String?>.data(null)
        : ref.watch(departmentNameProvider(effectiveDeptId));
    final entityAsync = employee.hiringEntityId == null
        ? const AsyncValue<String?>.data(null)
        : ref.watch(hiringEntityNameProvider(employee.hiringEntityId!));
    final managerAsync = employee.reportsToId == null
        ? const AsyncValue<String?>.data(null)
        : ref.watch(managerNameProvider(employee.reportsToId!));

    final deptName = deptAsync.asData?.value;
    final entityName = entityAsync.asData?.value;
    final managerName = managerAsync.asData?.value;
    final effectiveJobTitle = roleDerivedJobTitle ?? employee.jobTitle;
    final archived = employee.deletedAt != null;
    final statusLabel = archived
        ? 'ARCHIVED'
        : employee.employmentStatus.toUpperCase();
    final typeLabel = employee.employmentType.replaceAll('_', ' ');
    final mobile = isMobile(context);

    final nameBlock = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          employee.fullName,
          style: TextStyle(
            fontSize: mobile ? 20 : 24,
            fontWeight: FontWeight.w700,
            height: 1.1,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          runSpacing: 4,
          children: [
            Text(
              employee.employeeNumber,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
                color: Color(0xFF6B7280),
              ),
            ),
            const Text('│',
                style: TextStyle(color: Color(0xFF9CA3AF))),
            StatusChip(
              label: typeLabel,
              tone: toneForStatus(typeLabel),
            ),
            StatusChip(
              label: statusLabel,
              tone: archived
                  ? ChipTone.danger
                  : toneForStatus(statusLabel),
            ),
            if (employee.larkUserId != null) ...[
              const Text('│',
                  style: TextStyle(color: Color(0xFF9CA3AF))),
              Text(
                'Lark: ${employee.larkUserId}',
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 11,
                  color: Color(0xFF6B7280),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 6),
        Text(
          _buildSubtitle(effectiveJobTitle, deptName),
          style: const TextStyle(
            fontSize: 14,
            color: Color(0xFF374151),
          ),
        ),
        if (entityName != null)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              'Hired under: $entityName',
              style: const TextStyle(
                fontSize: 12,
                color: Color(0xFF6B7280),
              ),
            ),
          ),
      ],
    );

    final actionButtons = Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        if (canManage)
          OutlinedButton(
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                    content:
                        Text('Workflow launcher — coming soon.')),
              );
            },
            child: const Text('Start Workflow'),
          ),
        if (canManage)
          OutlinedButton(
            onPressed: () =>
                context.push('/employees/${employee.id}/edit'),
            child: const Text('Edit Employee'),
          ),
        if (isAdmin)
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
            ),
            onPressed: () => _confirmSeparate(context, ref),
            child: const Text('Separate Employee'),
          ),
      ],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Back link
        InkWell(
          onTap: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/employees');
            }
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('← ', style: TextStyle(color: Color(0xFF2563EB))),
                Text(
                  'Back to Employees',
                  style: TextStyle(
                    color: const Color(0xFF2563EB),
                    decoration: TextDecoration.underline,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        // Name + action buttons row — stacked on mobile.
        if (mobile)
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              nameBlock,
              const SizedBox(height: 12),
              actionButtons,
            ],
          )
        else
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: nameBlock),
              const SizedBox(width: 16),
              actionButtons,
            ],
          ),
        const SizedBox(height: 20),
        // Info cards row
        LayoutBuilder(builder: (ctx, c) {
          // Four cards: wrap when narrow.
          final cardWidth = c.maxWidth >= 920
              ? (c.maxWidth - 3 * 12) / 4
              : c.maxWidth >= 600
                  ? (c.maxWidth - 12) / 2
                  : c.maxWidth;
          return Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              SizedBox(
                width: cardWidth,
                child: InfoCard(
                  label: 'Hire Date',
                  value: _fmtDate(employee.hireDate),
                ),
              ),
              SizedBox(
                width: cardWidth,
                child: InfoCard(
                  label: 'Regularization Date',
                  value: employee.regularizationDate == null
                      ? '—'
                      : _fmtDate(employee.regularizationDate!),
                ),
              ),
              SizedBox(
                width: cardWidth,
                child: InfoCard(
                  label: 'OT Eligible',
                  value: employee.isOtEligible ? 'Yes' : 'No',
                ),
              ),
              SizedBox(
                width: cardWidth,
                child: InfoCard(
                  label: 'Reports To',
                  value: managerName ?? '—',
                ),
              ),
            ],
          );
        }),
      ],
    );
  }

  String _buildSubtitle(String? jobTitle, String? deptName) {
    final parts = <String>[];
    if (jobTitle != null && jobTitle.isNotEmpty) parts.add(jobTitle);
    if (deptName != null && deptName.isNotEmpty) parts.add(deptName);
    return parts.join(' • ');
  }

  String _fmtDate(DateTime d) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[d.month - 1]} ${d.day}, ${d.year}';
  }

  Future<void> _confirmSeparate(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (c) => AlertDialog(
            title: const Text('Separate employee?'),
            content: Text(
              'This will archive ${employee.fullName}. They will be hidden '
              'from active lists but their records remain for historical reports.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(c, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(c, true),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFDC2626),
                ),
                child: const Text('Separate'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed || !context.mounted) return;
    await ref.read(employeeRepositoryProvider).archive(employee.id);
    ref.invalidate(employeeByIdProvider(employee.id));
    ref.invalidate(employeeListProvider);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${employee.fullName} has been separated.')),
      );
    }
  }
}
