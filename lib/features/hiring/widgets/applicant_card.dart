import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../data/models/applicant.dart';

class ApplicantCard extends StatelessWidget {
  final Applicant applicant;
  final String? jobTitle;     // resolved from RoleScorecard by parent
  final String? entityName;   // resolved from HiringEntity by parent
  const ApplicantCard({
    super.key,
    required this.applicant,
    this.jobTitle,
    this.entityName,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: () => context.go('/hiring/${applicant.id}'),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(applicant.fullName,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              if (jobTitle != null) ...[
                const SizedBox(height: 4),
                Text(jobTitle!,
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    )),
              ],
              const SizedBox(height: 8),
              Row(
                children: [
                  if (entityName != null) ...[
                    Icon(Icons.business_outlined,
                        size: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant),
                    const SizedBox(width: 4),
                    Text(entityName!,
                        style: TextStyle(
                          fontSize: 11,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        )),
                  ],
                  const Spacer(),
                  Text(
                    _relative(applicant.appliedAt),
                    style: TextStyle(
                      fontSize: 11,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _relative(DateTime d) {
    final delta = DateTime.now().difference(d);
    if (delta.inDays >= 1) return '${delta.inDays}d ago';
    if (delta.inHours >= 1) return '${delta.inHours}h ago';
    if (delta.inMinutes >= 1) return '${delta.inMinutes}m ago';
    return 'just now';
  }
}
