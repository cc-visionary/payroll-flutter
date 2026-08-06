import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/features/workforce_planning/tabs/tab_intro.dart';

Widget _host(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  testWidgets('the purpose is always visible, the detail is not', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        const TabIntro(
          purpose: 'Move work until nobody is over capacity.',
          details: [WpGlossary.load],
        ),
      ),
    );
    expect(
      find.text('Move work until nobody is over capacity.'),
      findsOneWidget,
    );
    expect(
      find.textContaining('÷ that person', findRichText: true),
      findsNothing,
      reason: 'help that cannot be dismissed becomes furniture',
    );
    expect(find.text('How this works'), findsOneWidget);
  });

  testWidgets('expanding reveals the terms and collapsing hides them again', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        const TabIntro(
          purpose: 'Anything',
          details: [WpGlossary.load, WpGlossary.derived],
        ),
      ),
    );

    await tester.tap(find.text('How this works'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Over 100% = Over', findRichText: true),
      findsOneWidget,
    );
    expect(
      find.textContaining('whoever holds its role card', findRichText: true),
      findsOneWidget,
    );

    await tester.tap(find.text('Hide'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Over 100% = Over', findRichText: true),
      findsNothing,
    );
  });

  testWidgets('with no details there is nothing to expand', (tester) async {
    await tester.pumpWidget(
      _host(const TabIntro(purpose: 'Just a line', details: [])),
    );
    expect(find.text('Just a line'), findsOneWidget);
    expect(find.text('How this works'), findsNothing);
  });

  testWidgets('a trailing widget shares the row', (tester) async {
    await tester.pumpWidget(
      _host(
        const TabIntro(
          purpose: 'Anything',
          details: [],
          trailing: Text('42 tasks'),
        ),
      ),
    );
    expect(find.text('42 tasks'), findsOneWidget);
  });

  // The glossary exists so one word cannot mean two things on two tabs.
  test('glossary entries are non-empty and distinct', () {
    const all = [
      WpGlossary.derived,
      WpGlossary.weighted,
      WpGlossary.load,
      WpGlossary.notCosted,
      WpGlossary.unassigned,
      WpGlossary.multiplier,
      WpGlossary.node,
    ];
    for (final e in all) {
      expect(e.term.trim(), isNotEmpty);
      expect(
        e.meaning.trim().length,
        greaterThan(20),
        reason: 'a one-word gloss explains nothing',
      );
    }
    expect(all.map((e) => e.term).toSet(), hasLength(all.length));
  });
}
