class Kpi {
  final String id;
  final String companyId;
  final String name;
  final String? category;
  final String? description;
  final String? measurementUnit;
  final bool isActive;

  /// The department that owns this measure. Organisational only — a role card
  /// in another department may still link it.
  final String? departmentId;
  const Kpi({
    required this.id,
    required this.companyId,
    required this.name,
    this.category,
    this.description,
    this.measurementUnit,
    this.isActive = true,
    this.departmentId,
  });
  factory Kpi.fromRow(Map<String, dynamic> r) => Kpi(
    id: r['id'] as String,
    companyId: r['company_id'] as String,
    name: r['name'] as String,
    category: r['category'] as String?,
    description: r['description'] as String?,
    measurementUnit: r['measurement_unit'] as String?,
    isActive: r['is_active'] as bool? ?? true,
    departmentId: r['department_id'] as String?,
  );
  Map<String, dynamic> toInsert(String companyId) => {
    'company_id': companyId,
    'name': name.trim(),
    'category': (category?.trim().isEmpty ?? true) ? null : category!.trim(),
    'description':
        (description?.trim().isEmpty ?? true) ? null : description!.trim(),
    'measurement_unit': (measurementUnit?.trim().isEmpty ?? true)
        ? null
        : measurementUnit!.trim(),
    'is_active': isActive,
    'department_id': departmentId,
  };
}

/// One KPI attached to a role card, as edited in the form.
class KpiLinkInput {
  final String? kpiId; // null → create the library KPI on save
  final String name;
  final String? measurementUnit;
  final String? category;
  final String target;
  final String frequency;
  const KpiLinkInput({
    this.kpiId,
    required this.name,
    this.measurementUnit,
    this.category,
    required this.target,
    required this.frequency,
  });
}
