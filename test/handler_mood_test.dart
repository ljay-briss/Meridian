import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meridian_private/controller.dart';
import 'package:meridian_private/data.dart';

void main() {
  group('Handler mood', () {
    test('a wrong sighting response now gets a handler reaction line', () {
      final g = CareerController();
      addTearDown(g.dispose);
      g.startShift();
      final wrong = g.sighting!.correctWord == 'bird' ? 'snake' : 'bird';
      final before = g.threads['handler']!.length;
      g.respond(wrong);
      final thread = g.threads['handler']!;
      // player's wrong word + handler's reaction = at least 2 new messages
      expect(thread.length, greaterThanOrEqualTo(before + 2));
      final reaction = thread.last;
      expect(reaction.fromMe, isFalse);
      expect(kHandlerWrongLines.map((l) => l.text), contains(reaction.text));
    });

    test('mood rises on a correct report and falls on a wrong one', () {
      final correctGame = CareerController();
      addTearDown(correctGame.dispose);
      correctGame.startShift();
      correctGame.respond(correctGame.sighting!.correctWord);
      expect(correctGame.handlerMood.mood, greaterThan(0));

      final wrongGame = CareerController();
      addTearDown(wrongGame.dispose);
      wrongGame.startShift();
      final wrong = wrongGame.sighting!.correctWord == 'bird' ? 'snake' : 'bird';
      wrongGame.respond(wrong);
      expect(wrongGame.handlerMood.mood, lessThan(0));
    });

    test('handler reaction lines vary across repeated correct reports', () {
      // pickLine's VarietyBoost (recency/frequency weighting) replaced the
      // old hard "never immediately repeat" rule with a soft preference —
      // repeats are now heavily discouraged, not impossible. Assert variety
      // over many trials instead of a strict no-repeat guarantee.
      final g = CareerController();
      addTearDown(g.dispose);
      final seen = <String>{};
      fakeAsync((async) {
        g.startShift();
        for (var i = 0; i < 30; i++) {
          final before = g.threads['handler']!.length;
          g.respond(g.sighting!.correctWord);
          final reaction = g.threads['handler']!.sublist(before).lastWhere((m) => !m.fromMe);
          seen.add(reaction.text);
          async.elapse(const Duration(seconds: CareerController.sightingGapSeconds));
        }
      });
      expect(seen.length, greaterThan(1));
      for (final text in seen) {
        expect(kHandlerApprovalLines.map((l) => l.text), contains(text));
      }
    });

    test('restart resets handler mood', () {
      final g = CareerController();
      addTearDown(g.dispose);
      g.startShift();
      g.respond(g.sighting!.correctWord);
      expect(g.handlerMood.mood, isNot(0));
      g.restart();
      expect(g.handlerMood.mood, 0);
      expect(g.handlerMood.memories, isEmpty);
    });
  });
}
