import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../inputs/company_picker.dart';
import '../inputs/date_field.dart';
import '../inputs/employee_picker.dart';
import '../inputs/findings_editor.dart';
import '../templates/non_reg_inputs.dart';
import '../../../widgets/employee_name_field.dart';
import '../../../widgets/role_title_field.dart';

class NonRegForm extends ConsumerStatefulWidget {
  final NonRegInputs initial;
  final bool employeeLocked;
  final ValueChanged<NonRegInputs> onChanged;
  final ValueChanged<String> onEmployeeChanged;
  final ValueChanged<String> onCompanyChanged;
  const NonRegForm({
    super.key,
    required this.initial,
    required this.employeeLocked,
    required this.onChanged,
    required this.onEmployeeChanged,
    required this.onCompanyChanged,
  });

  @override
  ConsumerState<NonRegForm> createState() => _NonRegFormState();
}

class _NonRegFormState extends ConsumerState<NonRegForm> {
  late NonRegInputs _i = widget.initial;
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant NonRegForm oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.initial, widget.initial)) {
      _i = widget.initial;
    }
  }

  void _set(NonRegInputs n) {
    setState(() => _i = n);
    widget.onChanged(n);
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
            onChanged: (id) {
              if (id != null) {
                // Optimistic local update so validation passes immediately
                // while the parent's async autofill is still running.
                _set(_i.copyWith(employeeId: id));
                widget.onEmployeeChanged(id);
              }
            },
          ),
          const SizedBox(height: 16),
          _label('Position'),
          const SizedBox(height: 4),
          RoleTitleField(
            value: _i.employeePosition,
            onChanged: (s) => _set(_i.copyWith(employeePosition: s)),
          ),
          const SizedBox(height: 16),
          _label('Company'),
          const SizedBox(height: 4),
          CompanyPicker(
            selectedId: _i.companyId.isEmpty ? null : _i.companyId,
            locked: false,
            onChanged: (id) {
              if (id == null) return;
              _set(_i.copyWith(companyId: id));
              widget.onCompanyChanged(id);
            },
          ),
          const SizedBox(height: 16),
          _label('HR Manager Name'),
          const SizedBox(height: 4),
          EmployeeNameField(
            value: _i.hrManagerName ?? '',
            onChanged: (s) =>
                _set(_i.copyWith(hrManagerName: s.isEmpty ? null : s)),
          ),
          const SizedBox(height: 16),
          _label('Date Issued'),
          const SizedBox(height: 4),
          DateField(
            value: _i.dateIssued,
            locked: false,
            onChanged: (d) {
              if (d != null) _set(_i.copyWith(dateIssued: d));
            },
          ),
          const SizedBox(height: 16),
          _label('Probationary Start'),
          const SizedBox(height: 4),
          DateField(
            value: _i.probationaryStart,
            locked: false,
            onChanged: (d) => _set(_i.copyWith(probationaryStart: d)),
          ),
          const SizedBox(height: 16),
          _label('Probationary End'),
          const SizedBox(height: 4),
          DateField(
            value: _i.probationaryEnd,
            locked: false,
            onChanged: (d) => _set(_i.copyWith(probationaryEnd: d)),
          ),
          const SizedBox(height: 16),
          _label('Effective End Date'),
          const SizedBox(height: 4),
          DateField(
            value: _i.effectiveEndDate,
            locked: false,
            onChanged: (d) => _set(_i.copyWith(effectiveEndDate: d)),
          ),
          const SizedBox(height: 16),
          _label('Salutation Name'),
          const SizedBox(height: 4),
          TextFormField(
            initialValue: _i.salutationName,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              isDense: true,
              hintText: 'e.g., Ms. Vidal',
            ),
            onChanged: (s) => _set(_i.copyWith(salutationName: s)),
          ),
          const SizedBox(height: 16),
          _label('Note on Scope of Evaluation (optional)'),
          const SizedBox(height: 4),
          TextFormField(
            initialValue: _i.noteOnScope,
            maxLines: 3,
            minLines: 1,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              isDense: true,
              hintText:
                  'If duties were reassigned during probation, briefly note here.',
            ),
            onChanged: (s) => _set(_i.copyWith(noteOnScope: s)),
          ),
          const SizedBox(height: 16),
          _label('Findings'),
          const SizedBox(height: 4),
          FindingsEditor(
            findings: _i.findings,
            onChanged: (next) => _set(_i.copyWith(findings: next)),
          ),
          const SizedBox(height: 16),
          _label('Witness Name (optional)'),
          const SizedBox(height: 4),
          TextFormField(
            initialValue: _i.witnessName,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              isDense: true,
              hintText: 'Pre-fills the witness signature line.',
            ),
            onChanged: (s) => _set(_i.copyWith(witnessName: s)),
          ),
        ],
      ),
    );
  }
}
