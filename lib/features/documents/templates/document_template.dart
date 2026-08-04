import 'package:flutter/material.dart' show IconData;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/employee.dart';
import '../../../data/models/hiring_entity.dart';
import '../blocks/block.dart';

/// Resolved signatory defaults for autofill: the employee flagged for a
/// signing capacity, reduced to what templates print. `title` null →
/// templates keep their per-document default role text.
class SignatoryInfo {
  final String name;
  final String? title;
  final String? signaturePngB64;
  const SignatoryInfo({required this.name, this.title, this.signaturePngB64});
}

/// Read-only context handed to a template's autofill / gates methods.
/// `ref` is provided so a template can pull from any Riverpod provider
/// (employment events, payslip aggregates, etc.).
///
/// Exactly one of [employee] or [applicantId] should be set when the template
/// supports both modes (e.g. EmploymentContractTemplate). Templates that only
/// know about employees can ignore [applicantId].
class AutofillContext {
  final Employee? employee;
  final HiringEntity? company;
  final WidgetRef ref;
  /// Set when generating a document for a hiring applicant rather than an
  /// existing employee. The template is responsible for reading the Applicant
  /// from [applicantByIdProvider] using this id.
  final String? applicantId;

  /// The specific `compensation_changes.id` this document belongs to, when the
  /// generation was launched from a compensation/role-change workflow. The
  /// salary-adjustment template selects THIS change from the employee's list
  /// (rather than defaulting to the newest) so an older change's notice renders
  /// its own salary/mode. Null when not launched from such a workflow.
  final String? compensationChangeId;

  /// Flagged authorized signatories (employees.is_hr_signatory /
  /// is_legal_signatory). Null when unassigned or not loaded — templates
  /// fall back to the hiring entity's text defaults.
  final SignatoryInfo? hrSignatory;
  final SignatoryInfo? legalSignatory;
  const AutofillContext({
    this.employee,
    this.company,
    required this.ref,
    this.applicantId,
    this.compensationChangeId,
    this.hrSignatory,
    this.legalSignatory,
  });
}

/// Hard block surfaced at the picker step. A non-empty list from
/// [DocumentTemplate.gates] grays the template card with [reason] as
/// the tooltip.
class Gate {
  final String reason;
  const Gate(this.reason);
}

/// Per-field validation error. The form highlights `field`; the
/// preview pane suppresses rendering while any errors exist.
class ValidationError {
  final String field;
  final String message;
  const ValidationError(this.field, this.message);
}

/// Marker base class so each template's input record is type-safe.
/// `toDebugMap` is for logs only — nothing is persisted in v1.
abstract class TemplateInputs {
  Map<String, dynamic> toDebugMap();

  /// Full, JSON-serializable snapshot of the template's inputs. Used to
  /// persist generation parameters in `employee_documents.generation_options`.
  /// `DateTime` → ISO-8601, `Decimal` → string, enums → `.name`. Binary
  /// fields (e.g. `logoBytes`) are intentionally excluded.
  Map<String, dynamic> toJson();
}

/// A code-defined document template. Each template:
/// 1. Declares its identity ([id], [name], [icon], [version]).
/// 2. Provides [emptyInputs] for the form's initial state.
/// 3. Pulls autofill data via [autofill].
/// 4. Surfaces hard blocks via [gates] (used by the picker).
/// 5. Validates inputs via [validate] (drives the preview gate).
/// 6. Renders to a `List<Block>` via [build] for the PDF builder.
abstract class DocumentTemplate<I extends TemplateInputs> {
  const DocumentTemplate();
  String get id;
  String get name;
  String get description;
  IconData get icon;
  int get version;

  /// Whether this template can be generated for many employees at once via
  /// the bulk-generate flow. Only fully-autofill templates (no unique
  /// per-employee manual input) opt in by overriding to `true`.
  bool get supportsBulk => false;

  I emptyInputs();
  Future<I> autofill(AutofillContext ctx);
  List<Gate> gates(AutofillContext ctx);
  List<ValidationError> validate(I inputs);
  List<Block> build(I inputs);
}
