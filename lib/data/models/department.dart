class Department {
  final String id;
  final String companyId;
  final String code;
  final String name;
  final String? parentDepartmentId;
  final String? costCenterCode;
  final String? managerId;
  final DateTime? deletedAt;

  const Department({
    required this.id,
    required this.companyId,
    required this.code,
    required this.name,
    this.parentDepartmentId,
    this.costCenterCode,
    this.managerId,
    this.deletedAt,
  });

  factory Department.fromRow(Map<String, dynamic> r) => Department(
        id: r['id'] as String,
        companyId: r['company_id'] as String,
        code: r['code'] as String,
        name: r['name'] as String,
        parentDepartmentId: r['parent_department_id'] as String?,
        costCenterCode: r['cost_center_code'] as String?,
        managerId: r['manager_id'] as String?,
        deletedAt: r['deleted_at'] == null
            ? null
            : DateTime.parse(r['deleted_at'] as String),
      );
}
