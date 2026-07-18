import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/data/models/role_scorecard.dart';
import 'package:payroll_flutter/features/documents/blocks/section_heading_block.dart';
import 'package:payroll_flutter/features/documents/blocks/table_block.dart';
import 'package:payroll_flutter/features/documents/blocks/title_block.dart';
import 'package:payroll_flutter/features/responsibility_cards/role_card_pdf.dart';

RoleScorecard buildCard({
  String mission = 'Own the storefront experience.',
  List<ResponsibilityArea> responsibilities = const [
    ResponsibilityArea(area: 'Merchandising', tasks: ['Curate weekly drops']),
  ],
  List<KpiItem> kpis = const [
    KpiItem(
        name: 'Conversion',
        measurement: 'CVR %',
        target: '3%',
        frequency: 'Monthly'),
  ],
  List<RequiredSkill> skills = const [
    RequiredSkill(name: 'Excel', description: 'Pivot tables'),
  ],
  List<BehavioralExpectation> behaviors = const [
    BehavioralExpectation(name: 'Ownership', description: 'Sees issues through'),
  ],
}) =>
    RoleScorecard(
      id: 'card-1',
      companyId: 'co-1',
      jobTitle: 'Brand Associate',
      missionStatement: mission,
      responsibilities: responsibilities,
      kpis: kpis,
      requiredSkills: skills,
      behavioralExpectations: behaviors,
      wageType: 'MONTHLY',
      workHoursPerDay: 8,
      workDaysPerWeek: 'MON_FRI',
      isActive: true,
      effectiveDate: DateTime(2026, 1, 1),
    );

void main() {
  test('a populated card renders every section in order', () {
    final blocks = roleCardBlocks(buildCard());
    expect(blocks.whereType<TitleBlock>().length, 1);
    final headings =
        blocks.whereType<SectionHeadingBlock>().map((b) => b.title).toList();
    expect(headings, [
      'Mission',
      'Key Responsibilities',
      'Key Performance Indicators',
      'Required Skills',
      'Behavioral Expectations',
    ]);
    expect(
      blocks.whereType<SectionHeadingBlock>().map((b) => b.number).toList(),
      [1, 2, 3, 4, 5],
    );
    expect(blocks.whereType<TableBlock>().length, 1);
  });

  test('empty sections are omitted and numbering stays sequential', () {
    final blocks = roleCardBlocks(buildCard(
      mission: '',
      kpis: const [],
      skills: const [],
      behaviors: const [],
    ));
    final headings =
        blocks.whereType<SectionHeadingBlock>().map((b) => b.title).toList();
    expect(headings, ['Key Responsibilities']);
    expect(blocks.whereType<SectionHeadingBlock>().single.number, 1);
    expect(blocks.whereType<TableBlock>(), isEmpty);
  });

  test('with no branding the first block is the title, not a letterhead', () {
    final blocks = roleCardBlocks(buildCard());
    expect(blocks.first, isA<TitleBlock>());
  });
}
