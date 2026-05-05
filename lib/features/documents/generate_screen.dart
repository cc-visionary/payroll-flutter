import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pdf/pdf.dart';

import '../../core/pdf/pdf_filename.dart';
import '../../core/pdf/pdf_preview_scaffold.dart';
import '../../core/pdf/pdf_theme.dart';
import 'forms/quitclaim_form.dart';
import 'pdf/pdf_builder.dart';
import 'providers.dart';
import 'templates/document_template.dart';
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
  bool _autofillDone = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _runAutofill());
  }

  Future<void> _runAutofill() async {
    final tpl = findTemplateById(widget.templateId);
    if (tpl is! QuitclaimTemplate) {
      setState(() => _autofillDone = true);
      return;
    }
    final eId = widget.employeeId;
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
      return PdfPreviewScaffold(
        filename: filename,
        enabled: errors.isEmpty,
        buildPdf: (PdfPageFormat format) async {
          final theme = await PdfTheme.defaults();
          return buildDocumentPdf(blocks: tpl.build(inputs), theme: theme);
        },
      );
    }
    return const Center(child: Text('Preview not implemented'));
  }
}
