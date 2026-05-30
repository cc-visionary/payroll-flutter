import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../auth/profile_provider.dart';
import '../../data/models/applicant.dart';
import '../../data/repositories/applicant_repository.dart';
import '../../data/repositories/role_scorecard_repository.dart';
import '../../data/repositories/hiring_entity_repository.dart';

class ApplicantFormScreen extends ConsumerStatefulWidget {
  /// null = create. Non-null = edit existing applicant.
  final String? applicantId;
  const ApplicantFormScreen({super.key, this.applicantId});

  @override
  ConsumerState<ApplicantFormScreen> createState() => _ApplicantFormScreenState();
}

class _ApplicantFormScreenState extends ConsumerState<ApplicantFormScreen> {
  final _formKey = GlobalKey<FormState>();
  bool _loading = true;
  bool _saving = false;
  Applicant? _seed;

  // Identity
  final _firstName = TextEditingController();
  final _middleName = TextEditingController();
  final _lastName = TextEditingController();
  final _suffix = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _mobile = TextEditingController();
  // Role (hard-gated)
  String? _roleScorecardId;
  String? _hiringEntityId;
  String? _departmentId;
  // Sourcing
  final _source = TextEditingController();
  String? _referredById;
  final _linkedin = TextEditingController();
  final _portfolio = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (widget.applicantId == null) {
      setState(() => _loading = false);
      return;
    }
    final a = await ref.read(applicantRepositoryProvider).byId(widget.applicantId!);
    if (a != null) {
      _firstName.text = a.firstName;
      _middleName.text = a.middleName ?? '';
      _lastName.text = a.lastName;
      _suffix.text = a.suffix ?? '';
      _email.text = a.email;
      _phone.text = a.phoneNumber ?? '';
      _mobile.text = a.mobileNumber ?? '';
      _roleScorecardId = a.roleScorecardId;
      _hiringEntityId = a.hiringEntityId;
      _departmentId = a.departmentId;
      _source.text = a.source ?? '';
      _referredById = a.referredById;
      _linkedin.text = a.linkedinUrl ?? '';
      _portfolio.text = a.portfolioUrl ?? '';
    }
    setState(() {
      _seed = a;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(userProfileProvider).asData?.value;
    if (!(profile?.isHrOrAdmin ?? false)) {
      return Scaffold(
        appBar: AppBar(title: const Text('Applicant')),
        body: const Center(child: Text('You do not have permission.')),
      );
    }
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Applicant')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.applicantId == null ? 'New applicant' : 'Edit applicant'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/hiring'),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _SectionLabel('Identity'),
              Row(children: [
                Expanded(
                  child: TextFormField(
                    controller: _firstName,
                    decoration: const InputDecoration(labelText: 'First name *'),
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _middleName,
                    decoration: const InputDecoration(labelText: 'Middle name'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _lastName,
                    decoration: const InputDecoration(labelText: 'Last name *'),
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 80,
                  child: TextFormField(
                    controller: _suffix,
                    decoration: const InputDecoration(labelText: 'Suffix'),
                  ),
                ),
              ]),
              const SizedBox(height: 12),
              TextFormField(
                controller: _email,
                decoration: const InputDecoration(labelText: 'Email *'),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              Row(children: [
                Expanded(
                  child: TextFormField(
                    controller: _phone,
                    decoration: const InputDecoration(labelText: 'Phone'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _mobile,
                    decoration: const InputDecoration(labelText: 'Mobile'),
                  ),
                ),
              ]),
              const SizedBox(height: 24),
              const _SectionLabel('Role *'),
              _RoleScorecardPicker(
                value: _roleScorecardId,
                onChanged: (id) => setState(() => _roleScorecardId = id),
              ),
              const SizedBox(height: 12),
              _HiringEntityPicker(
                value: _hiringEntityId,
                onChanged: (id) => setState(() => _hiringEntityId = id),
              ),
              const SizedBox(height: 24),
              const _SectionLabel('Sourcing'),
              TextFormField(
                controller: _source,
                decoration: const InputDecoration(labelText: 'Source (e.g. Referral, Lark Careers, LinkedIn)'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _linkedin,
                decoration: const InputDecoration(labelText: 'LinkedIn URL'),
              ),
              TextFormField(
                controller: _portfolio,
                decoration: const InputDecoration(labelText: 'Portfolio URL'),
              ),
              // Offer + Notes + Save land in Task 15.
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Text(text,
            style: const TextStyle(
                fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0.4)),
      );
}

class _RoleScorecardPicker extends ConsumerWidget {
  final String? value;
  final ValueChanged<String?> onChanged;
  const _RoleScorecardPicker({required this.value, required this.onChanged});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scorecards = ref.watch(roleScorecardListProvider).asData?.value ?? const [];
    return InputDecorator(
      decoration: InputDecoration(
        labelText: 'Role Scorecard *',
        errorText: value == null ? 'A Role Scorecard is required' : null,
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String?>(
          isExpanded: true,
          value: value,
          hint: const Text('Pick a scorecard'),
          items: [
            for (final s in scorecards)
              DropdownMenuItem<String?>(value: s.id, child: Text(s.jobTitle)),
          ],
          onChanged: onChanged,
        ),
      ),
    );
  }
}

class _HiringEntityPicker extends ConsumerWidget {
  final String? value;
  final ValueChanged<String?> onChanged;
  const _HiringEntityPicker({required this.value, required this.onChanged});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entities = ref.watch(hiringEntityListProvider).asData?.value ?? const [];
    return DropdownButtonFormField<String?>(
      initialValue: value,
      decoration: const InputDecoration(labelText: 'Hiring Entity (brand)'),
      items: [
        const DropdownMenuItem<String?>(value: null, child: Text('— None —')),
        for (final e in entities)
          DropdownMenuItem<String?>(value: e.id, child: Text(e.name)),
      ],
      onChanged: onChanged,
    );
  }
}
