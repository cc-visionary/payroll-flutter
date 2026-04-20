import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../app/breakpoints.dart';
import '../../app/shell.dart';
import '../../core/money.dart';
import '../auth/profile_provider.dart';

/// Penalties / Cash Advances / Reimbursements — one tab each.
/// Each tab shows a stats row on top (total count + outstanding amount
/// + settled amount) and a list of rows including the employee tied to it
/// plus a settled-yet indicator ("Deducted on …", "Paid on …", progress bar).
class AdjunctsScreen extends ConsumerWidget {
  const AdjunctsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        drawer: isMobile(context) ? const AppDrawer() : null,
        appBar: AppBar(
          title: const Text('Payroll Adjuncts'),
          bottom: const TabBar(tabs: [
            Tab(text: 'Penalties'),
            Tab(text: 'Cash Advances'),
            Tab(text: 'Reimbursements'),
          ]),
        ),
        body: const TabBarView(children: [
          _AdjunctList(kind: _AdjunctKind.penalty),
          _AdjunctList(kind: _AdjunctKind.cashAdvance),
          _AdjunctList(kind: _AdjunctKind.reimbursement),
        ]),
      ),
    );
  }
}

enum _AdjunctKind { penalty, cashAdvance, reimbursement }

extension on _AdjunctKind {
  String get table => switch (this) {
        _AdjunctKind.penalty => 'penalties',
        _AdjunctKind.cashAdvance => 'cash_advances',
        _AdjunctKind.reimbursement => 'reimbursements',
      };
  String get amountKey => switch (this) {
        _AdjunctKind.penalty => 'total_amount',
        _AdjunctKind.cashAdvance => 'amount',
        _AdjunctKind.reimbursement => 'amount',
      };
  String get emptyLabel => switch (this) {
        _AdjunctKind.penalty => 'No penalties yet.',
        _AdjunctKind.cashAdvance => 'No cash advances yet.',
        _AdjunctKind.reimbursement => 'No reimbursements yet.',
      };
}

final _listProvider = FutureProvider.family<List<Map<String, dynamic>>,
    _AdjunctKind>((ref, kind) async {
  final profile = ref.watch(userProfileProvider).asData?.value;
  final employeeId =
      (profile?.isHrOrAdmin ?? false) ? null : profile?.employeeId;

  final baseSelect = 'employees(id, employee_number, first_name, last_name)';
  final select = kind == _AdjunctKind.penalty
      ? '*, $baseSelect, penalty_installments(id, installment_number, amount, is_deducted, payroll_run_id, deducted_at)'
      : '*, $baseSelect';
  var q = Supabase.instance.client.from(kind.table).select(select);
  if (employeeId != null) q = q.eq('employee_id', employeeId);
  final rows = await q.order('created_at', ascending: false).limit(200)
      as List<dynamic>;
  return rows.cast<Map<String, dynamic>>();
});

class _AdjunctList extends ConsumerWidget {
  final _AdjunctKind kind;
  const _AdjunctList({required this.kind});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(_listProvider(kind));
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
        child: Text('Error: $e', style: const TextStyle(color: Colors.red)),
      ),
      data: (rows) => RefreshIndicator(
        onRefresh: () async => ref.invalidate(_listProvider(kind)),
        child: CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              sliver: SliverToBoxAdapter(
                child: _StatsRow(kind: kind, rows: rows),
              ),
            ),
            if (rows.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Text(
                      kind.emptyLabel,
                      style: const TextStyle(color: Colors.grey),
                    ),
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                sliver: SliverList.builder(
                  itemCount: rows.length,
                  itemBuilder: (_, i) => _AdjunctCard(kind: kind, row: rows[i]),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Stats row — 4 tiles: Total · Outstanding ₱ · Settled ₱ · Needs attention
// ---------------------------------------------------------------------------

class _StatsRow extends StatelessWidget {
  final _AdjunctKind kind;
  final List<Map<String, dynamic>> rows;
  const _StatsRow({required this.kind, required this.rows});

  @override
  Widget build(BuildContext context) {
    final stats = _computeStats(kind, rows);
    final tiles = <_StatTile>[
      _StatTile(label: 'Total', value: '${rows.length}'),
      _StatTile(
        label: stats.outstandingLabel,
        value: Money.fmtPhp(stats.outstandingAmount),
        tone: _Tone.warn,
      ),
      _StatTile(
        label: stats.settledLabel,
        value: Money.fmtPhp(stats.settledAmount),
        tone: _Tone.ok,
      ),
      _StatTile(
        label: stats.attentionLabel,
        value: '${stats.attentionCount}',
        tone: stats.attentionCount > 0 ? _Tone.alert : _Tone.neutral,
      ),
    ];
    final mobile = isMobile(context);
    return LayoutBuilder(
      builder: (_, c) {
        final cols = mobile ? 2 : 4;
        final gap = 12.0;
        final itemW = (c.maxWidth - gap * (cols - 1)) / cols;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final t in tiles) SizedBox(width: itemW, child: t),
          ],
        );
      },
    );
  }
}

enum _Tone { neutral, ok, warn, alert }

class _StatTile extends StatelessWidget {
  final String label;
  final String value;
  final _Tone tone;
  const _StatTile({
    required this.label,
    required this.value,
    this.tone = _Tone.neutral,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fg = switch (tone) {
      _Tone.ok => const Color(0xFF15803D),
      _Tone.warn => const Color(0xFFB45309),
      _Tone.alert => scheme.error,
      _Tone.neutral => scheme.onSurface,
    };
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: fg,
              fontFamily: 'GeistMono',
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _Stats {
  final Decimal outstandingAmount;
  final Decimal settledAmount;
  final int attentionCount;
  final String outstandingLabel;
  final String settledLabel;
  final String attentionLabel;
  _Stats({
    required this.outstandingAmount,
    required this.settledAmount,
    required this.attentionCount,
    required this.outstandingLabel,
    required this.settledLabel,
    required this.attentionLabel,
  });
}

_Stats _computeStats(_AdjunctKind kind, List<Map<String, dynamic>> rows) {
  Decimal dec(Object? v) => Decimal.parse((v ?? '0').toString());
  switch (kind) {
    case _AdjunctKind.penalty:
      var outstanding = Decimal.zero;
      var settled = Decimal.zero;
      var active = 0;
      for (final r in rows) {
        final total = dec(r['total_amount']);
        final deducted = dec(r['total_deducted']);
        final status = (r['status'] as String? ?? '').toUpperCase();
        settled += deducted;
        if (status == 'ACTIVE') {
          outstanding += (total - deducted);
          active++;
        }
      }
      return _Stats(
        outstandingAmount: outstanding,
        settledAmount: settled,
        attentionCount: active,
        outstandingLabel: 'Outstanding',
        settledLabel: 'Deducted',
        attentionLabel: 'Active',
      );
    case _AdjunctKind.cashAdvance:
      var outstanding = Decimal.zero;
      var settled = Decimal.zero;
      var pending = 0;
      for (final r in rows) {
        final amt = dec(r['amount']);
        final isDeducted = r['is_deducted'] == true;
        final status = (r['status'] as String? ?? '').toUpperCase();
        final larkStatus =
            (r['lark_approval_status'] as String? ?? '').toUpperCase();
        if (isDeducted) {
          settled += amt;
        } else if (status != 'CANCELLED' && status != 'REJECTED') {
          outstanding += amt;
        }
        if (larkStatus == 'PENDING' || status == 'PENDING') pending++;
      }
      return _Stats(
        outstandingAmount: outstanding,
        settledAmount: settled,
        attentionCount: pending,
        outstandingLabel: 'Outstanding',
        settledLabel: 'Deducted',
        attentionLabel: 'Pending',
      );
    case _AdjunctKind.reimbursement:
      var outstanding = Decimal.zero;
      var settled = Decimal.zero;
      var pending = 0;
      for (final r in rows) {
        final amt = dec(r['amount']);
        final isPaid = r['is_paid'] == true;
        final status = (r['status'] as String? ?? '').toUpperCase();
        final larkStatus =
            (r['lark_approval_status'] as String? ?? '').toUpperCase();
        if (isPaid) {
          settled += amt;
        } else if (status != 'CANCELLED' && status != 'REJECTED') {
          outstanding += amt;
        }
        if (larkStatus == 'PENDING' || status == 'PENDING') pending++;
      }
      return _Stats(
        outstandingAmount: outstanding,
        settledAmount: settled,
        attentionCount: pending,
        outstandingLabel: 'Unpaid',
        settledLabel: 'Paid',
        attentionLabel: 'Pending',
      );
  }
}

// ---------------------------------------------------------------------------
// Row card — title + employee + date + settled-yet status + amount.
// ---------------------------------------------------------------------------

class _AdjunctCard extends StatelessWidget {
  final _AdjunctKind kind;
  final Map<String, dynamic> row;
  const _AdjunctCard({required this.kind, required this.row});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final amount = row[kind.amountKey] == null
        ? '—'
        : Money.fmtPhp(Decimal.parse(row[kind.amountKey].toString()));
    final title = _title();
    final emp = row['employees'] as Map<String, dynamic>?;
    final empNo = emp?['employee_number'] as String?;
    final empName = _empName(emp);
    final (whenLabel, whenText) = _eventDate();
    final settled = _settledLabel();

    final mobile = isMobile(context);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top: title + right-side amount & status chip
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      amount,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        fontFamily: 'GeistMono',
                      ),
                    ),
                    const SizedBox(height: 6),
                    _StatusChip(
                      label: settled.label,
                      tone: settled.tone,
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 10),
            // Meta: employee + creator + date
            DefaultTextStyle.merge(
              style: TextStyle(
                fontSize: 12,
                color: scheme.onSurfaceVariant,
              ),
              child: Wrap(
                spacing: 12,
                runSpacing: 4,
                children: [
                  if (empName != null)
                    _Meta(
                      icon: Icons.person_outline,
                      text: empNo == null ? empName : '$empName · $empNo',
                    ),
                  if (whenText != null)
                    _Meta(
                      icon: Icons.event,
                      text: '$whenLabel $whenText',
                    ),
                ],
              ),
            ),
            // Settled-yet tail — progress bar for penalties, paid/deducted-on
            // line for CA/reimbursements.
            if (kind == _AdjunctKind.penalty)
              _PenaltyProgress(row: row)
            else
              _SettledOnLine(kind: kind, row: row, compact: mobile),
          ],
        ),
      ),
    );
  }

  String _title() {
    switch (kind) {
      case _AdjunctKind.penalty:
        return row['custom_description'] as String? ?? 'Penalty';
      case _AdjunctKind.cashAdvance:
        return row['reason'] as String? ?? 'Cash Advance';
      case _AdjunctKind.reimbursement:
        final type = row['reimbursement_type'] as String?;
        final reason = row['reason'] as String?;
        if (type != null && reason != null) return '$type — $reason';
        return type ?? reason ?? 'Reimbursement';
    }
  }

  /// The most meaningful date to show on the card header — ie the date the
  /// user cares about when asking "when did this happen?" Different per
  /// kind: effective_date for penalties (PD 851 + HR audit), transaction or
  /// approval for reimbursements, approval for CA.
  (String label, String? text) _eventDate() {
    switch (kind) {
      case _AdjunctKind.penalty:
        final eff = row['effective_date'] as String?;
        return ('Effective', _fmtDayOnly(eff));
      case _AdjunctKind.cashAdvance:
        final approved = row['lark_approved_at'] as String?;
        if (approved != null) return ('Approved', _fmtDate(approved));
        return ('Requested', _fmtDate(row['created_at'] as String?));
      case _AdjunctKind.reimbursement:
        final txn = row['transaction_date'] as String?;
        if (txn != null) return ('Transaction', _fmtDayOnly(txn));
        final approved = row['lark_approved_at'] as String?;
        if (approved != null) return ('Approved', _fmtDate(approved));
        return ('Requested', _fmtDate(row['created_at'] as String?));
    }
  }

  _SettledLabel _settledLabel() {
    switch (kind) {
      case _AdjunctKind.penalty:
        final status = (row['status'] as String? ?? '').toUpperCase();
        return switch (status) {
          'COMPLETED' =>
            const _SettledLabel('Completed', _Tone.ok),
          'CANCELLED' =>
            const _SettledLabel('Cancelled', _Tone.neutral),
          _ => const _SettledLabel('Active', _Tone.warn),
        };
      case _AdjunctKind.cashAdvance:
        if (row['is_deducted'] == true) {
          return const _SettledLabel('Deducted', _Tone.ok);
        }
        final status = (row['status'] as String? ?? '').toUpperCase();
        return switch (status) {
          'CANCELLED' || 'REJECTED' =>
            _SettledLabel(status.toLowerCase(), _Tone.neutral),
          'APPROVED' => const _SettledLabel('Approved', _Tone.warn),
          _ => const _SettledLabel('Pending', _Tone.warn),
        };
      case _AdjunctKind.reimbursement:
        if (row['is_paid'] == true) {
          return const _SettledLabel('Paid', _Tone.ok);
        }
        final status = (row['status'] as String? ?? '').toUpperCase();
        return switch (status) {
          'CANCELLED' || 'REJECTED' =>
            _SettledLabel(status.toLowerCase(), _Tone.neutral),
          'APPROVED' => const _SettledLabel('Approved', _Tone.warn),
          _ => const _SettledLabel('Pending', _Tone.warn),
        };
    }
  }
}

class _SettledLabel {
  final String label;
  final _Tone tone;
  const _SettledLabel(this.label, this.tone);
}

class _StatusChip extends StatelessWidget {
  final String label;
  final _Tone tone;
  const _StatusChip({required this.label, required this.tone});

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = switch (tone) {
      _Tone.ok => (const Color(0xFFE8F3EC), const Color(0xFF1B6B33)),
      _Tone.warn => (const Color(0xFFFFF3E0), const Color(0xFF8A5A00)),
      _Tone.alert => (const Color(0xFFFBE9E9), const Color(0xFFA1261E)),
      _Tone.neutral => (const Color(0xFFEEEEF1), const Color(0xFF4B4F5C)),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: fg,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}

class _Meta extends StatelessWidget {
  final IconData icon;
  final String text;
  const _Meta({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    final color = DefaultTextStyle.of(context).style.color;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 4),
        Text(text),
      ],
    );
  }
}

class _PenaltyProgress extends StatelessWidget {
  final Map<String, dynamic> row;
  const _PenaltyProgress({required this.row});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final total = Decimal.parse((row['total_amount'] ?? '0').toString());
    final deducted = Decimal.parse((row['total_deducted'] ?? '0').toString());
    final remaining = (total - deducted);
    final ratio = total == Decimal.zero
        ? 0.0
        : (deducted.toDouble() / total.toDouble()).clamp(0.0, 1.0);
    final installments = (row['installment_count'] as num?)?.toInt();

    final installmentRows =
        (row['penalty_installments'] as List<dynamic>?)
                ?.cast<Map<String, dynamic>>() ??
            const <Map<String, dynamic>>[];
    final deductedCount =
        installmentRows.where((i) => i['is_deducted'] == true).length;
    final queuedCount = installmentRows
        .where((i) =>
            i['is_deducted'] != true && i['payroll_run_id'] != null)
        .length;
    final status = (row['status'] as String? ?? '').toUpperCase();

    // Hint explaining why the penalty is still ACTIVE: is any installment
    // already queued on a (still-DRAFT/REVIEW) payroll run, or does it need
    // to be picked up on the next compute?
    String? hint;
    if (status == 'ACTIVE' && installmentRows.isNotEmpty) {
      if (deductedCount == 0 && queuedCount == 0) {
        hint = 'No installment is on a payroll run yet — it will be picked '
            'up on the next payroll compute.';
      } else if (deductedCount == 0 && queuedCount > 0) {
        hint = '$queuedCount installment${queuedCount == 1 ? '' : 's'} '
            'queued on an unreleased payroll run.';
      } else if (queuedCount > 0) {
        hint = '$queuedCount more installment${queuedCount == 1 ? '' : 's'} '
            'queued on an unreleased run.';
      }
    }

    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: 6,
              backgroundColor: scheme.surfaceContainerHighest,
              color: const Color(0xFF15803D),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '${Money.fmtPhp(deducted)} of ${Money.fmtPhp(total)} deducted'
            '${remaining > Decimal.zero ? ' · ${Money.fmtPhp(remaining)} remaining' : ''}'
            '${installments == null ? '' : ' · $installments installment${installments == 1 ? '' : 's'}'}',
            style: TextStyle(
              fontSize: 11,
              color: scheme.onSurfaceVariant,
            ),
          ),
          if (hint != null) ...[
            const SizedBox(height: 4),
            Text(
              hint,
              style: TextStyle(
                fontSize: 11,
                fontStyle: FontStyle.italic,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SettledOnLine extends StatelessWidget {
  final _AdjunctKind kind;
  final Map<String, dynamic> row;
  final bool compact;
  const _SettledOnLine({
    required this.kind,
    required this.row,
    required this.compact,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = _text();
    if (text == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          color: scheme.onSurfaceVariant,
        ),
      ),
    );
  }

  String? _text() {
    if (kind == _AdjunctKind.cashAdvance) {
      if (row['is_deducted'] == true) {
        final when = _fmtDate(row['deducted_at'] as String?);
        return when == null ? 'Deducted' : 'Deducted · $when';
      }
      final approved = _fmtDate(row['lark_approved_at'] as String?);
      if (approved != null) return 'Lark approved · $approved';
      return null;
    }
    if (kind == _AdjunctKind.reimbursement) {
      if (row['is_paid'] == true) {
        final when = _fmtDate(row['paid_at'] as String?);
        return when == null ? 'Paid' : 'Paid · $when';
      }
      final approved = _fmtDate(row['lark_approved_at'] as String?);
      if (approved != null) return 'Lark approved · $approved';
      return null;
    }
    return null;
  }
}

String? _empName(Map<String, dynamic>? emp) {
  if (emp == null) return null;
  final first = emp['first_name'] as String? ?? '';
  final last = emp['last_name'] as String? ?? '';
  final name = '$first $last'.trim();
  return name.isEmpty ? null : name;
}

String? _fmtDayOnly(String? iso) {
  if (iso == null || iso.isEmpty) return null;
  // `date` columns come back as 'YYYY-MM-DD' — parse as local midnight to
  // avoid timezone-skew that would display the day before in UTC- zones.
  final parts = iso.split('T').first.split('-');
  if (parts.length != 3) return null;
  final y = int.tryParse(parts[0]);
  final m = int.tryParse(parts[1]);
  final d = int.tryParse(parts[2]);
  if (y == null || m == null || d == null) return null;
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  return '${months[m - 1]} $d, $y';
}

String? _fmtDate(String? iso) {
  if (iso == null || iso.isEmpty) return null;
  final dt = DateTime.tryParse(iso)?.toLocal();
  if (dt == null) return null;
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  final h = dt.hour == 0 ? 12 : (dt.hour > 12 ? dt.hour - 12 : dt.hour);
  final m = dt.minute.toString().padLeft(2, '0');
  final p = dt.hour >= 12 ? 'PM' : 'AM';
  return '${months[dt.month - 1]} ${dt.day}, ${dt.year} · $h:$m $p';
}
