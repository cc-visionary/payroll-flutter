import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/breakpoints.dart';
import '../../data/models/employee.dart';
import '../../data/models/employee_bank_account.dart';
import '../../data/repositories/employee_bank_account_repository.dart';
import '../../data/repositories/employee_repository.dart';
import '../../data/repositories/role_scorecard_repository.dart';
import '../auth/profile_provider.dart';
import '../payroll/constants.dart';

/// Create/edit form for an Employee.
/// - /employees/new    → create
/// - /employees/:id    → edit existing
class EmployeeFormScreen extends ConsumerStatefulWidget {
  final String? employeeId;
  const EmployeeFormScreen({super.key, this.employeeId});

  @override
  ConsumerState<EmployeeFormScreen> createState() => _EmployeeFormScreenState();
}

class _EmployeeFormScreenState extends ConsumerState<EmployeeFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _empNo = TextEditingController();
  final _firstName = TextEditingController();
  final _middleName = TextEditingController();
  final _lastName = TextEditingController();
  final _workEmail = TextEditingController();
  final _mobile = TextEditingController();

  String? _roleScorecardId;
  String? _paymentSourceAccount;
  String? _origPaymentSourceAccount;
  String _employmentType = 'PROBATIONARY';
  String _employmentStatus = 'ACTIVE';
  DateTime _hireDate = DateTime.now();
  DateTime? _regularizationDate;
  bool _isRankAndFile = true;
  bool _isOtEligible = true;
  bool _isNdEligible = true;
  bool _isHolidayEligible = true;

  // Admin-only payroll overrides
  bool _taxOnFullEarnings = false;
  final _declaredWage = TextEditingController();
  String _declaredWageType = 'MONTHLY';
  DateTime? _declaredWageEffectiveAt;
  final _declaredWageReason = TextEditingController();
  // Snapshot of original values so we only write when dirty
  bool _origTaxOnFull = false;
  String? _origDeclaredWage;
  String? _origDeclaredWageType;
  DateTime? _origDeclaredWageEffectiveAt;
  String? _origDeclaredWageReason;

  bool _loading = false;
  String? _error;
  Employee? _existing;

  bool get _isEdit => widget.employeeId != null;

  @override
  void initState() {
    super.initState();
    if (_isEdit) {
      Future.microtask(_loadExisting);
    }
  }

  Future<void> _loadExisting() async {
    setState(() => _loading = true);
    try {
      final e = await ref.read(employeeRepositoryProvider).byId(widget.employeeId!);
      if (e == null) {
        setState(() => _error = 'Employee not found');
        return;
      }
      _existing = e;
      _empNo.text = e.employeeNumber;
      _firstName.text = e.firstName;
      _middleName.text = e.middleName ?? '';
      _lastName.text = e.lastName;
      _roleScorecardId = e.roleScorecardId;
      _paymentSourceAccount = e.paymentSourceAccount;
      _origPaymentSourceAccount = e.paymentSourceAccount;
      _workEmail.text = e.workEmail ?? '';
      _mobile.text = e.mobileNumber ?? '';
      _employmentType = e.employmentType;
      _employmentStatus = e.employmentStatus;
      _hireDate = e.hireDate;
      _regularizationDate = e.regularizationDate;
      _isRankAndFile = e.isRankAndFile;
      _isOtEligible = e.isOtEligible;
      _isNdEligible = e.isNdEligible;
      _isHolidayEligible = e.isHolidayPayEligible;
      _taxOnFullEarnings = e.taxOnFullEarnings;
      _origTaxOnFull = e.taxOnFullEarnings;
      _declaredWage.text = e.declaredWageOverride?.toString() ?? '';
      _origDeclaredWage = e.declaredWageOverride?.toString();
      _declaredWageType = e.declaredWageType ?? 'MONTHLY';
      _origDeclaredWageType = e.declaredWageType;
      _declaredWageEffectiveAt = e.declaredWageEffectiveAt;
      _origDeclaredWageEffectiveAt = e.declaredWageEffectiveAt;
      _declaredWageReason.text = e.declaredWageReason ?? '';
      _origDeclaredWageReason = e.declaredWageReason;
      setState(() {});
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final profile = ref.read(userProfileProvider).asData?.value;
    if (profile == null) return;
    final canEditTax = profile.isHrOrAdmin;
    final canEditWage = profile.appRole == AppRole.SUPER_ADMIN;
    final taxDirty = canEditTax && _taxOnFullEarnings != _origTaxOnFull;
    final wageText = _declaredWage.text.trim();
    final wageCurrent = wageText.isEmpty ? null : wageText;
    final wageDirty = canEditWage &&
        (wageCurrent != _origDeclaredWage ||
            _declaredWageType != (_origDeclaredWageType ?? 'MONTHLY') ||
            _declaredWageEffectiveAt != _origDeclaredWageEffectiveAt ||
            _declaredWageReason.text.trim() != (_origDeclaredWageReason ?? ''));

    if (wageDirty) {
      final confirmed = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Confirm declared wage override'),
              content: const Text(
                'Changing declared wage override affects statutory and tax calculations. '
                'This action is audited. Continue?',
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Confirm')),
              ],
            ),
          ) ??
          false;
      if (!confirmed) return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      // Job title + department are derived from the selected role scorecard
      // so they stay in sync with the role. Empty string when no role linked.
      final cards = ref.read(roleScorecardListProvider).asData?.value ?? const [];
      final selectedCard = _roleScorecardId == null
          ? null
          : cards.where((c) => c.id == _roleScorecardId).cast<dynamic>().firstOrNull;
      final derivedJobTitle = selectedCard?.jobTitle as String?;
      final derivedDepartmentId = selectedCard?.departmentId as String?;

      await ref.read(employeeRepositoryProvider).upsert(
            id: _existing?.id,
            companyId: _existing?.companyId ?? profile.companyId,
            employeeNumber: _empNo.text.trim(),
            firstName: _firstName.text.trim(),
            middleName: _middleName.text.trim().isEmpty ? null : _middleName.text.trim(),
            lastName: _lastName.text.trim(),
            jobTitle: derivedJobTitle,
            departmentId: derivedDepartmentId,
            roleScorecardId: _roleScorecardId,
            workEmail: _workEmail.text.trim().isEmpty ? null : _workEmail.text.trim(),
            mobileNumber: _mobile.text.trim().isEmpty ? null : _mobile.text.trim(),
            employmentType: _employmentType,
            employmentStatus: _employmentStatus,
            hireDate: _hireDate,
            regularizationDate: _regularizationDate,
            isRankAndFile: _isRankAndFile,
            isOtEligible: _isOtEligible,
            isNdEligible: _isNdEligible,
            isHolidayPayEligible: _isHolidayEligible,
            writeTaxOnFullEarnings: taxDirty,
            taxOnFullEarnings: _taxOnFullEarnings,
            writeDeclaredWage: wageDirty,
            declaredWageOverride: wageCurrent,
            declaredWageType: wageCurrent == null ? null : _declaredWageType,
            declaredWageEffectiveAt: wageCurrent == null ? null : _declaredWageEffectiveAt,
            declaredWageReason: wageCurrent == null
                ? null
                : (_declaredWageReason.text.trim().isEmpty ? null : _declaredWageReason.text.trim()),
            declaredWageSetById: wageDirty ? profile.userId : null,
            writePaymentRouting:
                _paymentSourceAccount != _origPaymentSourceAccount,
            paymentSourceAccount: _paymentSourceAccount,
            paymentMethod:
                _paymentSourceAccount == null ? null : 'BANK_TRANSFER',
          );
      if (!mounted) return;
      ref.invalidate(employeeListProvider);
      // Also refresh the single-employee provider so the profile screen
      // reflects edits (declared wage, tax toggle, etc.) immediately on return.
      if (_existing?.id != null) {
        ref.invalidate(employeeByIdProvider(_existing!.id));
      }
      context.pop();
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pickDate(DateTime initial, void Function(DateTime) set) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(1950),
      lastDate: DateTime(2100),
    );
    if (picked != null) setState(() => set(picked));
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_isEdit ? 'Edit Employee' : 'New Employee')),
      body: _loading && _existing == null && _isEdit
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: ListView(
                padding: EdgeInsets.all(isMobile(context) ? 16 : 24),
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const _SectionLabel('Identity'),
                          _field(_empNo, 'Employee #', required: true),
                          _responsiveRow([
                            _field(_firstName, 'First name', required: true),
                            _field(_middleName, 'Middle name'),
                            _field(_lastName, 'Last name', required: true),
                          ]),
                          const SizedBox(height: 12),
                          _responsiveRow([
                            _field(_workEmail, 'Work email'),
                            _field(_mobile, 'Mobile number'),
                          ]),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const _SectionLabel('Employment'),
                          _buildRoleScorecardField(),
                          const SizedBox(height: 12),
                          _responsiveRow([
                            DropdownButtonFormField<String>(
                              initialValue: _employmentType,
                              decoration: const InputDecoration(labelText: 'Type', border: OutlineInputBorder()),
                              items: const [
                                'REGULAR', 'PROBATIONARY', 'CONTRACTUAL', 'CONSULTANT',
                                'INTERN', 'SEASONAL', 'CASUAL'
                              ].map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
                              onChanged: (v) => setState(() => _employmentType = v!),
                            ),
                            DropdownButtonFormField<String>(
                              initialValue: _employmentStatus,
                              decoration: const InputDecoration(labelText: 'Status', border: OutlineInputBorder()),
                              items: const [
                                'ACTIVE', 'RESIGNED', 'TERMINATED', 'AWOL',
                                'DECEASED', 'END_OF_CONTRACT', 'RETIRED'
                              ].map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
                              onChanged: (v) => setState(() => _employmentStatus = v!),
                            ),
                          ]),
                          const SizedBox(height: 12),
                          _responsiveRow([
                            _DatePickerField(
                              label: 'Hire date',
                              value: _hireDate,
                              onTap: () => _pickDate(_hireDate, (d) => _hireDate = d),
                            ),
                            _DatePickerField(
                              label: 'Regularization date',
                              value: _regularizationDate,
                              onTap: () => _pickDate(
                                  _regularizationDate ?? DateTime.now(),
                                  (d) => _regularizationDate = d),
                              onClear: () => setState(() => _regularizationDate = null),
                            ),
                          ]),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const _SectionLabel('Payroll eligibility'),
                          SwitchListTile(
                            title: const Text('Rank and file'),
                            value: _isRankAndFile,
                            onChanged: (v) => setState(() => _isRankAndFile = v),
                          ),
                          SwitchListTile(
                            title: const Text('Overtime eligible'),
                            value: _isOtEligible,
                            onChanged: (v) => setState(() => _isOtEligible = v),
                          ),
                          SwitchListTile(
                            title: const Text('Night differential eligible'),
                            value: _isNdEligible,
                            onChanged: (v) => setState(() => _isNdEligible = v),
                          ),
                          SwitchListTile(
                            title: const Text('Holiday pay eligible'),
                            value: _isHolidayEligible,
                            onChanged: (v) => setState(() => _isHolidayEligible = v),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (_isEdit) ...[
                    const SizedBox(height: 16),
                    _buildPaymentAccountsCard(),
                  ],
                  ..._buildPayrollOverridesSection(),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(_error!, style: const TextStyle(color: Colors.red)),
                  ],
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                          onPressed: () => context.pop(),
                          child: const Text('Cancel')),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: _loading ? null : _save,
                        child: _loading
                            ? const SizedBox(
                                height: 18,
                                width: 18,
                                child: CircularProgressIndicator(strokeWidth: 2))
                            : const Text('Save'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildRoleScorecardField() {
    final async = ref.watch(roleScorecardListProvider);
    return async.when(
      loading: () => const InputDecorator(
        decoration: InputDecoration(
          labelText: 'Role scorecard',
          border: OutlineInputBorder(),
          isDense: true,
        ),
        child: Text('Loading…'),
      ),
      error: (e, _) => InputDecorator(
        decoration: const InputDecoration(
          labelText: 'Role scorecard',
          border: OutlineInputBorder(),
          isDense: true,
        ),
        child: Text('Error: $e', style: const TextStyle(color: Colors.red)),
      ),
      data: (cards) {
        final activeIds = cards.map((c) => c.id).toSet();
        final currentValue =
            _roleScorecardId != null && activeIds.contains(_roleScorecardId)
                ? _roleScorecardId
                : null;
        return DropdownButtonFormField<String?>(
          initialValue: currentValue,
          decoration: const InputDecoration(
            labelText: 'Role scorecard',
            border: OutlineInputBorder(),
            isDense: true,
          ),
          items: [
            const DropdownMenuItem<String?>(
              value: null,
              child: Text('— None —'),
            ),
            ...cards.map(
              (c) => DropdownMenuItem<String?>(
                value: c.id,
                child: Text(c.jobTitle),
              ),
            ),
          ],
          onChanged: (v) => setState(() => _roleScorecardId = v),
        );
      },
    );
  }

  Widget _buildPaymentAccountsCard() {
    final accountsAsync =
        ref.watch(employeeBankAccountsProvider(widget.employeeId!));
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const _SectionLabel('Payment Accounts'),
                const Spacer(),
                TextButton.icon(
                  onPressed: () => _openAccountDialog(null),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Add account'),
                ),
              ],
            ),
            const SizedBox(height: 4),
            accountsAsync.when(
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) => Text('Error: $e',
                  style: const TextStyle(color: Colors.red)),
              data: (accounts) {
                if (accounts.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text('No accounts yet. Click "Add account".',
                        style: TextStyle(color: Colors.grey)),
                  );
                }
                return Column(
                  children: [
                    for (final a in accounts) _accountRow(a),
                  ],
                );
              },
            ),
            const SizedBox(height: 16),
            _buildDefaultPaySourceField(accountsAsync.asData?.value ?? const []),
          ],
        ),
      ),
    );
  }

  Widget _accountRow(EmployeeBankAccount a) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          IconButton(
            tooltip: a.isPrimary ? 'Primary' : 'Set as primary',
            icon: Icon(
              a.isPrimary ? Icons.star : Icons.star_border,
              color: a.isPrimary ? const Color(0xFFF59E0B) : null,
            ),
            onPressed: a.isPrimary
                ? null
                : () async {
                    await ref
                        .read(employeeBankAccountRepositoryProvider)
                        .setPrimary(
                          employeeId: widget.employeeId!,
                          accountId: a.id,
                        );
                    ref.invalidate(employeeBankAccountsProvider);
                  },
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${a.bankName} · ${a.accountNumber}',
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                Text(a.accountName,
                    style: const TextStyle(fontSize: 12, color: Colors.grey)),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Edit',
            icon: const Icon(Icons.edit_outlined, size: 18),
            onPressed: () => _openAccountDialog(a),
          ),
          IconButton(
            tooltip: 'Delete',
            icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red),
            onPressed: () => _confirmDeleteAccount(a),
          ),
        ],
      ),
    );
  }

  /// Look up the employee's hiring entity code (used by the default pay
  /// source dropdown to filter company-scoped sources). Returns null when
  /// the employee has no hiring entity assigned — the dropdown then
  /// effectively only scopes by bank.
  String? _resolveHiringEntityCode() {
    // Placeholder: we only have `hiringEntityId` on the Employee model, not
    // the code. A full fetch would require watching a hiringEntityByIdProvider
    // here. Until that's wired, return null so shared + bank-matched sources
    // still appear.
    return null;
  }

  /// Default pay source dropdown — filtered so only sources whose bank_code
  /// matches one of this employee's registered accounts are selectable. CASH
  /// (bankCode = null) is always available.
  Widget _buildDefaultPaySourceField(List<EmployeeBankAccount> accounts) {
    final employeeBankCodes = accounts.map((a) => a.bankCode).toSet();
    // Filter by the employee's hiring entity code (via the linked role
    // scorecard's entity, falling back to the employee's own). Shared sources
    // (hiringEntityCode == null) always pass.
    final entityCode = _resolveHiringEntityCode();
    final eligible = paymentSourceAccounts
        .where((p) =>
            (p.hiringEntityCode == null || p.hiringEntityCode == entityCode) &&
            (p.bankCode == null || employeeBankCodes.contains(p.bankCode)))
        .toList();
    final ensureCurrentIncluded =
        _paymentSourceAccount != null &&
            !eligible.any((p) => p.value == _paymentSourceAccount);
    final items = [
      const DropdownMenuItem<String?>(value: null, child: Text('— None —')),
      ...eligible
          .map((p) => DropdownMenuItem<String?>(value: p.value, child: Text(p.label))),
      if (ensureCurrentIncluded)
        DropdownMenuItem<String?>(
          value: _paymentSourceAccount,
          child: Text('$_paymentSourceAccount (no matching account)'),
        ),
    ];
    return DropdownButtonFormField<String?>(
      initialValue: _paymentSourceAccount,
      decoration: InputDecoration(
        labelText: 'Default pay source',
        helperText: employeeBankCodes.isEmpty
            ? 'Add a bank account above to unlock bank-backed sources'
            : 'Filtered to sources matching the registered banks',
        border: const OutlineInputBorder(),
        isDense: true,
      ),
      items: items,
      onChanged: (v) => setState(() => _paymentSourceAccount = v),
    );
  }

  Future<void> _openAccountDialog(EmployeeBankAccount? existing) async {
    final changed = await showDialog<bool>(
      context: context,
      builder: (_) => _BankAccountDialog(
        employeeId: widget.employeeId!,
        existing: existing,
      ),
    );
    if (changed == true) {
      ref.invalidate(employeeBankAccountsProvider);
    }
  }

  Future<void> _confirmDeleteAccount(EmployeeBankAccount a) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete payment account?'),
        content: Text(
            'Remove ${a.bankName} · ${a.accountNumber}? If this is the default, '
            "you'll need to pick a new default pay source."),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(employeeBankAccountRepositoryProvider).delete(a.id);
    ref.invalidate(employeeBankAccountsProvider);
  }

  List<Widget> _buildPayrollOverridesSection() {
    final profile = ref.watch(userProfileProvider).asData?.value;
    if (profile == null) return const [];
    // Admin-tier only: ADMIN / HR / SUPER_ADMIN see the section. Others don't.
    if (!profile.isHrOrAdmin) return const [];
    final canEditWage = profile.appRole == AppRole.SUPER_ADMIN;
    return [
      const SizedBox(height: 16),
      Card(
        child: ExpansionTile(
          title: Row(children: const [
            Icon(Icons.shield_outlined, size: 18),
            SizedBox(width: 8),
            Text('Payroll Overrides (Admin)'),
          ]),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Tax Calculation Mode',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Choose how withholding tax is calculated for this employee.',
                    style: TextStyle(fontSize: 12, color: Colors.black54),
                  ),
                  const SizedBox(height: 8),
                  SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(
                        value: false,
                        label: Text('Basic Pay Only'),
                        icon: Icon(Icons.rule_outlined, size: 16),
                      ),
                      ButtonSegment(
                        value: true,
                        label: Text('Gross Pay'),
                        icon: Icon(Icons.summarize_outlined, size: 16),
                      ),
                    ],
                    selected: {_taxOnFullEarnings},
                    onSelectionChanged: (s) =>
                        setState(() => _taxOnFullEarnings = s.first),
                    showSelectedIcon: false,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _taxOnFullEarnings
                        ? 'Tax is calculated on Basic + OT + Holiday + Night Differential, minus statutory contributions. Commissions, adjustments, allowances, and reimbursements are excluded.'
                        : 'Tax is calculated only on Basic Pay minus Late/Undertime deductions. Excludes OT, commissions, adjustments, allowances, reimbursements. (Default)',
                    style: const TextStyle(fontSize: 12, color: Colors.black54),
                  ),
                ],
              ),
            ),
            const Divider(),
            Row(children: [
              const Icon(Icons.payments_outlined, size: 18),
              const SizedBox(width: 8),
              const Text('Declared wage override',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(width: 8),
              if (!canEditWage)
                const Tooltip(
                  message: 'Only Super Admin can edit declared wage override',
                  child: Icon(Icons.lock_outline, size: 16),
                ),
            ]),
            const SizedBox(height: 4),
            const Text(
              'Overrides wage used for statutory/tax calc only. Does not change actual earnings.',
              style: TextStyle(fontSize: 12, color: Colors.black54),
            ),
            const SizedBox(height: 8),
            _responsiveRow([
              TextFormField(
                controller: _declaredWage,
                enabled: canEditWage,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Override amount (PHP)',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              DropdownButtonFormField<String>(
                initialValue: _declaredWageType,
                decoration: const InputDecoration(
                  labelText: 'Wage type',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                items: const ['MONTHLY', 'DAILY', 'HOURLY']
                    .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                    .toList(),
                onChanged: canEditWage
                    ? (v) => setState(() => _declaredWageType = v!)
                    : null,
              ),
            ]),
            const SizedBox(height: 12),
            _DatePickerField(
              label: 'Effective at',
              value: _declaredWageEffectiveAt,
              onTap: canEditWage
                  ? () => _pickDate(
                        _declaredWageEffectiveAt ?? DateTime.now(),
                        (d) => _declaredWageEffectiveAt = d,
                      )
                  : () {},
              onClear: canEditWage
                  ? () => setState(() => _declaredWageEffectiveAt = null)
                  : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _declaredWageReason,
              enabled: canEditWage,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Reason',
                hintText: 'Why is this override being applied?',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ],
        ),
      ),
    ];
  }

  Widget _responsiveRow(List<Widget> children, {double gap = 12}) {
    if (isMobile(context)) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (int i = 0; i < children.length; i++) ...[
            if (i > 0) SizedBox(height: gap),
            children[i],
          ],
        ],
      );
    }
    return Row(children: [
      for (int i = 0; i < children.length; i++) ...[
        if (i > 0) SizedBox(width: gap),
        Expanded(child: children[i]),
      ],
    ]);
  }

  Widget _field(TextEditingController c, String label, {bool required = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: TextFormField(
        controller: c,
        decoration: InputDecoration(
          labelText: label + (required ? ' *' : ''),
          border: const OutlineInputBorder(),
          isDense: true,
        ),
        validator: required
            ? (v) => (v == null || v.trim().isEmpty) ? 'Required' : null
            : null,
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(text,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
      );
}

class _DatePickerField extends StatelessWidget {
  final String label;
  final DateTime? value;
  final VoidCallback onTap;
  final VoidCallback? onClear;
  const _DatePickerField({
    required this.label,
    required this.value,
    required this.onTap,
    this.onClear,
  });
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: InputDecorator(
        decoration: InputDecoration(labelText: label, border: const OutlineInputBorder(), isDense: true),
        child: Row(
          children: [
            Expanded(
              child: InkWell(
                onTap: onTap,
                child: Text(
                  value == null ? 'Select...' : value!.toIso8601String().substring(0, 10),
                  style: TextStyle(color: value == null ? Theme.of(context).hintColor : null),
                ),
              ),
            ),
            if (onClear != null && value != null)
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.clear, size: 16),
                onPressed: onClear,
              ),
          ],
        ),
      ),
    );
  }
}

class _BankAccountDialog extends ConsumerStatefulWidget {
  final String employeeId;
  final EmployeeBankAccount? existing;
  const _BankAccountDialog({required this.employeeId, required this.existing});

  @override
  ConsumerState<_BankAccountDialog> createState() => _BankAccountDialogState();
}

class _BankAccountDialogState extends ConsumerState<_BankAccountDialog> {
  final _formKey = GlobalKey<FormState>();
  final _number = TextEditingController();
  final _name = TextEditingController();
  String? _bankCode;
  bool _isPrimary = false;
  bool _saving = false;
  String? _error;

  // Pull the bank list from the app's payment source constants so the
  // employee can only register accounts whose bank the company actually uses.
  List<({String code, String label})> get _bankChoices {
    final seen = <String>{};
    final out = <({String code, String label})>[];
    for (final p in paymentSourceAccounts) {
      final code = p.bankCode;
      if (code == null || !seen.add(code)) continue;
      out.add((code: code, label: p.label.split(' ').take(2).join(' ')));
    }
    // Replace label with just bank name (e.g. "Metrobank") pulled from the
    // source label — everything before the last word usually reads as the
    // bank. Fallback to the raw code.
    return paymentSourceAccounts
        .where((p) => p.bankCode != null)
        .map((p) => (code: p.bankCode!, label: _bankLabelFor(p.bankCode!)))
        .fold<List<({String code, String label})>>([], (list, b) {
      if (!list.any((x) => x.code == b.code)) list.add(b);
      return list;
    });
  }

  String _bankLabelFor(String code) {
    switch (code) {
      case 'MBTC':
        return 'Metrobank (MBTC)';
      case 'GCASH':
        return 'GCash';
      case 'BDO':
        return 'BDO';
      case 'BPI':
        return 'BPI';
      default:
        return code;
    }
  }

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) {
      _bankCode = e.bankCode;
      _number.text = e.accountNumber;
      _name.text = e.accountName;
      _isPrimary = e.isPrimary;
    }
  }

  @override
  void dispose() {
    _number.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate() || _bankCode == null) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final repo = ref.read(employeeBankAccountRepositoryProvider);
      final saved = await repo.upsert(
        id: widget.existing?.id,
        employeeId: widget.employeeId,
        bankCode: _bankCode!,
        bankName: _bankLabelFor(_bankCode!),
        accountNumber: _number.text.trim(),
        accountName: _name.text.trim(),
        isPrimary: _isPrimary,
      );
      // Enforce one-primary-at-a-time.
      if (_isPrimary) {
        await repo.setPrimary(
          employeeId: widget.employeeId,
          accountId: saved.id,
        );
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dialogWidth = isMobile(context)
        ? MediaQuery.sizeOf(context).width - 48
        : 400.0;
    return AlertDialog(
      title: Text(widget.existing == null ? 'Add payment account' : 'Edit payment account'),
      content: SizedBox(
        width: dialogWidth,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DropdownButtonFormField<String>(
                initialValue: _bankCode,
                decoration: const InputDecoration(
                  labelText: 'Bank *',
                  border: OutlineInputBorder(),
                ),
                items: _bankChoices
                    .map((b) => DropdownMenuItem(
                          value: b.code,
                          child: Text(b.label),
                        ))
                    .toList(),
                validator: (v) => v == null ? 'Required' : null,
                onChanged: (v) => setState(() => _bankCode = v),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _number,
                decoration: const InputDecoration(
                  labelText: 'Account number *',
                  border: OutlineInputBorder(),
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _name,
                decoration: const InputDecoration(
                  labelText: 'Account name *',
                  border: OutlineInputBorder(),
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 12),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: const Text('Set as primary (default)'),
                value: _isPrimary,
                onChanged: (v) => setState(() => _isPrimary = v ?? false),
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!, style: const TextStyle(color: Colors.red)),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  height: 16,
                  width: 16,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Save'),
        ),
      ],
    );
  }
}
