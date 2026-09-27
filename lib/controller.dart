import 'dart:async';
import 'dart:math';
import 'package:flutter/widgets.dart' hide Intent;
import 'content/mama_reactions.dart';
import 'content/vale_reactions.dart';
import 'conversation/intents.dart';
import 'conversation/reply_tray.dart';
import 'conversation/vale_intents.dart';
import 'data.dart';
import 'theme.dart' show money;

double _clamp01to100(double v) => v.clamp(0, 100).toDouble();

/// Where a Level 2 checkpoint stop is in its own mini state machine —
/// see [CareerController.checkpointPhase].
enum CheckpointPhase { gather, approach, inspection, result }

/// Picks the crew name that flavors every rival-pressure event for the run.
String _pickRivalCrewName(Random rng) => kRivalCrewNames[rng.nextInt(kRivalCrewNames.length)];

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
  // before promotion. This is the real sim's pacing (weeks and months of
  // grind, not a handful of actions). Danger/lethality tuning (strikes,
  // catch odds, etc.) is untouched — this only controls how long each level
  // takes to clear.
  // ══════════════════════════════════════════════════════════════════════
  static const int kCleanWeeksToPromote = 2;
  static const int kRunsPerTransporterWeek = 6;
  static const int kTransporterWeeksToPromote = 2;
  static const int kSuccessfulRunsToPromote = kRunsPerTransporterWeek * kTransporterWeeksToPromote;
  static const int kCollectorWeeksToPromote = 3;
  static const int kMonthsAsLeaderToPromote = 4;
  static const int kStrategicGoodCyclesToPromote = 4;
  static const int kStrategicCyclesToPromote = 4;

  // A rival crew's hostility — separate from police heat / cartel suspicion,
  // this is a third pressure track that a specific named crew builds against
  // you across the whole run (see kRivalCrewNames in data.dart).
  static const double kRivalWarningThreshold = 60.0;
  static const double kRivalLethalThreshold = 95.0;
  static const double kRivalDeathOdds = 0.35;

  // ── shared state ──
  int day = 1;
  int level = 1;
  int cash = 0;
  int cleanBalance = 0;
  double policeHeat = 0;
  double cartelSuspicion = 0;
  double rivalPressure = 0;
  late String rivalCrewName;
  String? pendingRivalWarning;

  // Chosen once, at the Level 3->4 promotion fork (see acceptPromotion) —
  // deliberately not reset in restart(): dying past Level 4 restarts you at
  // that level with the path you already picked, and dying before Level 4
  // correctly leaves this null until you reach the fork again.
  String? careerPath;
  double get _pathIncomeMultiplier => careerPath == 'boss' ? 1.15 : 1.0;

  // Legacy — tracked across every career this session, never reset by
  // restart() or devJumpToLevel(). See startNewCareer().
  int legacyRuns = 0;
  int peakLevelEver = 1;
  double get _pathNegotiationCostMultiplier =>
      careerPath == 'fixer' ? 0.5 : (careerPath == 'muscle' ? 1.5 : 1.0);

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
  bool fieldGuideSeen = false; // per app session — the one-time vehicle silhouette field guide, shown before the first Level 1 shift

  // The side hustle's minigame pick — set by [startSideHustle], consumed by
  // whichever screen pushes the matching game, resolved by [resolveSideHustle].
  SideHustleGameKind? pendingSideHustleGame;
  SideHustleGameKind? _lastSideHustleGame; // avoid immediately repeating the same minigame

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
        // cleanWeeks only moves once every 7 days — fold in how far the
        // *current* week has gotten so the bar advances after every clean
        // day instead of sitting still for most of a week. Voided the
        // moment a strike lands this week, since that week won't count.
        final daysIntoWeek = (day - 1) % 7;
        final weekFraction = weeklyStrikeOccurred ? 0.0 : daysIntoWeek / 7;
        return ((cleanWeeks + weekFraction) / kCleanWeeksToPromote).clamp(0, 1);
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
        return '${successfulRuns ~/ kRunsPerTransporterWeek}/$kTransporterWeeksToPromote weeks clean';
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
  static const int sightingsPerDay = 3; // no longer gates the day boundary — kept as a display counter only
  static const int responseWindowSeconds = 15;
  static const int sightingGapSeconds = 5; // quiet road between sightings
  static const int dayDurationSeconds = 300; // a shift is 5 real minutes, start to end
  int strikes = 0;
  Sighting? sighting;
  bool sightingHandled = false;
  bool weeklyStrikeOccurred = false;
  int cleanWeeks = 0;
  String? lastWarning;
  int sightingsToday = 0;
  int secondsRemaining = responseWindowSeconds;
  int sightingSeq = 0; // bumped on every roll, even if the pool repeats an entry
  bool dayStarted = false; // player must tap "Start shift" before sightings roll
  bool _dayTimeUp = false; // the 5-minute shift clock ran out — day ends once the current sighting (if any) resolves
  int daySecondsRemaining = dayDurationSeconds;
  Timer? _sightingTimer;
  Timer? _sightingGapTimer;
  Timer? _dayTimer;

  // ── Level 2: Transporter ──
  int? runStage;
  double runRisk = 0;
  int successfulRuns = 0;
  RunOutcome? lastRunOutcome;
  // Which CheckpointScenario is in play at each checkpoint this run — rolled
  // fresh in [beginRun] so the tell (and which approach/response it favors)
  // changes run to run instead of the scene always reading the same way.
  List<int> _runVariantIdx = [];
  CheckpointPhase checkpointPhase = CheckpointPhase.gather;
  bool observedThisStop = false;
  bool checkedVehicleThisStop = false;
  int suspicion = 0; // 0..5, resets every checkpoint
  String? checkpointHeadline; // 'CLEAR' | 'SECONDARY INSPECTION' | 'CHECKPOINT FAILED'
  String? checkpointBody;
  // Rolled once per run (or forced by [prepVehicleReady]) — shared by all 3
  // stops, since it's the same truck all the way to the crossing.
  bool runConcealmentGood = true;
  // Pre-run prep, bought while idle and consumed the instant a run starts —
  // see [prepCleanDocuments] / [prepVehicle].
  bool prepDocsClean = false;
  bool prepVehicleReady = false;
  bool _activeDocsClean = false;
  static const int kPrepDocsCost = 150;
  static const int kPrepVehicleCost = 200;
  // Per-checkpoint-index memory of the last scenario seen there, so a
  // repeat (or a shift change) can be called out instead of read as new —
  // cleared whenever the level restarts (see [_initLevel2]).
  final Map<int, String> _lastCheckpointHook = {};

  /// The scenario on offer at the current stop. Only valid while a run is
  /// active ([runStage] non-null).
  CheckpointScenario get currentScenario => kCheckpoints[runStage!].scenarios[_runVariantIdx[runStage!]];

  String get vehicleRevealText => runConcealmentGood ? kVehicleRevealGood : kVehicleRevealBad;

  /// Non-null only right after landing on a stop whose scenario hook matches
  /// what was seen at this same checkpoint index last run.
  String? get checkpointMemoryLine {
    if (runStage == null) return null;
    final scenario = currentScenario;
    if (_lastCheckpointHook[runStage!] != scenario.memoryHook) return null;
    return scenario.memoryRepeatLine;
  }

  // ── Level 3: Collector ──
  static const int collectorGapSeconds = 4; // travel time between stops
  // The night's time budget. Every action on the route spends some of it —
  // it doesn't tick on its own, so the player only ever loses time by
  // choosing where to spend it (chase a stubborn payer, or move on).
  static const int routeSeconds = 180;
  static const int visitSeconds = 20;
  static const int threatenSeconds = 35;
  static const int vandalizeSeconds = 50;
  static const int sideHustleSeconds = 30;
  int routeSecondsLeft = routeSeconds;
  int routeBudget = routeSeconds; // this night's total — shorter after a poor week
  int routePenaltySeconds = 0; // carried from a poor week into the next night
  static const int kPoorWeekTimePenalty = 20;
  static const double kPartialWeekRatio = 0.6; // collected/expected that still counts as "close"
  int collectorShortWeeks = 0; // short weeks this level — the boss remembers, into the next level

  // Rolls and the word going around — see [visitOdds] / [threatenOdds].
  static const double kVisitBaseOdds = 0.55;
  static const double kThreatenBaseOdds = 0.45;
  static const double kOnEdgeVisitPenalty = 0.15;
  static const double kOnEdgeThreatenBonus = 0.15;
  static const double kWatchedVisitPenalty = 0.10;
  // Targets who've heard what happened at an earlier stop — harder to talk
  // round, easier to scare. Cleared every night.
  final Set<String> targetOnEdge = {};
  // Targets an action has been taken on tonight. A rival-watched target
  // that's never touched is one the player left alone.
  final Set<String> targetTouched = {};
  int routeActions = 0;

  // The rival crew's hold on a watched target.
  static const double kWatchedActionPressure = 5; // every action taken on one
  static const double kIgnoredWatchRelief = 8; // leaving one alone all night

  // Call in a favour — one per Level 3, not per night.
  static const double kFavourSuspicion = 15;
  bool favourUsed = false;

  // The night's single curveball: null | 'police' | 'rival'.
  static const int kLayLowSeconds = 40;
  static const double kLayLowHeatRelief = 15;
  static const double kKeepGoingHeat = 10;
  static const int kConfrontSeconds = 20;
  String? pendingCurveball;
  String? curveballTargetId; // the target the rival crew is working (rival curveball only)
  bool curveballFired = false;
  int _curveballAfter = 2; // route actions in before it lands
  final Map<String, int> collected = {};
  final Map<String, String> targetState = {}; // pending | resisting | refused | paid | lost | missed
  final Map<String, String> targetExcuse = {};
  int collectorWeeks = 0;
  bool collectorBusy = false; // traveling between stops — no action can be taken
  // Set the instant the UI starts an action's suspense beat, before the
  // real roll happens — kept separate from [collectorBusy] (the travel-time
  // gap that only starts once a roll resolves) so the two locks don't
  // stomp on each other.
  bool actionInFlight = false;
  Timer? _collectorGapTimer;
  // Set by [reportToBoss] when the week closes short — held just long enough
  // for the UI to pop up and tell the player the gap came out of their own
  // pocket, instead of that happening silently.
  String? shortfallNotice;
  // Consecutive clean weeks each target has been paid in full — a pattern
  // the rival crew can notice (see [_maybeTriggerFactionNotice]), so paying
  // a target reliably isn't a free action forever.
  final Map<String, int> targetPaidStreak = {};
  // Targets the rival crew has muscled in on — permanently skims a cut of
  // what they pay from then on (see [effectiveOwed]), a small persistent
  // scar on the world from how the player played earlier weeks.
  final Set<String> targetUnderRivalWatch = {};
  static const int kFactionNoticeStreak = 2;
  static const double kFactionCutFraction = 0.3; // the rival's skim once they've noticed

  // ── Level 4: Cell Leader ──
  static const int level4GapSeconds = 5; // settling time after closing a month or a crisis
  int stashKg = 100;
  final Map<String, int> allocated = {};
  List<String> crewNames = [];
  final Map<String, double> crewLoyalty = {};
  int monthsAsLeader = 0;
  int lastMonthTake = 0;
  int shortMonths = 0;
  String? pendingIncursion;
  String? pendingTrouble; // crew member name with trouble
  bool level4Busy = false;
  Timer? _level4GapTimer;

  // Per-distributor relationship state — keyed by Distributor.id, so adding
  // a new entry to kDistributors picks up all of this for free. Trust drifts
  // from how well each month's order was met (see [_resolveDelivery]);
  // demandBonus is the running drift on top of Distributor.baseDemandKg.
  final Map<String, double> distributorTrust = {}; // 0..1, starts at 0.6
  final Map<String, int> distributorDemandBonus = {};
  final Map<String, int> distributorLowTrustStreak = {}; // consecutive months below the "losing them" threshold
  final Set<String> distributorLostToRival = {}; // chain-reaction end state — see _resolveDelivery

  // This month's decision point (see kMonthlySituations) — rolled fresh by
  // [_rollMonthlySituation] every time a month opens. [currentSituationChoiceId]
  // is null until the player picks an option; closing the month with nothing
  // picked auto-applies the template's last ("ignore") option instead of
  // silently skipping it.
  MonthlySituationTemplate? currentSituation;
  String? currentSituationFocusId; // distributor id, only set when the template needs one
  String? currentSituationChoiceId;
  String? _lastSituationId; // avoids immediately repeating the same template
  MonthResolution? lastResolution; // most recent month's payoff card — see closeMonth()

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
  bool strategicBusy = false;
  Timer? _strategicGapTimer;
  // The higher up the pyramid, the longer a cycle takes to settle.
  int get strategicGapSeconds => level == 5 ? 5 : (level == 6 ? 6 : 7);

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
    rivalCrewName = _pickRivalCrewName(_rng);
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
    if (rivalPressure >= kRivalLethalThreshold && _rng.nextDouble() < kRivalDeathOdds) {
      _die('$rivalCrewName found you before the cops ever needed to.');
      return true;
    }
    _maybeTriggerRivalWarning();
    return false;
  }

  /// Once rival pressure climbs high enough, an informant tip lands in the
  /// handler thread and the player gets a forced choice on how to answer it
  /// (see [resolveRivalWarning]) — same request/resolve shape as the boss's
  /// attachment warning, just for a different pressure track.
  void _maybeTriggerRivalWarning() {
    if (rivalPressure < kRivalWarningThreshold || pendingRivalWarning != null) return;
    pendingRivalWarning = '$rivalCrewName know your name now. Word is they\'re deciding what to do about it.';
    _announce('handler', 'Heard $rivalCrewName has been asking questions about you. Watch yourself.');
  }

  void resolveRivalWarning(String choice) {
    if (pendingRivalWarning == null) return;
    switch (choice) {
      case 'pay':
        final cost = max(1000, (cash * 0.1).round());
        if (cash < cost) return;
        cash -= cost;
        rivalPressure = _clamp01to100(rivalPressure - 30);
        break;
      case 'retaliate':
        cash = (cash - 500).clamp(0, 1 << 30);
        policeHeat = _clamp01to100(policeHeat + 10);
        cartelSuspicion = _clamp01to100(cartelSuspicion + 5);
        rivalPressure = _clamp01to100(rivalPressure - 20);
        break;
      default: // 'ignore'
        break;
    }
    pendingRivalWarning = null;
    notifyListeners();
  }

  /// Proactive defuse: pay a slice of cash on hand to bring rival pressure
  /// down before it ever reaches a forced warning.
  void payOffRival() {
    if (rivalPressure <= 0) return;
    final cost = max(1000, (cash * 0.08).round());
    if (cash < cost) return;
    cash -= cost;
    rivalPressure = _clamp01to100(rivalPressure - 25);
    cartelSuspicion = _clamp01to100(cartelSuspicion + 2);
    notifyListeners();
  }

  /// Always on offer, any time the player isn't dead — never gated to a
  /// level's pacing gaps or limited to once per cycle. The card should never
  /// just vanish on the player.
  bool get sideHustleAvailable => !gameOver;

  /// On the Level 3 route a side hustle costs [sideHustleSeconds] of the
  /// night, so it can be on offer but out of reach once time runs low.
  bool get sideHustleAffordable => level != 3 || routeSecondsLeft >= sideHustleSeconds;

  /// Opens a side hustle once per waiting window — turns the pacing gaps
  /// into a small skill-based minigame instead of dead air. Picks a kind
  /// different from whichever ran last time so the same game doesn't show
  /// up twice in a row. The UI reads [pendingSideHustleGame] to know which
  /// screen to push; the actual win/lose call is made by the player's play
  /// in that screen, then reported back via [resolveSideHustle].
  void startSideHustle() {
    if (!sideHustleAvailable || !sideHustleAffordable) return;
    if (level == 3) routeSecondsLeft -= sideHustleSeconds;
    const kinds = SideHustleGameKind.values;
    var kind = kinds[_rng.nextInt(kinds.length)];
    if (kinds.length > 1) {
      while (kind == _lastSideHustleGame) {
        kind = kinds[_rng.nextInt(kinds.length)];
      }
    }
    pendingSideHustleGame = kind;
    notifyListeners();
  }

  /// Reports the outcome of whichever minigame [startSideHustle] opened. A
  /// win pays this level's side-hustle rate; a loss costs a smaller, scaled
  /// amount and a small heat bump — unlike every other cash deduction in the
  /// game, this loss is allowed to push [cash] negative.
  void resolveSideHustle(bool won) {
    if (pendingSideHustleGame == null) return;
    _lastSideHustleGame = pendingSideHustleGame;
    pendingSideHustleGame = null;
    if (won) {
      cash += kSideHustlePayout[level] ?? 0;
    } else {
      cash -= kSideHustleLossPayout[level] ?? 0;
      policeHeat = _clamp01to100(policeHeat + 6);
      // At Level 4 a botched side hustle also puts a little heat on rivals
      // watching your corner — everywhere else this stays a pure police risk.
      if (level == 4) rivalPressure = _clamp01to100(rivalPressure + 3);
    }
    notifyListeners();
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
    if (lvl > peakLevelEver) peakLevelEver = lvl;
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

  void markFieldGuideSeen() {
    if (fieldGuideSeen) return;
    fieldGuideSeen = true;
    notifyListeners();
  }

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
    rivalPressure = 0;
    rivalCrewName = _pickRivalCrewName(_rng);
    pendingRivalWarning = null;
    pendingSideHustleGame = null;
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

  /// Retires the current career and starts a brand new one from Level 1.
  /// Unlike [restart] (same level, after a death — a "retry"), this is a
  /// deliberate choice to go again, and it's the only place a legacy perk
  /// carries forward: legacyRuns/peakLevelEver are never reset by restart().
  void startNewCareer() {
    legacyRuns += 1;
    level = 1;
    restart(); // full state reset + _reinitLevel(1)
    cash = 100 * legacyRuns; // deliberately minor — flavor, not a head start
    _announce('handler', 'Word travels. This isn\'t your first rodeo — that\'s worth something.');
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

  void acceptPromotion({String? path}) {
    if (!promotionAvailable) return;
    if (level == 3 && path != null) careerPath = path;
    // Every short week on the route follows you up — the new boss has heard.
    if (level == 3) cartelSuspicion = _clamp01to100(cartelSuspicion + promotionCarryOver);
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
    _sightingGapTimer?.cancel();
    _collectorGapTimer?.cancel();
    _level4GapTimer?.cancel();
    _strategicGapTimer?.cancel();
    _dayTimer?.cancel();
    level = 1;
    strikes = 0;
    cleanWeeks = 0;
    weeklyStrikeOccurred = false;
    lastWarning = null;
    sightingsToday = 0;
    sighting = null;
    sightingHandled = false;
    dayStarted = false;
    _dayTimeUp = false;
    daySecondsRemaining = dayDurationSeconds;
  }

  /// Player-initiated: the plaza is quiet until they tap in for the day.
  /// Rolls the first sighting and starts both the response-window timer and
  /// the 5-minute shift clock.
  void startShift() {
    if (level != 1 || dayStarted) return;
    dayStarted = true;
    _dayTimeUp = false;
    sighting = _rollSighting();
    sightingSeq += 1;
    sightingHandled = false;
    _startSightingTimer();
    _startDayTimer();
    notifyListeners();
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

  // A shift is 5 real minutes, independent of how many sightings roll through
  // it. Firing this doesn't cut off a sighting mid-response-window — it just
  // flags the shift as due to end; _resolveSighting (and the gap-timer
  // callback, if the clock runs out during the quiet stretch between
  // sightings) actually close the day out once nothing's left pending.
  void _startDayTimer() {
    _dayTimer?.cancel();
    daySecondsRemaining = dayDurationSeconds;
    _dayTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      daySecondsRemaining -= 1;
      if (daySecondsRemaining <= 0) {
        timer.cancel();
        _dayTimeUp = true;
        if (sighting == null) {
          _endShiftIfIdle(); // notifies on its own
          return;
        }
      }
      notifyListeners();
    });
  }

  /// Closes out the day from the quiet gap between sightings (no sighting
  /// pending) once the shift clock has run out. Mirrors the tail end of
  /// _resolveSighting for the case where the clock expires while waiting,
  /// rather than while a sighting is on screen.
  void _endShiftIfIdle() {
    if (!_dayTimeUp || sighting != null) return;
    _sightingGapTimer?.cancel();
    _dayTimer?.cancel();
    _dayTimeUp = false;
    dayStarted = false;
    _advanceDay(); // may end the game via _die, which notifies on its own
    notifyListeners();
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
      if (sighting!.kind == SightingKind.rival) {
        rivalPressure = _clamp01to100(rivalPressure + 8);
      }
      _strike(wrongReason);
      if (gameOver) return;
    }
    unread = true;
    sightingsToday += 1; // display-only tally now — the shift clock, not a sighting count, ends the day

    // The road sits quiet for a stretch before the next thing worth reporting rolls by.
    sighting = null;

    if (_dayTimeUp) {
      // The shift clock already ran out while this last sighting was still
      // pending — close the day out now instead of rolling the gap timer.
      sightingsToday = 0;
      _dayTimeUp = false;
      dayStarted = false;
      _dayTimer?.cancel();
      _advanceDay(); // may end the game via _die, which notifies on its own
      notifyListeners();
      return;
    }

    notifyListeners();
    _sightingGapTimer?.cancel();
    _sightingGapTimer = Timer(const Duration(seconds: sightingGapSeconds), () {
      if (_dayTimeUp) {
        sightingsToday = 0;
        _endShiftIfIdle(); // notifies on its own
        return;
      }
      sighting = _rollSighting();
      sightingSeq += 1;
      sightingHandled = false;
      _startSightingTimer();
      notifyListeners();
    });
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
    _sightingGapTimer?.cancel();
    _collectorGapTimer?.cancel();
    _level4GapTimer?.cancel();
    _strategicGapTimer?.cancel();
    _dayTimer?.cancel();
    level = 2;
    runStage = null;
    runRisk = 0;
    successfulRuns = 0;
    lastWarning = null;
    lastRunOutcome = null;
    _runVariantIdx = [];
    prepDocsClean = false;
    prepVehicleReady = false;
    _lastCheckpointHook.clear();
    _announce('handler', 'New job. Get the product across. Eight hours, don\'t stop for anyone.');
  }

  /// Bought while idle between runs, consumed the instant [beginRun] starts
  /// the next one — see [_activeDocsClean] / [runConcealmentGood].
  void prepCleanDocuments() {
    if (level != 2 || runStage != null || prepDocsClean || cash < kPrepDocsCost) return;
    cash -= kPrepDocsCost;
    prepDocsClean = true;
    notifyListeners();
  }

  void prepVehicle() {
    if (level != 2 || runStage != null || prepVehicleReady || cash < kPrepVehicleCost) return;
    cash -= kPrepVehicleCost;
    prepVehicleReady = true;
    notifyListeners();
  }

  void beginRun() {
    if (level != 2 || runStage != null) return;
    runStage = 0;
    runRisk = 0.05;
    lastWarning = null;
    lastRunOutcome = null;
    _runVariantIdx = [for (final cp in kCheckpoints) _rng.nextInt(cp.scenarios.length)];
    _activeDocsClean = prepDocsClean;
    runConcealmentGood = prepVehicleReady || _rng.nextDouble() < 0.7;
    prepDocsClean = false;
    prepVehicleReady = false;
    _beginCheckpointGather();
    notifyListeners();
  }

  void _beginCheckpointGather() {
    checkpointPhase = CheckpointPhase.gather;
    observedThisStop = false;
    checkedVehicleThisStop = false;
    suspicion = 0;
    checkpointHeadline = null;
    checkpointBody = null;
  }

  /// Reveals [CheckpointScenario.observeReveal] — a free but not-quite-free
  /// look: the same small risk nudge as [checkVehicle], for lingering at
  /// the checkpoint instead of just driving up to it.
  void observeCheckpoint() {
    if (level != 2 || runStage == null || checkpointPhase != CheckpointPhase.gather || observedThisStop) return;
    observedThisStop = true;
    runRisk += 0.01;
    notifyListeners();
  }

  void checkVehicle() {
    if (level != 2 || runStage == null || checkpointPhase != CheckpointPhase.gather || checkedVehicleThisStop) return;
    checkedVehicleThisStop = true;
    runRisk += 0.01;
    notifyListeners();
  }

  /// CONTINUE — skip whatever information wasn't already gathered and move
  /// straight to picking an approach.
  void proceedToApproach() {
    if (level != 2 || runStage == null || checkpointPhase != CheckpointPhase.gather) return;
    checkpointPhase = CheckpointPhase.approach;
    notifyListeners();
  }

  /// Commits to [approach] for the current stop. Its own risk/heat apply
  /// immediately; if it doesn't skip the inspection outright, whether one
  /// actually happens is rolled from [CheckpointApproach.baseInspectionChance]
  /// nudged by the scenario's [CheckpointKind].
  void chooseApproach(CheckpointApproach approach) {
    if (level != 2 || runStage == null || checkpointPhase != CheckpointPhase.approach) return;
    if (cash < approach.cost) return;
    final checkpoint = kCheckpoints[runStage!];
    if (approach.cost > 0) {
      cash -= approach.cost;
      recentStoryEvent = 'bribed';
    }
    // Reading the scenario's tell right and picking the approach it favors
    // earns a discount on top of whatever the approach already offers — the
    // only reward for paying attention, no cash required.
    final matchedTell = checkpoint.approaches.indexOf(approach) == currentScenario.favoredApproachIndex;
    runRisk += matchedTell ? approach.riskDelta * 0.5 : approach.riskDelta;
    if (approach.heatDelta > 0) rivalPressure = _clamp01to100(rivalPressure + approach.heatDelta);
    if (approach.skipsInspection) {
      _resolveCheckpointClear();
      notifyListeners();
      return;
    }
    final kindBump = switch (currentScenario.kind) {
      CheckpointKind.heightened => 0.25,
      CheckpointKind.trap => 0.15,
      CheckpointKind.unusual => 0.10,
      CheckpointKind.routine => 0.0,
    };
    final chance = (approach.baseInspectionChance + kindBump).clamp(0.0, 1.0);
    if (_rng.nextDouble() < chance) {
      checkpointPhase = CheckpointPhase.inspection;
    } else {
      _resolveCheckpointClear();
    }
    notifyListeners();
  }

  /// Answers the officer's question during an inspection sub-scene. How
  /// [response] plays depends on whether it matches the scenario's favored
  /// response, the run's concealment roll, and how tense this stop already
  /// is — not on the label alone, so there's no single "correct" tap.
  void respondToInspection(InspectionResponse response) {
    if (level != 2 || runStage == null || checkpointPhase != CheckpointPhase.inspection) return;
    final checkpoint = kCheckpoints[runStage!];
    final scenario = currentScenario;
    final matchedTell = checkpoint.responses.indexOf(response) == scenario.favoredResponseIndex;
    final kindBump = (scenario.kind == CheckpointKind.heightened || scenario.kind == CheckpointKind.trap) ? 1 : 0;
    final concealmentMod = runConcealmentGood ? -1 : 1;
    suspicion = (response.suspicionDelta + (matchedTell ? -2 : 0) + concealmentMod + kindBump + (_activeDocsClean ? -1 : 0))
        .clamp(0, 5);
    if (suspicion < 3) {
      _resolveCheckpointClear();
      notifyListeners();
      return;
    }
    runRisk += 0.15;
    policeHeat = _clamp01to100(policeHeat + 3);
    checkpointPhase = CheckpointPhase.result;
    if (suspicion >= 5 && _rng.nextDouble() < 0.4) {
      checkpointHeadline = 'CHECKPOINT FAILED';
      checkpointBody = 'They pulled the truck apart right there.';
      runRisk = 0.95; // the end-of-run roll still clamps to 0.85 — a sliver of a chance, same as any other run
    } else {
      checkpointHeadline = 'SECONDARY INSPECTION';
      checkpointBody = 'They waved you through, but not before a much closer look.';
    }
    notifyListeners();
  }

  void _resolveCheckpointClear() {
    checkpointPhase = CheckpointPhase.result;
    checkpointHeadline = 'CLEAR';
    checkpointBody = 'Through without a second look.';
  }

  /// Dismisses the current stop's result panel — either lands on the next
  /// checkpoint's gather phase, or (last checkpoint, or a failed one) rolls
  /// the run's actual outcome via [_resolveRun].
  void advanceCheckpoint() {
    if (level != 2 || runStage == null || checkpointPhase != CheckpointPhase.result) return;
    _lastCheckpointHook[runStage!] = currentScenario.memoryHook;
    if (checkpointHeadline == 'CHECKPOINT FAILED') {
      _resolveRun();
      return;
    }
    runStage = runStage! + 1;
    if (runStage! >= kCheckpoints.length) {
      _resolveRun();
    } else {
      _beginCheckpointGather();
      notifyListeners();
    }
  }

  void _resolveRun() {
    final caught = _rng.nextDouble() < runRisk.clamp(0, 0.85);
    runStage = null;
    if (caught) {
      // A fine, not a strike — being caught costs cash instead of counting
      // toward an arrest, so a bad run stings without ending the career.
      cash -= 650;
      policeHeat = _clamp01to100(policeHeat + 15);
      recentStoryEvent = 'close_call';
      if (_rng.nextDouble() < 0.4) {
        rivalPressure = _clamp01to100(rivalPressure + 10);
      }
      lastWarning = 'Almost got stopped at the crossing — paid \$650 to make it disappear. No cargo, no pay this run.';
      lastRunOutcome = const RunOutcome(caught: true, cashDelta: -650);
      if (_checkExposure()) return;
      _tickPersonalRelationships();
      notifyListeners();
      return;
    }
    lastWarning = null;
    recentStoryEvent = 'run_success';
    cash += 1000;
    successfulRuns += 1;
    policeHeat = _clamp01to100(policeHeat + 8);
    lastRunOutcome = const RunOutcome(caught: false, cashDelta: 1000);
    if (_checkExposure()) return;
    _tickPersonalRelationships();
    if (successfulRuns >= kSuccessfulRunsToPromote) promotionAvailable = true;
    notifyListeners();
  }

  /// Dismisses the post-run result panel [_resolveRun] left up, returning
  /// the player to the idle "truck is loaded" screen.
  void acknowledgeRunOutcome() {
    if (lastRunOutcome == null) return;
    lastRunOutcome = null;
    notifyListeners();
  }

  // ══════════════════════════════════════════════════════════════════════
  // Level 3: Collector
  // ══════════════════════════════════════════════════════════════════════

  void _initLevel3() {
    _sightingTimer?.cancel();
    _sightingGapTimer?.cancel();
    _collectorGapTimer?.cancel();
    _level4GapTimer?.cancel();
    _strategicGapTimer?.cancel();
    _dayTimer?.cancel();
    level = 3;
    collectorWeeks = 0;
    collectorShortWeeks = 0;
    routePenaltySeconds = 0;
    favourUsed = false;
    collectorBusy = false;
    actionInFlight = false;
    shortfallNotice = null;
    targetPaidStreak.clear();
    targetUnderRivalWatch.clear();
    _startNight();
    _announce('handler', 'Route\'s the same every week. Come back short and it\'s on you.');
  }

  /// Resets everything that only lives for one night's route — target
  /// states, the clock, the word going around, and the night's curveball.
  void _startNight() {
    collected.clear();
    targetState.clear();
    targetExcuse.clear();
    for (final t in kCollectionRoute) {
      targetState[t.id] = 'pending';
    }
    targetOnEdge.clear();
    targetTouched.clear();
    routeBudget = routeSeconds - routePenaltySeconds;
    routeSecondsLeft = routeBudget;
    routeActions = 0;
    curveballFired = false;
    pendingCurveball = null;
    curveballTargetId = null;
    _curveballAfter = 2 + _rng.nextInt(2);
  }

  /// What a target actually pays out — full price, unless the rival crew
  /// has noticed it paying like clockwork and started skimming a cut.
  int effectiveOwed(CollectionTarget t) => targetUnderRivalWatch.contains(t.id) ? (t.owed * (1 - kFactionCutFraction)).round() : t.owed;

  int get expectedTotal => kCollectionRoute.fold(0, (a, t) => a + effectiveOwed(t));
  int get collectedTotal => collected.values.fold(0, (a, v) => a + v);

  bool canAffordRouteTime(int seconds) => routeSecondsLeft >= seconds;

  /// True once no target still in play (pending or resisting) has an action
  /// the remaining night can pay for — the route can't advance any further,
  /// so the player has to report in with whatever they've got.
  bool get routeStalled => !kCollectionRoute.any((t) {
        switch (targetState[t.id]) {
          case 'pending':
            return canAffordRouteTime(visitSeconds);
          case 'resisting':
            return canAffordRouteTime(threatenSeconds);
          default:
            return false;
        }
      });

  bool _spendRouteTime(int seconds) {
    if (!canAffordRouteTime(seconds)) return false;
    routeSecondsLeft -= seconds;
    return true;
  }

  // ── Odds the player can read off the card ──

  /// Chance a plain visit gets paid. Everything that moves it is shown on
  /// the target's card, so the order the player works the route in is a
  /// choice they can reason about, not a hidden roll.
  double visitOdds(String targetId) {
    var p = kVisitBaseOdds;
    if (targetUnderRivalWatch.contains(targetId)) p -= kWatchedVisitPenalty;
    if (targetOnEdge.contains(targetId)) p -= kOnEdgeVisitPenalty;
    if (rivalPressure >= 60) {
      p -= 0.10;
    } else if (rivalPressure >= 40) {
      p -= 0.05;
    }
    return p.clamp(0.15, 0.85);
  }

  /// Chance a threat lands — a target that's heard what happened down the
  /// road is easier to scare.
  double threatenOdds(String targetId) => (kThreatenBaseOdds + (targetOnEdge.contains(targetId) ? kOnEdgeThreatenBonus : 0)).clamp(0.15, 0.85);

  // ── Locks ──

  /// Nothing on the route can be done while the player owes a decision, or
  /// while the previous stop is still being driven away from.
  bool get _routeBlocked => collectorBusy || pendingCurveball != null || pendingRivalWarning != null;

  /// What the UI reads to disable every action — also covers the moment
  /// between the tap and the roll, when a second tap must not land.
  bool get collectorLocked => _routeBlocked || actionInFlight;

  // Travel time to/from a stop — locks every action on the route until it
  // clears, so a week can't be cleared in a handful of instant taps.
  void _startCollectorGap() {
    collectorBusy = true;
    _collectorGapTimer?.cancel();
    _collectorGapTimer = Timer(const Duration(seconds: collectorGapSeconds), () {
      collectorBusy = false;
      notifyListeners();
    });
  }

  /// Locks every collector action the instant the UI starts a target's
  /// suspense beat — before [visit]/[threaten]/[vandalize] have even rolled
  /// — so a second tap can't land mid-animation. Cleared by
  /// [endCollectorAction] right before the real call, which then re-locks
  /// via [_startCollectorGap] once it resolves.
  void beginCollectorAction() {
    if (level != 3 || collectorLocked) return;
    actionInFlight = true;
    notifyListeners();
  }

  void endCollectorAction() {
    if (!actionInFlight) return;
    actionInFlight = false;
    notifyListeners();
  }

  /// Bookkeeping every resolved route action shares: the target has been
  /// touched, the rival watches for it, violence spreads word to the rest
  /// of the route, and the night may throw its curveball.
  void _finishRouteAction(String targetId, {bool violent = false}) {
    targetTouched.add(targetId);
    routeActions += 1;
    if (targetUnderRivalWatch.contains(targetId)) {
      rivalPressure = _clamp01to100(rivalPressure + kWatchedActionPressure);
    }
    if (violent) {
      // Whoever hasn't been visited yet hears about it before you arrive.
      for (final t in kCollectionRoute) {
        if (t.id != targetId && targetState[t.id] == 'pending') targetOnEdge.add(t.id);
      }
    }
    _maybeTriggerRivalWarning();
    _maybeTriggerCurveball();
    _startCollectorGap();
    notifyListeners();
  }

  void visit(String targetId) {
    if (level != 3 || _routeBlocked) return;
    if (targetState[targetId] != 'pending') return;
    if (!_spendRouteTime(visitSeconds)) return;
    final target = kCollectionRoute.firstWhere((t) => t.id == targetId);
    if (_rng.nextDouble() < visitOdds(targetId)) {
      collected[targetId] = effectiveOwed(target);
      targetState[targetId] = 'paid';
    } else {
      targetState[targetId] = 'resisting';
      targetExcuse[targetId] = kExcuses[_rng.nextInt(kExcuses.length)];
    }
    policeHeat = _clamp01to100(policeHeat + 1.5);
    cartelSuspicion = _clamp01to100(cartelSuspicion + 1);
    _finishRouteAction(targetId);
  }

  void threaten(String targetId) {
    if (level != 3 || _routeBlocked) return;
    if (targetState[targetId] != 'resisting') return;
    if (!_spendRouteTime(threatenSeconds)) return;
    final target = kCollectionRoute.firstWhere((t) => t.id == targetId);
    if (_rng.nextDouble() < threatenOdds(targetId)) {
      collected[targetId] = effectiveOwed(target);
      targetState[targetId] = 'paid';
    } else {
      targetState[targetId] = 'refused';
      recentStoryEvent = 'refused';
    }
    cartelSuspicion = _clamp01to100(cartelSuspicion + 2);
    rivalPressure = _clamp01to100(rivalPressure + 3);
    _finishRouteAction(targetId, violent: true);
  }

  void vandalize(String targetId, {required bool now}) {
    if (level != 3 || _routeBlocked) return;
    final state = targetState[targetId];
    if (state != 'resisting' && state != 'refused') return;
    if (!_spendRouteTime(vandalizeSeconds)) return;
    final target = kCollectionRoute.firstWhere((t) => t.id == targetId);
    recentStoryEvent = 'crew_violence';
    threads['crew']!.add(Message('${target.name}, ${now ? 'now' : 'tonight'}.', true));
    // Daylight is riskier than waiting for cover of night, but nothing at
    // the bottom is ever truly safe — someone can always tip the cops off.
    final failChance = now ? 0.5 : 0.2;
    if (_rng.nextDouble() < failChance) {
      targetState[targetId] = 'lost';
      policeHeat = _clamp01to100(policeHeat + (now ? 20 : 12));
      rivalPressure = _clamp01to100(rivalPressure + (now ? 6 : 3));
      final line = _pickVariant(_rng, now ? kCrewFailNowLines : kCrewFailTonightLines, _lastCrewLine);
      threads['crew']!.add(Message(line, false));
      _lastCrewLine = line;
    } else {
      collected[targetId] = effectiveOwed(target) * 2;
      targetState[targetId] = 'paid';
      cartelSuspicion = _clamp01to100(cartelSuspicion + (now ? 3 : 2));
      policeHeat = _clamp01to100(policeHeat + (now ? 8 : 4));
      rivalPressure = _clamp01to100(rivalPressure + (now ? 3 : 1));
      final line = _pickVariant(_rng, kCrewSuccessLines, _lastCrewLine);
      threads['crew']!.add(Message(line, false));
      _lastCrewLine = line;
    }
    unread = true;
    _finishRouteAction(targetId, violent: true);
  }

  // ── Call in a favour ──

  bool get favourAvailable => level == 3 && !favourUsed;

  /// Suspicion the player carries into Level 4 for the short weeks they had
  /// on the route (4 each, capped at 15).
  double get promotionCarryOver => min(15.0, collectorShortWeeks * 4.0);

  /// Targets a favour can still be spent on.
  List<CollectionTarget> get favourTargets => [
        for (final t in kCollectionRoute)
          if (const {'pending', 'resisting', 'refused'}.contains(targetState[t.id])) t,
      ];

  /// The emergency button: once per Level 3, any target still holding out
  /// pays in full — for a real jump in cartel suspicion.
  void callInFavour(String targetId) {
    if (!favourAvailable || _routeBlocked) return;
    if (!favourTargets.any((t) => t.id == targetId)) return;
    final target = kCollectionRoute.firstWhere((t) => t.id == targetId);
    favourUsed = true;
    collected[targetId] = effectiveOwed(target);
    targetState[targetId] = 'paid';
    targetExcuse.remove(targetId);
    targetTouched.add(targetId);
    cartelSuspicion = _clamp01to100(cartelSuspicion + kFavourSuspicion);
    _announce('handler', 'Word came down that ${target.name} would be square. Somebody up the chain owes you nothing now — and knows you asked.');
    notifyListeners();
  }

  // ── The night's curveball ──

  /// One major event per night's route, once the player is a couple of
  /// stops in. It reflects how the night has gone: if the rival crew is
  /// hotter than the police, they're the ones who turn up.
  void _maybeTriggerCurveball() {
    if (curveballFired || pendingCurveball != null || pendingRivalWarning != null) return;
    if (routeActions < _curveballAfter) return;
    final inPlay = [
      for (final t in kCollectionRoute)
        if (targetState[t.id] == 'pending' || targetState[t.id] == 'resisting') t,
    ];
    if (inPlay.isEmpty) return;
    curveballFired = true;
    final open = inPlay.where((t) => !targetUnderRivalWatch.contains(t.id)).toList()..sort((a, b) => b.owed.compareTo(a.owed));
    if (rivalPressure > policeHeat && open.isNotEmpty) {
      pendingCurveball = 'rival';
      curveballTargetId = open.first.id;
      _announce('handler', '$rivalCrewName are working ${open.first.name} right now. Your call.');
    } else {
      pendingCurveball = 'police';
      curveballTargetId = null;
      _announce('handler', 'Patrol car keeps circling your route. Don\'t get made.');
    }
  }

  /// Police: `lay_low` | `keep_going`. Rival: `confront` | `let_go`.
  void resolveCurveball(String choice) {
    final kind = pendingCurveball;
    if (kind == null) return;
    if (kind == 'police') {
      if (choice == 'lay_low') {
        routeSecondsLeft = max(0, routeSecondsLeft - kLayLowSeconds);
        policeHeat = _clamp01to100(policeHeat - kLayLowHeatRelief);
      } else {
        policeHeat = _clamp01to100(policeHeat + kKeepGoingHeat);
        cartelSuspicion = _clamp01to100(cartelSuspicion + 2);
      }
    } else {
      final id = curveballTargetId;
      if (choice == 'confront') {
        routeSecondsLeft = max(0, routeSecondsLeft - kConfrontSeconds);
        if (_rng.nextDouble() < 0.5) {
          rivalPressure = _clamp01to100(rivalPressure - 10);
        } else {
          if (id != null) targetUnderRivalWatch.add(id);
          rivalPressure = _clamp01to100(rivalPressure + 8);
          policeHeat = _clamp01to100(policeHeat + 5);
        }
      } else {
        // Let them have their cut — they skim the target, and stand down.
        if (id != null) targetUnderRivalWatch.add(id);
        rivalPressure = _clamp01to100(rivalPressure - 6);
      }
    }
    pendingCurveball = null;
    curveballTargetId = null;
    notifyListeners();
  }

  /// A target paying [kFactionNoticeStreak] weeks running is the kind of
  /// steady income the rival crew eventually clocks — one notice at a time
  /// keeps it readable, and the target it lands on permanently pays less
  /// from then on (see [effectiveOwed]) while [rivalPressure] takes a real
  /// hit, on the same track the existing rival-warning system already
  /// watches.
  void _maybeTriggerFactionNotice() {
    if (targetUnderRivalWatch.isNotEmpty) return;
    for (final t in kCollectionRoute) {
      if ((targetPaidStreak[t.id] ?? 0) >= kFactionNoticeStreak && _rng.nextDouble() < 0.5) {
        targetUnderRivalWatch.add(t.id);
        rivalPressure = _clamp01to100(rivalPressure + 15);
        _announce('handler', '$rivalCrewName noticed ${t.name} paying like clockwork. They\'re going to want a piece of that from now on.');
        return;
      }
    }
  }

  void reportToBoss() {
    if (level != 3 || _routeBlocked) return;
    // The player can call it a night any time — moving on from a target that
    // won't pay is a choice, not something the level forbids. Whatever they
    // leave unfinished (or the clock ran out on) pays nothing.
    for (final t in kCollectionRoute) {
      final s = targetState[t.id];
      if (s == 'pending' || s == 'resisting') targetState[t.id] = 'missed';
    }
    final expected = expectedTotal;
    final got = collectedTotal;
    final shortfall = expected - got;
    if (shortfall > 0) {
      // A short week isn't the end of the career — how bad it was decides
      // what it costs. Cash is allowed to go negative, same as every other
      // "caught" cost in the game.
      collectorShortWeeks += 1;
      final ratio = expected == 0 ? 1.0 : got / expected;
      if (ratio >= kPartialWeekRatio) {
        // Close enough that the boss splits the gap with you.
        final owed = (shortfall / 2).ceil();
        cash -= owed;
        cartelSuspicion = _clamp01to100(cartelSuspicion + 5);
        routePenaltySeconds = 0;
        shortfallNotice = 'Expected ${money(expected)}. Collected ${money(got)}. '
            'Close, but not enough — the boss took half the gap (${money(owed)}) out of your own pocket.';
        _announce('handler', 'Boss says you\'re close. "Close" doesn\'t pay him.');
      } else {
        cash -= shortfall;
        cartelSuspicion = _clamp01to100(cartelSuspicion + 12);
        routePenaltySeconds = kPoorWeekTimePenalty;
        shortfallNotice = 'Expected ${money(expected)}. Collected ${money(got)}. '
            'The whole ${money(shortfall)} gap came out of your own pocket — and next week\'s route gets ${kPoorWeekTimePenalty}s less night to work with.';
        _announce('handler', 'Boss isn\'t happy. He\'s cutting your leash next week.');
      }
    } else {
      cash += 1500;
      collectorWeeks += 1;
      routePenaltySeconds = 0;
    }
    // A watched target left completely alone is one the rival crew stops
    // bothering about — pressure eases, and if it's low enough they lose
    // interest in that target altogether.
    for (final t in kCollectionRoute) {
      if (!targetUnderRivalWatch.contains(t.id) || targetTouched.contains(t.id)) continue;
      rivalPressure = _clamp01to100(rivalPressure - kIgnoredWatchRelief);
      if (rivalPressure < 25) {
        targetUnderRivalWatch.remove(t.id);
        _announce('handler', '$rivalCrewName have moved on from ${t.name}. Nobody\'s skimming it now.');
      }
    }
    // A target paid reliably enough, enough weeks running, and the rival
    // crew notices the pattern — persistent, not just this week's roll.
    for (final t in kCollectionRoute) {
      if (targetState[t.id] == 'paid') {
        targetPaidStreak[t.id] = (targetPaidStreak[t.id] ?? 0) + 1;
      } else {
        targetPaidStreak[t.id] = 0;
      }
    }
    _maybeTriggerFactionNotice();
    _startNight();
    if (_checkExposure()) return;
    _tickPersonalRelationships();
    if (collectorWeeks >= kCollectorWeeksToPromote) promotionAvailable = true;
    notifyListeners();
  }

  /// Dismisses the shortfall popup [reportToBoss] raised.
  void acknowledgeShortfall() {
    if (shortfallNotice == null) return;
    shortfallNotice = null;
    notifyListeners();
  }

  // ══════════════════════════════════════════════════════════════════════
  // Level 4: Cell Leader
  // ══════════════════════════════════════════════════════════════════════

  void _initLevel4() {
    _sightingTimer?.cancel();
    _sightingGapTimer?.cancel();
    _collectorGapTimer?.cancel();
    _level4GapTimer?.cancel();
    _strategicGapTimer?.cancel();
    _dayTimer?.cancel();
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
    level4Busy = false;
    distributorTrust
      ..clear()
      ..addEntries(kDistributors.map((d) => MapEntry(d.id, 0.6)));
    distributorDemandBonus.clear();
    distributorLowTrustStreak.clear();
    distributorLostToRival.clear();
    lastResolution = null;
    _lastSituationId = null;
    _rollMonthlySituation();
  }

  int get allocatedKg => allocated.values.fold(0, (a, v) => a + v);

  // Below this, a month counts as "short" the way the boss reads it (see
  // closeMonth). Tuned to the new per-distributor economy below — a
  // reasonably-run month with an average spread of trust/reliability nets
  // comfortably above this; only real neglect or a genuinely disastrous
  // month lands under it.
  static const int kLevel4ShortMonthThreshold = 20000;

  // Word doesn't travel instantly — closing a month or settling a crisis
  // locks the next action for a stretch instead of chaining straight through.
  void _startLevel4Gap() {
    level4Busy = true;
    _level4GapTimer?.cancel();
    _level4GapTimer = Timer(const Duration(seconds: level4GapSeconds), () {
      level4Busy = false;
      notifyListeners();
    });
  }

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

  // ── Distributor economics — generic over kDistributors, so a new entry
  // there gets trust drift, reliability, and heat/rival cost for free. ──

  double trustFor(String id) => distributorTrust[id] ?? 0.6;

  /// This month's order size, after any drift trust has caused and any
  /// chain-reaction penalty from having been lost to a rival (see
  /// [_resolveDelivery]).
  int demandFor(String id) {
    final d = kDistributors.firstWhere((x) => x.id == id, orElse: () => kDistributors.first);
    final base = max(0, d.baseDemandKg + (distributorDemandBonus[id] ?? 0));
    return distributorLostToRival.contains(id) ? (base * 0.5).round() : base;
  }

  /// Heat both systems are actively feeding each other — the interaction
  /// the whole exposure model hinges on (see closeMonth/effectiveReliability).
  bool get doubleTroubleActive => policeHeat >= 40 && rivalPressure >= 40;

  /// Heat generated by risky Level 4 choices compounds on itself — the same
  /// action produces more heat the hotter things already are.
  double _heatSelfFeedMultiplier() => 1 + (policeHeat / 100) * 0.6;

  double _exposureHeatWeight(DistributorExposure e) => switch (e) {
        DistributorExposure.low => 0.015,
        DistributorExposure.medium => 0.05,
        DistributorExposure.high => 0.12,
      };

  double _exposureRivalWeight(DistributorExposure e) => switch (e) {
        DistributorExposure.low => 0.01,
        DistributorExposure.medium => 0.03,
        DistributorExposure.high => 0.07,
      };

  /// 0..1 odds this distributor pays this month's order in full — folds in
  /// trust, both pressure tracks (and their interaction), and whether
  /// they've already been lost to a rival. Pure/deterministic: used for both
  /// [projectedOutcome]'s estimate and the real dice roll in
  /// [_resolveDelivery].
  double effectiveReliability(Distributor d) {
    double r = d.baseReliability + (trustFor(d.id) - 0.6) * 0.3;
    final heatTier = level4HeatTierFor(policeHeat);
    final rivalTier = level4RivalTierFor(rivalPressure);
    if (heatTier.index >= Level4HeatTier.investigation.index) {
      r -= d.exposure == DistributorExposure.high ? 0.18 : 0.08;
    }
    if (heatTier.index >= Level4HeatTier.heavy.index && d.exposure == DistributorExposure.high) {
      r -= 0.15;
    }
    if (rivalTier.index >= Level4RivalTier.encroaching.index) r -= 0.08;
    if (doubleTroubleActive) r -= 0.08;
    if (distributorLostToRival.contains(d.id)) r -= 0.2;
    return r.clamp(0.05, 0.97);
  }

  /// $/kg this distributor actually pays — nervous, high-heat markets pay a
  /// little less; a trusted relationship pays a little more.
  double effectivePricePerKg(Distributor d) {
    double p = d.basePricePerKg;
    if (policeHeat >= 40) p *= 0.94;
    if (rivalPressure >= 40) p *= 0.96;
    p *= 0.88 + trustFor(d.id) * 0.24;
    return p;
  }

  /// Live, non-committal read of what closing the month right now would do
  /// — the Home screen recomputes this on every build so the player can see
  /// the tradeoff shift as they move kg around, before they commit to it.
  MonthProjection get projectedOutcome {
    double revenue = 0, heatDelta = 0, rivalDelta = 0, exposureScore = 0;
    int totalKg = 0;
    for (final d in kDistributors) {
      final kg = allocated[d.id] ?? 0;
      if (kg <= 0) continue;
      totalKg += kg;
      final wanted = demandFor(d.id);
      final excess = max(0, kg - wanted);
      final normal = kg - excess;
      final rel = effectiveReliability(d);
      final expectedFraction = (0.3 + 0.7 * rel).clamp(0.0, 1.0);
      final price = effectivePricePerKg(d);
      revenue += (normal * price + excess * price * 0.6) * expectedFraction;
      final hw = _exposureHeatWeight(d.exposure);
      heatDelta += normal * hw + excess * hw * 2;
      if (excess > 0) rivalDelta += excess * _exposureRivalWeight(d.exposure);
      exposureScore += (switch (d.exposure) {
            DistributorExposure.low => 0.0,
            DistributorExposure.medium => 1.0,
            DistributorExposure.high => 2.0,
          }) *
          kg;
    }
    heatDelta *= _heatSelfFeedMultiplier();
    if (doubleTroubleActive) {
      heatDelta += 3;
      rivalDelta += 3;
    }
    final avgExposure = totalKg > 0 ? exposureScore / totalKg : 0.0;
    return MonthProjection(
      projectedTake: (revenue * 0.10 * _pathIncomeMultiplier).round(),
      projectedPoliceHeatDelta: heatDelta,
      projectedRivalPressureDelta: rivalDelta,
      riskLabel: avgExposure >= 1.3 ? 'HIGH' : (avgExposure >= 0.5 ? 'MEDIUM' : 'LOW'),
    );
  }

  // ── Monthly situations — data-driven decision point, see kMonthlySituations. ──

  String? get currentSituationDescription {
    final s = currentSituation;
    return s == null ? null : _fillSituationTemplate(s.description);
  }

  String _fillSituationTemplate(String s) {
    var out = s.replaceAll('{rival}', rivalCrewName);
    final focusId = currentSituationFocusId;
    if (focusId != null) {
      final d = kDistributors.firstWhere((x) => x.id == focusId, orElse: () => kDistributors.first);
      out = out.replaceAll('{distributor}', d.name);
    }
    return out;
  }

  void _applySituationOption(MonthlySituationOption option) {
    if (option.cashCost != 0) cash = (cash - option.cashCost).clamp(0, 1 << 30);
    if (option.policeHeatDelta != 0) policeHeat = _clamp01to100(policeHeat + option.policeHeatDelta);
    if (option.rivalPressureDelta != 0) rivalPressure = _clamp01to100(rivalPressure + option.rivalPressureDelta);
    if (option.cartelSuspicionDelta != 0) cartelSuspicion = _clamp01to100(cartelSuspicion + option.cartelSuspicionDelta);
    if (option.allCrewLoyaltyDelta != 0) {
      for (final n in crewNames) {
        crewLoyalty[n] = ((crewLoyalty[n] ?? 0.8) + option.allCrewLoyaltyDelta).clamp(0, 1);
      }
    }
    final focusId = currentSituationFocusId;
    if (focusId != null) {
      if (option.focusDistributorTrustDelta != 0) {
        distributorTrust[focusId] = (trustFor(focusId) + option.focusDistributorTrustDelta).clamp(0, 1);
      }
      if (option.focusDistributorDemandDelta != 0) {
        distributorDemandBonus[focusId] = ((distributorDemandBonus[focusId] ?? 0) + option.focusDistributorDemandDelta).clamp(-15, 20);
      }
    }
  }

  /// The player's response to [currentSituation] — effects land immediately
  /// (same pattern as [respondIncursion]/[discipline]); the filled-in result
  /// line is picked back up by [closeMonth] for that month's resolution card.
  void chooseSituationOption(String optionId) {
    final situation = currentSituation;
    if (situation == null || currentSituationChoiceId != null) return;
    final option = situation.options.firstWhere((o) => o.id == optionId, orElse: () => situation.options.last);
    if (option.cashCost > 0 && cash < option.cashCost) return;
    _applySituationOption(option);
    currentSituationChoiceId = optionId;
    notifyListeners();
  }

  /// Rolls next month's situation — called once a month resolves, and once
  /// up front by [_initLevel4] so there's always one waiting.
  void _rollMonthlySituation() {
    final pool = kMonthlySituations;
    var template = pool[_rng.nextInt(pool.length)];
    if (pool.length > 1) {
      while (template.id == _lastSituationId) {
        template = pool[_rng.nextInt(pool.length)];
      }
    }
    _lastSituationId = template.id;
    currentSituation = template;
    currentSituationChoiceId = null;
    currentSituationFocusId = template.needsDistributorFocus ? kDistributors[_rng.nextInt(kDistributors.length)].id : null;
  }

  /// One distributor's delivery for the month: a reliability-weighted dice
  /// roll (not the deterministic expected value [projectedOutcome] uses),
  /// generic trust/demand drift, the "lost to a rival" chain reaction, and
  /// the heat/rival cost of having done business with them at all. Every
  /// heat/rival change it makes is appended to [heatReasons]/[rivalReasons]
  /// with a label — nothing here changes either meter silently.
  DeliveryLine _resolveDelivery(Distributor d, int kg, List<HeatReason> heatReasons, List<HeatReason> rivalReasons) {
    final wanted = demandFor(d.id);
    final rel = effectiveReliability(d);
    final price = effectivePricePerKg(d);
    final roll = _rng.nextDouble();
    int paidKg;
    String detail;
    if (roll < rel) {
      paidKg = kg;
      detail = 'paid in full';
    } else if (roll < rel + (1 - rel) * 0.65) {
      final frac = 0.4 + _rng.nextDouble() * 0.45;
      paidKg = (kg * frac).round().clamp(0, kg);
      detail = kg - paidKg > 0 ? 'was short by ${kg - paidKg} KG' : 'paid in full';
    } else {
      final frac = _rng.nextDouble() * 0.3;
      paidKg = (kg * frac).round().clamp(0, kg);
      detail = paidKg == 0 ? 'refused the order entirely' : 'refused part of the order';
    }

    final excess = max(0, kg - wanted);
    final normal = kg - excess;
    final paidNormal = min(paidKg, normal);
    final paidExcess = max(0, paidKg - normal);
    final revenue = (paidNormal * price + paidExcess * price * 0.6).round();

    // Trust & demand drift — generic over every distributor, so this is the
    // one place adding a fourth one to kDistributors needs to touch.
    final metRatio = wanted > 0 ? (paidKg / wanted) : (paidKg > 0 ? 1.5 : 1.0);
    double trust = trustFor(d.id);
    if (metRatio >= 1.0) {
      trust = (trust + 0.04).clamp(0, 1);
    } else if (metRatio >= 0.6) {
      trust = (trust - 0.02).clamp(0, 1);
    } else {
      trust = (trust - 0.1).clamp(0, 1);
    }
    distributorTrust[d.id] = trust;
    if (trust > 0.75) {
      distributorDemandBonus[d.id] = ((distributorDemandBonus[d.id] ?? 0) + (2 * d.growth).round()).clamp(-15, 20);
    } else if (trust < 0.35) {
      distributorDemandBonus[d.id] = ((distributorDemandBonus[d.id] ?? 0) - 3).clamp(-15, 20);
    }

    // Chain reaction: a distributor whose trust stays in the gutter two
    // months running quietly starts supplying $rivalCrewName instead — a
    // consequence of earlier decisions, not a fresh random event.
    if (trust < 0.25) {
      distributorLowTrustStreak[d.id] = (distributorLowTrustStreak[d.id] ?? 0) + 1;
    } else {
      distributorLowTrustStreak[d.id] = 0;
      if (trust > 0.65) distributorLostToRival.remove(d.id);
    }
    if ((distributorLowTrustStreak[d.id] ?? 0) >= 2 && distributorLostToRival.add(d.id)) {
      rivalPressure = _clamp01to100(rivalPressure + 10);
      rivalReasons.add(HeatReason('${d.name} started supplying $rivalCrewName', 10));
      detail = '$detail — and word is they\'re talking to $rivalCrewName now';
    }

    // The cost of having done business with them at all this month — always
    // applied (matching what projectedOutcome promised before the player
    // committed); only logged as a reason once it's big enough to be worth
    // reading, so the card doesn't fill up with noise-level line items.
    final hw = _exposureHeatWeight(d.exposure);
    final h = (normal * hw + excess * hw * 2) * _heatSelfFeedMultiplier();
    if (h > 0) {
      policeHeat = _clamp01to100(policeHeat + h);
      if (h >= 0.4) {
        heatReasons.add(HeatReason('${d.name} — ${d.exposure == DistributorExposure.high ? 'high-risk' : 'active'} distribution', h));
      }
    }
    if (excess > 0) {
      final rv = excess * _exposureRivalWeight(d.exposure);
      if (rv > 0) {
        rivalPressure = _clamp01to100(rivalPressure + rv);
        if (rv >= 0.4) {
          rivalReasons.add(HeatReason('Flooded ${d.name}\'s market past what they wanted', rv));
        }
      }
    }

    return DeliveryLine(distributorName: d.name, wantedKg: wanted, paidKg: paidKg, revenue: revenue, detail: detail);
  }

  MonthResolution? closeMonth() {
    if (level != 4 || level4Busy) return null;
    if (pendingIncursion != null || pendingTrouble != null) return null;

    // The month's situation doesn't block closing — ignoring it is a valid
    // (if worse) choice. Anything left unpicked auto-resolves to the
    // template's last option instead of just silently vanishing.
    String? situationSummary;
    final situation = currentSituation;
    if (situation != null) {
      final defaulted = currentSituationChoiceId == null;
      final option = situation.options.firstWhere((o) => o.id == currentSituationChoiceId, orElse: () => situation.options.last);
      if (defaulted) _applySituationOption(option);
      final line = _fillSituationTemplate(option.resultLine);
      situationSummary = defaulted ? 'Ignored — $line' : line;
    }
    currentSituationChoiceId = null;

    final heatReasons = <HeatReason>[];
    final rivalReasons = <HeatReason>[];
    final deliveries = <DeliveryLine>[];
    double revenue = 0;
    for (final d in kDistributors) {
      final kg = allocated[d.id] ?? 0;
      if (kg <= 0) continue;
      final delivery = _resolveDelivery(d, kg, heatReasons, rivalReasons);
      deliveries.add(delivery);
      revenue += delivery.revenue;
    }

    // Both meters running hot at once is meaningfully worse than either
    // alone — the interaction the whole system is built around.
    final crewLines = <String>[];
    if (doubleTroubleActive) {
      policeHeat = _clamp01to100(policeHeat + 3);
      rivalPressure = _clamp01to100(rivalPressure + 3);
      heatReasons.add(const HeatReason('Police and rivals both circling', 3));
      rivalReasons.add(const HeatReason('Police and rivals both circling', 3));
      if (crewNames.isNotEmpty) {
        final hit = crewNames[_rng.nextInt(crewNames.length)];
        final before = crewLoyalty[hit] ?? 0.8;
        final after = (before - 0.05).clamp(0.0, 1.0);
        crewLoyalty[hit] = after;
        crewLines.add('$hit loyalty ${((after - before) * 100).round()}');
      }
    }

    final take = (revenue * 0.10 * _pathIncomeMultiplier).round();
    cash += take;
    lastMonthTake = take;
    monthsAsLeader += 1;
    stashKg = 100;
    allocated.clear();
    // A crew that only hears from a dealmaker or a numbers guy drifts a
    // little every month — Muscle is the one path that's actually around.
    if (careerPath == 'fixer' || careerPath == 'boss') {
      for (final n in crewNames) {
        crewLoyalty[n] = ((crewLoyalty[n] ?? 0.8) - 0.03).clamp(0, 1);
      }
    }
    // Heat cools slower now — a violent month lingers instead of washing out
    // by the next one. Suspicion creeps up a little every month regardless
    // of how careful you are; moving product at this volume is never fully invisible.
    policeHeat = _clamp01to100(policeHeat - 3);
    cartelSuspicion = _clamp01to100(cartelSuspicion + 2);
    heatReasons.add(const HeatReason('Natural cooldown', -3));

    if (take < kLevel4ShortMonthThreshold) {
      shortMonths += 1;
      _announce('handler', kBossPressureLines[_rng.nextInt(kBossPressureLines.length)]);
      if (shortMonths >= 2) {
        _die('The regional boss doesn\'t tolerate coming up short twice running.');
        return null;
      }
    } else {
      shortMonths = 0;
      if (_rng.nextDouble() < 0.25) {
        _announce('handler', kBossPressureLines[_rng.nextInt(kBossPressureLines.length)]);
      }
    }
    if (_checkExposure()) return null;
    _tickPersonalRelationships();

    // Trouble and an incursion can both land the same month — reckless crew
    // and hungry rivals don't wait for a convenient week. Muscle keeps a
    // tighter leash on the crew, so trouble is rarer for that path. Both
    // meters running hot makes everything more frequent, not just worse.
    final troubleChance = (careerPath == 'muscle' ? 0.30 : 0.45) + (doubleTroubleActive ? 0.10 : 0);
    if (_rng.nextDouble() < troubleChance && crewNames.isNotEmpty) {
      pendingTrouble = crewNames[_rng.nextInt(crewNames.length)];
      recentStoryEvent = 'crew_trouble';
    }
    final incursionChance = 0.45 + (doubleTroubleActive ? 0.15 : 0);
    if (_rng.nextDouble() < incursionChance) {
      pendingIncursion = '$rivalCrewName is testing your corner on the east side.';
      recentStoryEvent ??= 'incursion'; // don't overwrite crew_trouble if both land
      rivalPressure = _clamp01to100(rivalPressure + 15);
      rivalReasons.add(const HeatReason('New rival incursion', 15));
    }
    if (pendingTrouble == null && pendingIncursion == null && monthsAsLeader >= kMonthsAsLeaderToPromote) {
      promotionAvailable = true;
    }

    final resolution = MonthResolution(
      monthNumber: monthsAsLeader,
      take: take,
      deliveries: deliveries,
      policeHeatReasons: heatReasons,
      rivalPressureReasons: rivalReasons,
      crewLines: crewLines,
      territoryLines: ['$rivalCrewName — pressure now ${rivalPressure.round()} (${level4RivalTierLabel(level4RivalTierFor(rivalPressure))})'],
      situationSummary: situationSummary,
    );
    lastResolution = resolution;
    _rollMonthlySituation();
    _maybeStartLevel4Gap();
    notifyListeners();
    return resolution;
  }

  // The gap only starts once nothing is left to resolve — a freshly rolled
  // crisis must stay answerable right away, never locked behind a cooldown.
  void _maybeStartLevel4Gap() {
    if (pendingIncursion == null && pendingTrouble == null) _startLevel4Gap();
  }

  void respondIncursion(String choice) {
    if (pendingIncursion == null) return;
    if (choice == 'violence') {
      recentStoryEvent = 'crew_violence';
      policeHeat = _clamp01to100(policeHeat + 25 * _heatSelfFeedMultiplier());
      cartelSuspicion = _clamp01to100(cartelSuspicion - 10);
      rivalPressure = _clamp01to100(rivalPressure - 20);
    } else {
      cash = (cash - (2000 * _pathNegotiationCostMultiplier).round()).clamp(0, 1 << 30);
      cartelSuspicion = _clamp01to100(cartelSuspicion + 5);
      rivalPressure = _clamp01to100(rivalPressure - 8);
    }
    pendingIncursion = null;
    if (pendingTrouble == null && monthsAsLeader >= kMonthsAsLeaderToPromote) promotionAvailable = true;
    _maybeStartLevel4Gap();
    notifyListeners();
  }

  void discipline(String name, String action) {
    if (pendingTrouble != name) return;
    if (action == 'beating') {
      recentStoryEvent = 'crossed_line';
      // Muscle knows how to send a message without losing the room.
      crewLoyalty[name] = ((crewLoyalty[name] ?? 0.8) - (careerPath == 'muscle' ? 0.075 : 0.15)).clamp(0, 1);
      policeHeat = _clamp01to100(policeHeat + 4 * _heatSelfFeedMultiplier());
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
    _maybeStartLevel4Gap();
    notifyListeners();
  }

  // ══════════════════════════════════════════════════════════════════════
  // Levels 5-7: strategic layer
  // ══════════════════════════════════════════════════════════════════════

  void _initStrategic(int lvl) {
    _sightingTimer?.cancel();
    _sightingGapTimer?.cancel();
    _collectorGapTimer?.cancel();
    _level4GapTimer?.cancel();
    _strategicGapTimer?.cancel();
    _dayTimer?.cancel();
    level = lvl;
    strategicCycles = 0;
    strategicEvent = null;
    strategicEventKind = null;
    investigationStage = 0;
    raidTargetName = null;
    strategicBusy = false;
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

  // Settling a cycle at this level takes real time — longer the higher up
  // the pyramid you are, per [strategicGapSeconds].
  void _startStrategicGap() {
    strategicBusy = true;
    _strategicGapTimer?.cancel();
    _strategicGapTimer = Timer(Duration(seconds: strategicGapSeconds), () {
      strategicBusy = false;
      notifyListeners();
    });
  }

  // Only start the cooldown once every level-5 cell crisis this cycle is
  // resolved — a freshly rolled crisis must stay answerable right away.
  void _maybeStartStrategicGap() {
    if (pendingCellSkim == null && pendingCellPoach == null && pendingCellShortage == null) {
      _startStrategicGap();
    }
  }

  void seizeTerritory(Territory t) {
    if (t.controlled || cash < 3000000) return;
    t.controlled = true;
    cash -= 3000000;
    cartelSuspicion = _clamp01to100(cartelSuspicion + 15);
    policeHeat = _clamp01to100(policeHeat + 10);
    rivalPressure = _clamp01to100(rivalPressure + 12);
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
    if (level < 5 || strategicBusy) return;
    if (level == 5 && (pendingCellSkim != null || pendingCellPoach != null || pendingCellShortage != null)) return;
    if (level >= 6 && strategicEvent != null) return;
    final revenue = strategicMonthlyRevenue;
    final take = (revenue * (level == 5 ? 0.08 : level == 6 ? 0.05 : 0.03) * _pathIncomeMultiplier).round();
    cash += take;
    strategicCycles += 1;
    policeHeat = _clamp01to100(policeHeat + 6);
    if (_checkExposure()) return;
    _tickPersonalRelationships();

    if (level == 5) {
      _advanceCellLeaders();
      if (gameOver) return;
      _maybeStartStrategicGap();
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
      // A newly surfaced event must stay answerable right away — the gap
      // starts once resolveStrategicEvent clears it, not here.
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
    // Only a clean cycle (no fresh event) leaves you free to advance again
    // right away, so only a clean cycle starts the cooldown here.
    if (strategicEvent == null) _startStrategicGap();
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
    strategicEvent = '$rivalCrewName is moving on your hold in ${t.name}.';
    strategicEventKind = 'raid_territory';
    rivalPressure = _clamp01to100(rivalPressure + 15);
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
          cash = (cash - (2000000 * _pathNegotiationCostMultiplier).round()).clamp(0, 1 << 30);
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
    _startStrategicGap();
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
      rivalPressure = _clamp01to100(rivalPressure - 15);
    } else if (choice == 'payoff' && cash >= 1000000) {
      cash -= 1000000;
      cartelSuspicion = _clamp01to100(cartelSuspicion + 5);
      rivalPressure = _clamp01to100(rivalPressure - 8);
    } else {
      t.controlled = false;
      cartelSuspicion = _clamp01to100(cartelSuspicion - 5);
      rivalPressure = _clamp01to100(rivalPressure - 25);
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
      rivalPressure = _clamp01to100(rivalPressure + 10);
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
      rivalPressure = _clamp01to100(rivalPressure - 5);
    } else {
      // They walk — the cell falls apart without them for a while.
      cell.loyalty = (cell.loyalty - 0.3).clamp(0, 1);
      cell.performance = (cell.performance - 0.25).clamp(0, 1);
      cartelSuspicion = _clamp01to100(cartelSuspicion + 6);
      rivalPressure = _clamp01to100(rivalPressure + 5);
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
    if (pendingCellSkim == null && pendingCellPoach == null && pendingCellShortage == null) {
      if (strategicGoodCycles >= kStrategicGoodCyclesToPromote) promotionAvailable = true;
      // The gap only starts once every crisis this cycle is resolved — a
      // freshly rolled one must stay answerable right away.
      _startStrategicGap();
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

  // Reply-tray chip generation & scoring (_storyContextChips,
  // personalReplyOptions, and their scoring helpers) has moved to the
  // ReplyTray extension in conversation/reply_tray.dart — that's the single
  // place that now decides what shows up in a personal thread's reply tray.

  /// How many times per week (reset at the [_advanceDay] week boundary) the
  /// player can use Mama's "(Ask for Money)" flow — see [resolveMoneyAsk].
  /// Small on purpose: unlike every other personal-thread action, this one
  /// grants real [cash], so it needs a hard cap rather than just a
  /// relationship-stat nudge.
  static const int kMaxMoneyAsksPerWeek = 2;

  /// Remaining "(Ask for Money)" uses this week for [contactId].
  int moneyAsksRemaining(String contactId) =>
      (kMaxMoneyAsksPerWeek - relationships[contactId]!.moneyAsksThisWeek).clamp(0, kMaxMoneyAsksPerWeek);

  /// Sends [intent] to [contactId] (Mama, in practice — the only contact
  /// [personalReplyOptions] offers [IntentChip]s for): translates the chip
  /// into a [PersonalReplyAction] template carrying its full [IntentChip.
  /// phrasings] pool (rather than a single pre-picked line) and hands it to
  /// [personalReplyAction], which now does the actual phrasing-resolution
  /// generically for every action, chip-originated or not — see its own doc
  /// comment. Every stat delta, block check, topic-thread update, and spam
  /// counter still behaves exactly as it already did for a scripted
  /// [PersonalReplyAction].
  void sendIntent(String contactId, ConversationIntent intent) {
    final chips = contactId == 'mama' ? kIntentChips : kValeIntentChips;
    final chip = chips.firstWhere((c) => c.intent == intent);
    personalReplyAction(
      contactId,
      PersonalReplyAction(
        chip.label,
        phrasings: chip.phrasings,
        tone: chip.primaryTone,
        topics: chip.primaryTopics,
        intent: chip.primaryIntent,
        intensity: chip.intensity,
        conversationIntent: intent,
      ),
    );
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
    final p = kPersonalContact[contactId]!;
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
    rel.pendingQuestionId = null;

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
      // A money ask is a real exchange worth remembering for days, not just
      // the next few turns — the new "high" tier (Phase 11), not "medium"
      // (which now means a lighter conversational-continuity move; see
      // _conversationImportance's doc comment).
      importance: MemoryImportance.high,
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
      topicSubject: rel.topicSubject,
      levelPhase: levelPhase,
      recentConversation: rel.recentConversation,
      facts: rel.facts,
      honesty: rel.honesty,
      reliability: rel.reliability,
      responsiveness: rel.responsiveness,
      personality: p.personality,
      conversationDepth: rel.conversationDepth,
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
      // A money ask is a real exchange worth remembering for days, not just
      // the next few turns — the new "high" tier (Phase 11), not "medium"
      // (which now means a lighter conversational-continuity move; see
      // _conversationImportance's doc comment).
      importance: MemoryImportance.high,
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
  /// for how this drives eviction (Phase 11: turns for low/medium, days for
  /// high, permanent for critical), and [_permanentMemoryFor] for which
  /// intents also get promoted into the permanent [RelationshipState.memories]
  /// log. A legacy free-text-derived turn (conversationIntent == null) is
  /// always low — there's no chip-level signal to weigh it by.
  ///
  /// [critical] and [high] are unchanged from before Phase 11 (previously
  /// named `high`/`medium`) — confront/questionLoyalty/makePeace were always
  /// the "permanent milestone" set, apologize/insult/askAboutFamily/etc. were
  /// always the "real exchange, not small talk" set. What's new is [medium]:
  /// carved out of the old flat `low` catch-all for intents that are still
  /// conversational moves rather than substance (checkIn, elaborate, deflect
  /// — about whether/how the thread continues) but read as a notch more
  /// deliberate than a bare greeting or a "lol" — so they get a slightly
  /// longer window (~10 turns) than pure social lubricant (~3 turns)
  /// without competing with genuinely substantive content for space.
  static MemoryImportance _conversationImportance(ConversationIntent? intent) {
    const critical = {ConversationIntent.confront, ConversationIntent.questionLoyalty, ConversationIntent.makePeace};
    const high = {
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
    const medium = {ConversationIntent.checkIn, ConversationIntent.elaborate, ConversationIntent.deflect};
    if (intent == null) return MemoryImportance.low;
    if (critical.contains(intent)) return MemoryImportance.critical;
    if (high.contains(intent)) return MemoryImportance.high;
    if (medium.contains(intent)) return MemoryImportance.medium;
    return MemoryImportance.low;
  }

  /// A critical-importance turn is charged enough to outlive
  /// [RelationshipState.recentConversation]'s rolling window entirely — it
  /// gets promoted into the permanent [MemoryEvent] log the same way
  /// [MemoryKind.firstWarmReply] already does elsewhere. Returns null for an
  /// intent that's critical-importance for the moment but isn't the kind of
  /// thing worth a permanent milestone (none currently — every entry in
  /// [_conversationImportance]'s `critical` set maps to one).
  static MemoryKind? _permanentMemoryFor(ConversationIntent intent) => switch (intent) {
        ConversationIntent.confront || ConversationIntent.questionLoyalty => MemoryKind.deepConfession,
        ConversationIntent.makePeace => MemoryKind.promiseMade,
        _ => null,
      };

  /// Grace window (in [RelationshipState.turnCount] turns) before a
  /// [MemoryImportance.low] turn is pruned from
  /// [RelationshipState.recentConversation] — pure social lubricant ("lol",
  /// a bare greeting) that shouldn't linger long enough to compete with
  /// anything that actually matters. See [_pruneConversationMemory].
  static const int kLowImportanceTurnWindow = 3;

  /// [kLowImportanceTurnWindow]'s counterpart for [MemoryImportance.medium]
  /// — a conversational-continuity move (checkIn, elaborate, deflect) reads
  /// as a bit more deliberate than pure filler, so it earns a longer window,
  /// still turn-granular rather than day-granular since it's still ordinary
  /// small-talk-adjacent pacing, not a real topic.
  static const int kMediumImportanceTurnWindow = 10;

  /// Grace window (in game [day]s) before a [MemoryImportance.high] turn is
  /// pruned — day-granular rather than turn-granular because "a real
  /// exchange from earlier this week" is the thing being modeled, not "a few
  /// messages ago." "Several days," per Phase 11's own framing.
  static const int kHighImportanceDayWindow = 5;

  /// Bounds [RelationshipState.recentConversation] (Phase 11): [low]-
  /// importance turns (small talk — "lol") expire after
  /// [kLowImportanceTurnWindow] turns, [medium] after
  /// [kMediumImportanceTurnWindow] turns, [high]-importance turns (arguments,
  /// apologies, real questions) after [kHighImportanceDayWindow] days, and
  /// [critical] turns are never pruned by age — only the hard 12-entry cap
  /// below can push one out, and by then it's already been promoted to a
  /// permanent memory (see [_permanentMemoryFor]). Turn-based windows read
  /// against [RelationshipState.turnCount] (only a reply to this contact
  /// advances it — the same constraint [isOverdue] documents), so a low/
  /// medium turn effectively ages out relative to how much has since been
  /// said to this contact, not relative to the calendar. Called after every
  /// new turn and once more on each morning tick, so a quiet contact's
  /// day-based ([high]) window still ages out even on days the player never
  /// opens their thread — a quiet contact's turn-based ([low]/[medium])
  /// windows don't need that second call, since nothing advances turnCount
  /// without a reply anyway.
  void _pruneConversationMemory(RelationshipState rel) {
    rel.recentConversation.removeWhere((e) {
      switch (e.importance) {
        case MemoryImportance.low:
          return rel.turnCount - e.turn >= kLowImportanceTurnWindow;
        case MemoryImportance.medium:
          return rel.turnCount - e.turn >= kMediumImportanceTurnWindow;
        case MemoryImportance.high:
          return day - e.day >= kHighImportanceDayWindow;
        case MemoryImportance.critical:
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

  /// Phase 10: marks any promise/request [PendingInteraction] whose deadline
  /// has passed as [PendingInteraction.broken] and applies the relationship
  /// consequence — a real, measurable hit to reliability/trust, not just a
  /// status flag no caller reads. Never a question — see
  /// [PendingInteraction.broken]'s doc comment for why that type is excluded.
  /// Called from [personalReplyAction] only: [isOverdue] compares against
  /// [RelationshipState.turnCount], which nothing but a reply advances, so
  /// this can't usefully run on the passive tick/day cadence instead — a
  /// broken commitment surfaces the next time the player actually talks to
  /// this contact, not silently in the background.
  void _breakOverdueInteractions(RelationshipState rel) {
    for (final interaction in rel.pendingInteractions) {
      if (interaction.type == InteractionType.question) continue;
      if (!isOverdue(interaction, rel.turnCount)) continue;
      interaction.resolved = true;
      interaction.broken = true;
      rel.reliability = nudgeReliability(rel.reliability, delta: -3.0);
      rel.trust = (rel.trust - 2).clamp(0, 100);
      recordMemory(rel.memories, MemoryEvent(MemoryKind.brokenPromise, day));
    }
  }

  /// Resolves [template]'s [PersonalReplyAction.phrasings] pool down to the
  /// single line this turn actually sends — the same pickLine()-driven,
  /// repeat-avoiding selection [sendIntent] already used to do by hand for an
  /// [IntentChip], now generalized so every [PersonalReplyAction] (catalog,
  /// story-context, or chip-originated) goes through one resolution path.
  /// [turnPhase] is passed in rather than read fresh via [levelPhase], since
  /// [personalReplyAction] captures it before clearing [recentStoryEvent] —
  /// see that method's own comment on why the order matters.
  ///
  /// Mirrors [IntentChip.phrasings]' override contract exactly: whichever
  /// (tone, topic, intent, subject, resolvesThread, establishesFacts,
  /// fulfillsPromise, isVulnerableDisclosure) the picked [DialogueLine]
  /// specifies wins over [template]'s own fallback value for that same axis;
  /// everything else carries over unchanged. Returns a new
  /// [PersonalReplyAction] with [PersonalReplyAction.phrasings] narrowed to
  /// exactly that one line, so [PersonalReplyAction.text] resolves to it.
  PersonalReplyAction _resolvePersonalReplyAction(
    PersonalReplyAction template,
    RelationshipState rel,
    PersonalContact p,
    LevelPhase turnPhase,
  ) {
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
      topicSubject: rel.topicSubject,
      playerTopicsToday: rel.topicsDiscussedToday,
      levelPhase: turnPhase,
      recentConversation: rel.recentConversation,
      facts: rel.facts,
      honesty: rel.honesty,
      reliability: rel.reliability,
      responsiveness: rel.responsiveness,
      personality: p.personality,
      conversationDepth: rel.conversationDepth,
    );
    final line = pickLine(
          _rng,
          template.phrasings,
          ctx,
          currentDay: day,
          lineLastUsedDay: rel.lineLastUsedDay,
          recentLineHistory: rel.recentLineHistory,
        ) ??
        template.phrasings.first;
    recordLineUse(rel.lineLastUsedDay, rel.recentLineHistory, line, day);

    return PersonalReplyAction(
      template.label,
      phrasings: [line],
      tone: line.tone ?? template.tone,
      topics: line.topic != null ? {line.topic!, ...template.topics} : template.topics,
      intent: line.intent ?? template.intent,
      intensity: template.intensity,
      isDebtTopic: template.isDebtTopic,
      allowedContacts: template.allowedContacts,
      conversationIntent: template.conversationIntent,
      subject: line.subject ?? template.subject,
      resolvesThread: line.resolvesThread || template.resolvesThread,
      establishesFacts: line.establishesFacts ?? template.establishesFacts,
      fulfillsPromise: line.fulfillsPromise || template.fulfillsPromise,
      isVulnerableDisclosure: line.isVulnerableDisclosure || template.isVulnerableDisclosure,
      showWhenMoodBelow: template.showWhenMoodBelow,
      showWhenMoodAbove: template.showWhenMoodAbove,
      requiresThread: template.requiresThread,
      showWhenLevelMin: template.showWhenLevelMin,
      showWhenLevelMax: template.showWhenLevelMax,
      showWhenTrustBelow: template.showWhenTrustBelow,
      showWhenTrustAbove: template.showWhenTrustAbove,
      showWhenSuspicionAbove: template.showWhenSuspicionAbove,
      showWhenClosenessAbove: template.showWhenClosenessAbove,
    );
  }

  /// Reply to [contactId] by picking a [PersonalReplyAction] (from
  /// [personalReplyOptions], though any catalog entry is accepted) — each
  /// option already declares the (tone, topics, intent, intensity) axes
  /// [classifyMessage] used to infer from free text, so choosing one is
  /// self-classifying. Applies the relationship-stat deltas scaled by
  /// [impactMultiplier] and picks a same-turn reaction line, identically to
  /// how the old free-text path did once classification was done.
  ///
  /// [action] arrives as a template — [PersonalReplyAction.phrasings] may
  /// hold several candidate wordings — and the very first thing this method
  /// does is resolve it down to the one line this turn actually sends (see
  /// [_resolvePersonalReplyAction]), reassigning the parameter so every
  /// `action.*` read below (topic advancement, stat deltas, spam tracking,
  /// the sent [Message], ...) already reflects that line's own overrides.
  void personalReplyAction(String contactId, PersonalReplyAction action) {
    final rel = relationships[contactId]!;
    if (rel.goneQuiet || rel.resolved || rel.isBlocked) return;
    // Phase 10: a promise/request whose deadline already passed breaks the
    // moment the player next talks to this contact, before this turn's own
    // action is processed — see _breakOverdueInteractions's doc comment.
    _breakOverdueInteractions(rel);
    // Captured before recentStoryEvent is cleared below — [levelPhase]
    // reads recentStoryEvent to detect LevelPhase.cusp, so evaluating it
    // after the clear would make cusp permanently unreachable from this
    // method's own ConversationEvent record and reaction DialogueContext.
    final turnPhase = levelPhase;
    // Consume the story event — the player has spoken about (or chosen not to
    // speak about) whatever just happened. The tray resets to its normal state.
    recentStoryEvent = null;
    final p = kPersonalContact[contactId]!;
    action = _resolvePersonalReplyAction(action, rel, p, turnPhase);
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

    // Conversation depth (Phase 16): classifies THIS turn from what was
    // just said, then combines it with the thread's existing depth — see
    // advanceDepth()'s doc comment for why escalation is immediate but
    // de-escalation only steps down one level at a time. Placed after
    // advanceTopic() so classifyDepth() reads the just-updated currentTopic,
    // not the prior turn's.
    rel.conversationDepth = advanceDepth(
      rel.conversationDepth,
      classifyDepth(
        conversationIntent: action.conversationIntent,
        topic: rel.currentTopic,
        intensity: action.intensity,
        isVulnerableDisclosure: action.isVulnerableDisclosure,
      ),
    );

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
    if (resolved.answered) {
      _resolvePendingInteraction(rel, InteractionType.question);
      rel.pendingQuestionId = null;
    }
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
      _openPendingInteraction(
        rel,
        type: InteractionType.promise,
        topic: rel.currentTopic,
        subject: action.subject,
        deadlineTurn: rel.turnCount + kDefaultPromiseDeadlineTurns,
      );
    }

    // A promise explicitly kept (Phase 9) — resolves both a promise the
    // player made themselves (InteractionType.promise) and one Mama asked
    // for (InteractionType.request, opened via DialogueLine.requestsPromise
    // — Phase 10): from the player's side, "I did what I said I would" reads
    // the same regardless of who first raised it. Either resolve is a no-op
    // if nothing of that type is currently open.
    if (action.fulfillsPromise) {
      _resolvePendingInteraction(rel, InteractionType.promise);
      _resolvePendingInteraction(rel, InteractionType.request);
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
    if (turnImportance == MemoryImportance.critical) {
      final kind = _permanentMemoryFor(action.conversationIntent!);
      if (kind != null) recordMemory(rel.memories, MemoryEvent(kind, day));
    }
    _pruneConversationMemory(rel);

    personalThreads[contactId]!.add(Message(action.text, true));

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
          e.importance != MemoryImportance.low,
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
        topicSubject: rel.topicSubject,
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
        personality: p.personality,
        conversationDepth: rel.conversationDepth,
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
        // The bespoke-tray trigger is broader than the dodge-tracked
        // "pending question" state above: Mama's line doesn't have to be
        // grammatically a question to deserve a tray built around exactly
        // what she just said (see DialogueLine.questionId's doc comment and
        // reply_tray.dart's kQuestionAnswerChips lookup) — a loaded
        // STATEMENT ("I ran into your ex today...") can just as easily carry
        // one. Any tagged line sets it, independent of intent.
        if (reaction.questionId != null) {
          rel.pendingQuestionId = reaction.questionId;
        }
        // Phase 10: Mama's reply itself asks the player to commit to
        // something concrete (e.g. "Promise me you'll call your grandma") —
        // opens a request with a deadline, same as the question case above.
        if (reaction.requestsPromise) {
          _openPendingInteraction(
            rel,
            type: InteractionType.request,
            topic: reaction.topic,
            subject: reaction.subject,
            deadlineTurn: rel.turnCount + (reaction.promiseDeadlineTurns ?? kDefaultPromiseDeadlineTurns),
          );
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
        _pruneConversationMemory(rel); // ages out high-importance (day-based) conversation events even on a day the player never opens this thread; low/medium (turn-based) can't age without a reply anyway
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
            topicSubject: rel.topicSubject,
            playerTopicsToday: rel.topicsDiscussedToday,
            // Phase 12: an unprompted opener can carry requiredFacts/
            // requiredEventTopic (e.g. the coverJob callback) same as a
            // reaction line — both need facts/recentConversation to actually
            // be checkable here, which this ctx never carried before.
            recentConversation: rel.recentConversation,
            facts: rel.facts,
            personality: p.personality,
            conversationDepth: rel.conversationDepth,
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
            // Same broadening as the reaction path above — an unprompted
            // line doesn't have to be a grammatical question to deserve a
            // tray built around exactly what Mama just said.
            if (line.questionId != null) {
              rel.pendingQuestionId = line.questionId;
            }
            // Phase 10: same wiring as the reaction path above, for a line
            // Mama sends unprompted rather than in reply to the player.
            if (line.requestsPromise) {
              _openPendingInteraction(
                rel,
                type: InteractionType.request,
                topic: line.topic,
                subject: line.subject,
                deadlineTurn: rel.turnCount + (line.promiseDeadlineTurns ?? kDefaultPromiseDeadlineTurns),
              );
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
    _sightingGapTimer?.cancel();
    _collectorGapTimer?.cancel();
    _level4GapTimer?.cancel();
    _strategicGapTimer?.cancel();
    _dayTimer?.cancel();
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
