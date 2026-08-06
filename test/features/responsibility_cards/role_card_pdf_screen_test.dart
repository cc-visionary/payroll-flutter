import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:payroll_flutter/features/documents/providers.dart';
import 'package:payroll_flutter/features/responsibility_cards/role_card_pdf_screen.dart';

void main() {
  testWidgets('shows a not-found message when the card is missing', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          roleScorecardByIdProvider(
            'missing',
          ).overrideWith((ref) async => null),
        ],
        child: const MaterialApp(home: RoleCardPdfScreen(cardId: 'missing')),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Role card not found.'), findsOneWidget);
  });
}
