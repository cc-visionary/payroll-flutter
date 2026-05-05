import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class DateField extends StatelessWidget {
  final DateTime? value;
  final bool locked;
  final ValueChanged<DateTime?> onChanged;
  const DateField({
    super.key,
    required this.value,
    required this.locked,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('MMMM d, yyyy');
    return InkWell(
      onTap: locked
          ? null
          : () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: value ?? DateTime.now(),
                firstDate: DateTime(2000),
                lastDate: DateTime(2100),
              );
              if (picked != null) onChanged(picked);
            },
      child: InputDecorator(
        decoration: const InputDecoration(
          border: OutlineInputBorder(),
          isDense: true,
          suffixIcon: Icon(Icons.calendar_today_outlined, size: 18),
        ),
        child: Text(value == null ? 'Pick a date' : fmt.format(value!)),
      ),
    );
  }
}
