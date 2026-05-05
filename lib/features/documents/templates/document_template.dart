import 'package:flutter/material.dart' show IconData;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/employee.dart';
import '../../../data/models/hiring_entity.dart';
import '../blocks/block.dart';

/// Read-only context handed to a template's autofill / gates methods.
/// `ref` is provided so a template can pull from any Riverpod provider
/// (employment events, payslip aggregates, etc.).
class AutofillContext {
  final Employee? employee;
  final HiringEntity? company;
  final WidgetRef ref;
  const AutofillContext({this.employee, this.company, required this.ref});
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

  I emptyInputs();
  Future<I> autofill(AutofillContext ctx);
  List<Gate> gates(AutofillContext ctx);
  List<ValidationError> validate(I inputs);
  List<Block> build(I inputs);
}
