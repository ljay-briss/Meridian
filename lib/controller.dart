import 'dart:async';
import 'dart:math';
import 'package:flutter/widgets.dart' hide Intent;
import 'content/mama_reactions.dart';
import 'content/vale_reactions.dart';
import 'conversation/intents.dart';
import 'conversation/vale_intents.dart';
import 'data.dart';

double _clamp01to100(double v) => v.clamp(0, 100).toDouble();

/// Picks a random line from [pool], avoiding [avoid] when the pool has more
/// than one option — keeps a contact from sending the same line twice in a row.
String _pickVariant(Random rng, List<String> pool, String? avoid) {
  if (pool.length <= 1) return pool.first;
  String pick;
  do {
    pick = pool[rng.nextInt(pool.length)];
  } while (pick == avoid);
  return pick;
}

/// Holds all game state and logic across every career level.
class CareerController extends ChangeNotifier {
  final Random _rng;

  // ══════════════════════════════════════════════════════════════════════
  // PLAYTEST TUNING — how many weeks/runs/months/cycles each level needs
  // before promotion. Deliberately shortened right now so a full L1-L7 run
  // is quick to play-test. This is meant to be the real sim's pacing (weeks
  // and months of grind, not a handful of actions) — turn these back up once
  // that's built. Danger/lethality tuning (strikes, catch odds, etc.) is
  // untouched — this only controls how long each level takes to clear.
  // ══════════════════════════════════════════════════════════════════════
  static const int kCleanWeeksToPromote = 1; // real target: 2
  static const int kSuccessfulRunsToPromote = 2; // real target: 4
  static const int kCollectorWeeksToPromote = 1; // real target: 3
  static const int kMonthsAsLeaderToPromote = 2; // real target: 4
  static const int kStrategicGoodCyclesToPromote = 2; // real target: 4
  static const int kStrategicCyclesToPromote = 2; // real target: 4

  // ── shared state ──
  int day = 1;
  int level = 1;
  int cash = 0;
  int cleanBalance = 0;
  double policeHeat = 0;
  double cartelSuspicion = 0;
  bool gameOver = false;
  bool arrested = false;
  String gameOverReason = '';
  bool promotionAvailable = false;

  final Map<String, List<Message>> threads = {for (final c in kContacts) c.id: []};
  bool unread = false;
  String? _lastCrewLine; // avoids repeating the same crew outcome line twice in a row
  final ContactMood handlerMood = ContactMood(); // how El Primo's been feeling about your calls lately
  final Set<int> tutorialSeenLevels = {}; // per app session — survives restart(), not devJumpToLevel spam
  int? pendingTutorialBannerLevel; // set alongside the message; UI consumes it to pop a top banner once

  // Advances once per _tickPersonalRelationships() beat — this is a
  // turn-based game with no wall clock, so "time of day" is driven by
  // relationship-tick cadence rather than a real timer. See TimeOfDay in
  // dialogue_engine.dart.
  int _relationshipTickCount = 0;
  TimeOfDay get timeOfDay => timeOfDayForTick(_relationshipTickCount);
  bool get isWeekend => isWeekendForTick(_relationshipTickCount);

  String get dayLabel => kWeekdays[(day - 1) % 7];

  /// 0..1 progress toward this level's promotion, or null once there's
  /// nowhere left to be promoted to (level 7).
  double? get levelProgress {
    switch (level) {
      case 1:
        return (cleanWeeks / kCleanWeeksToPromote).clamp(0, 1);
      case 2:
        return (successfulRuns / kSuccessfulRunsToPromote).clamp(0, 1);
      case 3:
        return (collectorWeeks / kCollectorWeeksToPromote).clamp(0, 1);
      case 4:
        return (monthsAsLeader / kMonthsAsLeaderToPromote).clamp(0, 1);
      case 5:
        return (strategicGoodCycles / kStrategicGoodCyclesToPromote).clamp(0, 1);
      case 6:
        return (strategicCycles / kStrategicCyclesToPromote).clamp(0, 1);
      default:
        return null;
    }
  }

  /// How deep into the current level a personal-thread turn is happening —
  /// read by [DialogueLine.phases] via [DialogueContext.levelPhase] so a
  /// reaction can feel like it belongs to *now* rather than to the level in
  /// the abstract. Forced to [LevelPhase.cusp] right after a major story
  /// beat (while [recentStoryEvent] is still set) regardless of raw
  /// progress — that's the moment a reaction most wants to feel current.
  /// Level 7 has no [levelProgress] (nothing left to promote toward), so it
  /// reads as [LevelPhase.late] outright.
  LevelPhase get levelPhase {
    if (recentStoryEvent != null) return LevelPhase.cusp;
    final p = levelProgress;
    if (p == null) return LevelPhase.late;
    if (p < 0.15) return LevelPhase.opening;
    if (p < 0.4) return LevelPhase.early;
    if (p < 0.75) return LevelPhase.mid;
    return LevelPhase.late;
  }

  /// Short "N/target unit" caption to sit next to [levelProgress].
  String? get levelProgressLabel {
    switch (level) {
      case 1:
        return '$cleanWeeks/$kCleanWeeksToPromote clean weeks';
      case 2:
        return '$successfulRuns/$kSuccessfulRunsToPromote successful runs';
      case 3:
        return '$collectorWeeks/$kCollectorWeeksToPromote clean weeks';
      case 4:
        return '$monthsAsLeader/$kMonthsAsLeaderToPromote months as leader';
      case 5:
        return '$strategicGoodCycles/$kStrategicGoodCyclesToPromote strong cycles';
      case 6:
        return '$strategicCycles/$kStrategicCyclesToPromote cycles';
      default:
        return null;
    }
  }

  // ── Level 1: Plaza Lookout ──
  static const int sightingsPerDay = 3;
  static const int responseWindowSeconds = 15;
  int strikes = 0;
  Sighting? sighting;
  bool sightingHandled = false;
  bool weeklyStrikeOccurred = false;
  int cleanWeeks = 0;
  String? lastWarning;
  int sightingsToday = 0;
  int secondsRemaining = responseWindowSeconds;
  int sightingSeq = 0; // bumped on every roll, even if the pool repeats an entry
  Timer? _sightingTimer;

  // ── Level 2: Transporter ──
  int? runStage;
  double runRisk = 0;
  int successfulRuns = 0;
  int transportStrikes = 0;

  // ── Level 3: Collector ──
  final Map<String, int> collected = {};
  final Map<String, String> targetState = {}; // pending | resisting | refused | paid | lost
  final Map<String, String> targetExcuse = {};
  int collectorWeeks = 0;

  // ── Level 4: Cell Leader ──
  int stashKg = 100;
  final Map<String, int> allocated = {};
  List<String> crewNames = [];
  final Map<String, double> crewLoyalty = {};
  int monthsAsLeader = 0;
  int lastMonthTake = 0;
  int shortMonths = 0;
  String? pendingIncursion;
  String? pendingTrouble; // crew member name with trouble

  // ── Level 5: cell-leader management loop ──
  List<CellLeaderRecord> cellLeaders = [];
  static const int maxCheckInsPerCycle = 2;
  final Set<String> checkedInThisCycle = {};
  String? pendingCellSkim; // cell name skimming product/cash
  String? pendingCellPoach; // cell name a rival is trying to poach
  String? pendingCellShortage; // cell name running short on product
  int weakCycles = 0; // consecutive cycles average performance was in the danger zone
  int strategicGoodCycles = 0; // consecutive cycles average performance cleared the promotion bar

  // ── Level 5-7: strategic layer ──
  List<Territory> territories = [];
  int strategicCycles = 0;
  String? lastLaunderFront; // which front business last cleaned cash
  String? strategicEvent; // flavor text for the current pending decision
  String? strategicEventKind; // levels 6-7 only: 'investigation' | 'raid_territory' | 'paranoia' | 'diplomacy' | 'bribe'
  int investigationStage = 0; // 0 = none, 1 = surveillance, 2 = grand jury, 3 = raid imminent
  String? raidTargetName; // territory under active raid

  // ── Levels 6-7: inner circle ──
  List<String> innerCircleIds = [];
  final Map<String, bool> circleMole = {}; // hidden ground truth — never shown to the player
  String? paranoiaTargetId; // member currently flagged, awaiting a decision

  // ── Personal relationships ──
  final Map<String, RelationshipState> relationships = {for (final p in kPersonalContacts) p.id: RelationshipState()};
  final Map<String, List<Message>> personalThreads = {for (final p in kPersonalContacts) p.id: []};
  String? attachmentWarningContactId;

  // ── Story-contextual chip tracking ──
  // Set at key game moments so the personal chat tray can surface a chip that
  // references what just happened in the story. Cleared when the player sends
  // any personal reply (the event is "consumed" once they've talked about it).
  // Values: 'bribed' | 'close_call' | 'run_success' | 'crossed_line' |
  //         'crew_violence' | 'refused' | 'crew_trouble' | 'incursion'
  String? recentStoryEvent;

  /// [random] is injectable purely for deterministic tests; real gameplay
  /// always uses the default (unseeded) generator.
  CareerController({Random? random}) : _rng = random ?? Random() {
    _reinitLevel(1);
  }

  // ══════════════════════════════════════════════════════════════════════
  // Shared helpers
  // ══════════════════════════════════════════════════════════════════════

  /// Returns true (and ends the game) if maxed-out exposure triggers a raid or hit.
  bool _checkExposure() {
    // A $10M bounty and Special Forces attention make maxed-out heat far
    // less survivable at the very top than anywhere else in the org.
    final heatThreshold = level == 7 ? 90.0 : 95.0;
    final heatOdds = level == 7 ? 0.5 : 0.35;
    if (policeHeat >= heatThreshold && _rng.nextDouble() < heatOdds) {
      // At the top of the org, law enforcement takes you in rather than takes you out.
      _die('The raid came before dawn. No warning this time.', arrested: level >= 6);
      return true;
    }
    if (cartelSuspicion >= 95 && _rng.nextDouble() < 0.35) {
      _die('They found out. It wasn\'t quick.');
      return true;
    }
    return false;
  }

  void _die(String reason, {bool arrested = false}) {
    gameOver = true;
    this.arrested = arrested;
    gameOverReason = reason;
    notifyListeners();
  }

  /// Dispatches to the right level's init routine. Shared by [restart],
  /// [devJumpToLevel], and [acceptPromotion] so they can't drift apart.
  void _reinitLevel(int lvl) {
    switch (lvl) {
      case 1:
        _initLevel1();
        break;
      case 2:
        _initLevel2();
        break;
      case 3:
        _initLevel3();
        break;
      case 4:
        _initLevel4();
        break;
      case 5:
      case 6:
      case 7:
        _initStrategic(lvl);
        break;
    }
    _announceTutorial(lvl);
  }

  /// Sends the level's rundown into the handler thread as a real text —
  /// instead of an auto-popup — once per level per app session.
  void _announceTutorial(int lvl) {
    if (!tutorialSeenLevels.add(lvl)) return;
    threads['handler']!.add(Message('LEVEL $lvl — ${kLevelTitles[lvl]}\n\n${kTutorialBody[lvl]}', false));
    unread = true;
    pendingTutorialBannerLevel = lvl;
  }

  void consumeTutorialBanner() => pendingTutorialBannerLevel = null;

  /// A death restarts the player at the level they died on, not back at
  /// Level 1 — dying as a Plaza Boss shouldn't send you back to lookout duty.
  void restart() {
    gameOver = false;
    arrested = false;
    gameOverReason = '';
    day = 1;
    cash = 0;
    cleanBalance = 0;
    policeHeat = 0;
    cartelSuspicion = 0;
    _relationshipTickCount = 0;
    threads.updateAll((key, value) => []);
    relationships.updateAll((key, value) => RelationshipState());
    personalThreads.updateAll((key, value) => []);
    attachmentWarningContactId = null;
    _lastCrewLine = null;
    handlerMood.mood = 0;
    handlerMood.memories.clear();
    handlerMood.lineLastUsedDay.clear();
    handlerMood.recentLineHistory.clear();
    _reinitLevel(level);
    notifyListeners();
  }

  /// Dev/testing helper: jump straight to a level with fresh state for that level.
  void devJumpToLevel(int lvl) {
    gameOver = false;
    arrested = false;
    promotionAvailable = false;
    _reinitLevel(lvl);
    notifyListeners();
  }

  void acceptPromotion() {
    if (!promotionAvailable) return;
    promotionAvailable = false;
    _reinitLevel(level + 1);
    notifyListeners();
  }

  void markMessagesRead() {
    if (!unread) return;
    unread = false;
    notifyListeners();
  }

  void _announce(String contactId, String text) {
    threads[contactId]!.add(Message(text, false));
    unread = true;
  }

  // ══════════════════════════════════════════════════════════════════════
  // Level 1: Plaza Lookout
  // ══════════════════════════════════════════════════════════════════════

  void _initLevel1() {
    _sightingTimer?.cancel();
    level = 1;
    strikes = 0;
    cleanWeeks = 0;
    weeklyStrikeOccurred = false;
    lastWarning = null;
    sightingsToday = 0;
    sighting = _rollSighting();
    sightingSeq += 1;
    sightingHandled = false;
    _announce('handler', 'Eyes on the road. Military trucks: text "bird". Rival SUVs: text "snake". You have ${responseWindowSeconds}s to answer.');
    _startSightingTimer();
  }

  Sighting _rollSighting() => kSightingPool[_rng.nextInt(kSightingPool.length)];

  void _startSightingTimer() {
    _sightingTimer?.cancel();
    secondsRemaining = responseWindowSeconds;
    _sightingTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      secondsRemaining -= 1;
      if (secondsRemaining <= 0) {
        timer.cancel();
        _handleTimeout();
      } else {
        notifyListeners();
      }
    });
  }

  void respond(String word) {
    if (level != 1 || sighting == null || sightingHandled) return;
    _sightingTimer?.cancel();
    threads['handler']!.add(Message(word, true));
    _resolveSighting(
      correct: word == sighting!.correctWord,
      wrongReason: 'Sent the wrong word. That could get someone killed.',
    );
  }

  void _handleTimeout() {
    if (level != 1 || gameOver || sighting == null || sightingHandled) return;
    threads['handler']!.add(const Message("(never answered)", true));
    _resolveSighting(
      correct: false,
      wrongReason: 'Took too long to answer. Someone had to explain that.',
    );
  }

  void _resolveSighting({required bool correct, required String wrongReason}) {
    sightingHandled = true;
    lastWarning = null; // clear any previous warning now that the player has acted again

    // Mood reflects the streak going INTO this call, before this call's own
    // nudge — so "you've been sharp all week" means the prior calls, not
    // just this one.
    handlerMood.mood = decayMood(handlerMood.mood);
    final moodCtx = DialogueContext(
      mood: handlerMood.mood,
      closeness: 0,
      trust: 0,
      suspicion: 0,
      daysSinceReply: 0,
      recentTones: const [],
      memories: handlerMood.memories,
    );

    if (correct) {
      handlerMood.mood = (handlerMood.mood + 8).clamp(-100, 100);
      final line = pickLine(
        _rng,
        kHandlerApprovalLines,
        moodCtx,
        currentDay: day,
        lineLastUsedDay: handlerMood.lineLastUsedDay,
        recentLineHistory: handlerMood.recentLineHistory,
      );
      if (line != null) {
        threads['handler']!.add(Message(line.text, false));
        recordLineUse(handlerMood.lineLastUsedDay, handlerMood.recentLineHistory, line, day);
      }
      cartelSuspicion = _clamp01to100(cartelSuspicion - 2);
      policeHeat = _clamp01to100(policeHeat - 2);
    } else {
      // A wrong report — or no report at all — is a penalty on its own, independent
      // of the strike system: it's a real signal leaking to the wrong side.
      handlerMood.mood = (handlerMood.mood - 15).clamp(-100, 100);
      final line = pickLine(
        _rng,
        kHandlerWrongLines,
        moodCtx,
        currentDay: day,
        lineLastUsedDay: handlerMood.lineLastUsedDay,
        recentLineHistory: handlerMood.recentLineHistory,
      );
      if (line != null) {
        threads['handler']!.add(Message(line.text, false));
        recordLineUse(handlerMood.lineLastUsedDay, handlerMood.recentLineHistory, line, day);
      }
      policeHeat = _clamp01to100(policeHeat + 6);
      cartelSuspicion = _clamp01to100(cartelSuspicion + 6);
      _strike(wrongReason);
      if (gameOver) return;
    }
    unread = true;

    // A handful of sightings make up one day — a single answer no longer skips a whole day.
    sightingsToday += 1;
    if (sightingsToday >= sightingsPerDay) {
      sightingsToday = 0;
      if (!_advanceDay()) return;
    }
    sighting = _rollSighting();
    sightingSeq += 1;
    sightingHandled = false;
    _startSightingTimer();
    notifyListeners();
  }

  void _strike(String reason) {
    strikes += 1;
    weeklyStrikeOccurred = true;
    recentStoryEvent = 'close_call';
    if (strikes >= 2) {
      _die('$reason Two strikes. There is no third.');
      return;
    }
    lastWarning = reason;
  }

  /// Weekly pay, promotion check, exposure check, and relationship ticks —
  /// everything that happens once a day actually turns over. Returns false
  /// if the game ended as part of this day boundary.
  bool _advanceDay() {
    day += 1;
    if ((day - 1) % 7 == 0) {
      cash += 100;
      if (!weeklyStrikeOccurred) cleanWeeks += 1;
      weeklyStrikeOccurred = false;
      if (cleanWeeks >= kCleanWeeksToPromote) promotionAvailable = true;
      for (final rel in relationships.values) {
        rel.moneyAsksThisWeek = 0;
      }
    }
    if (_checkExposure()) return false;
    _tickPersonalRelationships();
    return true;
  }

  // ══════════════════════════════════════════════════════════════════════
  // Level 2: Transporter
  // ══════════════════════════════════════════════════════════════════════

  void _initLevel2() {
    _sightingTimer?.cancel();
    level = 2;
    runStage = null;
    runRisk = 0;
    successfulRuns = 0;
    transportStrikes = 0;
    lastWarning = null;
    _announce('handler', 'New job. Get the product across. Eight hours, don\'t stop for anyone.');
  }

  void beginRun() {
    if (level != 2 || runStage != null) return;
    runStage = 0;
    runRisk = 0.05;
    lastWarning = null;
    notifyListeners();
  }

  void chooseCheckpoint(CheckpointChoice choice) {
    if (level != 2 || runStage == null) return;
    if (choice.cost > 0) {
      if (cash < choice.cost) return;
      cash -= choice.cost;
      recentStoryEvent = 'bribed';
    }
    runRisk += choice.riskDelta;
    runStage = runStage! + 1;
    if (runStage! >= kCheckpoints.length) {
      _resolveRun();
    } else {
      notifyListeners();
    }
  }

  void _resolveRun() {
    final caught = _rng.nextDouble() < runRisk.clamp(0, 0.85);
    runStage = null;
    if (caught) {
      transportStrikes += 1;
      policeHeat = _clamp01to100(policeHeat + 15);
      recentStoryEvent = 'close_call';
      if (transportStrikes >= 2) {
        _die('Stopped at the crossing. Twenty years, no parole hearing for a while.', arrested: true);
        return;
      }
      // A first close call costs the load and the pay, but not the run — same
      // two-strike shape as the lookout job: one warning, then it's fatal.
      lastWarning = 'Almost got stopped at the crossing. No cargo, no pay this run. One strike — a second ends it.';
      if (_checkExposure()) return;
      _tickPersonalRelationships();
      notifyListeners();
      return;
    }
    lastWarning = null;
    recentStoryEvent = 'run_success';
    cash += 3000;
    successfulRuns += 1;
    policeHeat = _clamp01to100(policeHeat + 8);
    if (_checkExposure()) return;
    _tickPersonalRelationships();
    if (successfulRuns >= kSuccessfulRunsToPromote) promotionAvailable = true;
    notifyListeners();
  }

  // ══════════════════════════════════════════════════════════════════════
  // Level 3: Collector
  // ══════════════════════════════════════════════════════════════════════

  void _initLevel3() {
    _sightingTimer?.cancel();
    level = 3;
    collected.clear();
    targetState.clear();
    targetExcuse.clear();
    for (final t in kCollectionRoute) {
      targetState[t.id] = 'pending';
    }
    collectorWeeks = 0;
    _announce('handler', 'Route\'s the same every week. Come back short and it\'s on you.');
  }

  int get expectedTotal => kCollectionRoute.fold(0, (a, t) => a + t.owed);
  int get collectedTotal => collected.values.fold(0, (a, v) => a + v);

  void visit(String targetId) {
    if (level != 3) return;
    if (targetState[targetId] != 'pending') return;
    final target = kCollectionRoute.firstWhere((t) => t.id == targetId);
    if (_rng.nextDouble() < 0.55) {
      collected[targetId] = target.owed;
      targetState[targetId] = 'paid';
    } else {
      targetState[targetId] = 'resisting';
      targetExcuse[targetId] = kExcuses[_rng.nextInt(kExcuses.length)];
    }
    policeHeat = _clamp01to100(policeHeat + 1.5);
    cartelSuspicion = _clamp01to100(cartelSuspicion + 1);
    notifyListeners();
  }

  void threaten(String targetId) {
    if (level != 3) return;
    if (targetState[targetId] != 'resisting') return;
    final target = kCollectionRoute.firstWhere((t) => t.id == targetId);
    if (_rng.nextDouble() < 0.45) {
      collected[targetId] = target.owed;
      targetState[targetId] = 'paid';
    } else {
      targetState[targetId] = 'refused';
      recentStoryEvent = 'refused';
    }
    cartelSuspicion = _clamp01to100(cartelSuspicion + 2);
    notifyListeners();
  }

  void vandalize(String targetId, {required bool now}) {
    if (level != 3) return;
    final state = targetState[targetId];
    if (state != 'resisting' && state != 'refused') return;
    final target = kCollectionRoute.firstWhere((t) => t.id == targetId);
    recentStoryEvent = 'crew_violence';
    threads['crew']!.add(Message('${target.name}, ${now ? 'now' : 'tonight'}.', true));
    // Daylight is riskier than waiting for cover of night, but nothing at
    // the bottom is ever truly safe — someone can always tip the cops off.
    final failChance = now ? 0.5 : 0.2;
    if (_rng.nextDouble() < failChance) {
      targetState[targetId] = 'lost';
      policeHeat = _clamp01to100(policeHeat + (now ? 20 : 12));
      final line = _pickVariant(_rng, now ? kCrewFailNowLines : kCrewFailTonightLines, _lastCrewLine);
      threads['crew']!.add(Message(line, false));
      _lastCrewLine = line;
    } else {
      collected[targetId] = target.owed * 2;
      targetState[targetId] = 'paid';
      cartelSuspicion = _clamp01to100(cartelSuspicion + (now ? 3 : 2));
      policeHeat = _clamp01to100(policeHeat + (now ? 8 : 4));
      final line = _pickVariant(_rng, kCrewSuccessLines, _lastCrewLine);
      threads['crew']!.add(Message(line, false));
      _lastCrewLine = line;
    }
    unread = true;
    notifyListeners();
  }

  void reportToBoss() {
    if (level != 3) return;
    if (targetState.values.any((s) => s == 'pending' || s == 'resisting')) return;
    if (collectedTotal < expectedTotal) {
      _die('You came up \$${expectedTotal - collectedTotal} short. They don\'t forgive that.');
      return;
    }
    cash += 1500;
    collectorWeeks += 1;
    collected.clear();
    for (final t in kCollectionRoute) {
      targetState[t.id] = 'pending';
    }
    targetExcuse.clear();
    if (_checkExposure()) return;
    _tickPersonalRelationships();
    if (collectorWeeks >= kCollectorWeeksToPromote) promotionAvailable = true;
    notifyListeners();
  }

  // ══════════════════════════════════════════════════════════════════════
  // Level 4: Cell Leader
  // ══════════════════════════════════════════════════════════════════════

  void _initLevel4() {
    _sightingTimer?.cancel();
    level = 4;
    stashKg = 100;
    allocated.clear();
    crewNames = List.generate(10, (i) => '${kCrewNamesPool[i % kCrewNamesPool.length]}${i >= kCrewNamesPool.length ? ' ${i ~/ kCrewNamesPool.length + 1}' : ''}');
    crewLoyalty
      ..clear()
      ..addEntries(crewNames.map((n) => MapEntry(n, 0.8)));
    monthsAsLeader = 0;
    lastMonthTake = 0;
    shortMonths = 0;
    pendingIncursion = null;
    pendingTrouble = null;
  }

  int get allocatedKg => allocated.values.fold(0, (a, v) => a + v);

  void allocate(String distributorId, int kg) {
    if (level != 4) return;
    final current = allocated[distributorId] ?? 0;
    final delta = kg - current;
    if (delta > 0 && allocatedKg + delta > stashKg) return;
    if (kg <= 0) {
      allocated.remove(distributorId);
    } else {
      allocated[distributorId] = kg;
    }
    notifyListeners();
  }

  void closeMonth() {
    if (level != 4) return;
    if (pendingIncursion != null || pendingTrouble != null) return;
    double revenue = 0;
    for (final entry in allocated.entries) {
      final d = kDistributors.firstWhere((x) => x.id == entry.key);
      revenue += entry.value * d.pricePerKg;
    }
    final take = (revenue * 0.10).round();
    cash += take;
    lastMonthTake = take;
    monthsAsLeader += 1;
    stashKg = 100;
    allocated.clear();
    // Heat cools slower now — a violent month lingers instead of washing out
    // by the next one. Suspicion creeps up a little every month regardless
    // of how careful you are; moving product at this volume is never fully invisible.
    policeHeat = _clamp01to100(policeHeat - 3);
    cartelSuspicion = _clamp01to100(cartelSuspicion + 2);

    if (take < 65000) {
      shortMonths += 1;
      _announce('handler', kBossPressureLines[_rng.nextInt(kBossPressureLines.length)]);
      if (shortMonths >= 2) {
        _die('The regional boss doesn\'t tolerate coming up short twice running.');
        return;
      }
    } else {
      shortMonths = 0;
      if (_rng.nextDouble() < 0.25) {
        _announce('handler', kBossPressureLines[_rng.nextInt(kBossPressureLines.length)]);
      }
    }
    if (_checkExposure()) return;
    _tickPersonalRelationships();

    // Trouble and an incursion can both land the same month — reckless crew
    // and hungry rivals don't wait for a convenient week.
    if (_rng.nextDouble() < 0.45 && crewNames.isNotEmpty) {
      pendingTrouble = crewNames[_rng.nextInt(crewNames.length)];
      recentStoryEvent = 'crew_trouble';
    }
    if (_rng.nextDouble() < 0.45) {
      pendingIncursion = 'A rival crew is testing your corner on the east side.';
      recentStoryEvent ??= 'incursion'; // don't overwrite crew_trouble if both land
    }
    if (pendingTrouble == null && pendingIncursion == null && monthsAsLeader >= kMonthsAsLeaderToPromote) {
      promotionAvailable = true;
    }
    notifyListeners();
  }

  void respondIncursion(String choice) {
    if (pendingIncursion == null) return;
    if (choice == 'violence') {
      recentStoryEvent = 'crew_violence';
      policeHeat = _clamp01to100(policeHeat + 25);
      cartelSuspicion = _clamp01to100(cartelSuspicion - 10);
    } else {
      cash = (cash - 2000).clamp(0, 1 << 30);
      cartelSuspicion = _clamp01to100(cartelSuspicion + 5);
    }
    pendingIncursion = null;
    if (pendingTrouble == null && monthsAsLeader >= kMonthsAsLeaderToPromote) promotionAvailable = true;
    notifyListeners();
  }

  void discipline(String name, String action) {
    if (pendingTrouble != name) return;
    if (action == 'beating') {
      recentStoryEvent = 'crossed_line';
      crewLoyalty[name] = ((crewLoyalty[name] ?? 0.8) - 0.15).clamp(0, 1);
      policeHeat = _clamp01to100(policeHeat + 4);
    } else {
      crewNames.remove(name);
      crewLoyalty.remove(name);
      for (final n in crewNames) {
        crewLoyalty[n] = ((crewLoyalty[n] ?? 0.8) - 0.05).clamp(0, 1);
      }
      cartelSuspicion = _clamp01to100(cartelSuspicion + 2);
    }
    pendingTrouble = null;
    if (pendingIncursion == null && monthsAsLeader >= kMonthsAsLeaderToPromote) promotionAvailable = true;
    notifyListeners();
  }

  // ══════════════════════════════════════════════════════════════════════
  // Levels 5-7: strategic layer
  // ══════════════════════════════════════════════════════════════════════

  void _initStrategic(int lvl) {
    _sightingTimer?.cancel();
    level = lvl;
    strategicCycles = 0;
    strategicEvent = null;
    strategicEventKind = null;
    investigationStage = 0;
    raidTargetName = null;
    if (lvl == 5) {
      cellLeaders = List.generate(5, (i) => CellLeaderRecord('Cell ${i + 1}', 0.6 + _rng.nextDouble() * 0.3, 0.7));
      checkedInThisCycle.clear();
      pendingCellSkim = null;
      pendingCellPoach = null;
      pendingCellShortage = null;
      weakCycles = 0;
      strategicGoodCycles = 0;
    }
    if (lvl >= 6) {
      territories = kTerritoryNames.map((n) => Territory(n, n == kTerritoryNames.first)).toList();
      innerCircleIds = kInnerCircle.map((m) => m.id).toList();
      circleMole.clear();
      // Usually someone really is working against you — but not always.
      final moleId = _rng.nextDouble() < 0.7 ? innerCircleIds[_rng.nextInt(innerCircleIds.length)] : null;
      for (final id in innerCircleIds) {
        circleMole[id] = id == moleId;
      }
      paranoiaTargetId = null;
    }
  }

  int get strategicMonthlyRevenue {
    switch (level) {
      case 5:
        return 2500000 + cellLeaders.fold(0, (a, c) => a + (c.performance * 400000).round());
      case 6:
        return 20000000;
      case 7:
        return 100000000;
      default:
        return 0;
    }
  }

  void seizeTerritory(Territory t) {
    if (t.controlled || cash < 3000000) return;
    t.controlled = true;
    cash -= 3000000;
    cartelSuspicion = _clamp01to100(cartelSuspicion + 15);
    policeHeat = _clamp01to100(policeHeat + 10);
    notifyListeners();
  }

  void launderFunds(int amount) {
    final amt = min(amount, cash);
    if (amt <= 0) return;
    final fee = (amt * 0.12).round();
    cash -= amt;
    cleanBalance += amt - fee;
    policeHeat = _clamp01to100(policeHeat - 4);
    lastLaunderFront = kLaunderFronts[_rng.nextInt(kLaunderFronts.length)];
    notifyListeners();
  }

  void advanceStrategicCycle() {
    if (level < 5) return;
    if (level == 5 && (pendingCellSkim != null || pendingCellPoach != null || pendingCellShortage != null)) return;
    if (level >= 6 && strategicEvent != null) return;
    final revenue = strategicMonthlyRevenue;
    final take = (revenue * (level == 5 ? 0.08 : level == 6 ? 0.05 : 0.03)).round();
    cash += take;
    strategicCycles += 1;
    policeHeat = _clamp01to100(policeHeat + 6);
    if (_checkExposure()) return;
    _tickPersonalRelationships();

    if (level == 5) {
      _advanceCellLeaders();
      if (gameOver) return;
      notifyListeners();
      return;
    }

    // Ambient heat escalates a standing investigation — it only gets worse on its own.
    if (policeHeat >= 90 && investigationStage < 3) {
      investigationStage = 3;
    } else if (policeHeat >= 70 && investigationStage < 2) {
      investigationStage = 2;
    } else if (policeHeat >= 50 && investigationStage < 1) {
      investigationStage = 1;
    }

    if (investigationStage > 0) {
      strategicEvent = _investigationText(investigationStage);
      strategicEventKind = 'investigation';
      notifyListeners();
      return;
    }

    final roll = _rng.nextDouble();
    if (roll < 0.30) {
      _rollRaidEvent();
    } else if (roll < 0.45) {
      strategicEvent = level == 7
          ? 'A rival cartel leader proposes carving up a shared territory.'
          : 'A general wants a "consulting fee" to keep looking the other way.';
      strategicEventKind = level == 7 ? 'diplomacy' : 'bribe';
    } else if (roll < 0.55 && level >= 6 && innerCircleIds.isNotEmpty) {
      final id = innerCircleIds[_rng.nextInt(innerCircleIds.length)];
      final member = kInnerCircle.firstWhere((m) => m.id == id);
      paranoiaTargetId = id;
      strategicEvent = kParanoiaLines[_rng.nextInt(kParanoiaLines.length)].replaceAll('{name}', member.name);
      strategicEventKind = 'paranoia';
    } else if (strategicCycles >= kStrategicCyclesToPromote) {
      promotionAvailable = level < 7;
    }
    notifyListeners();
  }

  String _investigationText(int stage) {
    switch (stage) {
      case 1:
        return 'Under surveillance. Someone inside has been talking to the wrong people.';
      case 2:
        return "A grand jury has convened. This isn't rumor anymore.";
      default:
        return 'The raid is coming. Days, maybe hours.';
    }
  }

  void _rollRaidEvent() {
    final controlled = territories.where((t) => t.controlled).toList();
    if (controlled.isEmpty) return;
    final t = controlled[_rng.nextInt(controlled.length)];
    raidTargetName = t.name;
    strategicEvent = 'A rival cartel is moving on your hold in ${t.name}.';
    strategicEventKind = 'raid_territory';
  }

  void resolveStrategicEvent(String choice) {
    if (strategicEvent == null) return;
    switch (strategicEventKind) {
      case 'investigation':
        _resolveInvestigation(choice);
        break;
      case 'raid_territory':
        _resolveTerritoryRaid(choice);
        break;
      case 'bribe':
        if (choice == 'pay') {
          cash = (cash - 2000000).clamp(0, 1 << 30);
          policeHeat = _clamp01to100(policeHeat - 20);
        } else {
          policeHeat = _clamp01to100(policeHeat + 10);
        }
        break;
      case 'diplomacy':
        if (choice == 'accept') {
          cartelSuspicion = _clamp01to100(cartelSuspicion - 15);
        } else {
          cartelSuspicion = _clamp01to100(cartelSuspicion + 20);
        }
        break;
      case 'paranoia':
        _resolveParanoia(choice);
        break;
    }
    if (gameOver) return;
    strategicEvent = null;
    strategicEventKind = null;
    raidTargetName = null;
    paranoiaTargetId = null;
    if (strategicCycles >= kStrategicCyclesToPromote) promotionAvailable = level < 7;
    notifyListeners();
  }

  void _resolveParanoia(String choice) {
    final id = paranoiaTargetId;
    if (id == null) return;
    final wasMole = circleMole[id] ?? false;
    if (choice == 'execute') {
      innerCircleIds.remove(id);
      if (wasMole) {
        // The real threat is gone.
        cartelSuspicion = _clamp01to100(cartelSuspicion - 15);
        policeHeat = _clamp01to100(policeHeat - 10);
      } else {
        // Killed a loyal man on a hunch. That doesn't stay quiet.
        cartelSuspicion = _clamp01to100(cartelSuspicion + 10);
      }
    } else {
      if (wasMole) {
        // Whoever it was keeps working against you.
        policeHeat = _clamp01to100(policeHeat + 12);
        cartelSuspicion = _clamp01to100(cartelSuspicion + 8);
      } else {
        cartelSuspicion = _clamp01to100(cartelSuspicion - 3);
      }
    }
  }

  void _resolveInvestigation(String choice) {
    switch (investigationStage) {
      case 1:
        if (choice == 'bribe_judge' && cash >= 1500000) {
          cash -= 1500000;
          policeHeat = _clamp01to100(policeHeat - 25);
          investigationStage = 0;
        } else if (choice == 'go_dark') {
          policeHeat = _clamp01to100(policeHeat - 12);
          investigationStage = 0;
        }
        break;
      case 2:
        if (choice == 'flip_witness' && cash >= 3000000) {
          cash -= 3000000;
          cartelSuspicion = _clamp01to100(cartelSuspicion + 10);
          policeHeat = _clamp01to100(policeHeat - 30);
          investigationStage = 0;
        } else if (choice == 'bribe_judge' && cash >= 5000000) {
          cash -= 5000000;
          policeHeat = _clamp01to100(policeHeat - 15);
          investigationStage = 1;
        }
        break;
      default: // stage 3
        if (choice == 'go_to_ground') {
          cash = (cash * 0.75).round();
          policeHeat = _clamp01to100(policeHeat - 40);
          investigationStage = 1;
        } else if (choice == 'make_a_stand') {
          cartelSuspicion = _clamp01to100(cartelSuspicion + 5);
          if (_rng.nextDouble() < 0.5) {
            _die('The raid hit before you could disappear.', arrested: true);
            return;
          }
          policeHeat = _clamp01to100(policeHeat - 10);
        } else if (_rng.nextDouble() < 0.7) {
          _die('You waited too long to move.', arrested: true);
          return;
        }
    }
  }

  void _resolveTerritoryRaid(String choice) {
    final t = territories.firstWhere((x) => x.name == raidTargetName, orElse: () => territories.first);
    if (choice == 'defend') {
      cartelSuspicion = _clamp01to100(cartelSuspicion - 10);
      policeHeat = _clamp01to100(policeHeat + 15);
    } else if (choice == 'payoff' && cash >= 1000000) {
      cash -= 1000000;
      cartelSuspicion = _clamp01to100(cartelSuspicion + 5);
    } else {
      t.controlled = false;
      cartelSuspicion = _clamp01to100(cartelSuspicion - 5);
    }
  }

  // ══════════════════════════════════════════════════════════════════════
  // Level 5: cell-leader management loop
  // ══════════════════════════════════════════════════════════════════════

  /// Every cycle, every cell drifts a little without attention, at most two
  /// cells can be checked in on, and independent per-cell crises can stack —
  /// the difficulty here is triage, not any single mistake.
  void _advanceCellLeaders() {
    checkedInThisCycle.clear();
    for (final cell in cellLeaders) {
      cell.performance = (cell.performance - 0.05 - _rng.nextDouble() * 0.05).clamp(0, 1);
      cell.loyalty = (cell.loyalty - 0.03 - _rng.nextDouble() * 0.03).clamp(0, 1);
    }
    // Running five cells is never fully invisible either, check-ins or not.
    cartelSuspicion = _clamp01to100(cartelSuspicion + 1);

    final avg = cellLeaders.isEmpty ? 0.0 : cellLeaders.fold(0.0, (a, c) => a + c.performance) / cellLeaders.length;
    if (avg < 0.3) {
      weakCycles += 1;
      _announce('handler', kBossPressureLines[_rng.nextInt(kBossPressureLines.length)]);
      if (weakCycles >= 2) {
        _die('Your cells are bleeding money. The regional boss doesn\'t forgive that twice running.');
        return;
      }
    } else {
      weakCycles = 0;
    }
    strategicGoodCycles = avg >= 0.65 ? strategicGoodCycles + 1 : 0;

    if (_rng.nextDouble() < 0.35 && cellLeaders.isNotEmpty) {
      pendingCellSkim = cellLeaders[_rng.nextInt(cellLeaders.length)].name;
    }
    if (_rng.nextDouble() < 0.3 && cellLeaders.isNotEmpty) {
      pendingCellPoach = cellLeaders[_rng.nextInt(cellLeaders.length)].name;
    }
    if (_rng.nextDouble() < 0.3 && cellLeaders.isNotEmpty) {
      pendingCellShortage = cellLeaders[_rng.nextInt(cellLeaders.length)].name;
    }
    _afterCellEventResolved();
  }

  void checkInOnCell(String cellName) {
    if (level != 5) return;
    if (checkedInThisCycle.length >= maxCheckInsPerCycle || checkedInThisCycle.contains(cellName)) return;
    final cell = cellLeaders.firstWhere((c) => c.name == cellName, orElse: () => cellLeaders.first);
    cell.performance = (cell.performance + 0.1).clamp(0, 1);
    cell.loyalty = (cell.loyalty + 0.08).clamp(0, 1);
    checkedInThisCycle.add(cellName);
    notifyListeners();
  }

  void resolveCellSkim(String choice) {
    if (pendingCellSkim == null) return;
    final cell = cellLeaders.firstWhere((c) => c.name == pendingCellSkim, orElse: () => cellLeaders.first);
    if (choice == 'discipline') {
      cell.loyalty = (cell.loyalty - 0.15).clamp(0, 1);
      cell.performance = (cell.performance + 0.05).clamp(0, 1);
      policeHeat = _clamp01to100(policeHeat + 3);
    } else {
      cash = (cash - 15000).clamp(0, 1 << 30);
      cartelSuspicion = _clamp01to100(cartelSuspicion + 4);
    }
    pendingCellSkim = null;
    _afterCellEventResolved();
    notifyListeners();
  }

  void resolveCellPoach(String choice) {
    if (pendingCellPoach == null) return;
    final cell = cellLeaders.firstWhere((c) => c.name == pendingCellPoach, orElse: () => cellLeaders.first);
    if (choice == 'reassure' && cash >= 100000) {
      cash -= 100000;
      cell.loyalty = (cell.loyalty + 0.2).clamp(0, 1);
    } else {
      // They walk — the cell falls apart without them for a while.
      cell.loyalty = (cell.loyalty - 0.3).clamp(0, 1);
      cell.performance = (cell.performance - 0.25).clamp(0, 1);
      cartelSuspicion = _clamp01to100(cartelSuspicion + 6);
    }
    pendingCellPoach = null;
    _afterCellEventResolved();
    notifyListeners();
  }

  void resolveCellShortage(String choice) {
    if (pendingCellShortage == null) return;
    final cell = cellLeaders.firstWhere((c) => c.name == pendingCellShortage, orElse: () => cellLeaders.first);
    if (choice == 'reallocate' && cash >= 50000) {
      cash -= 50000;
      cell.performance = (cell.performance + 0.15).clamp(0, 1);
    } else {
      cell.performance = (cell.performance - 0.1).clamp(0, 1);
    }
    pendingCellShortage = null;
    _afterCellEventResolved();
    notifyListeners();
  }

  void _afterCellEventResolved() {
    if (pendingCellSkim == null &&
        pendingCellPoach == null &&
        pendingCellShortage == null &&
        strategicGoodCycles >= kStrategicGoodCyclesToPromote) {
      promotionAvailable = true;
    }
  }

  // ══════════════════════════════════════════════════════════════════════
  // Personal relationships
  // ══════════════════════════════════════════════════════════════════════

  void openPersonalThread(String contactId) {
    final rel = relationships[contactId]!;
    if (!rel.unread) return;
    rel.unread = false;
    notifyListeners();
  }

  /// Generates story-contextual chips for the personal chat tray based on
  /// current game state. These are injected at the front of the tray so they
  /// always surface, regardless of the static catalog's scoring. Each chip is
  /// a fully valid [PersonalReplyAction] — it routes through the same dialogue
  /// engine as any static chip when the player taps it.
  ///
  /// Ordering: most urgent / specific events first (a bribe that just happened
  /// beats a generic "bored" chip), falling back to time-of-day and mood chips,
  /// with deflection chips ("just missed you") always at the end as a way out.
  List<PersonalReplyAction> _storyContextChips(String contactId) {
    final chips = <PersonalReplyAction>[];
    final rel = relationships[contactId]!;
    final thread = personalThreads[contactId]!;

    // ── 1. Event-reactive (most specific/urgent) ───────────────────────────
    switch (recentStoryEvent) {
      case 'bribed':
        chips.add(const PersonalReplyAction('Paid someone off', "I had to pay someone off today. Felt weird about it.", tone: ReplyTone.honest, topics: {Topic.money}, intent: Intent.confession, intensity: 0.6));
        chips.add(const PersonalReplyAction('Had to grease someone', "Slipped someone some cash today to make a problem go away.", tone: ReplyTone.vague, topics: {Topic.money}, intent: Intent.statement, intensity: 0.5));
        break;
      case 'close_call':
        chips.add(const PersonalReplyAction('Close call', "Had a close call today. I'm okay though.", tone: ReplyTone.honest, topics: {Topic.wellbeing}, intent: Intent.statement, intensity: 0.6));
        chips.add(const PersonalReplyAction('Shook up', "Something happened today that had me scared for a second. I'm fine.", tone: ReplyTone.honest, topics: {Topic.wellbeing}, intent: Intent.statement, intensity: 0.6));
        chips.add(const PersonalReplyAction('Too close', "Almost messed up bad today. Keeping it together though.", tone: ReplyTone.vague, topics: {Topic.wellbeing}, intent: Intent.statement, intensity: 0.5));
        break;
      case 'run_success':
        chips.add(const PersonalReplyAction('Something went right', "Something I had to do today actually worked out.", tone: ReplyTone.warm, topics: {Topic.goodNews}, intent: Intent.statement, intensity: 0.4));
        chips.add(const PersonalReplyAction('Getting it done', "Pulled off something today I wasn't sure I could.", tone: ReplyTone.warm, topics: {Topic.goodNews}, intent: Intent.statement, intensity: 0.4));
        chips.add(const PersonalReplyAction('Getting the hang of it', "Starting to get the hang of things. Feels good.", tone: ReplyTone.warm, topics: {Topic.goodNews}, intent: Intent.statement, intensity: 0.3));
        break;
      case 'crossed_line':
        chips.add(const PersonalReplyAction('Crossed a line', "I did something today I can't really undo.", tone: ReplyTone.honest, topics: {Topic.wellbeing}, intent: Intent.confession, intensity: 0.7));
        chips.add(const PersonalReplyAction('Not proud of it', "Had to handle something the hard way. Not proud of it.", tone: ReplyTone.honest, topics: {Topic.wellbeing}, intent: Intent.confession, intensity: 0.6));
        chips.add(const PersonalReplyAction('Had to do it', "I told myself I'd never do something like that. Then I did.", tone: ReplyTone.honest, topics: {Topic.wellbeing}, intent: Intent.confession, intensity: 0.7));
        break;
      case 'crew_violence':
        chips.add(const PersonalReplyAction('Had to get rough', "Had to handle something the hard way today.", tone: ReplyTone.vague, topics: {Topic.suspicion}, intent: Intent.statement, intensity: 0.6));
        chips.add(const PersonalReplyAction('Ugly situation', "Things got ugly today. I handled it. But still.", tone: ReplyTone.honest, topics: {Topic.wellbeing}, intent: Intent.statement, intensity: 0.6));
        chips.add(const PersonalReplyAction('People push you', "Some people push you until you have no choice.", tone: ReplyTone.vague, topics: {Topic.suspicion}, intent: Intent.statement, intensity: 0.5));
        break;
      case 'refused':
        chips.add(const PersonalReplyAction('Someone pushed back', "Someone gave me a hard time today. Had to deal with it.", tone: ReplyTone.honest, topics: {Topic.suspicion}, intent: Intent.statement, intensity: 0.5));
        chips.add(const PersonalReplyAction('People are difficult', "Not everyone plays ball. Learning that the hard way.", tone: ReplyTone.vague, topics: {Topic.suspicion}, intent: Intent.statement, intensity: 0.4));
        break;
      case 'crew_trouble':
        chips.add(const PersonalReplyAction('Team drama', "Someone on my team is causing problems. Dealing with it.", tone: ReplyTone.vague, topics: {Topic.plans}, intent: Intent.statement, intensity: 0.5));
        chips.add(const PersonalReplyAction('Managing people', "Managing people is harder than I thought.", tone: ReplyTone.honest, topics: {Topic.plans}, intent: Intent.statement, intensity: 0.4));
        chips.add(const PersonalReplyAction('Trust issues', "One person can mess up the whole thing. Hate that.", tone: ReplyTone.vague, topics: {Topic.suspicion}, intent: Intent.statement, intensity: 0.5));
        break;
      case 'incursion':
        chips.add(const PersonalReplyAction('Things are tense', "Things have been tense in my area lately.", tone: ReplyTone.vague, topics: {Topic.suspicion}, intent: Intent.statement, intensity: 0.5));
        chips.add(const PersonalReplyAction('People testing me', "Someone's testing me right now. Seeing how I respond.", tone: ReplyTone.vague, topics: {Topic.suspicion}, intent: Intent.statement, intensity: 0.5));
        break;
    }

    // ── 2. Time-of-day aware ───────────────────────────────────────────────
    switch (timeOfDay) {
      case TimeOfDay.night:
        chips.add(const PersonalReplyAction("Can't sleep", "Can't really sleep. Brain won't shut off.", tone: ReplyTone.honest, topics: {Topic.wellbeing}, intent: Intent.statement, intensity: 0.3));
        chips.add(const PersonalReplyAction('Night thoughts', "Everything feels heavier at night for some reason.", tone: ReplyTone.honest, topics: {Topic.wellbeing}, intent: Intent.statement, intensity: 0.3));
        chips.add(const PersonalReplyAction('Wide awake', "It's late and I should be asleep but my head won't slow down.", tone: ReplyTone.honest, topics: {Topic.wellbeing}, intent: Intent.statement, intensity: 0.3));
        break;
      case TimeOfDay.morning:
        if (level >= 2) {
          chips.add(const PersonalReplyAction('Big day ahead', "Got a lot going on today. Wish me luck.", tone: ReplyTone.warm, topics: {Topic.plans}, intent: Intent.statement, intensity: 0.4));
          chips.add(const PersonalReplyAction('Up early', "Up early. Can't stop thinking about what's ahead.", tone: ReplyTone.honest, topics: {Topic.plans}, intent: Intent.statement, intensity: 0.3));
        }
        break;
      case TimeOfDay.evening:
        chips.add(const PersonalReplyAction('Long day', "Today was a lot. Don't even know where to start.", tone: ReplyTone.honest, topics: {Topic.wellbeing}, intent: Intent.statement, intensity: 0.4));
        chips.add(const PersonalReplyAction('Finally breathing', "Finally getting to breathe a little. It's been a day.", tone: ReplyTone.warm, topics: {Topic.wellbeing}, intent: Intent.statement, intensity: 0.3));
        chips.add(const PersonalReplyAction('Day done', "Glad today is almost over honestly.", tone: ReplyTone.honest, topics: {Topic.wellbeing}, intent: Intent.statement, intensity: 0.3));
        break;
      case TimeOfDay.afternoon:
        break;
    }

    // ── 3. Cash state ─────────────────────────────────────────────────────
    if (cash < 300 && level >= 2) {
      chips.add(const PersonalReplyAction('Broke', "Money's been really tight lately.", tone: ReplyTone.honest, topics: {Topic.money}, intent: Intent.statement, intensity: 0.5, subject: 'being broke'));
      chips.add(const PersonalReplyAction('Struggling financially', "Things have been rough financially. Not gonna lie.", tone: ReplyTone.honest, topics: {Topic.money}, intent: Intent.statement, intensity: 0.5));
      chips.add(const PersonalReplyAction('Debt stress', "I owe people. It's sitting heavy on me.", tone: ReplyTone.honest, topics: {Topic.money}, intent: Intent.statement, intensity: 0.5, subject: 'debt'));
    } else if (cash > 50000) {
      chips.add(const PersonalReplyAction('Doing well', "Things have been going well for me lately. Money-wise.", tone: ReplyTone.warm, topics: {Topic.money}, intent: Intent.statement, intensity: 0.4, resolvesThread: true));
      chips.add(const PersonalReplyAction('Good stretch', "Had a good stretch recently. Can't complain.", tone: ReplyTone.warm, topics: {Topic.goodNews}, intent: Intent.statement, intensity: 0.3));
    } else if (cash > 8000 && level <= 3) {
      chips.add(const PersonalReplyAction('Good week', "Actually had a decent week financially.", tone: ReplyTone.warm, topics: {Topic.goodNews}, intent: Intent.statement, intensity: 0.4));
    }

    // ── 4. Heat / being watched ────────────────────────────────────────────
    if (policeHeat > 75) {
      chips.add(const PersonalReplyAction('Need to be careful', "I need to be more careful. Things are getting risky.", tone: ReplyTone.honest, topics: {Topic.suspicion}, intent: Intent.statement, intensity: 0.7));
      chips.add(const PersonalReplyAction('Heat is on', "There's a lot of attention on me right now. Gotta stay low.", tone: ReplyTone.vague, topics: {Topic.suspicion}, intent: Intent.statement, intensity: 0.6));
    } else if (policeHeat > 50) {
      chips.add(const PersonalReplyAction('Watched', "I feel like people have been watching me lately.", tone: ReplyTone.vague, topics: {Topic.suspicion}, intent: Intent.statement, intensity: 0.5));
      chips.add(const PersonalReplyAction('Something feels off', "Something feels off. Like someone's paying attention.", tone: ReplyTone.vague, topics: {Topic.suspicion}, intent: Intent.statement, intensity: 0.5));
      chips.add(const PersonalReplyAction('Eyes on me', "I've just been feeling... observed. Can't explain it.", tone: ReplyTone.vague, topics: {Topic.suspicion}, intent: Intent.statement, intensity: 0.4));
    }

    // ── 5. Relationship-reactive ───────────────────────────────────────────
    if (rel.suspicion > 50) {
      chips.add(const PersonalReplyAction("You don't have to worry", "I feel like you've been worried about me. You don't have to be.", tone: ReplyTone.warm, topics: {Topic.wellbeing}, intent: Intent.statement, intensity: 0.4));
      chips.add(const PersonalReplyAction('I know you worry', "I know you worry. I'm being careful. I promise.", tone: ReplyTone.warm, topics: {Topic.wellbeing}, intent: Intent.promise, intensity: 0.4));
    }
    if (rel.mood < -20) {
      chips.add(const PersonalReplyAction('Know I messed up', "I know I've been letting you down lately.", tone: ReplyTone.honest, topics: {Topic.affection}, intent: Intent.confession, intensity: 0.5));
      chips.add(const PersonalReplyAction('Been distant', "I've been distant. I know. I'm sorry.", tone: ReplyTone.warm, topics: {Topic.affection}, intent: Intent.confession, intensity: 0.4));
      chips.add(const PersonalReplyAction('Trying to do better', "I want to do better by you. I mean that.", tone: ReplyTone.warm, topics: {Topic.affection}, intent: Intent.promise, intensity: 0.4));
    }
    if (rel.daysSinceReply > 2 && thread.isNotEmpty) {
      chips.add(const PersonalReplyAction('Been MIA', "I know I've been MIA. Things have been a lot.", tone: ReplyTone.warm, topics: {Topic.wellbeing}, intent: Intent.statement, intensity: 0.4));
      chips.add(const PersonalReplyAction('Sorry been quiet', "Sorry I've been quiet. It's been one of those stretches.", tone: ReplyTone.warm, topics: {Topic.affection}, intent: Intent.statement, intensity: 0.4));
      chips.add(const PersonalReplyAction('Checked out for a bit', "I kind of checked out for a while. I'm back though.", tone: ReplyTone.warm, topics: {Topic.affection}, intent: Intent.statement, intensity: 0.3));
    }

    // ── 6. Level-specific story context ───────────────────────────────────
    switch (level) {
      case 1:
        if (strikes > 0) {
          chips.add(const PersonalReplyAction('Messed up at work', "I messed up at work today. Wasn't fatal but it was close.", tone: ReplyTone.honest, topics: {Topic.wellbeing}, intent: Intent.confession, intensity: 0.5));
          chips.add(const PersonalReplyAction('Slipped up', "Made a mistake at work. Won't happen again.", tone: ReplyTone.honest, topics: {Topic.wellbeing}, intent: Intent.statement, intensity: 0.4));
        }
        if (cleanWeeks >= 1) {
          chips.add(const PersonalReplyAction('Work going okay', "Things at work have been going okay lately.", tone: ReplyTone.warm, topics: {Topic.wellbeing}, intent: Intent.statement, intensity: 0.3));
        }
        chips.add(const PersonalReplyAction('New job', "Started something new. Still figuring it out.", tone: ReplyTone.honest, topics: {Topic.plans}, intent: Intent.statement, intensity: 0.3));
        break;
      case 2:
        if (runStage != null) {
          chips.add(const PersonalReplyAction('In the middle of something', "Can't really talk right now. In the middle of something.", tone: ReplyTone.vague, topics: {Topic.plans}, intent: Intent.statement, intensity: 0.5));
          chips.add(const PersonalReplyAction('Kind of tense right now', "Things are a little tense right now. I'll explain later.", tone: ReplyTone.vague, topics: {Topic.suspicion}, intent: Intent.statement, intensity: 0.5));
        }
        chips.add(const PersonalReplyAction('Long drives', "Been doing a lot of driving lately. Long ones.", tone: ReplyTone.vague, topics: {Topic.plans}, intent: Intent.statement, intensity: 0.3));
        chips.add(const PersonalReplyAction('Checkpoints', "Lot of people asking me questions lately. At work.", tone: ReplyTone.vague, topics: {Topic.suspicion}, intent: Intent.statement, intensity: 0.4));
        break;
      case 3:
        if (targetState.values.any((s) => s == 'refused' || s == 'lost')) {
          chips.add(const PersonalReplyAction('Difficult people', "Some people just make things harder than they need to be.", tone: ReplyTone.honest, topics: {Topic.suspicion}, intent: Intent.statement, intensity: 0.5));
          chips.add(const PersonalReplyAction('Not everyone cooperates', "Not everyone's cooperative. Having to push sometimes.", tone: ReplyTone.vague, topics: {Topic.suspicion}, intent: Intent.statement, intensity: 0.4));
        }
        chips.add(const PersonalReplyAction('Different stress', "Work's been... a different kind of stress lately.", tone: ReplyTone.vague, topics: {Topic.wellbeing}, intent: Intent.statement, intensity: 0.4));
        chips.add(const PersonalReplyAction('Going door to door', "Been doing a lot of face-to-face stuff for work. Tiring.", tone: ReplyTone.vague, topics: {Topic.plans}, intent: Intent.statement, intensity: 0.3));
        break;
      case 4:
        if (pendingTrouble != null) {
          chips.add(const PersonalReplyAction('Someone causing problems', "Someone I work with is giving me problems. Have to deal with it.", tone: ReplyTone.vague, topics: {Topic.plans}, intent: Intent.statement, intensity: 0.5));
        }
        if (pendingIncursion != null) {
          chips.add(const PersonalReplyAction('Competition', "Someone's trying to move into my space at work. Handling it.", tone: ReplyTone.vague, topics: {Topic.suspicion}, intent: Intent.statement, intensity: 0.5));
        }
        if (lastMonthTake > 80000) {
          chips.add(const PersonalReplyAction('Best month yet', "Had my best month financially. By a lot.", tone: ReplyTone.warm, topics: {Topic.money}, intent: Intent.statement, intensity: 0.4));
        }
        chips.add(const PersonalReplyAction('Managing people', "Managing people is harder than I thought it'd be.", tone: ReplyTone.honest, topics: {Topic.plans}, intent: Intent.statement, intensity: 0.4));
        chips.add(const PersonalReplyAction('In charge now', "A lot of people are depending on me right now. It's a lot.", tone: ReplyTone.honest, topics: {Topic.plans}, intent: Intent.statement, intensity: 0.4));
        break;
      case 5:
      case 6:
      case 7:
        if (investigationStage > 0) {
          chips.add(const PersonalReplyAction('Under a microscope', "I feel like I'm under a microscope lately.", tone: ReplyTone.vague, topics: {Topic.suspicion}, intent: Intent.statement, intensity: 0.7));
          chips.add(const PersonalReplyAction('Heat is serious', "There are serious people paying close attention to me right now.", tone: ReplyTone.vague, topics: {Topic.suspicion}, intent: Intent.statement, intensity: 0.7));
          chips.add(const PersonalReplyAction('Got to lay low', "Can't be as visible as I was. Got to pull back for a bit.", tone: ReplyTone.vague, topics: {Topic.plans}, intent: Intent.statement, intensity: 0.6));
        }
        chips.add(const PersonalReplyAction('In deep', "Sometimes I feel like I'm in over my head.", tone: ReplyTone.honest, topics: {Topic.wellbeing}, intent: Intent.confession, intensity: 0.6));
        chips.add(const PersonalReplyAction('Hard to separate', "It's getting harder to keep different parts of my life separate.", tone: ReplyTone.honest, topics: {Topic.wellbeing}, intent: Intent.confession, intensity: 0.6));
        chips.add(const PersonalReplyAction('People around me', "The people around me lately... it's a different world.", tone: ReplyTone.vague, topics: {Topic.suspicion}, intent: Intent.statement, intensity: 0.5));
        break;
    }

    // ── 7. Guilt / moral reflection (level-gated) ─────────────────────────
    if (level >= 3) {
      chips.add(const PersonalReplyAction('Been doing things', "I've been doing things lately I can't really talk about.", tone: ReplyTone.vague, topics: {Topic.suspicion}, intent: Intent.statement, intensity: 0.5));
    }
    if (level >= 4) {
      chips.add(const PersonalReplyAction('Reflecting', "I've been thinking about the choices I've been making lately.", tone: ReplyTone.honest, topics: {Topic.wellbeing}, intent: Intent.confession, intensity: 0.5));
      chips.add(const PersonalReplyAction('Who am I becoming', "Sometimes I wonder if I'm turning into someone I wouldn't recognize.", tone: ReplyTone.honest, topics: {Topic.wellbeing}, intent: Intent.confession, intensity: 0.6));
      chips.add(PersonalReplyAction("The people I'm around", "I've been spending time around some new people. Different crowd.", tone: ReplyTone.vague, topics: {Topic.suspicion}, intent: Intent.statement, intensity: 0.4));    }
    if (level >= 5) {
      chips.add(const PersonalReplyAction('Worth it?', "I don't know if what I'm doing is worth it anymore.", tone: ReplyTone.honest, topics: {Topic.wellbeing}, intent: Intent.confession, intensity: 0.7));
      chips.add(const PersonalReplyAction('Point of no return', "I've passed a point where I can't really go back to who I was.", tone: ReplyTone.honest, topics: {Topic.wellbeing}, intent: Intent.confession, intensity: 0.7));
      chips.add(const PersonalReplyAction('Carrying a lot', "There's a lot I carry around that nobody knows about.", tone: ReplyTone.honest, topics: {Topic.wellbeing}, intent: Intent.confession, intensity: 0.6));
    }

    // ── 8. Deflection — always available, always last ──────────────────────
    chips.addAll([
      const PersonalReplyAction('Just missed you', "Nothing crazy. Just wanted to hear your voice.", tone: ReplyTone.warm, topics: {Topic.affection}, intent: Intent.statement, intensity: 0.2),
      const PersonalReplyAction('No reason', "No reason. Just missed you.", tone: ReplyTone.warm, topics: {Topic.affection}, intent: Intent.statement, intensity: 0.2),
      const PersonalReplyAction('Bored', "Bored honestly. What are you up to?", tone: ReplyTone.warm, topics: {Topic.greeting}, intent: Intent.question, intensity: 0.2),
      const PersonalReplyAction('Had you on my mind', "Just had you on my mind.", tone: ReplyTone.warm, topics: {Topic.affection}, intent: Intent.statement, intensity: 0.2),
      const PersonalReplyAction('Slow day', "Nothing interesting going on today honestly.", tone: ReplyTone.honest, topics: {Topic.wellbeing}, intent: Intent.statement, intensity: 0.2),
      const PersonalReplyAction('In my head', "I've been quiet lately. Just been in my head.", tone: ReplyTone.vague, topics: {Topic.wellbeing}, intent: Intent.statement, intensity: 0.3),
      const PersonalReplyAction('Just checking in', "Just wanted to check in. See how you're doing.", tone: ReplyTone.warm, topics: {Topic.greeting}, intent: Intent.question, intensity: 0.2),
      const PersonalReplyAction('Today was a lot', "Today was a lot. Don't even know where to start.", tone: ReplyTone.honest, topics: {Topic.wellbeing}, intent: Intent.statement, intensity: 0.3),
    ]);

    return chips;
  }

  /// How many options [personalReplyOptions] surfaces at once — half the
  /// full catalog, rounded up. A proportion rather than a fixed number, so
  /// it stays "half the menu" if the catalog's size ever changes.
  static int get _personalReplyOptionCount => (kPersonalReplyActions.length / 2).ceil();

  /// The subset of [kPersonalReplyActions] offered for [contactId] right
  /// now — narrowed to [_personalReplyOptionCount] options by contact fit
  /// (some options, like flirting, only make sense for certain relations)
  /// and by the live conversation's context: what the thread's on, whether
  /// a question is hanging, how tense/broke/distant things are, and the
  /// time of day. Recomputed from current state on every call (no
  /// randomness), so the same state always offers the same options, and the
  /// menu shifts only when the conversation itself does. Returned in the
  /// catalog's own order, not score order, so the menu reads consistently.
  List<ReplyOption> personalReplyOptions(String contactId) {
    final rel = relationships[contactId]!;
    final threadEmpty = personalThreads[contactId]!.isEmpty;
    final tod = timeOfDay;
    final lv = level;

    // Inject story-contextual chips at the front (up to 3), for every
    // contact — these are generated in priority order so the most
    // urgent/specific chips come first. We don't dedupe against the rest of
    // the tray — a context chip and a general one can have similar intent,
    // but the context one is always more specific and earns its slot
    // independently.
    final contextChips = _storyContextChips(contactId).take(3).map(StoryChipOption.new).toList();

    // Mama and Vale get the intent-chip catalog — see conversation/intents.dart
    // (Mama's kIntentChips) and conversation/vale_intents.dart (Vale's
    // kValeIntentChips). Every other contact keeps the exact original
    // kPersonalReplyActions catalog and scoring below, untouched.
    if (contactId == 'mama' || contactId == 'partner') {
      final chips = contactId == 'mama' ? kIntentChips : kValeIntentChips;

      // Contact-specific legacy actions ('Change the subject', 'Come clean (a
      // little)', 'Deny everything', 'Brush it off', etc. — see the
      // allowedContacts entries in kPersonalReplyActions) predate the
      // intent-chip system and were never migrated into it. They cover
      // exactly the deflection/answer register the generic intent-chip
      // catalog doesn't have (nothing in kIntentChips/kValeIntentChips lets
      // the player lie about or partially explain a suspicion-raising topic)
      // — without them, a pointed follow-up like "what are the actual
      // plans?" had no chip that actually addressed it. Scored/gated
      // identically to every other contact's kPersonalReplyActions tray
      // below, just restricted to entries tagged for this contact. (Vale has
      // none of these yet, so this is simply empty for her today.)
      final eligibleLegacy = [
        for (var i = 0; i < kPersonalReplyActions.length; i++)
          if (kPersonalReplyActions[i].allowedContacts?.contains(contactId) ?? false)
            if (kPersonalReplyActions[i].showWhenMoodBelow == null || rel.mood < kPersonalReplyActions[i].showWhenMoodBelow!)
              if (kPersonalReplyActions[i].showWhenMoodAbove == null || rel.mood > kPersonalReplyActions[i].showWhenMoodAbove!)
                if (!kPersonalReplyActions[i].requiresThread || !threadEmpty)
                  if (kPersonalReplyActions[i].showWhenLevelMin == null || lv >= kPersonalReplyActions[i].showWhenLevelMin!)
                    if (kPersonalReplyActions[i].showWhenLevelMax == null || lv <= kPersonalReplyActions[i].showWhenLevelMax!)
                      if (kPersonalReplyActions[i].showWhenTrustBelow == null || rel.trust < kPersonalReplyActions[i].showWhenTrustBelow!)
                        if (kPersonalReplyActions[i].showWhenTrustAbove == null || rel.trust > kPersonalReplyActions[i].showWhenTrustAbove!)
                          if (kPersonalReplyActions[i].showWhenSuspicionAbove == null || rel.suspicion > kPersonalReplyActions[i].showWhenSuspicionAbove!)
                            if (kPersonalReplyActions[i].showWhenClosenessAbove == null || rel.closeness > kPersonalReplyActions[i].showWhenClosenessAbove!)
                              (index: i, action: kPersonalReplyActions[i]),
      ];
      final scoredLegacy = [
        for (final e in eligibleLegacy) (index: e.index, action: e.action, score: _personalReplyOptionScore(e.action, rel: rel, threadEmpty: threadEmpty, tod: tod, level: lv)),
      ]..sort((a, b) {
          final byScore = b.score.compareTo(a.score);
          return byScore != 0 ? byScore : a.index.compareTo(b.index);
        });
      final pickedLegacy = scoredLegacy.take(_mamaLegacyActionCount).toList()..sort((a, b) => a.index.compareTo(b.index));
      final legacyChips = pickedLegacy.map((p) => StoryChipOption(p.action));

      final eligible = [
        for (var i = 0; i < chips.length; i++)
          if (chips[i].showWhenMoodBelow == null || rel.mood < chips[i].showWhenMoodBelow!)
            if (chips[i].showWhenMoodAbove == null || rel.mood > chips[i].showWhenMoodAbove!)
              if (!chips[i].requiresThread || !threadEmpty)
                if (chips[i].showWhenLevelMin == null || lv >= chips[i].showWhenLevelMin!)
                  if (chips[i].showWhenLevelMax == null || lv <= chips[i].showWhenLevelMax!)
                    if (chips[i].showWhenTrustBelow == null || rel.trust < chips[i].showWhenTrustBelow!)
                      if (chips[i].showWhenTrustAbove == null || rel.trust > chips[i].showWhenTrustAbove!)
                        if (chips[i].showWhenSuspicionAbove == null || rel.suspicion > chips[i].showWhenSuspicionAbove!)
                          if (chips[i].showWhenClosenessAbove == null || rel.closeness > chips[i].showWhenClosenessAbove!)
                            (index: i, chip: chips[i]),
      ];
      final scored = [
        for (final e in eligible) (index: e.index, chip: e.chip, score: _intentChipScore(e.chip, rel: rel, threadEmpty: threadEmpty, tod: tod, level: lv)),
      ]..sort((a, b) {
          final byScore = b.score.compareTo(a.score);
          return byScore != 0 ? byScore : a.index.compareTo(b.index);
        });
      // _intentChipScore starts every chip at a baseline of 1.0 and only adds
      // from there — a chip still sitting at exactly 1.0 got no contextual
      // signal at all (nothing about mood/topic/time-of-day/level favors it
      // right now), so it isn't relevant to this turn, just generically
      // available. Filtering those out means the tray only ever contains
      // chips something about the current state actually justifies, instead
      // of always padding up to _intentChipCount with whatever was left.
      // The single top-scored chip is kept even at baseline as a floor, so
      // the tray is never completely empty when truly nothing stands out.
      final relevant = scored.where((e) => e.score > 1.0).toList();
      final picked = (relevant.isNotEmpty ? relevant : scored.take(1).toList()).take(_intentChipCount);
      // Kept in score order (highest first), not re-sorted back to catalog
      // order — whichever chip is actually the best fit for what just
      // happened leads, whether that's Explain More after a real topic gets
      // raised or something else entirely after a plain Greet. `scored` is
      // already sorted this way (see above), so this just carries that
      // order through instead of discarding it.
      final pickedChips = picked.map((p) => p.chip).toList();
      // Mama-only for now: resolveMoneyAsk's reaction pool (kMamaMoneyAskReactions)
      // is written in her voice specifically, so surfacing this for Vale
      // would send her replies in the wrong character's voice. Surfaced
      // whenever the live thread is actually on money and the weekly cap
      // isn't spent — see resolveMoneyAsk. Placed right after the context
      // chips so it's easy to spot the turn it's actually relevant, rather
      // than buried among the always-present intent chips.
      final moneyAskChip = (contactId == 'mama' && rel.currentTopic == Topic.money && moneyAsksRemaining(contactId) > 0)
          ? const [MoneyAskChipOption()]
          : const <ReplyOption>[];
      return [...contextChips, ...moneyAskChip, ...legacyChips, ...pickedChips];
    }

    final eligible = [
      for (var i = 0; i < kPersonalReplyActions.length; i++)
        if (kPersonalReplyActions[i].allowedContacts == null || kPersonalReplyActions[i].allowedContacts!.contains(contactId))
          // Visibility gates: mood, thread-presence, level, trust, suspicion, closeness.
          if (kPersonalReplyActions[i].showWhenMoodBelow == null || rel.mood < kPersonalReplyActions[i].showWhenMoodBelow!)
            if (kPersonalReplyActions[i].showWhenMoodAbove == null || rel.mood > kPersonalReplyActions[i].showWhenMoodAbove!)
              if (!kPersonalReplyActions[i].requiresThread || !threadEmpty)
                if (kPersonalReplyActions[i].showWhenLevelMin == null || lv >= kPersonalReplyActions[i].showWhenLevelMin!)
                  if (kPersonalReplyActions[i].showWhenLevelMax == null || lv <= kPersonalReplyActions[i].showWhenLevelMax!)
                    if (kPersonalReplyActions[i].showWhenTrustBelow == null || rel.trust < kPersonalReplyActions[i].showWhenTrustBelow!)
                      if (kPersonalReplyActions[i].showWhenTrustAbove == null || rel.trust > kPersonalReplyActions[i].showWhenTrustAbove!)
                        if (kPersonalReplyActions[i].showWhenSuspicionAbove == null || rel.suspicion > kPersonalReplyActions[i].showWhenSuspicionAbove!)
                          if (kPersonalReplyActions[i].showWhenClosenessAbove == null || rel.closeness > kPersonalReplyActions[i].showWhenClosenessAbove!)
                            (index: i, action: kPersonalReplyActions[i]),
    ];
    final scored = [
      for (final e in eligible) (index: e.index, action: e.action, score: _personalReplyOptionScore(e.action, rel: rel, threadEmpty: threadEmpty, tod: tod, level: lv)),
    ]..sort((a, b) {
        final byScore = b.score.compareTo(a.score);
        return byScore != 0 ? byScore : a.index.compareTo(b.index);
      });
    final picked = scored.take(_personalReplyOptionCount).toList()..sort((a, b) => a.index.compareTo(b.index));
    final staticChips = picked.map((p) => StoryChipOption(p.action));

    return [...contextChips, ...staticChips];
  }

  /// How many [IntentChip]s [personalReplyOptions] surfaces at once for
  /// Mama, on top of up to 3 story chips — a fixed tray size rather than a
  /// proportion of the 20-entry catalog (unlike [_personalReplyOptionCount]):
  /// half of 20 is a tray nobody can scan at a glance.
  static const int _intentChipCount = 5;

  /// How many of Mama's orphaned legacy [kPersonalReplyActions] entries
  /// (allowedContacts: {'mama'}) [personalReplyOptions] surfaces alongside
  /// her intent chips — small on purpose, since these exist to plug specific
  /// deflection/answer gaps the generic intent-chip catalog doesn't cover,
  /// not to duplicate it wholesale.
  static const int _mamaLegacyActionCount = 2;

  /// How many times per week (reset at the [_advanceDay] week boundary) the
  /// player can use Mama's "(Ask for Money)" flow — see [resolveMoneyAsk].
  /// Small on purpose: unlike every other personal-thread action, this one
  /// grants real [cash], so it needs a hard cap rather than just a
  /// relationship-stat nudge.
  static const int kMaxMoneyAsksPerWeek = 2;

  /// Remaining "(Ask for Money)" uses this week for [contactId].
  int moneyAsksRemaining(String contactId) =>
      (kMaxMoneyAsksPerWeek - relationships[contactId]!.moneyAsksThisWeek).clamp(0, kMaxMoneyAsksPerWeek);

  /// Mirrors [_personalReplyOptionScore], adapted to an [IntentChip]'s
  /// (primaryTone, primaryTopics, primaryIntent) — the representative
  /// register used for tray-ranking nudges only; the actual turn plays out
  /// with whichever phrasing line pickLine() ends up choosing.
  static double _intentChipScore(
    IntentChip a, {
    required RelationshipState rel,
    required bool threadEmpty,
    required TimeOfDay tod,
    required int level,
  }) {
    var score = 1.0;

    if (threadEmpty) {
      if (a.primaryTopics.contains(Topic.greeting)) score += 5;
      if (a.primaryIntent == Intent.dismissal) score -= 3;
    }

    if (rel.currentTopic != null && a.primaryTopics.contains(rel.currentTopic)) score += 4;
    if (!rel.lastQuestionAnswered && a.primaryIntent == Intent.dismissal) score -= 3;

    // Elaborate exists specifically to answer "say more" — it should win a
    // slot whenever there's actually a thread to continue or a question
    // hanging, so the player is never left with nothing that flows with
    // what Mama just said. Outweighs the empty-thread greeting bonus above
    // on purpose: a live topic or pending question only exists once the
    // thread already has content, so the two conditions never fight.
    // Topic.greeting is excluded on purpose — a plain "hey" isn't a subject
    // worth "explaining more" about, so it shouldn't make elaborate look
    // like the best reply just because some topic happens to be set.
    if (a.intent == ConversationIntent.elaborate) {
      if (rel.topicProgress >= 1 && rel.currentTopic != Topic.greeting) score += 8;
      if (!rel.lastQuestionAnswered) score += 6;
    }

    if (rel.fear > 40 && a.primaryTone == ReplyTone.warm) score += 2;
    if (rel.suspicion > 50 && (a.primaryTone == ReplyTone.warm || a.primaryTone == ReplyTone.honest)) score += 2;
    if (rel.trust < 30 && a.primaryTone == ReplyTone.honest) score += 2;

    if (rel.mood < -30 && (a.primaryTone == ReplyTone.warm || a.primaryIntent == Intent.promise)) score += 4;
    if (rel.mood < -30 && (a.primaryTone == ReplyTone.cold || a.primaryIntent == Intent.dismissal)) score -= 4;
    if (rel.mood < -10 && a.primaryIntent == Intent.dismissal) score -= 2;
    if (rel.mood > 30 && a.primaryTopics.contains(Topic.affection)) score += 2;
    if (rel.mood > 30 && (a.primaryTopics.contains(Topic.wellbeing) || a.primaryTopics.contains(Topic.goodNews))) score += 1;

    switch (tod) {
      case TimeOfDay.morning:
        if (a.primaryTopics.contains(Topic.greeting) || a.primaryTopics.contains(Topic.wellbeing)) score += 2;
        break;
      case TimeOfDay.afternoon:
        if (a.primaryTopics.contains(Topic.family) || a.primaryTopics.contains(Topic.suspicion)) score += 2;
        break;
      case TimeOfDay.evening:
      case TimeOfDay.night:
        if (a.primaryTopics.contains(Topic.affection) || a.primaryIntent == Intent.promise) score += 2;
        break;
    }

    if (a.showWhenLevelMin != null && level >= a.showWhenLevelMin!) score += 2;
    if (a.showWhenLevelMax != null && level <= a.showWhenLevelMax!) score += 1;
    if (a.showWhenSuspicionAbove != null && rel.suspicion > (a.showWhenSuspicionAbove! + 15)) score += 2;
    if (a.showWhenTrustAbove != null && rel.trust > (a.showWhenTrustAbove! + 10)) score += 1;
    if (a.showWhenClosenessAbove != null && rel.closeness > (a.showWhenClosenessAbove! + 10)) score += 1;

    return score;
  }

  /// Sends [intent] to [contactId] (Mama, in practice — the only contact
  /// [personalReplyOptions] offers [IntentChip]s for): picks the actual
  /// player-side wording from the chip's [IntentChip.phrasings] via
  /// pickLine() (so it varies turn to turn even though the chip's label
  /// never does), then routes through the existing, unmodified
  /// [personalReplyAction] — every stat delta, block check, topic-thread
  /// update, and spam counter behaves exactly as it already did for a
  /// scripted [PersonalReplyAction].
  void sendIntent(String contactId, ConversationIntent intent) {
    final rel = relationships[contactId]!;
    if (rel.goneQuiet || rel.resolved || rel.isBlocked) return;
    final chips = contactId == 'mama' ? kIntentChips : kValeIntentChips;
    final chip = chips.firstWhere((c) => c.intent == intent);
    final ctx = DialogueContext(
      mood: rel.mood,
      closeness: rel.closeness,
      trust: rel.trust,
      suspicion: rel.suspicion,
      daysSinceReply: rel.daysSinceReply,
      recentTones: rel.recentTones,
      memories: rel.memories,
      timeOfDay: timeOfDay,
      isWeekend: isWeekend,
      currentTopic: rel.currentTopic,
      topicProgress: rel.topicProgress,
      playerTopicsToday: rel.topicsDiscussedToday,
      levelPhase: levelPhase,
      recentConversation: rel.recentConversation,
      facts: rel.facts,
      honesty: rel.honesty,
      reliability: rel.reliability,
      responsiveness: rel.responsiveness,
    );
    final line = pickLine(
          _rng,
          chip.phrasings,
          ctx,
          currentDay: day,
          lineLastUsedDay: rel.lineLastUsedDay,
          recentLineHistory: rel.recentLineHistory,
        ) ??
        chip.phrasings.first;
    recordLineUse(rel.lineLastUsedDay, rel.recentLineHistory, line, day);

    final action = PersonalReplyAction(
      chip.label,
      line.text,
      tone: line.tone ?? chip.primaryTone,
      topics: line.topic != null ? {line.topic!, ...chip.primaryTopics} : chip.primaryTopics,
      intent: line.intent ?? chip.primaryIntent,
      intensity: chip.intensity,
      conversationIntent: intent,
      // Forwarded from whichever specific phrasing pickLine() chose — a
      // pre-existing gap fixed alongside establishesFacts below: subject/
      // resolvesThread already existed on DialogueLine (Phase 3) but were
      // never carried over here, so no IntentChip phrasing's subject/
      // resolvesThread has ever actually taken effect. No behavior change
      // for existing content (nothing currently sets either on a phrasing),
      // but silently dropping them here would leave establishesFacts with
      // the exact same latent gap the moment anyone tries to use it below.
      subject: line.subject,
      resolvesThread: line.resolvesThread,
      establishesFacts: line.establishesFacts,
      fulfillsPromise: line.fulfillsPromise,
    );
    personalReplyAction(contactId, action);
  }

  /// Resolves the player's typed dollar amount from Mama's "(Ask for Money)"
  /// flow (relationships_screen.dart's _showAskForMoneyDialog, reached via
  /// [MoneyAskChipOption] in [personalReplyOptions]). Distinct from
  /// [sendIntent]/[personalReplyAction]: this is the one place in a personal
  /// thread where the player's reply carries a real number instead of a
  /// pre-written phrasing, so the reaction has to branch on the amount
  /// itself (see [_resolveMoneyAskOutcome]) rather than a scripted
  /// (tone, topic, intent). Also the only personal-thread action that grants
  /// real [cash] — capped by [kMaxMoneyAsksPerWeek]/[moneyAsksRemaining] so
  /// it can't become a free-money loop.
  void resolveMoneyAsk(String contactId, int amount) {
    final rel = relationships[contactId]!;
    if (rel.goneQuiet || rel.resolved || rel.isBlocked) return;
    if (amount <= 0 || moneyAsksRemaining(contactId) <= 0) return;
    rel.moneyAsksThisWeek += 1;

    personalThreads[contactId]!.add(Message('Can you send me \$$amount?', true));

    final advanced = advanceTopic(
      currentTopic: rel.currentTopic,
      currentProgress: rel.topicProgress,
      messageTopics: {Topic.money},
      currentSubject: rel.topicSubject,
      currentUnresolved: rel.topicUnresolved,
      currentTurnsActive: rel.topicTurnsActive,
      messageSubject: 'money ask',
    );
    rel.currentTopic = advanced.topic;
    rel.topicProgress = advanced.progress;
    rel.topicSubject = advanced.subject;
    rel.topicUnresolved = advanced.unresolved;
    rel.topicTurnsActive = advanced.turnsActive;
    rel.lastQuestionAnswered = true;

    rel.turnCount += 1;
    _openPendingInteraction(rel, type: InteractionType.request, topic: Topic.money, subject: 'money ask');
    rel.recentConversation.add(ConversationEvent(
      topic: Topic.money,
      tone: ReplyTone.honest,
      intensity: 0.6,
      fromMe: true,
      turn: rel.turnCount,
      day: day,
      level: level,
      phase: levelPhase,
      importance: MemoryImportance.medium,
    ));

    final outcome = _resolveMoneyAskOutcome(amount, rel);
    // The request is resolved the instant Mama responds — granted, reluctant,
    // or refused all count as "addressed"; resolved means answered, not
    // necessarily satisfied.
    _resolvePendingInteraction(rel, InteractionType.request);
    switch (outcome) {
      case MoneyAskOutcome.granted:
        cash += amount;
        rel.trust = (rel.trust + 3).clamp(0, 100);
        rel.debt = (rel.debt + amount / 15).clamp(0, 100);
        rel.mood = (rel.mood + 6).clamp(-100, 100);
        break;
      case MoneyAskOutcome.reluctant:
        cash += amount;
        rel.debt = (rel.debt + amount / 8).clamp(0, 100);
        rel.suspicion = (rel.suspicion + 6).clamp(0, 100);
        rel.mood = (rel.mood - 3).clamp(-100, 100);
        break;
      case MoneyAskOutcome.refused:
        rel.mood = (rel.mood - 10).clamp(-100, 100);
        rel.suspicion = (rel.suspicion + (amount > 300 ? 10 : 5)).clamp(0, 100);
        break;
    }

    final ctx = DialogueContext(
      mood: rel.mood,
      closeness: rel.closeness,
      trust: rel.trust,
      suspicion: rel.suspicion,
      daysSinceReply: rel.daysSinceReply,
      recentTones: rel.recentTones,
      memories: rel.memories,
      timeOfDay: timeOfDay,
      isWeekend: isWeekend,
      currentTopic: rel.currentTopic,
      topicProgress: rel.topicProgress,
      levelPhase: levelPhase,
      recentConversation: rel.recentConversation,
      facts: rel.facts,
      honesty: rel.honesty,
      reliability: rel.reliability,
      responsiveness: rel.responsiveness,
    );
    final pool = kMamaMoneyAskReactions[outcome]!;
    final line = pickLine(_rng, pool, ctx, currentDay: day, lineLastUsedDay: rel.lineLastUsedDay, recentLineHistory: rel.recentLineHistory) ?? pool.first;
    recordLineUse(rel.lineLastUsedDay, rel.recentLineHistory, line, day);

    personalThreads[contactId]!.add(Message(line.text, false));
    rel.lastLine = line.text;
    rel.recentConversation.add(ConversationEvent(
      topic: Topic.money,
      tone: ReplyTone.honest,
      intensity: 0.6,
      fromMe: false,
      turn: rel.turnCount,
      day: day,
      level: level,
      phase: levelPhase,
      importance: MemoryImportance.medium,
    ));
    _pruneConversationMemory(rel);
    notifyListeners();
  }

  /// $100 or less: she just sends it. $101-300: she will, but only once
  /// there's enough trust/closeness to not feel used — otherwise it's a
  /// refusal like anything larger. Above $300 is always too much, regardless
  /// of relationship state — no amount of trust makes handing over that much
  /// cash on a text thread feel reasonable to a mother on a tight budget.
  static MoneyAskOutcome _resolveMoneyAskOutcome(int amount, RelationshipState rel) {
    if (amount <= 100) return MoneyAskOutcome.granted;
    if (amount <= 300) {
      return (rel.trust >= 35 && rel.closeness >= 30) ? MoneyAskOutcome.reluctant : MoneyAskOutcome.refused;
    }
    return MoneyAskOutcome.refused;
  }

  /// How much weight a [ConversationEvent] carries in
  /// [RelationshipState.recentConversation] — see [_pruneConversationMemory]
  /// for how this drives eviction, and [_permanentMemoryFor] for which
  /// intents also get promoted into the permanent [RelationshipState.memories]
  /// log. A legacy free-text-derived turn (conversationIntent == null) is
  /// always low — there's no chip-level signal to weigh it by.
  static MemoryImportance _conversationImportance(ConversationIntent? intent) {
    const high = {ConversationIntent.confront, ConversationIntent.questionLoyalty, ConversationIntent.makePeace};
    const medium = {
      ConversationIntent.apologize,
      ConversationIntent.insult,
      ConversationIntent.askAboutFamily,
      ConversationIntent.askForHelp,
      ConversationIntent.askForAdvice,
      ConversationIntent.compliment,
      ConversationIntent.congratulate,
      ConversationIntent.reassure,
      ConversationIntent.askAboutSomeone,
      ConversationIntent.askWhatsGoingOn,
      ConversationIntent.askAboutWork,
    };
    if (intent == null) return MemoryImportance.low;
    if (high.contains(intent)) return MemoryImportance.high;
    if (medium.contains(intent)) return MemoryImportance.medium;
    return MemoryImportance.low;
  }

  /// A high-importance turn is charged enough to outlive
  /// [RelationshipState.recentConversation]'s rolling window entirely — it
  /// gets promoted into the permanent [MemoryEvent] log the same way
  /// [MemoryKind.firstWarmReply] already does elsewhere. Returns null for an
  /// intent that's high-importance for the moment but isn't the kind of
  /// thing worth a permanent milestone (none currently — every entry in
  /// [_conversationImportance]'s `high` set maps to one).
  static MemoryKind? _permanentMemoryFor(ConversationIntent intent) => switch (intent) {
        ConversationIntent.confront || ConversationIntent.questionLoyalty => MemoryKind.deepConfession,
        ConversationIntent.makePeace => MemoryKind.promiseMade,
        _ => null,
      };

  /// Bounds [RelationshipState.recentConversation]: low-importance turns
  /// (small talk) expire the day after they happen, medium-importance turns
  /// (arguments, apologies, real questions) last 3 days, and high-importance
  /// turns are never day-pruned — only the hard 12-entry cap below can push
  /// one out, and by then it's already been promoted to a permanent memory
  /// (see [_permanentMemoryFor]). Called after every new turn and once more
  /// on each morning tick, so a quiet contact's window still ages out even
  /// on days the player never opens their thread.
  void _pruneConversationMemory(RelationshipState rel) {
    rel.recentConversation.removeWhere((e) {
      final age = day - e.day;
      switch (e.importance) {
        case MemoryImportance.low:
          return age >= 1;
        case MemoryImportance.medium:
          return age >= 3;
        case MemoryImportance.high:
          return false;
      }
    });
    while (rel.recentConversation.length > 12) {
      rel.recentConversation.removeAt(0);
    }
  }

  /// Opens a new [PendingInteraction], first resolving any existing
  /// unresolved one of the same [type] — mirrors the single-slot semantics
  /// [RelationshipState.lastQuestionAnswered] already had for questions
  /// specifically: only one of a given type is ever meaningfully "live" at
  /// once, so a fresh one supersedes rather than piling up alongside a stale
  /// one nobody was ever going to resolve. FIFO-capped the same way
  /// [_pruneConversationMemory] caps recentConversation, so a long-running
  /// relationship's history doesn't grow unbounded.
  void _openPendingInteraction(
    RelationshipState rel, {
    required InteractionType type,
    Topic? topic,
    String? subject,
    int? deadlineTurn,
  }) {
    for (final existing in rel.pendingInteractions) {
      if (existing.type == type && !existing.resolved) existing.resolved = true;
    }
    rel.pendingInteractions.add(PendingInteraction(
      type: type,
      topic: topic,
      subject: subject,
      createdTurn: rel.turnCount,
      deadlineTurn: deadlineTurn,
    ));
    while (rel.pendingInteractions.length > 20) {
      rel.pendingInteractions.removeAt(0);
    }
  }

  /// Resolves the most recently opened, still-unresolved [type] interaction,
  /// if any. A no-op when nothing of that type is currently open — safe to
  /// call speculatively (see its call site in [personalReplyAction]) rather
  /// than only when the caller already knows one exists.
  void _resolvePendingInteraction(RelationshipState rel, InteractionType type) {
    for (final existing in rel.pendingInteractions.reversed) {
      if (existing.type == type && !existing.resolved) {
        existing.resolved = true;
        return;
      }
    }
  }

  /// Higher favors surfacing [a] in [personalReplyOptions] right now.
  /// Additive nudges on a base of 1.0 — not a formal formula like the
  /// engine's [pickLine] weights, just enough of a thumb on the scale that
  /// contextually sensible options rise to the top of the cut.
  static double _personalReplyOptionScore(
    PersonalReplyAction a, {
    required RelationshipState rel,
    required bool threadEmpty,
    required TimeOfDay tod,
    required int level,
  }) {
    var score = 1.0;

    if (threadEmpty) {
      // Opening a conversation favors a greeting; leading with a dismissal
      // reads as a non-sequitur when nothing's been said yet.
      if (a.topics.contains(Topic.greeting)) score += 5;
      if (a.intent == Intent.dismissal) score -= 3;
    }

    // Staying on the thread's live topic favors continuing it.
    if (rel.currentTopic != null && a.topics.contains(rel.currentTopic)) score += 4;

    // A question left hanging favors an actual answer over a dodge.
    if (!rel.lastQuestionAnswered && a.intent == Intent.dismissal) score -= 3;

    // Money already on the table favors the money-tagged options.
    if (a.isDebtTopic && (rel.debt > 25 || rel.currentTopic == Topic.money)) score += 4;

    // Tense or fraying favors de-escalating; low trust favors honesty.
    if (rel.fear > 40 && a.tone == ReplyTone.warm) score += 2;
    if (rel.suspicion > 50 && (a.tone == ReplyTone.warm || a.tone == ReplyTone.honest)) score += 2;
    if (rel.trust < 30 && a.tone == ReplyTone.honest) score += 2;

    // Mood-aware nudges — when she's hurt, warm/repair options rise; cold sinks.
    if (rel.mood < -30 && (a.tone == ReplyTone.warm || a.intent == Intent.promise)) score += 4;
    if (rel.mood < -30 && (a.tone == ReplyTone.cold || a.intent == Intent.dismissal)) score -= 4;
    if (rel.mood < -10 && a.intent == Intent.dismissal) score -= 2;
    if (rel.mood > 30 && a.topics.contains(Topic.affection)) score += 2;
    if (rel.mood > 30 && (a.topics.contains(Topic.wellbeing) || a.topics.contains(Topic.goodNews))) score += 1;

    // Time of day colors what reads naturally to bring up.
    switch (tod) {
      case TimeOfDay.morning:
        if (a.topics.contains(Topic.greeting) || a.topics.contains(Topic.wellbeing)) score += 2;
        break;
      case TimeOfDay.afternoon:
        if (a.topics.contains(Topic.family) || a.topics.contains(Topic.suspicion) || a.isDebtTopic) score += 2;
        break;
      case TimeOfDay.evening:
      case TimeOfDay.night:
        if (a.topics.contains(Topic.affection) || a.intent == Intent.promise) score += 2;
        break;
    }

    // Story-level nudges — options that fit the current level of tension
    // score higher so the most contextually appropriate ones rise to the top
    // of the cut without needing to hard-exclude others.
    if (a.showWhenLevelMin != null && level >= a.showWhenLevelMin!) score += 2;
    if (a.showWhenLevelMax != null && level <= a.showWhenLevelMax!) score += 1;
    // High-suspicion options score higher when the character is already worried.
    if (a.showWhenSuspicionAbove != null && rel.suspicion > (a.showWhenSuspicionAbove! + 15)) score += 2;
    // Trust-gated options score higher when trust matches their intent.
    if (a.showWhenTrustAbove != null && rel.trust > (a.showWhenTrustAbove! + 10)) score += 1;
    if (a.showWhenClosenessAbove != null && rel.closeness > (a.showWhenClosenessAbove! + 10)) score += 1;

    return score;
  }

  /// Reply to [contactId] by picking a [PersonalReplyAction] (from
  /// [personalReplyOptions], though any catalog entry is accepted) — each
  /// option already declares the (tone, topics, intent, intensity) axes
  /// [classifyMessage] used to infer from free text, so choosing one is
  /// self-classifying. Applies the relationship-stat deltas scaled by
  /// [impactMultiplier] and picks a same-turn reaction line, identically to
  /// how the old free-text path did once classification was done.
  void personalReplyAction(String contactId, PersonalReplyAction action) {
    final rel = relationships[contactId]!;
    if (rel.goneQuiet || rel.resolved || rel.isBlocked) return;
    // Captured before recentStoryEvent is cleared below — [levelPhase]
    // reads recentStoryEvent to detect LevelPhase.cusp, so evaluating it
    // after the clear would make cusp permanently unreachable from this
    // method's own ConversationEvent record and reaction DialogueContext.
    final turnPhase = levelPhase;
    // Consume the story event — the player has spoken about (or chosen not to
    // speak about) whatever just happened. The tray resets to its normal state.
    recentStoryEvent = null;
    final p = kPersonalContact[contactId]!;
    final impact = impactMultiplier(action.intensity);

    // Captured before advanceTopic overwrites it — planResponse() needs to
    // know whether this turn actually switched topics, not just what the
    // topic is now.
    final previousTopic = rel.currentTopic;

    // Tracks what this conversation thread is on and how many turns it's
    // been on it — lets reaction selection continue/deepen the same topic
    // instead of picking blind by tone alone (see advanceTopic()).
    final advanced = advanceTopic(
      currentTopic: rel.currentTopic,
      currentProgress: rel.topicProgress,
      messageTopics: action.topics,
      currentSubject: rel.topicSubject,
      currentUnresolved: rel.topicUnresolved,
      currentTurnsActive: rel.topicTurnsActive,
      messageSubject: action.subject,
      resolves: action.resolvesThread,
    );
    rel.currentTopic = advanced.topic;
    rel.topicProgress = advanced.progress;
    rel.topicSubject = advanced.subject;
    rel.topicUnresolved = advanced.unresolved;
    rel.topicTurnsActive = advanced.turnsActive;

    // Was a question mama asked left dangling? A dismissal ("whatever",
    // "nvm") while one's pending is a dodge — surfaces for exactly this
    // reply via questionJustDodged, then clears either way (the question
    // isn't "pending" indefinitely once the player has responded at all).
    // Captured before resolvePendingQuestion overwrites lastQuestionAnswered
    // — planResponse() needs to know whether one was genuinely pending
    // going into this turn, not just the post-turn state.
    final questionWasPending = !rel.lastQuestionAnswered;
    final resolved = resolvePendingQuestion(wasAnswered: rel.lastQuestionAnswered, messageIntent: action.intent);
    rel.lastQuestionAnswered = resolved.answered;
    if (resolved.answered) _resolvePendingInteraction(rel, InteractionType.question);
    final dodgedNow = resolved.justDodged;

    // Behavioral reputation (Phase 9): a dodge PATTERN, not just this one
    // dodge — dodgeMatch/dodgedNow already drive this turn's own line
    // selection; this is the separate "this isn't the first time" layer on
    // top of that, so it only counts consecutive dodges, resetting on any
    // non-dodge reply.
    rel.consecutiveDodgeCount = dodgedNow ? rel.consecutiveDodgeCount + 1 : 0;
    rel.suspicion = nudgeSuspicionFromDodgePattern(rel.suspicion, rel.consecutiveDodgeCount);

    // Short-term conversation memory (intent-chip system): every turn gets a
    // ConversationEvent, so a later reply — Mama's, specifically, see
    // kMamaIntentReactions/recallMatch below — can reference what was just
    // said instead of treating each turn as an isolated dialogue box. Legacy
    // free-text-derived actions (conversationIntent == null) still get
    // recorded (importance low), just never match a requiresRecentIntent gate.
    rel.turnCount += 1;
    final myTurn = rel.turnCount;

    // A promise-tagged reply opens a pending interaction of its own — nothing
    // previously tracked a promise past the one-time MemoryKind.promiseMade
    // milestone, so there was no way to later reference (or check on)
    // something specific the player committed to. Placed after the turnCount
    // increment above so createdTurn lines up with the same turn number this
    // turn's ConversationEvent below is logged under, not the prior turn's.
    if (action.intent == Intent.promise) {
      _openPendingInteraction(rel, type: InteractionType.promise, topic: rel.currentTopic, subject: action.subject);
    }

    // A promise explicitly kept (Phase 9) — the "kept" half of reliability
    // tracking only; see fulfillsPromise's doc comment for why the "broken"
    // half (deadline expiry) isn't wired.
    if (action.fulfillsPromise) {
      _resolvePendingInteraction(rel, InteractionType.promise);
      rel.reliability = nudgeReliability(rel.reliability);
      rel.trust = (rel.trust + 0.5).clamp(0, 100);
    }

    // Whatever this reply establishes about the player becomes a durable,
    // keyed fact — see recordFact()'s doc comment for repeated-vs-
    // contradicting-value handling. Surfaced to planResponse() below when it
    // actually contradicts something — only the first one, if an action
    // somehow establishes more than one fact and more than one contradicts;
    // no current content does that, so ResponsePlan carrying just one is a
    // real (if currently theoretical) limitation, not an oversight.
    ContradictionEvent? contradiction;
    action.establishesFacts?.forEach((key, value) {
      contradiction ??= recordFact(rel.facts, key, value, myTurn);
    });

    final turnImportance = _conversationImportance(action.conversationIntent);
    rel.recentConversation.add(ConversationEvent(
      intent: action.conversationIntent,
      topic: rel.currentTopic,
      tone: action.tone,
      intensity: action.intensity,
      fromMe: true,
      turn: myTurn,
      day: day,
      level: level,
      phase: turnPhase,
      dodged: dodgedNow,
      importance: turnImportance,
    ));
    // A handful of intents mark a real relationship moment, not small talk —
    // promote those into the existing permanent [memories] log so they
    // outlive the rolling window's cap even after it's pruned or evicted.
    if (turnImportance == MemoryImportance.high) {
      final kind = _permanentMemoryFor(action.conversationIntent!);
      if (kind != null) recordMemory(rel.memories, MemoryEvent(kind, day));
    }
    _pruneConversationMemory(rel);

    personalThreads[contactId]!.add(Message(action.resolveText(rel, timeOfDay), true));

    switch (action.tone) {
      case ReplyTone.warm:
        // The Golden Cage limits how close you can still get, even when you try.
        final closenessGain = (level >= 6 ? 4.0 : 8.0) * impact;
        rel.closeness = (rel.closeness + closenessGain).clamp(0, 100);
        rel.trust = (rel.trust + 5 * impact).clamp(0, 100);
        rel.suspicion = (rel.suspicion - 6 * p.suspicionRate * impact).clamp(0, 100);
        break;
      case ReplyTone.honest:
        rel.trust = (rel.trust + 8 * impact).clamp(0, 100);
        rel.suspicion = (rel.suspicion + 3 * p.suspicionRate * impact).clamp(0, 100);
        break;
      case ReplyTone.vague:
        rel.closeness = (rel.closeness - 2 * impact).clamp(0, 100);
        rel.suspicion = (rel.suspicion + 6 * p.suspicionRate * impact).clamp(0, 100);
        break;
      case ReplyTone.cold:
        rel.closeness = (rel.closeness - 10 * impact).clamp(0, 100);
        rel.trust = (rel.trust - 8 * impact).clamp(0, 100);
        rel.suspicion = (rel.suspicion + 4 * p.suspicionRate * impact).clamp(0, 100);
        break;
      case ReplyTone.excuse:
        // Betrayal (formula 14's block trigger) is the sole betrayalCount
        // path — a lie the contact already half-suspects blowing up on you.
        final backfire = rel.suspicion > 50;
        rel.trust = (rel.trust + (backfire ? -4 : 6) * impact).clamp(0, 100);
        rel.suspicion = (rel.suspicion + (backfire ? 14 : 5) * p.suspicionRate * impact).clamp(0, 100);
        if (backfire) rel.betrayalCount += 1;
        break;
    }

    rel.fear = nudgeFear(rel.fear, action.tone, action.intensity);
    rel.respect = nudgeRespect(rel.respect, action.tone, action.intensity);
    rel.debt = nudgeDebt(rel.debt, isDebtTopic: action.isDebtTopic, tone: action.tone);

    // Captured before pushRecentTone overwrites it — the tone from the
    // player's immediately prior turn, if any, used to notice a sudden
    // register change (e.g. a bare "hey" followed by "let's be honest").
    final previousTone = rel.recentTones.isNotEmpty ? rel.recentTones.last : null;
    final toneShifted = detectToneShift(previousTone: previousTone, tone: action.tone);

    rel.mood = nudgeMood(rel.mood, action.tone, personalityModifier: personalityModifier(p.emotionalVolatility));
    pushRecentTone(rel.recentTones, action.tone);
    if (action.tone == ReplyTone.warm) {
      recordMemory(rel.memories, MemoryEvent(MemoryKind.firstWarmReply, day), once: true);
    }

    // Consecutive-action spam tracking — increments when the player sends the
    // same action back-to-back; resets on any different action.
    if (action.label == rel.lastActionLabel) {
      rel.consecutiveActionCount += 1;
    } else {
      rel.lastActionLabel = action.label;
      rel.consecutiveActionCount = 1;
    }

    // Within-day memory — count how many times this action was sent today and
    // accumulate the topics the player has raised so the character can
    // reference them in later proactive openers.
    rel.todayActionCounts[action.label] = (rel.todayActionCounts[action.label] ?? 0) + 1;
    rel.topicsDiscussedToday.addAll(action.topics);

    // Block consequence (formula 14): two backfired lies with trust already
    // gone is the end of the conversation, permanently.
    if (rel.trust < 15 && rel.betrayalCount >= 2) {
      rel.isBlocked = true;
      personalThreads[contactId]!.add(const Message("You're dead to me. Don't contact me again.", false));
      rel.unread = true;
      notifyListeners();
      return;
    }

    // Response planning (Phase 5): decide what KIND of reply this is before
    // searching for a specific line — see planResponse()'s own doc comment
    // for the priority order it applies. Spam/daily-repeat below stay a
    // separate pre-check rather than folding into the plan: piling onto the
    // same message twice isn't a conversational "kind of move" the way
    // answering a question or telling a joke is — it's Mama reacting to the
    // repetition itself, which is why it already short-circuited pool choice
    // before ResponseIntent existed, and still does.
    final questionJustAnswered = questionWasPending && resolved.answered;
    final topicJustChanged = previousTopic != null && rel.currentTopic != null && rel.currentTopic != previousTopic;
    final hasCallbackOpportunity = rel.recentConversation.any(
      (e) =>
          e.topic == rel.currentTopic &&
          e.turn < myTurn &&
          (e.importance == MemoryImportance.medium || e.importance == MemoryImportance.high),
    );
    final plan = planResponse(
      actionIntent: action.conversationIntent,
      questionJustAnswered: questionJustAnswered,
      questionJustAsked: action.intent == Intent.question,
      thread: rel.thread,
      topicJustChanged: topicJustChanged,
      hasCallbackOpportunity: hasCallbackOpportunity,
      contradiction: contradiction,
      rng: _rng,
    );
    rel.lastResponsePlan = plan;

    // Reaction pool priority:
    //   1. spamReactions      — same action sent back-to-back (≥2 times)
    //   2. dailyRepeatReactions — same action sent again later today (≥2 times, not consecutive)
    //   3. tone shift lines   — sudden register change the character calls out
    //   4. normal tone pool   — default per-tone reaction lines
    //
    // planResponse()'s ResponseIntent doesn't hard-narrow the pool the way
    // tone-shift does — unlike a tone shift (rare, always worth calling out),
    // ResponseIntent.answerQuestion fires on nearly every question-asking
    // turn, so hard-narrowing to only acknowledgesAnsweredQuestion-tagged
    // lines would exclude the entire existing, already-tuned pool of
    // question-answering content whenever a question is simply asked or
    // answered — a real regression caught by this session's own test suite.
    // It drives pickLine's scoring instead, via answeredQuestionMatch inside
    // _finalWeight (DialogueContext.questionJustAnswered below) — the same
    // soft-nudge treatment dodgeMatch/recallMatch already use for their own
    // equally-common signals; only a genuinely rare event like a tone shift
    // earns a hard override.
    //
    // Escalation: prolonged spam (≥5 back-to-back) irritates the character
    // enough that they stop replying to that message entirely. A mood hit is
    // still applied — ignoring someone costs the relationship — but no line
    // fires. The silence IS the reaction.
    final spamPool = kRelationshipContent[contactId]?.spamReactions ?? const [];
    final dailyPool = kRelationshipContent[contactId]?.dailyRepeatReactions ?? const [];
    final isConsecutiveSpam = rel.consecutiveActionCount >= 2 && spamPool.isNotEmpty;
    final isSpamSilenced = rel.consecutiveActionCount >= 7; // character stops replying entirely
    final isDailyRepeat = !isConsecutiveSpam && (rel.todayActionCounts[action.label] ?? 0) >= 2 && dailyPool.isNotEmpty;

    if (isSpamSilenced) {
      // A small extra mood penalty for being ignored — the relationship still
      // suffers even when no line fires.
      rel.mood = (rel.mood - 8).clamp(-100, 100);
      rel.daysSinceReply = 0;
      rel.unread = false;
      notifyListeners();
      return;
    }

    // Intent-specific reactions (Mama and Vale only, so far) slot in as a 4th
    // override tier, between the daily-repeat pool and the generic per-tone
    // pool — same priority-ladder pattern as spam/dailyRepeat above, not a
    // blend with the generic pool. Falls straight through to the generic
    // pool whenever the intent has no entries for the tone actually picked
    // (or the contact has no intent-reaction map at all yet), so a thin
    // intent bucket never dead-ends the reaction.
    final intentReactions = switch (contactId) {
      'mama' => kMamaIntentReactions,
      'partner' => kValeIntentReactions,
      _ => const <ConversationIntent, Map<ReplyTone, List<DialogueLine>>>{},
    };
    final intentPool = (!isConsecutiveSpam && !isDailyRepeat && action.conversationIntent != null)
        ? (intentReactions[action.conversationIntent]?[action.tone] ?? const <DialogueLine>[])
        : const <DialogueLine>[];

    // A contradiction is rare enough (unlike ResponseIntent.answerQuestion,
    // which fires on nearly every question-asking turn — see
    // answeredQuestionMatch's doc comment for why THAT one is a soft nudge,
    // not a pool override) that hard-routing to dedicated content when one
    // fires is safe: it can't crowd out an entire existing pool the way
    // over-eager narrowing did in Phase 5, since a fact contradiction only
    // exists at all when the player's own action establishes a fact that
    // conflicts with one already on record. Mama-only for now, same as
    // kMamaMoneyAskReactions — the reaction text is written in her voice.
    final contradictionPool = (contactId == 'mama' && !isConsecutiveSpam && !isDailyRepeat && plan.contradiction != null)
        ? (kMamaContradictionReactions[plan.intent] ?? const <DialogueLine>[])
        : const <DialogueLine>[];

    final List<DialogueLine>? reactionPool;
    if (isConsecutiveSpam) {
      reactionPool = spamPool;
    } else if (isDailyRepeat) {
      reactionPool = dailyPool;
    } else if (contradictionPool.isNotEmpty) {
      reactionPool = contradictionPool;
    } else if (intentPool.isNotEmpty) {
      reactionPool = intentPool;
    } else {
      reactionPool = kPersonalReactions[contactId]?[action.tone];
    }

    // Turn-granularity freshness/recall only apply to intent-chip-driven
    // turns — legacy PersonalReplyAction sends (every other contact, plus
    // any direct call with conversationIntent == null) keep the exact
    // day-granularity behavior they always had.
    final useTurnFreshness = action.conversationIntent != null;

    if (reactionPool != null) {
      // A sudden tone shift is something a real person would actually call
      // out, not just something that might statistically come up — when one
      // just happened, react only from the shift-acknowledging lines (still
      // varied, since a pool can carry more than one) instead of leaving it
      // to chance against the whole tone pool. Falls back to the full pool
      // if this tone happens to carry no shift-acknowledging lines.
      // (Tone-shift override is skipped during spam/repeat routing — the
      // character is already reacting to the repetition itself.)
      final shiftLines = (!isConsecutiveSpam && !isDailyRepeat && toneShifted)
          ? reactionPool.where((l) => l.acknowledgesToneShift).toList()
          : const <DialogueLine>[];
      final pool = shiftLines.isNotEmpty ? shiftLines : reactionPool;
      final ctx = DialogueContext(
        mood: rel.mood,
        closeness: rel.closeness,
        trust: rel.trust,
        suspicion: rel.suspicion,
        daysSinceReply: rel.daysSinceReply,
        recentTones: rel.recentTones,
        memories: rel.memories,
        timeOfDay: timeOfDay,
        isWeekend: isWeekend,
        currentTopic: rel.currentTopic,
        topicProgress: rel.topicProgress,
        playerTopics: action.topics,
        playerIntent: action.intent,
        questionJustDodged: dodgedNow,
        questionJustAnswered: questionJustAnswered,
        toneShift: toneShifted,
        playerTopicsToday: rel.topicsDiscussedToday,
        consecutiveActionCount: rel.consecutiveActionCount,
        levelPhase: turnPhase,
        recentConversation: rel.recentConversation,
        facts: rel.facts,
        honesty: rel.honesty,
        reliability: rel.reliability,
        responsiveness: rel.responsiveness,
      );
      final reaction = pickLine(
        _rng,
        pool,
        ctx,
        currentDay: day,
        lineLastUsedDay: rel.lineLastUsedDay,
        recentLineHistory: rel.recentLineHistory,
        currentTurn: useTurnFreshness ? myTurn : null,
        lineLastUsedTurn: useTurnFreshness ? rel.lineLastUsedTurn : const {},
      );
      if (reaction != null) {
        personalThreads[contactId]!.add(Message(reaction.text, false));
        rel.lastLine = reaction.text;
        recordLineUse(
          rel.lineLastUsedDay,
          rel.recentLineHistory,
          reaction,
          day,
          cap: useTurnFreshness ? 12 : 5,
          turn: useTurnFreshness ? myTurn : null,
          lineLastUsedTurn: useTurnFreshness ? rel.lineLastUsedTurn : null,
        );
        // Mama just asked something new — the player's next reply is what
        // resolves it (answered or dodged), so it isn't "answered" yet.
        if (reaction.intent == Intent.question) {
          rel.lastQuestionAnswered = false;
          _openPendingInteraction(rel, type: InteractionType.question, topic: reaction.topic, subject: reaction.subject);
        }
      } else {
        // Every line in `pool` got gated out for the current relationship
        // state — rather than silently sending nothing (indistinguishable
        // from a bug), fall back to a guaranteed-eligible "I don't know what
        // to say" line so the character always visibly responds to whatever
        // the player just said. See RelationshipContent.fallbackReactions.
        final fallbackPool = kRelationshipContent[contactId]?.fallbackReactions ?? const <DialogueLine>[];
        if (fallbackPool.isNotEmpty) {
          final fallback = pickLine(_rng, fallbackPool, ctx, currentDay: day) ?? fallbackPool.first;
          personalThreads[contactId]!.add(Message(fallback.text, false));
          rel.lastLine = fallback.text;
        }
      }
    }

    // How promptly this reply came, before the counter resets below — see
    // nudgeResponsiveness's doc comment for the <=1/>=3 thresholds.
    rel.responsiveness = nudgeResponsiveness(rel.responsiveness, rel.daysSinceReply);

    rel.daysSinceReply = 0;
    rel.unread = false;
    rel.followUpSent = false;
    notifyListeners();
  }

  /// Advances every personal relationship by one beat. Called whenever the
  /// player advances a day/cycle on the cartel side, so ignoring people has
  /// a cost even when you're not actively texting them.
  void _tickPersonalRelationships() {
    _relationshipTickCount += 1;
    // Morning tick — a new game-day is starting: clear per-day memory so each
    // "day" of in-game conversation gets a fresh slate for repeat detection.
    if (timeOfDay == TimeOfDay.morning) {
      for (final p in kPersonalContacts) {
        final rel = relationships[p.id];
        if (rel == null) continue;
        rel.todayActionCounts.clear();
        rel.topicsDiscussedToday.clear();
        _pruneConversationMemory(rel); // ages out low/medium-importance conversation events even on a day the player never opens this thread
      }
    }
    for (final p in kPersonalContacts) {
      final rel = relationships[p.id]!;
      if (rel.goneQuiet || rel.resolved || rel.isBlocked) continue;
      final content = kRelationshipContent[p.id]!;
      final thread = personalThreads[p.id]!;
      final awaitingReply = thread.isNotEmpty && !thread.last.fromMe;

      // Sustained warmth/coldness from the player gradually shifts the
      // character's emotional baseline — a long-neglected mama becomes
      // quicker to worry; one consistently treated well settles a bit
      // warmer. The offset is capped at ±15 so it never fully overrides
      // personality, and it drifts at 0.3/tick so it takes many turns to move.
      if (rel.recentTones.length >= 3) {
        final warmCount = rel.recentTones.where((t) => t == ReplyTone.warm).length;
        final coldCount = rel.recentTones.where((t) => t == ReplyTone.cold || t == ReplyTone.excuse).length;
        if (warmCount >= 3) rel.warmthOffset = (rel.warmthOffset + 0.3).clamp(-15, 15);
        if (coldCount >= 3) rel.warmthOffset = (rel.warmthOffset - 0.3).clamp(-15, 15);
        // Behavioral reputation (Phase 9): honesty, same mechanism/cadence
        // as warmthOffset just above — a sustained pattern in
        // recentTones, not a single turn. See nudgeHonesty's doc comment
        // for why this deliberately mirrors warmthOffset instead of
        // introducing a second, competing definition of "repeated".
        final honestCount = rel.recentTones.where((t) => t == ReplyTone.honest).length;
        rel.honesty = nudgeHonesty(rel.honesty, honestCount);
      }
      rel.mood = decayMood(rel.mood, baselineAttraction: baselineAttraction(p.personalityWarmth + rel.warmthOffset));
      rel.fear = decayMood(rel.fear);

      if (awaitingReply) {
        rel.daysSinceReply += 1;
        if (rel.daysSinceReply >= 3) {
          rel.suspicion = (rel.suspicion + 5 * p.suspicionRate).clamp(0, 100);
          rel.trust = (rel.trust - 2).clamp(0, 100);
        }
        if (rel.daysSinceReply == 3 && !rel.followUpSent) {
          final ctx = DialogueContext(
            mood: rel.mood,
            closeness: rel.closeness,
            trust: rel.trust,
            suspicion: rel.suspicion,
            daysSinceReply: rel.daysSinceReply,
            recentTones: rel.recentTones,
            memories: rel.memories,
            timeOfDay: timeOfDay,
            isWeekend: isWeekend,
          );
          final line = pickLine(
            _rng,
            content.followUp,
            ctx,
            currentDay: day,
            lineLastUsedDay: rel.lineLastUsedDay,
            recentLineHistory: rel.recentLineHistory,
          ) ?? content.followUp.first;
          thread.add(Message(line.text, false));
          recordLineUse(rel.lineLastUsedDay, rel.recentLineHistory, line, day);
          rel.followUpSent = true;
          rel.unread = true;
        }
      }

      if (rel.trust <= 0) {
        rel.goneQuiet = true;
        final ctx = DialogueContext(
          mood: rel.mood,
          closeness: rel.closeness,
          trust: rel.trust,
          suspicion: rel.suspicion,
          daysSinceReply: rel.daysSinceReply,
          recentTones: rel.recentTones,
          memories: rel.memories,
          timeOfDay: timeOfDay,
          isWeekend: isWeekend,
        );
        final line = pickLine(_rng, content.goneQuietLine, ctx, currentDay: day) ?? content.goneQuietLine.first;
        thread.add(Message(line.text, false));
        continue;
      }
      if (rel.suspicion >= 100) {
        rel.resolved = true;
        final ctx = DialogueContext(
          mood: rel.mood,
          closeness: rel.closeness,
          trust: rel.trust,
          suspicion: rel.suspicion,
          daysSinceReply: rel.daysSinceReply,
          recentTones: rel.recentTones,
          memories: rel.memories,
          timeOfDay: timeOfDay,
          isWeekend: isWeekend,
        );
        final line = pickLine(_rng, content.confrontation, ctx, currentDay: day) ?? content.confrontation.first;
        thread.add(Message(line.text, false));
        rel.unread = true;
        _echoToLinkedContact(p.id, MemoryKind.heardAboutConfrontation);
        continue;
      }
      if (!awaitingReply) {
        final chance = effectiveInitiative(p.initiative, rel.mood, p.moodSensitivity, trust: rel.trust, closeness: rel.closeness);
        if (_rng.nextDouble() < chance) {
          final pool = rel.suspicion >= 80
              ? content.distant
              : rel.suspicion >= 60
                  ? content.questioning
                  : content.openers;
          final ctx = DialogueContext(
            mood: rel.mood,
            closeness: rel.closeness,
            trust: rel.trust,
            suspicion: rel.suspicion,
            daysSinceReply: rel.daysSinceReply,
            recentTones: rel.recentTones,
            memories: rel.memories,
            timeOfDay: timeOfDay,
            isWeekend: isWeekend,
            currentTopic: rel.currentTopic,
            topicProgress: rel.topicProgress,
            playerTopicsToday: rel.topicsDiscussedToday,
          );
          final line = pickLine(
            _rng,
            pool,
            ctx,
            currentDay: day,
            lineLastUsedDay: rel.lineLastUsedDay,
            recentLineHistory: rel.recentLineHistory,
          );
          if (line != null) {
            thread.add(Message(line.text, false));
            rel.lastLine = line.text;
            rel.unread = true;
            recordLineUse(rel.lineLastUsedDay, rel.recentLineHistory, line, day);
            // Mama raising a topic starts (or continues) a thread the
            // player's next reply can build on — see advanceTopic(). A
            // generic, untagged line leaves whatever thread was already
            // active alone. Always a fresh stage-1 start rather than routing
            // through advanceTopic() itself — Mama raising something
            // unprompted is always a new beat, never a deepening of turns the
            // player didn't just contribute to.
            if (line.topic != null) {
              rel.currentTopic = line.topic;
              rel.topicProgress = 1;
              rel.topicSubject = line.resolvesThread ? null : line.subject;
              rel.topicUnresolved = !line.resolvesThread;
              rel.topicTurnsActive = 1;
            }
            // Same as the reaction path: mama asking something unprompted
            // leaves it awaiting the player's reply.
            if (line.intent == Intent.question) {
              rel.lastQuestionAnswered = false;
              _openPendingInteraction(rel, type: InteractionType.question, topic: line.topic, subject: line.subject);
            }
          }
        }
      }
    }
    _maybeBossNotices();
  }

  /// Word gets around, one hop: whoever's linked to [id] (see
  /// kRelationshipLinks) hears about a notable event secondhand — a smaller
  /// mood hit than living it directly, but enough to notice. No-ops if [id]
  /// has no link, or the linked contact's storyline has already concluded.
  void _echoToLinkedContact(String id, MemoryKind kind, {double moodDelta = -10}) {
    final linkedId = kRelationshipLinks[id];
    final linkedRel = linkedId == null ? null : relationships[linkedId];
    if (linkedRel != null && !linkedRel.goneQuiet && !linkedRel.resolved && !linkedRel.isBlocked) {
      linkedRel.mood = (linkedRel.mood + moodDelta).clamp(-100, 100);
      recordMemory(linkedRel.memories, MemoryEvent(kind, day), once: true);
    }
  }

  void _maybeBossNotices() {
    if (level < 4 || attachmentWarningContactId != null) return;
    for (final p in kPersonalContacts) {
      final rel = relationships[p.id]!;
      if (rel.closeness >= 80 && !rel.flaggedByBoss && _rng.nextDouble() < 0.5) {
        attachmentWarningContactId = p.id;
        rel.flaggedByBoss = true;
        return;
      }
    }
  }

  void resolveAttachmentWarning(String choice) {
    final id = attachmentWarningContactId;
    if (id == null) return;
    final rel = relationships[id]!;
    if (choice == 'cut_off') {
      rel.closeness = (rel.closeness - 40).clamp(0, 100);
      rel.trust = (rel.trust - 20).clamp(0, 100);
      // The contact only has a way to notice something changed on their end
      // — reassure/ignore both resolve the boss's suspicion without ever
      // touching this relationship, so only cut_off earns a memory here.
      recordMemory(rel.memories, MemoryEvent(MemoryKind.cutOff, day), once: true);
      _echoToLinkedContact(id, MemoryKind.heardAboutCutOff);
    } else if (choice == 'reassure') {
      final cost = max(1000, (cash * 0.05).round());
      if (cash < cost) return;
      cash -= cost;
      cartelSuspicion = _clamp01to100(cartelSuspicion + 5);
    } else {
      cartelSuspicion = _clamp01to100(cartelSuspicion + 15);
    }
    attachmentWarningContactId = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _sightingTimer?.cancel();
    super.dispose();
  }
}

/// Inherited access to the controller.
class AppScope extends InheritedNotifier<CareerController> {
  const AppScope({super.key, required CareerController controller, required super.child})
      : super(notifier: controller);

  static CareerController of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'AppScope not found in widget tree');
    return scope!.notifier!;
  }
}
