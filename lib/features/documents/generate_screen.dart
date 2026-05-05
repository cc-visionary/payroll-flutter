import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pdf/pdf.dart';

import '../../core/pdf/pdf_filename.dart';
import '../../core/pdf/pdf_preview_scaffold.dart';
import '../../core/pdf/pdf_theme.dart';
import 'forms/coe_form.dart';
import 'forms/nte_form.dart';
import 'forms/quitclaim_form.dart';
import 'pdf/pdf_builder.dart';
import 'providers.dart';
import 'templates/coe_inputs.dart';
import 'templates/coe_template.dart';
import 'templates/document_template.dart';
import 'templates/nte_inputs.dart';
import 'templates/nte_template.dart';
import 'templates/quitclaim_inputs.dart';
import 'templates/quitclaim_template.dart';
import 'templates/template_registry.dart';

class GenerateScreen extends ConsumerStatefulWidget {
  final String templateId;
  final String? employeeId;
  const GenerateScreen({
    super.key,
    required this.templateId,
    this.employeeId,
  });

  @override
  ConsumerState<GenerateScreen> createState() => _GenerateScreenState();
}

class _GenerateScreenState extends ConsumerState<GenerateScreen> {
  QuitclaimInputs? _quitclaim;
  CoeInputs? _coe;
  NteInputs? _nte;
  bool _autofillDone = false;
  String? _autofillError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _runAutofill());
  }

  Future<void> _runAutofill() async {
    final tpl = findTemplateById(widget.templateId);
    final eId = widget.employeeId;

    // Pre-warm the font theme so any cold-start failure surfaces here
    // rather than as an unhelpful preview build error.
    try {
      await PdfTheme.defaults();
    } catch (_) {
      setState(() {
        _autofillError =
            'Font download failed — connect to the internet once to enable PDF generation.';
        _autofillDone = true;
      });
      return;
    }

    if (tpl is CoeTemplate) {
      if (eId == null) {
        setState(() {
          _coe = tpl.emptyInputs();
          _autofillDone = true;
        });
        return;
      }
      final emp = await ref.read(documentEmployeeProvider(eId).future);
      final co = (emp == null || emp.hiringEntityId == null)
          ? null
          : await ref
              .read(hiringEntityByIdProvider(emp.hiringEntityId!).future);
      final ctx = AutofillContext(employee: emp, company: co, ref: ref);
      final filled = await tpl.autofill(ctx);
      setState(() {
        _coe = filled;
        _autofillDone = true;
      });
      return;
    }
    if (tpl is NteTemplate) {
      if (eId == null) {
        setState(() {
          _nte = tpl.emptyInputs();
          _autofillDone = true;
        });
        return;
      }
      final emp = await ref.read(documentEmployeeProvider(eId).future);
      final co = (emp == null || emp.hiringEntityId == null)
          ? null
          : await ref
              .read(hiringEntityByIdProvider(emp.hiringEntityId!).future);
      final ctx = AutofillContext(employee: emp, company: co, ref: ref);
      final filled = await tpl.autofill(ctx);
      setState(() {
        _nte = filled;
        _autofillDone = true;
      });
      return;
    }
    if (tpl is! QuitclaimTemplate) {
      setState(() => _autofillDone = true);
      return;
    }
    if (eId == null) {
      setState(() {
        _quitclaim = tpl.emptyInputs();
        _autofillDone = true;
      });
      return;
    }
    final emp = await ref.read(documentEmployeeProvider(eId).future);
    final co = (emp == null || emp.hiringEntityId == null)
        ? null
        : await ref.read(hiringEntityByIdProvider(emp.hiringEntityId!).future);
    final ctx = AutofillContext(employee: emp, company: co, ref: ref);
    final filled = await tpl.autofill(ctx);
    setState(() {
      _quitclaim = filled;
      _autofillDone = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final tpl = findTemplateById(widget.templateId);
    if (tpl == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Generate Document')),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('Template not found.'),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () => context.go('/documents'),
                child: const Text('Back to documents'),
              ),
            ],
          ),
        ),
      );
    }
    if (!_autofillDone) {
      return Scaffold(
        appBar: AppBar(title: Text(tpl.name)),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (_autofillError != null) {
      return Scaffold(
        appBar: AppBar(title: Text(tpl.name)),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              _autofillError!,
              textAlign: TextAlign.center,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(title: Text(tpl.name)),
      body: Row(
        children: [
          SizedBox(
            width: 480,
            child: _formFor(tpl),
          ),
          const VerticalDivider(width: 1),
          Expanded(child: _previewFor(tpl)),
        ],
      ),
    );
  }

  Widget _formFor(DocumentTemplate tpl) {
    if (tpl is QuitclaimTemplate && _quitclaim != null) {
      return QuitclaimForm(
        initial: _quitclaim!,
        employeeLocked: widget.employeeId != null,
        onChanged: (next) => setState(() => _quitclaim = next),
      );
    }
    if (tpl is CoeTemplate && _coe != null) {
      return CoeForm(
        initial: _coe!,
        employeeLocked: widget.employeeId != null,
        onChanged: (next) => setState(() => _coe = next),
      );
    }
    if (tpl is NteTemplate && _nte != null) {
      return NteForm(
        initial: _nte!,
        employeeLocked: widget.employeeId != null,
        onChanged: (next) => setState(() => _nte = next),
      );
    }
    return const Center(child: Text('Form not implemented'));
  }

  Widget _previewFor(DocumentTemplate tpl) {
    if (tpl is QuitclaimTemplate && _quitclaim != null) {
      final inputs = _quitclaim!;
      final errors = tpl.validate(inputs);
      final filename = filenameForDocument(
        templateId: 'quitclaim',
        employeeNumber: null,
        employeeId: inputs.employeeId.isEmpty ? '00000000' : inputs.employeeId,
        date: inputs.dateSigned,
      );
      return _previewWithBanner(errors, filename, (format) async {
        final theme = await PdfTheme.defaults();
        return buildDocumentPdf(blocks: tpl.build(inputs), theme: theme);
      });
    }
    if (tpl is CoeTemplate && _coe != null) {
      final inputs = _coe!;
      final errors = tpl.validate(inputs);
      final filename = filenameForDocument(
        templateId: 'coe',
        employeeNumber: null,
        employeeId: inputs.employeeId.isEmpty ? '00000000' : inputs.employeeId,
        date: DateTime.now(),
      );
      return _previewWithBanner(errors, filename, (format) async {
        final theme = await PdfTheme.defaults();
        return buildDocumentPdf(blocks: tpl.build(inputs), theme: theme);
      });
    }
    if (tpl is NteTemplate && _nte != null) {
      final inputs = _nte!;
      final errors = tpl.validate(inputs);
      final filename = filenameForDocument(
        templateId: 'nte',
        employeeNumber: null,
        employeeId: inputs.employeeId.isEmpty ? '00000000' : inputs.employeeId,
        date: inputs.dateIssued,
      );
      return _previewWithBanner(errors, filename, (format) async {
        final theme = await PdfTheme.defaults();
        return buildDocumentPdf(blocks: tpl.build(inputs), theme: theme);
      });
    }
    return const Center(child: Text('Preview not implemented'));
  }

  Widget _previewWithBanner(
    List<ValidationError> errors,
    String filename,
    Future<Uint8List> Function(PdfPageFormat) build,
  ) {
    return Column(
      children: [
        if (errors.isNotEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(8),
            color: Colors.amber.shade100,
            child: Tooltip(
              message: errors.map((e) => '• ${e.message}').join('\n'),
              child: Text(
                '${errors.length} issue${errors.length == 1 ? '' : 's'} — '
                'hover for details.',
                style: const TextStyle(color: Colors.black87),
              ),
            ),
          ),
        Expanded(
          child: PdfPreviewScaffold(
            filename: filename,
            enabled: errors.isEmpty,
            buildPdf: build,
          ),
        ),
      ],
    );
  }
}
