// Rule-based dialogue selection engine. Pure Dart, no Flutter imports, no
// project imports — content-agnostic so it never needs to change as more
// characters/lines are added; only the data in data.dart grows.
import 'dart:math';

enum ReplyTone { warm, honest, vague, cold, excuse }

/// What the player's free text is trying to DO, independent of its tone.
enum Intent { question, promise, confession, dismissal, statement }

/// The DELIVERY register a specific phrasing is written in — distinct from
/// [ReplyTone] (the line's emotional valence, e.g. warm vs. cold) and from
/// [ConversationIntent]/[Intent] (WHAT the player is trying to do or say):
/// this is HOW it's said. The same [ConversationIntent.checkIn] can be sent
/// as "Hey mama, how you doing?" ([warm]), "What's up ma?" ([casual]), or
/// "You alive over there? 😂" ([funny]) — three phrasings of the identical
/// player action, not three different actions. Optional on [DialogueLine]
/// (`null` — most existing content — is simply unstyled, same as every
/// other line ever authored before this existed); read by [styleMatch] to
/// let [CharacterPersonality] bias which flavor of phrasing gets reached
/// for, the same way [humorMatch]/[warmthMatch]/[curiosityMatch]/
/// [patienceMatch] already bias other axes.
enum DialogueStyle { warm, casual, funny, short, affectionate, serious, playful }

/// Grows by adding cases — no engine change needed to add a new milestone kind.
enum MemoryKind {
  firstWarmReply,
  cutOff,
  heardAboutCutOff,
  heardAboutConfrontation,
  promiseMade, // [ConversationIntent.makePeace] resolved warmly — a commitment worth remembering past the short-term window
  deepConfession, // [ConversationIntent.confront]/[ConversationIntent.questionLoyalty] fired — a charged exchange, not small talk
  brokenPromise, // a promise/request's deadline passed unresolved — see [isOverdue]/`CareerController._breakOverdueInteractions` (Phase 10)
}

/// What the player is trying to communicate, independent of the exact words
/// used to say it — the chip the player taps in a personal thread (see
/// `IntentChip` in conversation/intents.dart) is always one of these.
/// Distinct from [Intent]: [Intent] is the narrower speech-act axis
/// ([pickLine] already used it for question/promise/confession/dismissal/
/// statement matching before intent chips existed) — a single
/// [ConversationIntent] like [insult] still resolves to one of those speech
/// acts once a specific line is picked. Kept as engine vocabulary (like
/// [Topic]/[MemoryKind]) because [ConversationEvent] — which the engine's
/// recall matching reads — needs to name it without depending on
/// conversation/intents.dart's content.
enum ConversationIntent {
  greet,
  checkIn,
  askAboutFamily,
  thank,
  compliment,
  apologize,
  sayGoodbye,
  askAboutWork,
  askWhatsGoingOn,
  askAboutSomeone,
  askForAdvice,
  askForHelp,
  joke,
  insult,
  confront,
  questionLoyalty,
  reassure,
  makePeace,
  sarcasm,
  congratulate,
  /// Continues whatever the conversation is actually on right now — the
  /// one intent that isn't about opening a topic but about answering
  /// "say more" / "tell me what you're thinking" once one's already live.
  /// Its phrasings (see conversation/intents.dart) are topic-tagged per
  /// [Topic] so [pickLine]'s topic-tiering (see pickLine's doc comment)
  /// always surfaces an answer that actually addresses what's live, not a
  /// content-free placeholder; CareerController._intentChipScore also gives
  /// it a large boost specifically when a thread is live or a question is
  /// pending, so it's present whenever the player would otherwise have
  /// nothing that flows.
  elaborate,
  /// The player declining to elaborate — the deliberate opposite number to
  /// [elaborate]: "I don't want to get into it right now" instead of "let me
  /// explain." Kept as its own intent/chip (see conversation/intents.dart's
  /// "Not Right Now") rather than folded into [elaborate]'s own phrasing pool
  /// so tapping "Explain More" always actually explains, and declining is a
  /// separate, explicit choice.
  deflect,
  // ── Phase 2 (see reply_tray.dart's `_storyContextChips`) ────────────────
  // Migrating the highest-specificity story-event chips off the generic
  // (tone, topic) pool onto their own isolated reaction pool each — see
  // `content/mama_reactions.dart`'s matching entries. These chips describe
  // one exact narrative beat ("I paid someone off today"), so pooling them
  // with dozens of unrelated same-topic/same-tone lines is exactly the
  // collision risk `intentMatch`/isolated `kMamaIntentReactions` buckets
  // exist to avoid (see the "Okay fine, I've been a little stressed"/
  // "Whatever's got you worried" bugs this was written to stop repeating).
  // `topic`/`tone` stay on each chip as secondary filters — pickLine still
  // reads them — but `intent` is what actually selects the reaction pool now.
  /// "Paid someone off" / "Had to grease someone" — the `recentStoryEvent ==
  /// 'bribed'` chips.
  admitBribe,
  /// "Close call" / "Shook up" / "Too close" — `recentStoryEvent ==
  /// 'close_call'`.
  reportCloseCall,
  /// "Something went right" / "Getting it done" / "Getting the hang of it"
  /// — `recentStoryEvent == 'run_success'`.
  reportSuccess,
  /// "Crossed a line" / "Not proud of it" / "Had to do it" —
  /// `recentStoryEvent == 'crossed_line'`.
  admitCrossedLine,
  /// "Had to get rough" / "Ugly situation" / "People push you" —
  /// `recentStoryEvent == 'crew_violence'`.
  admitViolence,
  /// "Someone pushed back" / "People are difficult" — `recentStoryEvent ==
  /// 'refused'`.
  reportPushback,
  /// "Team drama" / "Managing people" / "Trust issues" — `recentStoryEvent
  /// == 'crew_trouble'`.
  reportCrewTrouble,
  /// "Things are tense" / "People testing me" — `recentStoryEvent ==
  /// 'incursion'`.
  reportIncursion,
  /// "Messed up at work" / "Slipped up" — the level-1 `strikes > 0` chips;
  /// the flagship example this phase was built around.
  admitMistake,
  // ── Phase 3 — the rest of `_storyContextChips`'s clusters and the legacy
  // `kPersonalReplyActions` catalog (data.dart). Same rationale as Phase 2's
  // batch above; grouped one intent per CLUSTER (every chip in an `if`/
  // `case` block sharing one id, same as Phase 2), not one per literal
  // chip — several are reused directly by an existing intent above instead
  // of getting a new one here, wherever the register already matches (see
  // each PersonalReplyAction call site's own comment for which).
  /// "Can't sleep" / "Night thoughts" / "Wide awake" — the `TimeOfDay.night` cluster.
  reportCantSleep,
  /// "Big day ahead" / "Up early" — the `TimeOfDay.morning`, level>=2 cluster.
  reportBigDayAhead,
  /// "Long day" / "Finally breathing" / "Day done" — the `TimeOfDay.evening`
  /// cluster; also reused by "Slow day"/"Today was a lot" (section 8).
  reportLongDay,
  /// "Broke" / "Struggling financially" / "Debt stress" — the `cash < 300` cluster.
  reportBroke,
  /// "Doing well" / "Good stretch" / "Good week" — the `cash > 50000`/`cash >
  /// 8000` clusters; also reused by "Best month yet" (level 4).
  reportDoingWell,
  /// "Need to be careful" / "Heat is on" — the `policeHeat > 75` cluster;
  /// also reused by the level 5-7 `investigationStage > 0` cluster ("Under a
  /// microscope"/"Heat is serious"/"Got to lay low") — same "serious heat"
  /// register at two different story points.
  reportHeatHigh,
  /// "Watched" / "Something feels off" / "Eyes on me" — the `policeHeat > 50` cluster.
  reportFeelingWatched,
  /// "Know I messed up" / "Been distant" / "Trying to do better" — the
  /// `rel.mood < -20` cluster.
  admitPullingAway,
  /// "Been MIA" / "Sorry been quiet" / "Checked out for a bit" — the
  /// `rel.daysSinceReply > 2` cluster. Distinct from [admitPullingAway]: a
  /// timing lapse reads differently from an emotional one, even though both
  /// are apologetic.
  apologizeForGoingQuiet,
  /// "Work going okay" — level 1, `cleanWeeks >= 1`.
  reportWorkGoingOkay,
  /// "New job" — level 1, always shown.
  reportNewJob,
  /// "In the middle of something" / "Kind of tense right now" — level 2, `runStage != null`.
  tooBusyRightNow,
  /// "Long drives" / "Checkpoints" — level 2, always shown.
  reportJobRoutine,
  /// "Difficult people" / "Not everyone cooperates" — level 3, a refused/lost target.
  reportDifficultPeople,
  /// "Different stress" / "Going door to door" — level 3, always shown.
  reportFieldWorkStress,
  /// "Managing people" / "In charge now" — level 4, always shown.
  reportNewResponsibility,
  /// "In deep" / "Hard to separate" — level 5-7, always shown.
  admitInOverHead,
  /// "People around me" — level 5-7; also reused by "The people I'm around"
  /// (level 4 guilt/reflection) — same underlying disclosure at two levels.
  reportNewCrowd,
  /// "Reflecting" / "Who am I becoming" — level 4 guilt/reflection.
  admitSelfDoubt,
  /// "Worth it?" / "Point of no return" / "Carrying a lot" — level 5 guilt/reflection.
  admitDeepDoubt,
  /// "Just missed you" / "No reason" / "Had you on my mind" — the always-
  /// available deflection cluster's no-real-reason opener.
  reachOutNoReason,
  // ── Phase 3 — kPersonalReplyActions (data.dart's legacy catalog) ────────
  // NOTE: the generic, high-traffic entries (Greet, Reassure, Be honest, Ask
  // how they are, Ask about family, Push for answers, Stay vague, Make an
  // excuse, Brush off, Insult, Talk/Deflect about money, Check in)
  // deliberately have NO intent here and were never given one — see the
  // long comment at the top of kPersonalReplyActions (data.dart) for why:
  // isolating them would cut them off from the engine's cross-cutting
  // reactive machinery (dodge/toneShift/answeredQuestion acknowledgment,
  // requiredFacts, honesty/reliability gating, the questionId bespoke-tray
  // system) that lives only in the generic pool — confirmed by several
  // engine tests once tried. Only the mama-specific, narrower/level-gated
  // entries below got one.
  /// "Followed through" — the player reporting they kept a promise
  /// ([DialogueLine.fulfillsPromise]).
  reportFollowedThrough,
  /// "Make it right" — a repair move, only offered once mood's already low.
  makeItRight,
  /// "Tell her about your day" — an early-game, low-stakes daily update.
  tellAboutDay,
  /// "Share something good" — an early-game unprompted good-news share.
  shareGoodNews,
  /// "Change the subject" — actively redirecting onto Mama, distinct from
  /// [deflect] (declining to elaborate at all): this one still engages, just
  /// not on the original topic.
  changeSubject,
  /// "Deny everything" — flatly denying a suspicion once it's already high.
  denyEverything,
  /// "Come clean (a little)" — a partial, hedged admission.
  comeCleanPartially,
  /// "Open up" — a real, vulnerable disclosure ([DialogueLine.isVulnerableDisclosure]).
  openUp,
  /// "Keep her at a distance" — deliberately withholding to protect her.
  keepDistance,
  /// "Tell her you miss her" — late-game homesickness/longing.
  missHer,
  // ── Item 11: action chains ───────────────────────────────────────────
  // A [DialogueLine.questionId]-tagged Mama line can itself be answered by a
  // [kQuestionAnswerChips] chip whose OWN Mama-reply line carries a further
  // questionId — the tray-swap mechanism (items 2/6/7) already supports
  // this with no engine change; chaining is purely a content pattern. These
  // two are the "Ask About Uncle" worked example: narrow, one-off, chain-
  // specific replies, isolated the same way Phase 2's story-event chips
  // were (not generic/high-traffic — see the big NOTE a few entries up for
  // why THAT distinction matters).
  /// "Ask About Uncle" — reached from the `mama_uncle_back` bespoke tray.
  askAboutUncle,
  /// "Ask How Mama Is Doing" — reached from the `mama_uncle_stubborn`
  /// bespoke tray; its own reply converges the chain back into the
  /// EXISTING `mama_wellbeing_checkin` bespoke tray (item 2) rather than
  /// opening a new leaf — chains can merge, not just branch.
  askIfMamaIsOkay,
}

/// How far into the current story level the conversation is sitting, derived
/// from [CareerController.levelProgress] (or forced to [cusp] right after a
/// major story beat — see `CareerController.levelPhase`). Read by
/// [DialogueLine.phases] so a reaction can feel like it belongs to *now*
/// rather than to the level in the abstract ("you've been quiet about what's
/// really going on" only lands once there's something to be quiet about).
enum LevelPhase { opening, early, mid, late, cusp }

/// How long a [ConversationEvent] stays in [DialogueContext.recentConversation]
/// before it's pruned — see `CareerController._pruneConversationMemory` for
/// the eviction rule this actually drives (Phase 11): [low] survives ~3
/// turns, [medium] ~10 turns, [high] several days, [critical] permanently.
/// "lol" ([low]) shouldn't sit in the same window competing for space
/// against "I'm thinking about leaving the family" ([high]/[critical]) —
/// this is the axis that keeps them from doing that.
///
/// This is the "Recent" layer of the game's four-tier memory model, the
/// other three being existing structures rather than new ones:
/// - **Immediate** — this turn only, never persisted: [DialogueContext]
///   itself (`mood`, `recentTones.last`, `currentTopic`, `playerIntent`, …),
///   read once by [pickLine] and gone.
/// - **Recent** — [ConversationEvent] in `RelationshipState.recentConversation`,
///   this enum's own scope. A *kind* of thing was said ("askedAboutFamily,
///   tagged suspicion"), not its specific content, and it fades on the
///   schedule below.
/// - **Long-term** — [MemoryEvent]/[MemoryKind] in `RelationshipState.memories`
///   (milestones — see [recordMemory]/[memoryWeight]) and [ConversationFact]
///   in `RelationshipState.facts` (specific durable content, e.g. "brother's
///   name is Marcus" — see [recordFact]). Both survive past whatever prunes
///   [recentConversation]; a [critical]-importance turn is how one gets
///   promoted here (see `CareerController._permanentMemoryFor`).
/// - **Relationship** — the accumulated net effect, not a discrete memory of
///   any one thing: `RelationshipState`'s own stat fields (closeness, trust,
///   suspicion, mood, honesty, reliability, …). Nothing here ever points
///   back to which turn caused it; it's what she feels now, not what she
///   remembers happening.
enum MemoryImportance { low, medium, high, critical }

/// One turn of personal-thread conversation, kept in a short rolling window
/// (`RelationshipState.recentConversation`) so a reply can reference what was
/// just said instead of treating every turn as an isolated dialogue box. See
/// [recallMatch] for how [DialogueLine.requiresRecentIntent]/
/// [forbidsRecentIntent] read this list.
class ConversationEvent {
  final ConversationIntent? intent; // null for a legacy free-text/story-chip turn with no intent chip behind it
  final Topic? topic;
  final ReplyTone tone;
  final double intensity;
  final bool fromMe; // true = the player sent it; false = it's Mama's reply that turn
  final int turn; // RelationshipState.turnCount at the moment this was recorded — see recallWithinTurns
  final int day;
  final int level;
  final LevelPhase? phase;
  final bool dodged; // true if this turn dodged a pending question
  final MemoryImportance importance;
  ConversationEvent({
    this.intent,
    this.topic,
    required this.tone,
    required this.intensity,
    required this.fromMe,
    required this.turn,
    required this.day,
    required this.level,
    this.phase,
    this.dodged = false,
    this.importance = MemoryImportance.low,
  });
}

/// What a line is actually ABOUT, independent of its exact wording. Real
/// conversation rotates subject, not just phrasing — a mother who asks about
/// your health three times in a row feels scripted even if each line is
/// worded differently. Grows by adding cases, same as [MemoryKind]. Read by
/// [pickLine] via [topicMatch] (boosts a line that matches the conversation's
/// live topic) and by [DialogueLine.progressionMin]/[DialogueLine.progressionMax]
/// (gates a line to a stage of that topic thread) — see [advanceTopic] for how
/// the live topic and its progression stage are derived turn to turn.
/// [greeting] and [wellbeing] are conversational-move topics (what kind of
/// exchange this is) rather than subject-matter ones; the rest describe what
/// the exchange is actually about. [goodNews] is split out from [wellbeing]
/// on purpose — [wellbeing] is a check-in/hardship register ("you okay?",
/// "I'm managing"), while [goodNews] is a positive-update register
/// ("something went right"). Before the split, both lived under [wellbeing],
/// so topicMatch()'s 16x same-topic boost would just as happily surface a
/// hardship-flavored reply ("Stress happens, mijo...") to a thread that was
/// actually opened with good news, since the engine only tracks subject, not
/// valence — see kMamaIntentReactions[ConversationIntent.elaborate] for the
/// reply pool this was breaking.
enum Topic { family, health, money, plans, suspicion, affection, greeting, wellbeing, goodNews }

/// A discrete part of a relationship's day, driven by
/// [CareerController]'s relationship-tick counter rather than a wall clock —
/// this is a turn-based game, so "time of day" advances one segment every
/// time personal relationships get a beat (see `_tickPersonalRelationships`),
/// not on a real timer. Cycles morning → afternoon → evening → night → morning.
enum TimeOfDay { morning, afternoon, evening, night }

/// Pure function from a relationship-tick count to the [TimeOfDay] segment it
/// falls in.
TimeOfDay timeOfDayForTick(int tickCount) => TimeOfDay.values[tickCount % TimeOfDay.values.length];

/// Every 4 ticks (one full [TimeOfDay] cycle) counts as one "cycle day";
/// the last two of every 7 cycle-days are the weekend. Same tick-driven
/// logic as [timeOfDayForTick] — not tied to the real calendar.
bool isWeekendForTick(int tickCount) {
  final cycleDay = tickCount ~/ TimeOfDay.values.length;
  return cycleDay % 7 >= 5;
}

class MemoryEvent {
  final MemoryKind kind;
  final int day; // game day this was recorded — drives memoryWeight() recency decay
  const MemoryEvent(this.kind, this.day);
}

/// Appends [event] to [memories]. If [once], no-ops when a memory of the same
/// kind is already present (dedupes milestones so they're safe to record on
/// every qualifying turn — the dedupe key is [MemoryKind] only, not day).
/// Otherwise enforces [cap] via FIFO eviction.
void recordMemory(List<MemoryEvent> memories, MemoryEvent event, {bool once = false, int cap = 12}) {
  if (once && memories.any((m) => m.kind == event.kind)) return;
  memories.add(event);
  while (memories.length > cap) {
    memories.removeAt(0);
  }
}

/// What kind of thing is left hanging between Mama and the player — a
/// unified shape for three things that used to have no shared tracking at
/// all: [question] (Mama asked something — the one case that already had
/// its own single-slot tracking, [RelationshipState.lastQuestionAnswered]/
/// [resolvePendingQuestion], which this doesn't replace, see
/// [CareerController]'s `_openPendingInteraction`), [promise] (the player
/// committed to something via an [Intent.promise]-tagged reply — previously
/// tracked nowhere at all beyond the one-time [MemoryKind.promiseMade]
/// milestone), and [request] (someone asked for something concrete, e.g.
/// [CareerController.resolveMoneyAsk] — previously only implicit in that
/// flow's own bespoke outcome handling).
enum InteractionType { question, request, promise }

/// Something raised in conversation that hasn't been settled yet — created
/// when Mama asks something, the player promises something, or a concrete
/// request is made, and marked [resolved] once addressed (answered, granted/
/// refused, or otherwise closed out — "resolved" means "addressed", not
/// necessarily "satisfied": a refused request still resolves it). [topic]/
/// [subject] mirror [RelationshipState.topicSubject]'s finer-grained "what
/// specifically" — e.g. `type: question, topic: family, subject: 'Marcus'`
/// for "Did you talk to Marcus?" — so a later reply can eventually be
/// evaluated against what's actually still open, not just whether *a*
/// question of *some* kind is pending. [deadlineTurn] is compared against
/// [RelationshipState.turnCount] by [isOverdue] — see [CareerController]'s
/// `_breakOverdueInteractions` (Phase 10) for the caller that actually acts
/// on it, checked at the top of every reply to this contact (turnCount is
/// the only clock a deadline this shape can be compared against — nothing
/// advances it on a passive day/tick, so an overdue promise surfaces the
/// next time the player actually talks to them, not silently in the
/// background).
///
/// [broken] distinguishes HOW a resolved interaction was closed: [resolved]
/// alone only means "addressed" (see above — even a refused request
/// resolves), so a promise/request that lapsed past its deadline needs its
/// own flag to read as a failure rather than a success. Only meaningful once
/// [resolved] is true; a still-pending interaction is neither kept nor
/// broken yet. Not set for [InteractionType.question] — a dodged question
/// already has [RelationshipState.consecutiveDodgeCount]/
/// [nudgeSuspicionFromDodgePattern] as its own consequence path, and
/// "broken" reads oddly for a question anyway (nothing was promised).
///
/// This only tracks state — nothing in [pickLine]/[DialogueLine.isEligible]
/// reads it yet, the same disclosed gap as [RelationshipState.topicUnresolved]
/// before it. Wiring line selection to react to what's actually pending is
/// the natural next step, not done here.
class PendingInteraction {
  final InteractionType type;
  final Topic? topic;
  final String? subject;
  final int createdTurn;
  final int? deadlineTurn;
  bool resolved;
  bool broken;
  PendingInteraction({
    required this.type,
    this.topic,
    this.subject,
    required this.createdTurn,
    this.deadlineTurn,
    this.resolved = false,
    this.broken = false,
  });
}

/// True once [interaction]'s [PendingInteraction.deadlineTurn] has passed
/// without it being resolved — the trigger [CareerController].
/// `_breakOverdueInteractions` acts on. Pure predicate (no mutation), so it's
/// testable on its own rather than only through the controller's tick. An
/// interaction with no deadline, or one already resolved (kept, refused, or
/// previously broken), is never overdue — a strict `>` (not `>=`) so an
/// interaction is still on time on the turn its deadline actually falls on,
/// matching [PendingInteraction.deadlineTurn]'s doc comment ("the caller
/// checks turnCount against it").
bool isOverdue(PendingInteraction interaction, int currentTurn) {
  if (interaction.resolved) return false;
  final deadline = interaction.deadlineTurn;
  return deadline != null && currentTurn > deadline;
}

/// Default grace window (in [RelationshipState.turnCount] turns) a
/// promise/request gets before [isOverdue] considers it broken, for any
/// caller that doesn't specify its own (see [DialogueLine.promiseDeadlineTurns]
/// and `CareerController.personalReplyAction`'s player-initiated promise
/// path). Generous rather than tight — most promise-tagged content (e.g.
/// "Reassure") is a vague commitment, not a same-conversation task, so a
/// short window would make ordinary conversational pacing read as broken
/// promises.
const int kDefaultPromiseDeadlineTurns = 8;

/// A specific, keyed piece of information Mama actually knows about the
/// player — deliberately separate from [ConversationEvent]/
/// [RelationshipState.recentConversation]: that system remembers that a
/// *kind* of thing was said ("you used the elaborate intent, tagged
/// suspicion"), not the specific content of what it was. This is the other
/// half — "your brother's name is Marcus" — durable, keyed, and gone the
/// pruning short-term memory can't touch. [key]/[value] are both freeform
/// strings by design (`'brotherName' -> 'Marcus'`, `'worksNightShift' ->
/// 'true'`) rather than a typed enum, since the set of things a player could
/// establish isn't closed the way [Topic]/[MemoryKind] are.
class ConversationFact {
  final String key;
  final String value;
  double confidence;
  final int firstMentionedTurn;
  int lastConfirmedTurn;
  final bool important;
  ConversationFact({
    required this.key,
    required this.value,
    this.confidence = 1.0,
    required this.firstMentionedTurn,
    required this.lastConfirmedTurn,
    this.important = false,
  });
}

/// A fact that just replaced a different value under the same key —
/// [recordFact]'s correction branch, surfaced as its own event instead of
/// only being visible as a side effect on [RelationshipState.facts]. [key]
/// (not `subject`, despite Phase 8's original sketch using that word) to
/// match [ConversationFact.key] directly — this is about the same key, and
/// naming it differently here would read as a second, unrelated concept the
/// way [RelationshipState.topicSubject] already had to be renamed away from
/// bare `subject` to avoid colliding with [RelationshipState.resolved].
class ContradictionEvent {
  final String key;
  final String oldValue;
  final String newValue;
  final int turn;
  const ContradictionEvent({required this.key, required this.oldValue, required this.newValue, required this.turn});
}

/// Records that [key] = [value] was established on [turn], into [facts]
/// (keyed by [ConversationFact.key] — a player has exactly one current value
/// per key, not a history of every value ever claimed). Three cases:
/// - New key: inserted fresh, [ConversationFact.firstMentionedTurn] and
///   [ConversationFact.lastConfirmedTurn] both set to [turn]. Returns null.
/// - Same key, same value re-confirmed: [ConversationFact.lastConfirmedTurn]
///   advances and [ConversationFact.confidence] nudges up (capped at 1.0) —
///   saying the same thing twice makes it more certain, not less. Returns
///   null.
/// - Same key, DIFFERENT value: treated as a correction, not a fabrication —
///   people's circumstances change ('worksNightShift' flips when a job
///   does) as often as a line just being freshly authored gets it wrong.
///   The value is replaced, [ConversationFact.firstMentionedTurn] resets to
///   [turn] (a new claim starting its own history), and confidence resets to
///   a deliberately lower [correctionConfidence] rather than the full 1.0 a
///   brand-new fact gets — a claim that just contradicted a prior one
///   shouldn't read as equally certain on arrival. Returns the
///   [ContradictionEvent] describing the change, for a caller (see
///   [planResponse]) that wants to react to it.
ContradictionEvent? recordFact(
  Map<String, ConversationFact> facts,
  String key,
  String value,
  int turn, {
  bool important = false,
  double correctionConfidence = 0.7,
}) {
  final existing = facts[key];
  if (existing == null) {
    facts[key] = ConversationFact(
      key: key,
      value: value,
      firstMentionedTurn: turn,
      lastConfirmedTurn: turn,
      important: important,
    );
    return null;
  } else if (existing.value == value) {
    existing.lastConfirmedTurn = turn;
    existing.confidence = (existing.confidence + 0.1).clamp(0.0, 1.0);
    return null;
  } else {
    final oldValue = existing.value;
    facts[key] = ConversationFact(
      key: key,
      value: value,
      confidence: correctionConfidence,
      firstMentionedTurn: turn,
      lastConfirmedTurn: turn,
      important: important || existing.important,
    );
    return ContradictionEvent(key: key, oldValue: oldValue, newValue: value, turn: turn);
  }
}

/// How strongly a memory should still influence line selection: full weight
/// for the first 5 days, then decays linearly to a 0.1 floor by day 30.
double memoryWeight(MemoryEvent event, int currentDay) {
  final daysSince = currentDay - event.day;
  if (daysSince < 5) return 1.0;
  return max(0.1, 1.0 - (daysSince / 30));
}

/// Pushes [tone] onto [buf] (most-recent-last), trimmed to [capacity].
void pushRecentTone(List<ReplyTone> buf, ReplyTone tone, {int capacity = 5}) {
  buf.add(tone);
  while (buf.length > capacity) {
    buf.removeAt(0);
  }
}

// ── Behavioral reputation (Phase 9) ─────────────────────────────────────
// honesty/reliability/responsiveness are deliberately NOT nudged by a single
// turn's tone the way mood/trust/suspicion/fear/respect/debt already are
// (see nudgeMood/nudgeFear/nudgeRespect/nudgeDebt) — that's the entire point
// of the distinction: those respond to what THIS line was; these respond to
// a sustained PATTERN across several turns. A one-off honest reply shouldn't
// move honesty at all.
//
// Not built here, disclosed rather than silently skipped: irritation (no
// behavior rule was specified for it, and it would likely just duplicate
// mood/respect); a decay/penalty side for honesty (only the "repeatedly
// honest" half was specified — no rule for dishonesty was given, so none is
// invented); reliability's "broken" half (a promise going unresolved past
// some deadline) — PendingInteraction.deadlineTurn has been informational-
// only since Phase 4 and stays that way; only the "kept" half (explicit
// fulfillment) is wired this phase.

/// No-op below [threshold] — a single honest turn, or even two, isn't "the
/// player repeatedly tells the truth" yet. [recentHonestCount] is a
/// frequency count within [RelationshipState.recentTones]'s rolling window
/// (`.where((t) => t == ReplyTone.honest).length`), not a strict consecutive
/// streak — deliberately matching `warmthOffset`'s already-established
/// convention for "sustained pattern" in this exact codebase
/// (CareerController's periodic tick, not a new competing definition of
/// "repeated"). Meant to be called from that same tick, at that same small
/// per-tick [delta] (0.3-ish, not the full 1.0 a single dramatic turn might
/// earn elsewhere) — repeated calls while the pattern holds compound
/// naturally rather than needing a one-time-unlock flag.
double nudgeHonesty(double honesty, int recentHonestCount, {int threshold = 3, double delta = 0.3}) {
  if (recentHonestCount < threshold) return honesty;
  return (honesty + delta).clamp(0, 100);
}

/// [nudgeHonesty]'s mirror for a dodge PATTERN — not the same mechanism,
/// since a dodge isn't a [ReplyTone] and so can't reuse
/// [RelationshipState.recentTones] the way honesty does; a dodge is a
/// per-turn event (see [resolvePendingQuestion]'s `justDodged`), so this
/// reacts immediately off a simple consecutive counter
/// (RelationshipState.consecutiveDodgeCount) rather than waiting for the
/// next tick. [threshold] defaults lower than honesty's (2, not 3) —
/// repeated evasion reads as a pattern faster than repeated honesty needs
/// to, and suspicion already has plenty of single-turn signals feeding it
/// elsewhere, so this only adds the "this isn't the first time" layer on
/// top of those, not a replacement for them.
double nudgeSuspicionFromDodgePattern(double suspicion, int consecutiveDodgeCount, {int threshold = 2, double delta = 1.0}) {
  if (consecutiveDodgeCount < threshold) return suspicion;
  return (suspicion + delta).clamp(0, 100);
}

/// A promise actually fulfilled (see [PersonalReplyAction.fulfillsPromise]/
/// [DialogueLine.fulfillsPromise]) — not gated on a streak the way honesty
/// is, since "kept a promise" is inherently a discrete, one-off event
/// (there's no partial credit for a promise half-kept), unlike "has been
/// telling the truth," which is only meaningful as a sustained pattern.
double nudgeReliability(double reliability, {double delta = 1.0}) => (reliability + delta).clamp(0, 100);

/// How promptly the player replied, from [daysSinceReply] AT THE MOMENT OF
/// REPLYING (captured before RelationshipState.daysSinceReply resets to 0) —
/// same day or the next (<=1) reads as responsive, 3+ days (the same
/// threshold `_tickPersonalRelationships` uses before nudging toward
/// goneQuiet) reads as unresponsive. Anything in between (a normal gap, not
/// a pattern either way) is neutral — no nudge, same "don't move on a
/// non-signal" restraint as [nudgeHonesty] below its own threshold.
double nudgeResponsiveness(double responsiveness, int daysSinceReplyAtReplyTime, {double delta = 1.0}) {
  if (daysSinceReplyAtReplyTime <= 1) return (responsiveness + delta).clamp(0, 100);
  if (daysSinceReplyAtReplyTime >= 3) return (responsiveness - delta).clamp(0, 100);
  return responsiveness;
}

/// Moves [mood] a [rate] fraction of the way toward its fixed point
/// (`baselineAttraction / rate`, which is 0 for the default baseline of 0),
/// snapping to that fixed point once close enough so it doesn't drift forever
/// on float dust.
double decayMood(double mood, {double rate = 0.2, double baselineAttraction = 0}) {
  final next = mood * (1 - rate) + baselineAttraction;
  final fixedPoint = baselineAttraction / rate;
  return (next - fixedPoint).abs() < 0.5 ? fixedPoint : next;
}

/// One-shot delta applied on a player tone choice, clamped to [-100, 100].
/// [personalityModifier] scales the delta (see [personalityModifier]/formula
/// 9's PersonalityModifier) — defaults to 1.0, reproducing the old flat delta.
double nudgeMood(double mood, ReplyTone tone, {double personalityModifier = 1.0}) {
  final delta = switch (tone) {
    ReplyTone.warm => 18.0,
    ReplyTone.honest => 6.0,
    ReplyTone.vague => -4.0,
    ReplyTone.cold => -20.0,
    ReplyTone.excuse => -6.0,
  };
  return (mood + delta * personalityModifier).clamp(-100, 100);
}

/// Formula 9's PersonalityModifier: volatile characters (near 1.0) swing
/// close to double on mood deltas; stable characters (near 0.0) swing closer
/// to half.
double personalityModifier(double emotionalVolatility) => emotionalVolatility * 0.5 + 0.5;

/// Formula 11's BaselineAttraction: how far a character's mood drifts from 0
/// at rest, driven by their overall warmth (50 = neutral).
double baselineAttraction(double personalityWarmth) => (personalityWarmth - 50) / 100;

/// Formula 10's ImpactMultiplier: scales relationship-stat deltas by how
/// intensely a message was delivered.
double impactMultiplier(double intensity) => 0.5 + intensity * 0.5;

/// Formula 10's FearDelta: a harsh, high-intensity reply reads as
/// intimidating; a warm one reads as reassuring. Clamped 0–100.
double nudgeFear(double fear, ReplyTone tone, double intensity) {
  final delta = switch (tone) {
    ReplyTone.cold => 10 + 20 * intensity,
    ReplyTone.warm => -(5 + 10 * intensity),
    _ => 0.0,
  };
  return (fear + delta).clamp(0, 100);
}

/// Formula 10's RespectDelta: directness reads as competence, excuses read
/// as evasive. Clamped 0–100.
double nudgeRespect(double respect, ReplyTone tone, double intensity) {
  final delta = switch (tone) {
    ReplyTone.honest => 5 + 10 * intensity,
    ReplyTone.excuse => -(5 + 10 * intensity),
    _ => 0.0,
  };
  return (respect + delta).clamp(0, 100);
}

/// Formula 10's DebtDelta: fires only when the chosen reply option is
/// money-related (its own `isDebtTopic` flag — see [PersonalReplyAction]) —
/// deflecting reads as owing more, settling it warmly/honestly reads as
/// paying it down. No decay; debt is sticky.
double nudgeDebt(double debt, {required bool isDebtTopic, required ReplyTone tone}) {
  if (!isDebtTopic) return debt;
  final settling = tone == ReplyTone.warm || tone == ReplyTone.honest;
  return (debt + (settling ? -15 : 15)).clamp(0, 100);
}

/// moodSensitivity = 0 and trust/closeness = 0 reproduces the old flat-chance
/// behavior exactly — the compatibility guarantee for any character that
/// hasn't opted into mood- or relationship-modulated initiative (formula 12's
/// RelationshipModifier).
double effectiveInitiative(double baseInitiative, double mood, double moodSensitivity, {double trust = 0, double closeness = 0}) {
  final relationshipModifier = (trust + closeness) / 200 * 0.2;
  return (baseInitiative + (mood / 100) * moodSensitivity + relationshipModifier).clamp(0.0, 1.0);
}

/// Formula 15's relationship-type cascade — first match wins. Meridian has no
/// per-contact "Fear"/"Respect"/"Debt" axis outside personal relationships, so
/// this only applies to [DialogueContext]-style state that tracks them.
enum RelationshipType { love, respect, fear, trust, hatred, indebted, neutral }

RelationshipType detectRelationshipType({
  required double closeness,
  required double trust,
  required double fear,
  required double respect,
  required double debt,
}) {
  if (closeness > 80 && trust > 60) return RelationshipType.love;
  if (respect > 70 && trust > 50) return RelationshipType.respect;
  if (fear > 70 && trust < 40) return RelationshipType.fear;
  if (trust > 70 && fear < 30) return RelationshipType.trust;
  if (closeness < 20 && trust < 30) return RelationshipType.hatred;
  if (debt > 50) return RelationshipType.indebted;
  return RelationshipType.neutral;
}

// ── Response planning ───────────────────────────────────────────────────
// The engine used to go straight from a player action to weighted line
// selection: eligible lines → _finalWeight → pick. Every "what kind of
// moment is this" decision lived either as an implicit if/else ladder in
// CareerController.personalReplyAction (spam override → daily-repeat
// override → intent-specific pool → generic tone pool) or as a multiplicative
// nudge buried inside _finalWeight (dodgeMatch, recallMatch, toneShiftMatch).
// Nothing wrong with that as line-scoring — it's still exactly how a specific
// line gets picked once a pool is chosen — but nothing made "why this pool"
// an inspectable, testable decision on its own. planResponse() is that
// decision, made explicit and named, before any line search happens.

/// A read-only snapshot of RelationshipState's topic-tracking fields
/// (currentTopic/topicProgress/topicSubject/topicUnresolved/topicTurnsActive)
/// bundled into one object for callers — like [ResponsePlan] — that want to
/// hand one thing around instead of five. Not a new source of truth: those
/// loose fields on RelationshipState stay authoritative (see
/// RelationshipState.thread's doc comment for why they were never migrated
/// into this shape wholesale).
class ConversationThread {
  final Topic topic;
  final String? subject;
  final int stage;
  final int turnsActive;
  final bool unresolved;
  final bool playerInitiated;
  const ConversationThread({
    required this.topic,
    this.subject,
    this.stage = 1,
    this.turnsActive = 0,
    this.unresolved = true,
    this.playerInitiated = false,
  });
}

/// What kind of move Mama's reply is making — decided once, up front, by
/// [planResponse], instead of emerging from several independent signals all
/// fighting inside one weighted score. [answerQuestion] covers both
/// directions of a genuine question exchange: the player just answered
/// something Mama asked, or the player just asked Mama something directly
/// (chips like "Ask About Family" carry `primaryIntent: Intent.question`) —
/// either way her reply has to actually engage with a question, not just
/// continue in whatever register was already live.
enum ResponseIntent {
  answerQuestion,
  acknowledge,
  followUp,
  continueTopic,
  callback,
  challenge,
  comfort,
  joke,
  apologize,
  changeTopic,
  closeConversation,
  /// A genuinely new addition, not one of Phase 5's original 11 — added in
  /// Phase 8 because a contradiction's "ask for clarification" outcome (see
  /// [planResponse]) has no honest home among the other ten: it isn't
  /// [challenge] (that's an accusation, not a confused double-check) and
  /// isn't [answerQuestion] (that's the reverse direction — Mama answering,
  /// not Mama asking). Forcing it into an ill-fitting bucket the way
  /// [ConversationIntent.makePeace]/[insult] were folded into [comfort]/
  /// [challenge] would have made [ResponseIntent.challenge]'s own meaning
  /// blurrier for every other caller, not just this one.
  clarify,
}

/// The output of [planResponse] — what CareerController.personalReplyAction
/// consults before searching for a line, the same way it already consults
/// [DialogueContext.toneShift] to narrow to shift-acknowledging lines first.
/// [topic]/[thread] are carried along for a future line-search step to read
/// without re-deriving them; today only [intent] actually changes which
/// lines get considered (see [DialogueLine.acknowledgesAnsweredQuestion]).
class ResponsePlan {
  final ResponseIntent intent;
  final Topic? topic;
  final ConversationThread? thread;
  /// Set only on the turn a [ContradictionEvent] actually fired and drove
  /// [intent] — see [planResponse]'s contradiction-handling tier. Carried
  /// along so a caller picking reaction content knows not just THAT this is
  /// a challenge/acknowledge/clarify moment but specifically which fact
  /// contradicted which prior value.
  final ContradictionEvent? contradiction;
  const ResponsePlan({required this.intent, this.topic, this.thread, this.contradiction});
}

/// Decides [ResponsePlan.intent] from this turn's signals, in priority order:
///
/// 1. A handful of [ConversationIntent] values are specific/loaded enough to
///    always win outright — being confronted, apologized to, or told a joke
///    is never actually "just answering a question" even if one happens to
///    be pending at the same time, or a fact happens to have just
///    contradicted an earlier one.
/// 2. [contradiction], if one just fired — see the weighted pick below.
/// 3. A genuine question exchange, either direction (see [ResponseIntent]'s
///    own doc comment) — outranks generic topic continuation.
/// 4. [ConversationIntent.elaborate]/[ConversationIntent.deflect] — the two
///    intents that are explicitly ABOUT continuing (or declining to
///    continue) whatever's already live, so they're checked before the
///    weaker state-driven fallback below.
/// 5. State-driven fallback, for legacy actions (no ConversationIntent) and
///    every ConversationIntent not covered above (greet, checkIn, thank,
///    compliment, congratulate, askAboutFamily/Work/Someone,
///    askForAdvice/Help — none of these carry a sharper signal than "the
///    conversation is continuing"): a topic switch, a live callback
///    opportunity, or deepening the existing thread, in that order, falling
///    through to [ResponseIntent.acknowledge] when none apply.
///
/// [ConversationIntent.makePeace]/[ConversationIntent.reassure] map to
/// [ResponseIntent.comfort] and [ConversationIntent.insult]/[sarcasm] map to
/// [ResponseIntent.challenge] — the closest fit among the 12 values, not a
/// perfect 1:1; [ResponseIntent] doesn't have a slot for every
/// [ConversationIntent] and was never going to.
///
/// A [contradiction] doesn't resolve to one fixed [ResponseIntent] — Mama
/// might call it out, accept it, or ask for clarification, and forcing a
/// single deterministic answer would make every "your job changed" moment
/// play out identically. [rng] weighs the three outcomes 30/40/30
/// (challenge/acknowledge/clarify) — optional and defaulting to a fresh
/// [Random] (same pattern as CareerController's own constructor) since
/// every caller before this one had no randomness to inject and shouldn't
/// need to start now just because [contradiction] happens to be unset for
/// them.
ResponsePlan planResponse({
  required ConversationIntent? actionIntent,
  required bool questionJustAnswered,
  required bool questionJustAsked,
  required ConversationThread? thread,
  required bool topicJustChanged,
  required bool hasCallbackOpportunity,
  ContradictionEvent? contradiction,
  Random? rng,
}) {
  ResponsePlan plan(ResponseIntent intent) =>
      ResponsePlan(intent: intent, topic: thread?.topic, thread: thread, contradiction: contradiction);

  switch (actionIntent) {
    case ConversationIntent.confront:
    case ConversationIntent.questionLoyalty:
    case ConversationIntent.insult:
    case ConversationIntent.sarcasm:
      return plan(ResponseIntent.challenge);
    case ConversationIntent.apologize:
      return plan(ResponseIntent.apologize);
    case ConversationIntent.joke:
      return plan(ResponseIntent.joke);
    case ConversationIntent.sayGoodbye:
      return plan(ResponseIntent.closeConversation);
    case ConversationIntent.makePeace:
    case ConversationIntent.reassure:
      return plan(ResponseIntent.comfort);
    default:
      break;
  }

  if (contradiction != null) {
    final r = (rng ?? Random()).nextDouble();
    final outcome = r < 0.3 ? ResponseIntent.challenge : (r < 0.7 ? ResponseIntent.acknowledge : ResponseIntent.clarify);
    return plan(outcome);
  }

  if (questionJustAnswered || questionJustAsked) return plan(ResponseIntent.answerQuestion);
  if (actionIntent == ConversationIntent.elaborate) return plan(ResponseIntent.followUp);
  if (actionIntent == ConversationIntent.deflect) return plan(ResponseIntent.acknowledge);

  if (topicJustChanged) return plan(ResponseIntent.changeTopic);
  if (hasCallbackOpportunity) return plan(ResponseIntent.callback);
  if (thread != null && thread.unresolved && thread.stage > 1) return plan(ResponseIntent.continueTopic);
  return plan(ResponseIntent.acknowledge);
}

// ── Line selection ──────────────────────────────────────────────────────

/// A character's stable behavioral profile (Phase 15) — biases WHICH lines
/// [pickLine] reaches for, not a parallel dialogue engine per character. Each
/// axis feeds its own small multiplier into [_finalWeight] (see
/// [humorMatch]/[curiosityMatch]/[warmthMatch]/[patienceMatch]) the exact
/// same way [toneMatch]/[topicMatch] already do — "your existing weight and
/// _finalWeight() architecture is perfect for this" was the brief, so this
/// adds terms to that one formula rather than branching content per contact.
///
/// Every axis is 0-100, 50 = neutral (no bias either way), matching the
/// convention [RelationshipState.honesty]/[reliability]/[responsiveness]
/// already established for "a trait being measured" rather than an
/// absence-based 0 default.
///
/// Distinct from `PersonalContact`'s existing `personalityWarmth`/
/// `emotionalVolatility` (data.dart), which drive MOOD DYNAMICS
/// ([baselineAttraction]/[personalityModifier]) — [warmth] here drives LINE
/// SELECTION instead. A character can drift toward a warm mood baseline
/// without that same warmth making a comforting LINE more likely to be
/// picked, which is why this is its own axis rather than double-booking
/// `personalityWarmth`.
///
/// [strictness]/[sarcasm]/[directness]/[talkativeness] are carried but not
/// yet wired into a multiplier — no concrete selection rule was specified
/// for them yet, the same disclosed-not-invented gap Phase 9's own doc
/// comment models (see `nudgeHonesty`'s doc comment).
class CharacterPersonality {
  final double warmth, humor, patience, curiosity, strictness, sarcasm, directness, talkativeness;
  const CharacterPersonality({
    this.warmth = 50,
    this.humor = 50,
    this.patience = 50,
    this.curiosity = 50,
    this.strictness = 50,
    this.sarcasm = 50,
    this.directness = 50,
    this.talkativeness = 50,
  });
}

/// Every axis at 50 — the default for a contact with no authored
/// [CharacterPersonality], and for a [DialogueContext] built before this
/// field existed. Every [_finalWeight] personality multiplier evaluates to
/// exactly 1.0 (no-op) against this, so nothing already-shipped is affected
/// by its absence.
const kNeutralPersonality = CharacterPersonality();

/// Everything a [DialogueLine.when] predicate (or declarative gate) might
/// need to decide eligibility.
class DialogueContext {
  final double mood, closeness, trust, suspicion;
  final int daysSinceReply;
  final List<ReplyTone> recentTones; // most-recent-last
  final List<MemoryEvent> memories;
  final TimeOfDay timeOfDay;
  final bool isWeekend;
  final Topic? currentTopic; // the topic this conversation thread is presently on — see advanceTopic()
  final int topicProgress; // turns spent on currentTopic; 0 when there's no active thread
  /// Finer-grained "what specifically" within [currentTopic] — mirrors
  /// `RelationshipState.topicSubject` (see its own doc comment). Read by
  /// [DialogueLine.isEligible] for [DialogueLine.requiredSubject] (Phase 12).
  /// Absent from every call site written before that gate existed — `null`
  /// there is indistinguishable from "no subject is currently live," which is
  /// the correct read for a caller that was never in a position to have one.
  final String? topicSubject;
  final Set<Topic> playerTopics; // topics detected in the player's current message, if any
  final Intent? playerIntent; // the current message's intent, if any (e.g. Intent.question)
  final bool questionJustDodged; // true for exactly the turn where the player dismissed a pending question
  final bool questionJustAnswered; // true for exactly the turn a pending question got a genuine (non-dodge) reply
  final bool toneShift; // true for exactly the turn the player's tone changed from their immediately prior one
  /// Topics the player mentioned at any point during this game day. Populated
  /// from [RelationshipState.topicsDiscussedToday] and cleared each morning
  /// tick. Lets opener lines ask follow-up questions about earlier parts of
  /// the conversation without needing a custom event system.
  final Set<Topic> playerTopicsToday;
  /// How many times in a row the player sent the same action — used to gate
  /// escalating spam-reaction lines so they only surface at higher counts.
  final int consecutiveActionCount;
  /// How deep into the current story level this turn is happening — see
  /// [LevelPhase]. Read by [phaseMatch]; `null` (the default for every call
  /// site that predates intent chips) is always neutral, never a mismatch.
  final LevelPhase? levelPhase;
  /// Short rolling window of recent personal-thread turns — see
  /// [ConversationEvent] and `RelationshipState.recentConversation`. Read by
  /// [recallMatch]. Defaults empty, which makes every recall gate neutral —
  /// existing call sites that don't pass this see no behavior change.
  final List<ConversationEvent> recentConversation;
  /// Keyed facts Mama currently knows about the player — see
  /// [ConversationFact] and `RelationshipState.facts`. Read by
  /// [DialogueLine.isEligible] for [DialogueLine.requiredFacts]. Defaults
  /// empty, which makes every fact gate fail closed (a line requiring a fact
  /// stays ineligible until one exists) rather than neutral — unlike a
  /// missing memory/recall signal, a required fact genuinely can't be
  /// treated as "doesn't matter" without changing what the gate means.
  final Map<String, ConversationFact> facts;
  /// Behavioral-reputation axes (Phase 9) — see RelationshipState's own
  /// fields and nudgeHonesty/nudgeReliability/nudgeResponsiveness for how
  /// they move. Default to 50, matching RelationshipState's own starting
  /// value (neutral — nothing observed yet), not 0 — these are traits being
  /// measured, the same convention trust/closeness already use, unlike
  /// suspicion/fear/respect/debt's absence-based 0 default.
  final double honesty, reliability, responsiveness;
  /// This contact's stable behavioral profile (Phase 15) — see
  /// [CharacterPersonality]'s own doc comment. Defaults to
  /// [kNeutralPersonality] (every axis 50), under which every personality
  /// multiplier in [_finalWeight] is a no-op — existing call sites that
  /// don't pass this see no behavior change.
  final CharacterPersonality personality;
  /// How emotionally deep the conversation is running right now (Phase 16) —
  /// see [ConversationDepth]'s own doc comment. Defaults to
  /// [ConversationDepth.smallTalk], matching `RelationshipState.
  /// conversationDepth`'s own starting value for a thread that hasn't said
  /// anything yet.
  final ConversationDepth conversationDepth;
  const DialogueContext({
    required this.mood,
    required this.closeness,
    required this.trust,
    required this.suspicion,
    required this.daysSinceReply,
    required this.recentTones,
    required this.memories,
    this.honesty = 50,
    this.reliability = 50,
    this.responsiveness = 50,
    this.timeOfDay = TimeOfDay.morning,
    this.isWeekend = false,
    this.currentTopic,
    this.topicProgress = 0,
    this.topicSubject,
    this.playerTopics = const {},
    this.playerIntent,
    this.questionJustDodged = false,
    this.questionJustAnswered = false,
    this.toneShift = false,
    this.playerTopicsToday = const {},
    this.consecutiveActionCount = 0,
    this.levelPhase,
    this.recentConversation = const [],
    this.facts = const {},
    this.personality = kNeutralPersonality,
    this.conversationDepth = ConversationDepth.smallTalk,
  });

  bool hasMemory(MemoryKind k) => memories.any((m) => m.kind == k);
  int countRecentTone(ReplyTone t) => recentTones.where((x) => x == t).length;
  bool hasTopicToday(Topic t) => playerTopicsToday.contains(t);
}

/// A single candidate line. [when] stays as an escape hatch for compound
/// logic (recent-tone counts, ORs, etc.) the declarative gates below can't
/// express; both apply — a line is eligible only when [when] AND every
/// declarative gate pass (formulas 4/6's ConditionMatch/MemoryMatch, which
/// are binary 1.0/0.0 despite the "Match" name).
class DialogueLine {
  final String text;
  final bool Function(DialogueContext ctx) when;
  final double weight;
  final Topic? topic;
  final double? moodMin, moodMax, trustMin, trustMax, suspicionMin, suspicionMax;
  final double? closenessMin, closenessMax; // same shape as the other stat gates — closeness was the one RelationshipState axis isEligible() never checked
  /// Same shape as the stat gates above, for Phase 9's behavioral-reputation
  /// axes (RelationshipState.honesty/reliability/responsiveness) — a line
  /// that only makes sense once the player has actually earned a reputation
  /// for something, e.g. honestyMin gating a line that says "you've always
  /// been straight with me."
  final double? honestyMin, honestyMax, reliabilityMin, reliabilityMax, responsivenessMin, responsivenessMax;
  /// Eligible once ANY listed [MemoryKind] is present — not all of them.
  /// Named `any...` rather than plain `requiredMemories` because "required"
  /// on a set reads as AND to most people; this is OR, same as
  /// [forbiddenMemories] below (which the same reading happens to get
  /// right — "forbidden if any of these" already matches how it behaves).
  final Set<MemoryKind>? anyRequiredMemories;
  final Set<MemoryKind>? forbiddenMemories;
  final ReplyTone? tone; // this line's own emotional register, used by ToneMatch
  /// This line IS a joke/playful aside — read by [humorMatch] (Phase 15) to
  /// boost it for a high-[CharacterPersonality.humor] character. No existing
  /// tag ([tone]/[intent]/[topic]) captures "this specific line is playful"
  /// on its own, so this is a new, narrow, single-purpose flag rather than
  /// overloading one of those — the same reasoning [requestsPromise] (Phase
  /// 10) and [acknowledgesDodge] (Phase 3) were each added for their own
  /// single purpose instead of folding into a broader existing field.
  final bool isJoke;
  /// This line/phrasing IS a raw, first-time disclosure — e.g. "I haven't
  /// told anyone this." Read by [classifyDepth] (Phase 16), the same
  /// single-purpose-flag reasoning as [isJoke]: not derivable from
  /// [topic]/[tone]/an intensity value the way the other [ConversationDepth]
  /// tiers are, so content that means it says so directly. Forwarded from a
  /// chosen [DialogueLine] to the synthesized [PersonalReplyAction] the same
  /// way [subject]/[fulfillsPromise] already are (see `CareerController.
  /// sendIntent`) — the actual classification reads
  /// [PersonalReplyAction.isVulnerableDisclosure], this is a legacy pool's
  /// self-initiated equivalent to declare it too.
  final bool isVulnerableDisclosure;
  final Set<TimeOfDay>? timesOfDay; // null = any time of day
  final bool? requireWeekend; // null = no constraint; true = weekend only; false = weekday only
  final Intent? intent; // the player intent this line is meant to address, used by intentMatch
  final int? progressionMin, progressionMax; // gates a line to a stage of the [topic] thread — see advanceTopic()
  /// Gates this line to a range of [DialogueContext.conversationDepth]
  /// (Phase 16) — same shape as [progressionMin]/[progressionMax], just
  /// against [ConversationDepth.index] instead of [topicProgress]. The
  /// stated purpose: a raw, [ConversationDepth.vulnerable]-gated response
  /// (`minDepth: ConversationDepth.vulnerable`) can't surface during
  /// ordinary small talk, and a light aside (`maxDepth:
  /// ConversationDepth.casual`) can't surface once things have turned
  /// serious.
  final ConversationDepth? minDepth, maxDepth;
  final bool acknowledgesDodge; // fits a reply to a just-dismissed pending question, used by dodgeMatch
  final bool acknowledgesToneShift; // fits a reply that notices the player's tone just changed, used by toneShiftMatch
  /// Fits a reply that specifically notices a pending question just got a
  /// genuine (non-dodge) answer — [acknowledgesDodge]'s mirror image, scored
  /// (not pool-narrowed — see [answeredQuestionMatch]'s doc comment for why)
  /// via [answeredQuestionMatch].
  final bool acknowledgesAnsweredQuestion;
  /// Restricts this line to specific [LevelPhase]s (e.g. a line that only
  /// makes sense once a level is wrapping up) — see [phaseMatch]. `null` (the
  /// default) means every phase.
  final Set<LevelPhase>? phases;
  /// This line only makes sense as a callback — it's suppressed hard unless
  /// [ConversationIntent] appears in [DialogueContext.recentConversation]
  /// within the last [recallWithinTurns] turns (or ever, if that's null). See
  /// [recallMatch]. Mutually exclusive in practice with [forbidsRecentIntent],
  /// though nothing stops setting both.
  final ConversationIntent? requiresRecentIntent;
  /// The mirror of [requiresRecentIntent] — this line is suppressed hard when
  /// that intent WAS recently raised (e.g. don't re-ask something already
  /// just answered).
  final ConversationIntent? forbidsRecentIntent;
  final int? recallWithinTurns;
  /// Finer-grained "what specifically" within [topic] — see
  /// [PersonalReplyAction.subject]'s doc comment for the full rationale.
  /// Read only when Mama raises a topic unprompted (a self-initiated line
  /// carrying [topic] sets RelationshipState.topicSubject to this); a line
  /// picked as a same-turn reaction doesn't touch it — the player's own
  /// action already drove that via advanceTopic().
  final String? subject;
  /// The mirror of [PersonalReplyAction.resolvesThread] for a self-initiated
  /// line: true if Mama raising this closes out the topic/subject as already
  /// addressed rather than opening it as newly pending.
  final bool resolvesThread;
  /// Hard-gates this line to [RelationshipState.facts] — eligible only when
  /// EVERY entry here matches a fact Mama currently holds with that exact
  /// value (AND semantics: a Map naturally reads as "all of these", unlike
  /// [anyRequiredMemories]'s Set, which is why that one needed the `any`
  /// prefix to read correctly and this one doesn't). `{'brotherName':
  /// 'Marcus'}` only fires once Mama actually knows the brother's name is
  /// Marcus — see [PersonalReplyAction.establishesFacts]/this class's own
  /// [establishesFacts] for how a fact gets known in the first place.
  final Map<String, String>? requiredFacts;
  /// The mirror of [PersonalReplyAction.establishesFacts] for a self-
  /// initiated line — see its doc comment. Not read for a same-turn reaction
  /// line the way [subject] isn't either; the player's own action drives
  /// what gets recorded.
  final Map<String, String>? establishesFacts;
  /// The mirror of [PersonalReplyAction.fulfillsPromise] for a self-
  /// initiated line. See its doc comment — resolving a promise as KEPT is
  /// the only half of reliability tracking Phase 9 wires; a promise going
  /// unresolved past some deadline (the "broken" half) stays unbuilt.
  final bool fulfillsPromise;
  /// True if this line asks the player to commit to something concrete —
  /// e.g. "Promise me you'll call your grandma." (Phase 10). Opens an
  /// [InteractionType.request] [PendingInteraction] (see
  /// `CareerController.personalReplyAction`/`_tickPersonalRelationships`,
  /// the same two spots that already open one for [Intent.question]), using
  /// [subject]/[topic] as what's being asked for. [PersonalReplyAction.
  /// fulfillsPromise] resolves it the same way it resolves a player-made
  /// promise — from the player's side, following through on what Mama asked
  /// for and following through on what they themselves promised read as the
  /// same act, so one flag closes either.
  final bool requestsPromise;
  /// Overrides [kDefaultPromiseDeadlineTurns] for this specific request —
  /// null (the default) uses the shared default. Only meaningful alongside
  /// [requestsPromise].
  final int? promiseDeadlineTurns;
  /// Hard-gates this line to [DialogueContext.recentConversation] (Phase
  /// 12): eligible only when some turn in that window carries this [Topic].
  /// The [requiresRecentIntent] callback mechanism already answers "did the
  /// player recently do X" by [ConversationIntent]; this answers "was this
  /// SUBJECT MATTER recently on the table at all" by [Topic] instead —
  /// coarser than an intent match, but usable by content that doesn't care
  /// which specific intent raised it, only that it did. Not turn-windowed
  /// the way [recallWithinTurns] bounds [requiresRecentIntent] — Phase 11's
  /// own importance-tiered pruning already keeps [recentConversation]
  /// relevance-bounded (a family-topic turn ages out on its own schedule),
  /// so a second window here would just be redundant tuning of the same
  /// knob from a different angle. A hard gate, not a soft recallMatch boost
  /// like [requiresRecentIntent]: paired with [requiredFacts] (see its own
  /// doc comment's `{'brotherName': 'Marcus'}` example), a line that NAMES
  /// something specific is wrong to fire at all if the setup was never
  /// there, not just less likely to.
  final Topic? requiredEventTopic;
  /// Hard-gates this line to [DialogueContext.topicSubject] (Phase 12):
  /// eligible only when the conversation thread is CURRENTLY, right now, on
  /// this exact subject — e.g. `'brother'` for a callback that only makes
  /// sense while the brother subthread specifically is live, not just
  /// [Topic.family] in general. Distinct from [requiredEventTopic] the same
  /// way [DialogueContext.topicSubject] is distinct from
  /// [DialogueContext.recentConversation]: this reads the live thread's
  /// present state, not conversation history — see
  /// `RelationshipState.topicSubject`'s own doc comment for why a bare
  /// [Topic] can't tell "the brother" apart from "the aunt" within
  /// [Topic.family] on its own.
  final String? requiredSubject;
  /// Identifies WHICH specific thing Mama just said — e.g.
  /// `'mama_wellbeing_checkin'` for every phrasing of "how are you / how was
  /// your day," `'mama_suspicion_distant'` for every phrasing of "something
  /// feels off with you," `'mama_brother_distant'` for "you haven't called
  /// your brother, everything okay?" Several differently-worded lines can
  /// (and should) share the same id when they're getting at the same
  /// underlying thing — this identifies what was RAISED, not the exact
  /// sentence, and despite the name isn't limited to lines tagged
  /// [Intent.question]: a loaded STATEMENT deserves a tray built around what
  /// was actually said just as much as a literal question does (`intent`
  /// only additionally decides whether it also opens a dodge-tracked
  /// `PendingInteraction` — see `CareerController`'s two call sites, which
  /// set `RelationshipState.pendingQuestionId` off this field unconditionally
  /// but only flip `lastQuestionAnswered`/open the interaction when `intent
  /// == Intent.question`). `conversation/reply_tray.dart`'s
  /// `personalReplyOptions` reads `pendingQuestionId` to look up
  /// `kQuestionAnswerChips` (conversation/intents.dart) — a bespoke set of
  /// reply chips for exactly what was raised, replacing the generic
  /// Explain-More/Not-Right-Now tray for the turn (this is the tray
  /// responding to Mama's exact last line + thread + relationship state,
  /// not just `currentTopic`). `null` (every line with no dedicated chips
  /// authored) falls back to that generic tray exactly as before this field
  /// existed.
  final String? questionId;
  /// This phrasing's delivery register — see [DialogueStyle]'s own doc
  /// comment. `null` (every line authored before this field existed, and
  /// most content going forward) means unstyled, exactly as before: neutral
  /// under [styleMatch], no behavior change.
  final DialogueStyle? style;
  const DialogueLine(
    this.text, {
    this.when = _alwaysTrue,
    this.weight = 1.0,
    this.topic,
    this.moodMin,
    this.moodMax,
    this.trustMin,
    this.trustMax,
    this.suspicionMin,
    this.suspicionMax,
    this.closenessMin,
    this.closenessMax,
    this.honestyMin,
    this.honestyMax,
    this.reliabilityMin,
    this.reliabilityMax,
    this.responsivenessMin,
    this.responsivenessMax,
    this.anyRequiredMemories,
    this.forbiddenMemories,
    this.tone,
    this.timesOfDay,
    this.requireWeekend,
    this.intent,
    this.progressionMin,
    this.progressionMax,
    this.acknowledgesDodge = false,
    this.acknowledgesToneShift = false,
    this.acknowledgesAnsweredQuestion = false,
    this.phases,
    this.requiresRecentIntent,
    this.forbidsRecentIntent,
    this.recallWithinTurns,
    this.subject,
    this.resolvesThread = false,
    this.requiredFacts,
    this.establishesFacts,
    this.fulfillsPromise = false,
    this.requestsPromise = false,
    this.promiseDeadlineTurns,
    this.requiredEventTopic,
    this.requiredSubject,
    this.isJoke = false,
    this.isVulnerableDisclosure = false,
    this.minDepth,
    this.maxDepth,
    this.questionId,
    this.style,
  });
  static bool _alwaysTrue(DialogueContext ctx) => true;

  bool isEligible(DialogueContext ctx) {
    if (!when(ctx)) return false;
    if (moodMin != null && ctx.mood < moodMin!) return false;
    if (moodMax != null && ctx.mood > moodMax!) return false;
    if (trustMin != null && ctx.trust < trustMin!) return false;
    if (trustMax != null && ctx.trust > trustMax!) return false;
    if (suspicionMin != null && ctx.suspicion < suspicionMin!) return false;
    if (suspicionMax != null && ctx.suspicion > suspicionMax!) return false;
    if (closenessMin != null && ctx.closeness < closenessMin!) return false;
    if (closenessMax != null && ctx.closeness > closenessMax!) return false;
    if (honestyMin != null && ctx.honesty < honestyMin!) return false;
    if (honestyMax != null && ctx.honesty > honestyMax!) return false;
    if (reliabilityMin != null && ctx.reliability < reliabilityMin!) return false;
    if (reliabilityMax != null && ctx.reliability > reliabilityMax!) return false;
    if (responsivenessMin != null && ctx.responsiveness < responsivenessMin!) return false;
    if (responsivenessMax != null && ctx.responsiveness > responsivenessMax!) return false;
    if (anyRequiredMemories != null && !anyRequiredMemories!.any(ctx.hasMemory)) return false;
    if (forbiddenMemories != null && forbiddenMemories!.any(ctx.hasMemory)) return false;
    if (timesOfDay != null && !timesOfDay!.contains(ctx.timeOfDay)) return false;
    if (requireWeekend != null && requireWeekend != ctx.isWeekend) return false;
    if (progressionMin != null && ctx.topicProgress < progressionMin!) return false;
    if (progressionMax != null && ctx.topicProgress > progressionMax!) return false;
    if (minDepth != null && ctx.conversationDepth.index < minDepth!.index) return false;
    if (maxDepth != null && ctx.conversationDepth.index > maxDepth!.index) return false;
    if (phases != null && ctx.levelPhase != null && !phases!.contains(ctx.levelPhase)) return false;
    if (requiredFacts != null) {
      for (final entry in requiredFacts!.entries) {
        if (ctx.facts[entry.key]?.value != entry.value) return false;
      }
    }
    if (requiredEventTopic != null && !ctx.recentConversation.any((e) => e.topic == requiredEventTopic)) return false;
    if (requiredSubject != null && ctx.topicSubject != requiredSubject) return false;
    return true;
  }
}

// Direct opposites score 0.0 alignment (ToneMatch 1.0, no boost); an exact
// match scores 1.0 (ToneMatch 1.3); everything else that isn't an exact match
// scores 0.5 (ToneMatch 1.15). This reproduces the spec's own worked example
// (player warm, response tagged vague -> 1.15x) even though that contradicts
// the spec's stated alignment table, which doesn't list warm/vague as
// "similar" — the worked example is treated as authoritative since it's the
// only unambiguous data point.
const Set<(ReplyTone, ReplyTone)> _oppositeTonePairs = {
  (ReplyTone.warm, ReplyTone.cold),
  (ReplyTone.cold, ReplyTone.warm),
  (ReplyTone.honest, ReplyTone.excuse),
  (ReplyTone.excuse, ReplyTone.honest),
};

double _toneAlignment(ReplyTone player, ReplyTone response) {
  if (player == response) return 1.0;
  if (_oppositeTonePairs.contains((player, response))) return 0.0;
  return 0.5;
}

/// Formula 3's ToneMatch. Neutral (1.0, no boost) when the line carries no
/// tone tag or the player hasn't sent anything yet.
double toneMatch(ReplyTone? lineTone, List<ReplyTone> recentPlayerTones) {
  if (lineTone == null || recentPlayerTones.isEmpty) return 1.0;
  return 1.0 + 0.3 * _toneAlignment(recentPlayerTones.last, lineTone);
}

/// Neutral (1.0, no boost) when the line carries no topic tag. A line whose
/// topic matches what the conversation thread is presently on scores
/// highest (continuity); one that matches a topic freshly raised in the
/// player's current message but isn't the tracked thread yet scores lower
/// but still boosted; a line tagged with a topic that's neither scores low.
/// This used to be the ONLY topic signal pickLine() had, which meant even a
/// heavy boost was still just one multiplier among several — a large enough
/// pool of generic/untagged lines could out-vote the handful of correctly
/// topic-tagged ones often enough to read as a non-sequitur. pickLine() now
/// hard-prefers an on-topic tier first (see its doc comment) and only falls
/// through to scoring the full pool — where this function's multiplier is
/// what actually decides among candidates — when no line in the pool matches
/// the live topic at all. So the numbers below now mostly matter as the
/// tie-breaker *within* whichever tier pickLine() selected.
double topicMatch(Topic? lineTopic, Topic? currentTopic, Set<Topic> playerTopics) {
  if (lineTopic == null) return 1.0;
  if (lineTopic == currentTopic) return 16.0;
  if (playerTopics.contains(lineTopic)) return 6.0;
  return 0.15;
}

/// Neutral (1.0, no boost) when the line carries no intent tag or the
/// player's message has no classified intent. Otherwise boosts a line
/// authored to address that intent (e.g. an answer line tagged
/// [Intent.question]) over one that doesn't.
double intentMatch(Intent? lineIntent, Intent? playerIntent) {
  if (lineIntent == null || playerIntent == null) return 1.0;
  return lineIntent == playerIntent ? 5.0 : 0.3;
}

// ── Character personality (Phase 15) ────────────────────────────────────
// Each function below is [CharacterPersonality]'s own doc comment's promise
// made concrete: one trait, one line property, one multiplier, folded into
// _finalWeight the same way toneMatch/topicMatch/intentMatch already are.
// All four share the same linear scale — trait 0 -> 0.5x, 50 (neutral) ->
// 1.0x (a no-op, so an unset/neutral CharacterPersonality changes nothing),
// 100 -> 1.5x — the same shape personalityModifier() already uses for
// emotionalVolatility, just over a 0-100 axis instead of 0-1.
double _traitScale(double trait) => 0.5 + trait.clamp(0, 100) / 100;

/// High [humor] boosts a [DialogueLine.isJoke] line; neutral (1.0) for
/// everything else regardless of how funny the character is — humor doesn't
/// make a NON-joke line more likely, it just makes reaching for the joke
/// line, when one's eligible, more likely.
double humorMatch(bool lineIsJoke, double humor) => lineIsJoke ? _traitScale(humor) : 1.0;

/// High [curiosity] boosts a line tagged [Intent.question] — a naturally
/// curious character reaches for a question over a statement more often.
/// Independent of [intentMatch] (which matches a line's intent against the
/// PLAYER's, for answering what they just said); this is about the
/// character's own tendency to ask, regardless of what's being replied to.
double curiosityMatch(Intent? lineIntent, double curiosity) => lineIntent == Intent.question ? _traitScale(curiosity) : 1.0;

/// High [warmth] boosts a [ReplyTone.warm]-tagged line — a comforting reply
/// reads as more natural for a warm character. Distinct from
/// `PersonalContact.personalityWarmth` (see [CharacterPersonality]'s own doc
/// comment): that shifts where MOOD settles at rest; this shifts which LINE
/// gets picked.
double warmthMatch(ReplyTone? lineTone, double warmth) => lineTone == ReplyTone.warm ? _traitScale(warmth) : 1.0;

/// Low [patience] boosts a [ReplyTone.cold]-tagged line once the player has
/// actually repeated themselves ([consecutiveActionCount] >= 2 — the same
/// "not a single-turn signal" restraint [nudgeHonesty]/
/// [nudgeSuspicionFromDodgePattern] already apply to their own patterns, so
/// asking something once doesn't read as "the player keeps asking"). Uses
/// [_traitScale] on `100 - patience` so a patient character (high patience)
/// suppresses the irritated line instead of boosting it, and an impatient
/// one (low patience) boosts it — the inversion is the whole point: this
/// models a trait running out, not a trait being expressed directly the way
/// [humorMatch]/[curiosityMatch]/[warmthMatch] each do.
double patienceMatch(ReplyTone? lineTone, double patience, int consecutiveActionCount) {
  if (lineTone != ReplyTone.cold || consecutiveActionCount < 2) return 1.0;
  return _traitScale(100 - patience);
}

/// [DialogueStyle]'s own trait multiplier, same shape/neutral-at-null
/// contract as [humorMatch]/[curiosityMatch]/[warmthMatch]: `null` style is
/// always 1.0 (no bias). Reuses [CharacterPersonality] axes already
/// declared rather than adding new state — [warmth]/[humor] were already
/// wired to [ReplyTone.warm]/[DialogueLine.isJoke]; [strictness] and
/// [talkativeness] were carried but explicitly left unwired (see
/// [CharacterPersonality]'s own doc comment) until now:
/// - [warm]/[affectionate] scale with [warmth] — the same trait that
///   already favors a warm-toned line favors an affectionately-styled one.
/// - [funny]/[playful] scale with [humor] — mirrors [humorMatch].
/// - [serious] scales UP with [strictness]; [casual] scales up with its
///   INVERSE (100 - strictness) — one trait, two opposite style ends, same
///   inversion pattern [patienceMatch] already uses for `100 - patience`.
/// - [short] scales up with the inverse of [talkativeness] — a terse
///   character reaches for the short line; a talkative one doesn't avoid it
///   (no positive "long" style exists to reward instead), so only this one
///   end of the axis is wired.
double styleMatch(DialogueStyle? style, CharacterPersonality personality) {
  return switch (style) {
    null => 1.0,
    DialogueStyle.warm || DialogueStyle.affectionate => _traitScale(personality.warmth),
    DialogueStyle.funny || DialogueStyle.playful => _traitScale(personality.humor),
    DialogueStyle.serious => _traitScale(personality.strictness),
    DialogueStyle.casual => _traitScale(100 - personality.strictness),
    DialogueStyle.short => _traitScale(100 - personality.talkativeness),
  };
}

/// Neutral (1.0) for a line that doesn't specifically acknowledge a dodge —
/// most of the pool. A dodge-acknowledging line is boosted hard on exactly
/// the turn a pending question just got dismissed, and mildly suppressed
/// otherwise (it would be a non-sequitur — "I'll pretend that answered my
/// question" said when nothing was actually asked).
double dodgeMatch(bool lineAcknowledgesDodge, bool questionJustDodged) {
  if (!lineAcknowledgesDodge) return 1.0;
  return questionJustDodged ? 3.0 : 0.5;
}

/// [dodgeMatch]'s mirror image: neutral (1.0) for a line that doesn't
/// specifically acknowledge an answered question — most of the pool. An
/// answer-acknowledging line is boosted hard on exactly the turn a pending
/// question got a genuine reply (not a dodge), and mildly suppressed
/// otherwise (a non-sequitur — "oh good, you actually told me" said when
/// nothing was actually pending). A soft multiplicative nudge, deliberately
/// NOT a hard pool-narrowing the way toneShiftMatch's tone-shift override is
/// in CareerController.personalReplyAction — ResponseIntent.answerQuestion
/// fires on nearly every question-asking turn (not a rare event the way a
/// tone shift is), so narrowing hard to it would exclude the entire existing
/// pool of question-answering content instead of just favoring a few tagged
/// lines within it.
double answeredQuestionMatch(bool lineAcknowledgesAnsweredQuestion, bool questionJustAnswered) {
  if (!lineAcknowledgesAnsweredQuestion) return 1.0;
  return questionJustAnswered ? 3.0 : 0.5;
}

/// Neutral (1.0) for a line that doesn't specifically call out a tone
/// shift — most of the pool. A shift-acknowledging line is boosted hard on
/// exactly the turn the player's tone changed from their immediately prior
/// one ("wait, why the sudden change?"), and mildly suppressed otherwise (it
/// would be a non-sequitur to remark on a shift that didn't happen).
double toneShiftMatch(bool lineAcknowledgesToneShift, bool toneShift) {
  if (!lineAcknowledgesToneShift) return 1.0;
  return toneShift ? 3.0 : 0.5;
}

/// Neutral (1.0) for a line with neither [DialogueLine.requiresRecentIntent]
/// nor [DialogueLine.forbidsRecentIntent] set — the entire pool before intent
/// chips existed, and still every generic filler line. A callback line
/// ("I appreciate you apologizing yesterday") is boosted when the recent
/// window actually contains what it's calling back to, and — per the design
/// goal that recall is a weighted possibility, not a guarantee — only
/// SUPPRESSED (not excluded outright) when the callback condition isn't met,
/// so a thin pool never goes fully ineligible over a memory gate the way a
/// hard [DialogueLine.isEligible] check would.
///
/// The boost scales with the matched event's [MemoryImportance] (the
/// strongest one, if more than one turn in the window qualifies) — a
/// callback to a confront-level exchange should read as more insistent than
/// one to a turn that only happened to carry a matching intent tag while
/// being small talk. [MemoryImportance.medium] keeps the flat 4.0 this
/// function used before importance-weighting existed, so any pool authored
/// against the old flat behavior (every current one — see controller.dart's
/// `_conversationImportance`, which defaults ordinary turns to medium/low)
/// sees no change unless it specifically earns [MemoryImportance.high].
/// [forbidsRecentIntent]'s suppression stays flat: it exists to prevent an
/// immediate non-sequitur repeat, not to model memory strength.
double recallMatch(DialogueLine line, List<ConversationEvent> recent, int currentTurn) {
  bool inWindow(ConversationEvent e) =>
      line.recallWithinTurns == null || currentTurn - e.turn <= line.recallWithinTurns!;
  var m = 1.0;
  if (line.requiresRecentIntent != null) {
    final matches = recent.where((e) => e.intent == line.requiresRecentIntent && inWindow(e));
    if (matches.isEmpty) {
      m *= 0.2;
    } else {
      final strongest = matches.map((e) => e.importance).reduce((a, b) => a.index > b.index ? a : b);
      m *= switch (strongest) {
        MemoryImportance.low => 2.0,
        MemoryImportance.medium => 4.0,
        MemoryImportance.high => 7.0,
        // Phase 11: a callback to a critical (milestone-tier, permanent)
        // exchange should read as more insistent than even a high-importance
        // one — same reasoning the doc comment above gives for high over
        // medium, one notch further.
        MemoryImportance.critical => 10.0,
      };
    }
  }
  if (line.forbidsRecentIntent != null) {
    final hit = recent.any((e) => e.intent == line.forbidsRecentIntent && inWindow(e));
    if (hit) m *= 0.2;
  }
  return m;
}

/// Whether the player's tone this turn is a SIGNIFICANT shift from their
/// immediately prior one — a polar-register swing, using the same
/// opposite-pair definition [toneMatch]'s [_toneAlignment] already uses
/// (warm↔cold, honest↔excuse) rather than a second, narrower hand-rolled set
/// — adding a new opposite pair now only has one place to change, and
/// honest↔excuse (previously NOT treated as a shift here, inconsistently
/// with how [_toneAlignment] already scored it) now correctly counts: someone
/// being direct and then suddenly making excuses is exactly this kind of
/// polar tell, especially mid-suspicion. Every other step (honest→vague,
/// vague→cold, warm→honest, ...) stays natural conversation drift that
/// shouldn't feel called out. [previousTone] of `null` never counts.
///
/// This only ever compares to the single immediately-prior turn, so a slow
/// warm→vague→cold drift across several turns won't trip it until the tone
/// actually lands on cold — each individual step against its own predecessor
/// is non-polar. Catching that kind of gradual withdrawal would mean
/// comparing against a short window of recent turns instead of just one,
/// which raises real design questions (how far back, whether it should keep
/// re-firing for as long as the older tone is still in-window) rather than
/// being a one-line fix, so it isn't done here.
bool detectToneShift({required ReplyTone? previousTone, required ReplyTone tone}) {
  if (previousTone == null || previousTone == tone) return false;
  return _toneAlignment(previousTone, tone) == 0.0;
}

/// Decides the conversation thread's topic state for the NEXT line
/// selection. A message with no detected topic leaves the thread on
/// whatever was already active rather than losing it (a bare "ok" shouldn't
/// reset the conversation). A message that mentions the topic already in
/// play deepens it (progress+1). A message that raises a different topic
/// switches the thread to it, starting over at stage 1. When a message
/// raises more than one topic, [Set] iteration order — insertion order, as
/// the caller built [messageTopics] — picks the new thread, with one
/// carve-out: a bare greeting co-detected with nothing but [Topic.family]
/// (e.g. Mama's chips tag "hey mom" with both — see intents.dart) stays a
/// greeting rather than being displaced by that incidental address-term
/// match, since addressing a parent contact isn't the same as raising family
/// as a subject.
///
/// [subject]/[unresolved]/[turnsActive] track finer-grained thread state
/// alongside [topic]/[progress] — see [PersonalReplyAction.subject]/
/// [PersonalReplyAction.resolvesThread]'s doc comments for the rationale.
/// [messageSubject] narrows the topic further when the caller's action
/// declares one (e.g. "rent" within a [Topic.money] thread); omit it to leave
/// whatever subject was already tracked untouched. [resolves] closes the
/// current subject/topic out as addressed. [turnsActive] climbs on every
/// call the topic is live — including a hold turn that doesn't touch
/// [progress] — and only resets when the topic itself actually changes,
/// which is what lets a caller tell "2 exchanges deep" apart from "open 6
/// turns but only actually addressed twice".
({Topic? topic, int progress, String? subject, bool unresolved, int turnsActive}) advanceTopic({
  required Topic? currentTopic,
  required int currentProgress,
  required Set<Topic> messageTopics,
  String? currentSubject,
  bool currentUnresolved = true,
  int currentTurnsActive = 0,
  String? messageSubject,
  bool resolves = false,
}) {
  if (messageTopics.isEmpty) {
    return (
      topic: currentTopic,
      progress: currentProgress,
      subject: resolves ? null : currentSubject,
      unresolved: resolves ? false : currentUnresolved,
      turnsActive: currentTopic == null ? 0 : currentTurnsActive + 1,
    );
  }
  if (currentTopic != null && messageTopics.contains(currentTopic)) {
    return (
      topic: currentTopic,
      progress: currentProgress + 1,
      subject: resolves ? null : (messageSubject ?? currentSubject),
      unresolved: !resolves,
      turnsActive: currentTurnsActive + 1,
    );
  }
  if (messageTopics.contains(Topic.greeting) &&
      messageTopics.difference({Topic.greeting, Topic.family}).isEmpty) {
    return (topic: Topic.greeting, progress: 1, subject: null, unresolved: false, turnsActive: 1);
  }
  return (
    topic: messageTopics.first,
    progress: 1,
    subject: resolves ? null : messageSubject,
    unresolved: !resolves,
    turnsActive: 1,
  );
}

/// How emotionally deep the conversation is running right now (Phase 16),
/// from small talk up to a full confrontation. Declaration order IS depth
/// order — `.index` compares directly, the same convention
/// [MemoryImportance]'s ordering already relies on (see [recallMatch]'s
/// `strongest` reduce) — so [DialogueLine.minDepth]/[maxDepth] can gate on
/// it the exact same shape [progressionMin]/[progressionMax] already gate on
/// [DialogueContext.topicProgress].
enum ConversationDepth { smallTalk, casual, personal, serious, vulnerable, confrontation }

/// Classifies ONE turn's own depth from what was actually said — the
/// player's [PersonalReplyAction]/chosen [DialogueLine] properties, not the
/// thread's already-tracked depth (see [advanceDepth] for how the two
/// combine). Mirrors the worked examples this was speced against:
/// - "How's work?" — a light topic, unremarkable intensity -> [casual].
/// - "I'm having money problems." — [Topic.money] at a real but moderate
///   intensity -> [personal].
/// - "I'm scared I'm going to lose my apartment." — the same kind of topic,
///   but delivered at real urgency -> [serious]. Intensity, not topic alone,
///   is what separates these two — the same substance can be personal or
///   serious depending on how it's actually delivered.
/// - "I haven't told anyone this." -> [vulnerable]. Not derivable from
///   topic/tone/intensity the way the tiers above are — a first-time
///   disclosure is a fact about the specific content, not a register, so
///   [isVulnerableDisclosure] is an explicit flag content sets directly, the
///   same reasoning [DialogueLine.isJoke] (Phase 15) was added for "this
///   line is playful" instead of trying to infer it.
///
/// [conversationIntent] short-circuits to [ConversationDepth.confrontation]
/// for [ConversationIntent.confront]/[questionLoyalty] — already the
/// engine's own "charged, not small talk" signal (see
/// `CareerController._conversationImportance`'s `critical` set, Phase 11),
/// so this reuses it rather than inventing a second one. [topic] of `null`
/// (no topic at all) or [Topic.greeting] never reads as more than
/// [ConversationDepth.smallTalk], regardless of intensity — "Hey!! 😊" said
/// enthusiastically is still just a greeting, not something deeper.
ConversationDepth classifyDepth({
  ConversationIntent? conversationIntent,
  required Topic? topic,
  required double intensity,
  bool isVulnerableDisclosure = false,
}) {
  if (isVulnerableDisclosure) return ConversationDepth.vulnerable;
  if (conversationIntent == ConversationIntent.confront || conversationIntent == ConversationIntent.questionLoyalty) {
    return ConversationDepth.confrontation;
  }
  if (topic == null || topic == Topic.greeting) return ConversationDepth.smallTalk;
  if (intensity >= 0.75) return ConversationDepth.serious;
  if (intensity >= 0.45) return ConversationDepth.personal;
  return ConversationDepth.casual;
}

/// Advances `RelationshipState.conversationDepth` (Phase 16) given
/// [turnDepth] (this turn's own [classifyDepth] result) and [current] (what
/// the thread was already sitting at). Escalates in one step, all the way to
/// [turnDepth] — the worked examples in [classifyDepth]'s doc comment read
/// as one exchange going deeper turn by turn, not something that should lag
/// behind what was just said. De-escalates only one step at a time, though:
/// a subsequent small-talk reply shouldn't instantly reset a moment that was
/// just [ConversationDepth.vulnerable] back to [ConversationDepth.smallTalk]
/// — that gradual cooldown (not an instant snap-back) is the entire reason
/// [DialogueLine.minDepth]/[maxDepth] are worth gating on at all, rather than
/// just reading [turnDepth] directly turn to turn.
ConversationDepth advanceDepth(ConversationDepth current, ConversationDepth turnDepth) {
  if (turnDepth.index >= current.index) return turnDepth;
  return ConversationDepth.values[current.index - 1];
}

/// Resolves whether a question mama previously asked (if any) got answered
/// or dodged by the player's latest message, from [wasAnswered] (the
/// relationship's [RelationshipState]-equivalent state going into this
/// turn) and the message's classified [Intent]. A dismissal
/// ([Intent.dismissal]) while a question is still pending is a dodge —
/// [justDodged] is true for exactly that turn, driving [dodgeMatch] on
/// *this* reply. [answered] is what the caller should persist for next
/// time: any non-dismissal reply resolves it, a further dismissal leaves it
/// still pending. Note [answered] reflects only the player's message —
/// mama's own reply for this same turn may itself ask a new question
/// (an [Intent.question]-tagged line), which is a separate, later step the
/// caller applies on top of this result, not a contradiction of it.
({bool answered, bool justDodged}) resolvePendingQuestion({
  required bool wasAnswered,
  required Intent messageIntent,
}) {
  final wasPending = !wasAnswered;
  final justDodged = wasPending && messageIntent == Intent.dismissal;
  return (answered: !wasPending || messageIntent != Intent.dismissal, justDodged: justDodged);
}

double _requiredMemoryWeight(DialogueLine line, DialogueContext ctx, int currentDay) {
  final required = line.anyRequiredMemories;
  if (required == null || required.isEmpty) return 1.0;
  final matched = <MemoryEvent>[];
  for (final k in required) {
    final events = ctx.memories.where((m) => m.kind == k);
    if (events.isNotEmpty) matched.add(events.last);
  }
  if (matched.isEmpty) return 1.0;
  final total = matched.fold<double>(0, (a, m) => a + memoryWeight(m, currentDay));
  return total / matched.length;
}

/// Formula 16's FinalWeight: BaseWeight x ToneMatch x TopicMatch x
/// IntentMatch x DodgeMatch x RecallMatch x memory recency x [humorMatch] x
/// [curiosityMatch] x [warmthMatch] x [patienceMatch] x [styleMatch]
/// (Phase 15's character-personality terms) x random jitter x repeat
/// penalty x freshness bonus.
/// [lastUsedDay] of `null` (never used) is treated as 10+ days fresh, the
/// same as any well-rested line.
///
/// Freshness/repeat normally run on day granularity — fine for content that's
/// sent at most a few times a day, but a personal thread can see a dozen
/// turns inside one game day, and day-granularity freshness can't tell turn 1
/// from turn 11. When [currentTurn] is supplied (alongside [lineLastUsedTurn]),
/// freshness is computed from turns instead, at the same 4-per-"day" scale
/// [TimeOfDay] already uses elsewhere, and the day-based inputs are ignored.
/// Both default absent, so every call site written before turn tracking
/// existed computes byte-for-byte the same score it always did.
double _finalWeight(
  Random rng,
  DialogueLine line,
  DialogueContext ctx,
  int currentDay,
  Map<String, int> lineLastUsedDay,
  List<String> recentLineHistory, {
  int? currentTurn,
  Map<String, int> lineLastUsedTurn = const {},
}) {
  final tm = toneMatch(line.tone, ctx.recentTones);
  final tpm = topicMatch(line.topic, ctx.currentTopic, ctx.playerTopics);
  final im = intentMatch(line.intent, ctx.playerIntent);
  final dm = dodgeMatch(line.acknowledgesDodge, ctx.questionJustDodged);
  final aqm = answeredQuestionMatch(line.acknowledgesAnsweredQuestion, ctx.questionJustAnswered);
  final tsm = toneShiftMatch(line.acknowledgesToneShift, ctx.toneShift);
  final mw = _requiredMemoryWeight(line, ctx, currentDay);
  final rm = recallMatch(line, ctx.recentConversation, currentTurn ?? currentDay * 4);
  final hm = humorMatch(line.isJoke, ctx.personality.humor);
  final cm = curiosityMatch(line.intent, ctx.personality.curiosity);
  final wm = warmthMatch(line.tone, ctx.personality.warmth);
  final pm = patienceMatch(line.tone, ctx.personality.patience, ctx.consecutiveActionCount);
  final sm = styleMatch(line.style, ctx.personality);
  final double daysSince;
  if (currentTurn != null) {
    final lastTurn = lineLastUsedTurn[line.text];
    final turnsSince = lastTurn == null ? 40 : (currentTurn - lastTurn).clamp(0, 40);
    daysSince = turnsSince / 4;
  } else {
    final lastUsed = lineLastUsedDay[line.text];
    daysSince = (lastUsed == null ? 10 : (currentDay - lastUsed).clamp(0, 10)).toDouble();
  }
  final recentUses = recentLineHistory.where((t) => t == line.text).length;
  final rngFactor = 1 + rng.nextDouble() * 0.15;
  final recentPenalty = (1 - recentUses * 0.1).clamp(0.1, 1.0);
  final freshnessBonus = 1 + daysSince * 0.05;
  return line.weight * tm * tpm * im * dm * aqm * tsm * mw * rm * hm * cm * wm * pm * sm * rngFactor * recentPenalty * freshnessBonus;
}

/// How weighty the current exchange reads right now (Phase 14) — drives how
/// tightly [_topicTier] holds to the live topic vs lets a reply wander (see
/// [topicTierWeights]). A three-way read of signals [DialogueContext] already
/// carries, not a new tracked field: [DialogueContext.suspicion] and
/// [DialogueContext.mood] are the two axes already standing in for "things
/// are tense" elsewhere in this engine (see [nudgeSuspicionFromDodgePattern]/
/// [decayMood]), and [Topic.suspicion] is the one [Topic] tag that's
/// explicitly about something being wrong, the same way [Topic.greeting]/
/// [Topic.wellbeing]/[Topic.goodNews] are explicitly light conversational
/// registers (see the [Topic] enum's own doc comment). Neither a serious nor
/// a casual signal -> [moderate], the register the 70/15/10/5 split below
/// was written against.
enum ConversationRegister { casual, moderate, serious }

ConversationRegister conversationRegister(DialogueContext ctx) {
  if (ctx.suspicion >= 70 || ctx.currentTopic == Topic.suspicion || ctx.mood <= -40) {
    return ConversationRegister.serious;
  }
  if (ctx.suspicion <= 20 &&
      ctx.mood >= -10 &&
      (ctx.currentTopic == null ||
          ctx.currentTopic == Topic.greeting ||
          ctx.currentTopic == Topic.wellbeing ||
          ctx.currentTopic == Topic.goodNews)) {
    return ConversationRegister.casual;
  }
  return ConversationRegister.moderate;
}

/// [_topicTier]'s four weighted buckets (Phase 14), summing to 1.0:
/// [currentTopic] — a line tagged with the thread's tracked topic;
/// [playerMentioned] — a line tagged with a DIFFERENT topic the player just
/// raised this same turn; [tangent] — a line tagged with some other topic
/// entirely (a natural digression); [initiative] — an untagged line (the
/// character bringing up something of their own, topic-agnostic). Replaces
/// the old hard cutoff (100% [currentTopic] whenever any eligible line
/// carried it) with a weighted draw, so a conversation can wander without
/// [currentTopic] ever losing its dominant share.
class TopicTierWeights {
  final double currentTopic, playerMentioned, tangent, initiative;
  const TopicTierWeights({
    required this.currentTopic,
    required this.playerMentioned,
    required this.tangent,
    required this.initiative,
  });
}

const _kModerateTopicWeights = TopicTierWeights(currentTopic: 0.70, playerMentioned: 0.15, tangent: 0.10, initiative: 0.05);
// Little room to wander — a real question or confrontation shouldn't get
// derailed by a tangent, and a secondary aside the player mentioned in
// passing doesn't deserve a pickup mid-crisis (0 share, not just a small one).
const _kSeriousTopicWeights = TopicTierWeights(currentTopic: 0.90, playerMentioned: 0.0, tangent: 0.05, initiative: 0.05);
// Room to breathe — small talk can drift onto a tangent or a fresh thought
// just as easily as it stays put; a secondary aside isn't being suppressed
// on purpose here either (0 share), it's just not one of the three things
// casual conversation actually reaches for.
const _kCasualTopicWeights = TopicTierWeights(currentTopic: 0.60, playerMentioned: 0.0, tangent: 0.20, initiative: 0.20);

TopicTierWeights topicTierWeights(ConversationRegister register) => switch (register) {
      ConversationRegister.moderate => _kModerateTopicWeights,
      ConversationRegister.serious => _kSeriousTopicWeights,
      ConversationRegister.casual => _kCasualTopicWeights,
    };

/// Splits [eligible] into [TopicTierWeights]'s four buckets and draws one,
/// weighted by [topicTierWeights] for [ctx]'s [conversationRegister] — the
/// Phase 14 replacement for the old hard cutoff (100% on-topic whenever any
/// eligible line carried [DialogueContext.currentTopic]; see this function's
/// git history for that version). No live topic at all means there's nothing
/// to weigh "on-topic" against, so tiering is skipped entirely and every
/// eligible line stays in play, same as before.
///
/// The four buckets exactly partition [eligible] (every line falls into
/// precisely one — see the class-level doc comment), so excluding empty
/// buckets and any bucket a caller's [TopicTierWeights] zeroed out (e.g.
/// [ConversationRegister.serious]'s `playerMentioned: 0.0`) before drawing
/// still always leaves at least one candidate: [eligible] itself is
/// non-empty, so some bucket must be too. Falling back to the untouched
/// [eligible] list is a documented safety net for a [TopicTierWeights] that
/// zeroed out every bucket that happens to be non-empty (not reachable with
/// the three built-in registers above, but a future custom weighting
/// shouldn't have to reprove this function's own invariant to stay safe).
List<DialogueLine> _topicTier(List<DialogueLine> eligible, DialogueContext ctx, Random rng) {
  final currentTopic = ctx.currentTopic;
  if (currentTopic == null) return eligible;

  final onTopic = eligible.where((l) => l.topic == currentTopic).toList();
  final playerMentioned = eligible.where((l) => l.topic != null && l.topic != currentTopic && ctx.playerTopics.contains(l.topic)).toList();
  final tangent = eligible.where((l) => l.topic != null && l.topic != currentTopic && !ctx.playerTopics.contains(l.topic)).toList();
  final initiative = eligible.where((l) => l.topic == null).toList();

  final weights = topicTierWeights(conversationRegister(ctx));
  final buckets = [
    (onTopic, weights.currentTopic),
    (playerMentioned, weights.playerMentioned),
    (tangent, weights.tangent),
    (initiative, weights.initiative),
  ].where((b) => b.$1.isNotEmpty && b.$2 > 0).toList();
  if (buckets.isEmpty) return eligible;

  final total = buckets.fold(0.0, (a, b) => a + b.$2);
  var r = rng.nextDouble() * total;
  for (final bucket in buckets) {
    r -= bucket.$2;
    if (r <= 0) return bucket.$1;
  }
  return buckets.last.$1;
}

/// Picks a weighted-random line from [pool] using formula 16's FinalWeight —
/// context first, randomness second. Line selection happens in two passes:
/// first [_topicTier] draws a topic-relevance bucket (Phase 14: on-topic vs
/// player-mentioned vs a natural tangent vs the character's own initiative,
/// weighted by [conversationRegister] — see its own doc comment for why this
/// isn't the old hard 100%-on-topic cutoff), THEN the remaining candidates
/// are scored and weighted-randomly drawn from, so variety (tone match,
/// freshness, repeat penalty, rng jitter) still applies — just among options
/// from the drawn bucket, instead of across the whole pool regardless of fit.
///
/// [lineLastUsedDay] and [recentLineHistory] (last 5 lines sent by this
/// contact, any pool, most-recent-last) drive the variety/repetition terms —
/// pass [recordLineUse]'s backing collections here. Pure: never mutates its
/// inputs. Returns null if nothing in [pool] is eligible; every pool authored
/// against this engine must keep at least one always-eligible line so this is
/// a documented fallback contract, not a runtime surprise.
///
/// [currentTurn]/[lineLastUsedTurn] opt into turn-granularity freshness — see
/// [_finalWeight]. Omit both for the original day-granularity behavior.
DialogueLine? pickLine(
  Random rng,
  List<DialogueLine> pool,
  DialogueContext ctx, {
  required int currentDay,
  Map<String, int> lineLastUsedDay = const {},
  List<String> recentLineHistory = const [],
  int? currentTurn,
  Map<String, int> lineLastUsedTurn = const {},
}) {
  final eligible = pool.where((l) => l.isEligible(ctx)).toList();
  if (eligible.isEmpty) return null;

  final candidates = _topicTier(eligible, ctx, rng);

  final scores = [
    for (final l in candidates)
      _finalWeight(rng, l, ctx, currentDay, lineLastUsedDay, recentLineHistory, currentTurn: currentTurn, lineLastUsedTurn: lineLastUsedTurn),
  ];
  final total = scores.fold(0.0, (a, b) => a + b);
  var r = rng.nextDouble() * total;
  for (var i = 0; i < candidates.length; i++) {
    r -= scores[i];
    if (r <= 0) return candidates[i];
  }
  return candidates.last;
}

/// Records that [line] was just used, for [pickLine]'s variety scoring on
/// future picks. Call after [pickLine] returns a non-null result. [cap]
/// bounds [recentLineHistory]'s length (default 5, matching the original
/// behavior); pass a larger [cap] for a pool that needs a longer memory of
/// its own recent picks. [turn]/[lineLastUsedTurn] additionally record
/// turn-granularity usage for [pickLine]'s turn-based freshness — omit both
/// to only track day granularity, as before.
void recordLineUse(
  Map<String, int> lineLastUsedDay,
  List<String> recentLineHistory,
  DialogueLine line,
  int day, {
  int cap = 5,
  int? turn,
  Map<String, int>? lineLastUsedTurn,
}) {
  lineLastUsedDay[line.text] = day;
  if (turn != null && lineLastUsedTurn != null) {
    lineLastUsedTurn[line.text] = turn;
  }
  recentLineHistory.add(line.text);
  while (recentLineHistory.length > cap) {
    recentLineHistory.removeAt(0);
  }
}

/// Pure UI helper — maps a mood value to a small status glyph.
String moodEmoji(double mood) {
  if (mood >= 40) return '😊';
  if (mood >= 12) return '🙂';
  if (mood > -12) return '😐';
  if (mood > -40) return '😕';
  return '😠';
}
