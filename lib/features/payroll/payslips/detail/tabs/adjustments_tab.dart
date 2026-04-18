import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../core/money.dart';
import '../../../../../data/repositories/payroll_repository.dart';
import '../../../runs/detail/providers.dart' as run_providers;
import '../providers.dart';

class AdjustmentsTab extends ConsumerStatefulWidget {
  final String runId;
  final String employeeId;
  final bool canEdit;
  const AdjustmentsTab({
    super.key,
    required this.runId,
    required this.employeeId,
    required this.canEdit,
  });

  @override
  ConsumerState<AdjustmentsTab> createState() => _AdjustmentsTabState();
}

class _AdjustmentsTabState extends ConsumerState<AdjustmentsTab> {
  bool _showForm = false;
  String? _editingId;
  String _initialType = 'EARNING';
  String _initialDesc = '';
  String _initialAmount = '';
  bool _saving = false;

  void _openAddForm() {
    setState(() {
      _showForm = true;
      _editingId = null;
      _initialType = 'EARNING';
      _initialDesc = '';
      _initialAmount = '';
    });
  }

  void _openEditForm(Map<String, dynamic> row) {
    setState(() {
      _showForm = true;
      _editingId = row['id'] as String;
      _initialType = (row['category'] as String) == 'ADJUSTMENT_ADD'
          ? 'EARNING'
          : 'DEDUCTION';
      _initialDesc = row['description'] as String? ?? '';
      _initialAmount = (row['amount'] ?? '').toString();
    });
  }

  void _closeForm() {
    setState(() {
      _showForm = false;
      _editingId = null;
    });
  }

  Future<void> _save({
    required String type,
    required String description,
    required String amountText,
  }) async {
    final desc = description.trim();
    // Strip formatting commas (e.g. `1,782.00` → `1782.00`) before parsing.
    final amountStr = amountText.replaceAll(',', '').trim();
    if (desc.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Description is required.')),
      );
      return;
    }
    if (amountStr.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Amount is required.')),
      );
      return;
    }
    final amountDec = Decimal.tryParse(amountStr);
    if (amountDec == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Amount must be a valid number.')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      final repo = ref.read(payrollRepositoryProvider);
      final category =
          type == 'EARNING' ? 'ADJUSTMENT_ADD' : 'ADJUSTMENT_DEDUCT';
      if (_editingId == null) {
        await repo.insertManualAdjustment(
          runId: widget.runId,
          employeeId: widget.employeeId,
          category: category,
          description: desc,
          amount: amountDec.toString(),
        );
      } else {
        await repo.updateManualAdjustment(
          id: _editingId!,
          category: category,
          description: desc,
          amount: amountDec.toString(),
        );
      }
      ref.invalidate(
        manualAdjustmentsProvider(
          ManualAdjustmentsKey(
            runId: widget.runId,
            employeeId: widget.employeeId,
          ),
        ),
      );
      ref.invalidate(run_providers.payrollRunDetailProvider(widget.runId));
      if (mounted) _closeForm();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Save failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _confirmDelete(Map<String, dynamic> row) async {
    final ok = await showDialog<bool>(
          context: context,
          builder: (c) => AlertDialog(
            title: const Text('Delete adjustment?'),
            content: Text(
              'Remove "${row['description']}" (${Money.fmtPhp(Decimal.parse(row['amount'].toString()))})?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(c, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(c, true),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFDC2626),
                ),
                child: const Text('Delete'),
              ),
            ],
          ),
        ) ??
        false;
    if (!ok || !mounted) return;
    await ref
        .read(payrollRepositoryProvider)
        .deleteManualAdjustment(row['id'] as String);
    ref.invalidate(
      manualAdjustmentsProvider(
        ManualAdjustmentsKey(
          runId: widget.runId,
          employeeId: widget.employeeId,
        ),
      ),
    );
    ref.invalidate(run_providers.payrollRunDetailProvider(widget.runId));
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(
      manualAdjustmentsProvider(
        ManualAdjustmentsKey(
          runId: widget.runId,
          employeeId: widget.employeeId,
        ),
      ),
    );
    return async.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Padding(
        padding: const EdgeInsets.all(24),
        child: Text('Error: $e', style: const TextStyle(color: Colors.red)),
      ),
      data: (rows) => ListView(
        padding: const EdgeInsets.symmetric(vertical: 16),
        children: [
          _Card(rows: rows, child: _body(rows)),
        ],
      ),
    );
  }

  Widget _body(List<Map<String, dynamic>> rows) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
          child: Row(
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Commissions & Manual Adjustments',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Add commissions, incentives, or other manual adjustments for this pay period.',
                      style: TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
                    ),
                  ],
                ),
              ),
              if (widget.canEdit && !_showForm)
                FilledButton.icon(
                  onPressed: _openAddForm,
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Add Item'),
                ),
            ],
          ),
        ),
        if (_showForm && widget.canEdit) ...[
          Divider(height: 1, color: Theme.of(context).dividerColor),
          // Keyed by editingId so opening a different row for edit resets the
          // form state (controllers re-initialise). Without the key the old
          // description/amount would bleed into the next open.
          _Form(
            key: ValueKey(_editingId ?? 'new'),
            initialType: _initialType,
            initialDescription: _initialDesc,
            initialAmount: _initialAmount,
            isEditing: _editingId != null,
            saving: _saving,
            onCancel: _closeForm,
            onSave: _save,
          ),
        ],
        Divider(height: 1, color: Theme.of(context).dividerColor),
        _TableHeader(),
        Divider(height: 1, color: Theme.of(context).dividerColor),
        if (rows.isEmpty)
          Padding(
            padding: const EdgeInsets.all(32),
            child: Center(
              child: Text(
                'No adjustments yet.',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          )
        else
          for (final r in rows) ...[
            _Row(
              row: r,
              canEdit: widget.canEdit,
              onEdit: () => _openEditForm(r),
              onDelete: () => _confirmDelete(r),
            ),
            Divider(height: 1, color: Theme.of(context).dividerColor),
          ],
        _TotalRow(rows: rows),
        if (!widget.canEdit)
          Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFFEFCE8),
              border: Border.all(color: const Color(0xFFFDE68A)),
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Text(
              'Note: This payroll run is finalized. Commissions can no longer '
              'be edited. To make changes, the payroll must be reopened.',
              style: TextStyle(fontSize: 12),
            ),
          ),
      ],
    );
  }
}

class _Card extends StatelessWidget {
  final List<Map<String, dynamic>> rows;
  final Widget child;
  const _Card({required this.rows, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(8),
      ),
      child: child,
    );
  }
}

/// Inline add/edit form for a manual adjustment.
///
/// Owns its own `TextEditingController`s + dropdown state so typing isn't
/// vulnerable to parent-widget rebuilds (e.g. from unrelated `ref.watch`
/// invalidations). The prior version held controllers on the parent
/// `_AdjustmentsTabState` — which was *technically* fine but interacted
/// badly with the Linux desktop IME when special characters like `[` / `]`
/// were typed, making backspaces appear to "do nothing". Keyed by the
/// row-id on the parent side so opening a different row resets cleanly.
class _Form extends StatefulWidget {
  final String initialType;
  final String initialDescription;
  final String initialAmount;
  final bool isEditing;
  final bool saving;
  final VoidCallback onCancel;
  final Future<void> Function({
    required String type,
    required String description,
    required String amountText,
  }) onSave;

  const _Form({
    super.key,
    required this.initialType,
    required this.initialDescription,
    required this.initialAmount,
    required this.isEditing,
    required this.saving,
    required this.onCancel,
    required this.onSave,
  });

  @override
  State<_Form> createState() => _FormState();
}

class _FormState extends State<_Form> {
  late String _type;
  late final TextEditingController _descCtrl;
  late final TextEditingController _amountCtrl;
  late final FocusNode _descFocus;
  late final FocusNode _amountFocus;

  @override
  void initState() {
    super.initState();
    _type = widget.initialType;
    _descCtrl = TextEditingController(text: widget.initialDescription);
    _amountCtrl = TextEditingController(text: widget.initialAmount);
    _descFocus = FocusNode(debugLabel: 'adjustment-description');
    _amountFocus = FocusNode(debugLabel: 'adjustment-amount');
  }

  @override
  void dispose() {
    _descCtrl.dispose();
    _amountCtrl.dispose();
    _descFocus.dispose();
    _amountFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 160,
                child: DropdownButtonFormField<String>(
                  // `initialValue` is one-shot in Flutter 3.33+ (`value` is
                  // deprecated). That's OK here because the outer `_Form`
                  // is keyed by row id — selecting a different row throws
                  // the whole form away and re-creates this dropdown with
                  // the new initial type. We keep a local `_type` mirror
                  // so onSave() can read the current selection.
                  initialValue: _type,
                  decoration: const InputDecoration(
                    labelText: 'Type',
                    border: OutlineInputBorder(),
                    isDense: true,
                    helperText: ' ',
                    helperStyle: TextStyle(fontSize: 11),
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 'EARNING',
                      child: Text('Earning (+)'),
                    ),
                    DropdownMenuItem(
                      value: 'DEDUCTION',
                      child: Text('Deduction (-)'),
                    ),
                  ],
                  onChanged: (v) =>
                      v == null ? null : setState(() => _type = v),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                // Scoped FocusTraversalGroup + explicit Shortcuts keep
                // Backspace / Ctrl+V / Ctrl+C routed to the active TextField
                // instead of bubbling up to ancestors (the parent
                // NestedScrollView + TabBarView on some Linux desktop
                // engines otherwise swallow printable Backspace and paste
                // events once a child widget calls FocusManager.requestFocus
                // during a keyboard-driven rebuild).
                child: TextField(
                  controller: _descCtrl,
                  focusNode: _descFocus,
                  keyboardType: TextInputType.text,
                  textInputAction: TextInputAction.next,
                  onSubmitted: (_) => _amountFocus.requestFocus(),
                  // IBus / fcitx on Linux can hold characters like `[` or
                  // `]` in a composition buffer; backspace then targets the
                  // invisible composition instead of the visible text.
                  // Disabling autocorrect / suggestions / personalised
                  // learning forces each keystroke to commit immediately.
                  autocorrect: false,
                  enableSuggestions: false,
                  enableIMEPersonalizedLearning: false,
                  enableInteractiveSelection: true,
                  decoration: const InputDecoration(
                    labelText: 'Description',
                    border: OutlineInputBorder(),
                    isDense: true,
                    helperText: ' ',
                    helperStyle: TextStyle(fontSize: 11),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 180,
                child: _AmountField(controller: _amountCtrl),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: widget.saving ? null : widget.onCancel,
                child: const Text('Cancel'),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: widget.saving
                    ? null
                    : () => widget.onSave(
                          type: _type,
                          description: _descCtrl.text,
                          amountText: _amountCtrl.text,
                        ),
                child: Text(widget.isEditing ? 'Update' : 'Add'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TableHeader extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurfaceVariant;
    final style = TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w600,
      color: color,
      letterSpacing: 0.4,
    );
    return Container(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: Row(
        children: [
          SizedBox(width: 100, child: Text('TYPE', style: style)),
          Expanded(child: Text('DESCRIPTION', style: style)),
          SizedBox(
              width: 140,
              child: Align(
                alignment: Alignment.centerRight,
                child: Text('AMOUNT', style: style),
              )),
          SizedBox(width: 120, child: Text('DATE ADDED', style: style)),
          SizedBox(width: 80, child: Text('ACTIONS', style: style)),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  final Map<String, dynamic> row;
  final bool canEdit;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  const _Row({
    required this.row,
    required this.canEdit,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final category = row['category'] as String? ?? 'ADJUSTMENT_ADD';
    final isEarning = category == 'ADJUSTMENT_ADD';
    final amount = Decimal.parse((row['amount'] ?? '0').toString());
    final created = row['created_at'] as String?;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        children: [
          SizedBox(
            width: 100,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(
                  color: isEarning
                      ? const Color(0xFFDCFCE7)
                      : const Color(0xFFFEE2E2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  isEarning ? 'Earning' : 'Deduction',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: isEarning
                        ? const Color(0xFF166534)
                        : const Color(0xFF991B1B),
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: Text(
              row['description'] as String? ?? '—',
              style: const TextStyle(fontSize: 13),
            ),
          ),
          SizedBox(
            width: 140,
            child: Align(
              alignment: Alignment.centerRight,
              child: Text(
                '${isEarning ? '' : '-'}${Money.fmtPhp(amount)}',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: isEarning
                      ? const Color(0xFF16A34A)
                      : const Color(0xFFDC2626),
                ),
              ),
            ),
          ),
          SizedBox(
            width: 120,
            child: Text(
              created == null ? '—' : _fmtShort(DateTime.parse(created)),
              style: const TextStyle(fontSize: 12),
            ),
          ),
          SizedBox(
            width: 80,
            child: canEdit
                ? Row(
                    children: [
                      IconButton(
                        tooltip: 'Edit',
                        icon: const Icon(Icons.edit_outlined, size: 16),
                        onPressed: onEdit,
                        visualDensity: VisualDensity.compact,
                      ),
                      IconButton(
                        tooltip: 'Delete',
                        icon: const Icon(Icons.delete_outline, size: 16),
                        color: const Color(0xFFDC2626),
                        onPressed: onDelete,
                        visualDensity: VisualDensity.compact,
                      ),
                    ],
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  static String _fmtShort(DateTime d) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[d.month - 1]} ${d.day}, ${d.year}';
  }
}

class _TotalRow extends StatelessWidget {
  final List<Map<String, dynamic>> rows;
  const _TotalRow({required this.rows});

  @override
  Widget build(BuildContext context) {
    var total = Decimal.zero;
    for (final r in rows) {
      final cat = r['category'] as String;
      final amt = Decimal.parse((r['amount'] ?? '0').toString());
      total = cat == 'ADJUSTMENT_ADD' ? total + amt : total - amt;
    }
    return Container(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      child: Row(
        children: [
          const Expanded(
            child: Text(
              'Total',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Text(
            Money.fmtPhp(total),
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: total >= Decimal.zero
                  ? const Color(0xFF16A34A)
                  : const Color(0xFFDC2626),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Amount input with live thousands formatting + inline validation.
// ---------------------------------------------------------------------------

/// Text field for entering a monetary amount. Auto-formats with thousands
/// commas as the user types (`1234.5` → `1,234.5`), and shows an inline
/// error when the value can't be parsed as a non-negative decimal. The
/// parent reads the raw controller text and strips commas before parsing
/// with `Decimal.tryParse`.
class _AmountField extends StatefulWidget {
  final TextEditingController controller;
  const _AmountField({required this.controller});

  @override
  State<_AmountField> createState() => _AmountFieldState();
}

class _AmountFieldState extends State<_AmountField> {
  String? _errorText;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_validate);
    // Format any pre-populated text (Edit flow) on first paint.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final current = widget.controller.text;
      if (current.isNotEmpty) {
        widget.controller.value = _formatValue(current);
      }
      _validate();
    });
  }

  @override
  void dispose() {
    widget.controller.removeListener(_validate);
    super.dispose();
  }

  void _validate() {
    final raw = widget.controller.text.replaceAll(',', '').trim();
    String? err;
    if (raw.isEmpty) {
      err = null;
    } else {
      final parsed = Decimal.tryParse(raw);
      if (parsed == null) {
        err = 'Enter a valid number';
      } else if (parsed < Decimal.zero) {
        err = 'Must be zero or more';
      }
    }
    if (err != _errorText) setState(() => _errorText = err);
  }

  static TextEditingValue _formatValue(String rawText) {
    final stripped = rawText.replaceAll(',', '');
    if (stripped.isEmpty) {
      return const TextEditingValue();
    }
    // Keep only digits + one dot; bail (leave untouched) on anything else
    // so the validator can surface the error.
    final allowed = RegExp(r'^[0-9]*\.?[0-9]*$');
    if (!allowed.hasMatch(stripped)) {
      return TextEditingValue(
        text: stripped,
        selection: TextSelection.collapsed(offset: stripped.length),
      );
    }
    final dot = stripped.indexOf('.');
    final intPart = dot == -1 ? stripped : stripped.substring(0, dot);
    final fracPart = dot == -1 ? '' : stripped.substring(dot);
    final grouped = _groupThousands(intPart);
    final formatted = '$grouped$fracPart';
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }

  static String _groupThousands(String digits) {
    if (digits.length <= 3) return digits;
    final buf = StringBuffer();
    final rem = digits.length % 3;
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (i - rem) % 3 == 0) buf.write(',');
      buf.write(digits[i]);
    }
    return buf.toString();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: widget.controller,
      keyboardType:
          const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [_ThousandsInputFormatter()],
      // Same IME-hardening as the Description field — keeps backspace +
      // paste routed directly to the field instead of the IBus/fcitx
      // composition buffer on Linux desktop.
      autocorrect: false,
      enableSuggestions: false,
      enableIMEPersonalizedLearning: false,
      decoration: InputDecoration(
        labelText: 'Amount',
        border: const OutlineInputBorder(),
        isDense: true,
        prefixText: '₱ ',
        errorText: _errorText,
        helperText: _errorText == null ? ' ' : null, // reserve vertical space
        helperStyle: const TextStyle(fontSize: 11),
      ),
    );
  }
}

/// Inserts thousands commas as the user types and re-positions the caret
/// so typing feels natural. Strips everything that isn't a digit or a
/// single dot. Keeps empty input untouched so placeholder + validation can
/// render cleanly.
class _ThousandsInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    final text = newValue.text;
    if (text.isEmpty) return newValue;

    // Count "real" chars (digits + dot) before the caret so we can
    // reposition it after we re-insert commas.
    final charsBeforeCaret = text
        .substring(0, newValue.selection.end.clamp(0, text.length))
        .replaceAll(',', '')
        .length;

    // Strip non-numeric (but allow a single dot).
    final cleaned = StringBuffer();
    var sawDot = false;
    for (final ch in text.split('')) {
      if (ch == '.') {
        if (sawDot) continue;
        sawDot = true;
        cleaned.write(ch);
      } else if (ch.codeUnitAt(0) >= 0x30 && ch.codeUnitAt(0) <= 0x39) {
        cleaned.write(ch);
      }
      // commas / other chars are dropped — they'll be re-inserted below.
    }
    final stripped = cleaned.toString();
    if (stripped.isEmpty) {
      return const TextEditingValue();
    }

    // Re-group. Keep the fractional portion (after the dot) untouched.
    final dot = stripped.indexOf('.');
    final intPart = dot == -1 ? stripped : stripped.substring(0, dot);
    final fracPart = dot == -1 ? '' : stripped.substring(dot);
    final grouped = _AmountFieldState._groupThousands(intPart);
    final formatted = '$grouped$fracPart';

    // Translate the logical caret (chars before caret, ignoring commas)
    // into an offset in the formatted string.
    var realCount = 0;
    var offset = formatted.length;
    for (var i = 0; i < formatted.length; i++) {
      if (formatted[i] == ',') continue;
      if (realCount == charsBeforeCaret) {
        offset = i;
        break;
      }
      realCount++;
    }
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: offset),
    );
  }
}
