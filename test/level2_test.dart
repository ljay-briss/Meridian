import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:meridian_private/controller.dart';
import 'package:meridian_private/data.dart';

/// Always returns [value] from nextDouble() and [intValue] from nextInt(),
/// making every roll in the Level 2 checkpoint flow deterministic for
/// tests: which scenario is picked, whether an inspection triggers, and the
/// final catch/no-catch roll in [CareerController._resolveRun].
class _FixedRandom implements Random {
  final double value;
  final int intValue;
  const _FixedRandom(this.value, {this.intValue = 0});
  @override
  double nextDouble() => value;
  @override
  int nextInt(int max) => intValue;
  @override
  bool nextBool() => false;
}

/// Drives one full run using the free, no-inspection-skipping approach
/// (index 0) at every checkpoint, taking whatever inspection response comes
/// up (index 0) whenever one triggers.
void _driveRun(CareerController g) {
  g.beginRun();
  while (g.runStage != null) {
    switch (g.checkpointPhase) {
      case CheckpointPhase.gather:
        g.proceedToApproach();
        break;
      case CheckpointPhase.approach:
        g.chooseApproach(kCheckpoints[g.runStage!].approaches.first);
        break;
      case CheckpointPhase.inspection:
        g.respondToInspection(kCheckpoints[g.runStage!].responses.first);
        break;
      case CheckpointPhase.result:
        g.advanceCheckpoint();
        break;
    }
  }
}

void main() {
  group('Level 2 — Transporter', () {
    test('getting caught costs a cash fine instead of a strike', () {
      final g = CareerController(random: const _FixedRandom(0)); // 0.0 always "caught"/"inspected"
      addTearDown(g.dispose);
      g.devJumpToLevel(2);

      _driveRun(g);

      expect(g.cash, lessThan(0));
      expect(g.gameOver, isFalse);
      expect(g.lastWarning, isNotNull);
      expect(g.runStage, isNull); // free to begin another run
    });

    test('repeated catches keep costing money without ending the career', () {
      final g = CareerController(random: const _FixedRandom(0));
      addTearDown(g.dispose);
      g.devJumpToLevel(2);

      _driveRun(g);
      final afterFirst = g.cash;
      _driveRun(g);

      expect(g.gameOver, isFalse);
      expect(g.cash, lessThan(afterFirst));
    });

    test('a clean run pays out and does not touch cash negatively', () {
      // Above every inspection-chance/suspicion/catch roll used in the flow —
      // no inspections trigger, and the final roll never catches.
      final g = CareerController(random: const _FixedRandom(0.99));
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

    test('choosing an approach that costs more than the player has does nothing', () {
      final g = CareerController(random: const _FixedRandom(0.99));
      addTearDown(g.dispose);
      g.devJumpToLevel(2);
      g.cash = 0;
      g.beginRun();
      g.proceedToApproach();

      final paidApproach = kCheckpoints[0].approaches[1]; // the paid option always costs > $0
      g.chooseApproach(paidApproach);

      expect(g.checkpointPhase, CheckpointPhase.approach); // never committed
      expect(g.cash, 0);
    });

    test('the route-change approach skips the inspection sub-scene entirely', () {
      final g = CareerController(random: const _FixedRandom(0)); // would always trigger an inspection otherwise
      addTearDown(g.dispose);
      g.devJumpToLevel(2);
      g.cash = 1000;
      g.beginRun();
      g.proceedToApproach();

      final routeChange = kCheckpoints[0].approaches[2];
      expect(routeChange.skipsInspection, isTrue);
      g.chooseApproach(routeChange);

      expect(g.checkpointPhase, CheckpointPhase.result);
      expect(g.checkpointHeadline, 'CLEAR');
    });

    test('observing and checking the vehicle each add a small risk nudge', () {
      final g = CareerController(random: const _FixedRandom(0.99));
      addTearDown(g.dispose);
      g.devJumpToLevel(2);
      g.beginRun();
      final before = g.runRisk;

      g.observeCheckpoint();
      g.checkVehicle();

      expect(g.runRisk, closeTo(before + 0.02, 1e-9));
      expect(g.observedThisStop, isTrue);
      expect(g.checkedVehicleThisStop, isTrue);

      // Using either action twice in the same stop is a no-op.
      g.observeCheckpoint();
      expect(g.runRisk, closeTo(before + 0.02, 1e-9));
    });

    test('a bad inspection response can escalate to a secondary inspection', () {
      // intValue: 1 rolls the heightened scenario at checkpoint 1, whose
      // favored approach/response are both index 1 — the free approach and
      // the "get defensive" response below deliberately miss both tells.
      final g = CareerController(random: const _FixedRandom(0, intValue: 1));
      addTearDown(g.dispose);
      g.devJumpToLevel(2);
      g.beginRun();
      g.proceedToApproach();
      g.chooseApproach(kCheckpoints[0].approaches.first); // triggers the inspection

      expect(g.checkpointPhase, CheckpointPhase.inspection);
      g.respondToInspection(kCheckpoints[0].responses.last); // "Get defensive" — worst baseline, and unmatched here

      expect(g.suspicion, 3);
      expect(g.checkpointPhase, CheckpointPhase.result);
      expect(g.checkpointHeadline, 'SECONDARY INSPECTION');
    });

    test('completing all 3 checkpoints resolves the run exactly once', () {
      final g = CareerController(random: const _FixedRandom(0.99));
      addTearDown(g.dispose);
      g.devJumpToLevel(2);

      _driveRun(g);

      expect(g.successfulRuns, 1);
      expect(g.lastRunOutcome, isNotNull);
      expect(g.lastRunOutcome!.caught, isFalse);
    });
  });
}
