import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/breakpoints.dart';
import '../../data/models/employee.dart';
import '../../data/models/employee_bank_account.dart';
import '../../data/repositories/employee_bank_account_repository.dart';
import '../../data/repositories/employee_repository.dart';
import '../../data/repositories/employee_statutory_id_repository.dart';
import 'profile/providers.dart';
import '../../data/repositories/hiring_entity_repository.dart';
import '../../data/repositories/role_scorecard_repository.dart';
import '../auth/profile_provider.dart';
import '../payroll/constants.dart';

/// Brand-allocation entry mode for the employee form.
enum BrandMode { derive, manual }

/// Resolves the brand allocation to persist for an employee. In derive mode the
/// selected role scorecard's entity is used; in manual mode the explicit pick is
/// used. Returns null when nothing resolves — the form must block save then.
String? resolveBrandAllocation({
  required bool deriveFromScorecard,
  required String? scorecardHiringEntityId,
  required String? manualHiringEntityId,
}) => deriveFromScorecard ? scorecardHiringEntityId : manualHiringEntityId;

/// A subset of Applicant fields the EmployeeFormScreen can prefill from on
/// conversion. Keeping this as a separate value object (rather than coupling
/// the EmployeeFormScreen to the Applicant model directly) keeps the form
/// independent of the hiring feature.
class ApplicantSeed {
  final String firstName;
  final String? middleName;
  final String lastName;
  final String? suffix;
  final String email;
  final String? phoneNumber;
  final String? mobileNumber;
  final String? roleScorecardId;
  final String? hiringEntityId;
  final String? departmentId;
  final String? referredById;
  final DateTime? expectedStartDate;
  final String? offerSalary; // expected_salary_max as a Decimal string
  const ApplicantSeed({
    required this.firstName,
    this.middleName,
    required this.lastName,
    this.suffix,
    required this.email,
    this.phoneNumber,
    this.mobileNumber,
    this.roleScorecardId,
    this.hiringEntityId,
    this.departmentId,
    this.referredById,
    this.expectedStartDate,
    this.offerSalary,
  });
}

/// Create/edit form for an Employee.
/// - /employees/new    → create
/// - /employees/:id    → edit existing
class EmployeeFormScreen extends ConsumerStatefulWidget {
  final String? employeeId;

  /// When non-null, the form opens in "create from applicant" mode: fields
  /// are prefilled from the applicant and, on save, the caller is given the
  /// new employee id so it can call `applicantRepository.markConverted`.
  final ApplicantSeed? applicantSeed;
  final ValueChanged<String>? onCreatedFromApplicant;

  const EmployeeFormScreen({
    super.key,
    this.employeeId,
    this.applicantSeed,
    this.onCreatedFromApplicant,
  });

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
  DateTime? _birthDate;
  final _addressLine1 = TextEditingController();
  final _addressLine2 = TextEditingController();
  final _city = TextEditingController();
  final _province = TextEditingController();
  final _zipCode = TextEditingController();
  final _sss = TextEditingController();
  final _philhealth = TextEditingController();
  final _pagibig = TextEditingController();

  String? _roleScorecardId;
  String? _paymentSourceAccount;
  String? _origPaymentSourceAccount;
  String _employmentType = 'PROBATIONARY';
  String _employmentStatus = 'ACTIVE';
  String _origEmploymentStatus = 'ACTIVE';
  DateTime? _separationDate;
  DateTime? _origSeparationDate;
  final _separationReason = TextEditingController();
  DateTime _hireDate = DateTime.now();
  final _probationMonths = TextEditingController(text: '6');
  bool _isRankAndFile = true;
  bool _isOtEligible = true;
  bool _isNdEligible = true;
  bool _isHolidayEligible = true;

  // Brand allocation (Company / hiring entity). HR/Admin editable.
  BrandMode _brandMode = BrandMode.derive;
  String? _hiringEntityId; // manual selection
  String? _origHiringEntityId;

  // Statutory employer-of-record override (HR/Admin editable). null = inherit
  // from brand allocation (`hiring_entity_id`). Stored as `statutory_entity_id`.
  String? _statutoryEntityId;
  String? _origStatutoryEntityId;

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

  // Per-benefit eligibility overrides. `false` = use the default
  // regularization-date gate; `true` = force-enrol this employee in the
  // named benefit even while still probationary.
  bool _sssEligibilityOverride = false;
  bool _philhealthEligibilityOverride = false;
  bool _pagibigEligibilityOverride = false;
  bool _origSssEligibilityOverride = false;
  bool _origPhilhealthEligibilityOverride = false;
  bool _origPagibigEligibilityOverride = false;

  bool _loading = false;
  String? _error;
  Employee? _existing;

  bool get _isEdit => widget.employeeId != null;

  @override
  void initState() {
    super.initState();
    if (_isEdit) {
      Future.microtask(_loadExisting);
    } else if (widget.applicantSeed != null) {
      _applyApplicantSeed(widget.applicantSeed!);
    }
  }

  void _applyApplicantSeed(ApplicantSeed s) {
    _firstName.text = s.firstName;
    _middleName.text = s.middleName ?? '';
    _lastName.text = s.lastName;
    // Note: the form has no suffix or personal phone field — only work email
    // and mobile. Map accordingly.
    _workEmail.text = s.email;
    _mobile.text = s.mobileNumber ?? s.phoneNumber ?? '';
    _roleScorecardId = s.roleScorecardId;
    _hireDate = s.expectedStartDate ?? DateTime.now();
    if (s.hiringEntityId != null && s.hiringEntityId!.isNotEmpty) {
      _hiringEntityId = s.hiringEntityId;
      _brandMode = BrandMode.manual;
    }
    // offerSalary: intentionally not applied to declaredWageOverride here;
    // that is a statutory/tax-calc field (SUPER_ADMIN only). HR can fill it
    // manually after conversion if the negotiated salary differs.
  }

  Future<void> _loadExisting() async {
    setState(() => _loading = true);
    try {
      final e = await ref
          .read(employeeRepositoryProvider)
          .byId(widget.employeeId!);
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
      _birthDate = e.birthDate;
      _addressLine1.text = e.addressLine1 ?? '';
      _addressLine2.text = e.addressLine2 ?? '';
      _city.text = e.city ?? '';
      _province.text = e.province ?? '';
      _zipCode.text = e.zipCode ?? '';
      final ids = await ref
          .read(employeeStatutoryIdRepositoryProvider)
          .byEmployee(e.id);
      _sss.text = ids['SSS'] ?? '';
      _philhealth.text = ids['PHILHEALTH'] ?? '';
      _pagibig.text = ids['PAGIBIG'] ?? '';
      _employmentType = e.employmentType;
      _employmentStatus = e.employmentStatus;
      _origEmploymentStatus = e.employmentStatus;
      _separationDate = e.separationDate;
      _origSeparationDate = e.separationDate;
      _hireDate = e.hireDate;
      // Derive probation months from the stored regularization date so the
      // input reflects the saved policy. Empty when no regularization date.
      if (e.regularizationDate != null) {
        final m =
            (e.regularizationDate!.year - e.hireDate.year) * 12 +
            (e.regularizationDate!.month - e.hireDate.month);
        _probationMonths.text = m > 0 ? m.toString() : '';
      } else {
        _probationMonths.text = '';
      }
      _isRankAndFile = e.isRankAndFile;
      _isOtEligible = e.isOtEligible;
      _isNdEligible = e.isNdEligible;
      _isHolidayEligible = e.isHolidayPayEligible;
      _hiringEntityId = e.hiringEntityId;
      _origHiringEntityId = e.hiringEntityId;
      // Existing employees with a stored brand open in manual mode showing it
      // (lossless); legacy null-brand rows default to derive.
      _brandMode = e.hiringEntityId == null
          ? BrandMode.derive
          : BrandMode.manual;
      _statutoryEntityId = e.statutoryEntityId;
      _origStatutoryEntityId = e.statutoryEntityId;
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
      _sssEligibilityOverride = e.sssEligibilityOverride;
      _origSssEligibilityOverride = e.sssEligibilityOverride;
      _philhealthEligibilityOverride = e.philhealthEligibilityOverride;
      _origPhilhealthEligibilityOverride = e.philhealthEligibilityOverride;
      _pagibigEligibilityOverride = e.pagibigEligibilityOverride;
      _origPagibigEligibilityOverride = e.pagibigEligibilityOverride;
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
    final canEditStatutoryEntity = profile.isHrOrAdmin;
    final canEditWage = profile.appRole == AppRole.SUPER_ADMIN;
    final taxDirty = canEditTax && _taxOnFullEarnings != _origTaxOnFull;
    final statutoryEntityDirty =
        canEditStatutoryEntity && _statutoryEntityId != _origStatutoryEntityId;
    final wageText = _declaredWage.text.trim();
    final wageCurrent = wageText.isEmpty ? null : wageText;
    final wageDirty =
        canEditWage &&
        (wageCurrent != _origDeclaredWage ||
            _declaredWageType != (_origDeclaredWageType ?? 'MONTHLY') ||
            _declaredWageEffectiveAt != _origDeclaredWageEffectiveAt ||
            _declaredWageReason.text.trim() != (_origDeclaredWageReason ?? ''));
    // Per-benefit eligibility-override dirty flags. Admin-tier only — gated by
    // the same `isHrOrAdmin` check used for the rest of this section.
    final canEditBenefitOverrides = profile.isHrOrAdmin;
    final sssOverrideDirty =
        canEditBenefitOverrides &&
        _sssEligibilityOverride != _origSssEligibilityOverride;
    final philhealthOverrideDirty =
        canEditBenefitOverrides &&
        _philhealthEligibilityOverride != _origPhilhealthEligibilityOverride;
    final pagibigOverrideDirty =
        canEditBenefitOverrides &&
        _pagibigEligibilityOverride != _origPagibigEligibilityOverride;

    if (wageDirty) {
      final confirmed =
          await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Confirm declared wage override'),
              content: const Text(
                'Changing declared wage override affects statutory and tax calculations. '
                'This action is audited. Continue?',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Confirm'),
                ),
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
      final cards =
          ref.read(roleScorecardListProvider).asData?.value ?? const [];
      final selectedCard = _roleScorecardId == null
          ? null
          : cards
                .where((c) => c.id == _roleScorecardId)
                .cast<dynamic>()
                .firstOrNull;
      final derivedJobTitle = selectedCard?.jobTitle as String?;
      final derivedDepartmentId = selectedCard?.departmentId as String?;

      final canEditBrand = profile.isHrOrAdmin;
      String? effectiveHiringEntityId;
      if (canEditBrand) {
        effectiveHiringEntityId = resolveBrandAllocation(
          deriveFromScorecard: _brandMode == BrandMode.derive,
          scorecardHiringEntityId: selectedCard?.hiringEntityId as String?,
          manualHiringEntityId: _hiringEntityId,
        );
        if (effectiveHiringEntityId == null) {
          setState(
            () => _error =
                'Company (brand) is required. Pick a brand, or choose a role '
                'scorecard that has a company set.',
          );
          return;
        }
      } else {
        // Non-HR cannot edit the brand; preserve whatever was stored so their
        // edit to other fields neither nulls nor is blocked by the brand.
        effectiveHiringEntityId = _origHiringEntityId;
      }

      final saved = await ref
          .read(employeeRepositoryProvider)
          .upsert(
            id: _existing?.id,
            companyId: _existing?.companyId ?? profile.companyId,
            employeeNumber: _empNo.text.trim(),
            firstName: _firstName.text.trim(),
            middleName: _middleName.text.trim().isEmpty
                ? null
                : _middleName.text.trim(),
            lastName: _lastName.text.trim(),
            jobTitle: derivedJobTitle,
            departmentId: derivedDepartmentId,
            roleScorecardId: _roleScorecardId,
            hiringEntityId: effectiveHiringEntityId,
            workEmail: _workEmail.text.trim().isEmpty
                ? null
                : _workEmail.text.trim(),
            mobileNumber: _mobile.text.trim().isEmpty
                ? null
                : _mobile.text.trim(),
            birthDate: _birthDate,
            addressLine1: _addressLine1.text.trim().isEmpty
                ? null
                : _addressLine1.text.trim(),
            addressLine2: _addressLine2.text.trim().isEmpty
                ? null
                : _addressLine2.text.trim(),
            city: _city.text.trim().isEmpty ? null : _city.text.trim(),
            province: _province.text.trim().isEmpty
                ? null
                : _province.text.trim(),
            zipCode: _zipCode.text.trim().isEmpty ? null : _zipCode.text.trim(),
            employmentType: _employmentType,
            employmentStatus: _employmentStatus,
            hireDate: _hireDate,
            regularizationDate: _computedRegularizationDate(),
            separationDate: _employmentStatus == 'ACTIVE'
                ? null
                : _separationDate,
            isRankAndFile: _isRankAndFile,
            isOtEligible: _isOtEligible,
            isNdEligible: _isNdEligible,
            isHolidayPayEligible: _isHolidayEligible,
            writeTaxOnFullEarnings: taxDirty,
            taxOnFullEarnings: _taxOnFullEarnings,
            writeDeclaredWage: wageDirty,
            declaredWageOverride: wageCurrent,
            declaredWageType: wageCurrent == null ? null : _declaredWageType,
            declaredWageEffectiveAt: wageCurrent == null
                ? null
                : _declaredWageEffectiveAt,
            declaredWageReason: wageCurrent == null
                ? null
                : (_declaredWageReason.text.trim().isEmpty
                      ? null
                      : _declaredWageReason.text.trim()),
            declaredWageSetById: wageDirty ? profile.userId : null,
            writePaymentRouting:
                _paymentSourceAccount != _origPaymentSourceAccount,
            paymentSourceAccount: _paymentSourceAccount,
            paymentMethod: _paymentSourceAccount == null
                ? null
                : 'BANK_TRANSFER',
            writeStatutoryEntity: statutoryEntityDirty,
            statutoryEntityId: _statutoryEntityId,
            sssEligibilityOverride: sssOverrideDirty
                ? _sssEligibilityOverride
                : null,
            philhealthEligibilityOverride: philhealthOverrideDirty
                ? _philhealthEligibilityOverride
                : null,
            pagibigEligibilityOverride: pagibigOverrideDirty
                ? _pagibigEligibilityOverride
                : null,
          );
      // Notify the hiring flow on a successful CREATE (not update) so it can
      // mark the applicant as converted. Only fires when an ApplicantSeed was
      // provided — never fires on edit.
      if (_existing == null &&
          widget.applicantSeed != null &&
          widget.onCreatedFromApplicant != null) {
        widget.onCreatedFromApplicant!(saved.id);
      }
      // Record a SEPARATION_CONFIRMED timeline event when:
      //   - status transitions from ACTIVE → non-ACTIVE, or
      //   - the employee is already separated and the separation date moves.
      // Uses the saved employee's id so this works for new employees too.
      final isSeparating =
          _employmentStatus != 'ACTIVE' && _separationDate != null;
      final statusChangedToSeparated =
          _origEmploymentStatus == 'ACTIVE' && _employmentStatus != 'ACTIVE';
      final separationDateChanged =
          _origEmploymentStatus != 'ACTIVE' &&
          _separationDate != _origSeparationDate;
      if (isSeparating && (statusChangedToSeparated || separationDateChanged)) {
        await ref
            .read(employeeRepositoryProvider)
            .recordSeparationEvent(
              employeeId: saved.id,
              separationDate: _separationDate!,
              reason: _employmentStatus,
              remarks: _separationReason.text.trim().isEmpty
                  ? null
                  : _separationReason.text.trim(),
              actorUserId: profile.userId,
            );
      }
      await ref.read(employeeStatutoryIdRepositoryProvider).upsertAll(
        saved.id,
        {
          'SSS': _sss.text.trim().isEmpty ? null : _sss.text.trim(),
          'PHILHEALTH': _philhealth.text.trim().isEmpty
              ? null
              : _philhealth.text.trim(),
          'PAGIBIG': _pagibig.text.trim().isEmpty ? null : _pagibig.text.trim(),
        },
      );
      if (!mounted) return;
      ref.invalidate(employeeListProvider);
      ref.invalidate(employeeStatutoryIdsProvider(saved.id));
      ref.invalidate(timelineProvider(saved.id));
      // Also refresh the single-employee provider so the profile screen
      // reflects edits (declared wage, tax toggle, etc.) immediately on return.
      if (_existing?.id != null) {
        ref.invalidate(employeeByIdProvider(_existing!.id));
      }
      context.pop();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Probation months → regularization date = hire date + N months.
  /// Returns null when input is blank or non-positive.
  DateTime? _computedRegularizationDate() {
    final m = int.tryParse(_probationMonths.text.trim());
    if (m == null || m <= 0) return null;
    return DateTime(_hireDate.year, _hireDate.month + m, _hireDate.day);
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
                          const SizedBox(height: 12),
                          _responsiveRow([
                            _DatePickerField(
                              label: 'Birthday',
                              value: _birthDate,
                              onTap: () => _pickDate(
                                _birthDate ?? DateTime(2000, 1, 1),
                                (d) => _birthDate = d,
                              ),
                              onClear: () => setState(() => _birthDate = null),
                            ),
                            _field(_addressLine1, 'Address line 1'),
                          ]),
                          const SizedBox(height: 12),
                          _field(_addressLine2, 'Address line 2'),
                          const SizedBox(height: 12),
                          _responsiveRow([
                            _field(_city, 'City'),
                            _field(_province, 'Province'),
                            _field(_zipCode, 'ZIP code'),
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
                          const _SectionLabel('Statutory IDs'),
                          _responsiveRow([
                            _field(_sss, 'SSS Number'),
                            _field(_philhealth, 'PhilHealth Number'),
                            _field(_pagibig, 'Pag-IBIG Number'),
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
                              decoration: const InputDecoration(
                                labelText: 'Type',
                                border: OutlineInputBorder(),
                              ),
                              items:
                                  const [
                                        'REGULAR',
                                        'PROBATIONARY',
                                        'CONTRACTUAL',
                                        'CONSULTANT',
                                        'INTERN',
                                        'SEASONAL',
                                        'CASUAL',
                                      ]
                                      .map(
                                        (s) => DropdownMenuItem(
                                          value: s,
                                          child: Text(s),
                                        ),
                                      )
                                      .toList(),
                              onChanged: (v) =>
                                  setState(() => _employmentType = v!),
                            ),
                            DropdownButtonFormField<String>(
                              initialValue: _employmentStatus,
                              decoration: const InputDecoration(
                                labelText: 'Status',
                                border: OutlineInputBorder(),
                              ),
                              items:
                                  const [
                                        'ACTIVE',
                                        'RESIGNED',
                                        'TERMINATED',
                                        'AWOL',
                                        'DECEASED',
                                        'END_OF_CONTRACT',
                                        'RETIRED',
                                      ]
                                      .map(
                                        (s) => DropdownMenuItem(
                                          value: s,
                                          child: Text(s),
                                        ),
                                      )
                                      .toList(),
                              onChanged: (v) => setState(() {
                                _employmentStatus = v!;
                                if (_employmentStatus != 'ACTIVE' &&
                                    _separationDate == null) {
                                  _separationDate = DateTime.now();
                                }
                              }),
                            ),
                          ]),
                          const SizedBox(height: 12),
                          _responsiveRow([
                            _DatePickerField(
                              label: 'Hire date',
                              value: _hireDate,
                              onTap: () =>
                                  _pickDate(_hireDate, (d) => _hireDate = d),
                            ),
                            TextFormField(
                              controller: _probationMonths,
                              keyboardType: TextInputType.number,
                              decoration: InputDecoration(
                                labelText: 'Probation period (months)',
                                border: const OutlineInputBorder(),
                                hintText: '6',
                                helperText:
                                    _computedRegularizationDate() == null
                                    ? 'Leave blank to skip regularization'
                                    : 'Regularizes on '
                                          '${_computedRegularizationDate()!.toIso8601String().substring(0, 10)}',
                              ),
                              onChanged: (_) => setState(() {}),
                            ),
                          ]),
                          const SizedBox(height: 12),
                          _buildBrandAllocationField(),
                          const SizedBox(height: 12),
                          _buildStatutoryEntityField(),
                          if (_employmentStatus != 'ACTIVE') ...[
                            const SizedBox(height: 16),
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Theme.of(context)
                                    .colorScheme
                                    .errorContainer
                                    .withValues(alpha: 0.25),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  const _SectionLabel('Separation'),
                                  _responsiveRow([
                                    _DatePickerField(
                                      label: 'Separation date',
                                      value: _separationDate,
                                      onTap: () => _pickDate(
                                        _separationDate ?? DateTime.now(),
                                        (d) => _separationDate = d,
                                      ),
                                      onClear: () => setState(
                                        () => _separationDate = null,
                                      ),
                                    ),
                                    TextFormField(
                                      controller: _separationReason,
                                      decoration: const InputDecoration(
                                        labelText:
                                            'Reason / remarks (optional)',
                                        border: OutlineInputBorder(),
                                      ),
                                    ),
                                  ]),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Recorded on the timeline as Separation Confirmed. '
                                    'Used by COE generation as the end-of-employment date.',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
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
                            onChanged: (v) =>
                                setState(() => _isRankAndFile = v),
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
                            onChanged: (v) =>
                                setState(() => _isHolidayEligible = v),
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
                        child: const Text('Cancel'),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: _loading ? null : _save,
                        child: _loading
                            ? const SizedBox(
                                height: 18,
                                width: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
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

  Widget _buildBrandAllocationField() {
    final profile = ref.watch(userProfileProvider).asData?.value;
    final canEdit = profile?.isHrOrAdmin ?? false;
    final entities =
        ref.watch(hiringEntityListProvider).asData?.value ?? const [];
    final cards =
        ref.watch(roleScorecardListProvider).asData?.value ?? const [];
    final selectedCard = _roleScorecardId == null
        ? null
        : cards.where((c) => c.id == _roleScorecardId).firstOrNull;
    final derivedId = selectedCard?.hiringEntityId;
    String nameOf(String? id) => id == null
        ? '—'
        : (entities.where((e) => e.id == id).firstOrNull?.name ??
              '(unavailable)');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SegmentedButton<BrandMode>(
          segments: const [
            ButtonSegment(
              value: BrandMode.derive,
              label: Text('From role scorecard'),
            ),
            ButtonSegment(value: BrandMode.manual, label: Text('Set manually')),
          ],
          selected: {_brandMode},
          onSelectionChanged: canEdit
              ? (s) => setState(() => _brandMode = s.first)
              : null,
        ),
        const SizedBox(height: 8),
        if (_brandMode == BrandMode.derive)
          InputDecorator(
            decoration: InputDecoration(
              labelText: 'Company (brand)',
              helperText: derivedId == null
                  ? 'This role scorecard has no company set — choose "Set '
                        'manually", or set it on the scorecard.'
                  : 'Derived from the role scorecard.',
              border: const OutlineInputBorder(),
              isDense: true,
            ),
            child: Text(derivedId == null ? '— None —' : nameOf(derivedId)),
          )
        else
          DropdownButtonFormField<String?>(
            initialValue: entities.any((e) => e.id == _hiringEntityId)
                ? _hiringEntityId
                : null,
            decoration: const InputDecoration(
              labelText: 'Company (brand)',
              helperText: 'Required.',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            items: [
              const DropdownMenuItem<String?>(
                value: null,
                child: Text('— Select —'),
              ),
              for (final e in entities)
                DropdownMenuItem<String?>(value: e.id, child: Text(e.name)),
            ],
            onChanged: canEdit
                ? (v) => setState(() => _hiringEntityId = v)
                : null,
          ),
      ],
    );
  }

  Widget _buildStatutoryEntityField() {
    final profile = ref.watch(userProfileProvider).asData?.value;
    final canEdit = profile?.isHrOrAdmin ?? false;
    final async = ref.watch(hiringEntityListProvider);
    return async.when(
      loading: () => const InputDecorator(
        decoration: InputDecoration(
          labelText: 'Statutory Employer of Record',
          border: OutlineInputBorder(),
          isDense: true,
        ),
        child: Text('Loading…'),
      ),
      error: (e, _) => InputDecorator(
        decoration: const InputDecoration(
          labelText: 'Statutory Employer of Record',
          border: OutlineInputBorder(),
          isDense: true,
        ),
        child: Text('Error: $e', style: const TextStyle(color: Colors.red)),
      ),
      data: (entities) {
        final activeIds = entities.map((e) => e.id).toSet();
        // Defensive: if the persisted value points to an inactive/deleted
        // entity, surface it as "(unavailable)" so the dropdown still opens.
        final currentValue =
            _statutoryEntityId != null && activeIds.contains(_statutoryEntityId)
            ? _statutoryEntityId
            : null;
        return DropdownButtonFormField<String?>(
          initialValue: currentValue,
          decoration: const InputDecoration(
            labelText: 'Statutory Employer of Record',
            helperText: 'Leave blank to inherit from brand allocation.',
            border: OutlineInputBorder(),
            isDense: true,
          ),
          items: [
            const DropdownMenuItem<String?>(
              value: null,
              child: Text('— Inherit from brand allocation —'),
            ),
            ...entities.map(
              (e) =>
                  DropdownMenuItem<String?>(value: e.id, child: Text(e.name)),
            ),
          ],
          onChanged: canEdit
              ? (v) => setState(() => _statutoryEntityId = v)
              : null,
        );
      },
    );
  }

  Widget _buildPaymentAccountsCard() {
    final accountsAsync = ref.watch(
      employeeBankAccountsProvider(widget.employeeId!),
    );
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
              error: (e, _) =>
                  Text('Error: $e', style: const TextStyle(color: Colors.red)),
              data: (accounts) {
                if (accounts.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      'No accounts yet. Click "Add account".',
                      style: TextStyle(color: Colors.grey),
                    ),
                  );
                }
                return Column(
                  children: [for (final a in accounts) _accountRow(a)],
                );
              },
            ),
            const SizedBox(height: 16),
            _buildDefaultPaySourceField(
              accountsAsync.asData?.value ?? const [],
            ),
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
                Text(
                  '${a.bankName} · ${a.accountNumber}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                Text(
                  a.accountName,
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
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
        .where(
          (p) =>
              (p.hiringEntityCode == null ||
                  p.hiringEntityCode == entityCode) &&
              (p.bankCode == null || employeeBankCodes.contains(p.bankCode)),
        )
        .toList();
    final ensureCurrentIncluded =
        _paymentSourceAccount != null &&
        !eligible.any((p) => p.value == _paymentSourceAccount);
    final items = [
      const DropdownMenuItem<String?>(value: null, child: Text('— None —')),
      ...eligible.map(
        (p) => DropdownMenuItem<String?>(value: p.value, child: Text(p.label)),
      ),
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
          "you'll need to pick a new default pay source.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
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
          title: Row(
            children: const [
              Icon(Icons.shield_outlined, size: 18),
              SizedBox(width: 8),
              Text('Payroll Overrides (Admin)'),
            ],
          ),
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
            Row(
              children: [
                const Icon(Icons.payments_outlined, size: 18),
                const SizedBox(width: 8),
                const Text(
                  'Declared wage override',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(width: 8),
                if (!canEditWage)
                  const Tooltip(
                    message: 'Only Super Admin can edit declared wage override',
                    child: Icon(Icons.lock_outline, size: 16),
                  ),
              ],
            ),
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
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
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
            const Divider(height: 32),
            Row(
              children: const [
                Icon(Icons.health_and_safety_outlined, size: 18),
                SizedBox(width: 8),
                Text(
                  'Benefit eligibility overrides',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              'Force-enrol this employee in a specific statutory benefit even '
              'while still probationary. Leave off to use the default '
              'regularization-date rule.',
              style: TextStyle(fontSize: 12, color: Colors.black54),
            ),
            const SizedBox(height: 4),
            Text(
              'Turning these on starts contributions immediately for the next '
              'payroll run.',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.error,
              ),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: const Text('Force-enrol SSS'),
              value: _sssEligibilityOverride,
              onChanged: (v) => setState(() => _sssEligibilityOverride = v),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: const Text('Force-enrol PhilHealth'),
              value: _philhealthEligibilityOverride,
              onChanged: (v) =>
                  setState(() => _philhealthEligibilityOverride = v),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: const Text('Force-enrol Pag-IBIG'),
              value: _pagibigEligibilityOverride,
              onChanged: (v) => setState(() => _pagibigEligibilityOverride = v),
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
    return Row(
      children: [
        for (int i = 0; i < children.length; i++) ...[
          if (i > 0) SizedBox(width: gap),
          Expanded(child: children[i]),
        ],
      ],
    );
  }

  Widget _field(
    TextEditingController c,
    String label, {
    bool required = false,
  }) {
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
    child: Text(
      text,
      style: Theme.of(
        context,
      ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
    ),
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
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          isDense: true,
        ),
        child: Row(
          children: [
            Expanded(
              child: InkWell(
                onTap: onTap,
                child: Text(
                  value == null
                      ? 'Select...'
                      : value!.toIso8601String().substring(0, 10),
                  style: TextStyle(
                    color: value == null ? Theme.of(context).hintColor : null,
                  ),
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
      title: Text(
        widget.existing == null
            ? 'Add payment account'
            : 'Edit payment account',
      ),
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
                    .map(
                      (b) =>
                          DropdownMenuItem(value: b.code, child: Text(b.label)),
                    )
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
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Save'),
        ),
      ],
    );
  }
}
