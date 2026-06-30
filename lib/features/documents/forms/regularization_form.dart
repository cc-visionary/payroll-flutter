import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../widgets/employee_name_field.dart';
import '../inputs/company_picker.dart';
import '../inputs/date_field.dart';
import '../inputs/employee_picker.dart';
import '../templates/regularization_inputs.dart';
import '../templates/regularization_validate.dart';

class RegularizationForm extends ConsumerStatefulWidget {
  final RegularizationInputs initial;
  final bool employeeLocked;
  final ValueChanged<RegularizationInputs> onChanged;
  final ValueChanged<String> onEmployeeChanged;
  final ValueChanged<String> onCompanyChanged;
  const RegularizationForm({
    super.key,
    required this.initial,
    required this.employeeLocked,
    required this.onChanged,
    required this.onEmployeeChanged,
    required this.onCompanyChanged,
  });

  @override
  ConsumerState<RegularizationForm> createState() => _RegularizationFormState();
}

class _RegularizationFormState extends ConsumerState<RegularizationForm> {
  late RegularizationInputs _i = widget.initial;
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant RegularizationForm oldWidget) {
    super.didUpdateWidget(oldWidget);
    // When the parent ships a new `initial` (e.g. async autofill arrived
    // after the employee was picked), adopt it locally so the form
    // reflects the freshly-computed values.
    if (!identical(oldWidget.initial, widget.initial)) {
      _i = widget.initial;
    }
  }

  void _set(RegularizationInputs next) {
    setState(() => _i = next);
    widget.onChanged(next);
  }

  String? _errFor(String field) {
    for (final e in validateRegularization(_i)) {
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
          _error('hrManager'),
          const SizedBox(height: 16),
          _label('Regularization date'),
          const SizedBox(height: 4),
          DateField(
            value: _i.regularizationDate,
            locked: false,
            onChanged: (d) {
              if (d != null) _set(_i.copyWith(regularizationDate: d));
            },
          ),
          _error('regularizationDate'),
          const SizedBox(height: 16),
          _label('Base salary'),
          const SizedBox(height: 4),
          TextFormField(
            key: ValueKey('salary-${_i.employeeId}'),
            initialValue: _i.baseSalary.toString(),
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
              _i.copyWith(baseSalary: Decimal.tryParse(v) ?? Decimal.zero),
            ),
          ),
          _error('baseSalary'),
          const SizedBox(height: 16),
          _label('Performance summary (optional)'),
          const SizedBox(height: 4),
          TextFormField(
            initialValue: _i.performanceSummary,
            minLines: 3,
            maxLines: 8,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              labelText: 'Performance summary (optional)',
              helperText:
                  'Pulled from 5-month probationary check-in, or paste manually.',
            ),
            onChanged: (v) => _set(_i.copyWith(performanceSummary: v)),
          ),
        ],
      ),
    );
  }
}
