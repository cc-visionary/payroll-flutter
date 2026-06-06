import 'package:flutter/material.dart';

import 'document_template.dart';
import 'template_registry.dart';

/// A dropdown field for choosing a document template, grouped by
/// [DocumentCategory] with non-selectable section headers. Shared by the
/// bulk-generate flow and the per-employee generate flow so segregation stays
/// consistent everywhere a template is picked.
///
/// Headers are rendered as disabled [DropdownMenuEntry]s — they show but can't
/// be selected. Categories with no matching template (after [filter]) are
/// hidden entirely.
class TemplatePickerField extends StatelessWidget {
  /// Currently-selected template id, or null when nothing is chosen yet.
  final String? selectedId;

  /// Called with the chosen template id. Header rows never fire this.
  final ValueChanged<String> onSelected;

  /// Optional predicate to limit which templates appear (e.g. bulk-capable).
  final bool Function(DocumentTemplate)? filter;

  final bool enabled;
  final String? hintText;

  const TemplatePickerField({
    super.key,
    required this.selectedId,
    required this.onSelected,
    this.filter,
    this.enabled = true,
    this.hintText,
  });

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    // Cap the menu height so a long, grouped list stays scrollable inside the
    // viewport rather than running off the bottom of the screen. Scales with
    // window height but stays within sane bounds for small/large displays.
    final menuHeight =
        (MediaQuery.sizeOf(context).height * 0.6).clamp(280.0, 520.0).toDouble();
    final entries = <DropdownMenuEntry<String>>[];

    for (final cat in kDocumentCategories) {
      final templates = filter == null
          ? cat.templates
          : cat.templates.where(filter!).toList();
      if (templates.isEmpty) continue;

      // Non-selectable category header (disabled entry).
      entries.add(
        DropdownMenuEntry<String>(
          value: '__header_${cat.id}',
          label: cat.label,
          enabled: false,
          labelWidget: Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Text(
              cat.label.toUpperCase(),
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
                color: muted,
              ),
            ),
          ),
        ),
      );

      for (final t in templates) {
        entries.add(
          DropdownMenuEntry<String>(
            value: t.id,
            label: t.name,
            labelWidget: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t.name,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                Text(
                  t.description,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, color: muted),
                ),
              ],
            ),
          ),
        );
      }
    }

    return DropdownMenu<String>(
      initialSelection: selectedId,
      enabled: enabled,
      requestFocusOnTap: false,
      enableSearch: false,
      expandedInsets: EdgeInsets.zero,
      menuHeight: menuHeight,
      hintText: hintText,
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(),
        isDense: true,
      ),
      dropdownMenuEntries: entries,
      onSelected: (value) {
        if (value == null || value.startsWith('__header_')) return;
        onSelected(value);
      },
    );
  }
}
