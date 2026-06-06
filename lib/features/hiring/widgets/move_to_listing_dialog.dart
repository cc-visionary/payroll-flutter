import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../data/repositories/applicant_repository.dart';
import '../../../data/repositories/job_listing_repository.dart';

class MoveToListingDialog extends ConsumerStatefulWidget {
  final String applicantId;
  final String? currentListingId;
  const MoveToListingDialog({
    super.key,
    required this.applicantId,
    this.currentListingId,
  });

  @override
  ConsumerState<MoveToListingDialog> createState() =>
      _MoveToListingDialogState();
}

class _MoveToListingDialogState extends ConsumerState<MoveToListingDialog> {
  String? _chosenListingId; // null = Talent Pool
  bool _includeClosed = false;
  bool _saving = false;
  bool _initialized = false;

  @override
  Widget build(BuildContext context) {
    if (!_initialized) {
      _chosenListingId = widget.currentListingId;
      _initialized = true;
    }
    final query = JobListingListQuery(
      statuses: _includeClosed ? null : const ['OPEN', 'PAUSED'],
    );
    final async = ref.watch(jobListingListProvider(query));
    return AlertDialog(
      title: const Text('Move to listing'),
      content: SizedBox(
        width: 480,
        child: async.when(
          loading: () => const SizedBox(
            height: 80,
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (e, _) => Text('Failed to load listings: $e'),
          data: (listings) => SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                RadioListTile<String?>(
                  value: null,
                  groupValue: _chosenListingId,
                  onChanged: _saving
                      ? null
                      : (v) => setState(() => _chosenListingId = v),
                  title: const Text('Talent Pool (no listing)'),
                ),
                for (final l in listings)
                  RadioListTile<String?>(
                    value: l.id,
                    groupValue: _chosenListingId,
                    onChanged: _saving
                        ? null
                        : (v) => setState(() => _chosenListingId = v),
                    title: Text(l.title),
                    subtitle: Text(
                      'Target ${l.targetHeadcount} · status ${l.status}',
                    ),
                  ),
                CheckboxListTile(
                  value: _includeClosed,
                  title: const Text('Include closed listings'),
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  onChanged: _saving
                      ? null
                      : (v) => setState(() => _includeClosed = v ?? false),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving || (_chosenListingId == widget.currentListingId)
              ? null
              : _save,
          child: Text(_saving ? 'Saving…' : 'Move'),
        ),
      ],
    );
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      // If moving INTO a real listing, adopt its role + brand.
      String? newRoleId;
      String? newEntityId;
      if (_chosenListingId != null) {
        final l = await ref.read(
          jobListingByIdProvider(_chosenListingId!).future,
        );
        newRoleId = l?.roleScorecardId;
        newEntityId = l?.hiringEntityId;
      }
      final updates = <String, dynamic>{
        'listing_id': _chosenListingId,
        if (newRoleId != null) 'role_scorecard_id': newRoleId,
        if (newEntityId != null) 'hiring_entity_id': newEntityId,
      };
      await Supabase.instance.client
          .from('applicants')
          .update(updates)
          .eq('id', widget.applicantId);
      ref.invalidate(applicantByIdProvider(widget.applicantId));
      ref.invalidate(applicantListProvider);
      if (mounted) Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}
