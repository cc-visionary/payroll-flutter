// lib/features/hiring/listing_form_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/repositories/hiring_entity_repository.dart';
import '../../data/repositories/job_listing_repository.dart';
import '../../data/repositories/role_scorecard_repository.dart';
import '../auth/profile_provider.dart';

class ListingFormScreen extends ConsumerStatefulWidget {
  final String? listingId; // null = create
  const ListingFormScreen({super.key, this.listingId});

  @override
  ConsumerState<ListingFormScreen> createState() => _ListingFormScreenState();
}

class _ListingFormScreenState extends ConsumerState<ListingFormScreen> {
  final _formKey = GlobalKey<FormState>();
  String _title = '';
  int _targetHeadcount = 1;
  String _status = 'OPEN';
  String? _roleId;
  String? _entityId;
  String? _notes;
  bool _saving = false;
  bool _loaded = false;
  String? _originalRoleId;
  String? _originalEntityId;

  @override
  void initState() {
    super.initState();
    if (widget.listingId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _load());
    } else {
      _loaded = true;
    }
  }

  Future<void> _load() async {
    final j = await ref.read(jobListingByIdProvider(widget.listingId!).future);
    if (j == null || !mounted) return;
    setState(() {
      _title = j.title;
      _targetHeadcount = j.targetHeadcount;
      _status = j.status;
      _roleId = j.roleScorecardId;
      _entityId = j.hiringEntityId;
      _originalRoleId = j.roleScorecardId;
      _originalEntityId = j.hiringEntityId;
      _notes = j.notes;
      _loaded = true;
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (widget.listingId != null &&
        (_roleId != _originalRoleId || _entityId != _originalEntityId)) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Recompute filled count?'),
          content: const Text(
            'Changing the role or brand will recompute the filled count against the new (role, brand). Continue?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Confirm'),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }

    setState(() => _saving = true);
    try {
      final profile = ref.read(userProfileProvider).asData?.value;
      if (profile == null) throw Exception('Not signed in.');
      await ref
          .read(jobListingRepositoryProvider)
          .upsert(
            id: widget.listingId,
            companyId: profile.companyId,
            hiringEntityId: _entityId!,
            roleScorecardId: _roleId!,
            title: _title,
            targetHeadcount: _targetHeadcount,
            status: _status,
            notes: _notes,
            setByUserId: profile.userId,
          );
      ref.invalidate(jobListingListProvider);
      if (widget.listingId != null) {
        ref.invalidate(jobListingByIdProvider(widget.listingId!));
      }
      if (mounted) context.go('/hiring');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final roles =
        ref.watch(roleScorecardListProvider).asData?.value ?? const [];
    final entities =
        ref.watch(hiringEntityListProvider).asData?.value ?? const [];
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.listingId == null ? 'New Listing' : 'Edit Listing'),
      ),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    DropdownButtonFormField<String>(
                      initialValue: _entityId,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        labelText: 'Brand',
                      ),
                      items: entities
                          .map(
                            (e) => DropdownMenuItem(
                              value: e.id,
                              child: Text(e.name),
                            ),
                          )
                          .toList(),
                      validator: (v) => v == null ? 'Required' : null,
                      onChanged: (v) => setState(() => _entityId = v),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: _roleId,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        labelText: 'Role',
                      ),
                      items: roles
                          .map(
                            (r) => DropdownMenuItem(
                              value: r.id,
                              child: Text(r.jobTitle),
                            ),
                          )
                          .toList(),
                      validator: (v) => v == null ? 'Required' : null,
                      onChanged: (v) {
                        setState(() {
                          _roleId = v;
                          if (_title.isEmpty && v != null) {
                            final r = roles.firstWhere((x) => x.id == v);
                            _title = r.jobTitle;
                          }
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      key: ValueKey('title-$_roleId'),
                      initialValue: _title,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        labelText: 'Title',
                      ),
                      validator: (v) =>
                          (v == null || v.trim().isEmpty) ? 'Required' : null,
                      onChanged: (v) => _title = v,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      initialValue: _targetHeadcount.toString(),
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        labelText: 'Target headcount',
                      ),
                      keyboardType: TextInputType.number,
                      validator: (v) {
                        final n = int.tryParse(v ?? '');
                        if (n == null || n < 1) return 'Must be ≥ 1';
                        return null;
                      },
                      onChanged: (v) => _targetHeadcount = int.tryParse(v) ?? 1,
                    ),
                    if (widget.listingId != null) ...[
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: _status,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          labelText: 'Status',
                        ),
                        items: const [
                          DropdownMenuItem(value: 'OPEN', child: Text('Open')),
                          DropdownMenuItem(
                            value: 'PAUSED',
                            child: Text('Paused'),
                          ),
                          DropdownMenuItem(
                            value: 'CLOSED',
                            child: Text('Closed'),
                          ),
                        ],
                        onChanged: (v) => setState(() => _status = v ?? 'OPEN'),
                      ),
                    ],
                    const SizedBox(height: 12),
                    TextFormField(
                      initialValue: _notes,
                      minLines: 3,
                      maxLines: 8,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        labelText: 'Notes (optional)',
                      ),
                      onChanged: (v) => _notes = v.isEmpty ? null : v,
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: _saving
                                ? null
                                : () => context.go('/hiring'),
                            child: const Text('Cancel'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton(
                            onPressed: _saving ? null : _save,
                            child: Text(_saving ? 'Saving…' : 'Save'),
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
}
