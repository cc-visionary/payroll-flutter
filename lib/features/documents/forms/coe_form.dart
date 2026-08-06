import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../inputs/company_picker.dart';
import '../inputs/date_field.dart';
import '../inputs/employee_picker.dart';
import '../templates/coe_inputs.dart';
import '../templates/coe_validate.dart';
import '../../../widgets/employee_name_field.dart';
import '../../../widgets/role_title_field.dart';

class CoeForm extends ConsumerStatefulWidget {
  final CoeInputs initial;
  final bool employeeLocked;
  final ValueChanged<CoeInputs> onChanged;
  final ValueChanged<String> onEmployeeChanged;
  final ValueChanged<String> onCompanyChanged;
  const CoeForm({
    super.key,
    required this.initial,
    required this.employeeLocked,
    required this.onChanged,
    required this.onEmployeeChanged,
    required this.onCompanyChanged,
  });

  @override
  ConsumerState<CoeForm> createState() => _CoeFormState();
}

class _CoeFormState extends ConsumerState<CoeForm> {
  late CoeInputs _i = widget.initial;
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant CoeForm oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.initial, widget.initial)) {
      _i = widget.initial;
    }
  }

  void _set(CoeInputs next) {
    setState(() => _i = next);
    widget.onChanged(next);
  }

  String? _err(String f) {
    for (final e in validateCoe(_i)) {
      if (e.field == f) return e.message;
    }
    return null;
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
            includeArchived: true,
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
          _label('Position'),
          const SizedBox(height: 4),
          RoleTitleField(
            value: _i.position,
            onChanged: (s) => _set(_i.copyWith(position: s)),
          ),
          if (_err('position') != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                _err('position')!,
                style: const TextStyle(color: Colors.red, fontSize: 12),
              ),
            ),
          const SizedBox(height: 16),
          _label('Hire Date'),
          const SizedBox(height: 4),
          DateField(
            value: _i.dateStart,
            locked: false,
            onChanged: (d) => _set(_i.copyWith(dateStart: d)),
          ),
          const SizedBox(height: 16),
          _label('Separation Date'),
          const SizedBox(height: 4),
          DateField(
            value: _i.dateEnd,
            locked: false,
            onChanged: (d) => _set(_i.copyWith(dateEnd: d)),
          ),
          const SizedBox(height: 16),
          _label('HR Manager Name'),
          const SizedBox(height: 4),
          EmployeeNameField(
            value: _i.hrManagerName ?? '',
            onChanged: (s) =>
                _set(_i.copyWith(hrManagerName: s.isEmpty ? null : s)),
          ),
          if (_i.hrManagerName == null || _i.hrManagerName!.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 4),
              child: Text(
                'Set HR Manager in Settings → Hiring Entities to skip this next time.',
                style: TextStyle(color: Colors.orange, fontSize: 12),
              ),
            ),
          const SizedBox(height: 16),
          _label('Place of Issuance'),
          const SizedBox(height: 4),
          TextFormField(
            initialValue: _i.place,
            decoration: const InputDecoration(
              hintText: 'e.g. Makati City',
              isDense: true,
            ),
            onChanged: (v) => _set(_i.copyWith(place: v)),
          ),
          if (_err('place') != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                _err('place')!,
                style: const TextStyle(color: Colors.red, fontSize: 12),
              ),
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
        ],
      ),
    );
  }
}
