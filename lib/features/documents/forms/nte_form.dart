import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../inputs/charges_editor.dart';
import '../inputs/company_picker.dart';
import '../inputs/date_field.dart';
import '../inputs/employee_picker.dart';
import '../inputs/hr_manager_field.dart';
import '../inputs/violations_editor.dart';
import '../templates/nte_inputs.dart';

class NteForm extends ConsumerStatefulWidget {
  final NteInputs initial;
  final bool employeeLocked;
  final ValueChanged<NteInputs> onChanged;
  final ValueChanged<String> onEmployeeChanged;
  const NteForm({
    super.key,
    required this.initial,
    required this.employeeLocked,
    required this.onChanged,
    required this.onEmployeeChanged,
  });

  @override
  ConsumerState<NteForm> createState() => _NteFormState();
}

class _NteFormState extends ConsumerState<NteForm> {
  late NteInputs _i = widget.initial;
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _set(NteInputs n) {
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
          if (id != null) widget.onEmployeeChanged(id);
        },
      ),
      const SizedBox(height: 16),
      _label('Company'),
      const SizedBox(height: 4),
      CompanyPicker(
        selectedId: _i.companyId.isEmpty ? null : _i.companyId,
        locked: false,
        onChanged: (id) {
          if (id != null) _set(_i.copyWith(companyId: id));
        },
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
      _label('Response Deadline'),
      const SizedBox(height: 4),
      DateField(
        value: _i.responseDeadline,
        locked: false,
        onChanged: (d) {
          if (d != null) _set(_i.copyWith(responseDeadline: d));
        },
      ),
      const SizedBox(height: 16),
      _label('Subject Subtopic (optional)'),
      const SizedBox(height: 4),
      TextFormField(
        initialValue: _i.subjectSubtopic,
        decoration: const InputDecoration(
          border: OutlineInputBorder(),
          isDense: true,
          hintText: 'Appears after "Notice to Explain — "',
        ),
        onChanged: (s) => _set(_i.copyWith(subjectSubtopic: s)),
      ),
      const SizedBox(height: 16),
      _label('HR Manager Name'),
      const SizedBox(height: 4),
      HrManagerField(
        value: _i.hrManagerName ?? '',
        onChanged: (s) =>
            _set(_i.copyWith(hrManagerName: s.isEmpty ? null : s)),
      ),
      const SizedBox(height: 16),
      _label('Charges'),
      const SizedBox(height: 4),
      ChargesEditor(
        charges: _i.charges,
        onChanged: (next) => _set(_i.copyWith(charges: next)),
      ),
      const SizedBox(height: 16),
      _label('Applicable Violations'),
      const SizedBox(height: 4),
      ViolationsEditor(
        items: _i.applicableViolations,
        onChanged: (next) => _set(_i.copyWith(applicableViolations: next)),
      ),
        ],
      ),
    );
  }
}
