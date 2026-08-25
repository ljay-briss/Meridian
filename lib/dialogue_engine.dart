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
  /// Deliberately topic-agnostic in its own phrasing (see
  /// conversation/intents.dart) since it has to fit ANY live [Topic], not
  /// just one; CareerController._intentChipScore gives it a large boost
  /// specifically when a thread is live or a question is pending, so it's
  /// present whenever the player would otherwise have nothing that flows.
  elaborate,
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
/// the exchange is actually about.
enum Topic { family, health, money, plans, suspicion, affection, greeting, wellbeing }

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

/// Formula 10's DebtDelta: fires only when the player's own text is
/// money-related ([isDebtTopic]) — deflecting reads as owing more, settling
/// it warmly/honestly reads as paying it down. No decay; debt is sticky.
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

// ── Free-text classification (formula 1's PlayerMessage + formula 7's
// SemanticMatch inputs) — a compact lexicon/heuristic classifier, not real
// ML/NLP: keyword and punctuation scoring, fully offline and deterministic. ──

class PlayerMessage {
  final String text;
  final ReplyTone tone;
  final Set<Topic> topics;
  final Intent intent;
  final Set<String> entities;
  final double intensity;
  const PlayerMessage({
    required this.text,
    required this.tone,
    required this.topics,
    required this.intent,
    required this.entities,
    required this.intensity,
  });
}

const List<String> _strongWords = [
  'hate', 'love', 'kill', 'death', 'always', 'never', 'perfect', 'forever', 'terrified', 'furious', 'desperate',
  'devastated', 'heartbroken', 'betrayed', 'disgusted', 'ashamed', 'humiliated', 'worthless', 'hopeless',
  'broken', 'shattered', 'destroyed', 'ruined', 'dying', 'screaming', 'crying', 'begging', 'pleading', 'sworn',
  'swear', 'disaster', 'unbearable', 'unforgivable', 'disgrace', 'nightmare', 'terrifying', 'horrifying',
  'urgent', 'emergency', 'insane', 'crazy', 'worst', 'incredible', 'unbelievable',
];

/// Formula 1's `intensity` axis: baseline 0.5, boosted by strong words,
/// shouting (all-caps), message length, and emphatic punctuation; reduced
/// slightly by trailing-off punctuation ("..."). Clamped 0–1.
double computeIntensity(String text) {
  if (text.isEmpty) return 0.0;
  var intensity = 0.5;

  final lower = text.toLowerCase();
  final words = lower.split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
  intensity += words.where((w) => _strongWords.contains(w.replaceAll(RegExp(r'[^a-z]'), ''))).length * 0.1;

  final hasLetter = text.contains(RegExp(r'[A-Za-z]'));
  if (hasLetter && text == text.toUpperCase()) intensity += 0.2;

  intensity += (text.length / 100) * 0.2;

  final exclaimCount = '!'.allMatches(text).length;
  final questionCount = '?'.allMatches(text).length;
  if (exclaimCount > 0) intensity += 0.1;
  final repeatedEmphasis = (max(exclaimCount, questionCount) - 1).clamp(0, 3);
  intensity += 0.05 * repeatedEmphasis;

  if (text.contains('..')) intensity -= 0.05;

  return intensity.clamp(0.0, 1.0);
}

const List<String> _debtKeywords = [
  'owe', 'owes', 'owed', 'owing', 'pay', 'paid', 'payment', 'payments',
  'debt', 'debts', 'cash', 'money', 'loan', 'loans', 'borrow', 'borrowed',
  'borrowing', 'lend', 'lending', 'repay', 'repayment', 'dollar', 'dollars',
  'bucks', 'rent', 'bill', 'bills', 'broke', 'funds', 'financial', 'interest',
  'credit', 'installment', 'iou', 'overdue', 'pay you back', 'pay back',
  'wire transfer', 'venmo', 'cashapp', 'atm', 'budget', 'afford', 'expensive',
  'mortgage', 'salary', 'paycheck', 'savings', 'check',
];

/// Whether the player's own text is money-related — drives [nudgeDebt].
/// Independent of [Topic.money], which tags what an NPC *line* is about.
bool isDebtTopic(String text) {
  final lower = text.toLowerCase();
  return _debtKeywords.any((k) => lower.contains(k));
}

const Map<ReplyTone, List<String>> _toneLexicon = {
  ReplyTone.warm: [
    'love', 'i love you', 'love you', 'sorry', "i'm sorry", 'i am sorry', 'forgive me', 'miss you', 'i miss you',
    'care about', 'i care about you', 'promise', 'appreciate', 'i appreciate you', 'grateful', 'thank you',
    'thankful', 'sweetheart', 'sweetie', 'my love', 'dear', 'precious', 'adore', 'cherish', 'take care',
    'be safe', 'stay safe', 'proud of you', 'mean everything', 'means a lot',
  ],
  ReplyTone.honest: [
    'the truth is', 'honestly', 'to be real', 'i need to tell you', 'actually', 'look,', "here's what happened",
    'real talk', 'let me be honest', "i'll be honest", 'no lies', 'straight up', 'for real', 'in all honesty',
    "i won't lie", 'truthfully', 'i have to be honest', 'the reality is', "i'm not gonna lie", 'ngl',
    'being honest', 'i owe you the truth', 'here\'s the truth', 'plain and simple', "let's be real",
    'i want to be honest', 'i need to be straight with you', 'honest answer', 'no filter',
  ],
  ReplyTone.vague: [
    'kind of', 'not really', 'i guess', 'maybe', "it's complicated", 'not sure', "i don't know", 'idk',
    'sort of', 'whatever works', "we'll see", 'i mean', 'kinda', 'dunno', 'not certain', 'hard to say',
    'who knows', 'it depends', "can't say", "it's a long story", "can't explain right now", 'hard to explain',
    "i'll explain later", "we'll talk later", 'not important right now', 'never mind', "it's nothing",
    'just stuff',
  ],
  ReplyTone.cold: [
    "don't care", 'whatever.', 'leave me alone', 'not now', "i'm done", 'stop asking', 'go away', 'whatever',
    'forget it', 'drop it', "i'm busy", 'not interested', 'stop texting me', 'leave me be', "don't want to talk",
    'not talking about this', 'enough', "that's enough", "i'm over this", 'done talking', 'done with this',
    'back off', 'quit it', 'not in the mood', 'nope', "don't start", 'stop',
  ],
  ReplyTone.excuse: [
    'just work', 'ran late', 'nothing happened', 'i swear', 'it was just', 'long meeting',
    'nothing to worry about', "it's not what it looks like", 'i can explain', "there's a reason",
    "it wasn't my fault", 'i got caught up', 'lost track of time', 'things came up', 'it was an accident',
    "i didn't mean to", 'it slipped my mind', 'i forgot', 'my phone died', 'bad signal', 'no service',
    'was in a rush', 'got tied up', 'unexpected stuff', 'work stuff', 'long story short', "wasn't planned",
    'out of my control', 'i had no choice',
  ],
};

// Whole-word only — matched by tokenizing, never by substring — since most of
// these are short enough to false-positive inside ordinary words ("hi" inside
// "this"/"which") if checked the same way as the phrase lexicon above.
const List<String> _greetingWords = ['hi', 'hey', 'hello', 'hiya', 'heyy', 'yo', 'sup', 'hola'];

bool _isGreeting(String lower) {
  final words = lower.split(RegExp(r'[^a-z]+')).where((w) => w.isNotEmpty);
  return words.any(_greetingWords.contains);
}

// Leading-position auxiliary/wh-words — a strong question signal in natural
// English word order ("Are you okay", "How are you").
const Set<String> _questionLeadWords = {
  'who', 'what', 'when', 'where', 'why', 'how', 'are', 'is', 'do', 'did', 'can', 'could', 'would', 'will', 'does',
};
// A narrower set safe to match ANYWHERE in a short message, not just in
// lead position — casual texting often drops the leading word or the "?"
// ("worried about what", "mad because why"). Restricted to wh-words only:
// "is"/"are"/"do" etc. show up constantly in ordinary statements, so
// allowing those anywhere would misread plain sentences as questions.
const Set<String> _questionAnywhereWords = {'who', 'what', 'when', 'where', 'why', 'how'};

/// A caring or curious question reads as engaged, not evasive — this exists
/// so [_classifyTone]'s no-lexicon-match fallback doesn't misfile "how are
/// you"-shaped messages as vague/cold just because no tone phrase matched.
bool _looksLikeQuestion(String lower) {
  final trimmed = lower.trim();
  if (trimmed.isEmpty) return false;
  if (trimmed.endsWith('?')) return true;
  final words = trimmed.split(RegExp(r'[^a-z]+')).where((w) => w.isNotEmpty).toList();
  if (words.isEmpty) return false;
  if (_questionLeadWords.contains(words.first)) return true;
  return words.length <= 6 && words.any(_questionAnywhereWords.contains);
}

ReplyTone _classifyTone(String lower) {
  ReplyTone best = ReplyTone.vague;
  var bestScore = 0;
  for (final entry in _toneLexicon.entries) {
    final score = entry.value.where((phrase) => lower.contains(phrase)).length;
    if (score > bestScore) {
      bestScore = score;
      best = entry.key;
    }
  }
  if (bestScore > 0) return best;
  // A bare greeting reads as friendly, not curt — checked before the
  // length-based fallback below so "hi"/"hey mom" don't fall into cold just
  // for being short.
  if (_isGreeting(lower)) return ReplyTone.warm;
  // A genuine question — even one with no tone-lexicon signal — reads as
  // direct engagement, not evasiveness. Checked before the length fallback
  // so "how are you"/"how so?" don't get misread as vague dodging.
  if (_looksLikeQuestion(lower)) return ReplyTone.honest;
  // No lexicon signal — fall back on shape: short and curt reads cold,
  // everything else reads vague (vague's role as the "didn't really say
  // anything" bucket).
  final trimmed = lower.trim();
  if (trimmed.isEmpty || trimmed.length <= 6) return ReplyTone.cold;
  return ReplyTone.vague;
}

const Map<Topic, List<String>> _topicLexicon = {
  Topic.family: [
    'mom', 'mamá', 'mama', 'dad', 'papá', 'papa', 'aunt', 'tía', 'uncle', 'tío', 'brother', 'tono', 'sister',
    'cousin', 'grandma', 'abuela', 'grandpa', 'abuelo', 'family', 'home', 'relatives', 'nephew', 'niece',
    'godmother', 'madrina', 'godfather', 'padrino', 'in-laws', 'siblings', 'parents', 'household', 'hometown',
    'family dinner', 'family gathering', 'reunion', 'holidays', 'birthday', 'anniversary',
  ],
  Topic.health: [
    'sick', 'cold', 'flu', 'fever', 'doctor', 'hospital', 'health', 'hurt', 'pain', 'ache', 'tired', 'exhausted',
    'medicine', 'pills', 'checkup', 'appointment', 'surgery', 'injury', 'injured', 'cough', 'headache',
    'stomach', 'dizzy', 'allergies', 'diagnosis', 'treatment', 'therapy', 'recovering', 'healing', 'symptoms',
    'clinic', 'nurse', 'prescription', 'x-ray', 'blood pressure', 'diabetes', 'insurance', 'emergency room',
  ],
  Topic.money: [
    'cash', 'pay', 'owe', 'rent', 'money', 'debt', 'loan', 'broke', 'bills', 'paycheck', 'salary', 'savings',
    'expenses', 'budget', 'afford', 'tight on cash', 'short on money', 'financial trouble', 'credit card',
    'bank', 'atm', 'wire transfer', 'venmo', 'cashapp', 'check', 'deposit', 'withdrawal', 'overdraft',
    'interest rate', 'mortgage', 'utilities', 'groceries', 'gas money', 'tuition', 'paycheck to paycheck',
    'in the red', 'going broke',
  ],
  Topic.plans: [
    'weekend', 'tonight', 'dinner', 'come by', 'visit', 'later', 'plans', 'tomorrow', 'next week',
    'this weekend', 'lunch', 'breakfast', 'brunch', 'get together', 'hang out', 'meet up', 'stop by',
    'come over', 'drop by', 'schedule', 'calendar', 'birthday party', 'holiday plans', 'vacation', 'trip',
    'road trip', 'movie night', 'game night', 'coffee', 'drinks', 'catch up', 'free time', 'day off',
    'next month', 'date night',
  ],
  Topic.suspicion: [
    'where were you', 'who is', 'secret', 'lying', 'truth', 'hiding', 'suspicious', 'secretive',
    'sneaking around', 'cover story', 'cover up', "why didn't you tell me", "what aren't you telling me",
    'who were you with', 'where have you been', 'why are you being weird', "something's off", "doesn't add up",
    'red flag', 'keeping secrets', 'hidden agenda', 'evasive', 'dodging the question', 'changing the subject',
    'not answering', 'avoiding me', 'acting strange', 'acting different', 'seems off', "don't trust this",
    "i don't believe you", "that doesn't sound right", 'catching you in a lie', 'half-truth',
    'story keeps changing', "what's wrong", 'whats wrong', "what's going on with you", 'why are you acting like this',
  ],
  Topic.affection: [
    'love you', 'miss you', 'care about', 'i adore you', 'sweetheart', 'precious to me', 'mean the world',
    'my heart', 'thinking of you', "can't stop thinking about you", 'you matter to me', 'i cherish you',
    'close to my heart', 'love you to pieces', 'warm hug', 'big hug', "i'm here for you", 'always love you',
    'forever grateful for you', 'blessed to have you', 'my everything', 'my world', 'so proud of you',
    'love you endlessly', 'missing your voice', 'missing your face', 'wish you were here', 'counting the days',
    "can't wait to see you", 'hold you close', 'love notes', 'xoxo', 'sending love', 'sending hugs',
    'love always',
  ],
  // Multi-word phrases only — a single short word like "hi" or "you" would
  // false-positive as a substring of unrelated words ("this", "your"), the
  // same trap [_greetingWords] avoids by tokenizing instead. [Topic.greeting]
  // itself is detected via [_isGreeting] in [_classifyTopics] below rather
  // than through this lexicon, for the same reason.
  Topic.wellbeing: [
    'how are you', 'how you doing', 'how you been', 'how ya doing', "how's it going", 'hows it going',
    'you good', 'you doing ok', 'you doing okay', 'you okay', 'you ok', 'you alright', 'everything okay',
    'everything ok', 'how have you been', 'how are things', 'how is everything', "how's your day", 'hows your day',
    'how was your day', 'how is your day',
    // Reciprocal answers to a wellbeing question ("How's your day been?" ->
    // "good and yours?") don't ask anything themselves, so none of the
    // "how ..."-shaped phrases above match them — without these, the
    // question mama just asked (and the topic thread it started) goes
    // unrecognized the instant the player just answers back instead of
    // re-asking in the same words.
    'and yours', 'and you?', 'how about you', 'what about you',
  ],
};

Set<Topic> _classifyTopics(String lower) {
  final topics = <Topic>{};
  for (final entry in _topicLexicon.entries) {
    if (entry.value.any((k) => lower.contains(k))) topics.add(entry.key);
  }
  // Reuses the tokenized greeting check ([_isGreeting], defined above)
  // instead of a substring lexicon entry, same false-positive concern as
  // above.
  if (_isGreeting(lower)) topics.add(Topic.greeting);
  return topics;
}

const Map<Intent, List<String>> _intentLexicon = {
  Intent.question: [
    '?', 'who', 'what', 'when', 'where', 'why', 'how', 'are you', 'is it', 'do you', 'did you', 'can you',
    'could you', 'would you', 'will you', 'does it', "isn't it", 'right?', 'huh?', 'really?', 'you sure',
    'is that true', 'what happened', 'why not', 'how come', "what's going on", 'whats going on', "what's up",
    'whats up', 'are we', 'am i wrong',
    // Casual check-in phrasing that skips a question word/mark entirely
    // ("you ok", "you good") — without these, a short reply like this used
    // to fall straight through to the no-lexicon-signal short-text
    // fallback below and misread as a dismissal.
    'you good', 'you ok', 'you okay', 'you alright', 'everything okay', 'everything ok',
  ],
  Intent.promise: [
    "i'll", 'i promise', 'i will', "i'm going to", 'i am going to', "i'll be there", 'i got you', 'count on me',
    'you can count on me', "i won't let you down", 'i swear i will', "i'll make it up to you", "i'll do better",
    "i'll try", "i'll come by", "i'll call you", "i'll text you", 'next time i promise', "i'll fix it",
    'i guarantee', "i'll take care of it", 'trust me on this', "i'll be better", "i'll change",
    'from now on i will', "i'll make sure", "i'll handle it",
  ],
  Intent.confession: [
    'i love you', "i'm sorry", 'i am sorry', 'i have to tell you something', 'i need to confess',
    'i have a confession', 'truth is i', 'i have to admit', 'i must admit', "i've been hiding",
    'i should have told you', 'i need to come clean', "there's something i haven't told you",
    "i haven't been honest", 'i lied about', 'i want to tell you the truth', "i've never told anyone",
    'confession', "i'm in love with you", 'i really love you', "i've always loved you",
    'my heart belongs to you', "i can't hide it anymore", 'i need to get this off my chest',
    "i've been meaning to tell you", 'the truth i never told you',
  ],
  Intent.dismissal: [
    'nothing', 'nvm', 'never mind', "it's fine", 'whatever', 'forget it', 'bye', 'gtg', 'gotta go', "i'm out",
    'later', 'k', 'kk', 'ok bye', 'not now', 'leave it', 'drop it', "don't worry about it", "it's whatever",
    'no comment', "i'm done talking", 'end of discussion', 'not discussing this', 'moving on', "that's it",
    "we're done here", 'stop', 'enough',
  ],
  Intent.statement: [
    'i am', "i'm", 'i think', 'i feel', 'i believe', 'the fact is', 'basically', 'so anyway', 'update:', 'fyi',
    'just so you know', 'heads up', 'by the way', 'btw', 'for your information', 'i wanted to let you know',
    'quick update', 'just letting you know', 'here is what happened', 'i did', 'i went', 'i saw', 'i finished',
    'i started', "i'm currently", "right now i'm", 'today i',
  ],
};

// Bare single-word intent-lexicon entries that are unsafe to substring-match
// — 'what' would match inside "whatever", 'k' inside "ok"/"like"/"make" —
// the same false-positive class [_isGreeting]/[_questionAnywhereWords]
// already tokenize around for tone/topic classification. Matched as whole
// tokens instead; every other (multi-word, or punctuation-bearing like '?')
// entry keeps substring matching, which is safe for those.
const Set<String> _questionWholeWords = {'who', 'what', 'when', 'where', 'why', 'how'};
const Set<String> _dismissalWholeWords = {'k'};

int _scoreIntentPhrases(String lower, Set<String> lowerWords, List<String> phrases, Set<String> wholeWordOnly) {
  var score = 0;
  for (final phrase in phrases) {
    if (wholeWordOnly.contains(phrase) ? lowerWords.contains(phrase) : lower.contains(phrase)) score++;
  }
  return score;
}

Intent _classifyIntent(String lower, String rawText) {
  final lowerWords = lower.split(RegExp(r'[^a-z]+')).where((w) => w.isNotEmpty).toSet();
  final scores = <Intent, int>{};
  for (final entry in _intentLexicon.entries) {
    final wholeWordOnly = switch (entry.key) {
      Intent.question => _questionWholeWords,
      Intent.dismissal => _dismissalWholeWords,
      _ => const <String>{},
    };
    scores[entry.key] = _scoreIntentPhrases(lower, lowerWords, entry.value, wholeWordOnly);
  }
  // A trailing '?' is the strongest, least ambiguous question signal —
  // weighted heavily so a genuine question wins even against an incidental
  // match elsewhere (e.g. "Why would you do that? I promise I'll explain.").
  if (rawText.trim().endsWith('?')) {
    scores[Intent.question] = (scores[Intent.question] ?? 0) + 3;
  }
  Intent best = Intent.statement;
  var bestScore = 0;
  for (final entry in scores.entries) {
    if (entry.value > bestScore) {
      bestScore = entry.value;
      best = entry.key;
    }
  }
  if (bestScore > 0) return best;
  // No lexicon signal — very short text reads as a dismissal, otherwise a
  // plain statement.
  if (lower.trim().length <= 8) return Intent.dismissal;
  return Intent.statement;
}

Set<String> _extractEntities(String lower, Iterable<String> knownEntityNames) {
  return knownEntityNames.where((name) => name.isNotEmpty && lower.contains(name.toLowerCase())).toSet();
}

/// Classifies free player text into a [PlayerMessage] — formula 1. Pure
/// lexicon/heuristic scoring, no network call.
PlayerMessage classifyMessage(String rawText, {required Iterable<String> knownEntityNames}) {
  final lower = rawText.toLowerCase();
  return PlayerMessage(
    text: rawText,
    tone: _classifyTone(lower),
    topics: _classifyTopics(lower),
    intent: _classifyIntent(lower, rawText),
    entities: _extractEntities(lower, knownEntityNames),
    intensity: computeIntensity(rawText),
  );
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
  const DialogueContext({
    required this.mood,
    required this.closeness,
    required this.trust,
    required this.suspicion,
    required this.daysSinceReply,
    required this.recentTones,
    required this.memories,
    this.timeOfDay = TimeOfDay.morning,
    this.isWeekend = false,
    this.currentTopic,
    this.topicProgress = 0,
    this.playerTopics = const {},
    this.playerIntent,
    this.questionJustDodged = false,
    this.toneShift = false,
    this.playerTopicsToday = const {},
    this.consecutiveActionCount = 0,
    this.levelPhase,
    this.recentConversation = const [],
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
  final Set<MemoryKind>? requiredMemories;
  final Set<MemoryKind>? forbiddenMemories;
  final ReplyTone? tone; // this line's own emotional register, used by ToneMatch
  final Set<TimeOfDay>? timesOfDay; // null = any time of day
  final bool? requireWeekend; // null = no constraint; true = weekend only; false = weekday only
  final Intent? intent; // the player intent this line is meant to address, used by intentMatch
  final int? progressionMin, progressionMax; // gates a line to a stage of the [topic] thread — see advanceTopic()
  final bool acknowledgesDodge; // fits a reply to a just-dismissed pending question, used by dodgeMatch
  final bool acknowledgesToneShift; // fits a reply that notices the player's tone just changed, used by toneShiftMatch
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
    this.requiredMemories,
    this.forbiddenMemories,
    this.tone,
    this.timesOfDay,
    this.requireWeekend,
    this.intent,
    this.progressionMin,
    this.progressionMax,
    this.acknowledgesDodge = false,
    this.acknowledgesToneShift = false,
    this.phases,
    this.requiresRecentIntent,
    this.forbidsRecentIntent,
    this.recallWithinTurns,
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
    if (requiredMemories != null && !requiredMemories!.any(ctx.hasMemory)) return false;
    if (forbiddenMemories != null && forbiddenMemories!.any(ctx.hasMemory)) return false;
    if (timesOfDay != null && !timesOfDay!.contains(ctx.timeOfDay)) return false;
    if (requireWeekend != null && requireWeekend != ctx.isWeekend) return false;
    if (progressionMin != null && ctx.topicProgress < progressionMin!) return false;
    if (progressionMax != null && ctx.topicProgress > progressionMax!) return false;
    if (phases != null && ctx.levelPhase != null && !phases!.contains(ctx.levelPhase)) return false;
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
/// but still boosted; a line tagged with a topic that's neither is heavily
/// deprioritized but never excluded outright, so a pool never loses its
/// always-eligible fallback guarantee purely to topic mismatch. The gap
/// between these is wide on purpose — a pool this size (dozens of generic,
/// untagged filler lines per tone) needs a strong pull for the handful of
/// topic-tagged lines to actually win a weighted draw against sheer numbers.
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
double recallMatch(DialogueLine line, List<ConversationEvent> recent, int currentTurn) {
  bool inWindow(ConversationEvent e) =>
      line.recallWithinTurns == null || currentTurn - e.turn <= line.recallWithinTurns!;
  var m = 1.0;
  if (line.requiresRecentIntent != null) {
    final hit = recent.any((e) => e.intent == line.requiresRecentIntent && inWindow(e));
    m *= hit ? 4.0 : 0.2;
  }
  if (line.forbidsRecentIntent != null) {
    final hit = recent.any((e) => e.intent == line.forbidsRecentIntent && inWindow(e));
    if (hit) m *= 0.2;
  }
  return m;
}

/// Whether the player's tone this turn is a SIGNIFICANT shift from their
/// immediately prior one. Only polar-register swings count — warm↔cold or
/// warm↔excuse — because a real person notices "hey you were just being sweet
/// and now you're icing me out", not every minor step up or down the register
/// (honest→vague, vague→cold, warm→honest are all natural conversation drift
/// that shouldn't feel called-out). [previousTone] of `null` never counts.
bool detectToneShift({required ReplyTone? previousTone, required ReplyTone tone}) {
  if (previousTone == null || previousTone == tone) return false;
  const warmSet = {ReplyTone.warm};
  const coldSet = {ReplyTone.cold, ReplyTone.excuse};
  return (warmSet.contains(previousTone) && coldSet.contains(tone)) ||
         (coldSet.contains(previousTone) && warmSet.contains(tone));
}

/// Decides the conversation thread's topic state for the NEXT line
/// selection. A message with no detected topic leaves the thread on
/// whatever was already active rather than losing it (a bare "ok" shouldn't
/// reset the conversation). A message that mentions the topic already in
/// play deepens it (progress+1). A message that raises a different topic
/// switches the thread to it, starting over at stage 1. When a message
/// raises more than one topic, [Set] iteration order — insertion order,
/// following [_topicLexicon]'s declaration order — picks the new thread,
/// with one carve-out: [Topic.family]'s lexicon includes direct-address
/// words ('mom', 'dad', ...) that fire on essentially every message to a
/// parent contact regardless of content ("hey mom" is addressing her, not
/// raising family as a subject) — so a bare greeting co-detected with
/// nothing but [Topic.family] stays a greeting rather than being displaced
/// by that incidental address-term match.
({Topic? topic, int progress}) advanceTopic({
  required Topic? currentTopic,
  required int currentProgress,
  required Set<Topic> messageTopics,
}) {
  if (messageTopics.isEmpty) return (topic: currentTopic, progress: currentProgress);
  if (currentTopic != null && messageTopics.contains(currentTopic)) {
    return (topic: currentTopic, progress: currentProgress + 1);
  }
  if (messageTopics.contains(Topic.greeting) &&
      messageTopics.difference({Topic.greeting, Topic.family}).isEmpty) {
    return (topic: Topic.greeting, progress: 1);
  }
  return (topic: messageTopics.first, progress: 1);
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
  final required = line.requiredMemories;
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
  return line.weight * tm * tpm * im * dm * tsm * mw * rm * rngFactor * recentPenalty * freshnessBonus;
}

/// Picks a weighted-random line from [pool] using formula 16's FinalWeight.
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

  final scores = [
    for (final l in eligible)
      _finalWeight(rng, l, ctx, currentDay, lineLastUsedDay, recentLineHistory, currentTurn: currentTurn, lineLastUsedTurn: lineLastUsedTurn),
  ];
  final total = scores.fold(0.0, (a, b) => a + b);
  var r = rng.nextDouble() * total;
  for (var i = 0; i < eligible.length; i++) {
    r -= scores[i];
    if (r <= 0) return eligible[i];
  }
  return eligible.last;
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
