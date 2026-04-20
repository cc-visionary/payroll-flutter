class ManagedUser {
  final String userId;
  final String email;
  final String? roleCode;
  final String status; // ACTIVE / INACTIVE
  final bool mustChangePassword;
  final DateTime? invitedAt;
  final String? invitedBy;
  final DateTime? lastSignInAt;
  final String? linkedEmployeeId;
  final String? linkedEmployeeName;

  const ManagedUser({
    required this.userId,
    required this.email,
    required this.roleCode,
    required this.status,
    required this.mustChangePassword,
    required this.invitedAt,
    required this.invitedBy,
    required this.lastSignInAt,
    required this.linkedEmployeeId,
    required this.linkedEmployeeName,
  });

  bool get isInactive => status == 'INACTIVE';

  String displayName() {
    if (linkedEmployeeName != null && linkedEmployeeName!.isNotEmpty) {
      return linkedEmployeeName!;
    }
    final at = email.indexOf('@');
    return at > 0 ? email.substring(0, at) : email;
  }
}

class UnlinkedEmployee {
  final String id;
  final String name;
  const UnlinkedEmployee({required this.id, required this.name});
}
