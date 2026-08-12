import '../../data/models/employee.dart';
import '../../data/models/role_scorecard.dart';
import 'org_tree.dart';

/// A single Accountability Chart box: one function, at most one holder.
///
/// EOS's one-seat-one-name rule expands a seat with N active holders into N
/// boxes, and — the point of the whole tool — a seat with none into exactly
/// one open box rather than zero. An open box is the finding; collapsing it
/// away would hide it.
class SeatBox {
  final String seatId;
  final String function;
  final String? holderName;
  final String? holderId;
  final List<String> roles;

  SeatBox({
    required this.seatId,
    required this.function,
    required this.holderName,
    required this.holderId,
    required this.roles,
  });

  bool get isOpen => holderId == null;
}

/// Expands each seat into one box per active holder, or one open box when the
/// seat has none. A holder is an employee whose `employmentStatus` is
/// `'ACTIVE'` and who has not been soft-deleted — the same filter
/// `role/people_pane.dart` uses for a seat's roster.
List<SeatBox> seatBoxes({
  required List<RoleScorecard> seats,
  required List<Employee> employees,
  required Map<String, List<String>> areasBySeat,
}) {
  final boxes = <SeatBox>[];
  for (final seat in seats) {
    final holders = employees.where(
      (e) =>
          e.roleScorecardId == seat.id &&
          e.employmentStatus == 'ACTIVE' &&
          e.deletedAt == null,
    );
    final roles = areasBySeat[seat.id] ?? const <String>[];
    if (holders.isEmpty) {
      boxes.add(
        SeatBox(
          seatId: seat.id,
          function: seat.jobTitle,
          holderName: null,
          holderId: null,
          roles: roles,
        ),
      );
    } else {
      for (final holder in holders) {
        boxes.add(
          SeatBox(
            seatId: seat.id,
            function: seat.jobTitle,
            holderName: holder.firstName,
            holderId: holder.id,
            roles: roles,
          ),
        );
      }
    }
  }
  return boxes;
}

/// Error for a seat drag (make [movingSeatId] report to [newParentId]), or
/// null when valid. Guards self-parenting and cycles, mirroring
/// `reportingDropError` in `structure_rows.dart` for the seat tree instead of
/// the people tree.
String? seatDropError({
  required String movingSeatId,
  required String newParentId,
  required List<({String id, String? parentId})> seats,
}) {
  if (movingSeatId == newParentId) return "A seat can't report to itself.";
  if (wouldCreateCycle(
    movingId: movingSeatId,
    newParentId: newParentId,
    people: seats,
  )) {
    return 'That would create a reporting loop.';
  }
  return null;
}
