import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:meridian_private/main.dart';

void main() {
  testWidgets('Level 1 home screen shows balance and watch status', (WidgetTester tester) async {
    await tester.pumpWidget(const MeridianApp());
    await tester.pump();

    expect(find.text('BALANCE'), findsOneWidget);
    expect(find.text('ON WATCH'), findsOneWidget);
    expect(find.text('KEY'), findsOneWidget);
    expect(find.text('"bird"'), findsNWidgets(2)); // once in the key, once on the reply button

    // Level 1 runs a live response-window timer; unmount to dispose the
    // controller and cancel it, or the test fails on a pending Timer.
    await tester.pumpWidget(const SizedBox());
  });
}
