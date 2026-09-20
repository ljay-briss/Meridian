import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:meridian_private/main.dart';

void main() {
  testWidgets('Level 1 home screen shows balance and watch status', (WidgetTester tester) async {
    await tester.pumpWidget(const MeridianApp());
    await tester.pump();

    // First launch shows the one-time vehicle field guide before Level 1 is
    // playable at all — dismiss it to reach the home screen.
    expect(find.text('Know the road'), findsOneWidget);
    await tester.tap(find.text('Got it — I\'m watching the road'));
    await tester.pump();

    expect(find.text('BALANCE'), findsOneWidget);
    expect(find.text('KEY'), findsOneWidget);

    // The shift hasn't started yet — no sighting, no "ON WATCH" readout.
    expect(find.text('ON WATCH'), findsNothing);
    final startShiftButton = find.text('Start shift');
    expect(startShiftButton, findsOneWidget);

    // The button sits below the fold in the test viewport — scroll it into
    // view before tapping, or the tap misses everything.
    await tester.ensureVisible(startShiftButton);
    await tester.tap(startShiftButton);
    await tester.pump();

    expect(find.text('ON WATCH'), findsOneWidget);
    expect(find.text('"bird"'), findsNWidgets(2)); // once in the key, once on the reply button

    // Level 1 runs live response-window and shift timers; unmount to dispose
    // the controller and cancel them, or the test fails on a pending Timer.
    await tester.pumpWidget(const SizedBox());
  });
}
