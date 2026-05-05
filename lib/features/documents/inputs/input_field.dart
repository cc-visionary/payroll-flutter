import 'package:flutter/material.dart';

/// State of a value that may be autofilled or manually entered.
sealed class FieldValue<T> {
  const FieldValue();
  T? get value;
}

class AutofilledValue<T> extends FieldValue<T> {
  @override
  final T value;
  final String source;
  const AutofilledValue(this.value, {required this.source});
}

class ManualValue<T> extends FieldValue<T> {
  @override
  final T? value;
  const ManualValue(this.value);
}

class BlankValue<T> extends FieldValue<T> {
  const BlankValue();
  @override
  T? get value => null;
}

/// Wraps any input field with the locked-with-unlock UX.
///
/// - [Autofilled] state shows a read-only chip with [source] caption and
///   an "Override" button that switches to manual.
/// - [ManualValue] state shows the live editable child + a small
///   warning banner explaining the override.
/// - [BlankValue] state shows the editable child without warning, and
///   may include a [warningWhenBlank] banner if the autofill source
///   was missing entirely.
class LockableField<T> extends StatelessWidget {
  final String label;
  final FieldValue<T> value;
  final String Function(T) display;
  final Widget editor;
  final VoidCallback onOverride;
  final String? warningWhenBlank;

  const LockableField({
    super.key,
    required this.label,
    required this.value,
    required this.display,
    required this.editor,
    required this.onOverride,
    this.warningWhenBlank,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final v = value;
    if (v is AutofilledValue<T>) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: theme.textTheme.labelLarge
                  ?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: theme.dividerColor),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(display(v.value)),
                      const SizedBox(height: 2),
                      Text(v.source,
                          style: TextStyle(
                            fontSize: 11,
                            color: theme.colorScheme.onSurfaceVariant,
                          )),
                    ],
                  ),
                ),
                TextButton(
                    onPressed: onOverride, child: const Text('Override')),
              ],
            ),
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: theme.textTheme.labelLarge
                ?.copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        editor,
        if (v is ManualValue<T>) ...[
          const SizedBox(height: 4),
          Text('Manual override — autofill no longer applied.',
              style: TextStyle(
                fontSize: 11,
                color: theme.colorScheme.tertiary,
              )),
        ],
        if (v is BlankValue<T> &&
            warningWhenBlank != null &&
            warningWhenBlank!.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(warningWhenBlank!,
              style: TextStyle(
                fontSize: 11,
                color: theme.colorScheme.error,
              )),
        ],
      ],
    );
  }
}
