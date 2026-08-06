import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../inputs/annex_a_editor.dart';
import '../inputs/company_picker.dart';
import '../inputs/date_field.dart';
import '../inputs/employee_picker.dart';
import '../templates/employment_contract_inputs.dart';
import '../../../data/models/role_scorecard.dart';
import '../../../data/repositories/role_scorecard_repository.dart';
import '../../../widgets/employee_name_field.dart';
import '../../../widgets/role_title_field.dart';

class EmploymentContractForm extends ConsumerStatefulWidget {
  final EmploymentContractInputs initial;
  final bool employeeLocked;
  final ValueChanged<EmploymentContractInputs> onChanged;
  final ValueChanged<String> onEmployeeChanged;
  final ValueChanged<String> onCompanyChanged;
  const EmploymentContractForm({
    super.key,
    required this.initial,
    required this.employeeLocked,
    required this.onChanged,
    required this.onEmployeeChanged,
    required this.onCompanyChanged,
  });

  @override
  ConsumerState<EmploymentContractForm> createState() =>
      _EmploymentContractFormState();
}

class _EmploymentContractFormState
    extends ConsumerState<EmploymentContractForm> {
  late EmploymentContractInputs _i = widget.initial;
  final ScrollController _scrollController = ScrollController();

  // Graduated training wage — local UI state. Seeded from the incoming
  // inputs so a pre-filled contract (rare today) shows the toggle on.
  late bool _trainingWageEnabled = widget.initial.trainingWage != null;
  late String _trainingDailyRate =
      widget.initial.trainingWage?.dailyRate ?? '350';
  late String _trainingDays =
      widget.initial.trainingWage?.trainingDays.toString() ?? '7';

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant EmploymentContractForm oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.initial, widget.initial)) {
      _i = widget.initial;
    }
  }

  // Assembles a TrainingWage from the current UI state, or null when the
  // toggle is off. trainingDays falls back to 7 on an unparseable value so
  // the assembled inputs stay well-formed while the user types.
  TrainingWage? _assembleTrainingWage() {
    if (!_trainingWageEnabled) return null;
    return TrainingWage(
      dailyRate: _trainingDailyRate,
      trainingDays: int.tryParse(_trainingDays.trim()) ?? 7,
    );
  }

  void _set(EmploymentContractInputs n) {
    setState(() => _i = n);
    widget.onChanged(n);
  }

  Future<void> _onPositionChanged(String position) async {
    // Always update the typed/selected position immediately.
    _set(_i.copyWith(position: position));
    final q = position.trim().toLowerCase();
    if (q.isEmpty) return;
    try {
      final cards = await ref.read(roleScorecardListProvider.future);
      RoleScorecard? match;
      for (final c in cards) {
        if (c.jobTitle.trim().toLowerCase() == q) {
          match = c;
          break;
        }
      }
      if (match == null || !mounted) return;
      final salary = match.baseSalary;
      _set(
        _i.copyWith(
          missionStatement: match.missionStatement,
          responsibilities: match.responsibilities
              .map((r) => ContractResponsibility(area: r.area, tasks: r.tasks))
              .toList(),
          kpis: match.kpis
              .map((k) => ContractKpi(metric: k.metric, frequency: k.frequency))
              .toList(),
          workHoursPerDay: match.workHoursPerDay,
          workDaysPerWeek: match.workDaysPerWeek,
          monthlySalary: salary == null
              ? _i.monthlySalary
              : NumberFormat('#,##0', 'en_US').format(salary.toDouble()),
          salaryPeriod: _periodFromWageType(match.wageType),
        ),
      );
    } catch (_) {
      // Best-effort: leave the position set, derived fields unchanged.
    }
  }

  String _periodFromWageType(String? wt) {
    switch ((wt ?? '').toUpperCase()) {
      case 'DAILY':
        return 'day';
      case 'HOURLY':
        return 'hour';
      default:
        return 'month';
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
            key: const ValueKey('ec-employee'),
            selectedId: (_i.employeeId?.isEmpty ?? true) ? null : _i.employeeId,
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
            key: const ValueKey('ec-company'),
            selectedId: _i.companyId.isEmpty ? null : _i.companyId,
            locked: false,
            onChanged: (id) {
              if (id == null) return;
              _set(_i.copyWith(companyId: id));
              widget.onCompanyChanged(id);
            },
          ),
          const SizedBox(height: 16),
          _label('Company Representative Name'),
          const SizedBox(height: 4),
          EmployeeNameField(
            key: const ValueKey('ec-representativeName'),
            value: _i.representativeName,
            onChanged: (v) => _set(_i.copyWith(representativeName: v)),
          ),
          const SizedBox(height: 16),
          _label('Representative Role'),
          const SizedBox(height: 4),
          RoleTitleField(
            key: const ValueKey('ec-representativeRole'),
            value: _i.representativeRole,
            hintText: 'e.g. People Manager',
            onChanged: (v) => _set(_i.copyWith(representativeRole: v)),
          ),
          const SizedBox(height: 16),
          _label('Place of Execution'),
          const SizedBox(height: 4),
          TextFormField(
            key: const ValueKey('ec-place'),
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
            key: const ValueKey('ec-industry'),
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
            key: const ValueKey('ec-position'),
            value: _i.position,
            onChanged: _onPositionChanged,
          ),
          const SizedBox(height: 16),
          _label('Date Entered'),
          const SizedBox(height: 4),
          DateField(
            key: const ValueKey('ec-dateEntered'),
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
            key: const ValueKey('ec-probationStart'),
            value: _i.probationStart,
            locked: false,
            onChanged: (d) => _set(_i.copyWith(probationStart: d)),
          ),
          const SizedBox(height: 16),
          _label('Probationary End'),
          const SizedBox(height: 4),
          DateField(
            key: const ValueKey('ec-probationEnd'),
            value: _i.probationEnd,
            locked: false,
            onChanged: (d) => _set(_i.copyWith(probationEnd: d)),
          ),
          const SizedBox(height: 16),
          _label('Salary (PHP)'),
          const SizedBox(height: 4),
          TextFormField(
            key: const ValueKey('ec-monthlySalary'),
            initialValue: _i.monthlySalary,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              isDense: true,
            ),
            onChanged: (v) => _set(_i.copyWith(monthlySalary: v)),
          ),
          const SizedBox(height: 16),
          _label('Salary Period'),
          const SizedBox(height: 4),
          DropdownButtonFormField<String>(
            key: const ValueKey('ec-salaryPeriod'),
            initialValue: _i.salaryPeriod,
            isExpanded: true,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              isDense: true,
            ),
            items: const [
              DropdownMenuItem(value: 'month', child: Text('Per month')),
              DropdownMenuItem(value: 'day', child: Text('Per day')),
              DropdownMenuItem(value: 'hour', child: Text('Per hour')),
            ],
            onChanged: (v) {
              if (v != null) _set(_i.copyWith(salaryPeriod: v));
            },
          ),
          const SizedBox(height: 16),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Graduated training wage'),
            value: _trainingWageEnabled,
            onChanged: (on) {
              setState(() => _trainingWageEnabled = on);
              _set(_i.copyWith(trainingWage: _assembleTrainingWage()));
            },
          ),
          if (_trainingWageEnabled) ...[
            const SizedBox(height: 8),
            _label('Training daily rate (PHP)'),
            const SizedBox(height: 4),
            TextFormField(
              key: const ValueKey('ec-trainingDailyRate'),
              initialValue: _trainingDailyRate,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (v) {
                _trainingDailyRate = v;
                _set(_i.copyWith(trainingWage: _assembleTrainingWage()));
              },
            ),
            const SizedBox(height: 16),
            _label('Training period (days)'),
            const SizedBox(height: 4),
            TextFormField(
              key: const ValueKey('ec-trainingDays'),
              initialValue: _trainingDays,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (v) {
                _trainingDays = v;
                _set(_i.copyWith(trainingWage: _assembleTrainingWage()));
              },
            ),
          ],
          const SizedBox(height: 16),
          _label('Work Hours per Day'),
          const SizedBox(height: 4),
          TextFormField(
            key: const ValueKey('ec-workHoursPerDay'),
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
            key: const ValueKey('ec-workDaysPerWeek'),
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
            key: const ValueKey('ec-nonCompeteMonths'),
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
            key: const ValueKey('ec-employerSignatoryName'),
            value: _i.employerSignatoryName,
            onChanged: (v) => _set(_i.copyWith(employerSignatoryName: v)),
          ),
          const SizedBox(height: 16),
          _label('Employer Signatory Role'),
          const SizedBox(height: 4),
          RoleTitleField(
            key: const ValueKey('ec-employerSignatoryRole'),
            value: _i.employerSignatoryRole,
            onChanged: (v) => _set(_i.copyWith(employerSignatoryRole: v)),
          ),
          const SizedBox(height: 16),
          _label('Witness 1 Name'),
          const SizedBox(height: 4),
          EmployeeNameField(
            key: const ValueKey('ec-witness1Name'),
            value: _i.witness1Name,
            onChanged: (v) => _set(_i.copyWith(witness1Name: v)),
            exclude: [
              _i.employeeFullName,
              _i.employerSignatoryName,
              _i.representativeName,
              _i.witness2Name,
            ],
          ),
          const SizedBox(height: 16),
          _label('Witness 1 Role'),
          const SizedBox(height: 4),
          RoleTitleField(
            key: const ValueKey('ec-witness1Role'),
            value: _i.witness1Role,
            onChanged: (v) => _set(_i.copyWith(witness1Role: v)),
          ),
          const SizedBox(height: 16),
          _label('Witness 2 Name'),
          const SizedBox(height: 4),
          EmployeeNameField(
            key: const ValueKey('ec-witness2Name'),
            value: _i.witness2Name,
            onChanged: (v) => _set(_i.copyWith(witness2Name: v)),
            exclude: [
              _i.employeeFullName,
              _i.employerSignatoryName,
              _i.representativeName,
              _i.witness1Name,
            ],
          ),
          const SizedBox(height: 16),
          _label('Witness 2 Role'),
          const SizedBox(height: 4),
          RoleTitleField(
            key: const ValueKey('ec-witness2Role'),
            value: _i.witness2Role,
            onChanged: (v) => _set(_i.copyWith(witness2Role: v)),
          ),
          const SizedBox(height: 16),
          _label('Mission Statement'),
          const SizedBox(height: 4),
          TextFormField(
            key: const ValueKey('ec-missionStatement'),
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
            key: const ValueKey('ec-annexA'),
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
