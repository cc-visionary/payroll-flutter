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
  final ymd = '${date.year.toString().padLeft(4, '0')}'
      '${date.month.toString().padLeft(2, '0')}'
      '${date.day.toString().padLeft(2, '0')}';
  return '${prefix}_${id}_$ymd.pdf';
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
    default:
      return templateId;
  }
}
