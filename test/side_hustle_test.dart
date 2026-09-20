import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meridian_private/controller.dart';
import 'package:meridian_private/data.dart';

void main() {
  group('Side hustle', () {
    test('starting one picks a minigame; resolving a win pays the level rate', () {
      final g = CareerController();
      addTearDown(g.dispose);

      g.startSideHustle();
      expect(g.pendingSideHustleGame, isNotNull);

      final cashBefore = g.cash;
      g.resolveSideHustle(true);

      expect(g.pendingSideHustleGame, isNull);
      expect(g.cash, cashBefore + (kSideHustlePayout[1] ?? 0));
    });

    test('it\'s always on offer — no cooldown, no need to wait for a gap', () {
      final g = CareerController();
      addTearDown(g.dispose);

      // Mid-shift, sighting live — still available; a loss followed
      // immediately by another attempt with no waiting in between.
      g.startShift();
      expect(g.sighting, isNotNull);
      expect(g.sideHustleAvailable, isTrue);

      g.startSideHustle();
      g.resolveSideHustle(false);
      expect(g.sideHustleAvailable, isTrue); // still on offer right away

      g.startSideHustle();
      g.resolveSideHustle(true);
      expect(g.sideHustleAvailable, isTrue); // and again, no cooldown after a win either
    });

    test('resolving a loss costs the scaled amount, can push cash negative, and bumps heat — unlike every other deduction', () {
      final g = CareerController();
      addTearDown(g.dispose);
      final heatBefore = g.policeHeat;

      g.startSideHustle();
      g.resolveSideHustle(false);

      expect(g.cash, -(kSideHustleLossPayout[1] ?? 0)); // started at 0, allowed to go negative
      expect(g.policeHeat, greaterThan(heatBefore));

      // A subsequent win, right away — no clamp regression on the recovery.
      g.startSideHustle();
      g.resolveSideHustle(true);
      expect(g.cash, -(kSideHustleLossPayout[1] ?? 0) + (kSideHustlePayout[1] ?? 0));
    });

    test('the same minigame never repeats twice in a row', () {
      final g = CareerController();
      addTearDown(g.dispose);

      g.startSideHustle();
      var previous = g.pendingSideHustleGame;
      g.resolveSideHustle(true);

      for (var i = 0; i < 20; i++) {
        expect(g.sideHustleAvailable, isTrue);
        g.startSideHustle();
        final kind = g.pendingSideHustleGame;
        expect(kind, isNotNull);
        expect(kind, isNot(previous));
        g.resolveSideHustle(true);
        previous = kind;
      }
    });

    test('resolveSideHustle is a no-op once nothing is pending', () {
      final g = CareerController();
      addTearDown(g.dispose);
      final cashBefore = g.cash;

      g.resolveSideHustle(true); // nothing started — should do nothing

      expect(g.cash, cashBefore);
    });

    test('unavailable once the game is over', () {
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
        expect(g.sideHustleAvailable, isFalse);
      });
    });
  });
}
