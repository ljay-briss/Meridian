import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:meridian_private/controller.dart';
import 'package:meridian_private/data.dart';

/// Always returns [value] from nextDouble(), making the catch/no-catch roll
/// in CareerController._resolveRun deterministic for tests.
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

/// Drives one full run using the first (free) choice at every checkpoint.
void _driveRun(CareerController g) {
  g.beginRun();
  while (g.runStage != null) {
    g.chooseCheckpoint(kCheckpoints[g.runStage!].choices.first);
  }
}

void main() {
  group('Level 2 — Transporter', () {
    test('getting caught costs a cash fine instead of a strike', () {
      final g = CareerController(random: const _FixedRandom(0)); // 0.0 always "caught"
      addTearDown(g.dispose);
      g.devJumpToLevel(2);

      _driveRun(g);

      expect(g.cash, -650);
      expect(g.gameOver, isFalse);
      expect(g.lastWarning, isNotNull);
      expect(g.runStage, isNull); // free to begin another run
    });

    test('repeated catches keep costing money without ending the career', () {
      final g = CareerController(random: const _FixedRandom(0));
      addTearDown(g.dispose);
      g.devJumpToLevel(2);

      _driveRun(g);
      _driveRun(g);

      expect(g.gameOver, isFalse);
      expect(g.cash, -1300);
    });

    test('a clean run pays out and does not touch cash negatively', () {
      final g = CareerController(random: const _FixedRandom(0.99)); // above the 0.85 clamp — never caught
      addTearDown(g.dispose);
      g.devJumpToLevel(2);

      _driveRun(g);

      expect(g.gameOver, isFalse);
      expect(g.cash, 1000);
      expect(g.successfulRuns, 1);
    });

    test('starting a new run clears the previous warning', () {
      final g = CareerController(random: const _FixedRandom(0));
      addTearDown(g.dispose);
      g.devJumpToLevel(2);

      _driveRun(g); // caught, sets lastWarning
      expect(g.lastWarning, isNotNull);

      g.beginRun();
      expect(g.lastWarning, isNull);
    });

    test('a bribe choice with no tap result defaults to the fumbled penalty', () {
      final g = CareerController(random: const _FixedRandom(0.5));
      addTearDown(g.dispose);
      g.devJumpToLevel(2);
      g.beginRun();
      g.cash = 1000;

      final bribeChoice = kCheckpoints[0].choices[1]; // 'Slip the guard' — 0.04 risk, $300
      g.chooseCheckpoint(bribeChoice);

      expect(g.runRisk, closeTo(0.05 + 0.04 + 0.20, 1e-9));
      expect(g.cash, 700);
    });

    test('a successful bribe tap keeps the low risk; a failed one raises it', () {
      final won = CareerController(random: const _FixedRandom(0.5));
      addTearDown(won.dispose);
      won.devJumpToLevel(2);
      won.beginRun();
      won.cash = 1000;
      won.chooseCheckpoint(kCheckpoints[0].choices[1], tapSucceeded: true);
      expect(won.runRisk, closeTo(0.05 + 0.04 * 0.75, 1e-9));

      final lost = CareerController(random: const _FixedRandom(0.5));
      addTearDown(lost.dispose);
      lost.devJumpToLevel(2);
      lost.beginRun();
      lost.cash = 1000;
      lost.chooseCheckpoint(kCheckpoints[0].choices[1], tapSucceeded: false);
      expect(lost.runRisk, closeTo(0.05 + 0.04 + 0.20, 1e-9));
    });
  });
}
