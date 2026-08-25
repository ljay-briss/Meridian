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
    test('getting caught the first time is a strike, not instant arrest', () {
      final g = CareerController(random: const _FixedRandom(0)); // 0.0 always "caught"
      addTearDown(g.dispose);
      g.devJumpToLevel(2);

      _driveRun(g);

      expect(g.transportStrikes, 1);
      expect(g.gameOver, isFalse);
      expect(g.lastWarning, isNotNull);
      expect(g.runStage, isNull); // free to begin another run
      expect(g.cash, 0); // no pay for a caught run
    });

    test('a second catch ends the run in arrest', () {
      final g = CareerController(random: const _FixedRandom(0));
      addTearDown(g.dispose);
      g.devJumpToLevel(2);

      _driveRun(g); // strike 1
      expect(g.gameOver, isFalse);
      _driveRun(g); // strike 2

      expect(g.gameOver, isTrue);
      expect(g.arrested, isTrue);
      expect(g.transportStrikes, 2);
    });

    test('a clean run does not touch the strike count', () {
      final g = CareerController(random: const _FixedRandom(0.99)); // above the 0.85 clamp — never caught
      addTearDown(g.dispose);
      g.devJumpToLevel(2);

      _driveRun(g);

      expect(g.transportStrikes, 0);
      expect(g.gameOver, isFalse);
      expect(g.cash, 3000);
      expect(g.successfulRuns, 1);
    });

    test('starting a new run clears the previous warning', () {
      final g = CareerController(random: const _FixedRandom(0));
      addTearDown(g.dispose);
      g.devJumpToLevel(2);

      _driveRun(g); // strike 1, sets lastWarning
      expect(g.lastWarning, isNotNull);

      g.beginRun();
      expect(g.lastWarning, isNull);
    });
  });
}
