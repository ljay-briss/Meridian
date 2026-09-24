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

void main() {
  group('Level 3 — Collector', () {
    test('a fully paid week pays out and advances collectorWeeks', () {
      fakeAsync((async) {
        final g = CareerController(random: const _FixedRandom(0)); // always < 0.55 — every visit pays
        addTearDown(g.dispose);
        g.devJumpToLevel(3);

        for (final t in kCollectionRoute) {
          g.visit(t.id);
          async.elapse(const Duration(seconds: CareerController.collectorGapSeconds));
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
          async.elapse(const Duration(seconds: CareerController.collectorGapSeconds));
          g.threaten(t.id); // -> refused
          async.elapse(const Duration(seconds: CareerController.collectorGapSeconds));
        }

        expect(g.targetState.values, everyElement('refused'));
        final cashBefore = g.cash;
        final expected = g.expectedTotal;
        g.reportToBoss();

        expect(g.gameOver, isFalse); // no more instant death on a short week
        expect(g.cash, cashBefore - expected); // the gap comes out of pocket
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
            async.elapse(const Duration(seconds: CareerController.collectorGapSeconds));
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
  });
}
