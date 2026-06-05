import 'package:collection/collection.dart';
import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/repositories/role_scorecard_repository.dart';
import '../../../widgets/employee_name_field.dart';
import '../inputs/company_picker.dart';
import '../inputs/date_field.dart';
import '../inputs/employee_picker.dart';
import '../providers.dart';
import '../templates/salary_adjustment_inputs.dart';
import '../templates/salary_adjustment_validate.dart';

class SalaryAdjustmentForm extends ConsumerStatefulWidget {
  final SalaryAdjustmentInputs initial;
  final bool employeeLocked;
  final ValueChanged<SalaryAdjustmentInputs> onChanged;
  final ValueChanged<String> onEmployeeChanged;
  const SalaryAdjustmentForm({
    super.key,
    required this.initial,
    required this.employeeLocked,
    required this.onChanged,
    required this.onEmployeeChanged,
  });

  @override
  ConsumerState<SalaryAdjustmentForm> createState() =>
      _SalaryAdjustmentFormState();
}

class _SalaryAdjustmentFormState extends ConsumerState<SalaryAdjustmentForm> {
  late SalaryAdjustmentInputs _i = widget.initial;
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant SalaryAdjustmentForm oldWidget) {
    super.didUpdateWidget(oldWidget);
    // When the parent ships a new `initial` (e.g. async autofill arrived
    // after the employee was picked), adopt it locally so the form
    // reflects the freshly-computed values.
    if (!identical(oldWidget.initial, widget.initial)) {
      _i = widget.initial;
    }
  }

  void _set(SalaryAdjustmentInputs next) {
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
    for (final e in validateSalaryAdjustment(_i)) {
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
    final isPromotion = _i.type == SalaryAdjustmentType.promotion;
    return Scrollbar(
      controller: _scrollController,
      child: ListView(
        controller: _scrollController,
        primary: false,
        padding: const EdgeInsets.all(16),
        children: [
          _label('Type'),
          const SizedBox(height: 4),
          SegmentedButton<SalaryAdjustmentType>(
            segments: const [
              ButtonSegment(
                value: SalaryAdjustmentType.salaryAdjustment,
                label: Text('Salary Adjustment'),
              ),
              ButtonSegment(
                value: SalaryAdjustmentType.promotion,
                label: Text('Promotion'),
              ),
            ],
            selected: {_i.type},
            onSelectionChanged: (s) => _set(_i.copyWith(type: s.first)),
          ),
          const SizedBox(height: 16),
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
          if (isPromotion) ...[
            const SizedBox(height: 24),
            const Divider(),
            const SizedBox(height: 8),
            Text('Promotion', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 16),
            _label('Target role'),
            const SizedBox(height: 4),
            _buildTargetRoleDropdown(),
            _error('newRoleScorecardId'),
          ],
          const SizedBox(height: 24),
          const Divider(),
          const SizedBox(height: 8),
          Text('Salary', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 16),
          _label('Current salary'),
          const SizedBox(height: 4),
          TextFormField(
            key: ValueKey('old-${_i.employeeId}'),
            initialValue: _i.oldSalary.toString(),
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              isDense: true,
              prefixText: '₱ ',
            ),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
            ],
            onChanged: (v) => _set(
              _i.copyWith(oldSalary: Decimal.tryParse(v) ?? Decimal.zero),
            ),
          ),
          _error('oldSalary'),
          const SizedBox(height: 16),
          _label('New salary'),
          const SizedBox(height: 4),
          TextFormField(
            key: ValueKey(
              'new-${_i.employeeId}-${_i.newRoleScorecardId ?? ""}',
            ),
            initialValue: _i.newSalary.toString(),
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              isDense: true,
              prefixText: '₱ ',
            ),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
            ],
            onChanged: (v) => _set(
              _i.copyWith(newSalary: Decimal.tryParse(v) ?? Decimal.zero),
            ),
          ),
          _error('newSalary'),
          const SizedBox(height: 24),
          const Divider(),
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
          _label('Reason'),
          const SizedBox(height: 4),
          TextFormField(
            initialValue: _i.reason,
            minLines: 3,
            maxLines: 8,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              labelText: 'Reason / context (shown in letter body)',
            ),
            onChanged: (v) => _set(_i.copyWith(reason: v)),
          ),
          _error('reason'),
        ],
      ),
    );
  }

  Widget _buildTargetRoleDropdown() {
    final async = ref.watch(roleScorecardListProvider);
    return async.when(
      loading: () => const InputDecorator(
        decoration: InputDecoration(
          labelText: 'Target role',
          border: OutlineInputBorder(),
          isDense: true,
        ),
        child: Text('Loading…'),
      ),
      error: (e, _) => InputDecorator(
        decoration: const InputDecoration(
          labelText: 'Target role',
          border: OutlineInputBorder(),
          isDense: true,
        ),
        child: Text('Error: $e', style: const TextStyle(color: Colors.red)),
      ),
      data: (cards) {
        final filtered = cards
            .where((c) => c.id != (_i.oldRoleScorecardId ?? ''))
            .toList();
        final activeIds = filtered.map((c) => c.id).toSet();
        final currentValue =
            _i.newRoleScorecardId != null &&
                activeIds.contains(_i.newRoleScorecardId)
            ? _i.newRoleScorecardId
            : null;
        return DropdownButtonFormField<String>(
          initialValue: currentValue,
          decoration: const InputDecoration(
            labelText: 'Target role',
            border: OutlineInputBorder(),
            isDense: true,
          ),
          items: filtered
              .map(
                (c) => DropdownMenuItem<String>(
                  value: c.id,
                  child: Text(c.jobTitle),
                ),
              )
              .toList(),
          onChanged: (id) {
            if (id == null) return;
            final sc = filtered.firstWhereOrNull((s) => s.id == id);
            if (sc == null) return;
            _set(
              _i.copyWith(
                newRoleScorecardId: id,
                newPosition: sc.jobTitle,
                newSalary: sc.baseSalary ?? _i.newSalary,
              ),
            );
          },
        );
      },
    );
  }
}
