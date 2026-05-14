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
  const QuitclaimForm({
    super.key,
    required this.initial,
    required this.employeeLocked,
    required this.onChanged,
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
          const Text('Employee', style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        EmployeePicker(
          selectedId: _i.employeeId.isEmpty ? null : _i.employeeId,
          locked: widget.employeeLocked,
          onChanged: (id) {
            if (id != null) _set(_i.copyWith(employeeId: id));
          },
        ),
        if (_errFor('employee') != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              _errFor('employee')!,
              style: const TextStyle(color: Colors.red, fontSize: 12),
            ),
          ),
        const SizedBox(height: 16),
        const Text('Company', style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        CompanyPicker(
          selectedId: _i.companyId.isEmpty ? null : _i.companyId,
          locked: false,
          onChanged: (id) {
            if (id != null) _set(_i.copyWith(companyId: id));
          },
        ),
        const SizedBox(height: 16),
        const Text(
          'Date Terminated',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 4),
        DateField(
          value: _i.dateTerminated,
          locked: false,
          onChanged: (d) => _set(_i.copyWith(dateTerminated: d)),
        ),
        const SizedBox(height: 16),
        const Text(
          'Date Signed',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 4),
        DateField(
          value: _i.dateSigned,
          locked: false,
          onChanged: (d) {
            if (d != null) _set(_i.copyWith(dateSigned: d));
          },
        ),
        const SizedBox(height: 16),
        const Text(
          'Final Pay Amount',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 4),
        AmountWithBreakdown(
          value: _i.finalPayAmount,
          breakdown: breakdown,
          locked: false,
          onChanged: (d) => _set(_i.copyWith(finalPayAmount: d)),
        ),
        const SizedBox(height: 16),
        if (_i.companySignatoryName == null ||
            _i.companySignatoryName!.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 4),
            child: Text(
              'Set a signatory in Settings → Hiring Entities to skip this next time.',
              style: TextStyle(color: Colors.orange, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}
