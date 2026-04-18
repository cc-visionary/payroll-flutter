class Role {
  final String id;
  final String code;
  final String name;
  final String? description;
  final List<String> permissions;
  final bool isSystem;

  const Role({
    required this.id,
    required this.code,
    required this.name,
    this.description,
    required this.permissions,
    required this.isSystem,
  });

  bool get hasWildcard => permissions.contains('*');

  factory Role.fromRow(Map<String, dynamic> r) {
    final raw = r['permissions'];
    final perms = <String>[];
    if (raw is List) {
      for (final p in raw) {
        if (p is String) perms.add(p);
      }
    }
    return Role(
      id: r['id'] as String,
      code: r['code'] as String,
      name: r['name'] as String,
      description: r['description'] as String?,
      permissions: perms,
      isSystem: r['is_system'] as bool? ?? false,
    );
  }
}

class UserRoleAssignment {
  final String userId;
  final String email;
  final String? employeeName;
  final DateTime? assignedAt;

  const UserRoleAssignment({
    required this.userId,
    required this.email,
    this.employeeName,
    this.assignedAt,
  });
}
