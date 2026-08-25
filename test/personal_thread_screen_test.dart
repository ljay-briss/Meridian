import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meridian_private/controller.dart';
import 'package:meridian_private/conversation/intents.dart';
import 'package:meridian_private/data.dart';
import 'package:meridian_private/theme.dart';
import 'package:meridian_private/screens/relationships_screen.dart';

Widget _harness(CareerController g) => AppScope(
      controller: g,
      child: ListenableBuilder(
        listenable: g,
        builder: (context, _) => MaterialApp(
          theme: appThemeData(AppColors.standard()),
          home: const PersonalThreadScreen(contactId: 'mama'),
        ),
      ),
    );

void main() {
  group('PersonalThreadScreen reply-action composer', () {
    testWidgets('shows exactly the contextual options personalReplyOptions computes', (tester) async {
      final g = CareerController();
      addTearDown(g.dispose);
      g.devJumpToLevel(4); // cancels level 1's live sighting timer, which the test binding disallows leaving pending
      await tester.pumpWidget(_harness(g));
      await tester.pump();

      expect(find.text('No messages yet.'), findsOneWidget);
      final shown = g.personalReplyOptions('mama');
      final rel = g.relationships['mama']!;
      // Mama's tray is intent chips (see conversation/intents.dart), not the
      // legacy scripted-sentence catalog — kPersonalReplyActions never
      // surfaces for her at all, so 'Flirt' (romantic-partner-only anyway)
      // trivially never shows. personalReplyOptions only includes a chip
      // once something about the current state actually favors it (see
      // CareerController._intentChipScore's 1.0 baseline), so the count is
      // capped at 5 rather than always exactly 5.
      expect(shown.whereType<IntentChip>().length, greaterThan(0));
      expect(shown.whereType<IntentChip>().length, lessThanOrEqualTo(5));
      for (final option in shown) {
        expect(find.text(option.displayLabel(rel, g.timeOfDay)), findsOneWidget);
      }
      expect(shown.whereType<IntentChip>().any((c) => c.label == 'Flirt'), isFalse);
    });

    testWidgets('tapping an intent chip posts a phrasing and a reaction line appears', (tester) async {
      final g = CareerController();
      addTearDown(g.dispose);
      g.devJumpToLevel(4); // cancels level 1's live sighting timer, which the test binding disallows leaving pending
      await tester.pumpWidget(_harness(g));
      await tester.pump();

      final rel = g.relationships['mama']!;
      final chip = kIntentChips.firstWhere((c) => c.intent == ConversationIntent.checkIn);
      final finder = find.text(chip.displayLabel(rel, g.timeOfDay));
      await tester.ensureVisible(finder); // the tray scrolls horizontally, so a later chip can start off-screen
      await tester.pump();
      await tester.tap(finder);
      await tester.pump();

      expect(g.personalThreads['mama']!.length, 2);
      expect(g.personalThreads['mama']!.first.fromMe, isTrue);
      expect(g.personalThreads['mama']!.last.fromMe, isFalse);
      // The sent line came from the chip's own phrasing pool.
      expect(chip.phrasings.map((l) => l.text), contains(g.personalThreads['mama']!.first.text));
    });

    testWidgets('a blocked contact shows the reply options replaced by a status line', (tester) async {
      final g = CareerController();
      addTearDown(g.dispose);
      g.devJumpToLevel(4); // cancels level 1's live sighting timer, which the test binding disallows leaving pending
      g.relationships['mama']!.isBlocked = true;
      await tester.pumpWidget(_harness(g));
      await tester.pump();

      for (final chip in kIntentChips) {
        expect(find.text('(${chip.label})'), findsNothing, reason: chip.label);
      }
      expect(find.text("They've blocked you."), findsOneWidget);
    });
  });
}
