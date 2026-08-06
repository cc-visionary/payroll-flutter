import 'dart:typed_data';

import '../../data/models/role_scorecard.dart';
import '../documents/blocks/block.dart';
import '../documents/blocks/bullet_list_block.dart';
import '../documents/blocks/heading_block.dart';
import '../documents/blocks/key_value_block.dart';
import '../documents/blocks/labelled_bullet_list_block.dart';
import '../documents/blocks/letterhead_block.dart';
import '../documents/blocks/paragraph_block.dart';
import '../documents/blocks/section_heading_block.dart';
import '../documents/blocks/spacer_block.dart';
import '../documents/blocks/table_block.dart';
import '../documents/blocks/title_block.dart';

/// Maps a role scorecard to the ordered PDF blocks for an employee-facing role
/// reference. Pure — no I/O. Empty sections are omitted so a sparse card never
/// renders a blank heading. Section numbers are assigned in render order, so
/// omitting a section does not leave a gap in the numbering.
List<Block> roleCardBlocks(
  RoleScorecard card, {
  Uint8List? logoBytes,
  String companyName = '',
  String? companyAddress,
}) {
  final blocks = <Block>[];
  var section = 0;

  if (logoBytes != null || companyName.isNotEmpty) {
    blocks.add(
      LetterheadBlock(
        logoBytes: logoBytes,
        companyName: companyName,
        companyAddress: (companyAddress?.trim().isEmpty ?? true)
            ? null
            : companyAddress,
      ),
    );
    blocks.add(const SpacerBlock(16));
  }

  blocks.add(TitleBlock(card.jobTitle));
  blocks.add(
    KeyValueBlock([
      KeyValueRow(
        'Effective date',
        card.effectiveDate.toIso8601String().substring(0, 10),
      ),
      KeyValueRow('Status', card.isActive ? 'Active' : 'Inactive'),
    ]),
  );

  if (card.missionStatement.trim().isNotEmpty) {
    blocks.add(SectionHeadingBlock(number: ++section, title: 'Mission'));
    blocks.add(ParagraphBlock(card.missionStatement));
  }

  if (card.responsibilities.isNotEmpty) {
    blocks.add(
      SectionHeadingBlock(number: ++section, title: 'Key Responsibilities'),
    );
    for (final area in card.responsibilities) {
      blocks.add(HeadingBlock(area.area));
      if (area.tasks.isNotEmpty) {
        blocks.add(BulletListBlock(area.tasks));
      }
    }
  }

  if (card.kpis.isNotEmpty) {
    blocks.add(
      SectionHeadingBlock(
        number: ++section,
        title: 'Key Performance Indicators',
      ),
    );
    blocks.add(
      TableBlock(
        headers: const ['KPI', 'Measurement', 'Target', 'Frequency'],
        rows: [
          for (final kpi in card.kpis)
            [kpi.name, kpi.measurement, kpi.target, kpi.frequency],
        ],
      ),
    );
  }

  if (card.requiredSkills.isNotEmpty) {
    blocks.add(
      SectionHeadingBlock(number: ++section, title: 'Required Skills'),
    );
    blocks.add(
      LabelledBulletListBlock(
        items: [
          for (final skill in card.requiredSkills)
            LabelledBulletItem(leadBold: skill.name, body: skill.description),
        ],
      ),
    );
  }

  if (card.behavioralExpectations.isNotEmpty) {
    blocks.add(
      SectionHeadingBlock(number: ++section, title: 'Behavioral Expectations'),
    );
    blocks.add(
      LabelledBulletListBlock(
        items: [
          for (final behavior in card.behavioralExpectations)
            LabelledBulletItem(
              leadBold: behavior.name,
              body: behavior.description,
            ),
        ],
      ),
    );
  }

  return blocks;
}
