/// A kind of leave the company recognises, and — the part payroll cares about
/// — whether it is paid.
///
/// Rows are created two ways: by hand in Settings ▸ Leave Types, and
/// automatically by `sync-lark-leaves` when Lark reports a type nobody has seen
/// before. A Lark-created row carries [larkLeaveTypeId] and arrives **unpaid**,
/// because Lark reports a type's name and never whether the company pays for
/// it. Marking one paid is a deliberate act in Settings.
class LeaveType {
  final String id;
  final String companyId;
  final String code;
  final String name;
  final String? description;

  /// Whether payroll pays a full day for leave of this type. The whole reason
  /// this screen exists.
  final bool isPaid;

  final bool isActive;

  /// Non-null when `sync-lark-leaves` created this row from a Lark leave type.
  /// Its presence is what tells you nobody chose these settings.
  final String? larkLeaveTypeId;

  const LeaveType({
    required this.id,
    required this.companyId,
    required this.code,
    required this.name,
    required this.isPaid,
    required this.isActive,
    this.description,
    this.larkLeaveTypeId,
  });

  bool get isFromLark => larkLeaveTypeId != null;

  factory LeaveType.fromRow(Map<String, dynamic> r) => LeaveType(
    id: r['id'] as String,
    companyId: r['company_id'] as String,
    code: (r['code'] ?? '') as String,
    name: (r['name'] ?? '') as String,
    description: r['description'] as String?,
    isPaid: (r['is_paid'] as bool?) ?? false,
    isActive: (r['is_active'] as bool?) ?? true,
    larkLeaveTypeId: r['lark_leave_type_id'] as String?,
  );

  LeaveType copyWith({bool? isPaid, bool? isActive, String? name}) => LeaveType(
    id: id,
    companyId: companyId,
    code: code,
    name: name ?? this.name,
    description: description,
    isPaid: isPaid ?? this.isPaid,
    isActive: isActive ?? this.isActive,
    larkLeaveTypeId: larkLeaveTypeId,
  );
}
