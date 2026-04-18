import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/status_colors.dart';
import '../../../data/models/hiring_entity.dart';
import '../../../data/repositories/hiring_entity_repository.dart';
import '../../auth/profile_provider.dart';

class HiringEntitiesSettingsScreen extends ConsumerWidget {
  const HiringEntitiesSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entitiesAsync = ref.watch(hiringEntityListProvider);
    final countsAsync = ref.watch(hiringEntityEmployeeCountsProvider);

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text('Hiring Entities / Companies',
              style: Theme.of(context).textTheme.headlineSmall),
          const Spacer(),
          FilledButton.icon(
            onPressed: () => _openForm(context, ref),
            icon: const Icon(Icons.add),
            label: const Text('Add Hiring Entity'),
          ),
        ]),
        const SizedBox(height: 4),
        const Text(
          'Legal entities that can hire employees. Each hiring entity has its '
          'own government registrations (TIN, SSS, PhilHealth, Pag-IBIG) and '
          'is used for contracts, payslips, and government reports.',
          style: TextStyle(color: Colors.grey),
        ),
        const SizedBox(height: 16),
        Expanded(
          child: entitiesAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(
                child: Text('Error: $e',
                    style: const TextStyle(color: Colors.red))),
            data: (entities) => entities.isEmpty
                ? const Center(
                    child: Text(
                        'No hiring entities yet. Click "Add Hiring Entity" to create one.'))
                : ListView.separated(
                    itemCount: entities.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (_, i) => _EntityCard(
                      entity: entities[i],
                      employeeCount:
                          countsAsync.asData?.value[entities[i].id] ?? 0,
                      onEdit: () =>
                          _openForm(context, ref, existing: entities[i]),
                    ),
                  ),
          ),
        ),
      ]),
    );
  }

  Future<void> _openForm(
    BuildContext context,
    WidgetRef ref, {
    HiringEntity? existing,
  }) async {
    final profile = ref.read(userProfileProvider).asData?.value;
    if (profile == null) return;
    await showDialog(
      context: context,
      builder: (_) => _EntityForm(
        companyId: profile.companyId,
        existing: existing,
        onSaved: () {
          ref.invalidate(hiringEntityListProvider);
          ref.invalidate(hiringEntityEmployeeCountsProvider);
        },
      ),
    );
  }
}

class _EntityCard extends StatelessWidget {
  final HiringEntity entity;
  final int employeeCount;
  final VoidCallback onEdit;
  const _EntityCard({
    required this.entity,
    required this.employeeCount,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final mono = const TextStyle(fontFamily: 'monospace', fontSize: 13);
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(6),
        side: BorderSide(color: Theme.of(context).dividerColor),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text(entity.name,
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(width: 8),
            StatusChip(
              label: entity.isActive ? 'Active' : 'Inactive',
              tone: entity.isActive ? StatusTone.success : StatusTone.neutral,
            ),
            const Spacer(),
            TextButton(onPressed: onEdit, child: const Text('Edit')),
          ]),
          if (entity.tradeName != null && entity.tradeName!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text('DBA: ${entity.tradeName}',
                  style: const TextStyle(color: Colors.grey, fontSize: 13)),
            ),
          const SizedBox(height: 12),
          Wrap(spacing: 24, runSpacing: 8, children: [
            _field(context, 'Code', entity.code, mono: mono),
            _field(context, 'TIN', entity.tin ?? '—', mono: mono),
            _field(context, 'SSS', entity.sssEmployerId ?? '—', mono: mono),
            _field(context, 'PhilHealth', entity.philhealthEmployerId ?? '—',
                mono: mono),
            _field(context, 'Pag-IBIG', entity.pagibigEmployerId ?? '—',
                mono: mono),
          ]),
          const SizedBox(height: 8),
          Text('$employeeCount employee${employeeCount == 1 ? '' : 's'}',
              style: const TextStyle(color: Colors.grey, fontSize: 12)),
        ]),
      ),
    );
  }

  Widget _field(BuildContext context, String label, String value,
      {required TextStyle mono}) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label,
          style: const TextStyle(
              fontSize: 11,
              color: Colors.grey,
              fontWeight: FontWeight.w500)),
      Text(value, style: mono),
    ]);
  }
}

class _EntityForm extends ConsumerStatefulWidget {
  final String companyId;
  final HiringEntity? existing;
  final VoidCallback onSaved;
  const _EntityForm({
    required this.companyId,
    required this.existing,
    required this.onSaved,
  });

  @override
  ConsumerState<_EntityForm> createState() => _FormState();
}

class _FormState extends ConsumerState<_EntityForm> {
  late final _name = TextEditingController(text: widget.existing?.name ?? '');
  late final _tradeName =
      TextEditingController(text: widget.existing?.tradeName ?? '');
  late final _code = TextEditingController(text: widget.existing?.code ?? '');
  late final _tin = TextEditingController(text: widget.existing?.tin ?? '');
  late final _rdo =
      TextEditingController(text: widget.existing?.rdoCode ?? '');
  late final _sss =
      TextEditingController(text: widget.existing?.sssEmployerId ?? '');
  late final _philhealth = TextEditingController(
      text: widget.existing?.philhealthEmployerId ?? '');
  late final _pagibig = TextEditingController(
      text: widget.existing?.pagibigEmployerId ?? '');
  late final _line1 =
      TextEditingController(text: widget.existing?.addressLine1 ?? '');
  late final _line2 =
      TextEditingController(text: widget.existing?.addressLine2 ?? '');
  late final _city = TextEditingController(text: widget.existing?.city ?? '');
  late final _province =
      TextEditingController(text: widget.existing?.province ?? '');
  late final _zip =
      TextEditingController(text: widget.existing?.zipCode ?? '');
  late final _phone =
      TextEditingController(text: widget.existing?.phoneNumber ?? '');
  late final _email =
      TextEditingController(text: widget.existing?.email ?? '');
  late bool _isActive = widget.existing?.isActive ?? true;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [
      _name,
      _tradeName,
      _code,
      _tin,
      _rdo,
      _sss,
      _philhealth,
      _pagibig,
      _line1,
      _line2,
      _city,
      _province,
      _zip,
      _phone,
      _email
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    final code = _code.text.trim().toUpperCase();
    if (name.isEmpty || code.isEmpty) {
      setState(() => _error = 'Legal name and code are required.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      String? t(TextEditingController c) =>
          c.text.trim().isEmpty ? null : c.text.trim();
      await ref.read(hiringEntityRepositoryProvider).upsert(
            id: widget.existing?.id,
            companyId: widget.companyId,
            code: code,
            name: name,
            tradeName: t(_tradeName),
            tin: t(_tin),
            rdoCode: t(_rdo),
            sssEmployerId: t(_sss),
            philhealthEmployerId: t(_philhealth),
            pagibigEmployerId: t(_pagibig),
            addressLine1: t(_line1),
            addressLine2: t(_line2),
            city: t(_city),
            province: t(_province),
            zipCode: t(_zip),
            phoneNumber: t(_phone),
            email: t(_email),
            isActive: _isActive,
          );
      widget.onSaved();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.existing == null
          ? 'Add Hiring Entity'
          : 'Edit Hiring Entity'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: SingleChildScrollView(
          child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _sectionHeader(context, 'Identity'),
                _row([
                  _text(_name, 'Legal Name'),
                  _text(_tradeName, 'Trade Name / DBA'),
                ]),
                _row([
                  _text(_code, 'Code',
                      mono: true,
                      formatters: [
                        FilteringTextInputFormatter.allow(
                            RegExp(r'[A-Za-z0-9_-]')),
                        LengthLimitingTextInputFormatter(20),
                      ]),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _isActive,
                    onChanged: (v) => setState(() => _isActive = v),
                    title: Text(_isActive ? 'Active' : 'Inactive'),
                  ),
                ]),
                const SizedBox(height: 16),
                _sectionHeader(context, 'Government IDs'),
                _row([
                  _text(_tin, 'TIN',
                      hint: '000-000-000-000', mono: true),
                  _text(_rdo, 'RDO Code', mono: true),
                ]),
                _row([
                  _text(_sss, 'SSS Employer ID',
                      hint: '00-0000000-0', mono: true),
                  _text(_philhealth, 'PhilHealth Employer ID',
                      hint: '00-000000000-0', mono: true),
                ]),
                _row([
                  _text(_pagibig, 'Pag-IBIG Employer ID',
                      hint: '0000-0000-0000', mono: true),
                  const SizedBox.shrink(),
                ]),
                const SizedBox(height: 16),
                _sectionHeader(context, 'Contact & Address'),
                _row([
                  _text(_phone, 'Phone'),
                  _text(_email, 'Email'),
                ]),
                _row([_text(_line1, 'Address Line 1')]),
                _row([_text(_line2, 'Address Line 2')]),
                _row([
                  _text(_city, 'City'),
                  _text(_province, 'Province'),
                  _text(_zip, 'ZIP'),
                ]),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(_error!,
                        style: const TextStyle(color: Colors.red, fontSize: 13)),
                  ),
              ]),
        ),
      ),
      actions: [
        TextButton(
            onPressed: _saving ? null : () => Navigator.pop(context),
            child: const Text('Cancel')),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Save'),
        ),
      ],
    );
  }

  Widget _sectionHeader(BuildContext context, String label) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(label,
            style: Theme.of(context)
                .textTheme
                .labelLarge
                ?.copyWith(fontWeight: FontWeight.w600)),
      );

  Widget _row(List<Widget> children) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (int i = 0; i < children.length; i++) ...[
                Expanded(child: children[i]),
                if (i < children.length - 1) const SizedBox(width: 12),
              ],
            ]),
      );

  Widget _text(
    TextEditingController c,
    String label, {
    String? hint,
    bool mono = false,
    List<TextInputFormatter>? formatters,
  }) =>
      TextField(
        controller: c,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          border: const OutlineInputBorder(),
          isDense: true,
        ),
        style: mono ? const TextStyle(fontFamily: 'monospace') : null,
        inputFormatters: formatters,
      );
}
