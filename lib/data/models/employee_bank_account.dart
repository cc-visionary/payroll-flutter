/// Plain-Dart mirror of `employee_bank_accounts`. Banks are stored as code +
/// display name (synced from a shared bank list) so the disbursement engine
/// can match the employee's account to a company payment source by bank_code.
class EmployeeBankAccount {
  final String id;
  final String employeeId;
  final String bankCode;
  final String bankName;
  final String accountNumber;
  final String accountName;
  final String? accountType;
  final bool isPrimary;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  const EmployeeBankAccount({
    required this.id,
    required this.employeeId,
    required this.bankCode,
    required this.bankName,
    required this.accountNumber,
    required this.accountName,
    this.accountType,
    required this.isPrimary,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
  });

  factory EmployeeBankAccount.fromRow(Map<String, dynamic> r) =>
      EmployeeBankAccount(
        id: r['id'] as String,
        employeeId: r['employee_id'] as String,
        bankCode: r['bank_code'] as String,
        bankName: r['bank_name'] as String,
        accountNumber: r['account_number'] as String,
        accountName: r['account_name'] as String,
        accountType: r['account_type'] as String?,
        isPrimary: r['is_primary'] as bool? ?? false,
        createdAt: DateTime.parse(r['created_at'] as String),
        updatedAt: DateTime.parse(r['updated_at'] as String),
        deletedAt: r['deleted_at'] == null
            ? null
            : DateTime.parse(r['deleted_at'] as String),
      );
}
