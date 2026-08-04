import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/employee.dart';
import '../../data/repositories/employee_repository.dart';
import 'templates/document_template.dart';

SignatoryInfo? _info(Employee? e) => e == null
    ? null
    : SignatoryInfo(
        name: e.fullName,
        title: (e.signatoryTitle?.isNotEmpty ?? false) ? e.signatoryTitle : null,
        signaturePngB64: e.signaturePngB64,
      );

/// Resolve both flagged signatories for document autofill. Errors degrade
/// to nulls so generation still works when the lookup fails (fields fall
/// back to hiring-entity defaults).
Future<({SignatoryInfo? hr, SignatoryInfo? legal})> loadAutofillSignatories(
    WidgetRef ref) async {
  try {
    final hr = await ref.read(hrSignatoryProvider.future);
    final legal = await ref.read(legalSignatoryProvider.future);
    return (hr: _info(hr), legal: _info(legal));
  } catch (_) {
    return (hr: null, legal: null);
  }
}
