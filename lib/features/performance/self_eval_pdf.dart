import 'package:pdf/widgets.dart' as pw;

import '../../data/repositories/lark_self_eval_repository.dart';
import '../documents/blocks/block.dart';
import '../documents/blocks/emphasis_paragraph_block.dart';
import '../documents/blocks/key_value_block.dart';
import '../documents/blocks/paragraph_block.dart';
import '../documents/blocks/section_heading_block.dart';
import '../documents/blocks/spacer_block.dart';
import '../documents/blocks/table_block.dart';
import '../documents/blocks/title_block.dart';

/// Human-friendly label for a self-eval review type code.
///
/// `PROBATIONARY_M1/_M3/_M6` map to the ordinal probationary milestones and
/// `QUARTERLY` to the quarterly check-in. Any other code is title-cased from
/// its raw underscore form so an unforeseen type still renders sensibly.
String reviewTypeLabel(String reviewType) {
  switch (reviewType.toUpperCase()) {
    case 'PROBATIONARY_M1':
      return 'Probationary — 1st Month';
    case 'PROBATIONARY_M3':
      return 'Probationary — 3rd Month';
    case 'PROBATIONARY_M6':
      return 'Probationary — 6th Month';
    case 'QUARTERLY':
      return 'Quarterly Check-In';
    default:
      return reviewType
          .toLowerCase()
          .split(RegExp(r'[_\s]+'))
          .where((w) => w.isNotEmpty)
          .map((w) => '${w[0].toUpperCase()}${w.substring(1)}')
          .join(' ');
  }
}

/// Maps a single self-evaluation response to the ordered PDF blocks for a
/// printable copy. Pure — no I/O. Empty sections are omitted so a sparse
/// response never renders a blank heading; section numbers are assigned in
/// render order so omitting one leaves no gap.
List<Block> selfEvalBlocks(SelfEvalDetail detail) {
  final r = detail.response;
  final blocks = <Block>[];

  blocks.add(const TitleBlock('Self-Evaluation'));
  blocks.add(const SpacerBlock(8));
  blocks.add(
    KeyValueBlock([
      KeyValueRow('Employee', detail.fullName.isEmpty ? '—' : detail.fullName),
      if (detail.employeeNumber.trim().isNotEmpty)
        KeyValueRow('Employee #', detail.employeeNumber),
      if ((detail.departmentName ?? '').trim().isNotEmpty)
        KeyValueRow('Department', detail.departmentName!),
      if ((detail.jobTitle ?? '').trim().isNotEmpty)
        KeyValueRow('Position', detail.jobTitle!),
      KeyValueRow('Review type', reviewTypeLabel(r.reviewType)),
      KeyValueRow(
        'Submitted',
        r.submittedAt == null
            ? 'Unknown'
            : r.submittedAt!.toIso8601String().substring(0, 10),
      ),
    ]),
  );

  var section = 0;

  final ratings = r.ratings.entries
      .where((e) => '${e.value}'.trim().isNotEmpty)
      .toList();
  if (ratings.isNotEmpty) {
    blocks.add(const SpacerBlock(16));
    blocks.add(SectionHeadingBlock(number: ++section, title: 'Ratings'));
    blocks.add(const SpacerBlock(8));
    blocks.add(
      TableBlock(
        headers: const ['Question', 'Score'],
        rows: [
          for (final e in ratings) [e.key, '${_scoreText(e.value)} / 5'],
        ],
      ),
    );
  }

  // Text answers, excluding any question already shown as a rating so a
  // question that appears in both maps is not duplicated.
  final ratingKeys = r.ratings.keys.toSet();
  final answers = r.answers.entries
      .where((e) => !ratingKeys.contains(e.key))
      .where((e) => '${e.value}'.trim().isNotEmpty)
      .toList();
  if (answers.isNotEmpty) {
    blocks.add(const SpacerBlock(16));
    blocks.add(SectionHeadingBlock(number: ++section, title: 'Responses'));
    for (final e in answers) {
      blocks.add(const SpacerBlock(8));
      blocks.add(
        EmphasisParagraphBlock(
          spans: [EmphasisSpan(e.key, bold: true)],
          align: pw.TextAlign.left,
        ),
      );
      blocks.add(const SpacerBlock(2));
      blocks.add(ParagraphBlock('${e.value}', align: pw.TextAlign.left));
    }
  }

  return blocks;
}

/// Render a rating value as a compact score. Whole numbers drop the decimal
/// (`4` not `4.0`); non-numeric values pass through unchanged.
String _scoreText(Object? value) {
  final n = value is num ? value : num.tryParse('$value');
  if (n == null) return '$value';
  return n == n.roundToDouble() ? n.toInt().toString() : '$n';
}
