import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../inputs/amount_with_breakdown.dart';
import '../inputs/company_picker.dart';
import '../inputs/date_field.dart';
import '../inputs/employee_picker.dart';
import '../templates/penalty_agreement_inputs.dart';
import '../templates/penalty_agreement_validate.dart';
import '../../../widgets/employee_name_field.dart';

class PenaltyAgreementForm extends ConsumerStatefulWidget {
  final PenaltyAgreementInputs initial;
  final bool employeeLocked;
  final ValueChanged<PenaltyAgreementInputs> onChanged;
  final ValueChanged<String> onEmployeeChanged;
  final ValueChanged<String> onCompanyChanged;
  const PenaltyAgreementForm({
    super.key,
    required this.initial,
    required this.employeeLocked,
    required this.onChanged,
    required this.onEmployeeChanged,
    required this.onCompanyChanged,
  });

  @override
  ConsumerState<PenaltyAgreementForm> createState() =>
      _PenaltyAgreementFormState();
}

class _PenaltyAgreementFormState extends ConsumerState<PenaltyAgreementForm> {
  late PenaltyAgreementInputs _i = widget.initial;
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant PenaltyAgreementForm oldWidget) {
    super.didUpdateWidget(oldWidget);
    // When the parent ships a new `initial` (e.g. async autofill arrived
    // after the employee was picked), adopt it locally so the form
    // reflects the freshly-loaded penalty.
    if (!identical(oldWidget.initial, widget.initial)) {
      _i = widget.initial;
    }
  }

  void _set(PenaltyAgreementInputs next) {
    setState(() => _i = next);
    widget.onChanged(next);
  }

  String? _errFor(String field) {
    for (final e in validatePenaltyAgreement(_i)) {
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
    final money = NumberFormat.currency(symbol: '₱', decimalDigits: 2);
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
              if (id == null) return;
              _set(_i.copyWith(companyId: id));
              widget.onCompanyChanged(id);
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
          const SizedBox(height: 24),
          const Divider(),
          const SizedBox(height: 8),
          Text('Penalty', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 16),
          _label('Incident description'),
          const SizedBox(height: 4),
          TextFormField(
            initialValue: _i.description,
            minLines: 2,
            maxLines: 5,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              isDense: true,
              labelText: 'What the penalty is for',
            ),
            onChanged: (v) => _set(_i.copyWith(description: v)),
          ),
          _error('description'),
          const SizedBox(height: 16),
          _label('Total amount'),
          const SizedBox(height: 4),
          AmountWithBreakdown(
            value: _i.totalAmount,
            breakdown: null,
            locked: false,
            onChanged: (d) => _set(_i.copyWith(totalAmount: d)),
          ),
          _error('totalAmount'),
          const SizedBox(height: 16),
          _label('Effective date'),
          const SizedBox(height: 4),
          DateField(
            value: _i.effectiveDate,
            locked: false,
            onChanged: (d) {
              if (d != null) _set(_i.copyWith(effectiveDate: d));
            },
          ),
          const SizedBox(height: 16),
          _label('Remarks (optional)'),
          const SizedBox(height: 4),
          TextFormField(
            initialValue: _i.remarks ?? '',
            minLines: 1,
            maxLines: 4,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              isDense: true,
              labelText: 'Remarks (optional)',
            ),
            onChanged: (v) => _set(_i.copyWith(remarks: v)),
          ),
          const SizedBox(height: 24),
          const Divider(),
          const SizedBox(height: 8),
          Text(
            'Repayment schedule',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          Text(
            'Read-only — the schedule comes from the penalty record. Edit it '
            'on the employee’s Financials tab.',
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          if (_i.installments.isEmpty)
            Text(
              'No installments on this penalty.',
              style: TextStyle(
                fontSize: 13,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            )
          else
            for (final l in _i.installments)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    SizedBox(
                      width: 40,
                      child: Text(
                        '${l.number}.',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    Expanded(child: Text(money.format(l.amount.toDouble()))),
                    Text(
                      l.isDeducted ? 'Deducted' : 'Scheduled',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
          _error('installments'),
        ],
      ),
    );
  }
}
