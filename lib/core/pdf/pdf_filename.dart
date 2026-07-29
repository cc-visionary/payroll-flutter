/// Build a suggested filename for a generated document PDF.
///
/// Format: `<Prefix>_<Identifier>_<YYYYMMDD>.pdf` where Prefix is a
/// human-readable template label and Identifier is the employee number,
/// falling back to the first 8 chars of the employee UUID (uppercased)
/// when the number is null. The same filename is shown in both the
/// Save / Share dialog and the OS print dialog.
String filenameForDocument({
  required String templateId,
  required String? employeeNumber,
  required String employeeId,
  required DateTime date,
}) {
  final prefix = _prefixFor(templateId);
  final id = employeeNumber ?? employeeId.substring(0, 8).toUpperCase();
  final ymd =
      '${date.year.toString().padLeft(4, '0')}'
      '${date.month.toString().padLeft(2, '0')}'
      '${date.day.toString().padLeft(2, '0')}';
  return '${prefix}_${id}_$ymd.pdf';
}

/// Build a suggested filename for a self-evaluation PDF export.
///
/// Format: `Self-Evaluation - <Name> - <Type> - <YYYY-MM-DD>.pdf`. Blank
/// fields fall back to placeholder tokens, and characters unsafe in filenames
/// are stripped so the same name works in both the Save / Share dialog and the
/// OS print dialog.
String filenameForSelfEval({
  required String employeeName,
  required String reviewTypeLabel,
  required DateTime? submittedAt,
}) {
  String clean(String s) => s.replaceAll(RegExp(r'[\\/:*?"<>|]'), '').trim();
  final name = clean(employeeName).isEmpty ? 'Employee' : clean(employeeName);
  final type = clean(reviewTypeLabel).isEmpty
      ? 'Self-Evaluation'
      : clean(reviewTypeLabel);
  final date = submittedAt == null
      ? 'undated'
      : '${submittedAt.year.toString().padLeft(4, '0')}-'
          '${submittedAt.month.toString().padLeft(2, '0')}-'
          '${submittedAt.day.toString().padLeft(2, '0')}';
  return 'Self-Evaluation - $name - $type - $date.pdf';
}

String _prefixFor(String templateId) {
  switch (templateId) {
    case 'quitclaim':
      return 'Quitclaim';
    case 'coe':
      return 'COE';
    case 'nte':
      return 'NTE';
    case 'non_reg':
      return 'NonReg';
    case 'employment_contract':
      return 'EmploymentContract';
    case 'nda':
      return 'NDA';
    case 'liability_waiver':
      return 'LiabilityWaiver';
    case 'final_pay':
      return 'FinalPay';
    case 'salary_adjustment':
      return 'SalaryAdjustment';
    case 'nod':
      return 'NOD';
    case 'regularization':
      return 'Regularization';
    case 'resignation_acceptance':
      return 'ResignationAcceptance';
    default:
      return templateId;
  }
}
