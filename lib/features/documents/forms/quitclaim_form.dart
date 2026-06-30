import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../inputs/amount_with_breakdown.dart';
import '../inputs/company_picker.dart';
import '../inputs/date_field.dart';
import '../inputs/employee_picker.dart';
import '../providers.dart';
import '../templates/quitclaim_inputs.dart';
import '../templates/quitclaim_validate.dart';

class QuitclaimForm extends ConsumerStatefulWidget {
  final QuitclaimInputs initial;
  final bool employeeLocked;
  final ValueChanged<QuitclaimInputs> onChanged;
  final ValueChanged<String> onEmployeeChanged;
  final ValueChanged<String> onCompanyChanged;
  const QuitclaimForm({
    super.key,
    required this.initial,
    required this.employeeLocked,
    required this.onChanged,
    required this.onEmployeeChanged,
    required this.onCompanyChanged,
  });

  @override
  ConsumerState<QuitclaimForm> createState() => _QuitclaimFormState();
}

class _QuitclaimFormState extends ConsumerState<QuitclaimForm> {
  late QuitclaimInputs _i = widget.initial;
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant QuitclaimForm oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.initial, widget.initial)) {
      _i = widget.initial;
    }
  }

  void _set(QuitclaimInputs next) {
    setState(() => _i = next);
    widget.onChanged(next);
  }

  String? _errFor(String field) {
    for (final e in validateQuitclaim(_i)) {
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
          _error('employee'),
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
          _label('Employee Address'),
          const SizedBox(height: 4),
          TextFormField(
            initialValue: _i.employeeAddress,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              isDense: true,
            ),
            onChanged: (v) => _set(_i.copyWith(employeeAddress: v)),
          ),
          _error('employeeAddress'),
          const SizedBox(height: 16),
          _label('Civil Status'),
          const SizedBox(height: 4),
          TextFormField(
            initialValue: _i.civilStatus,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              isDense: true,
              hintText: 'e.g. single, married',
            ),
            onChanged: (v) => _set(_i.copyWith(civilStatus: v)),
          ),
          _error('civilStatus'),
          const SizedBox(height: 16),
          _label('Final Pay Amount'),
          const SizedBox(height: 4),
          AmountWithBreakdown(
            value: _i.finalPayAmount,
            breakdown: breakdown,
            locked: false,
            onChanged: (d) => _set(_i.copyWith(finalPayAmount: d)),
          ),
          _error('finalPayAmount'),
          const SizedBox(height: 16),
          _label('Date Terminated'),
          const SizedBox(height: 4),
          DateField(
            value: _i.dateTerminated,
            locked: false,
            onChanged: (d) => _set(_i.copyWith(dateTerminated: d)),
          ),
          const SizedBox(height: 16),
          _label('Date Signed'),
          const SizedBox(height: 4),
          DateField(
            value: _i.dateSigned,
            locked: false,
            onChanged: (d) {
              if (d != null) _set(_i.copyWith(dateSigned: d));
            },
          ),
          _error('dateSigned'),
          const SizedBox(height: 16),
          _label('Place Signed'),
          const SizedBox(height: 4),
          TextFormField(
            initialValue: _i.placeSigned,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              isDense: true,
            ),
            onChanged: (v) => _set(_i.copyWith(placeSigned: v)),
          ),
          _error('placeSigned'),
        ],
      ),
    );
  }
}
