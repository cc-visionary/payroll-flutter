import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart' hide Block;

import '../../core/pdf/pdf_filename.dart';
import '../../core/pdf/pdf_preview_scaffold.dart';
import '../../core/pdf/pdf_theme.dart';
import '../../data/repositories/audit_repository.dart';
import '../../data/repositories/employee_document_repository.dart';
import '../employees/profile/providers.dart' show employeeDocumentsProvider;
import 'blocks/block.dart';
import 'document_type_mapping.dart';
import 'forms/coe_form.dart';
import 'forms/employment_contract_form.dart';
import 'forms/final_pay_form.dart';
import 'forms/liability_waiver_form.dart';
import 'forms/nda_form.dart';
import 'forms/nod_form.dart';
import 'forms/non_reg_form.dart';
import 'forms/nte_form.dart';
import 'forms/quitclaim_form.dart';
import 'forms/regularization_form.dart';
import 'forms/resignation_acceptance_form.dart';
import 'forms/salary_adjustment_form.dart';
import 'pdf/pdf_builder.dart';
import 'providers.dart';
import 'templates/coe_inputs.dart';
import 'templates/coe_template.dart';
import 'templates/document_template.dart';
import 'templates/employment_contract_inputs.dart';
import 'templates/employment_contract_template.dart';
import 'templates/final_pay_inputs.dart';
import 'templates/final_pay_template.dart';
import 'templates/liability_waiver_inputs.dart';
import 'templates/liability_waiver_template.dart';
import 'templates/nda_inputs.dart';
import 'templates/nda_template.dart';
import 'templates/nod_inputs.dart';
import 'templates/nod_template.dart';
import 'templates/non_reg_inputs.dart';
import 'templates/non_reg_template.dart';
import 'templates/nte_inputs.dart';
import 'templates/nte_template.dart';
import 'templates/quitclaim_inputs.dart';
import 'templates/quitclaim_template.dart';
import 'templates/regularization_inputs.dart';
import 'templates/regularization_template.dart';
import 'templates/resignation_acceptance_inputs.dart';
import 'templates/resignation_acceptance_template.dart';
import 'templates/salary_adjustment_inputs.dart';
import 'templates/salary_adjustment_template.dart';
import 'templates/template_registry.dart';

/// The two-stage flow of the generate screen.
///
/// * [editing] — the form is shown with a primary Generate button. No
///   Download/Print is exposed here; nothing has been saved yet.
/// * [preview] — a full PDF preview of the just-generated (and persisted)
///   document with Download / Print / Back-to-edit.
enum GenerateStage { editing, preview }

/// Normalise a template-inputs employee id to null when it is absent/empty.
///
/// A null result is the signal to SKIP persistence: the document is not scoped
/// to an employee record (applicant-mode offer letters, or a non-employee
/// document). Employee-scoped documents return their non-empty id unchanged.
String? scopedEmployeeId(String? raw) =>
    (raw == null || raw.isEmpty) ? null : raw;

/// Everything the shared generate-and-save pipeline needs for the current
/// template, computed once per build from the template's current inputs.
///
/// This is the single seam that collapses the ~12 per-template branches into
/// one path: the editing stage reads [errors] for the Generate button, and
/// [run] both renders and persists the PDF uniformly.
class _GenerateDescriptor {
  final String templateId;

  /// Current, JSON-serializable inputs (drives `generation_options`).
  final TemplateInputs inputs;

  /// Validation errors for the current inputs. Empty ⇒ Generate is enabled.
  final List<ValidationError> errors;

  /// Suggested PDF filename for this template + inputs.
  final String fileName;

  /// Resolved employee id, or null when the document is not scoped to an
  /// employee record (applicant-mode offer letters, empty id). Null ⇒ skip
  /// persistence and go straight to preview.
  final String? employeeId;

  /// Document-type metadata (`COE`, "Certificate of Employment", …).
  final DocumentTypeInfo docTypeInfo;

  /// Renders the PDF bytes for the current inputs using [theme].
  final Future<Uint8List> Function(PdfTheme theme) buildBytes;

  /// Audit-log callback fired after a successful Download / Print.
  final void Function(String action) onExported;

  const _GenerateDescriptor({
    required this.templateId,
    required this.inputs,
    required this.errors,
    required this.fileName,
    required this.employeeId,
    required this.docTypeInfo,
    required this.buildBytes,
    required this.onExported,
  });

  bool get isValid => errors.isEmpty;
}

class GenerateScreen extends ConsumerStatefulWidget {
  final String templateId;
  final String? employeeId;

  /// Test-only override for the PDF theme. When null (production) the screen
  /// fetches [PdfTheme.defaults] (Inter from Google Fonts). Tests inject
  /// [PdfTheme.testStub] to avoid the network fetch that races under
  /// `flutter_test`.
  final PdfTheme? pdfThemeOverride;

  /// When false, the editing-stage live preview pane is replaced by a light
  /// placeholder. Production keeps it true; widget tests set it false because
  /// the embedded `PdfPreview` rasterizer never quiesces under
  /// `pumpAndSettle`. The preview STAGE (post-Generate) always renders.
  final bool showLivePreview;

  const GenerateScreen({
    super.key,
    required this.templateId,
    this.employeeId,
    this.pdfThemeOverride,
    this.showLivePreview = true,
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
  LiabilityWaiverInputs? _liabilityWaiver;
  FinalPayInputs? _finalPay;
  SalaryAdjustmentInputs? _salaryAdjustment;
  NodInputs? _nod;
  RegularizationInputs? _regularization;
  ResignationAcceptanceInputs? _resignationAcceptance;
  bool _autofillDone = false;
  String? _autofillError;
  bool _dirty = false;
  // Monotonically incrementing key suffix bumped on every successful
  // autofill (initial mount + every picker-driven re-autofill). The form
  // widget's ValueKey uses this so it remounts cleanly when autofill
  // delivers new field values, but does NOT remount on optimistic local
  // state changes (e.g. the picker setting just `employeeId`).
  int _autofillRev = 0;

  // --- Two-stage flow state -------------------------------------------------
  GenerateStage _stage = GenerateStage.editing;

  /// Bytes of the document rendered at the last successful Generate. The
  /// preview stage serves these verbatim (no re-render), so Download / Print
  /// export exactly what was saved.
  Uint8List? _generatedBytes;

  /// Filename captured at the last Generate, used by the preview export bar.
  String? _generatedFileName;

  /// Audit callback captured at the last Generate, forwarded to the preview
  /// export bar so Download / Print keep logging EXPORT rows as before.
  void Function(String action)? _generatedOnExported;

  /// Saved `employee_documents.id` for THIS screen session. Held so that
  /// re-generating after "Back to edit" UPDATES the same row instead of
  /// inserting a new one. Reset only when the screen is freshly opened
  /// (i.e. never reset within a single mounted instance).
  String? _sessionRecordId;

  /// True when the last Generate skipped persistence because the document is
  /// not scoped to an employee record (applicant-mode / empty id).
  bool _saveSkipped = false;

  /// True when the last Generate reached preview but the best-effort settings
  /// save threw. The preview is fully usable (Download/Print work off the
  /// rendered bytes); this only signals that the settings record was NOT
  /// written, surfaced as a non-blocking warning banner.
  bool _saveFailed = false;

  /// Set while a Generate is in flight; disables the button and shows a
  /// spinner.
  bool _generating = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _runAutofill());
  }

  /// Resolve the PDF theme — injected stub in tests, network defaults in
  /// production.
  Future<PdfTheme> _theme() async =>
      widget.pdfThemeOverride ?? await PdfTheme.defaults();

  Future<void> _runAutofill() async {
    final tpl = findTemplateById(widget.templateId);
    final eId = widget.employeeId;

    // Pre-warm the font theme so any cold-start failure surfaces here
    // rather than as an unhelpful preview build error.
    try {
      await _theme();
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
        final ctx = await _contextFor(eId);
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
        final ctx = await _contextFor(eId);
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
        final ctx = await _contextFor(eId);
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
        final ctx = await _contextFor(eId);
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
        final ctx = await _contextFor(eId);
        final filled = await tpl.autofill(ctx);
        setState(() {
          _nda = filled;
          _autofillDone = true;
          _autofillRev++;
        });
        return;
      }
      if (tpl is LiabilityWaiverTemplate) {
        if (eId == null) {
          setState(() {
            _liabilityWaiver = tpl.emptyInputs();
            _autofillDone = true;
            _autofillRev++;
          });
          return;
        }
        final ctx = await _contextFor(eId);
        final filled = await tpl.autofill(ctx);
        setState(() {
          _liabilityWaiver = filled;
          _autofillDone = true;
          _autofillRev++;
        });
        return;
      }
      if (tpl is FinalPayTemplate) {
        if (eId == null) {
          setState(() {
            _finalPay = tpl.emptyInputs();
            _autofillDone = true;
            _autofillRev++;
          });
          return;
        }
        final ctx = await _contextFor(eId);
        final filled = await tpl.autofill(ctx);
        setState(() {
          _finalPay = filled;
          _autofillDone = true;
          _autofillRev++;
        });
        return;
      }
      if (tpl is SalaryAdjustmentTemplate) {
        if (eId == null) {
          setState(() {
            _salaryAdjustment = tpl.emptyInputs();
            _autofillDone = true;
            _autofillRev++;
          });
          return;
        }
        final ctx = await _contextFor(eId);
        final filled = await tpl.autofill(ctx);
        setState(() {
          _salaryAdjustment = filled;
          _autofillDone = true;
          _autofillRev++;
        });
        return;
      }
      if (tpl is NodTemplate) {
        if (eId == null) {
          setState(() {
            _nod = tpl.emptyInputs();
            _autofillDone = true;
            _autofillRev++;
          });
          return;
        }
        final ctx = await _contextFor(eId);
        final filled = await tpl.autofill(ctx);
        setState(() {
          _nod = filled;
          _autofillDone = true;
          _autofillRev++;
        });
        return;
      }
      if (tpl is RegularizationTemplate) {
        if (eId == null) {
          setState(() {
            _regularization = tpl.emptyInputs();
            _autofillDone = true;
            _autofillRev++;
          });
          return;
        }
        final ctx = await _contextFor(eId);
        final filled = await tpl.autofill(ctx);
        setState(() {
          _regularization = filled;
          _autofillDone = true;
          _autofillRev++;
        });
        return;
      }
      if (tpl is ResignationAcceptanceTemplate) {
        if (eId == null) {
          setState(() {
            _resignationAcceptance = tpl.emptyInputs();
            _autofillDone = true;
            _autofillRev++;
          });
          return;
        }
        final ctx = await _contextFor(eId);
        final filled = await tpl.autofill(ctx);
        setState(() {
          _resignationAcceptance = filled;
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
      final ctx = await _contextFor(eId);
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

  /// Build an [AutofillContext] for [employeeId], resolving the employee and
  /// (if any) the hiring entity.
  Future<AutofillContext> _contextFor(String employeeId) async {
    final emp = await ref.read(documentEmployeeProvider(employeeId).future);
    final co = (emp == null || emp.hiringEntityId == null)
        ? null
        : await ref.read(hiringEntityByIdProvider(emp.hiringEntityId!).future);
    return AutofillContext(employee: emp, company: co, ref: ref);
  }

  Future<void> _onPickerEmployeeChanged(String newEmployeeId) async {
    final tpl = findTemplateById(widget.templateId);
    if (tpl == null) return;
    try {
      final ctx = await _contextFor(newEmployeeId);
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
      } else if (tpl is LiabilityWaiverTemplate) {
        final filled = await tpl.autofill(ctx);
        if (!mounted) return;
        setState(() {
          _liabilityWaiver = filled;
          _autofillRev++;
          _dirty = true;
        });
      } else if (tpl is FinalPayTemplate) {
        final filled = await tpl.autofill(ctx);
        if (!mounted) return;
        setState(() {
          _finalPay = filled;
          _autofillRev++;
          _dirty = true;
        });
      } else if (tpl is SalaryAdjustmentTemplate) {
        final filled = await tpl.autofill(ctx);
        if (!mounted) return;
        setState(() {
          _salaryAdjustment = filled;
          _autofillRev++;
          _dirty = true;
        });
      } else if (tpl is NodTemplate) {
        final filled = await tpl.autofill(ctx);
        if (!mounted) return;
        setState(() {
          _nod = filled;
          _autofillRev++;
          _dirty = true;
        });
      } else if (tpl is RegularizationTemplate) {
        final filled = await tpl.autofill(ctx);
        if (!mounted) return;
        setState(() {
          _regularization = filled;
          _autofillRev++;
          _dirty = true;
        });
      } else if (tpl is ResignationAcceptanceTemplate) {
        final filled = await tpl.autofill(ctx);
        if (!mounted) return;
        setState(() {
          _resignationAcceptance = filled;
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
          content: Text('Could not refresh fields for new employee: $e'),
        ),
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

  /// Shared generate-and-preview pipeline. The PDF is always rendered on the
  /// fly; persistence is best-effort. The sequence is:
  ///
  /// 1. Render the PDF bytes. If RENDERING fails we stay on the editing stage
  ///    (we cannot preview without bytes) and surface the error.
  /// 2. On render success, ALWAYS transition to the preview stage so
  ///    Download / Print work regardless of persistence.
  /// 3. THEN, for employee-scoped documents, attempt to persist the SETTINGS
  ///    in its own try/catch. A failure here does NOT leave the preview — it
  ///    only raises a non-blocking warning. Applicant-mode / empty id skips
  ///    the save with the existing "not filed" note.
  Future<void> _runGenerate(_GenerateDescriptor d) async {
    if (!d.isValid || _generating) return;
    setState(() => _generating = true);

    // --- Step 1: render. A render failure keeps us on editing. -------------
    final Uint8List bytes;
    try {
      final theme = await _theme();
      bytes = await d.buildBytes(theme);
    } catch (e, st) {
      // Cannot preview without bytes — stay on editing, preserve form state.
      // ignore: avoid_print
      print('Generate render failed for ${widget.templateId}: $e\n$st');
      if (!mounted) return;
      setState(() => _generating = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Couldn't generate the document. $e"),
        ),
      );
      return;
    }

    // --- Step 2: render succeeded — go to preview unconditionally. ---------
    if (!mounted) return;
    final employeeId = d.employeeId;
    setState(() {
      _generatedBytes = bytes;
      _generatedFileName = d.fileName;
      _generatedOnExported = d.onExported;
      _saveSkipped = employeeId == null;
      _saveFailed = false;
      _stage = GenerateStage.preview;
      _generating = false;
    });

    // Applicant-mode / no employee id → nothing to persist.
    if (employeeId == null) return;

    // --- Step 3: best-effort settings save. A failure only warns. ----------
    try {
      final repo = ref.read(employeeDocumentRepositoryProvider);
      final saved = await repo.saveGenerated(
        employeeId: employeeId,
        documentType: d.docTypeInfo.code,
        title: d.docTypeInfo.title,
        fileName: d.fileName,
        generationOptions: d.inputs.toJson(),
        templateId: d.templateId,
        sessionRecordId: _sessionRecordId,
      );
      _sessionRecordId = saved.id;
      // Reflect the new/updated record immediately: the company-wide hub and
      // the employee's Documents tab must show it without a stale cache. The
      // tab provider is autoDispose (refreshes on next visit), but a tab that
      // is already open needs this explicit nudge.
      ref.invalidate(allDocumentsProvider);
      ref.invalidate(employeeDocumentsProvider(employeeId));
    } catch (e, st) {
      // Persistence is non-blocking: the document is already previewable and
      // exportable. Surface a warning but keep the user on the preview.
      // ignore: avoid_print
      print('Settings save failed for ${widget.templateId}: $e\n$st');
      if (!mounted) return;
      setState(() => _saveFailed = true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            "Saved to preview, but the settings weren't recorded.",
          ),
        ),
      );
    }
  }

  void _backToEdit() {
    setState(() {
      _stage = GenerateStage.editing;
      // Keep _generatedBytes etc. so a no-change re-generate is cheap, and
      // keep _sessionRecordId so re-Generate UPDATES the same row.
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

    final descriptor = _descriptorFor(tpl);

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
        body: _stage == GenerateStage.preview
            ? _buildPreviewStage()
            : _buildEditingStage(tpl, descriptor),
      ),
    );
  }

  /// Editing stage: form on the left, a (non-exportable) live preview on the
  /// right, and a primary Generate button. Download/Print are never shown
  /// here — generation is the save point.
  Widget _buildEditingStage(
    DocumentTemplate tpl,
    _GenerateDescriptor? descriptor,
  ) {
    return Row(
      children: [
        SizedBox(
          width: 480,
          child: Column(
            children: [
              Expanded(child: _formFor(tpl)),
              _buildGenerateBar(descriptor),
            ],
          ),
        ),
        const VerticalDivider(width: 1),
        Expanded(child: _buildLivePreview(descriptor)),
      ],
    );
  }

  /// Primary Generate button + validation banner. The button is disabled
  /// until the form is valid (no validation errors) and while a generate is
  /// in flight.
  Widget _buildGenerateBar(_GenerateDescriptor? descriptor) {
    final errors = descriptor?.errors ?? const <ValidationError>[];
    final canGenerate = descriptor != null && descriptor.isValid;
    return Material(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (errors.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Tooltip(
                  message: errors.map((e) => '• ${e.message}').join('\n'),
                  child: Text(
                    '${errors.length} issue${errors.length == 1 ? '' : 's'} '
                    'to resolve before generating — hover for details.',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                      fontSize: 13,
                    ),
                  ),
                ),
              ),
            FilledButton.icon(
              onPressed: (canGenerate && !_generating)
                  ? () => _runGenerate(descriptor)
                  : null,
              icon: _generating
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.task_alt),
              label: Text(_generating ? 'Generating…' : 'Generate'),
            ),
          ],
        ),
      ),
    );
  }

  /// A read-only live preview shown alongside the form for editing feedback.
  /// It NEVER exposes Download/Print (those belong to the preview stage).
  Widget _buildLivePreview(_GenerateDescriptor? descriptor) {
    if (descriptor == null) {
      return const Center(child: Text('Preview not implemented'));
    }
    if (!widget.showLivePreview) {
      // Test mode: the embedded PdfPreview rasterizer never settles, so it is
      // swapped for a placeholder. Validity is still reflected for parity.
      return Center(
        child: Text(
          descriptor.isValid
              ? 'Live preview hidden'
              : 'Complete required fields to preview',
        ),
      );
    }
    if (!descriptor.isValid) {
      return Center(
        child: Text(
          'Complete required fields to preview',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontSize: 14,
          ),
        ),
      );
    }
    return PdfPreviewScaffold(
      // No actions / onExported here — editing-stage preview is view-only.
      filename: descriptor.fileName,
      enabled: true,
      allowExport: false,
      buildPdf: (format) async {
        final theme = await _theme();
        return descriptor.buildBytes(theme);
      },
    );
  }

  /// Preview stage: full preview of the already-generated/saved bytes with
  /// Download + Print + Back-to-edit.
  Widget _buildPreviewStage() {
    final bytes = _generatedBytes;
    final filename = _generatedFileName;
    if (bytes == null || filename == null) {
      // Shouldn't happen — defensive fallback.
      return const Center(child: Text('Nothing generated yet.'));
    }
    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: Row(
            children: [
              TextButton.icon(
                onPressed: _backToEdit,
                icon: const Icon(Icons.edit, size: 18),
                label: const Text('Back to edit'),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _saveFailed
                    ? Row(
                        children: [
                          Icon(
                            Icons.warning_amber_rounded,
                            size: 16,
                            color: Theme.of(context).colorScheme.error,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              "Saved to preview, but the settings weren't "
                              'recorded.',
                              style: TextStyle(
                                fontSize: 13,
                                color: Theme.of(context).colorScheme.error,
                              ),
                            ),
                          ),
                        ],
                      )
                    : Text(
                        _saveSkipped
                            ? 'Not filed to an employee record.'
                            : 'Saved to the employee record.',
                        style: TextStyle(
                          fontSize: 13,
                          color:
                              Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
              ),
            ],
          ),
        ),
        Expanded(
          child: PdfPreviewScaffold(
            filename: filename,
            enabled: true,
            // Serve the already-saved bytes verbatim so Download / Print
            // export exactly what was persisted.
            buildPdf: (_) async => bytes,
            onExported: _generatedOnExported,
          ),
        ),
      ],
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
    if (tpl is LiabilityWaiverTemplate && _liabilityWaiver != null) {
      return LiabilityWaiverForm(
        key: ValueKey('liability_waiver-$_autofillRev'),
        initial: _liabilityWaiver!,
        employeeLocked: widget.employeeId != null,
        onChanged: (next) => setState(() {
          _liabilityWaiver = next;
          _dirty = true;
        }),
        onEmployeeChanged: _onPickerEmployeeChanged,
      );
    }
    if (tpl is FinalPayTemplate && _finalPay != null) {
      return FinalPayForm(
        key: ValueKey('final_pay-$_autofillRev'),
        initial: _finalPay!,
        employeeLocked: widget.employeeId != null,
        onChanged: (next) => setState(() {
          _finalPay = next;
          _dirty = true;
        }),
        onEmployeeChanged: _onPickerEmployeeChanged,
      );
    }
    if (tpl is SalaryAdjustmentTemplate && _salaryAdjustment != null) {
      return SalaryAdjustmentForm(
        key: ValueKey('salary_adjustment-$_autofillRev'),
        initial: _salaryAdjustment!,
        employeeLocked: widget.employeeId != null,
        onChanged: (next) => setState(() {
          _salaryAdjustment = next;
          _dirty = true;
        }),
        onEmployeeChanged: _onPickerEmployeeChanged,
      );
    }
    if (tpl is NodTemplate && _nod != null) {
      return NodForm(
        key: ValueKey('nod-$_autofillRev'),
        initial: _nod!,
        employeeLocked: widget.employeeId != null,
        onChanged: (next) => setState(() {
          _nod = next;
          _dirty = true;
        }),
        onEmployeeChanged: _onPickerEmployeeChanged,
      );
    }
    if (tpl is RegularizationTemplate && _regularization != null) {
      return RegularizationForm(
        key: ValueKey('regularization-$_autofillRev'),
        initial: _regularization!,
        employeeLocked: widget.employeeId != null,
        onChanged: (next) => setState(() {
          _regularization = next;
          _dirty = true;
        }),
        onEmployeeChanged: _onPickerEmployeeChanged,
      );
    }
    if (tpl is ResignationAcceptanceTemplate &&
        _resignationAcceptance != null) {
      return ResignationAcceptanceForm(
        key: ValueKey('resignation_acceptance-$_autofillRev'),
        initial: _resignationAcceptance!,
        employeeLocked: widget.employeeId != null,
        onChanged: (next) => setState(() {
          _resignationAcceptance = next;
          _dirty = true;
        }),
        onEmployeeChanged: _onPickerEmployeeChanged,
      );
    }
    return const Center(child: Text('Form not implemented'));
  }

  /// Computes the shared [_GenerateDescriptor] for the current template +
  /// inputs. Returns null when the template's inputs aren't ready yet (or the
  /// template is unhandled). Every template routes through here, so the
  /// Generate button, live preview, and save pipeline share one definition of
  /// `(inputs, errors, fileName, employeeId, build, audit)`.
  _GenerateDescriptor? _descriptorFor(DocumentTemplate tpl) {
    final docType = documentTypeForTemplateId(tpl.id);
    if (docType == null) return null;

    if (tpl is QuitclaimTemplate && _quitclaim != null) {
      final inputs = _quitclaim!;
      final filename = filenameForDocument(
        templateId: 'quitclaim',
        employeeNumber: null,
        employeeId: inputs.employeeId.isEmpty ? '00000000' : inputs.employeeId,
        date: inputs.dateSigned,
      );
      return _descriptor(
        templateId: 'quitclaim',
        inputs: inputs,
        errors: tpl.validate(inputs),
        fileName: filename,
        employeeId: scopedEmployeeId(inputs.employeeId),
        docType: docType,
        blocks: () => tpl.build(inputs),
        who: _who(inputs.employeeFullName, inputs.employeeId),
        auditDescription: (action, who) => 'Quitclaim PDF $action: $who',
        auditMetadata: (action) => {
          'template_id': 'quitclaim',
          'employee_id':
              inputs.employeeId.isEmpty ? null : inputs.employeeId,
          'file_name': filename,
          'action': action,
        },
      );
    }
    if (tpl is CoeTemplate && _coe != null) {
      final inputs = _coe!;
      final filename = filenameForDocument(
        templateId: 'coe',
        employeeNumber: null,
        employeeId: inputs.employeeId.isEmpty ? '00000000' : inputs.employeeId,
        date: inputs.dateIssued,
      );
      return _descriptor(
        templateId: 'coe',
        inputs: inputs,
        errors: tpl.validate(inputs),
        fileName: filename,
        employeeId: scopedEmployeeId(inputs.employeeId),
        docType: docType,
        blocks: () => tpl.build(inputs),
        who: _who(inputs.employeeFullName, inputs.employeeId),
        auditDescription: (action, who) => 'COE PDF $action: $who',
        auditMetadata: (action) => {
          'template_id': 'coe',
          'employee_id':
              inputs.employeeId.isEmpty ? null : inputs.employeeId,
          'file_name': filename,
          'action': action,
        },
      );
    }
    if (tpl is NteTemplate && _nte != null) {
      final inputs = _nte!;
      final filename = filenameForDocument(
        templateId: 'nte',
        employeeNumber: null,
        employeeId: inputs.employeeId.isEmpty ? '00000000' : inputs.employeeId,
        date: inputs.dateIssued,
      );
      final subject = inputs.finalSubject;
      return _descriptor(
        templateId: 'nte',
        inputs: inputs,
        errors: tpl.validate(inputs),
        fileName: filename,
        employeeId: scopedEmployeeId(inputs.employeeId),
        docType: docType,
        blocks: () => tpl.build(inputs),
        who: _who(inputs.employeeFullName, inputs.employeeId),
        auditDescription: (action, who) => 'NTE PDF $action: $who — $subject',
        auditMetadata: (action) => {
          'template_id': 'nte',
          'employee_id':
              inputs.employeeId.isEmpty ? null : inputs.employeeId,
          'subject': subject,
          'file_name': filename,
          'action': action,
        },
      );
    }
    if (tpl is NonRegTemplate && _nonReg != null) {
      final inputs = _nonReg!;
      final filename = filenameForDocument(
        templateId: 'non_reg',
        employeeNumber: null,
        employeeId: inputs.employeeId.isEmpty ? '00000000' : inputs.employeeId,
        date: inputs.dateIssued,
      );
      return _descriptor(
        templateId: 'non_reg',
        inputs: inputs,
        errors: tpl.validate(inputs),
        fileName: filename,
        employeeId: scopedEmployeeId(inputs.employeeId),
        docType: docType,
        blocks: () => tpl.build(inputs),
        who: _who(inputs.employeeFullName, inputs.employeeId),
        auditDescription: (action, who) => 'Non-Reg PDF $action: $who',
        auditMetadata: (action) => {
          'template_id': 'non_reg',
          'employee_id':
              inputs.employeeId.isEmpty ? null : inputs.employeeId,
          'file_name': filename,
          'action': action,
        },
      );
    }
    if (tpl is EmploymentContractTemplate && _employmentContract != null) {
      final inputs = _employmentContract!;
      final filename = filenameForDocument(
        templateId: 'employment_contract',
        employeeNumber: null,
        employeeId: (inputs.employeeId?.isEmpty ?? true)
            ? '00000000'
            : inputs.employeeId!,
        date: inputs.dateEntered,
      );
      return _descriptor(
        templateId: 'employment_contract',
        inputs: inputs,
        errors: tpl.validate(inputs),
        fileName: filename,
        // Applicant-mode contracts have a null/empty employeeId → skip save.
        employeeId: scopedEmployeeId(inputs.employeeId),
        docType: docType,
        blocks: () => tpl.build(inputs),
        who: _who(
          inputs.employeeFullName,
          inputs.employeeId ?? '',
        ),
        auditDescription: (action, who) =>
            'Employment Contract PDF $action: $who',
        auditMetadata: (action) => {
          'template_id': 'employment_contract',
          'employee_id': (inputs.employeeId?.isEmpty ?? true)
              ? null
              : inputs.employeeId,
          'file_name': filename,
          'action': action,
        },
      );
    }
    if (tpl is NdaTemplate && _nda != null) {
      final inputs = _nda!;
      final filename = filenameForDocument(
        templateId: 'nda',
        employeeNumber: null,
        employeeId: inputs.employeeId.isEmpty ? '00000000' : inputs.employeeId,
        date: inputs.effectiveDate ?? DateTime.now(),
      );
      return _descriptor(
        templateId: 'nda',
        inputs: inputs,
        errors: tpl.validate(inputs),
        fileName: filename,
        employeeId: scopedEmployeeId(inputs.employeeId),
        docType: docType,
        blocks: () => tpl.build(inputs),
        who: _who(inputs.employeeFullName, inputs.employeeId),
        auditDescription: (action, who) => 'NDA PDF $action: $who',
        auditMetadata: (action) => {
          'template_id': 'nda',
          'employee_id':
              inputs.employeeId.isEmpty ? null : inputs.employeeId,
          'file_name': filename,
          'action': action,
        },
      );
    }
    if (tpl is LiabilityWaiverTemplate && _liabilityWaiver != null) {
      final inputs = _liabilityWaiver!;
      final filename = filenameForDocument(
        templateId: 'liability_waiver',
        employeeNumber: null,
        employeeId: inputs.employeeId.isEmpty ? '00000000' : inputs.employeeId,
        date: inputs.dateSigned,
      );
      return _descriptor(
        templateId: 'liability_waiver',
        inputs: inputs,
        errors: tpl.validate(inputs),
        fileName: filename,
        employeeId: scopedEmployeeId(inputs.employeeId),
        docType: docType,
        blocks: () => tpl.build(inputs),
        who: _who(inputs.employeeFullName, inputs.employeeId),
        auditDescription: (action, who) => 'Liability Waiver PDF $action: $who',
        auditMetadata: (action) => {
          'template_id': 'liability_waiver',
          'employee_id':
              inputs.employeeId.isEmpty ? null : inputs.employeeId,
          'file_name': filename,
          'action': action,
        },
      );
    }
    if (tpl is FinalPayTemplate && _finalPay != null) {
      final inputs = _finalPay!;
      final filename = filenameForDocument(
        templateId: 'final_pay',
        employeeNumber: null,
        employeeId: inputs.employeeId.isEmpty ? '00000000' : inputs.employeeId,
        date: inputs.computedAsOf,
      );
      return _descriptor(
        templateId: 'final_pay',
        inputs: inputs,
        errors: tpl.validate(inputs),
        fileName: filename,
        employeeId: scopedEmployeeId(inputs.employeeId),
        docType: docType,
        blocks: () => tpl.build(inputs),
        who: _who(inputs.employeeFullName, inputs.employeeId),
        auditDescription: (action, who) => 'Final Pay PDF $action: $who',
        auditMetadata: (action) => {
          'template_id': 'final_pay',
          'employee_id':
              inputs.employeeId.isEmpty ? null : inputs.employeeId,
          'file_name': filename,
          'action': action,
        },
      );
    }
    if (tpl is SalaryAdjustmentTemplate && _salaryAdjustment != null) {
      final inputs = _salaryAdjustment!;
      final filename = filenameForDocument(
        templateId: 'salary_adjustment',
        employeeNumber: null,
        employeeId: inputs.employeeId.isEmpty ? '00000000' : inputs.employeeId,
        date: inputs.issueDate,
      );
      return _descriptor(
        templateId: 'salary_adjustment',
        inputs: inputs,
        errors: tpl.validate(inputs),
        fileName: filename,
        employeeId: scopedEmployeeId(inputs.employeeId),
        docType: docType,
        blocks: () => tpl.build(inputs),
        who: _who(inputs.employeeFullName, inputs.employeeId),
        auditDescription: (action, who) =>
            'Salary Adjustment PDF $action: $who',
        auditMetadata: (action) => {
          'template_id': 'salary_adjustment',
          'employee_id':
              inputs.employeeId.isEmpty ? null : inputs.employeeId,
          'file_name': filename,
          'action': action,
        },
      );
    }
    if (tpl is NodTemplate && _nod != null) {
      final inputs = _nod!;
      final filename = filenameForDocument(
        templateId: 'nod',
        employeeNumber: null,
        employeeId: inputs.employeeId.isEmpty ? '00000000' : inputs.employeeId,
        date: inputs.issueDate,
      );
      return _descriptor(
        templateId: 'nod',
        inputs: inputs,
        errors: tpl.validate(inputs),
        fileName: filename,
        employeeId: scopedEmployeeId(inputs.employeeId),
        docType: docType,
        blocks: () => tpl.build(inputs),
        who: _who(inputs.employeeFullName, inputs.employeeId),
        auditDescription: (action, who) => 'NOD PDF $action: $who',
        auditMetadata: (action) => {
          'template_id': 'nod',
          'employee_id':
              inputs.employeeId.isEmpty ? null : inputs.employeeId,
          'file_name': filename,
          'action': action,
        },
      );
    }
    if (tpl is RegularizationTemplate && _regularization != null) {
      final inputs = _regularization!;
      final filename = filenameForDocument(
        templateId: 'regularization',
        employeeNumber: null,
        employeeId: inputs.employeeId.isEmpty ? '00000000' : inputs.employeeId,
        date: inputs.issueDate,
      );
      return _descriptor(
        templateId: 'regularization',
        inputs: inputs,
        errors: tpl.validate(inputs),
        fileName: filename,
        employeeId: scopedEmployeeId(inputs.employeeId),
        docType: docType,
        blocks: () => tpl.build(inputs),
        who: _who(inputs.employeeFullName, inputs.employeeId),
        auditDescription: (action, who) => 'Regularization PDF $action: $who',
        auditMetadata: (action) => {
          'template_id': 'regularization',
          'employee_id':
              inputs.employeeId.isEmpty ? null : inputs.employeeId,
          'file_name': filename,
          'action': action,
        },
      );
    }
    if (tpl is ResignationAcceptanceTemplate &&
        _resignationAcceptance != null) {
      final inputs = _resignationAcceptance!;
      final filename = filenameForDocument(
        templateId: 'resignation_acceptance',
        employeeNumber: null,
        employeeId: inputs.employeeId.isEmpty ? '00000000' : inputs.employeeId,
        date: inputs.issueDate,
      );
      return _descriptor(
        templateId: 'resignation_acceptance',
        inputs: inputs,
        errors: tpl.validate(inputs),
        fileName: filename,
        employeeId: scopedEmployeeId(inputs.employeeId),
        docType: docType,
        blocks: () => tpl.build(inputs),
        who: _who(inputs.employeeFullName, inputs.employeeId),
        auditDescription: (action, who) =>
            'Resignation Acceptance PDF $action: $who',
        auditMetadata: (action) => {
          'template_id': 'resignation_acceptance',
          'employee_id':
              inputs.employeeId.isEmpty ? null : inputs.employeeId,
          'file_name': filename,
          'action': action,
        },
      );
    }
    return null;
  }

  /// Resolve the display "who" string for audit descriptions: prefer the
  /// typed-in / autofilled full name; fall back to the short employee id.
  String _who(String fullName, String employeeId) =>
      fullName.trim().isNotEmpty
          ? fullName.trim()
          : (employeeId.isEmpty ? '(unknown employee)' : employeeId);

  /// Assembles a [_GenerateDescriptor], wiring the audit callback to the same
  /// `auditRepositoryProvider.logExport` the screen used previously.
  _GenerateDescriptor _descriptor({
    required String templateId,
    required TemplateInputs inputs,
    required List<ValidationError> errors,
    required String fileName,
    required String? employeeId,
    required DocumentTypeInfo docType,
    required List<Block> Function() blocks,
    required String who,
    required String Function(String action, String who) auditDescription,
    required Map<String, dynamic> Function(String action) auditMetadata,
  }) {
    return _GenerateDescriptor(
      templateId: templateId,
      inputs: inputs,
      errors: errors,
      fileName: fileName,
      employeeId: employeeId,
      docTypeInfo: docType,
      buildBytes: (theme) async => buildDocumentPdf(
        blocks: blocks(),
        theme: theme,
      ),
      onExported: (action) {
        ref.read(auditRepositoryProvider).logExport(
              description: auditDescription(action, who),
              entityType: 'document_template_pdf',
              metadata: auditMetadata(action),
            );
      },
    );
  }
}
