/// Plain-Dart mirror of `hiring_entity_bank_accounts`. These are the company's
/// own bank/GCash/Cash accounts that payroll disburses FROM. Scoped per
/// hiring entity (GameCove and Luxium keep separate banks). Mirrors
/// `EmployeeBankAccount` in shape so the two UIs can share a dialog pattern.
class HiringEntityBankAccount {
  final String id;
  final String hiringEntityId;
  final String bankCode;
  final String bankName;
  final String accountNumber;
  final String accountName;
  final String? accountType;
  final bool isPrimary;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  const HiringEntityBankAccount({
    required this.id,
    required this.hiringEntityId,
    required this.bankCode,
    required this.bankName,
    required this.accountNumber,
    required this.accountName,
    this.accountType,
    required this.isPrimary,
    required this.isActive,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
  });

  factory HiringEntityBankAccount.fromRow(Map<String, dynamic> r) =>
      HiringEntityBankAccount(
        id: r['id'] as String,
        hiringEntityId: r['hiring_entity_id'] as String,
        bankCode: r['bank_code'] as String,
        bankName: r['bank_name'] as String,
        accountNumber: r['account_number'] as String,
        accountName: r['account_name'] as String,
        accountType: r['account_type'] as String?,
        isPrimary: r['is_primary'] as bool? ?? false,
        isActive: r['is_active'] as bool? ?? true,
        createdAt: DateTime.parse(r['created_at'] as String),
        updatedAt: DateTime.parse(r['updated_at'] as String),
        deletedAt: r['deleted_at'] == null
            ? null
            : DateTime.parse(r['deleted_at'] as String),
      );
}
