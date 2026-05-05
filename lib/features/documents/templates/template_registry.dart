import 'coe_template.dart';
import 'document_template.dart';
import 'nte_template.dart';
import 'quitclaim_template.dart';

/// Registry of all document templates. The picker reads this list directly.
const List<DocumentTemplate> kTemplates = [
  QuitclaimTemplate(),
  CoeTemplate(),
  NteTemplate(),
];

DocumentTemplate? findTemplateById(String id) {
  for (final t in kTemplates) {
    if (t.id == id) return t;
  }
  return null;
}
