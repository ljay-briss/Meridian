import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meridian_private/controller.dart';

void main() {
  group('Level 1 — Plaza Lookout', () {
    test('responding always rolls the next sighting immediately', () {
      final g = CareerController();
      addTearDown(g.dispose);
      final firstSighting = g.sighting;
      expect(firstSighting, isNotNull);

      g.respond(firstSighting!.correctWord);

      expect(g.sighting, isNotNull);
      expect(g.sightingHandled, isFalse); // ready for the new sighting, not stuck showing "Sent."
    });

    test('the day only advances every few sightings, not on every single answer', () {
      final g = CareerController();
      addTearDown(g.dispose);
      final dayBefore = g.day;

      // Answer one fewer sighting than it takes to complete a day.
      for (var i = 0; i < CareerController.sightingsPerDay - 1; i++) {
        g.respond(g.sighting!.correctWord);
      }
      expect(g.day, dayBefore); // still the same day

      g.respond(g.sighting!.correctWord); // the sighting that completes the day
      expect(g.day, dayBefore + 1);
    });

    test('a wrong answer is penalized immediately (heat/suspicion), not just a strike', () {
      final g = CareerController();
      addTearDown(g.dispose);
      final wrong = g.sighting!.correctWord == 'bird' ? 'snake' : 'bird';
      final heatBefore = g.policeHeat;
      final suspicionBefore = g.cartelSuspicion;

      g.respond(wrong);

      expect(g.strikes, 1);
      expect(g.policeHeat, greaterThan(heatBefore));
      expect(g.cartelSuspicion, greaterThan(suspicionBefore));
      expect(g.lastWarning, isNotNull);
    });

    test('two wrong answers in a row ends the run', () {
      final g = CareerController();
      addTearDown(g.dispose);
      for (var i = 0; i < 2 && !g.gameOver; i++) {
        final wrong = g.sighting!.correctWord == 'bird' ? 'snake' : 'bird';
        g.respond(wrong);
      }
      expect(g.gameOver, isTrue);
      expect(g.arrested, isFalse);
    });

    test('the countdown ticks down once a second while a sighting is pending', () {
      fakeAsync((async) {
        final g = CareerController();
        addTearDown(g.dispose);
        expect(g.secondsRemaining, CareerController.responseWindowSeconds);

        async.elapse(const Duration(seconds: 4));
        expect(g.secondsRemaining, CareerController.responseWindowSeconds - 4);
      });
    });

    test('taking too long to answer is penalized the same as answering wrong', () {
      fakeAsync((async) {
        final g = CareerController();
        addTearDown(g.dispose);
        final heatBefore = g.policeHeat;
        final suspicionBefore = g.cartelSuspicion;

        async.elapse(const Duration(seconds: CareerController.responseWindowSeconds));

        expect(g.strikes, 1);
        expect(g.policeHeat, greaterThan(heatBefore));
        expect(g.cartelSuspicion, greaterThan(suspicionBefore));
        expect(g.lastWarning, isNotNull);
        expect(g.sighting, isNotNull); // a new sighting rolled automatically
      });
    });

    test('answering in time cancels the pending timeout — no duplicate penalty', () {
      fakeAsync((async) {
        final g = CareerController();
        addTearDown(g.dispose);

        async.elapse(const Duration(seconds: 3)); // partway through the first window
        g.respond(g.sighting!.correctWord); // answered — should cancel the original timer

        // Elapse past when the ORIGINAL timer would have fired (15s from start,
        // i.e. 12s from here), but stay under the new sighting's own fresh deadline.
        async.elapse(const Duration(seconds: 13)); // total elapsed: 16s
        expect(g.strikes, 0);
      });
    });
  });
}
