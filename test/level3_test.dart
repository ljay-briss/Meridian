import 'dart:math';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meridian_private/controller.dart';
import 'package:meridian_private/data.dart';

/// Always returns [value] from nextDouble(), making the pay/resist and
/// threaten/refuse rolls in CareerController deterministic for tests.
class _FixedRandom implements Random {
  final double value;
  const _FixedRandom(this.value);
  @override
  double nextDouble() => value;
  @override
  int nextInt(int max) => 0;
  @override
  bool nextBool() => false;
}

const _gap = Duration(seconds: CareerController.collectorGapSeconds);

/// Lets the travel gap clear, and answers the night's curveball if one just
/// landed (the route is locked until it's answered) — picking the choice that
/// leaves the totals the tests care about alone.
void _settle(CareerController g, FakeAsync async) {
  async.elapse(_gap);
  final kind = g.pendingCurveball;
  if (kind != null) g.resolveCurveball(kind == 'police' ? 'keep_going' : 'let_go');
}

void main() {
  group('Level 3 — Collector', () {
    test('a fully paid week pays out and advances collectorWeeks', () {
      fakeAsync((async) {
        final g = CareerController(random: const _FixedRandom(0)); // always < 0.55 — every visit pays
        addTearDown(g.dispose);
        g.devJumpToLevel(3);

        for (final t in kCollectionRoute) {
          g.visit(t.id);
          _settle(g, async);
        }
        final cashBefore = g.cash;
        g.reportToBoss();

        expect(g.gameOver, isFalse);
        expect(g.shortfallNotice, isNull);
        expect(g.cash, cashBefore + 1500);
        expect(g.collectorWeeks, 1);
      });
    });

    test('coming up short costs the gap out of pocket instead of ending the career', () {
      fakeAsync((async) {
        final g = CareerController(random: const _FixedRandom(0.99)); // always >= 0.55/0.45 — every attempt fails
        addTearDown(g.dispose);
        g.devJumpToLevel(3);

        for (final t in kCollectionRoute) {
          g.visit(t.id); // -> resisting
          _settle(g, async);
          g.threaten(t.id); // -> refused
          _settle(g, async);
        }

        expect(g.targetState.values, everyElement('refused'));
        final cashBefore = g.cash;
        final expected = g.expectedTotal;
        g.reportToBoss();

        expect(g.gameOver, isFalse); // no more instant death on a short week
        expect(g.cash, cashBefore - expected); // nothing collected — the whole gap comes out of pocket
        expect(g.shortfallNotice, isNotNull);
        expect(g.collectorWeeks, 0); // a short week doesn't count as progress

        g.acknowledgeShortfall();
        expect(g.shortfallNotice, isNull);
      });
    });

    test('a target paid enough consecutive weeks draws permanent rival attention', () {
      fakeAsync((async) {
        final g = CareerController(random: const _FixedRandom(0)); // always pays; always <0.5 notice roll
        addTearDown(g.dispose);
        g.devJumpToLevel(3);

        void payFullWeek() {
          for (final t in kCollectionRoute) {
            g.visit(t.id);
            _settle(g, async);
          }
          g.reportToBoss();
        }

        payFullWeek(); // streak 1 for every target — too soon to be noticed
        expect(g.targetUnderRivalWatch, isEmpty);

        final rivalBefore = g.rivalPressure;
        payFullWeek(); // streak 2 — kFactionNoticeStreak reached

        expect(g.targetUnderRivalWatch, isNotEmpty);
        expect(g.rivalPressure, rivalBefore + 15);

        final noticed = kCollectionRoute.firstWhere((t) => g.targetUnderRivalWatch.contains(t.id));
        expect(g.effectiveOwed(noticed), (noticed.owed * 0.7).round());
        expect(g.effectiveOwed(noticed), lessThan(noticed.owed));
      });
    });

    group('time', () {
      test('each action spends its share of the night', () {
        fakeAsync((async) {
          final g = CareerController(random: const _FixedRandom(0.99)); // visit -> resisting, threaten -> refused
          addTearDown(g.dispose);
          g.devJumpToLevel(3);
          final t = kCollectionRoute.first.id;

          expect(g.routeSecondsLeft, CareerController.routeSeconds);
          g.visit(t);
          expect(g.routeSecondsLeft, CareerController.routeSeconds - CareerController.visitSeconds);
          _settle(g, async);
          g.threaten(t);
          expect(g.routeSecondsLeft, CareerController.routeSeconds - CareerController.visitSeconds - CareerController.threatenSeconds);
          _settle(g, async);
          g.vandalize(t, now: false);
          expect(
            g.routeSecondsLeft,
            CareerController.routeSeconds -
                CareerController.visitSeconds -
                CareerController.threatenSeconds -
                CareerController.vandalizeSeconds,
          );
        });
      });

      test('a side hustle costs time on the route and is blocked when time is short', () {
        final g = CareerController(random: const _FixedRandom(0));
        addTearDown(g.dispose);
        g.devJumpToLevel(3);

        g.startSideHustle();
        expect(g.routeSecondsLeft, CareerController.routeSeconds - CareerController.sideHustleSeconds);
        g.resolveSideHustle(true);

        g.routeSecondsLeft = CareerController.sideHustleSeconds - 1;
        expect(g.sideHustleAffordable, isFalse);
        g.startSideHustle();
        expect(g.pendingSideHustleGame, isNull);
        expect(g.routeSecondsLeft, CareerController.sideHustleSeconds - 1);
      });

      test('running out of night marks unreached targets missed and lets the player report short', () {
        fakeAsync((async) {
          final g = CareerController(random: const _FixedRandom(0.99));
          addTearDown(g.dispose);
          g.devJumpToLevel(3);

          g.routeSecondsLeft = CareerController.visitSeconds - 1; // can't afford even a visit
          expect(g.routeStalled, isTrue);
          g.visit(kCollectionRoute.first.id);
          expect(g.targetState[kCollectionRoute.first.id], 'pending'); // the action simply doesn't happen

          final cashBefore = g.cash;
          g.reportToBoss();
          expect(g.shortfallNotice, isNotNull);
          expect(g.cash, lessThan(cashBefore));
          expect(g.routeSecondsLeft, g.routeBudget); // fresh night (a shorter one — nothing was collected)
          expect(g.targetState.values, everyElement('pending'));
        });
      });
    });

    group('chain consequences', () {
      test('violence at one stop puts the unvisited ones on edge — harder to talk round, easier to scare', () {
        fakeAsync((async) {
          final g = CareerController(random: const _FixedRandom(0.99));
          addTearDown(g.dispose);
          g.devJumpToLevel(3);
          final first = kCollectionRoute[0].id;
          final second = kCollectionRoute[1].id;

          final visitBefore = g.visitOdds(second);
          final threatBefore = g.threatenOdds(second);
          g.visit(first); // -> resisting
          _settle(g, async);
          expect(g.targetOnEdge, isEmpty); // a plain visit doesn't spread word
          g.threaten(first);

          expect(g.targetOnEdge, containsAll([second, kCollectionRoute[2].id]));
          expect(g.targetOnEdge, isNot(contains(first)));
          expect(g.visitOdds(second), closeTo(visitBefore - CareerController.kOnEdgeVisitPenalty, 1e-9));
          expect(g.threatenOdds(second), closeTo(threatBefore + CareerController.kOnEdgeThreatenBonus, 1e-9));
        });
      });

      test('order matters: the same target pays more often when visited before the violence', () {
        final g = CareerController(random: const _FixedRandom(0.99));
        addTearDown(g.dispose);
        g.devJumpToLevel(3);
        final id = kCollectionRoute[1].id;
        final calm = g.visitOdds(id);
        g.targetOnEdge.add(id);
        expect(g.visitOdds(id), lessThan(calm));
      });
    });

    group('rival pressure', () {
      test('acting on a watched target costs rival pressure and lowers the odds', () {
        final g = CareerController(random: const _FixedRandom(0)); // visit pays
        addTearDown(g.dispose);
        g.devJumpToLevel(3);
        final id = kCollectionRoute[0].id;
        final calmOdds = g.visitOdds(id);
        g.targetUnderRivalWatch.add(id);
        expect(g.visitOdds(id), closeTo(calmOdds - CareerController.kWatchedVisitPenalty, 1e-9));

        final before = g.rivalPressure;
        g.visit(id);
        expect(g.targetState[id], 'paid'); // it still pays — at a price
        expect(g.rivalPressure, before + CareerController.kWatchedActionPressure);
      });

      test('high rival pressure makes every visit harder', () {
        final g = CareerController(random: const _FixedRandom(0));
        addTearDown(g.dispose);
        g.devJumpToLevel(3);
        final id = kCollectionRoute[0].id;
        final calm = g.visitOdds(id);
        g.rivalPressure = 45;
        final warm = g.visitOdds(id);
        g.rivalPressure = 65;
        final hot = g.visitOdds(id);
        expect(warm, lessThan(calm));
        expect(hot, lessThan(warm));
      });

      test('leaving a watched target alone eases the pressure — and can end the watch', () {
        final g = CareerController(random: const _FixedRandom(0));
        addTearDown(g.dispose);
        g.devJumpToLevel(3);
        final watched = kCollectionRoute[0].id;
        g.targetUnderRivalWatch.add(watched);
        g.rivalPressure = 20;

        g.reportToBoss(); // never touched the watched target

        expect(g.rivalPressure, 20 - CareerController.kIgnoredWatchRelief);
        expect(g.targetUnderRivalWatch, isNot(contains(watched))); // low enough that they lose interest
      });

      test('a watched target that stays hot keeps its watch when left alone', () {
        final g = CareerController(random: const _FixedRandom(0));
        addTearDown(g.dispose);
        g.devJumpToLevel(3);
        final watched = kCollectionRoute[0].id;
        g.targetUnderRivalWatch.add(watched);
        g.rivalPressure = 50;

        g.reportToBoss();

        expect(g.rivalPressure, 50 - CareerController.kIgnoredWatchRelief);
        expect(g.targetUnderRivalWatch, contains(watched));
      });
    });

    group('call in a favour', () {
      test('makes a target pay in full for a big suspicion hit — once', () {
        final g = CareerController(random: const _FixedRandom(0.99));
        addTearDown(g.dispose);
        g.devJumpToLevel(3);
        final club = kCollectionRoute.firstWhere((t) => t.id == 'club');

        final suspicionBefore = g.cartelSuspicion;
        expect(g.favourAvailable, isTrue);
        g.callInFavour(club.id);

        expect(g.targetState[club.id], 'paid');
        expect(g.collected[club.id], g.effectiveOwed(club));
        expect(g.cartelSuspicion, suspicionBefore + CareerController.kFavourSuspicion);
        expect(g.favourUsed, isTrue);
        expect(g.favourAvailable, isFalse);

        final other = kCollectionRoute.firstWhere((t) => t.id == 'taco');
        g.callInFavour(other.id);
        expect(g.targetState[other.id], 'pending'); // the second call goes nowhere
      });

      test('stays spent across weeks in the same level', () {
        fakeAsync((async) {
          final g = CareerController(random: const _FixedRandom(0));
          addTearDown(g.dispose);
          g.devJumpToLevel(3);
          g.callInFavour(kCollectionRoute[0].id);
          g.reportToBoss(); // a new night starts

          expect(g.favourUsed, isTrue);
          expect(g.favourAvailable, isFalse);
        });
      });
    });

    group('curveball', () {
      test('lands once per night after a couple of stops, and locks the route until answered', () {
        fakeAsync((async) {
          final g = CareerController(random: const _FixedRandom(0));
          addTearDown(g.dispose);
          g.devJumpToLevel(3);

          g.visit(kCollectionRoute[0].id);
          async.elapse(_gap);
          expect(g.pendingCurveball, isNull); // too early
          g.visit(kCollectionRoute[1].id);
          async.elapse(_gap);

          expect(g.pendingCurveball, isNotNull);
          expect(g.collectorLocked, isTrue);
          final leftBefore = g.routeSecondsLeft;
          g.visit(kCollectionRoute[2].id); // ignored while a decision is owed
          expect(g.targetState[kCollectionRoute[2].id], 'pending');
          expect(g.routeSecondsLeft, leftBefore);

          g.resolveCurveball('keep_going');
          expect(g.pendingCurveball, isNull);
          expect(g.curveballFired, isTrue);

          g.visit(kCollectionRoute[2].id);
          async.elapse(_gap);
          expect(g.pendingCurveball, isNull); // never a second one the same night
        });
      });

      test('police: lay low trades time for heat, keep collecting trades heat for time', () {
        fakeAsync((async) {
          final layLow = CareerController(random: const _FixedRandom(0));
          final keepGoing = CareerController(random: const _FixedRandom(0));
          addTearDown(layLow.dispose);
          addTearDown(keepGoing.dispose);
          for (final g in [layLow, keepGoing]) {
            g.devJumpToLevel(3);
            g.visit(kCollectionRoute[0].id);
            async.elapse(_gap);
            g.visit(kCollectionRoute[1].id);
            async.elapse(_gap);
            expect(g.pendingCurveball, 'police'); // heat outweighs the rival, who's been left alone
          }
          layLow.policeHeat = 40; // high enough that the relief isn't swallowed by the 0 floor
          final heatBefore = layLow.policeHeat;
          final timeBefore = layLow.routeSecondsLeft;
          layLow.resolveCurveball('lay_low');
          expect(layLow.policeHeat, heatBefore - CareerController.kLayLowHeatRelief);
          expect(layLow.routeSecondsLeft, timeBefore - CareerController.kLayLowSeconds);

          final keepHeat = keepGoing.policeHeat;
          final keepTime = keepGoing.routeSecondsLeft;
          keepGoing.resolveCurveball('keep_going');
          expect(keepGoing.policeHeat, keepHeat + CareerController.kKeepGoingHeat);
          expect(keepGoing.routeSecondsLeft, keepTime);
        });
      });

      test('rival: when they\'re the bigger threat they turn up at your most valuable open stop', () {
        fakeAsync((async) {
          final g = CareerController(random: const _FixedRandom(0.99)); // visits resist, threats fail
          addTearDown(g.dispose);
          g.devJumpToLevel(3);
          final first = kCollectionRoute[0].id;
          g.visit(first);
          async.elapse(_gap);
          g.threaten(first); // rival +3 outweighs the heat from one visit
          async.elapse(_gap);

          expect(g.pendingCurveball, 'rival');
          expect(g.curveballTargetId, 'club'); // the biggest stop still open

          g.rivalPressure = 30; // clear of the 0 floor
          final rivalBefore = g.rivalPressure;
          g.resolveCurveball('let_go');
          expect(g.targetUnderRivalWatch, contains('club'));
          expect(g.rivalPressure, rivalBefore - 6);
        });
      });

      test('rival: confronting them can back them off', () {
        fakeAsync((async) {
          final g = CareerController(random: const _FixedRandom(0));
          addTearDown(g.dispose);
          g.devJumpToLevel(3);
          g.rivalPressure = 30;
          g.visit(kCollectionRoute[0].id);
          async.elapse(_gap);
          g.visit(kCollectionRoute[1].id);
          async.elapse(_gap);
          expect(g.pendingCurveball, 'rival');

          final rivalBefore = g.rivalPressure;
          final timeBefore = g.routeSecondsLeft;
          g.resolveCurveball('confront'); // roll 0 < 0.5 — they back off
          expect(g.rivalPressure, rivalBefore - 10);
          expect(g.routeSecondsLeft, timeBefore - CareerController.kConfrontSeconds);
          expect(g.targetUnderRivalWatch, isEmpty);
        });
      });
    });

    group('partial results', () {
      test('close to expected: the boss splits the gap, but the week does not count', () {
        fakeAsync((async) {
          final g = CareerController(random: const _FixedRandom(0));
          addTearDown(g.dispose);
          g.devJumpToLevel(3);

          // Pay the two big stops, leave the taco stand — $12,000 of $12,500.
          g.visit('pharmacy');
          async.elapse(_gap);
          g.visit('club');
          _settle(g, async);

          final expected = g.expectedTotal;
          final cashBefore = g.cash;
          final suspicionBefore = g.cartelSuspicion;
          g.reportToBoss(); // call it a night with the taco stand unvisited

          final gap = expected - 12000;
          expect(g.cash, cashBefore - (gap / 2).ceil());
          expect(g.cartelSuspicion, greaterThan(suspicionBefore));
          expect(g.collectorWeeks, 0);
          expect(g.collectorShortWeeks, 1);
          expect(g.routePenaltySeconds, 0);
          expect(g.shortfallNotice, contains('Expected'));
          expect(g.shortfallNotice, contains('Collected'));
        });
      });

      test('far short: the whole gap is yours, and next week\'s night is shorter', () {
        fakeAsync((async) {
          final g = CareerController(random: const _FixedRandom(0));
          addTearDown(g.dispose);
          g.devJumpToLevel(3);

          g.visit('taco'); // $500 of $12,500
          _settle(g, async);
          final expected = g.expectedTotal;
          final cashBefore = g.cash;
          g.reportToBoss();

          expect(g.cash, cashBefore - (expected - 500));
          expect(g.routePenaltySeconds, CareerController.kPoorWeekTimePenalty);
          expect(g.routeBudget, CareerController.routeSeconds - CareerController.kPoorWeekTimePenalty);
          expect(g.routeSecondsLeft, g.routeBudget);
          expect(g.gameOver, isFalse);
        });
      });

      test('a clean week afterwards restores the full night', () {
        fakeAsync((async) {
          final g = CareerController(random: const _FixedRandom(0));
          addTearDown(g.dispose);
          g.devJumpToLevel(3);
          g.reportToBoss(); // nothing collected — a poor week
          expect(g.routePenaltySeconds, CareerController.kPoorWeekTimePenalty);

          for (final t in kCollectionRoute) {
            g.visit(t.id);
            _settle(g, async);
          }
          g.reportToBoss();

          expect(g.routePenaltySeconds, 0);
          expect(g.routeBudget, CareerController.routeSeconds);
        });
      });

      test('short weeks follow the player into the next level as suspicion', () {
        final g = CareerController(random: const _FixedRandom(0));
        addTearDown(g.dispose);
        g.devJumpToLevel(3);
        g.collectorShortWeeks = 2;
        g.cartelSuspicion = 10;
        g.promotionAvailable = true;

        g.acceptPromotion(path: kCareerPaths.first.id);

        expect(g.level, 4);
        expect(g.cartelSuspicion, 10 + 8);
      });
    });
  });
}
