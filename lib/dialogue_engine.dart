// Rule-based dialogue selection engine. Pure Dart, no Flutter imports, no
// project imports — content-agnostic so it never needs to change as more
// characters/lines are added; only the data in data.dart grows.
import 'dart:math';

enum ReplyTone { warm, honest, vague, cold, excuse }

/// What the player's free text is trying to DO, independent of its tone.
enum Intent { question, promise, confession, dismissal, statement }

/// Grows by adding cases — no engine change needed to add a new milestone kind.
enum MemoryKind {
  firstWarmReply,
  cutOff,
  heardAboutCutOff,
  heardAboutConfrontation,
  promiseMade, // [ConversationIntent.makePeace] resolved warmly — a commitment worth remembering past the short-term window
  deepConfession, // [ConversationIntent.confront]/[ConversationIntent.questionLoyalty] fired — a charged exchange, not small talk
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
}

/// How far into the current story level the conversation is sitting, derived
/// from [CareerController.levelProgress] (or forced to [cusp] right after a
/// major story beat — see `CareerController.levelPhase`). Read by
/// [DialogueLine.phases] so a reaction can feel like it belongs to *now*
/// rather than to the level in the abstract ("you've been quiet about what's
/// really going on" only lands once there's something to be quiet about).
enum LevelPhase { opening, early, mid, late, cusp }

/// How long a [ConversationEvent] stays in [DialogueContext.recentConversation]
/// before it's pruned — see `RelationshipState.recentConversation` for the
/// eviction rule. Small talk shouldn't linger; a betrayal should.
enum MemoryImportance { low, medium, high }

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
/// question of *some* kind is pending. [deadlineTurn] is optional and
/// currently informational only — nothing yet auto-expires an interaction
/// once its deadline passes; a caller that wants that behavior checks
/// [RelationshipState.turnCount] against it.
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
  PendingInteraction({
    required this.type,
    this.topic,
    this.subject,
    required this.createdTurn,
    this.deadlineTurn,
    this.resolved = false,
  });
}

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
  final Set<TimeOfDay>? timesOfDay; // null = any time of day
  final bool? requireWeekend; // null = no constraint; true = weekend only; false = weekday only
  final Intent? intent; // the player intent this line is meant to address, used by intentMatch
  final int? progressionMin, progressionMax; // gates a line to a stage of the [topic] thread — see advanceTopic()
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
    if (phases != null && ctx.levelPhase != null && !phases!.contains(ctx.levelPhase)) return false;
    if (requiredFacts != null) {
      for (final entry in requiredFacts!.entries) {
        if (ctx.facts[entry.key]?.value != entry.value) return false;
      }
    }
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
/// IntentMatch x DodgeMatch x RecallMatch x memory recency x random jitter x
/// repeat penalty x freshness bonus. [lastUsedDay] of `null` (never used) is
/// treated as 10+ days fresh, the same as any well-rested line.
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
  return line.weight * tm * tpm * im * dm * aqm * tsm * mw * rm * rngFactor * recentPenalty * freshnessBonus;
}

/// Narrows [eligible] to a "topic tier" before scoring — the fix for a
/// pool-with-enough-generic-lines drowning out the handful of lines that
/// actually address what's live (see topicMatch()'s doc comment). Tries, in
/// order: lines tagged with the thread's tracked topic ([currentTopic]);
/// failing that, lines tagged with a topic the player just raised this turn
/// ([playerTopics]); failing that, every eligible line untouched. Each tier
/// is tried only if it's non-empty, so this never narrows a pool down to
/// nothing — pickLine()'s always-eligible-line contract is unaffected, it
/// just means "eligible AND on-topic when that's possible" instead of
/// "eligible" alone.
List<DialogueLine> _topicTier(List<DialogueLine> eligible, Topic? currentTopic, Set<Topic> playerTopics) {
  if (currentTopic != null) {
    final onTopic = eligible.where((l) => l.topic == currentTopic).toList();
    if (onTopic.isNotEmpty) return onTopic;
  }
  if (playerTopics.isNotEmpty) {
    final justRaised = eligible.where((l) => l.topic != null && playerTopics.contains(l.topic)).toList();
    if (justRaised.isNotEmpty) return justRaised;
  }
  return eligible;
}

/// Picks a weighted-random line from [pool] using formula 16's FinalWeight —
/// context first, randomness second. Line selection happens in two passes:
/// first [_topicTier] narrows the eligible lines down to whichever ones
/// actually address the live topic (falling through tiers only when a
/// narrower one would be empty — see its doc comment), THEN the remaining
/// candidates are scored and weighted-randomly drawn from, so variety (tone
/// match, freshness, repeat penalty, rng jitter) still applies — just among
/// options that all fit the moment, instead of across the whole pool
/// regardless of fit.
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

  final candidates = _topicTier(eligible, ctx.currentTopic, ctx.playerTopics);

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
