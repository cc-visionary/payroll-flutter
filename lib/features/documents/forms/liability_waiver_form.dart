import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../inputs/company_picker.dart';
import '../inputs/date_field.dart';
import '../inputs/employee_picker.dart';
import '../providers.dart';
import '../templates/liability_waiver_inputs.dart';
import '../templates/liability_waiver_validate.dart';

class LiabilityWaiverForm extends ConsumerStatefulWidget {
  final LiabilityWaiverInputs initial;
  final bool employeeLocked;
  final ValueChanged<LiabilityWaiverInputs> onChanged;
  final ValueChanged<String> onEmployeeChanged;
  const LiabilityWaiverForm({
    super.key,
    required this.initial,
    required this.employeeLocked,
    required this.onChanged,
    required this.onEmployeeChanged,
  });

  @override
  ConsumerState<LiabilityWaiverForm> createState() =>
      _LiabilityWaiverFormState();
}

class _LiabilityWaiverFormState extends ConsumerState<LiabilityWaiverForm> {
  late LiabilityWaiverInputs _i = widget.initial;
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _set(LiabilityWaiverInputs next) {
    setState(() => _i = next);
    widget.onChanged(next);
  }

  Future<void> _onCompanyChanged(String id) async {
    // Optimistic: set the id immediately so the picker reflects the choice.
    _set(_i.copyWith(companyId: id));
    try {
      final co = await ref.read(hiringEntityByIdProvider(id).future);
      if (co == null || !mounted) return;
      final signingPlace = [co.city, co.province]
          .where((s) => s != null && s.isNotEmpty)
          .cast<String>()
          .join(', ');
      _set(_i.copyWith(
        companyName: co.name,
        signingPlace: signingPlace,
      ));
    } catch (_) {
      // Best-effort; leave companyId set, user can fill manually.
    }
  }

  String? _errFor(String field) {
    for (final e in validateLiabilityWaiver(_i)) {
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
                _set(_i.copyWith(employeeId: id));
                widget.onEmployeeChanged(id);
              }
            },
          ),
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
          _error('companyName'),
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
          _label('Date of Employment'),
          const SizedBox(height: 4),
          DateField(
            value: _i.dateOfEmployment,
            locked: false,
            onChanged: (d) => _set(_i.copyWith(dateOfEmployment: d)),
          ),
          _error('dateOfEmployment'),
          const SizedBox(height: 16),
          _label('Outing Date'),
          const SizedBox(height: 4),
          DateField(
            value: _i.outingDate,
            locked: false,
            onChanged: (d) => _set(_i.copyWith(outingDate: d)),
          ),
          _error('outingDate'),
          const SizedBox(height: 16),
          _label('Outing Location'),
          const SizedBox(height: 4),
          TextFormField(
            initialValue: _i.outingLocation,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              isDense: true,
            ),
            onChanged: (v) => _set(_i.copyWith(outingLocation: v)),
          ),
          _error('outingLocation'),
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
          const SizedBox(height: 16),
          _label('Signing Place (City, Province)'),
          const SizedBox(height: 4),
          TextFormField(
            initialValue: _i.signingPlace,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              isDense: true,
            ),
            onChanged: (v) => _set(_i.copyWith(signingPlace: v)),
          ),
          _error('signingPlace'),
        ],
      ),
    );
  }
}
