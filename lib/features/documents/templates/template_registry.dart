import 'package:flutter/material.dart';

import '../blocks/block.dart';
import '../blocks/paragraph_block.dart';
import 'coe_template.dart';
import 'document_template.dart';
import 'quitclaim_template.dart';

class _PlaceholderInputs extends TemplateInputs {
  @override
  Map<String, dynamic> toDebugMap() => const {};
}

class _PlaceholderTemplate extends DocumentTemplate<_PlaceholderInputs> {
  final String _id;
  final String _name;
  final String _description;
  final IconData _icon;
  const _PlaceholderTemplate({
    required String id,
    required String name,
    required String description,
    required IconData icon,
  })  : _id = id,
        _name = name,
        _description = description,
        _icon = icon;

  @override
  String get id => _id;
  @override
  String get name => _name;
  @override
  String get description => _description;
  @override
  IconData get icon => _icon;
  @override
  int get version => 0;
  @override
  _PlaceholderInputs emptyInputs() => _PlaceholderInputs();
  @override
  Future<_PlaceholderInputs> autofill(AutofillContext ctx) async =>
      _PlaceholderInputs();
  @override
  List<Gate> gates(AutofillContext ctx) =>
      const [Gate('Template not yet implemented')];
  @override
  List<ValidationError> validate(_PlaceholderInputs inputs) =>
      const [ValidationError('_', 'not implemented')];
  @override
  List<Block> build(_PlaceholderInputs inputs) =>
      const [ParagraphBlock('Placeholder')];
}

/// Registry of all document templates. Phases 5-7 replace each
/// placeholder with the real Quitclaim/COE/NTE template; the picker
/// reads this list directly.
const List<DocumentTemplate> kTemplates = [
  QuitclaimTemplate(),
  CoeTemplate(),
  _PlaceholderTemplate(
    id: 'nte',
    name: 'Notice to Explain',
    description: 'Disciplinary notice with charges and applicable violations.',
    icon: Icons.report_outlined,
  ),
];

DocumentTemplate? findTemplateById(String id) {
  for (final t in kTemplates) {
    if (t.id == id) return t;
  }
  return null;
}
