import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pdf/pdf.dart';

import '../../core/pdf/pdf_filename.dart';
import '../../core/pdf/pdf_preview_scaffold.dart';
import '../../core/pdf/pdf_theme.dart';
import '../../data/repositories/audit_repository.dart';
import 'forms/coe_form.dart';
import 'forms/employment_contract_form.dart';
import 'forms/nda_form.dart';
import 'forms/non_reg_form.dart';
import 'forms/nte_form.dart';
import 'forms/quitclaim_form.dart';
import 'pdf/pdf_builder.dart';
import 'providers.dart';
import 'templates/coe_inputs.dart';
import 'templates/coe_template.dart';
import 'templates/document_template.dart';
import 'templates/employment_contract_inputs.dart';
import 'templates/employment_contract_template.dart';
import 'templates/nda_inputs.dart';
import 'templates/nda_template.dart';
import 'templates/non_reg_inputs.dart';
import 'templates/non_reg_template.dart';
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
  NonRegInputs? _nonReg;
  EmploymentContractInputs? _employmentContract;
  NdaInputs? _nda;
  bool _autofillDone = false;
  String? _autofillError;
  bool _dirty = false;
  // Monotonically incrementing key suffix bumped on every successful
  // autofill (initial mount + every picker-driven re-autofill). The form
  // widget's ValueKey uses this so it remounts cleanly when autofill
  // delivers new field values, but does NOT remount on optimistic local
  // state changes (e.g. the picker setting just `employeeId`).
  int _autofillRev = 0;

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

    try {
      if (tpl is CoeTemplate) {
        if (eId == null) {
          setState(() {
            _coe = tpl.emptyInputs();
            _autofillDone = true;
            _autofillRev++;
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
          _autofillRev++;
        });
        return;
      }
      if (tpl is NteTemplate) {
        if (eId == null) {
          setState(() {
            _nte = tpl.emptyInputs();
            _autofillDone = true;
            _autofillRev++;
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
          _autofillRev++;
        });
        return;
      }
      if (tpl is NonRegTemplate) {
        if (eId == null) {
          setState(() {
            _nonReg = tpl.emptyInputs();
            _autofillDone = true;
            _autofillRev++;
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
          _nonReg = filled;
          _autofillDone = true;
          _autofillRev++;
        });
        return;
      }
      if (tpl is EmploymentContractTemplate) {
        if (eId == null) {
          setState(() {
            _employmentContract = tpl.emptyInputs();
            _autofillDone = true;
            _autofillRev++;
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
          _employmentContract = filled;
          _autofillDone = true;
          _autofillRev++;
        });
        return;
      }
      if (tpl is NdaTemplate) {
        if (eId == null) {
          setState(() {
            _nda = tpl.emptyInputs();
            _autofillDone = true;
            _autofillRev++;
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
          _nda = filled;
          _autofillDone = true;
          _autofillRev++;
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
          _autofillRev++;
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
        _quitclaim = filled;
        _autofillDone = true;
        _autofillRev++;
      });
    } catch (e, st) {
      // Log to console for debugging — keep the existing app behavior
      // of also surfacing a user-friendly message.
      // ignore: avoid_print
      print('Autofill failed for ${widget.templateId}: $e\n$st');
      if (!mounted) return;
      setState(() {
        _autofillError =
            'Could not load document data: $e\n\n'
            'Try going back and reopening this template. If the problem '
            'persists, check that the employee record is complete.';
        _autofillDone = true;
      });
    }
  }

  Future<void> _onPickerEmployeeChanged(String newEmployeeId) async {
    final tpl = findTemplateById(widget.templateId);
    if (tpl == null) return;
    try {
      final emp =
          await ref.read(documentEmployeeProvider(newEmployeeId).future);
      final co = (emp == null || emp.hiringEntityId == null)
          ? null
          : await ref
              .read(hiringEntityByIdProvider(emp.hiringEntityId!).future);
      final ctx = AutofillContext(employee: emp, company: co, ref: ref);
      if (tpl is CoeTemplate) {
        final filled = await tpl.autofill(ctx);
        if (!mounted) return;
        setState(() {
          _coe = filled;
          _autofillRev++;
          _dirty = true;
        });
      } else if (tpl is NteTemplate) {
        final filled = await tpl.autofill(ctx);
        if (!mounted) return;
        setState(() {
          _nte = filled;
          _autofillRev++;
          _dirty = true;
        });
      } else if (tpl is NonRegTemplate) {
        final filled = await tpl.autofill(ctx);
        if (!mounted) return;
        setState(() {
          _nonReg = filled;
          _autofillRev++;
          _dirty = true;
        });
      } else if (tpl is EmploymentContractTemplate) {
        final filled = await tpl.autofill(ctx);
        if (!mounted) return;
        setState(() {
          _employmentContract = filled;
          _autofillRev++;
          _dirty = true;
        });
      } else if (tpl is NdaTemplate) {
        final filled = await tpl.autofill(ctx);
        if (!mounted) return;
        setState(() {
          _nda = filled;
          _autofillRev++;
          _dirty = true;
        });
      } else if (tpl is QuitclaimTemplate) {
        final filled = await tpl.autofill(ctx);
        if (!mounted) return;
        setState(() {
          _quitclaim = filled;
          _autofillRev++;
          _dirty = true;
        });
      }
    } catch (e, st) {
      // ignore: avoid_print
      print('Re-autofill failed for ${tpl.id}: $e\n$st');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('Could not refresh fields for new employee: $e')),
      );
    }
  }

  Future<void> _attemptLeave() async {
    if (!_dirty) {
      if (mounted) context.go('/documents');
      return;
    }
    final discard = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Discard changes?'),
        content: const Text(
          'You have unsaved changes in this document. If you leave now, '
          'your changes will not be saved.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep editing'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    if (discard == true && mounted) context.go('/documents');
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
        appBar: AppBar(
          title: Text(tpl.name),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            tooltip: 'Back to documents',
            onPressed: () => context.go('/documents'),
          ),
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (_autofillError != null) {
      return Scaffold(
        appBar: AppBar(
          title: Text(tpl.name),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            tooltip: 'Back to documents',
            onPressed: () => context.go('/documents'),
          ),
        ),
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
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _attemptLeave();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(tpl.name),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            tooltip: 'Back to documents',
            onPressed: _attemptLeave,
          ),
        ),
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
      ),
    );
  }

  Widget _formFor(DocumentTemplate tpl) {
    if (tpl is QuitclaimTemplate && _quitclaim != null) {
      return QuitclaimForm(
        key: ValueKey('quitclaim-$_autofillRev'),
        initial: _quitclaim!,
        employeeLocked: widget.employeeId != null,
        onChanged: (next) => setState(() {
          _quitclaim = next;
          _dirty = true;
        }),
        onEmployeeChanged: _onPickerEmployeeChanged,
      );
    }
    if (tpl is CoeTemplate && _coe != null) {
      return CoeForm(
        key: ValueKey('coe-$_autofillRev'),
        initial: _coe!,
        employeeLocked: widget.employeeId != null,
        onChanged: (next) => setState(() {
          _coe = next;
          _dirty = true;
        }),
        onEmployeeChanged: _onPickerEmployeeChanged,
      );
    }
    if (tpl is NteTemplate && _nte != null) {
      return NteForm(
        key: ValueKey('nte-$_autofillRev'),
        initial: _nte!,
        employeeLocked: widget.employeeId != null,
        onChanged: (next) => setState(() {
          _nte = next;
          _dirty = true;
        }),
        onEmployeeChanged: _onPickerEmployeeChanged,
      );
    }
    if (tpl is NonRegTemplate && _nonReg != null) {
      return NonRegForm(
        key: ValueKey('non_reg-$_autofillRev'),
        initial: _nonReg!,
        employeeLocked: widget.employeeId != null,
        onChanged: (next) => setState(() {
          _nonReg = next;
          _dirty = true;
        }),
        onEmployeeChanged: _onPickerEmployeeChanged,
      );
    }
    if (tpl is EmploymentContractTemplate && _employmentContract != null) {
      return EmploymentContractForm(
        key: ValueKey('employment_contract-$_autofillRev'),
        initial: _employmentContract!,
        employeeLocked: widget.employeeId != null,
        onChanged: (next) => setState(() {
          _employmentContract = next;
          _dirty = true;
        }),
        onEmployeeChanged: _onPickerEmployeeChanged,
      );
    }
    if (tpl is NdaTemplate && _nda != null) {
      return NdaForm(
        key: ValueKey('nda-$_autofillRev'),
        initial: _nda!,
        employeeLocked: widget.employeeId != null,
        onChanged: (next) => setState(() {
          _nda = next;
          _dirty = true;
        }),
        onEmployeeChanged: _onPickerEmployeeChanged,
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
      // Prefer the typed-in / autofilled full name; fall back to the
      // short employee id when the name hasn't been resolved yet.
      final who = inputs.employeeFullName.trim().isNotEmpty
          ? inputs.employeeFullName.trim()
          : (inputs.employeeId.isEmpty
              ? '(unknown employee)'
              : inputs.employeeId);
      return _previewWithBanner(
        errors,
        filename,
        (format) async {
          final theme = await PdfTheme.defaults();
          return buildDocumentPdf(blocks: tpl.build(inputs), theme: theme);
        },
        onExported: (action) {
          ref.read(auditRepositoryProvider).logExport(
            description: 'Quitclaim PDF $action: $who',
            entityType: 'document_template_pdf',
            metadata: {
              'template_id': 'quitclaim',
              'employee_id':
                  inputs.employeeId.isEmpty ? null : inputs.employeeId,
              'file_name': filename,
              'action': action,
            },
          );
        },
      );
    }
    if (tpl is CoeTemplate && _coe != null) {
      final inputs = _coe!;
      final errors = tpl.validate(inputs);
      final filename = filenameForDocument(
        templateId: 'coe',
        employeeNumber: null,
        employeeId: inputs.employeeId.isEmpty ? '00000000' : inputs.employeeId,
        date: inputs.dateIssued,
      );
      final who = inputs.employeeFullName.trim().isNotEmpty
          ? inputs.employeeFullName.trim()
          : (inputs.employeeId.isEmpty
              ? '(unknown employee)'
              : inputs.employeeId);
      return _previewWithBanner(
        errors,
        filename,
        (format) async {
          final theme = await PdfTheme.defaults();
          return buildDocumentPdf(blocks: tpl.build(inputs), theme: theme);
        },
        onExported: (action) {
          ref.read(auditRepositoryProvider).logExport(
            description: 'COE PDF $action: $who',
            entityType: 'document_template_pdf',
            metadata: {
              'template_id': 'coe',
              'employee_id':
                  inputs.employeeId.isEmpty ? null : inputs.employeeId,
              'file_name': filename,
              'action': action,
            },
          );
        },
      );
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
      final who = inputs.employeeFullName.trim().isNotEmpty
          ? inputs.employeeFullName.trim()
          : (inputs.employeeId.isEmpty
              ? '(unknown employee)'
              : inputs.employeeId);
      final subject = inputs.finalSubject;
      return _previewWithBanner(
        errors,
        filename,
        (format) async {
          final theme = await PdfTheme.defaults();
          return buildDocumentPdf(blocks: tpl.build(inputs), theme: theme);
        },
        onExported: (action) {
          ref.read(auditRepositoryProvider).logExport(
            description: 'NTE PDF $action: $who — $subject',
            entityType: 'document_template_pdf',
            metadata: {
              'template_id': 'nte',
              'employee_id':
                  inputs.employeeId.isEmpty ? null : inputs.employeeId,
              'subject': subject,
              'file_name': filename,
              'action': action,
            },
          );
        },
      );
    }
    if (tpl is NonRegTemplate && _nonReg != null) {
      final inputs = _nonReg!;
      final errors = tpl.validate(inputs);
      final filename = filenameForDocument(
        templateId: 'non_reg',
        employeeNumber: null,
        employeeId: inputs.employeeId.isEmpty ? '00000000' : inputs.employeeId,
        date: inputs.dateIssued,
      );
      final who = inputs.employeeFullName.trim().isNotEmpty
          ? inputs.employeeFullName.trim()
          : (inputs.employeeId.isEmpty
              ? '(unknown employee)'
              : inputs.employeeId);
      return _previewWithBanner(
        errors,
        filename,
        (format) async {
          final theme = await PdfTheme.defaults();
          return buildDocumentPdf(blocks: tpl.build(inputs), theme: theme);
        },
        onExported: (action) {
          ref.read(auditRepositoryProvider).logExport(
            description: 'Non-Reg PDF $action: $who',
            entityType: 'document_template_pdf',
            metadata: {
              'template_id': 'non_reg',
              'employee_id':
                  inputs.employeeId.isEmpty ? null : inputs.employeeId,
              'file_name': filename,
              'action': action,
            },
          );
        },
      );
    }
    if (tpl is EmploymentContractTemplate && _employmentContract != null) {
      final inputs = _employmentContract!;
      final errors = tpl.validate(inputs);
      final filename = filenameForDocument(
        templateId: 'employment_contract',
        employeeNumber: null,
        employeeId: inputs.employeeId.isEmpty ? '00000000' : inputs.employeeId,
        date: inputs.dateEntered,
      );
      final who = inputs.employeeFullName.trim().isNotEmpty
          ? inputs.employeeFullName.trim()
          : (inputs.employeeId.isEmpty
              ? '(unknown employee)'
              : inputs.employeeId);
      return _previewWithBanner(
        errors,
        filename,
        (format) async {
          final theme = await PdfTheme.defaults();
          return buildDocumentPdf(blocks: tpl.build(inputs), theme: theme);
        },
        onExported: (action) {
          ref.read(auditRepositoryProvider).logExport(
            description: 'Employment Contract PDF $action: $who',
            entityType: 'document_template_pdf',
            metadata: {
              'template_id': 'employment_contract',
              'employee_id':
                  inputs.employeeId.isEmpty ? null : inputs.employeeId,
              'file_name': filename,
              'action': action,
            },
          );
        },
      );
    }
    if (tpl is NdaTemplate && _nda != null) {
      final inputs = _nda!;
      final errors = tpl.validate(inputs);
      final filename = filenameForDocument(
        templateId: 'nda',
        employeeNumber: null,
        employeeId: inputs.employeeId.isEmpty ? '00000000' : inputs.employeeId,
        date: inputs.effectiveDate ?? DateTime.now(),
      );
      final who = inputs.employeeFullName.trim().isNotEmpty
          ? inputs.employeeFullName.trim()
          : (inputs.employeeId.isEmpty
              ? '(unknown employee)'
              : inputs.employeeId);
      return _previewWithBanner(
        errors,
        filename,
        (format) async {
          final theme = await PdfTheme.defaults();
          return buildDocumentPdf(blocks: tpl.build(inputs), theme: theme);
        },
        onExported: (action) {
          ref.read(auditRepositoryProvider).logExport(
            description: 'NDA PDF $action: $who',
            entityType: 'document_template_pdf',
            metadata: {
              'template_id': 'nda',
              'employee_id':
                  inputs.employeeId.isEmpty ? null : inputs.employeeId,
              'file_name': filename,
              'action': action,
            },
          );
        },
      );
    }
    return const Center(child: Text('Preview not implemented'));
  }

  Widget _previewWithBanner(
    List<ValidationError> errors,
    String filename,
    Future<Uint8List> Function(PdfPageFormat) build, {
    void Function(String action)? onExported,
  }) {
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
            onExported: onExported,
          ),
        ),
      ],
    );
  }
}
