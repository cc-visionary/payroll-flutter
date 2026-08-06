import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';

import '../../../../app/theme.dart';
import '../../../../app/tokens.dart';
import '../../../../data/models/employee.dart';
import '../../../../data/models/role_scorecard.dart';
import '../../../documents/templates/document_template.dart';
import '../../../documents/templates/salary_adjustment_inputs.dart';
import '../../../documents/templates/salary_adjustment_validate.dart';

/// The validated payload returned by [showCompensationChangeDialog].
///
/// [changeType] is one of `SALARY_INCREASE | SALARY_DECREASE | PROMOTION |
/// LATERAL_TRANSFER | DEMOTION`. [newWageType] is one of
/// `MONTHLY | DAILY | HOURLY`. [newScorecardId] is only populated for the
/// role-change types; it is `null` for the pay-only variants.
class CompensationChangeRequest {
  final String changeType;
  final Decimal newSalary;
  final String newWageType;
  final String? newScorecardId;
  final DateTime effectiveDate;
  final String reason;

  const CompensationChangeRequest({
    required this.changeType,
    required this.newSalary,
    required this.newWageType,
    required this.newScorecardId,
    required this.effectiveDate,
    required this.reason,
  });
}

/// The five change types, in display order.
const List<String> kCompensationChangeTypes = [
  'SALARY_INCREASE',
  'SALARY_DECREASE',
  'PROMOTION',
  'LATERAL_TRANSFER',
  'DEMOTION',
];

const List<String> kWageTypes = ['MONTHLY', 'DAILY', 'HOURLY'];

String compensationChangeTypeLabel(String changeType) => switch (changeType) {
  'SALARY_INCREASE' => 'Salary Increase',
  'SALARY_DECREASE' => 'Salary Decrease',
  'PROMOTION' => 'Promotion',
  'LATERAL_TRANSFER' => 'Lateral Transfer',
  'DEMOTION' => 'Demotion',
  _ => changeType,
};

/// Maps a dialog change type to the underlying [SalaryAdjustmentType] used by
/// [validateSalaryAdjustment] and the salary-adjustment document template.
SalaryAdjustmentType changeTypeToAdjustmentType(String changeType) =>
    switch (changeType) {
      'PROMOTION' => SalaryAdjustmentType.promotion,
      'LATERAL_TRANSFER' => SalaryAdjustmentType.lateral,
      'DEMOTION' => SalaryAdjustmentType.demotion,
      // SALARY_INCREASE and SALARY_DECREASE are both pay-only adjustments.
      _ => SalaryAdjustmentType.salaryAdjustment,
    };

/// The new-salary field is shown for every type except a lateral transfer,
/// which by definition carries the current salary unchanged.
bool showsNewSalaryField(String changeType) => changeType != 'LATERAL_TRANSFER';

/// The target-role dropdown is shown only for the role-change types.
bool showsRoleDropdown(String changeType) =>
    changeType == 'PROMOTION' ||
    changeType == 'LATERAL_TRANSFER' ||
    changeType == 'DEMOTION';

/// Pure validation for a compensation change. Layers the direction/date rules
/// (which [validateSalaryAdjustment] does not cover) on top of the shared
/// salary-adjustment semantics (positivity, difference, lateral-equality,
/// role-change-differing-role).
///
/// [today] is injectable for deterministic testing; defaults to `DateTime.now()`.
List<ValidationError> validateCompensationRequest({
  required String changeType,
  required Decimal currentSalary,
  required Decimal newSalary,
  required String currentWageType,
  required String newWageType,
  required String? newScorecardId,
  required String? currentScorecardId,
  required DateTime effectiveDate,
  required String reason,
  required Employee employee,
  DateTime? today,
}) {
  final type = changeTypeToAdjustmentType(changeType);
  final inputs = SalaryAdjustmentInputs(
    type: type,
    employeeId: employee.id,
    employeeFullName: employee.fullName,
    companyId: employee.companyId,
    companyName: '',
    // Resolved for real at document-generation time (Task 10); a non-empty
    // placeholder keeps the shared validator from flagging a field this
    // dialog does not own.
    hrManagerName: 'HR',
    oldRoleScorecardId: currentScorecardId,
    newRoleScorecardId: type.isRoleChange ? newScorecardId : null,
    oldSalary: currentSalary,
    newSalary: newSalary,
    salaryPeriod: newWageType,
    effectiveDate: effectiveDate,
    issueDate: today ?? DateTime.now(),
    reason: reason,
  );

  // Only keep the errors for fields this dialog actually renders — the shared
  // validator also checks employee/company/HR-manager, which are supplied
  // upstream and are not editable here.
  const dialogFields = {
    'oldSalary',
    'newSalary',
    'newRoleScorecardId',
    'reason',
  };
  final errors = validateSalaryAdjustment(
    inputs,
  ).where((e) => dialogFields.contains(e.field)).toList();

  // Direction rules the shared validator does not enforce.
  switch (changeType) {
    case 'SALARY_INCREASE':
      if (newSalary <= currentSalary) {
        errors.add(
          const ValidationError(
            'newSalary',
            'A salary increase must be higher than the current salary',
          ),
        );
      }
    case 'SALARY_DECREASE':
    case 'DEMOTION':
      if (newSalary >= currentSalary) {
        errors.add(
          const ValidationError(
            'newSalary',
            'A salary decrease must be lower than the current salary',
          ),
        );
      }
    // LATERAL_TRANSFER equality is already enforced by the shared validator.
  }

  // Effective date must not be in the past.
  final now = today ?? DateTime.now();
  final todayDate = DateTime(now.year, now.month, now.day);
  final effDate = DateTime(
    effectiveDate.year,
    effectiveDate.month,
    effectiveDate.day,
  );
  if (effDate.isBefore(todayDate)) {
    errors.add(
      const ValidationError(
        'effectiveDate',
        'Effective date cannot be in the past',
      ),
    );
  }

  // Rates pro-rate fine for any wage type (the daily rate is the universal
  // unit — getDayRates derives hourly/minute from it). The ONE wageType-
  // dependent divergence is compute_engine.dart:100: paid-leave days count as
  // workdays only for MONTHLY employees. A DAILY->MONTHLY switch mid-period
  // would apply that rule to the whole period, over-counting leave taken
  // before the switch. Forcing such changes onto the 1st removes that edge.
  if (newWageType != currentWageType && effectiveDate.day != 1) {
    errors.add(
      const ValidationError(
        'effectiveDate',
        'A wage-type change must take effect on the 1st of a month',
      ),
    );
  }

  return errors;
}

/// Opens the "Adjust Compensation / Change Role" dialog. Returns a validated
/// [CompensationChangeRequest] on confirm, or `null` if the user cancels.
Future<CompensationChangeRequest?> showCompensationChangeDialog(
  BuildContext context, {
  required Employee employee,
  required RoleScorecard? currentCard,
  required List<RoleScorecard> allCards,
}) {
  return showDialog<CompensationChangeRequest>(
    context: context,
    builder: (_) => _CompensationChangeDialog(
      employee: employee,
      currentCard: currentCard,
      allCards: allCards,
    ),
  );
}

class _CompensationChangeDialog extends StatefulWidget {
  final Employee employee;
  final RoleScorecard? currentCard;
  final List<RoleScorecard> allCards;

  const _CompensationChangeDialog({
    required this.employee,
    required this.currentCard,
    required this.allCards,
  });

  @override
  State<_CompensationChangeDialog> createState() =>
      _CompensationChangeDialogState();
}

class _CompensationChangeDialogState extends State<_CompensationChangeDialog> {
  String _changeType = 'SALARY_INCREASE';
  final _salaryCtrl = TextEditingController();
  final _reasonCtrl = TextEditingController();
  late String _wageType;
  String? _scorecardId;
  late DateTime _effectiveDate;
  Map<String, String> _errors = const {};

  @override
  void initState() {
    super.initState();
    _wageType = _currentWageType;
    final now = DateTime.now();
    _effectiveDate = DateTime(now.year, now.month + 1, 1);
  }

  /// The employee's wage type as of today, i.e. before this change is
  /// applied. Single source of truth for both the wage-type dropdown's
  /// initial value and the "did this change switch wage type" validation
  /// check, so the two can never disagree.
  String get _currentWageType {
    final cardWage = widget.currentCard?.wageType;
    return kWageTypes.contains(cardWage) ? cardWage! : 'MONTHLY';
  }

  @override
  void dispose() {
    _salaryCtrl.dispose();
    _reasonCtrl.dispose();
    super.dispose();
  }

  Decimal get _currentSalary => widget.currentCard?.baseSalary ?? Decimal.zero;

  Decimal? _tryParseMoney(String raw) {
    final cleaned = raw.replaceAll(RegExp(r'[₱,\s]'), '').trim();
    if (cleaned.isEmpty) return null;
    try {
      return Decimal.parse(cleaned);
    } catch (_) {
      return null;
    }
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _effectiveDate,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: DateTime(now.year + 5),
    );
    if (picked != null) setState(() => _effectiveDate = picked);
  }

  void _confirm() {
    final current = _currentSalary;
    final Decimal newSalary;
    if (!showsNewSalaryField(_changeType)) {
      // Lateral transfer carries the current salary unchanged.
      newSalary = current;
    } else {
      final parsed = _tryParseMoney(_salaryCtrl.text);
      if (parsed == null) {
        setState(() => _errors = {'newSalary': 'Enter a valid amount'});
        return;
      }
      newSalary = parsed;
    }

    final errors = validateCompensationRequest(
      changeType: _changeType,
      currentSalary: current,
      newSalary: newSalary,
      currentWageType: _currentWageType,
      newWageType: _wageType,
      newScorecardId: _scorecardId,
      currentScorecardId: widget.currentCard?.id,
      effectiveDate: _effectiveDate,
      reason: _reasonCtrl.text.trim(),
      employee: widget.employee,
    );

    if (errors.isNotEmpty) {
      final byField = <String, String>{};
      for (final e in errors) {
        byField.putIfAbsent(e.field, () => e.message);
      }
      setState(() => _errors = byField);
      return;
    }

    Navigator.of(context).pop(
      CompensationChangeRequest(
        changeType: _changeType,
        newSalary: newSalary,
        newWageType: _wageType,
        newScorecardId: showsRoleDropdown(_changeType) ? _scorecardId : null,
        effectiveDate: _effectiveDate,
        reason: _reasonCtrl.text.trim(),
      ),
    );
  }

  void _onTypeChanged(String? next) {
    if (next == null) return;
    setState(() {
      _changeType = next;
      // Clear field errors when the shape of the form changes.
      _errors = const {};
    });
  }

  OutlineInputBorder get _fieldBorder =>
      OutlineInputBorder(borderRadius: BorderRadius.circular(LuxiumRadius.lg));

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dateStr = _effectiveDate.toIso8601String().substring(0, 10);
    // Errors that aren't bound to a rendered field (e.g. a missing current
    // salary) surface in a small banner so they aren't silently dropped.
    const boundFields = {
      'newSalary',
      'newRoleScorecardId',
      'reason',
      'effectiveDate',
    };
    final generalErrors = _errors.entries
        .where((e) => !boundFields.contains(e.key))
        .map((e) => e.value)
        .toList();

    return AlertDialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(LuxiumRadius.lg),
      ),
      title: const Text('Adjust Compensation / Change Role'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(widget.employee.fullName, style: theme.textTheme.titleSmall),
              const SizedBox(height: 4),
              Text(
                'Current: ${_currentSalary == Decimal.zero ? '—' : '₱$_currentSalary'} · ${_wageType.toLowerCase()}',
                style: AppTheme.mono(
                  context,
                  fontSize: 12,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                key: const Key('changeTypeDropdown'),
                initialValue: _changeType,
                decoration: InputDecoration(
                  labelText: 'Change type',
                  border: _fieldBorder,
                ),
                items: [
                  for (final t in kCompensationChangeTypes)
                    DropdownMenuItem(
                      value: t,
                      child: Text(compensationChangeTypeLabel(t)),
                    ),
                ],
                onChanged: _onTypeChanged,
              ),
              if (showsNewSalaryField(_changeType)) ...[
                const SizedBox(height: 12),
                TextFormField(
                  key: const Key('newSalaryField'),
                  controller: _salaryCtrl,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  style: AppTheme.mono(context),
                  decoration: InputDecoration(
                    labelText: 'New salary',
                    prefixText: '₱ ',
                    border: _fieldBorder,
                    errorText: _errors['newSalary'],
                  ),
                ),
              ],
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                key: const Key('wageTypeDropdown'),
                initialValue: _wageType,
                decoration: InputDecoration(
                  labelText: 'Wage type',
                  border: _fieldBorder,
                ),
                items: [
                  for (final w in kWageTypes)
                    DropdownMenuItem(
                      value: w,
                      child: Text(w[0] + w.substring(1).toLowerCase()),
                    ),
                ],
                onChanged: (v) => setState(() => _wageType = v ?? _wageType),
              ),
              if (showsRoleDropdown(_changeType)) ...[
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  key: const Key('roleDropdown'),
                  initialValue: _scorecardId,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: 'Target role',
                    border: _fieldBorder,
                    errorText: _errors['newRoleScorecardId'],
                  ),
                  items: [
                    for (final c in widget.allCards)
                      DropdownMenuItem(
                        value: c.id,
                        child: Text(
                          c.jobTitle,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: (v) => setState(() => _scorecardId = v),
                ),
              ],
              const SizedBox(height: 12),
              InkWell(
                onTap: _pickDate,
                borderRadius: BorderRadius.circular(LuxiumRadius.lg),
                child: InputDecorator(
                  decoration: InputDecoration(
                    labelText: 'Effective date',
                    border: _fieldBorder,
                    suffixIcon: const Icon(Icons.calendar_today, size: 18),
                    errorText: _errors['effectiveDate'],
                  ),
                  child: Text(dateStr, style: AppTheme.mono(context)),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                key: const Key('reasonField'),
                controller: _reasonCtrl,
                maxLines: 3,
                decoration: InputDecoration(
                  labelText: 'Reason',
                  hintText: 'e.g. Annual merit increase.',
                  border: _fieldBorder,
                  errorText: _errors['reason'],
                ),
              ),
              if (generalErrors.isNotEmpty) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(LuxiumRadius.lg),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final msg in generalErrors)
                        Text(
                          msg,
                          style: TextStyle(
                            fontSize: 12,
                            color: theme.colorScheme.onErrorContainer,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _confirm, child: const Text('Confirm')),
      ],
    );
  }
}
