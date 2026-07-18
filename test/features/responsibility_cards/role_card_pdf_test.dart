import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/data/models/role_scorecard.dart';
import 'package:payroll_flutter/features/documents/blocks/bullet_list_block.dart';
import 'package:payroll_flutter/features/documents/blocks/heading_block.dart';
import 'package:payroll_flutter/features/documents/blocks/labelled_bullet_list_block.dart';
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

  test('responsibilities render as a heading + bullet list per area', () {
    final blocks = roleCardBlocks(buildCard(
      responsibilities: const [
        ResponsibilityArea(
            area: 'Merchandising', tasks: ['Curate drops', 'Plan calendar']),
      ],
    ));
    expect(blocks.whereType<HeadingBlock>().map((b) => b.text),
        contains('Merchandising'));
    final bullets = blocks.whereType<BulletListBlock>().toList();
    expect(bullets, isNotEmpty);
    expect(bullets.first.items, ['Curate drops', 'Plan calendar']);
  });

  test('labelled items (skills/behaviors) always have a non-empty label and body', () {
    final items = roleCardBlocks(buildCard())
        .whereType<LabelledBulletListBlock>()
        .expand((b) => b.items)
        .toList();
    expect(items, isNotEmpty);
    for (final item in items) {
      expect(item.leadBold, isNotEmpty);
      expect(item.body, isNotEmpty);
    }
  });
}
