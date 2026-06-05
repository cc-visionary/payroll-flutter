import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../inputs/amount_with_breakdown.dart';
import '../inputs/company_picker.dart';
import '../inputs/date_field.dart';
import '../inputs/employee_picker.dart';
import '../providers.dart';
import '../templates/final_pay_inputs.dart';
import '../templates/final_pay_validate.dart';
import '../../../widgets/employee_name_field.dart';

class FinalPayForm extends ConsumerStatefulWidget {
  final FinalPayInputs initial;
  final bool employeeLocked;
  final ValueChanged<FinalPayInputs> onChanged;
  final ValueChanged<String> onEmployeeChanged;
  const FinalPayForm({
    super.key,
    required this.initial,
    required this.employeeLocked,
    required this.onChanged,
    required this.onEmployeeChanged,
  });

  @override
  ConsumerState<FinalPayForm> createState() => _FinalPayFormState();
}

class _FinalPayFormState extends ConsumerState<FinalPayForm> {
  late FinalPayInputs _i = widget.initial;
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant FinalPayForm oldWidget) {
    super.didUpdateWidget(oldWidget);
    // When the parent ships a new `initial` (e.g. async autofill arrived
    // after the employee was picked), adopt it locally so the form
    // reflects the freshly-computed values.
    if (!identical(oldWidget.initial, widget.initial)) {
      _i = widget.initial;
    }
  }

  void _set(FinalPayInputs next) {
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
    for (final e in validateFinalPay(_i)) {
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
    final breakdown = _i.employeeId.isEmpty
        ? null
        : ref.watch(finalPayBreakdownProvider(_i.employeeId)).asData?.value;
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
          const SizedBox(height: 24),
          const Divider(),
          const SizedBox(height: 8),
          Text('Computation', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 16),
          _label('Last net pay'),
          const SizedBox(height: 4),
          AmountWithBreakdown(
            value: _i.lastNetPay,
            breakdown: breakdown,
            locked: _i.lastNetPayLocked,
            onChanged: (d) =>
                _set(_i.copyWith(lastNetPay: d, lastNetPayLocked: true)),
          ),
          _error('lastNetPay'),
          const SizedBox(height: 16),
          _label('13th-month pay'),
          const SizedBox(height: 4),
          AmountWithBreakdown(
            value: _i.thirteenthMonth,
            breakdown: breakdown,
            locked: _i.thirteenthMonthLocked,
            onChanged: (d) => _set(
              _i.copyWith(thirteenthMonth: d, thirteenthMonthLocked: true),
            ),
          ),
          _error('thirteenthMonth'),
          const SizedBox(height: 16),
          _label('Unused leave conversion'),
          const SizedBox(height: 4),
          AmountWithBreakdown(
            value: _i.unusedLeaveConversion,
            breakdown: breakdown,
            locked: _i.unusedLeaveConversionLocked,
            onChanged: (d) => _set(
              _i.copyWith(
                unusedLeaveConversion: d,
                unusedLeaveConversionLocked: true,
              ),
            ),
          ),
          _error('unusedLeaveConversion'),
          const SizedBox(height: 16),
          _label('Outstanding cash advance'),
          const SizedBox(height: 4),
          AmountWithBreakdown(
            value: _i.outstandingCashAdvance,
            breakdown: breakdown,
            locked: _i.outstandingCashAdvanceLocked,
            onChanged: (d) => _set(
              _i.copyWith(
                outstandingCashAdvance: d,
                outstandingCashAdvanceLocked: true,
              ),
            ),
          ),
          _error('outstandingCashAdvance'),
          const SizedBox(height: 16),
          _label('Other deduction label (optional)'),
          const SizedBox(height: 4),
          TextFormField(
            initialValue: _i.otherDeductionsLabel,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              isDense: true,
              labelText: 'Other deduction label (optional)',
            ),
            onChanged: (v) => _set(_i.copyWith(otherDeductionsLabel: v)),
          ),
          const SizedBox(height: 16),
          _label('Other deductions'),
          const SizedBox(height: 4),
          AmountWithBreakdown(
            value: _i.otherDeductions,
            breakdown: null,
            locked: false,
            onChanged: (d) => _set(_i.copyWith(otherDeductions: d)),
          ),
          _error('otherDeductions'),
          const SizedBox(height: 24),
          const Divider(),
          const SizedBox(height: 16),
          _label('Computed as of'),
          const SizedBox(height: 4),
          DateField(
            value: _i.computedAsOf,
            locked: false,
            onChanged: (d) {
              if (d != null) _set(_i.copyWith(computedAsOf: d));
            },
          ),
          const SizedBox(height: 16),
          _label('Release date'),
          const SizedBox(height: 4),
          DateField(
            value: _i.releaseDate,
            locked: false,
            onChanged: (d) {
              if (d != null) _set(_i.copyWith(releaseDate: d));
            },
          ),
          _error('releaseDate'),
        ],
      ),
    );
  }
}
