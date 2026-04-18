/// Payment source accounts used for disbursement grouping. Mirrors
/// `lib/constants/employee.ts` in the payrollos reference project so the two
/// systems stay in sync.
///
/// `hiringEntityCode` scopes a source to a specific hiring entity — e.g.
/// `LUXIUM_MBTC` is only picked when the employee is hired under Luxium.
/// Leave null for sources shared across entities (CASH, GCash).
class PaymentSource {
  final String value;
  final String label;
  final String? bankCode;
  final String? hiringEntityCode;
  const PaymentSource({
    required this.value,
    required this.label,
    this.bankCode,
    this.hiringEntityCode,
  });
}

const paymentSourceAccounts = <PaymentSource>[
  PaymentSource(
    value: 'LUXIUM_MBTC',
    label: 'Luxium Metrobank',
    bankCode: 'MBTC',
    // Matches hiring_entities.code (not the parent company code). See
    // supabase/seed/01_company.sql — Luxium Trading Inc. = 'LX'.
    hiringEntityCode: 'LX',
  ),
  PaymentSource(
    value: 'GAMECOVE_MBTC',
    label: 'GameCove Metrobank',
    bankCode: 'MBTC',
    // Matches hiring_entities.code — GameCove Inc. = 'GC' (the 'GAMECOVE'
    // code belongs to the parent company row, not the hiring entity).
    hiringEntityCode: 'GC',
  ),
  PaymentSource(value: 'GCASH_CHRIS', label: 'GCash Chris', bankCode: 'GCASH'),
  PaymentSource(value: 'GCASH_CLINTON', label: 'GCash Clinton', bankCode: 'GCASH'),
  PaymentSource(value: 'CASH', label: 'Cash', bankCode: null),
];

String paymentSourceLabel(String? value) {
  if (value == null || value.isEmpty) return 'No Source';
  return paymentSourceAccounts
          .where((p) => p.value == value)
          .map((p) => p.label)
          .firstOrNull ??
      value;
}

String? paymentSourceBankCode(String value) =>
    paymentSourceAccounts
        .where((p) => p.value == value)
        .map((p) => p.bankCode)
        .firstOrNull;

/// Pick the best source for an employee row in the disbursement tab.
/// Matching rules, in priority order:
///   1. **Company**: filter to sources whose `hiringEntityCode` matches the
///      employee's hiring entity code (or is null = shared).
///   2. **Bank**: among those, prefer one whose `bankCode` matches one of the
///      employee's registered bank accounts.
///   3. **CASH fallback**: if no bank-matched source exists in the filtered
///      set, return CASH.
/// Returns null when nothing reasonable can be assigned (e.g., no CASH source
/// defined — won't happen with the current constant list).
String? resolveAutoPaymentSource({
  required String? hiringEntityCode,
  required Set<String> employeeBankCodes,
}) {
  bool matchesEntity(PaymentSource p) =>
      p.hiringEntityCode == null || p.hiringEntityCode == hiringEntityCode;

  // 1. Constrain to the employee's hiring entity (or shared).
  final scoped = paymentSourceAccounts.where(matchesEntity).toList();

  // 2. Prefer a bank match.
  for (final p in scoped) {
    if (p.bankCode != null && employeeBankCodes.contains(p.bankCode)) {
      return p.value;
    }
  }

  // 3. CASH fallback.
  final cash = scoped.where((p) => p.value == 'CASH').map((p) => p.value).firstOrNull;
  return cash;
}
