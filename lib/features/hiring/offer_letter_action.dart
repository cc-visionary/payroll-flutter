import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';

import '../../core/pdf/pdf_preview_scaffold.dart';
import '../../core/pdf/pdf_theme.dart';
import '../../data/models/applicant.dart';
import '../../data/models/hiring_entity.dart';
import '../../data/models/role_scorecard.dart';
import '../../data/repositories/department_repository.dart';
import '../documents/brand_logo.dart';
import '../documents/pdf/pdf_builder.dart';
import '../documents/providers.dart';
import '../documents/signatory_autofill.dart';
import 'offer_letter_template.dart';

/// Autofills [OfferLetterInputs] from the applicant, their role scorecard,
/// department and hiring entity, plus the HR signatory. Every lookup is
/// best-effort: a missing record leaves its field blank rather than failing.
Future<OfferLetterInputs> autofillOfferLetter({
  required Applicant applicant,
  required WidgetRef ref,
}) async {
  Future<T?> tryRead<T>(Future<T?> Function() f) async {
    try {
      return await f();
    } catch (_) {
      return null;
    }
  }

  final scorecardId = applicant.roleScorecardId;
  final RoleScorecard? scorecard = scorecardId == null
      ? null
      : await tryRead(
          () => ref.read(roleScorecardByIdProvider(scorecardId).future),
        );
  final entityId = applicant.hiringEntityId ?? scorecard?.hiringEntityId;
  final HiringEntity? entity = entityId == null
      ? null
      : await tryRead(
          () => ref.read(hiringEntityByIdProvider(entityId).future),
        );
  final departmentId = applicant.departmentId ?? scorecard?.departmentId;
  final departments =
      await tryRead(() => ref.read(departmentListProvider.future)) ?? const [];
  final department = departmentId == null
      ? null
      : departments.where((d) => d.id == departmentId).firstOrNull;
  final sigs = await loadAutofillSignatories(ref);
  final logo = await loadCompanyLogoBytes(entity);

  final brand = (entity?.tradeName?.isNotEmpty ?? false)
      ? entity!.tradeName!
      : entity?.name ?? '';
  final office = [
    entity?.addressLine1,
    entity?.addressLine2,
    entity?.city,
  ].where((s) => s != null && s.isNotEmpty).join(', ');
  final salary =
      scorecard?.baseSalary?.toDouble() ??
      applicant.expectedSalaryMax?.toDouble();

  return OfferLetterInputs(
    dateIssued: DateTime.now(),
    applicantFullName: applicant.fullName,
    salutationName: applicant.lastName,
    position: scorecard?.jobTitle ?? '',
    brandName: brand,
    basicSalary: formatOfferSalary(salary, scorecard?.wageType),
    department: department?.name ?? '',
    reportingTo: '',
    reportingOffice: office,
    officeHours: defaultOfficeHours(
      hoursPerDay: scorecard?.workHoursPerDay ?? 8,
      days: scorecard?.workDaysPerWeek ?? 'Monday to Saturday',
    ),
    contactNumber: entity?.phoneNumber ?? '',
    targetStartDate: applicant.expectedStartDate,
    signatoryName: sigs.hr?.name ?? entity?.hrManagerName ?? '',
    signatoryTitle: (sigs.hr?.title?.isNotEmpty ?? false)
        ? sigs.hr!.title!
        : 'People Manager',
    signaturePngB64: sigs.hr?.signaturePngB64,
    logoBytes: logo,
  );
}

/// Renders the offer letter to PDF bytes. Pure — no UI side effects.
Future<Uint8List> renderOfferLetter(OfferLetterInputs inputs) async {
  final theme = await PdfTheme.defaults();
  return buildDocumentPdf(
    blocks: buildOfferLetterBlocks(inputs),
    theme: theme,
  );
}

/// Autofills the offer letter, lets HR confirm the per-offer fields
/// (reporting line, deadline, start date…), then pushes a full-screen PDF
/// preview with Download / Print actions.
Future<void> showOfferLetterPreview(
  BuildContext context, {
  required Applicant applicant,
  required WidgetRef ref,
}) async {
  final autofilled = await autofillOfferLetter(applicant: applicant, ref: ref);
  if (!context.mounted) return;
  final inputs = await showDialog<OfferLetterInputs>(
    context: context,
    builder: (_) => _OfferLetterDetailsDialog(initial: autofilled),
  );
  if (inputs == null || !context.mounted) return;

  final ymd = DateFormat('yyyyMMdd').format(DateTime.now());
  final safeName = applicant.fullName.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '-');
  final filename = '${ymd}_OfferLetter_$safeName.pdf';

  await Navigator.of(context).push<void>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => Scaffold(
        appBar: AppBar(title: const Text('Offer Letter Preview')),
        body: PdfPreviewScaffold(
          filename: filename,
          enabled: true,
          buildPdf: (PdfPageFormat _) => renderOfferLetter(inputs),
        ),
      ),
    ),
  );
}

class _OfferLetterDetailsDialog extends StatefulWidget {
  final OfferLetterInputs initial;
  const _OfferLetterDetailsDialog({required this.initial});

  @override
  State<_OfferLetterDetailsDialog> createState() =>
      _OfferLetterDetailsDialogState();
}

class _OfferLetterDetailsDialogState extends State<_OfferLetterDetailsDialog> {
  late final _reportingTo = TextEditingController(
    text: widget.initial.reportingTo,
  );
  late final _officeHours = TextEditingController(
    text: widget.initial.officeHours,
  );
  late final _contact = TextEditingController(
    text: widget.initial.contactNumber,
  );
  late DateTime _dateIssued = widget.initial.dateIssued;
  late DateTime? _deadline = widget.initial.requirementsDeadline;
  late DateTime? _startDate = widget.initial.targetStartDate;

  @override
  void dispose() {
    _reportingTo.dispose();
    _officeHours.dispose();
    _contact.dispose();
    super.dispose();
  }

  Future<DateTime?> _pick(DateTime? current) => showDatePicker(
    context: context,
    initialDate: current ?? DateTime.now(),
    firstDate: DateTime(2020),
    lastDate: DateTime(2100),
  );

  Widget _dateField(String label, DateTime? value, ValueChanged<DateTime> set) {
    return InkWell(
      onTap: () async {
        final d = await _pick(value);
        if (d != null) setState(() => set(d));
      },
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          suffixIcon: const Icon(Icons.calendar_today_outlined, size: 18),
        ),
        child: Text(
          value == null ? 'Not set' : DateFormat('MMMM d, yyyy').format(value),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Offer letter details'),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _dateField(
                'Letter date',
                _dateIssued,
                (d) => _dateIssued = d,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _reportingTo,
                decoration: const InputDecoration(
                  labelText: 'Reporting to',
                  hintText: 'e.g. Retail Manager',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _officeHours,
                decoration: const InputDecoration(labelText: 'Office hours'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _contact,
                decoration: const InputDecoration(
                  labelText: 'Contact number for concerns',
                ),
              ),
              const SizedBox(height: 12),
              _dateField(
                'Submit requirements on or before',
                _deadline,
                (d) => _deadline = d,
              ),
              const SizedBox(height: 12),
              _dateField('Target start date', _startDate, (d) => _startDate = d),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(
            widget.initial.copyWith(
              dateIssued: _dateIssued,
              reportingTo: _reportingTo.text.trim(),
              officeHours: _officeHours.text.trim(),
              contactNumber: _contact.text.trim(),
              requirementsDeadline: _deadline,
              targetStartDate: _startDate,
            ),
          ),
          child: const Text('Preview'),
        ),
      ],
    );
  }
}
