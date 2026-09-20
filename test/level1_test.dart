import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meridian_private/controller.dart';

void main() {
  group('Level 1 — Plaza Lookout', () {
    test('the shift doesn\'t start on its own — no sighting until startShift() is called', () {
      final g = CareerController();
      addTearDown(g.dispose);
      expect(g.dayStarted, isFalse);
      expect(g.sighting, isNull);

      g.startShift();
      expect(g.dayStarted, isTrue);
      expect(g.sighting, isNotNull);
    });

    test('the road goes quiet right after answering, then the next sighting rolls after the gap', () {
      fakeAsync((async) {
        final g = CareerController();
        addTearDown(g.dispose);
        g.startShift();
        final firstSighting = g.sighting;
        expect(firstSighting, isNotNull);

        g.respond(firstSighting!.correctWord);
        expect(g.sighting, isNull); // quiet road — nothing to report yet
        expect(g.sightingHandled, isTrue); // not re-answerable during the gap

        async.elapse(const Duration(seconds: CareerController.sightingGapSeconds));
        expect(g.sighting, isNotNull);
        expect(g.sightingHandled, isFalse); // ready for the new sighting, not stuck showing "Sent."
      });
    });

    test('answering many sightings doesn\'t end the day early — only the shift clock does', () {
      fakeAsync((async) {
        final g = CareerController();
        addTearDown(g.dispose);
        g.startShift();
        final dayBefore = g.day;

        // Far more sightings than the old 3-per-day count would ever have
        // allowed, well under the 5-minute shift clock.
        for (var elapsed = 0; elapsed < 60; elapsed++) {
          if (g.sighting != null) g.respond(g.sighting!.correctWord);
          async.elapse(const Duration(seconds: 1));
        }

        expect(g.day, dayBefore); // still the same day
        expect(g.dayStarted, isTrue); // shift still running
      });
    });

    test('the day advances once the 5-minute shift clock runs out, independent of sighting count', () {
      fakeAsync((async) {
        final g = CareerController();
        addTearDown(g.dispose);
        g.startShift();
        final dayBefore = g.day;

        var elapsed = 0;
        while (elapsed < CareerController.dayDurationSeconds && g.dayStarted) {
          if (g.sighting != null) g.respond(g.sighting!.correctWord);
          async.elapse(const Duration(seconds: 1));
          elapsed += 1;
        }

        expect(g.day, dayBefore + 1);
        expect(g.dayStarted, isFalse); // back to the "start shift" idle state
        expect(g.gameOver, isFalse); // every sighting was answered correctly throughout
      });
    });

    test('a wrong answer is penalized immediately (heat/suspicion), not just a strike', () {
      final g = CareerController();
      addTearDown(g.dispose);
      g.startShift();
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
      fakeAsync((async) {
        final g = CareerController();
        addTearDown(g.dispose);
        g.startShift();
        for (var i = 0; i < 2 && !g.gameOver; i++) {
          final wrong = g.sighting!.correctWord == 'bird' ? 'snake' : 'bird';
          g.respond(wrong);
          if (!g.gameOver) async.elapse(const Duration(seconds: CareerController.sightingGapSeconds));
        }
        expect(g.gameOver, isTrue);
        expect(g.arrested, isFalse);
      });
    });

    test('the countdown ticks down once a second while a sighting is pending', () {
      fakeAsync((async) {
        final g = CareerController();
        addTearDown(g.dispose);
        g.startShift();
        expect(g.secondsRemaining, CareerController.responseWindowSeconds);

        async.elapse(const Duration(seconds: 4));
        expect(g.secondsRemaining, CareerController.responseWindowSeconds - 4);
      });
    });

    test('taking too long to answer is penalized the same as answering wrong', () {
      fakeAsync((async) {
        final g = CareerController();
        addTearDown(g.dispose);
        g.startShift();
        final heatBefore = g.policeHeat;
        final suspicionBefore = g.cartelSuspicion;

        async.elapse(const Duration(seconds: CareerController.responseWindowSeconds));

        expect(g.strikes, 1);
        expect(g.policeHeat, greaterThan(heatBefore));
        expect(g.cartelSuspicion, greaterThan(suspicionBefore));
        expect(g.lastWarning, isNotNull);
        expect(g.sighting, isNull); // quiet road during the gap, not an instant re-roll

        async.elapse(const Duration(seconds: CareerController.sightingGapSeconds));
        expect(g.sighting, isNotNull); // a new sighting rolled after the gap
      });
    });

    test('the promotion bar advances after every clean day, not just once a week', () {
      fakeAsync((async) {
        final g = CareerController();
        addTearDown(g.dispose);
        g.startShift();
        expect(g.levelProgress, 0);

        final dayBefore = g.day;
        var elapsed = 0;
        while (g.day == dayBefore && elapsed <= CareerController.dayDurationSeconds) {
          if (g.sighting != null) g.respond(g.sighting!.correctWord);
          async.elapse(const Duration(seconds: 1));
          elapsed += 1;
        }

        expect(g.day, dayBefore + 1); // one clean day closed out
        expect(g.gameOver, isFalse);
        expect(g.levelProgress, greaterThan(0)); // the bar has moved…
        expect(g.levelProgress, lessThan(1 / CareerController.kCleanWeeksToPromote)); // …but a single day isn't a whole week
      });
    });

    test('a strike this week zeroes the in-progress fraction of the bar', () {
      final g = CareerController();
      addTearDown(g.dispose);
      g.startShift();
      final wrong = g.sighting!.correctWord == 'bird' ? 'snake' : 'bird';

      g.respond(wrong); // strike 1 — not dead yet, but this week is voided

      expect(g.gameOver, isFalse);
      expect(g.levelProgress, 0);
    });

    test('answering in time cancels the pending timeout — no duplicate penalty', () {
      fakeAsync((async) {
        final g = CareerController();
        addTearDown(g.dispose);
        g.startShift();

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
