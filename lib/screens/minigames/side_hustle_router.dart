import 'package:flutter/material.dart';
import '../../data.dart';
import 'blackjack_game_screen.dart';
import 'cups_game_screen.dart';
import 'higher_lower_game_screen.dart';
import 'numbers_racket_game_screen.dart';
import 'read_the_tell_game_screen.dart';
import 'sequence_game_screen.dart';
import 'spot_fake_game_screen.dart';
import 'timing_stop_game_screen.dart';

/// Maps a [SideHustleGameKind] to the screen that plays it — the single
/// place that knows about every minigame, so adding a new kind later only
/// touches this switch plus the enum in data.dart.
Widget sideHustleScreenFor(SideHustleGameKind kind) {
  switch (kind) {
    case SideHustleGameKind.cups:
      return const CupsGameScreen();
    case SideHustleGameKind.blackjack:
      return const BlackjackGameScreen();
    case SideHustleGameKind.readTheTell:
      return const ReadTheTellGameScreen();
    case SideHustleGameKind.timingStop:
      return const TimingStopGameScreen();
    case SideHustleGameKind.higherLower:
      return const HigherLowerGameScreen();
    case SideHustleGameKind.sequence:
      return const SequenceGameScreen();
    case SideHustleGameKind.spotFake:
      return const SpotFakeGameScreen();
    case SideHustleGameKind.numbersRacket:
      return const NumbersRacketGameScreen();
  }
}
