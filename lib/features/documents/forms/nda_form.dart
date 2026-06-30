import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../inputs/company_picker.dart';
import '../inputs/date_field.dart';
import '../inputs/employee_picker.dart';
import '../templates/nda_inputs.dart';
import '../templates/nda_validate.dart';
import '../../../widgets/employee_name_field.dart';
import '../../../widgets/role_title_field.dart';

class NdaForm extends ConsumerStatefulWidget {
  final NdaInputs initial;
  final bool employeeLocked;
  final ValueChanged<NdaInputs> onChanged;
  final ValueChanged<String> onEmployeeChanged;
  final ValueChanged<String> onCompanyChanged;
  const NdaForm({
    super.key,
    required this.initial,
    required this.employeeLocked,
    required this.onChanged,
    required this.onEmployeeChanged,
    required this.onCompanyChanged,
  });

  @override
  ConsumerState<NdaForm> createState() => _NdaFormState();
}

class _NdaFormState extends ConsumerState<NdaForm> {
  late NdaInputs _i = widget.initial;
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant NdaForm oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.initial, widget.initial)) {
      _i = widget.initial;
    }
  }

  void _set(NdaInputs next) {
    setState(() => _i = next);
    widget.onChanged(next);
  }

  String? _errFor(String field) {
    for (final e in validateNda(_i)) {
      if (e.field == field) return e.message;
    }
    return null;
  }

  Widget _error(String field) {
    final msg = _errFor(field);
    if (msg == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Text(
        msg,
        style: const TextStyle(color: Colors.red, fontSize: 12),
      ),
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
                _set(_i.copyWith(employeeId: id));
                widget.onEmployeeChanged(id);
              }
            },
          ),
          _error('employeeFullName'),
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
          _error('companyName'),
          _error('companyAddress'),
          const SizedBox(height: 16),
          _label('Position'),
          const SizedBox(height: 4),
          RoleTitleField(
            value: _i.employeePosition,
            onChanged: (v) => _set(_i.copyWith(employeePosition: v)),
          ),
          _error('employeePosition'),
          const SizedBox(height: 16),
          _label('Home Address'),
          const SizedBox(height: 4),
          TextFormField(
            initialValue: _i.employeeHomeAddress,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              isDense: true,
            ),
            onChanged: (v) => _set(_i.copyWith(employeeHomeAddress: v)),
          ),
          _error('employeeHomeAddress'),
          const SizedBox(height: 16),
          _label('Effective Date'),
          const SizedBox(height: 4),
          DateField(
            value: _i.effectiveDate,
            locked: false,
            onChanged: (d) => _set(_i.copyWith(effectiveDate: d)),
          ),
          _error('effectiveDate'),
          const SizedBox(height: 16),
          _label('Authorized Signatory Name'),
          const SizedBox(height: 4),
          EmployeeNameField(
            value: _i.authorizedSignatoryName,
            onChanged: (v) =>
                _set(_i.copyWith(authorizedSignatoryName: v)),
          ),
          _error('authorizedSignatoryName'),
          const SizedBox(height: 16),
          _label('Authorized Signatory Role'),
          const SizedBox(height: 4),
          RoleTitleField(
            value: _i.authorizedSignatoryRole,
            onChanged: (v) =>
                _set(_i.copyWith(authorizedSignatoryRole: v)),
          ),
        ],
      ),
    );
  }
}
