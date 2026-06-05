import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../widgets/employee_name_field.dart';
import '../inputs/company_picker.dart';
import '../inputs/date_field.dart';
import '../inputs/employee_picker.dart';
import '../providers.dart';
import '../templates/resignation_acceptance_inputs.dart';
import '../templates/resignation_acceptance_validate.dart';

class ResignationAcceptanceForm extends ConsumerStatefulWidget {
  final ResignationAcceptanceInputs initial;
  final bool employeeLocked;
  final ValueChanged<ResignationAcceptanceInputs> onChanged;
  final ValueChanged<String> onEmployeeChanged;
  const ResignationAcceptanceForm({
    super.key,
    required this.initial,
    required this.employeeLocked,
    required this.onChanged,
    required this.onEmployeeChanged,
  });

  @override
  ConsumerState<ResignationAcceptanceForm> createState() =>
      _ResignationAcceptanceFormState();
}

class _ResignationAcceptanceFormState
    extends ConsumerState<ResignationAcceptanceForm> {
  late ResignationAcceptanceInputs _i = widget.initial;
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant ResignationAcceptanceForm oldWidget) {
    super.didUpdateWidget(oldWidget);
    // When the parent ships a new `initial` (e.g. async autofill arrived
    // after the employee was picked), adopt it locally so the form
    // reflects the freshly-computed values.
    if (!identical(oldWidget.initial, widget.initial)) {
      _i = widget.initial;
    }
  }

  void _set(ResignationAcceptanceInputs next) {
    setState(() => _i = next);
    widget.onChanged(next);
  }

  Future<void> _onCompanyChanged(String id) async {
    // Optimistic: set the id immediately so the picker reflects the choice.
    _set(_i.copyWith(companyId: id));
    try {
      final co = await ref.read(hiringEntityByIdProvider(id).future);
      if (co == null || !mounted) return;
      final address = <String?>[
        co.addressLine1,
        co.addressLine2,
        [
          co.city,
          co.province,
          co.zipCode,
        ].where((s) => s != null && s.isNotEmpty).join(', '),
      ].where((s) => s != null && s.isNotEmpty).cast<String>().join(', ');
      _set(
        _i.copyWith(
          companyName: co.name,
          companyAddress: address,
          hrManagerName: _i.hrManagerName.isNotEmpty
              ? _i.hrManagerName
              : (co.hrManagerName ?? ''),
        ),
      );
    } catch (_) {
      // Best-effort; leave companyId set, user can fill manually.
    }
  }

  String? _errFor(String field) {
    for (final e in validateResignationAcceptance(_i)) {
      if (e.field == field) return e.message;
    }
    return null;
  }

  Widget _error(String field) {
    final msg = _errFor(field);
    if (msg == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Text(msg, style: const TextStyle(color: Colors.red, fontSize: 12)),
    );
  }

  Widget _label(String s) =>
      Text(s, style: const TextStyle(fontWeight: FontWeight.w600));

  @override
  Widget build(BuildContext context) {
    return Scrollbar(
      controller: _scrollController,
      child: ListView(
        controller: _scrollController,
        primary: false,
        padding: const EdgeInsets.all(16),
        children: [
          _label('Employee'),
          const SizedBox(height: 4),
          EmployeePicker(
            selectedId: _i.employeeId.isEmpty ? null : _i.employeeId,
            locked: widget.employeeLocked,
            includeArchived: false,
            onChanged: (id) {
              if (id != null) {
                // Optimistic local update so validation passes immediately
                // while the parent's async autofill is still running.
                _set(_i.copyWith(employeeId: id));
                widget.onEmployeeChanged(id);
              }
            },
          ),
          _error('employee'),
          _error('employeeFullName'),
          const SizedBox(height: 16),
          _label('Company'),
          const SizedBox(height: 4),
          CompanyPicker(
            selectedId: _i.companyId.isEmpty ? null : _i.companyId,
            locked: false,
            onChanged: (id) {
              if (id != null) _onCompanyChanged(id);
            },
          ),
          _error('company'),
          const SizedBox(height: 16),
          _label('HR Manager Name'),
          const SizedBox(height: 4),
          EmployeeNameField(
            value: _i.hrManagerName,
            onChanged: (v) => _set(_i.copyWith(hrManagerName: v)),
          ),
          _error('hrManager'),
          const SizedBox(height: 16),
          _label('Resignation date (when submitted)'),
          const SizedBox(height: 4),
          DateField(
            value: _i.resignationDate,
            locked: false,
            onChanged: (d) {
              if (d != null) _set(_i.copyWith(resignationDate: d));
            },
          ),
          const SizedBox(height: 16),
          _label('Last day of work'),
          const SizedBox(height: 4),
          DateField(
            value: _i.lastDayOfWork,
            locked: false,
            onChanged: (d) {
              if (d != null) _set(_i.copyWith(lastDayOfWork: d));
            },
          ),
          _error('lastDayOfWork'),
          const SizedBox(height: 16),
          _label('Turnover instructions'),
          const SizedBox(height: 4),
          TextFormField(
            key: ValueKey('turnover-${_i.employeeId}'),
            initialValue: _i.turnoverInstructions,
            minLines: 3,
            maxLines: 8,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              labelText: 'Turnover instructions',
            ),
            onChanged: (v) => _set(_i.copyWith(turnoverInstructions: v)),
          ),
          _error('turnoverInstructions'),
          const SizedBox(height: 16),
          SwitchListTile(
            value: _i.includeClearanceMention,
            onChanged: (v) => _set(_i.copyWith(includeClearanceMention: v)),
            title: const Text('Include clearance reminder'),
            contentPadding: EdgeInsets.zero,
          ),
          SwitchListTile(
            value: _i.includeFinalPayMention,
            onChanged: (v) => _set(_i.copyWith(includeFinalPayMention: v)),
            title: const Text('Include DOLE LA 06-20 final-pay disclosure'),
            contentPadding: EdgeInsets.zero,
          ),
        ],
      ),
    );
  }
}
