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
  // Offer
  final _salaryMin = TextEditingController();
  final _salaryMax = TextEditingController();
  DateTime? _expectedStartDate;
  // Notes
  final _notes = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _firstName.dispose();
    _middleName.dispose();
    _lastName.dispose();
    _suffix.dispose();
    _email.dispose();
    _phone.dispose();
    _mobile.dispose();
    _source.dispose();
    _linkedin.dispose();
    _portfolio.dispose();
    _salaryMin.dispose();
    _salaryMax.dispose();
    _notes.dispose();
    super.dispose();
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
      _salaryMin.text = a.expectedSalaryMin?.toString() ?? '';
      _salaryMax.text = a.expectedSalaryMax?.toString() ?? '';
      _expectedStartDate = a.expectedStartDate;
      _notes.text = a.notes ?? '';
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
                onChanged: (id) {
                  setState(() => _roleScorecardId = id);
                  if (id != null) _autofillSalaryFromScorecard(id);
                },
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
              const SizedBox(height: 24),
              const _SectionLabel('Offer'),
              Row(children: [
                Expanded(
                  child: TextFormField(
                    controller: _salaryMin,
                    decoration: const InputDecoration(
                      labelText: 'Expected salary min (PHP)',
                      hintText: 'Auto-fills from scorecard baseSalary',
                    ),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _salaryMax,
                    decoration: const InputDecoration(
                      labelText: 'Expected salary max (PHP)',
                      hintText: 'Auto-fills from scorecard baseSalary',
                    ),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  ),
                ),
              ]),
              const SizedBox(height: 12),
              _DatePickerField(
                label: 'Expected start date',
                value: _expectedStartDate,
                onChanged: (d) => setState(() => _expectedStartDate = d),
              ),
              const SizedBox(height: 24),
              const _SectionLabel('Notes'),
              TextFormField(
                controller: _notes,
                maxLines: 4,
                decoration: const InputDecoration(border: OutlineInputBorder()),
              ),
              const SizedBox(height: 32),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => context.go('/hiring'),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 12),
                  FilledButton(
                    onPressed: _saving ? null : _save,
                    child: Text(_saving ? 'Saving…' : 'Save'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _autofillSalaryFromScorecard(String scorecardId) async {
    final cards = ref.read(roleScorecardListProvider).asData?.value ?? const [];
    final card = cards.firstWhere(
      (c) => c.id == scorecardId,
      orElse: () => cards.first,
    );
    if (card.baseSalary != null && _salaryMin.text.trim().isEmpty) {
      _salaryMin.text = card.baseSalary!.toString();
    }
    if (card.baseSalary != null && _salaryMax.text.trim().isEmpty) {
      _salaryMax.text = card.baseSalary!.toString();
    }
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_roleScorecardId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pick a Role Scorecard before saving.')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      final profile = ref.read(userProfileProvider).asData!.value!;
      final repo = ref.read(applicantRepositoryProvider);
      final id = await repo.upsert(
        id: widget.applicantId,
        companyId: profile.companyId,
        firstName: _firstName.text.trim(),
        middleName: _middleName.text.trim().isEmpty ? null : _middleName.text.trim(),
        lastName: _lastName.text.trim(),
        suffix: _suffix.text.trim().isEmpty ? null : _suffix.text.trim(),
        email: _email.text.trim(),
        phoneNumber: _phone.text.trim().isEmpty ? null : _phone.text.trim(),
        mobileNumber: _mobile.text.trim().isEmpty ? null : _mobile.text.trim(),
        roleScorecardId: _roleScorecardId!,
        departmentId: _departmentId,
        hiringEntityId: _hiringEntityId,
        source: _source.text.trim().isEmpty ? null : _source.text.trim(),
        referredById: _referredById,
        linkedinUrl: _linkedin.text.trim().isEmpty ? null : _linkedin.text.trim(),
        portfolioUrl: _portfolio.text.trim().isEmpty ? null : _portfolio.text.trim(),
        expectedSalaryMin: _salaryMin.text.trim().isEmpty ? null : _salaryMin.text.trim(),
        expectedSalaryMax: _salaryMax.text.trim().isEmpty ? null : _salaryMax.text.trim(),
        expectedStartDate: _expectedStartDate,
        status: _seed?.status ?? 'NEW',
        notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
        setByUserId: profile.userId,
      );
      if (!mounted) return;
      ref.invalidate(applicantListProvider);
      ref.invalidate(applicantsCountByStatusProvider);
      context.go('/hiring/$id');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Save failed: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
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

class _DatePickerField extends StatelessWidget {
  final String label;
  final DateTime? value;
  final ValueChanged<DateTime?> onChanged;
  const _DatePickerField({
    required this.label,
    required this.value,
    required this.onChanged,
  });
  @override
  Widget build(BuildContext context) {
    return InputDecorator(
      decoration: InputDecoration(labelText: label),
      child: Row(
        children: [
          Expanded(
            child: Text(
              value == null
                  ? 'Pick a date'
                  : value!.toIso8601String().substring(0, 10),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.calendar_today_outlined, size: 18),
            onPressed: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: value ?? DateTime.now(),
                firstDate: DateTime(2020),
                lastDate: DateTime(2100),
              );
              if (picked != null) onChanged(picked);
            },
          ),
          if (value != null)
            IconButton(
              icon: const Icon(Icons.clear, size: 18),
              onPressed: () => onChanged(null),
            ),
        ],
      ),
    );
  }
}
