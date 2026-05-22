import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../inputs/annex_a_editor.dart';
import '../inputs/company_picker.dart';
import '../inputs/date_field.dart';
import '../inputs/employee_picker.dart';
import '../providers.dart';
import '../templates/employment_contract_inputs.dart';
import '../../../widgets/employee_name_field.dart';
import '../../../widgets/role_title_field.dart';

class EmploymentContractForm extends ConsumerStatefulWidget {
  final EmploymentContractInputs initial;
  final bool employeeLocked;
  final ValueChanged<EmploymentContractInputs> onChanged;
  final ValueChanged<String> onEmployeeChanged;
  const EmploymentContractForm({
    super.key,
    required this.initial,
    required this.employeeLocked,
    required this.onChanged,
    required this.onEmployeeChanged,
  });

  @override
  ConsumerState<EmploymentContractForm> createState() =>
      _EmploymentContractFormState();
}

class _EmploymentContractFormState
    extends ConsumerState<EmploymentContractForm> {
  late EmploymentContractInputs _i = widget.initial;
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _set(EmploymentContractInputs n) {
    setState(() => _i = n);
    widget.onChanged(n);
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
        [co.city, co.province, co.zipCode]
            .where((s) => s != null && s.isNotEmpty)
            .join(', '),
      ].where((s) => s != null && s.isNotEmpty).cast<String>()
          .join(' · ');
      final place = [co.city, co.province, 'Philippines']
          .where((s) => s != null && s.isNotEmpty)
          .cast<String>()
          .join(', ');
      final repRole = (co.legalSignatoryRole?.isNotEmpty == true)
          ? co.legalSignatoryRole!
          : 'People Manager';
      final repName = co.hrManagerName ?? '';
      _set(_i.copyWith(
        companyName: co.name,
        companyAddress: address,
        place: place,
        representativeName: repName,
        representativeRole: repRole,
        employerSignatoryName: repName,
        employerSignatoryRole: repRole,
      ));
    } catch (_) {
      // Best-effort; leave companyId set, user can fill manually.
    }
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
          const SizedBox(height: 16),
          _label('Company Representative Name'),
          const SizedBox(height: 4),
          EmployeeNameField(
            value: _i.representativeName,
            onChanged: (v) => _set(_i.copyWith(representativeName: v)),
          ),
          const SizedBox(height: 16),
          _label('Representative Role'),
          const SizedBox(height: 4),
          RoleTitleField(
            value: _i.representativeRole,
            hintText: 'e.g. People Manager',
            onChanged: (v) => _set(_i.copyWith(representativeRole: v)),
          ),
          const SizedBox(height: 16),
          _label('Place of Execution'),
          const SizedBox(height: 4),
          TextFormField(
            initialValue: _i.place,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              isDense: true,
            ),
            onChanged: (v) => _set(_i.copyWith(place: v)),
          ),
          const SizedBox(height: 16),
          _label('Industry'),
          const SizedBox(height: 4),
          TextFormField(
            initialValue: _i.industry,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              isDense: true,
            ),
            onChanged: (v) => _set(_i.copyWith(industry: v)),
          ),
          const SizedBox(height: 16),
          _label('Position'),
          const SizedBox(height: 4),
          RoleTitleField(
            value: _i.position,
            onChanged: (v) => _set(_i.copyWith(position: v)),
          ),
          const SizedBox(height: 16),
          _label('Date Entered'),
          const SizedBox(height: 4),
          DateField(
            value: _i.dateEntered,
            locked: false,
            onChanged: (d) {
              if (d != null) _set(_i.copyWith(dateEntered: d));
            },
          ),
          const SizedBox(height: 16),
          _label('Probationary Start'),
          const SizedBox(height: 4),
          DateField(
            value: _i.probationStart,
            locked: false,
            onChanged: (d) => _set(_i.copyWith(probationStart: d)),
          ),
          const SizedBox(height: 16),
          _label('Probationary End'),
          const SizedBox(height: 4),
          DateField(
            value: _i.probationEnd,
            locked: false,
            onChanged: (d) => _set(_i.copyWith(probationEnd: d)),
          ),
          const SizedBox(height: 16),
          _label('Monthly Salary (PHP)'),
          const SizedBox(height: 4),
          TextFormField(
            initialValue: _i.monthlySalary,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              isDense: true,
            ),
            onChanged: (v) => _set(_i.copyWith(monthlySalary: v)),
          ),
          const SizedBox(height: 16),
          _label('Work Hours per Day'),
          const SizedBox(height: 4),
          TextFormField(
            initialValue: _i.workHoursPerDay.toString(),
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              isDense: true,
            ),
            onChanged: (v) {
              final n = int.tryParse(v.trim());
              if (n != null) _set(_i.copyWith(workHoursPerDay: n));
            },
          ),
          const SizedBox(height: 16),
          _label('Work Days per Week'),
          const SizedBox(height: 4),
          TextFormField(
            initialValue: _i.workDaysPerWeek,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              isDense: true,
            ),
            onChanged: (v) => _set(_i.copyWith(workDaysPerWeek: v)),
          ),
          const SizedBox(height: 16),
          _label('Non-Compete (months)'),
          const SizedBox(height: 4),
          TextFormField(
            initialValue: _i.nonCompeteMonths.toString(),
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              isDense: true,
            ),
            onChanged: (v) {
              final n = int.tryParse(v.trim());
              if (n != null) _set(_i.copyWith(nonCompeteMonths: n));
            },
          ),
          const SizedBox(height: 16),
          _label('Employer Signatory Name'),
          const SizedBox(height: 4),
          EmployeeNameField(
            value: _i.employerSignatoryName,
            onChanged: (v) => _set(_i.copyWith(employerSignatoryName: v)),
          ),
          const SizedBox(height: 16),
          _label('Employer Signatory Role'),
          const SizedBox(height: 4),
          RoleTitleField(
            value: _i.employerSignatoryRole,
            onChanged: (v) => _set(_i.copyWith(employerSignatoryRole: v)),
          ),
          const SizedBox(height: 16),
          _label('Witness 1 Name'),
          const SizedBox(height: 4),
          EmployeeNameField(
            value: _i.witness1Name,
            onChanged: (v) => _set(_i.copyWith(witness1Name: v)),
          ),
          const SizedBox(height: 16),
          _label('Witness 1 Role'),
          const SizedBox(height: 4),
          RoleTitleField(
            value: _i.witness1Role,
            onChanged: (v) => _set(_i.copyWith(witness1Role: v)),
          ),
          const SizedBox(height: 16),
          _label('Witness 2 Name'),
          const SizedBox(height: 4),
          EmployeeNameField(
            value: _i.witness2Name,
            onChanged: (v) => _set(_i.copyWith(witness2Name: v)),
          ),
          const SizedBox(height: 16),
          _label('Witness 2 Role'),
          const SizedBox(height: 4),
          RoleTitleField(
            value: _i.witness2Role,
            onChanged: (v) => _set(_i.copyWith(witness2Role: v)),
          ),
          const SizedBox(height: 16),
          _label('Mission Statement'),
          const SizedBox(height: 4),
          TextFormField(
            initialValue: _i.missionStatement,
            maxLines: 3,
            minLines: 1,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              isDense: true,
            ),
            onChanged: (v) => _set(_i.copyWith(missionStatement: v)),
          ),
          const SizedBox(height: 16),
          _label('Annex A'),
          const SizedBox(height: 4),
          AnnexAEditor(
            responsibilities: _i.responsibilities,
            onResponsibilitiesChanged: (next) =>
                _set(_i.copyWith(responsibilities: next)),
            kpis: _i.kpis,
            onKpisChanged: (next) => _set(_i.copyWith(kpis: next)),
          ),
        ],
      ),
    );
  }
}
