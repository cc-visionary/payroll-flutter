import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../widgets/employee_name_field.dart';
import '../inputs/company_picker.dart';
import '../inputs/image_attachment_field.dart';
import '../inputs/date_field.dart';
import '../inputs/employee_picker.dart';
import '../providers.dart';
import '../templates/nod_inputs.dart';
import '../templates/nod_validate.dart';

class NodForm extends ConsumerStatefulWidget {
  final NodInputs initial;
  final bool employeeLocked;
  final ValueChanged<NodInputs> onChanged;
  final ValueChanged<String> onEmployeeChanged;
  final ValueChanged<String> onCompanyChanged;
  const NodForm({
    super.key,
    required this.initial,
    required this.employeeLocked,
    required this.onChanged,
    required this.onEmployeeChanged,
    required this.onCompanyChanged,
  });

  @override
  ConsumerState<NodForm> createState() => _NodFormState();
}

class _NodFormState extends ConsumerState<NodForm> {
  late NodInputs _i = widget.initial;
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant NodForm oldWidget) {
    super.didUpdateWidget(oldWidget);
    // When the parent ships a new `initial` (e.g. async autofill arrived
    // after the employee was picked), adopt it locally so the form
    // reflects the freshly-computed values.
    if (!identical(oldWidget.initial, widget.initial)) {
      _i = widget.initial;
    }
  }

  void _set(NodInputs next) {
    setState(() => _i = next);
    widget.onChanged(next);
  }

  String? _errFor(String field) {
    for (final e in validateNod(_i)) {
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
    final ntesAsync = _i.employeeId.isEmpty
        ? const AsyncValue<List<EmployeeDocumentSummary>>.data([])
        : ref.watch(ntesByEmployeeProvider(_i.employeeId));
    final df = DateFormat('MMM d, yyyy');

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
                // Clear linked NTE since it changes per employee, then
                // notify parent so async autofill can run.
                _set(
                  _i.copyWith(
                    employeeId: id,
                    linkedNteDocumentId: null,
                    nteDate: null,
                  ),
                );
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
          _label('Link to NTE (optional)'),
          const SizedBox(height: 4),
          ntesAsync.when(
            loading: () => const LinearProgressIndicator(),
            error: (_, _) => const SizedBox.shrink(),
            data: (ntes) => DropdownButtonFormField<String?>(
              initialValue: _i.linkedNteDocumentId,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'Link to NTE (optional)',
                isDense: true,
              ),
              items: [
                const DropdownMenuItem<String?>(
                  value: null,
                  child: Text('— No NTE linked —'),
                ),
                ...ntes.map(
                  (n) => DropdownMenuItem<String?>(
                    value: n.id,
                    child: Text('${df.format(n.createdAt)} — ${n.title}'),
                  ),
                ),
              ],
              onChanged: (id) {
                EmployeeDocumentSummary? match;
                for (final n in ntes) {
                  if (n.id == id) {
                    match = n;
                    break;
                  }
                }
                _set(
                  _i.copyWith(
                    linkedNteDocumentId: id,
                    nteDate: match?.createdAt,
                    charges: _i.charges.isEmpty && match != null
                        ? match.title
                        : _i.charges,
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 16),
          _label('Charges'),
          const SizedBox(height: 4),
          TextFormField(
            key: ValueKey('charges-${_i.linkedNteDocumentId}'),
            initialValue: _i.charges,
            minLines: 3,
            maxLines: 10,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              labelText: 'Charges',
            ),
            onChanged: (v) => _set(_i.copyWith(charges: v)),
          ),
          _error('charges'),
          const SizedBox(height: 16),
          _label('Employee Response (summary)'),
          const SizedBox(height: 4),
          TextFormField(
            initialValue: _i.employeeResponseSummary,
            minLines: 3,
            maxLines: 10,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              labelText: 'Employee Response (summary)',
            ),
            onChanged: (v) => _set(_i.copyWith(employeeResponseSummary: v)),
          ),
          _error('employeeResponseSummary'),
          const SizedBox(height: 16),
          _label('Findings'),
          const SizedBox(height: 4),
          TextFormField(
            initialValue: _i.findings,
            minLines: 3,
            maxLines: 10,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              labelText: 'Findings',
            ),
            onChanged: (v) => _set(_i.copyWith(findings: v)),
          ),
          _error('findings'),
          const SizedBox(height: 16),
          _label('Decision'),
          const SizedBox(height: 4),
          DropdownButtonFormField<NodDecision>(
            initialValue: _i.decision,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              labelText: 'Decision',
              isDense: true,
            ),
            items: NodDecision.values
                .map((d) => DropdownMenuItem(value: d, child: Text(d.label)))
                .toList(),
            onChanged: (d) => _set(_i.copyWith(decision: d ?? _i.decision)),
          ),
          if (_i.decision == NodDecision.suspension) ...[
            const SizedBox(height: 16),
            _label('Suspension days'),
            const SizedBox(height: 4),
            TextFormField(
              key: ValueKey('days-${_i.decision}'),
              initialValue: _i.suspensionDays.toString(),
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'Suspension days',
                isDense: true,
              ),
              keyboardType: TextInputType.number,
              onChanged: (v) =>
                  _set(_i.copyWith(suspensionDays: int.tryParse(v) ?? 0)),
            ),
            _error('suspensionDays'),
          ],
          const SizedBox(height: 16),
          _label('Issue date'),
          const SizedBox(height: 4),
          DateField(
            value: _i.issueDate,
            locked: false,
            onChanged: (d) {
              if (d != null) _set(_i.copyWith(issueDate: d));
            },
          ),
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
          _error('effectiveDate'),
          const SizedBox(height: 16),
          _label('Attachment (optional)'),
          const SizedBox(height: 4),
          ImageAttachmentField(
            bytes: _i.attachmentBytes,
            caption: _i.attachmentCaption,
            onPicked: (bytes, _) => _set(_i.copyWith(attachmentBytes: bytes)),
            onRemoved: () => _set(
              _i.copyWith(attachmentBytes: null, attachmentCaption: null),
            ),
            onCaptionChanged: (v) =>
                _set(_i.copyWith(attachmentCaption: v.isEmpty ? null : v)),
          ),
        ],
      ),
    );
  }
}
