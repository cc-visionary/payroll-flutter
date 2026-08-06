import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Mirrors the AppBar `actions` structure added to PerformanceScreen, in
// isolation, to check whether a FilledButton.icon action renders/hit-tests
// with a real size.
void main() {
  testWidgets(
    'AppBar FilledButton.icon action has a non-zero size and hit-tests',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            appBar: AppBar(
              title: const Text('Performance'),
              actions: [
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilledButton.icon(
                    onPressed: () {},
                    icon: const Icon(Icons.add),
                    label: const Text('New check-in'),
                  ),
                ),
              ],
            ),
            body: const SizedBox.expand(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final size = tester.getSize(
        find.widgetWithText(FilledButton, 'New check-in'),
      );
      expect(size.width, greaterThan(0));
      expect(size.height, greaterThan(0));

      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: Offset.zero);
      addTearDown(gesture.removePointer);
      await gesture.moveTo(tester.getCenter(find.text('New check-in')));
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );
}
