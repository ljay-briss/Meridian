// Static data tables + plain models. No Flutter imports — pure Dart.
export 'dialogue_engine.dart';
import 'dialogue_engine.dart';

const List<String> kWeekdays = [
  'MONDAY', 'TUESDAY', 'WEDNESDAY', 'THURSDAY', 'FRIDAY', 'SATURDAY', 'SUNDAY',
];

const Map<int, String> kLevelTitles = {
  1: 'PLAZA LOOKOUT',
  2: 'TRANSPORTER',
  3: 'COLLECTOR',
  4: 'CELL LEADER',
  5: 'REGIONAL OPERATOR',
  6: 'PLAZA BOSS',
  7: 'CARTEL LEADER',
};

/// A quick, mechanics-first "what to do" per level — shown the first time a
/// level is entered, and re-viewable from Settings.
const Map<int, String> kTutorialBody = {
  1: 'Watch the road. A military convoy means text "bird". A rival cartel\'s SUV means text "snake". Anything harmless, leave it alone. You\'ve got 15 seconds once something rolls by — miss it or get it wrong and that\'s a warning. A second one, and there\'s no coming back.',
  2: 'Get the load across the border. At each checkpoint, pick how you handle it — paying costs cash but lowers your odds of getting stopped. Get caught twice and it\'s twenty years.',
  3: 'Work your route. Visit a stop to collect — if they won\'t pay, threaten them. Still nothing, tell your crew to vandalize the place. Tonight is safer than right now, but nothing here is ever fully safe. Report to your boss once every stop is settled — come back short, and that\'s it.',
  4: 'A hundred kilos land every month. Allocate them across your distributors on Home, then close out the month — sell to whoever pays best for the biggest cut. Check Crew and Territory before you close out — trouble there can block you, and it won\'t wait for a convenient month.',
  5: 'Five cells report to you. Every month they drift without attention, so check in on Org — you can only manage two at a time, so pick who needs it most. Handle whatever crisis comes up before you can advance the month. Let performance crash two months running and the boss replaces you.',
  6: 'You run the plaza now — territory, money, and an inner circle you can\'t fully trust. Watch Org for anyone acting off. Ignore a real threat and it keeps working against you, but kill the wrong man on a hunch and that costs you too. Heat that climbs too high brings an investigation you can\'t out-earn.',
  7: 'You\'re at the top, and there\'s nowhere left to be promoted to. Negotiate with rivals, manage the paranoia in your circle, and keep your heat down — a bounty this size doesn\'t forgive carelessness. This is the last job. You play it until you don\'t.',
};

class Contact {
  final String id, name, role, initials;
  const Contact(this.id, this.name, this.role, this.initials);
}

const List<Contact> kContacts = [
  Contact('handler', 'El Primo', 'Handler', 'P'),
  Contact('crew', 'The Crew', 'Your guys', 'C'),
];
final Map<String, Contact> kContact = {for (final c in kContacts) c.id: c};

/// Mutable mood/memory state for a cartel-side contact (currently just
/// El Primo). Lighter than [RelationshipState] — there's no closeness/trust/
/// suspicion axis here; cartelSuspicion/policeHeat already cover that
/// mechanically, this only tracks how he's currently feeling about you.
class ContactMood {
  double mood = 0;
  final List<MemoryEvent> memories = [];
  final Map<String, int> lineLastUsedDay = {}; // pickLine() variety scoring — text -> day last used
  final List<String> recentLineHistory = []; // pickLine() variety scoring — last 5 lines sent
}

// ── Cartel contact voice pools — phrasing variety for El Primo and the crew,
// picked at random (never twice in a row) around the same fixed mechanics. ──

const List<DialogueLine> kHandlerApprovalLines = [
  DialogueLine('Good eye. Stay put.'),
  DialogueLine("That's the one. Nice catch."),
  DialogueLine('Confirmed. Keep watching.'),
  DialogueLine(
    "You've been sharp all week. Keep that up.",
    when: _handlerMoodHigh,
    weight: 2.0,
  ),
];

const List<DialogueLine> kHandlerWrongLines = [
  DialogueLine("That's not good. Watch closer."),
  DialogueLine("Sloppy. Don't let that happen again."),
  DialogueLine(
    "That's not the first mistake this week. I need you sharp, not guessing.",
    when: _handlerMoodLow,
    weight: 2.0,
  ),
];

bool _handlerMoodHigh(DialogueContext ctx) => ctx.mood > 30;
bool _handlerMoodLow(DialogueContext ctx) => ctx.mood < -25;

const List<String> kCrewSuccessLines = [
  'Handled. They paid double after.',
  'Done. Message received loud and clear.',
  "Taken care of. Won't be a problem again.",
];

const List<String> kCrewFailNowLines = [
  'Cops rolled up on us. We had to bail.',
  'Someone saw us. We had to scatter.',
  'Wrong time. We got made and ran.',
];

const List<String> kCrewFailTonightLines = [
  "Somebody must've called ahead. They were ready for us.",
  'They knew we were coming. Bailed before we got close.',
  'Word got out first. We pulled back.',
];

class Message {
  final String text;
  final bool fromMe;
  const Message(this.text, this.fromMe);
}

// ── Level 1: Plaza Lookout ──────────────────────────────────────────────

enum SightingKind { military, rival, civilian }

class Sighting {
  final SightingKind kind;
  final String description;
  final String correctWord;
  const Sighting(this.kind, this.description, this.correctWord);
}

const List<Sighting> kSightingPool = [
  Sighting(SightingKind.military, 'Two military trucks roll toward the checkpoint.', 'bird'),
  Sighting(SightingKind.military, 'A convoy of federal trucks slows near the plaza.', 'bird'),
  Sighting(SightingKind.rival, 'A black SUV with tinted windows idles at the corner.', 'snake'),
  Sighting(SightingKind.rival, 'Two black SUVs circle the block twice.', 'snake'),
  Sighting(SightingKind.civilian, 'Just a delivery van. Nothing unusual.', 'clear'),
];

// ── Level 2: Transporter ────────────────────────────────────────────────

class Checkpoint {
  final String scene;
  final List<CheckpointChoice> choices;
  const Checkpoint(this.scene, this.choices);
}

class CheckpointChoice {
  final String label;
  final double riskDelta; // added to cumulative caught-chance
  final int cost;
  const CheckpointChoice(this.label, this.riskDelta, {this.cost = 0});
}

const List<Checkpoint> kCheckpoints = [
  Checkpoint('A Border Patrol checkpoint sits ahead, lights on.', [
    CheckpointChoice('Drive through calm', 0.14),
    CheckpointChoice('Slip the guard', 0.04, cost: 300),
    CheckpointChoice('Cut through the backroad', 0.08),
  ]),
  Checkpoint('A K9 unit is walking the checkpoint line.', [
    CheckpointChoice('Stay in lane', 0.18),
    CheckpointChoice('Pay off the handler', 0.05, cost: 500),
    CheckpointChoice('Detour, lose an hour', 0.07),
  ]),
  Checkpoint('Random secondary inspection zone ahead.', [
    CheckpointChoice('Roll the dice', 0.20),
    CheckpointChoice('Bribe the inspector', 0.06, cost: 400),
    CheckpointChoice('Turn back and wait it out', 0.10),
  ]),
];

// ── Level 3: Collector ──────────────────────────────────────────────────

class CollectionTarget {
  final String id, name, kind;
  final int owed;
  const CollectionTarget(this.id, this.name, this.kind, this.owed);
}

const List<CollectionTarget> kCollectionRoute = [
  CollectionTarget('taco', 'Taco Stand on 4th', 'Small business', 500),
  CollectionTarget('pharmacy', 'Farmacia Guadalupe', 'Pharmacy', 2000),
  CollectionTarget('club', 'Club Medianoche', 'Night club', 10000),
];

const List<String> kExcuses = [
  'Business is slow this week, come back later.',
  "My kid's sick, I swear I'll have it soon.",
  "I already paid your guy last week, check again.",
  'Please, I have nothing left after rent.',
];

// ── Level 4: Cell Leader ─────────────────────────────────────────────────

class Distributor {
  final String id, name;
  final double pricePerKg;
  const Distributor(this.id, this.name, this.pricePerKg);
}

const List<Distributor> kDistributors = [
  Distributor('d1', 'Downtown connect', 6500),
  Distributor('d2', 'Northside crew', 5800),
  Distributor('d3', 'Highway distributor', 7200),
];

const List<String> kCrewTroubleEvents = [
  '{name} got high on the product and mouthed off in public.',
  '{name} flashed cash at a bar and drew attention.',
  '{name} skimmed product for himself.',
  '{name} got into a fight over a girl at the wrong bar.',
];

const List<String> kCrewNamesPool = [
  'Beto', 'Chuy', 'Flaco', 'Tavo', 'Nene', 'Chino', 'Pelón', 'Güero', 'Tigre', 'Cholo',
];

/// Flavor-only reminders that the regional boss is always watching the bottom line.
const List<String> kBossPressureLines = [
  'The regional boss wants to know why last month wasn\'t bigger.',
  'Word from up top: quotas go up, not down. Figure it out.',
  'The boss doesn\'t care about your problems. He cares about the number.',
];

// ── Level 5-7: strategic layer ───────────────────────────────────────────

class CellLeaderRecord {
  final String name;
  double performance; // 0..1
  double loyalty; // 0..1
  CellLeaderRecord(this.name, this.performance, this.loyalty);
}

class Territory {
  final String name;
  bool controlled;
  Territory(this.name, this.controlled);
}

const List<String> kTerritoryNames = ['Sinaloa', 'Sonora', 'Tamaulipas', 'Veracruz', 'Chihuahua'];

const List<String> kOfficialTitles = [
  'Local police chief', 'State prosecutor', 'Customs supervisor', 'Regional governor',
];

// ── Levels 6-7: inner circle ──────────────────────────────────────────────

class InnerCircleMember {
  final String id, name, role;
  const InnerCircleMember(this.id, this.name, this.role);
}

const List<InnerCircleMember> kInnerCircle = [
  InnerCircleMember('security', 'Ramiro', 'Security chief'),
  InnerCircleMember('accountant', 'Doña Elena', 'Accountant'),
  InnerCircleMember('righthand', 'Beto', 'Right hand'),
  InnerCircleMember('courier', 'Nayeli', 'Courier'),
];

/// {name} is substituted with the flagged member's name. Deliberately never
/// says whether the tip is true — the player has to decide on ambiguity alone.
const List<String> kParanoiaLines = [
  '{name} has been unreachable for two days. Could be nothing.',
  '{name} was seen talking to someone nobody recognized.',
  'The numbers on {name}\'s side don\'t quite add up. Probably nothing.',
  'Someone says {name} has been asking questions they shouldn\'t.',
];

// ── Levels 5-7: money laundering fronts ──────────────────────────────────

const List<String> kLaunderFronts = [
  'La Cocina Del Rey restaurant',
  'Brillo Total car wash',
  'Constructora Alvarado',
];

// ── Personal relationships ───────────────────────────────────────────────

/// A personal contact — separate from the cartel-side [Contact]s. Tracks
/// hidden closeness/trust/suspicion stats via [RelationshipState] on the controller.
class PersonalContact {
  final String id, name, relation, initials;
  final double suspicionRate; // multiplier on how fast suspicion climbs for this person
  final double initiative; // base per-tick chance of an unprompted text; 0.4 = the old flat chance
  final double moodSensitivity; // how much current mood swings that chance; 0 = mood has no effect
  final double emotionalVolatility; // 0..1 -> personalityModifier(), which ranges 0.5 (stable) to 1.0 (volatile)
  final double personalityWarmth; // 0..100 -> baselineAttraction(); 50 = no drift (old behavior)
  const PersonalContact(
    this.id,
    this.name,
    this.relation,
    this.initials, {
    this.suspicionRate = 1.0,
    this.initiative = 0.4,
    this.moodSensitivity = 0.0,
    this.emotionalVolatility = 0.5,
    this.personalityWarmth = 50,
  });
}

const List<PersonalContact> kPersonalContacts = [
  PersonalContact('mama', 'Mamá', 'Mother', 'M',
      suspicionRate: 0.6, initiative: 0.35, moodSensitivity: 0.35, emotionalVolatility: 0.3, personalityWarmth: 70),
  PersonalContact('partner', 'Vale', 'Partner', 'V',
      suspicionRate: 1.4, initiative: 0.45, moodSensitivity: 0.6, emotionalVolatility: 0.7, personalityWarmth: 55),
  PersonalContact('friend', 'Kiko', 'Best friend', 'K', emotionalVolatility: 0.6, personalityWarmth: 60),
  PersonalContact('brother', 'Tono', 'Brother', 'T', emotionalVolatility: 0.4, personalityWarmth: 55),
  PersonalContact('oldfriend', 'Marco', 'Old friend', 'M', emotionalVolatility: 0.3, personalityWarmth: 60),
];
final Map<String, PersonalContact> kPersonalContact = {for (final p in kPersonalContacts) p.id: p};

/// Who plausibly talks to whom outside the player's view — a minimal,
/// single-hop "word gets around" graph, not a general rumor network. Mama and
/// her son Tono are family; Vale and Kiko are close enough day-to-day that
/// one would mention it to the other. Marco has moved on and isn't in either
/// loop, which fits his character.
const Map<String, String> kRelationshipLinks = {
  'mama': 'brother',
  'brother': 'mama',
  'partner': 'friend',
  'friend': 'partner',
};

/// Mutable hidden stats for one personal relationship.
class RelationshipState {
  double closeness = 50;
  double trust = 50;
  double suspicion = 0;
  double mood = 0; // short-term, -100..100, decays toward baselineAttraction() every tick
  double warmthOffset = 0; // -15..15; nudged by sustained tone patterns, shifts baselineAttraction over time
  double fear = 0; // 0..100, decays toward 0 every tick — see nudgeFear()
  double respect = 0; // 0..100, sticky — see nudgeRespect()
  double debt = 0; // 0..100, sticky — see nudgeDebt()
  int betrayalCount = 0; // backfired-excuse count; trust<15 && this>=2 triggers isBlocked
  bool isBlocked = false; // block consequence fired — ignores further replies/initiative
  int daysSinceReply = 0;
  bool goneQuiet = false; // trust hit 0
  bool resolved = false; // suspicion-100 ending already fired
  bool flaggedByBoss = false; // boss has already warned about this one
  bool unread = false;
  bool followUpSent = false; // guards the one-time "you good?" nudge per ignore-streak
  String? lastLine; // last opener/questioning/distant line shown
  final List<ReplyTone> recentTones = []; // ring buffer of the player's last few tone choices
  final List<MemoryEvent> memories = []; // capped long-term milestone log
  final Map<String, int> lineLastUsedDay = {}; // pickLine() variety scoring — text -> day last used
  final List<String> recentLineHistory = []; // pickLine() variety scoring — last 5 lines sent, any pool
  Topic? currentTopic; // the topic this conversation thread is presently on — see advanceTopic()
  int topicProgress = 0; // turns spent on currentTopic; 0 when there's no active thread
  bool lastQuestionAnswered = true; // false while a mama-asked Intent.question line is awaiting a real reply

  // Spam / repetition tracking.
  String? lastActionLabel; // label of the most-recent player action
  int consecutiveActionCount = 0; // increments when player repeats the same action back-to-back

  // Within-day memory — cleared each morning tick.
  final Map<String, int> todayActionCounts = {}; // label → how many times sent today
  final Set<Topic> topicsDiscussedToday = {}; // topics the player has brought up today

  // ── Short-term conversation memory (intent-chip system) ──────────────────
  int turnCount = 0; // increments once per personalReplyAction() call — drives recallWithinTurns/turn-granularity freshness, distinct from the game's day/TimeOfDay tick
  final Map<String, int> lineLastUsedTurn = {}; // pickLine() turn-granularity freshness — see recordLineUse's turn param
  final List<ConversationEvent> recentConversation = []; // rolling window, read by recallMatch() — see CareerController._pruneConversationMemory for the eviction rule
}

/// Character-specific message pools tied to the relationship thresholds.
/// [openers]/[questioning]/[distant] are conditional line pools — most
/// entries are always-eligible, but a character can carry a few lines that
/// only surface under specific mood/memory/pattern conditions (see [DialogueLine]).
class RelationshipContent {
  final List<DialogueLine> openers; // topics they bring up unprompted — suspicion < 60
  final List<DialogueLine> questioning; // suspicion 60-79
  final List<DialogueLine> distant; // suspicion >= 80
  final List<DialogueLine> confrontation; // suspicion hits 100 — fires once, picked like any other pool
  final List<DialogueLine> goneQuietLine; // trust hits 0 — fires once, picked like any other pool
  final List<DialogueLine> followUp; // sent once if left on read too long — picked like any other pool
  final List<DialogueLine> spamReactions; // override pool when player sends same action back-to-back
  final List<DialogueLine> dailyRepeatReactions; // override pool when player repeats same action later the same day
  // Last-resort net: CareerController.personalReplyAction falls back to this
  // pool whenever pickLine() comes back null on every other tier (every line
  // in the chosen pool got gated out for the current mood/trust/topic/etc.
  // state) — so the character never goes silently unresponsive to something
  // the player actually said. Every line here should stay ungated (no
  // when/moodMin/etc.) so pickLine() is guaranteed to find one eligible.
  final List<DialogueLine> fallbackReactions;
  const RelationshipContent({
    required this.openers,
    required this.questioning,
    required this.distant,
    required this.confrontation,
    required this.goneQuietLine,
    required this.followUp,
    this.spamReactions = const [],
    this.dailyRepeatReactions = const [],
    this.fallbackReactions = const [],
  });
}

/// A tappable reply option in a personal thread — replaces free-text typing.
/// Where [classifyMessage] used to infer (tone, topics, intent, intensity)
/// from whatever the player typed, an action declares them directly, so
/// picking one is self-classifying and skips the lexicon classifier
/// entirely. Everything downstream of classification — relationship-stat
/// deltas, topic-thread tracking, memory, and same-turn reaction-line
/// selection via [pickLine] — is unchanged, so replies still land
/// differently depending on relationship state, mood, and history.
///
/// [resolveText] picks the right wording for the current moment: mood-tier
/// variants take priority, then time-of-day variants, then the plain [text]
/// fallback. This keeps the thread feeling alive without adding engine
/// complexity — only [data.dart] content grows as more variants are written.
class PersonalReplyAction {
  final String label; // shown on the option button
  final String text; // default/fallback text added to the thread
  final ReplyTone tone;
  final Set<Topic> topics;
  final Intent intent;
  final double intensity; // 0..1 — feeds impactMultiplier/nudgeFear/nudgeRespect
  final bool isDebtTopic; // feeds nudgeDebt
  final Set<String>? allowedContacts; // null = offered to every personal contact

  // Time-of-day text variants — null means fall through to [text].
  final String? textMorning;
  final String? textEvening;
  final String? textNight;

  // Mood-tier text variants — checked before time-of-day variants.
  final String? textWhenLowMood;  // mood < -30
  final String? textWhenHighMood; // mood > 30

  // Visibility gates — action is excluded from the menu when the gate fails.
  // [showWhenMoodBelow]: only offered when mood < threshold (e.g. repair actions).
  // [showWhenMoodAbove]: only offered when mood > threshold (e.g. playful actions).
  // [requiresThread]: only offered once the thread has at least one message.
  // [showWhenLevelMin/Max]: ties the option to a story-level window.
  // [showWhenTrustBelow/Above]: trust-based gates.
  // [showWhenSuspicionAbove]: surfaces when the character is already suspicious.
  // [showWhenClosenessAbove]: surfaces only in close relationships.
  final double? showWhenMoodBelow;
  final double? showWhenMoodAbove;
  final bool requiresThread;
  final int? showWhenLevelMin;   // only shown at this level or above
  final int? showWhenLevelMax;   // only shown at this level or below
  final double? showWhenTrustBelow;
  final double? showWhenTrustAbove;
  final double? showWhenSuspicionAbove;
  final double? showWhenClosenessAbove;

  /// Set only when this action was synthesized by [CareerController.sendIntent]
  /// from an [IntentChip] — null for every entry in [kPersonalReplyActions]
  /// (the legacy scripted-sentence catalog), which keeps their behavior
  /// completely unchanged: personalReplyAction() only looks up
  /// kMamaIntentReactions when this is non-null.
  final ConversationIntent? conversationIntent;

  const PersonalReplyAction(
    this.label,
    this.text, {
    required this.tone,
    this.topics = const {},
    required this.intent,
    this.intensity = 0.5,
    this.isDebtTopic = false,
    this.conversationIntent,
    this.allowedContacts,
    this.textMorning,
    this.textEvening,
    this.textNight,
    this.textWhenLowMood,
    this.textWhenHighMood,
    this.showWhenMoodBelow,
    this.showWhenMoodAbove,
    this.requiresThread = false,
    this.showWhenLevelMin,
    this.showWhenLevelMax,
    this.showWhenTrustBelow,
    this.showWhenTrustAbove,
    this.showWhenSuspicionAbove,
    this.showWhenClosenessAbove,
  });

  /// Returns the most contextually appropriate wording for this action right
  /// now. Mood-tier variants win first (her current emotional state is the
  /// strongest context signal), then time-of-day, then plain [text].
  String resolveText(RelationshipState rel, TimeOfDay tod) {
    if (rel.mood < -30 && textWhenLowMood != null) return textWhenLowMood!;
    if (rel.mood > 30 && textWhenHighMood != null) return textWhenHighMood!;
    return switch (tod) {
      TimeOfDay.morning => textMorning ?? text,
      TimeOfDay.evening => textEvening ?? text,
      TimeOfDay.night   => textNight   ?? text,
      _                 => text,
    };
  }
}

/// Full catalog of reply options. Never shown all at once — see
/// [CareerController.personalReplyOptions], which narrows this to half the
/// menu, picked by contact fit and by the live conversation's context.
///
/// Actions with [allowedContacts] are only offered for those contacts.
/// Actions with visibility gates ([showWhenMoodBelow]/[showWhenMoodAbove]/
/// [requiresThread]) are filtered out when the gate fails, so they only
/// surface when they actually make sense. Text variants ([textMorning] etc.)
/// are resolved at render and send time by [PersonalReplyAction.resolveText].
const List<PersonalReplyAction> kPersonalReplyActions = [
  PersonalReplyAction(
    'Greet', 'Hey! 👋',
    tone: ReplyTone.warm, topics: {Topic.greeting}, intent: Intent.statement, intensity: 0.4,
    textMorning: 'Morning! Hope you slept well. ☀️',
    textEvening: "Hey, how's your evening going? 😊",
    textNight: 'Hey… you still up? 🌙',
    textWhenLowMood: "Hi… I've been thinking about you.",
    textWhenHighMood: 'Hey!! 😊 Just wanted to say hi!',
  ),
  PersonalReplyAction('Flirt', "Can't stop thinking about you. 😏",
      tone: ReplyTone.warm, topics: {Topic.affection}, intent: Intent.confession, intensity: 0.6, allowedContacts: {'partner'}),
  PersonalReplyAction(
    'Reassure', "I've got you. I promise.",
    tone: ReplyTone.warm, intent: Intent.promise, intensity: 0.6,
    textMorning: "Just wanted you to know I'm thinking about you today. ❤️",
    textEvening: "I hope today was okay. I'm here if you need me.",
    textNight: "You okay? I'm here.",
    textWhenLowMood: "I know things feel off between us. I'm still here, okay?",
    textWhenHighMood: "I'm good, I promise. Take care of yourself too. ❤️",
  ),
  PersonalReplyAction('Be honest', "Honestly? Here's what's going on.", tone: ReplyTone.honest, intent: Intent.statement, intensity: 0.5),
  PersonalReplyAction(
    'Ask how they are', 'How are you doing?',
    tone: ReplyTone.honest, topics: {Topic.wellbeing}, intent: Intent.question, intensity: 0.4,
    textMorning: 'How are you feeling this morning?',
    textEvening: 'How was your day?',
    textNight: "You good? It's late.",
    textWhenLowMood: "Are you okay? I've been worried about you.",
    textWhenHighMood: 'How are you? Tell me something good.',
  ),
  PersonalReplyAction(
    'Ask about family', "How's the family?",
    tone: ReplyTone.honest, topics: {Topic.family}, intent: Intent.question, intensity: 0.4,
    textMorning: "How's everyone doing this morning?",
    textEvening: "How's everyone? How's Tono?",
  ),
  PersonalReplyAction('Push for answers', "What's going on with you? Something feels off.", tone: ReplyTone.honest, topics: {Topic.suspicion}, intent: Intent.question, intensity: 0.6),
  PersonalReplyAction(
    'Stay vague', "It's complicated. I don't really know.",
    tone: ReplyTone.vague, intent: Intent.statement, intensity: 0.4,
    textWhenLowMood: "I don't know, okay? It's hard to explain right now.",
    textMorning: "I haven't even had coffee yet. Let's talk later.",
    textNight: "It's late. Not the right time for this.",
  ),
  PersonalReplyAction(
    'Make an excuse', "Work ran late, that's all it was.",
    tone: ReplyTone.excuse, intent: Intent.statement, intensity: 0.5,
    textMorning: "Got held up with work stuff this morning, that's it.",
    textWhenLowMood: "I know how it looks. I can't explain everything right now.",
  ),
  PersonalReplyAction(
    'Brush off', 'Not now. Drop it.',
    tone: ReplyTone.cold, intent: Intent.dismissal, intensity: 0.5,
    textMorning: "Not now. It's too early for this.",
    textNight: "I'm tired. We're not doing this tonight.",
  ),
  PersonalReplyAction('Insult', "You're impossible to deal with.", tone: ReplyTone.cold, intent: Intent.dismissal, intensity: 0.9),
  PersonalReplyAction('Talk about money', "I need to figure out this money situation. I'll pay you back.",
      tone: ReplyTone.warm, topics: {Topic.money}, intent: Intent.promise, intensity: 0.6, isDebtTopic: true),
  PersonalReplyAction('Deflect about money', "Not now, I don't want to talk about the rent.",
      tone: ReplyTone.cold, topics: {Topic.money}, intent: Intent.dismissal, intensity: 0.5, isDebtTopic: true),

  // ── Mamá-specific actions ─────────────────────────────────────────────
  // "Make it right" only surfaces when her mood has dropped below -30 — it's
  // a repair move, not a normal opener, so gateing it keeps it feeling earned.
  PersonalReplyAction(
    'Make it right', "I know I've been distant, Mamá. I'm sorry. ❤️",
    tone: ReplyTone.warm, intent: Intent.promise, intensity: 0.8,
    allowedContacts: {'mama'},
    showWhenMoodBelow: -30,
    textWhenLowMood: "I hate that I made you feel like this. I'm sorry, Mamá. ❤️",
  ),
  // "Check in" is a low-pressure invest action — available once the thread has
  // started, when mood isn't already badly negative (no point offering it mid-fight).
  PersonalReplyAction(
    'Check in', 'Just checking in. Thinking about you. 💙',
    tone: ReplyTone.warm, topics: {Topic.wellbeing}, intent: Intent.statement, intensity: 0.4,
    allowedContacts: {'mama'},
    requiresThread: true,
    showWhenMoodAbove: -20,
    textMorning: "Good morning, Mamá. Just wanted you to know I'm thinking about you. ☀️",
    textEvening: 'Evening, Mamá. Just checking in. How are you holding up?',
    textNight: 'Mamá, still up? I was just thinking about you.',
    textWhenHighMood: "Mamá! 😊 I'm having a good day and wanted to share that with you.",
  ),

  // ── Story-aware / level-gated mama actions ────────────────────────────────
  // These surface as the player's situation evolves. Early-game options feel
  // natural and open; mid-game options carry the weight of growing distance;
  // late-game options reflect guilt, fear of being found out, or desperation
  // to maintain the relationship despite everything.

  // Early game (levels 1–3): player can still be genuinely open.
  PersonalReplyAction(
    'Tell her about your day', "Had a pretty normal day, Mamá. Nothing crazy.",
    tone: ReplyTone.honest, topics: {Topic.wellbeing}, intent: Intent.statement, intensity: 0.4,
    allowedContacts: {'mama'},
    showWhenLevelMax: 3,
    textMorning: "Morning just started but I'm already thinking of you, Mamá.",
    textEvening: "Day's winding down. Wasn't too bad, honestly.",
  ),
  PersonalReplyAction(
    'Share something good', "Something actually went right today. Feels weird to say.",
    tone: ReplyTone.warm, topics: {Topic.wellbeing}, intent: Intent.statement, intensity: 0.5,
    allowedContacts: {'mama'},
    showWhenLevelMax: 3,
    showWhenMoodAbove: 10,
  ),

  // Mid game (levels 4–6): things are getting complicated; deflection and distance.
  PersonalReplyAction(
    'Brush it off', "Things are just busy right now, Mamá. Nothing to worry about.",
    tone: ReplyTone.vague, topics: {Topic.wellbeing}, intent: Intent.dismissal, intensity: 0.4,
    allowedContacts: {'mama'},
    showWhenLevelMin: 4,
    showWhenLevelMax: 7,
    textWhenLowMood: "I'm fine, Mamá. Please don't read into it.",
  ),
  PersonalReplyAction(
    'Reassure her', "I promise I'm being careful. I love you, Mamá.",
    tone: ReplyTone.warm, topics: {Topic.affection}, intent: Intent.promise, intensity: 0.6,
    allowedContacts: {'mama'},
    showWhenLevelMin: 4,
    showWhenMoodBelow: 0,
    textWhenLowMood: "Mamá, I know you're worried. I need you to trust me right now.",
  ),
  PersonalReplyAction(
    'Change the subject', "Anyway, how are YOU doing? How's the garden?",
    tone: ReplyTone.vague, topics: {Topic.family}, intent: Intent.dismissal, intensity: 0.3,
    allowedContacts: {'mama'},
    showWhenLevelMin: 4,
    showWhenSuspicionAbove: 30,
  ),

  // High-suspicion options (she's already worried).
  PersonalReplyAction(
    'Deny everything', "I don't know what you've heard, Mamá, but it's not true.",
    tone: ReplyTone.excuse, topics: {Topic.suspicion}, intent: Intent.statement, intensity: 0.7,
    allowedContacts: {'mama'},
    showWhenSuspicionAbove: 50,
    showWhenLevelMin: 3,
    textWhenLowMood: "Mamá, please. Whatever you think is going on — it isn't.",
  ),
  PersonalReplyAction(
    'Come clean (a little)', "Okay. Things have been… complicated. But I'm handling it.",
    tone: ReplyTone.honest, topics: {Topic.suspicion, Topic.wellbeing}, intent: Intent.statement, intensity: 0.7,
    allowedContacts: {'mama'},
    showWhenSuspicionAbove: 40,
    showWhenLevelMin: 4,
    showWhenTrustAbove: 45,
  ),

  // High closeness — only available when you've built real trust.
  PersonalReplyAction(
    'Open up', "Things have been hard, Mamá. I don't always know how to talk about it.",
    tone: ReplyTone.honest, topics: {Topic.wellbeing, Topic.affection}, intent: Intent.statement, intensity: 0.6,
    allowedContacts: {'mama'},
    showWhenClosenessAbove: 65,
    showWhenLevelMin: 4,
    textWhenLowMood: "Mamá, I've been carrying a lot. I'm not sure I'm okay.",
  ),

  // Late game (levels 7+): the weight of what the player's doing starts to show.
  PersonalReplyAction(
    'Apologize for real', "I'm sorry, Mamá. For everything. I don't want to lose you.",
    tone: ReplyTone.warm, topics: {Topic.affection, Topic.suspicion}, intent: Intent.promise, intensity: 0.9,
    allowedContacts: {'mama'},
    showWhenLevelMin: 7,
    textWhenLowMood: "Mamá... I know I've hurt you. I'm so, so sorry.",
  ),
  PersonalReplyAction(
    'Keep her at a distance', "I care about you too much to drag you into this. Please understand.",
    tone: ReplyTone.cold, topics: {Topic.suspicion}, intent: Intent.dismissal, intensity: 0.6,
    allowedContacts: {'mama'},
    showWhenLevelMin: 7,
    showWhenTrustBelow: 60,
  ),
  PersonalReplyAction(
    'Tell her you miss her', "I miss you, Mamá. I miss who I used to be when I was home.",
    tone: ReplyTone.warm, topics: {Topic.affection, Topic.family}, intent: Intent.statement, intensity: 0.7,
    allowedContacts: {'mama'},
    showWhenLevelMin: 6,
    showWhenClosenessAbove: 50,
  ),
];

/// Short same-turn reaction sent back immediately after the player picks a
/// [PersonalReplyAction] (each pre-tagged with a [ReplyTone]), keyed by
/// contact then tone. Fires right on the thread screen so texting feels like
/// a live conversation — the day/cycle tick still drives the longer-arc
/// unprompted openers/questioning/distant lines between sessions.
///
/// This is the single most-repeated message in the whole game — it fires on
/// every reply, in every conversation — so it gets a small pool per tone
/// (picked with the same avoid-repeat rule as everything else) instead of one
/// fixed line. A flat, unvarying line here is the fastest way for the whole
/// system to read as robotic, no matter how much variety exists elsewhere.
const Map<String, Map<ReplyTone, List<DialogueLine>>> kPersonalReactions = {
  'mama': {
    ReplyTone.warm: [
      DialogueLine('Aww, I love you too, mijo. Be safe. ❤️', weight: 2.0),
      DialogueLine('That means everything to me, mijo. Come see me soon, okay?', weight: 2.0, topic: Topic.family),
      DialogueLine('You have no idea how much I needed to hear that, mijo.', weight: 1.8),
      DialogueLine('My sweet boy. I worry about you every day. Stay safe.', weight: 1.5),
      DialogueLine("I'm so proud of the person you've become, mijo.", weight: 1.5),
      DialogueLine('Every time I hear from you, my heart feels lighter. ❤️', weight: 1.5),
      DialogueLine('You know you can always come home, right? No matter what.', weight: 1.5),
      DialogueLine('I was just thinking about you. You must have felt it.', weight: 1.0, topic: Topic.greeting),
      DialogueLine('Your smile is the best thing in my day, mijo.', weight: 1.0),
      DialogueLine("Don't forget to eat something. You're too skinny.", weight: 1.5, topic: Topic.health),
      DialogueLine('Mijo, you made my whole week.', weight: 1.5),
      DialogueLine('God, I love you so much. Please be careful.', weight: 1.5),
      DialogueLine("You better call me tomorrow too. I'm holding you to it.", weight: 1.0),
      DialogueLine("I'm crying a little. Happy tears. You're such a good son.", weight: 1.0),
      DialogueLine("Ok, I'm not crying. You are. Shut up. I love you.", weight: 1.0),
      DialogueLine("I don't know what I did to deserve you, mijo.", weight: 1.0),
      DialogueLine("You're the best thing I ever did, you know that?", weight: 1.0),
      DialogueLine("Call me when you get home safe. I'll be waiting up.", weight: 1.5, topic: Topic.plans),
      DialogueLine('I was so worried about you. But now I\'m not. Thanks, mijo.', weight: 1.0),
      DialogueLine("I don't say it enough. But you're everything to me.", weight: 1.5),
      DialogueLine('Ay, mijo. You have no idea how happy that makes me.', weight: 1.0),
      DialogueLine("That's my boy. I love you more than you know.", weight: 1.0),
      DialogueLine('You just made my whole day, mijo.', weight: 1.0),
      DialogueLine("I'm smiling so big right now, mijo.", weight: 1.0),
      DialogueLine("Every word you just said, I'm keeping in my heart.", weight: 1.0),
      DialogueLine("You're such a good son. The best.", weight: 1.0),
      DialogueLine('I love you to the moon and back, mijo.', weight: 1.0),
      DialogueLine("Come here — well, if you were here, I'd hug you so tight.", weight: 1.0),
      DialogueLine("That's exactly what I needed to hear today.", weight: 1.0),
      DialogueLine('I could cry, mijo. In a good way.', weight: 1.0),
      DialogueLine('You always know how to make your mother smile.', weight: 1.0),
      DialogueLine("I'm going to tell your aunt what you just said. She'll cry too.", weight: 1.0, topic: Topic.family),
      DialogueLine('You\'re the light of my life, mijo.', weight: 1.5),
      DialogueLine('Never stop being this sweet with me, okay?', weight: 1.0),
      DialogueLine("I don't care what anyone says, you're a good boy.", weight: 1.0),
      DialogueLine("That's my heart right there. You are.", weight: 1.0),
      DialogueLine('Even on my worst days, hearing from you fixes it.', weight: 1.5),
      DialogueLine('You make all the hard days worth it, mijo.', weight: 1.0),
      DialogueLine('I keep every message you send me. Every single one.', weight: 1.0),
      DialogueLine('God bless you, mijo. I mean that.', weight: 1.0),
      DialogueLine("You're going to make some woman very happy one day.", weight: 1.0),
      DialogueLine('I light a candle for you every Sunday, you know.', weight: 1.0),
      DialogueLine('Nothing makes me happier than hearing from my son.', weight: 1.5),
      DialogueLine('I love you more than words, mijo.', weight: 1.0),
      DialogueLine("You're everything I prayed for.", weight: 1.0),
      DialogueLine("I'm putting your picture up on the fridge again.", weight: 1.0),
      DialogueLine('That warms my whole heart, mijo.', weight: 1.0),
      DialogueLine("I'll never get tired of hearing that from you.", weight: 1.0),
      DialogueLine("You're my proudest achievement, you know that?", weight: 1.0),
      DialogueLine('Sending you all my love right now, mijo.', weight: 1.0),
      // Greeting-topic replies — a bare "hey"/"hi" reads as warm (see
      // _classifyTone) and should open the conversation and invite more,
      // not just react in the abstract. Stage 2 covers the player just
      // saying hi again without picking up the thread.
      DialogueLine('Hola mijo! I was just thinking about you. How are you doing?', weight: 2.0, topic: Topic.greeting),
      DialogueLine('Hey, mijo! Good to hear from you. What\'s going on with you today?', weight: 1.8, topic: Topic.greeting),
      DialogueLine('Ay, hola! There\'s my son. How\'s your day been?', weight: 1.5, topic: Topic.greeting),
      DialogueLine("Hi, mijo. You caught me at a good time — what's up?", weight: 1.5, topic: Topic.greeting),
      DialogueLine(
        "Back again already? I like that. Everything alright though?",
        weight: 1.5,
        topic: Topic.greeting,
        progressionMin: 2,
      ),
      DialogueLine(
        "Hi again, mijo. You keep saying hi and running off — talk to me a little.",
        weight: 1.3,
        topic: Topic.greeting,
        progressionMin: 2,
      ),
      DialogueLine('Well hello, sudden change of heart. Not that I mind, mijo.', weight: 1.2, acknowledgesToneShift: true),
      DialogueLine('Okay. A second ago I was worried. Now this. I\'ll take it though.', weight: 1.2, acknowledgesToneShift: true),
      DialogueLine('A moment ago you were cold. Now this. My heart doesn\'t know what to do, mijo.', weight: 1.0, acknowledgesToneShift: true),
      // ── Topic-matched warm reactions ────────────────────────────────────────
      // Each topic has TWO tiers:
      //   1. Curiosity/follow-up lines (weight 2.5–3.0) — surfaces when the
      //      player's message is open-ended or hints at something.
      //   2. Receiving/reassurance lines (weight 1.3–2.0) — fallback when the
      //      player has already given enough detail.
      // The 6× topicMatch multiplier in pickLine means these dominate over the
      // generic warm pool whenever the player's topic matches.

      // MONEY ─────────────────────────────────────────────────────────────────
      DialogueLine("Money stuff — what happened? Walk me through it, mijo.", weight: 3.0, topic: Topic.money),
      DialogueLine("Hold on. Something with money? Tell me what's going on.", weight: 3.0, topic: Topic.money),
      DialogueLine("Okay okay okay. Tell me about this money thing. All of it.", weight: 2.8, topic: Topic.money),
      DialogueLine("You mentioned money — is everything alright? Talk to me.", weight: 2.8, topic: Topic.money),
      DialogueLine("Mijo, don't dance around it. What's the money situation?", weight: 2.5, topic: Topic.money),
      DialogueLine("How bad is it? I want to know. Don't protect me from it.", weight: 2.5, topic: Topic.money),
      DialogueLine("Wait, you said money. I'm listening. What's going on?", weight: 2.5, topic: Topic.money),
      DialogueLine("I can hear it in your message. What's happening with the money?", weight: 2.2, topic: Topic.money),
      DialogueLine("You didn't have to bring that up. But I'm glad you did. Tell me more.", weight: 2.2, topic: Topic.money),
      DialogueLine("Something with money means something with you. Talk to me, mijo.", weight: 2.0, topic: Topic.money),
      // money receiving
      DialogueLine("Money stuff stresses me out for you. But I trust you, mijo. You'll figure it out.", weight: 1.8, topic: Topic.money),
      DialogueLine("Don't let that money situation eat you up. You're smart. You'll sort it out.", weight: 1.5, topic: Topic.money),
      DialogueLine("I know you will, mijo. You always find a way. Just don't do anything stupid.", weight: 1.3, topic: Topic.money),

      // HEALTH ─────────────────────────────────────────────────────────────────
      DialogueLine("Something with your health? Mijo, talk to me. What's going on?", weight: 3.0, topic: Topic.health),
      DialogueLine("Wait — are you okay? What happened?", weight: 3.0, topic: Topic.health),
      DialogueLine("Your health? Say more. I need to know you're okay.", weight: 2.8, topic: Topic.health),
      DialogueLine("Mijo, don't just drop that and move on. Are you alright?", weight: 2.8, topic: Topic.health),
      DialogueLine("What do you mean? Are you sick? Tell me what's happening.", weight: 2.5, topic: Topic.health),
      DialogueLine("You're worrying me. Tell me everything. Don't skip anything.", weight: 2.5, topic: Topic.health),
      DialogueLine("What kind of health thing? Start from the beginning.", weight: 2.5, topic: Topic.health),
      DialogueLine("Okay, I need more than that. What's going on with you?", weight: 2.2, topic: Topic.health),
      DialogueLine("Your health is not something you brush past. Tell me, mijo.", weight: 2.2, topic: Topic.health),
      DialogueLine("You can't say something like that and just move on. What happened?", weight: 2.0, topic: Topic.health),
      DialogueLine("I swear I felt something in my heart just now. Are you okay?", weight: 2.0, topic: Topic.health),
      // health receiving
      DialogueLine("Your health is everything, mijo. Please, PLEASE take care of yourself.", weight: 1.8, topic: Topic.health),
      DialogueLine("I'm glad you're okay. Eat something. Rest. Don't push yourself too hard.", weight: 1.5, topic: Topic.health),

      // PLANS ──────────────────────────────────────────────────────────────────
      DialogueLine("Ooh, plans! Tell me. What are you thinking, mijo?", weight: 3.0, topic: Topic.plans),
      DialogueLine("You have something going on? I want to hear all of it.", weight: 3.0, topic: Topic.plans),
      DialogueLine("What kind of plans? Come on, tell me everything.", weight: 2.8, topic: Topic.plans),
      DialogueLine("Okay I'm curious now. What are you planning?", weight: 2.8, topic: Topic.plans),
      DialogueLine("You got something in the works? Tell your mother.", weight: 2.5, topic: Topic.plans),
      DialogueLine("Plans? What plans? Don't leave me guessing, mijo.", weight: 2.5, topic: Topic.plans),
      DialogueLine("Something's happening and you want to tell me. So tell me.", weight: 2.5, topic: Topic.plans),
      DialogueLine("You're keeping something back. What's the plan, mijo?", weight: 2.2, topic: Topic.plans),
      DialogueLine("I like that you're thinking ahead. Now tell me about it.", weight: 2.2, topic: Topic.plans),
      DialogueLine("What's coming up? I want to know your plans.", weight: 2.0, topic: Topic.plans),
      DialogueLine("You've got that tone — something's happening. Tell me.", weight: 2.0, topic: Topic.plans),
      // plans receiving
      DialogueLine("I'll hold you to that, mijo. You better show up.", weight: 1.8, topic: Topic.plans),
      DialogueLine("Good. I'll start cooking. You bring the appetite.", weight: 1.5, topic: Topic.plans),

      // FAMILY ─────────────────────────────────────────────────────────────────
      DialogueLine("Family stuff — what happened? Tell me.", weight: 3.0, topic: Topic.family),
      DialogueLine("Something with family? Who? What happened?", weight: 3.0, topic: Topic.family),
      DialogueLine("Mijo, don't be vague with me about family. Talk to me.", weight: 2.8, topic: Topic.family),
      DialogueLine("What's going on? Is everyone okay?", weight: 2.8, topic: Topic.family),
      DialogueLine("You mentioned family — what's the situation?", weight: 2.5, topic: Topic.family),
      DialogueLine("Okay, what happened? I need to know.", weight: 2.5, topic: Topic.family),
      DialogueLine("Family can be complicated. Tell me what's going on.", weight: 2.5, topic: Topic.family),
      DialogueLine("I'm your mother. Whatever happened with family, I want to know.", weight: 2.2, topic: Topic.family),
      DialogueLine("You brought up family — don't drop it there. Keep going.", weight: 2.2, topic: Topic.family),
      DialogueLine("Something happened. I can feel it. Tell me everything.", weight: 2.0, topic: Topic.family),
      DialogueLine("Start from the beginning, mijo. What's going on with everyone?", weight: 2.0, topic: Topic.family),
      // family receiving
      DialogueLine("That means everything to me, mijo. Family first. Always.", weight: 1.8, topic: Topic.family),
      DialogueLine("I'm glad you feel that way. Never forget where you come from.", weight: 1.5, topic: Topic.family),

      // WELLBEING ──────────────────────────────────────────────────────────────
      DialogueLine("Ohhh, tell me about it! What happened?", weight: 3.0, topic: Topic.wellbeing),
      DialogueLine("Wait — something went right? Don't stop there, mijo. Tell me everything.", weight: 3.0, topic: Topic.wellbeing),
      DialogueLine("Oh yeah? I want to hear this. What happened?", weight: 2.8, topic: Topic.wellbeing),
      DialogueLine("Something went right? Okay, I need details. Talk to me.", weight: 2.5, topic: Topic.wellbeing),
      DialogueLine("Really?! See — I told you things would turn around. Now tell me.", weight: 2.5, topic: Topic.wellbeing),
      DialogueLine("Mijo, don't leave me hanging. What is it?", weight: 2.5, topic: Topic.wellbeing),
      DialogueLine("That's what I like to hear. Now keep going — what went right?", weight: 2.2, topic: Topic.wellbeing),
      DialogueLine("Okay good. Now sit down and tell your mother everything.", weight: 2.2, topic: Topic.wellbeing),
      DialogueLine("You're holding back. Don't. I want to hear every bit of it.", weight: 2.0, topic: Topic.wellbeing),
      DialogueLine("You always undersell the good things. Tell me properly, mijo.", weight: 2.0, topic: Topic.wellbeing),
      // wellbeing receiving
      DialogueLine("I'm relieved to hear that. You had me so worried, mijo.", weight: 1.5, topic: Topic.wellbeing),
      DialogueLine("Good. That's all I ever want — to know you're okay.", weight: 1.5, topic: Topic.wellbeing),
      DialogueLine("You don't know how much I needed to hear that. Please take care of yourself.", weight: 1.3, topic: Topic.wellbeing),

      // AFFECTION ──────────────────────────────────────────────────────────────
      DialogueLine("Mijo... don't stop there. Say more.", weight: 3.0, topic: Topic.affection),
      DialogueLine("You can't just say something like that and leave it there. Go on.", weight: 3.0, topic: Topic.affection),
      DialogueLine("Keep talking. I like where this is going.", weight: 2.8, topic: Topic.affection),
      DialogueLine("Okay, I need to hear all of it. What made you say that?", weight: 2.5, topic: Topic.affection),
      DialogueLine("You made your mother's heart race. Keep going.", weight: 2.5, topic: Topic.affection),
      DialogueLine("I don't hear that enough from you. Say it again?", weight: 2.5, topic: Topic.affection),
      DialogueLine("Ay mijo. I wasn't ready for that. Tell me more.", weight: 2.2, topic: Topic.affection),
      DialogueLine("Where is all this coming from? Not that I mind. Keep going.", weight: 2.2, topic: Topic.affection),
      DialogueLine("You never say things like that out of nowhere. What's on your heart?", weight: 2.0, topic: Topic.affection),
      // affection receiving
      DialogueLine("Mijo... you don't have to say that. But it means the world that you did.", weight: 1.8, topic: Topic.affection),
      DialogueLine("I needed that more than you know. I love you so much.", weight: 1.8, topic: Topic.affection),

      // SUSPICION ──────────────────────────────────────────────────────────────
      // Two sub-cases share this topic:
      //   A) Player is checking in on MAMA — she receives concern about herself.
      //      These lines should feel warm/deflecting/touched.
      //   B) Player is hinting at something worrying about themselves.
      //      These lines have mama lean in and push the player to open up.
      // Both are in the warm pool so both compete; whichever fits the moment
      // will feel natural. A) lines slightly outweigh B) because the most
      // common use of this chip is the player asking about mama.

      // A) Mama receiving the player's concern about her
      DialogueLine("Ay mijo, you always could tell. I'm fine. Don't worry about me.", weight: 3.0, topic: Topic.suspicion),
      DialogueLine("Oh. You noticed. I was hoping you wouldn't say anything.", weight: 3.0, topic: Topic.suspicion),
      DialogueLine("What? I'm fine. Why would you say that?", weight: 2.8, topic: Topic.suspicion),
      DialogueLine("Am I that obvious? I just... I have a lot on my mind right now.", weight: 2.8, topic: Topic.suspicion),
      DialogueLine("Nothing gets past you. I'm okay, mijo. Just a little tired.", weight: 2.8, topic: Topic.suspicion),
      DialogueLine("I didn't want to worry you. But yeah. Things have been heavy.", weight: 2.5, topic: Topic.suspicion),
      DialogueLine("You're checking up on your mama? That means more than you know.", weight: 2.5, topic: Topic.suspicion),
      DialogueLine("I'm fine, I'm fine. Stop worrying about me and worry about yourself.", weight: 2.5, topic: Topic.suspicion),
      DialogueLine("See? You DO care. I was starting to wonder, mijo.", weight: 2.2, topic: Topic.suspicion),
      DialogueLine("You sound like me. Checking up on people like that.", weight: 2.2, topic: Topic.suspicion),
      DialogueLine("Mijo... I appreciate you asking. I really do. I'm okay though.", weight: 2.2, topic: Topic.suspicion),
      DialogueLine("Yeah. Something's been off. I wasn't going to say anything.", weight: 2.0, topic: Topic.suspicion),
      DialogueLine("You noticed. I'm okay, I just... I'll tell you when I figure it out myself.", weight: 2.0, topic: Topic.suspicion),

      // B) Player is hinting at something about themselves — mama pushes back
      DialogueLine("You're hinting at something. I can feel it. Just say it.", weight: 1.8, topic: Topic.suspicion),
      DialogueLine("What aren't you telling me, mijo? Just say it straight.", weight: 1.8, topic: Topic.suspicion),
      DialogueLine("I know you. Something's on your mind. Tell me.", weight: 1.8, topic: Topic.suspicion),
      DialogueLine("You're dancing around something. Stop. Tell me what it is.", weight: 1.5, topic: Topic.suspicion),
      DialogueLine("I won't be upset. But you have to tell me what's going on.", weight: 1.5, topic: Topic.suspicion),
      DialogueLine("Something isn't right. I've felt it. Tell me I'm wrong.", weight: 1.5, topic: Topic.suspicion),
      DialogueLine("Whatever it is, I'd rather hear it from you than find out another way.", weight: 1.5, topic: Topic.suspicion),
    ],
    ReplyTone.honest: [
      DialogueLine("Ok, glad you're alright. Eat something today.", weight: 2.0, topic: Topic.health),
      DialogueLine('Good, mijo. Just make sure you rest.', weight: 2.0, topic: Topic.health),
      DialogueLine('Ok, good. Just take care of yourself.', weight: 1.8, topic: Topic.health),
      DialogueLine("I appreciate you being straight with me.", weight: 1.5),
      DialogueLine("You know I can always tell when you're lying. So thank you.", weight: 1.5),
      DialogueLine("That's all I wanted. The truth. Thank you.", weight: 1.5),
      DialogueLine("Well, I'm glad you told me. I was worried.", weight: 1.5, topic: Topic.suspicion),
      DialogueLine('Ok. I trust you. Just be careful.', weight: 1.5),
      DialogueLine('Honesty is all I ever ask for, mijo.', weight: 1.0),
      DialogueLine("Alright. If that's what's going on, I understand.", weight: 1.0),
      DialogueLine('I appreciate you telling me the truth. It makes me feel better.', weight: 1.5),
      DialogueLine("That's my boy. Always honest.", weight: 1.5),
      DialogueLine("You learned that from me. I don't like lies either.", weight: 1.0),
      DialogueLine("Ok, I believe you. Just tell me if something's wrong, okay?", weight: 1.5),
      DialogueLine('Good. Now I can sleep tonight.', weight: 1.0),
      DialogueLine("That's all I needed to hear. Thank you, mijo.", weight: 1.0),
      DialogueLine("I'm glad you told me. I was imagining all sorts of things.", weight: 1.0),
      DialogueLine("Honestly, I'm just glad you're okay.", weight: 1.5),
      DialogueLine('Thank you for not hiding things from me.', weight: 1.5),
      DialogueLine('I knew I could count on you to tell me the truth.', weight: 1.0),
      DialogueLine("I appreciate you not sugarcoating it, mijo.", weight: 1.0),
      DialogueLine("That's all I ever wanted — the truth.", weight: 1.0),
      DialogueLine('Thank you for trusting me with that.', weight: 1.0),
      DialogueLine("I'd rather hear something hard than a lie.", weight: 1.0),
      DialogueLine('You just gave me some peace of mind.', weight: 1.0),
      DialogueLine('I respect you more for being straight with me.', weight: 1.0),
      DialogueLine('That took guts to say. I noticed.', weight: 1.0),
      DialogueLine('Now I actually know what\'s going on. Thank you.', weight: 1.0),
      DialogueLine("See? That wasn't so hard, was it?", weight: 1.0),
      DialogueLine('I can breathe easier now, mijo.', weight: 1.0),
      DialogueLine("That's the son I raised. Honest.", weight: 1.0),
      DialogueLine("I'm not upset. I'm just glad you told me.", weight: 1.0),
      DialogueLine("You could've lied. You didn't. That means something.", weight: 1.5),
      DialogueLine("I'll always prefer the truth, even the ugly parts.", weight: 1.0),
      DialogueLine('Ok. Now we can actually talk about it.', weight: 1.0),
      DialogueLine("I knew you'd tell me eventually.", weight: 1.0),
      DialogueLine('That\'s more than I expected from you today. Thank you.', weight: 1.0),
      DialogueLine('I trust you a little more now, mijo.', weight: 1.0),
      DialogueLine('Honesty like that, I never take for granted.', weight: 1.0),
      DialogueLine("Whatever it is, we'll figure it out together.", weight: 1.5),
      DialogueLine("I'm proud of you for saying that out loud.", weight: 1.0),
      DialogueLine("It means a lot that you didn't hide it from me.", weight: 1.0),
      DialogueLine('Ok, mijo. I hear you. Loud and clear.', weight: 1.0),
      DialogueLine("That's exactly the kind of talk we need more of.", weight: 1.0),
      DialogueLine("I know that wasn't easy to say.", weight: 1.0),
      DialogueLine("You're growing up, mijo. I see it.", weight: 1.0),
      DialogueLine("Thank you for not making me guess.", weight: 1.0),
      DialogueLine("That's the truth I needed today.", weight: 1.0),
      DialogueLine("I'll take honesty over comfort any day.", weight: 1.0),
      DialogueLine("Now I can actually help you, since I know.", weight: 1.0),
      // Wellbeing-topic answers — "how are you"-shaped questions classify
      // honest (see _looksLikeQuestion's fallback in _classifyTone), so a
      // direct question deserves a direct answer instead of a generic
      // acknowledgment. Stage 2 turns the check-in toward worry, handing off
      // naturally into the suspicion/concern thread below.
      DialogueLine(
        "I'm doing well, mijo. Just been thinking about you a lot. Tell me what's new with you?",
        weight: 2.0,
        topic: Topic.wellbeing,
        intent: Intent.question,
      ),
      DialogueLine(
        "I'm alright, mijo. Keeping busy. How about you, really?",
        weight: 1.6,
        topic: Topic.wellbeing,
        intent: Intent.question,
      ),
      DialogueLine(
        "I'm good, mijo. Better now that I'm hearing from you. What's going on with you?",
        weight: 1.5,
        topic: Topic.wellbeing,
        intent: Intent.question,
      ),
      DialogueLine(
        "I'm alright, mijo. Just worried about you. You've been distant lately.",
        weight: 1.6,
        topic: Topic.wellbeing,
        intent: Intent.question,
        progressionMin: 2,
      ),
      DialogueLine(
        "I'm fine, mijo, don't worry about me. I just wish you'd tell me more.",
        weight: 1.3,
        topic: Topic.wellbeing,
        intent: Intent.question,
        progressionMin: 2,
      ),
      // Suspicion/concern-topic answers — mama naming and then unpacking a
      // specific worry over consecutive turns, instead of a flat vague/cold
      // deflection every time.
      DialogueLine(
        "I don't know, mijo. I just get this feeling something's wrong. You sound different. Distant.",
        weight: 1.8,
        topic: Topic.suspicion,
        intent: Intent.question,
      ),
      DialogueLine(
        "I can't explain it. A mother just knows. Something's off with you lately.",
        weight: 1.4,
        topic: Topic.suspicion,
        intent: Intent.question,
      ),
      DialogueLine(
        "Your messages are shorter. You don't tell me things anymore. Is everything okay with work?",
        weight: 1.6,
        topic: Topic.suspicion,
        intent: Intent.question,
        progressionMin: 2,
      ),
      DialogueLine(
        "You used to tell me everything. Now I have to guess. What changed, mijo?",
        weight: 1.4,
        topic: Topic.suspicion,
        intent: Intent.question,
        progressionMin: 2,
      ),
      DialogueLine("Wait— where did that come from? You were joking around a second ago.", weight: 1.2, acknowledgesToneShift: true),
      DialogueLine("Okay, that's a quick change of mood, mijo. Everything alright?", weight: 1.2, acknowledgesToneShift: true),
      // ── Topic-matched honest reactions ───────────────────────────────────────

      // MONEY
      DialogueLine("Money — okay. What's the situation? Break it down for me.", weight: 3.0, topic: Topic.money),
      DialogueLine("How much are we talking? Give me the real number.", weight: 2.8, topic: Topic.money),
      DialogueLine("You brought up money. I'm not going to pretend I didn't notice. Tell me.", weight: 2.8, topic: Topic.money),
      DialogueLine("Okay, the money thing — I need to understand what's actually happening.", weight: 2.5, topic: Topic.money),
      DialogueLine("Don't sugarcoat it. What's the money situation, mijo?", weight: 2.5, topic: Topic.money),
      DialogueLine("Is it bad? How bad? I can handle the truth.", weight: 2.2, topic: Topic.money),
      DialogueLine("You said money. That means something. Talk to me.", weight: 2.2, topic: Topic.money),
      // money receiving
      DialogueLine("Okay. Money problems are stress. Just don't do anything drastic, mijo.", weight: 1.8, topic: Topic.money),
      DialogueLine("I know money's been tight. Just be careful how you deal with it.", weight: 1.5, topic: Topic.money),

      // HEALTH
      DialogueLine("Your health — what's actually going on? Tell me straight.", weight: 3.0, topic: Topic.health),
      DialogueLine("Wait, something with your health? Tell me exactly what's happening.", weight: 3.0, topic: Topic.health),
      DialogueLine("Don't tell me you're okay if you're not. What's going on?", weight: 2.8, topic: Topic.health),
      DialogueLine("How long has this been going on? Tell me the real version.", weight: 2.5, topic: Topic.health),
      DialogueLine("I need the honest answer — how are you really doing?", weight: 2.5, topic: Topic.health),
      DialogueLine("Okay. Health stuff. Tell me everything. I'm not going to panic.", weight: 2.2, topic: Topic.health),
      // health receiving
      DialogueLine("Your health is not something to joke about. Please take it seriously.", weight: 1.8, topic: Topic.health),
      DialogueLine("Ok, glad you're alright. Eat something today.", weight: 1.5, topic: Topic.health),

      // PLANS
      DialogueLine("Plans — what kind? Give me the details, mijo.", weight: 3.0, topic: Topic.plans),
      DialogueLine("You've got something going on. I can tell. What is it?", weight: 2.8, topic: Topic.plans),
      DialogueLine("Okay, what are we talking here? What are the actual plans?", weight: 2.5, topic: Topic.plans),
      DialogueLine("I like that you're being upfront about it. So keep going — what's the plan?", weight: 2.5, topic: Topic.plans),
      DialogueLine("You mentioned plans. Don't stop at that — tell me what you're thinking.", weight: 2.2, topic: Topic.plans),
      // plans receiving
      DialogueLine("Look at you, thinking ahead. Good. Some structure is good for you.", weight: 1.8, topic: Topic.plans),
      DialogueLine("A new job? Since when? You didn't say anything about looking.", weight: 2.0, topic: Topic.plans),
      DialogueLine("As long as it's legit, mijo, that's all I'm asking.", weight: 2.0, topic: Topic.plans),
      DialogueLine("New job, huh? I hope it treats you better than the last one.", weight: 1.8, topic: Topic.plans),
      DialogueLine("Well, don't leave your mother in suspense. What is it exactly?", weight: 1.8, topic: Topic.plans),
      DialogueLine("Still figuring it out is fine, mijo, just don't disappear on me while you do.", weight: 1.6, topic: Topic.plans),

      // FAMILY
      DialogueLine("Family — what happened? Who? Tell me everything.", weight: 3.0, topic: Topic.family),
      DialogueLine("Okay, I need to know. What's going on with the family?", weight: 2.8, topic: Topic.family),
      DialogueLine("You said family and I'm already worried. Tell me what happened.", weight: 2.8, topic: Topic.family),
      DialogueLine("Which side? What happened? Give me the full picture, mijo.", weight: 2.5, topic: Topic.family),
      DialogueLine("Don't leave me guessing about family stuff. Talk.", weight: 2.5, topic: Topic.family),
      DialogueLine("Okay. Family drama. Tell me from the start.", weight: 2.2, topic: Topic.family),
      // family receiving
      DialogueLine("Family is everything, mijo. Don't ever lose sight of that.", weight: 1.8, topic: Topic.family),

      // WELLBEING
      DialogueLine("Oh yeah? Something went right? Okay, tell me. What happened?", weight: 3.0, topic: Topic.wellbeing),
      DialogueLine("Sounds like good news. I'll take it. Tell me more.", weight: 2.8, topic: Topic.wellbeing),
      DialogueLine("Something went right — okay. What exactly? Don't undersell it.", weight: 2.5, topic: Topic.wellbeing),
      DialogueLine("That's progress. Tell me what it was.", weight: 2.5, topic: Topic.wellbeing),
      DialogueLine("You're being modest. That means it's actually good. Tell me.", weight: 2.2, topic: Topic.wellbeing),

      // SUSPICION
      // A) Mama receiving player's concern about her — honest, a little guarded
      DialogueLine("What? I'm okay. Why, does something seem off?", weight: 3.0, topic: Topic.suspicion),
      DialogueLine("I'm fine, mijo. You're imagining things.", weight: 3.0, topic: Topic.suspicion),
      DialogueLine("Okay fine. I've been a little stressed. But I'm handling it.", weight: 2.8, topic: Topic.suspicion),
      DialogueLine("You noticed. I didn't want to bother you with it.", weight: 2.8, topic: Topic.suspicion),
      DialogueLine("I'm alright. I just have some things on my mind. It'll pass.", weight: 2.5, topic: Topic.suspicion),
      DialogueLine("Nothing's wrong. I'm just tired. Stop reading into things, mijo.", weight: 2.5, topic: Topic.suspicion),
      DialogueLine("Yeah. There's been a lot. But I don't want to put that on you.", weight: 2.2, topic: Topic.suspicion),
      DialogueLine("You're asking the right questions. That's new. I'm okay though.", weight: 2.2, topic: Topic.suspicion),
      // B) Player is hiding something — mama pushes
      DialogueLine("You're not being straight with me. What are you not saying?", weight: 1.8, topic: Topic.suspicion),
      DialogueLine("I can tell something's wrong. Just say it, mijo.", weight: 1.8, topic: Topic.suspicion),
      DialogueLine("What's really going on? Because this isn't the whole story.", weight: 1.5, topic: Topic.suspicion),
      DialogueLine("You're tiptoeing. That tells me everything. What happened?", weight: 1.5, topic: Topic.suspicion),
      DialogueLine("I'd rather know now than find out later. So tell me.", weight: 1.5, topic: Topic.suspicion),
      // receiving
      DialogueLine("Whatever's got you worried, I hope it passes. You can tell me about it.", weight: 1.3, topic: Topic.suspicion),

      // AFFECTION
      DialogueLine("You don't say things like that often. What brought this on?", weight: 3.0, topic: Topic.affection),
      DialogueLine("I'm not complaining — but where did that come from? Tell me.", weight: 2.8, topic: Topic.affection),
      DialogueLine("That was unexpected. In a good way. Keep going.", weight: 2.5, topic: Topic.affection),
      DialogueLine("Okay. Now I really want to know what you're thinking. Say more.", weight: 2.2, topic: Topic.affection),
    ],
    ReplyTone.vague: [
      DialogueLine('...alright. Call me when you can.', weight: 2.0),
      DialogueLine("Ok, mijo... just don't forget about me.", weight: 2.0),
      DialogueLine("Ok, mijo. Just don't be a stranger.", weight: 1.8),
      DialogueLine('Mm. I see. Well, you know where to find me.', weight: 1.5),
      DialogueLine("You're being cryptic today. That's fine. I'll wait.", weight: 1.5),
      DialogueLine("Alright. If that's how you want to be.", weight: 1.5),
      DialogueLine("You sound... far away. Both literally and not.", weight: 1.0, topic: Topic.suspicion),
      DialogueLine("I don't understand, but okay. Just know I love you.", weight: 1.5),
      DialogueLine("You're not telling me everything. But I won't push.", weight: 1.0, topic: Topic.suspicion),
      DialogueLine("I'll be here when you want to talk more. You know that.", weight: 1.5),
      DialogueLine('...Mijo? You still there?', weight: 1.5),
      DialogueLine("You're worrying me with this. But okay.", weight: 1.5, topic: Topic.suspicion),
      DialogueLine("Sometimes I wonder what's going on in that head of yours.", weight: 1.0),
      DialogueLine("You know I can tell when something's wrong.", weight: 1.5, topic: Topic.suspicion),
      DialogueLine("...Alright. I won't ask again.", weight: 1.5),
      DialogueLine("You've got that tone. I know that tone. You're hiding something.", weight: 1.0, topic: Topic.suspicion),
      DialogueLine("Ok. I'll stop asking. But I'm worried. You know that.", weight: 1.5, topic: Topic.suspicion),
      DialogueLine("You're not yourself today. I hope you're okay.", weight: 1.5, topic: Topic.wellbeing),
      DialogueLine("I'll wait until you're ready. I've got patience.", weight: 1.0),
      DialogueLine("You know I'm always here. Even when you're being vague.", weight: 1.0),
      DialogueLine('Ok, mijo. Whatever that means.', weight: 1.0),
      DialogueLine("You're speaking in riddles again.", weight: 1.0),
      DialogueLine("Alright. I'll just wait and see, I guess.", weight: 1.0),
      DialogueLine('That tells me nothing, but ok.', weight: 1.0, acknowledgesDodge: true),
      DialogueLine('Mmhmm. Sure, mijo.', weight: 1.0),
      DialogueLine('You and your mystery answers.', weight: 1.0),
      DialogueLine("Well, that cleared up nothing.", weight: 1.0, acknowledgesDodge: true),
      DialogueLine("Ok... I think? I don't really know.", weight: 1.0),
      DialogueLine('You get that from your father, being vague like that.', weight: 1.0),
      DialogueLine('Fine. Keep your secrets for now.', weight: 1.0),
      DialogueLine("I'll pretend that answered my question.", weight: 1.0, acknowledgesDodge: true),
      DialogueLine('Alright, mijo. Whatever you say.', weight: 1.0),
      DialogueLine("That's about as clear as mud.", weight: 1.0),
      DialogueLine("Ok, I won't push. This time.", weight: 1.0),
      DialogueLine("You're being very you right now.", weight: 1.0),
      DialogueLine("I guess I'll find out eventually.", weight: 1.0),
      DialogueLine('Sure, sure. Whatever you say, mijo.', weight: 1.0),
      DialogueLine("I'll just nod along, I suppose.", weight: 1.0),
      DialogueLine("That's a whole lot of nothing, mijo.", weight: 1.0, acknowledgesDodge: true),
      DialogueLine('Ok. I\'ll let it go. For now.', weight: 1.0),
      DialogueLine('You always do this when something\'s up.', weight: 1.0),
      DialogueLine('Fine, be mysterious. I still love you.', weight: 1.0),
      DialogueLine("I don't know what that means, but ok.", weight: 1.0),
      DialogueLine("Alright, mijo. I trust you know what you're doing.", weight: 1.0),
      DialogueLine("You're dodging, but ok.", weight: 1.0, acknowledgesDodge: true),
      DialogueLine("I'll take that as a maybe.", weight: 1.0),
      DialogueLine("That's your vague voice. I know it well.", weight: 1.0),
      DialogueLine("Ok, mijo... if you say so.", weight: 1.0),
      DialogueLine("Well, that was unclear. But ok.", weight: 1.0),
      DialogueLine("I'll just wait for the real answer later.", weight: 1.0),
      DialogueLine("You just went from one extreme to the other, mijo. Which is it?", weight: 1.0, acknowledgesToneShift: true),
      // Topic-matched vague reactions — she notices the subject even if the answer was dodgy.
      DialogueLine("So there IS something going on with money. I knew it.", weight: 2.0, topic: Topic.money),
      DialogueLine("You brought up the rent and then went quiet. That worries me.", weight: 1.8, topic: Topic.money),
      DialogueLine("So something's going on with your health. Don't brush that off.", weight: 2.0, topic: Topic.health),
      DialogueLine("You mentioned family and then shut down. That's not nothing, mijo.", weight: 1.8, topic: Topic.family),
      DialogueLine("So something's wrong. I can feel it even through the phone.", weight: 2.0, topic: Topic.suspicion),
    ],
    ReplyTone.cold: [
      DialogueLine('Ok.', weight: 2.5),
      DialogueLine('...Alright then.', weight: 2.0),
      DialogueLine('...Ok.', weight: 2.0),
      DialogueLine('Fine. Be that way.', weight: 1.5),
      DialogueLine("I see. That's how it is now.", weight: 1.5),
      DialogueLine("You don't have to be like that.", weight: 1.5),
      DialogueLine('You\'ll regret talking to me like that someday.', weight: 1.0),
      DialogueLine("I'm not going to argue with you.", weight: 1.5),
      DialogueLine('...Well. That hurts.', weight: 1.5),
      DialogueLine("I don't deserve that from you.", weight: 1.5),
      DialogueLine("You know I love you. But I don't like you right now.", weight: 1.0),
      DialogueLine("Fine. I'll give you space.", weight: 1.5),
      DialogueLine("You're being cruel. Why?", weight: 1.0),
      DialogueLine('I thought we were closer than this.', weight: 1.0),
      DialogueLine("You're pushing me away again.", weight: 1.5),
      DialogueLine("Ok. I get it. You don't want to talk.", weight: 1.5, acknowledgesDodge: true),
      DialogueLine('You used to be so sweet. What happened?', weight: 1.0),
      DialogueLine("This isn't you. I know it's not.", weight: 1.0),
      DialogueLine("I'll pray for you. You need it.", weight: 1.0),
      DialogueLine("...I'll wait. Until you're ready to be nice again.", weight: 1.5),
      DialogueLine("Fine. Don't tell me anything, then.", weight: 1.0, acknowledgesDodge: true),
      DialogueLine('Ok. Noted.', weight: 1.0),
      DialogueLine('Wow. Ok.', weight: 1.0),
      DialogueLine('Alright. Whatever you want.', weight: 1.0),
      DialogueLine("I won't bother you again.", weight: 1.0),
      DialogueLine('Understood.', weight: 1.0),
      DialogueLine("That's fine. I'm used to it.", weight: 1.0),
      DialogueLine("Ok, mijo. If that's how it's going to be.", weight: 1.0),
      DialogueLine("Noted. I'll remember that.", weight: 1.0),
      DialogueLine('Sure. Fine by me.', weight: 1.0),
      DialogueLine('I get it.', weight: 1.0),
      DialogueLine('Ok, then.', weight: 1.0),
      DialogueLine('Alright.', weight: 1.0),
      DialogueLine('I hear you.', weight: 1.0),
      DialogueLine("That's your choice.", weight: 1.0),
      DialogueLine("Fine. I'll stop asking.", weight: 1.0, acknowledgesDodge: true),
      DialogueLine("Ok. I won't push.", weight: 1.0, acknowledgesDodge: true),
      DialogueLine('Understood, mijo.', weight: 1.0),
      DialogueLine('Well. Ok then.', weight: 1.0),
      DialogueLine("I won't say anything else.", weight: 1.0),
      DialogueLine('Fine. Good to know.', weight: 1.0),
      DialogueLine("Ok. I'll leave you be.", weight: 1.0),
      DialogueLine('Alright, mijo. Have it your way.', weight: 1.0),
      DialogueLine('I see how it is.', weight: 1.0),
      DialogueLine("That's clear enough.", weight: 1.0),
      DialogueLine("Ok. I'll back off.", weight: 1.0),
      DialogueLine('Fine. I hear you loud and clear.', weight: 1.0),
      DialogueLine("Understood. I'll stop.", weight: 1.0),
      DialogueLine('Ok, mijo. Message received.', weight: 1.0),
      DialogueLine("Alright. I won't ask twice.", weight: 1.0),
      DialogueLine('Whoa. Where did that come from? You were fine a second ago.', weight: 1.2, acknowledgesToneShift: true),
      DialogueLine('That was a sudden switch, mijo. What happened?', weight: 1.2, acknowledgesToneShift: true),
      // Topic-matched cold reactions — she reacts to the subject of what was said.
      DialogueLine("So the money situation is that bad, huh. I don't like this, mijo.", weight: 2.0, topic: Topic.money),
      DialogueLine("You're shutting me out again. And now you bring up money?", weight: 1.8, topic: Topic.money),
      DialogueLine("Health problems and you're talking to me like this? Mijo.", weight: 2.0, topic: Topic.health),
      DialogueLine("You can be cold to me, fine. But don't disappear on the family.", weight: 2.0, topic: Topic.family),
      DialogueLine("You're pushing me away right when I'm worried about you. That hurts.", weight: 2.0, topic: Topic.suspicion),
    ],
    ReplyTone.excuse: [
      DialogueLine('If you say so, mijo.', weight: 2.5),
      DialogueLine("Mm. If that's what happened.", weight: 2.0),
      DialogueLine('Alright, mijo. If you say so.', weight: 2.0),
      DialogueLine("You know you don't have to lie to me, right?", weight: 1.5),
      DialogueLine('I was born at night, mijo. Not last night.', weight: 1.5),
      DialogueLine("You think I can't tell when you're making excuses?", weight: 1.5),
      DialogueLine("I've heard a lot of excuses in my life. That's one of them.", weight: 1.0),
      DialogueLine("If you don't want to talk, just say so.", weight: 1.5),
      DialogueLine("I've been on this earth longer than you. I know a lie when I hear one.", weight: 1.0),
      DialogueLine("Alright. I'll pretend I believe you.", weight: 1.5),
      DialogueLine("You're not that good of a liar, mijo.", weight: 1.5),
      DialogueLine("I don't need the story. I just need you to be honest with me.", weight: 1.5),
      DialogueLine("You know what? Fine. I'll accept that.", weight: 1.0),
      DialogueLine('I know you too well for that to work on me.', weight: 1.5),
      DialogueLine("You got caught, didn't you?", weight: 1.0),
      DialogueLine("I'm not mad. Just disappointed.", weight: 1.5),
      DialogueLine("You don't have to hide. I'll always love you.", weight: 1.0),
      DialogueLine('Mmhmm. Sure. That\'s what happened.', weight: 1.5),
      DialogueLine("You're digging yourself a hole. Stop while you can.", weight: 1.0),
      DialogueLine('I was born at night, but not LAST night, mijo.', weight: 1.5),
      DialogueLine('Mmhmm. Sure, mijo.', weight: 1.0),
      DialogueLine('If you say so.', weight: 1.0),
      DialogueLine("That's quite the story.", weight: 1.0),
      DialogueLine('Sure. Whatever you say happened.', weight: 1.0),
      DialogueLine("I've heard better excuses, honestly.", weight: 1.0),
      DialogueLine("Ok, I'll let that one slide.", weight: 1.0),
      DialogueLine('Alright. I\'ll believe you. For now.', weight: 1.0),
      DialogueLine("You always have a story ready, don't you?", weight: 1.0),
      DialogueLine('Mmhmm. Ok, mijo.', weight: 1.0),
      DialogueLine("That's convenient timing.", weight: 1.0),
      DialogueLine('Sure, sure. Whatever you say.', weight: 1.0),
      DialogueLine('I raised you, I know your excuses.', weight: 1.0),
      DialogueLine('Ok. Noted, mijo.', weight: 1.0),
      DialogueLine("That one was creative, I'll give you that.", weight: 1.0),
      DialogueLine("Alright, if that's the story we're going with.", weight: 1.0),
      DialogueLine("I've heard that one before, mijo.", weight: 1.0),
      DialogueLine("Sure. I'll pretend I believe that.", weight: 1.0),
      DialogueLine('Mmhmm. Ok then.', weight: 1.0),
      DialogueLine("You're getting better at those excuses.", weight: 1.0),
      DialogueLine('Alright, mijo. If you insist.', weight: 1.0),
      DialogueLine("That's not the first time I've heard that.", weight: 1.0),
      DialogueLine('Ok. Sure. Whatever helps you sleep.', weight: 1.0),
      DialogueLine('I know a story when I hear one, mijo.', weight: 1.0),
      DialogueLine("Fine. We'll go with your version.", weight: 1.0),
      DialogueLine('Mmhmm. Interesting excuse.', weight: 1.0),
      DialogueLine("Alright, I'll let it go this time.", weight: 1.0),
      DialogueLine("Sure, mijo. Whatever you need to tell yourself.", weight: 1.0),
      DialogueLine("I wasn't born yesterday, you know.", weight: 1.0),
      DialogueLine('Ok. Noted for next time.', weight: 1.0),
      DialogueLine("That's your story and you're sticking to it, huh?", weight: 1.0),
      DialogueLine('Mmhmm. That\'s a different story than a minute ago, mijo.', weight: 1.2, acknowledgesToneShift: true),
      DialogueLine("Wait, that's not what you were just saying.", weight: 1.2, acknowledgesToneShift: true),
    ],
  },
  'partner': {
    ReplyTone.warm: [
      DialogueLine("I love you too. Don't be a stranger."),
      DialogueLine('I needed to hear that. I love you.'),
      DialogueLine('I love you too. Come home soon, ok?'),
      DialogueLine('Whoa, where did that come from? Not complaining though. 😏', acknowledgesToneShift: true),
    ],
    ReplyTone.honest: [
      DialogueLine('Ok. Just wish I saw you more.'),
      DialogueLine('Alright. I miss you, you know.'),
      DialogueLine('Ok. I just miss having you around.'),
      DialogueLine('Okay, mood swing much? What happened?', acknowledgesToneShift: true),
    ],
    ReplyTone.vague: [
      DialogueLine('Fine. Whatever you say.'),
      DialogueLine('Sure. Whatever.'),
      DialogueLine('Ok, sure.'),
      DialogueLine("That's a weird 180 from a second ago.", acknowledgesToneShift: true),
    ],
    ReplyTone.cold: [
      DialogueLine('Wow. Ok then.'),
      DialogueLine('Cool. Great talk.'),
      DialogueLine('Fine. Whatever.'),
      DialogueLine("Whoa, where'd that come from? You were fine a sec ago.", acknowledgesToneShift: true),
    ],
    ReplyTone.excuse: [
      DialogueLine('...if you say so.'),
      DialogueLine('Right. Sure it was.'),
      DialogueLine('Mm. Ok.'),
      DialogueLine('Wait, that\'s a different story than a minute ago.', acknowledgesToneShift: true),
    ],
  },
  'friend': {
    ReplyTone.warm: [
      DialogueLine('love you too man, for real. hit me up soon'),
      DialogueLine('aw for real? love you too bro'),
      DialogueLine('love you too fr, don\'t be a stranger'),
      DialogueLine('whoa okay soft side coming out, i see you lol', acknowledgesToneShift: true),
    ],
    ReplyTone.honest: [
      DialogueLine('aight, good to hear. stay safe out there'),
      DialogueLine('bet, glad you good'),
      DialogueLine('aight bet, glad to hear it'),
      DialogueLine("damn ok mood switch, what's good?", acknowledgesToneShift: true),
    ],
    ReplyTone.vague: [
      DialogueLine('ok... whatever you say'),
      DialogueLine('aight if you say so'),
      DialogueLine('aight, whatever you say'),
      DialogueLine('bro that\'s a whole 180 from a sec ago', acknowledgesToneShift: true),
    ],
    ReplyTone.cold: [
      DialogueLine('damn ok then'),
      DialogueLine('bruh ok'),
      DialogueLine('aight then'),
      DialogueLine("damn where'd that come from, you good?", acknowledgesToneShift: true),
    ],
    ReplyTone.excuse: [
      DialogueLine('sure man, whatever you say lol'),
      DialogueLine('lol ok if you say so'),
      DialogueLine('aight if you say so lol'),
      DialogueLine("lol that's a different story than before", acknowledgesToneShift: true),
    ],
  },
  'brother': {
    ReplyTone.warm: [
      DialogueLine('Love you too, man. Stay safe.'),
      DialogueLine('Good to hear, man. Love you.'),
      DialogueLine("Love you too. Don't be a stranger."),
      DialogueLine("Whoa, didn't expect that. Not complaining.", acknowledgesToneShift: true),
    ],
    ReplyTone.honest: [
      DialogueLine('Alright. Good to hear.'),
      DialogueLine("Cool. Glad you're good."),
      DialogueLine('Good to hear, man.'),
      DialogueLine('Alright, quick change of tune. Everything good?', acknowledgesToneShift: true),
    ],
    ReplyTone.vague: [
      DialogueLine('Whatever, man.'),
      DialogueLine('Sure, man.'),
      DialogueLine('Aight, whatever.'),
      DialogueLine("That's a switch-up from a second ago.", acknowledgesToneShift: true),
    ],
    ReplyTone.cold: [
      DialogueLine('Ok then.'),
      DialogueLine('Alright.'),
      DialogueLine('Aight.'),
      DialogueLine("Whoa, where'd that come from?", acknowledgesToneShift: true),
    ],
    ReplyTone.excuse: [
      DialogueLine('Sure, whatever you say.'),
      DialogueLine('Right, sure.'),
      DialogueLine('Aight, sure.'),
      DialogueLine("That's not what you said a minute ago.", acknowledgesToneShift: true),
    ],
  },
  'oldfriend': {
    ReplyTone.warm: [
      DialogueLine('Love you too. Take it easy out there.'),
      DialogueLine('That means a lot. Take care of yourself.'),
      DialogueLine('Means a lot. Take care out there.'),
      DialogueLine("Didn't expect that from you. Good to see.", acknowledgesToneShift: true),
    ],
    ReplyTone.honest: [
      DialogueLine('Good to hear. Take care of yourself.'),
      DialogueLine('Glad to hear it. Stay safe.'),
      DialogueLine('Good to hear. Take it easy.'),
      DialogueLine("That's a sudden change. Everything alright?", acknowledgesToneShift: true),
    ],
    ReplyTone.vague: [
      DialogueLine('Ok, take care.'),
      DialogueLine('Alright, take it easy.'),
      DialogueLine('Ok, take it easy.'),
      DialogueLine("That's different from what you were saying.", acknowledgesToneShift: true),
    ],
    ReplyTone.cold: [
      DialogueLine('Alright then.'),
      DialogueLine('Ok.'),
      DialogueLine('Alright.'),
      DialogueLine('Whoa, that came out of nowhere.', acknowledgesToneShift: true),
    ],
    ReplyTone.excuse: [
      DialogueLine('If you say so.'),
      DialogueLine("Sure, if that's what it was."),
      DialogueLine('Alright, if you say so.'),
      DialogueLine("That's a different story than a minute ago.", acknowledgesToneShift: true),
    ],
  },
};

const Map<String, RelationshipContent> kRelationshipContent = {
  // ── mama and partner: full conditional variety — mood/memory/recent-tone
  // predicates layered on top of the original always-eligible lines. ──
  'mama': RelationshipContent(
    openers: [
      DialogueLine("I'm making lunch on Sunday. You coming?", weight: 2.0, topic: Topic.family, tone: ReplyTone.warm),
      DialogueLine("I hope that cold is getting better. I've been so worried about you.", weight: 1.5, topic: Topic.health, tone: ReplyTone.warm),
      DialogueLine("Your aunt was asking about you. She misses you too.", weight: 1.5, topic: Topic.family, tone: ReplyTone.honest),
      DialogueLine(
        "Mijo, that meant a lot to me... what you said earlier. I'm still thinking about it.",
        when: _rememberedFirstWarmAndWarm,
        weight: 2.0,
        topic: Topic.affection,
        tone: ReplyTone.warm,
      ),
      DialogueLine(
        "You seem like you're carrying something heavy. You can tell me, you know.",
        when: _twoRecentColdButLowSuspicion,
        weight: 1.5,
        topic: Topic.affection,
        tone: ReplyTone.vague,
      ),
      DialogueLine(
        "You've been so far away lately. Did I do something wrong?",
        when: _rememberedCutOff,
        weight: 1.5,
        topic: Topic.suspicion,
        tone: ReplyTone.cold,
      ),
      DialogueLine(
        "Your brother said you've been distant. I told him he was wrong. Is he wrong, mijo?",
        when: _heardAboutCutOff,
        weight: 1.5,
        topic: Topic.family,
        tone: ReplyTone.vague,
      ),
      DialogueLine(
        "Tono told me something happened. Can you tell me what's going on?",
        when: _heardAboutConfrontation,
        weight: 2.0,
        topic: Topic.family,
        tone: ReplyTone.honest,
      ),
      DialogueLine('Good morning, mijo. Just wanted to say I love you.', weight: 1.5, topic: Topic.affection, tone: ReplyTone.warm),
      DialogueLine('Hi mijo, just checking in on you.', weight: 1.5, topic: Topic.greeting, tone: ReplyTone.warm),
      DialogueLine(
        'I was just thinking about you. How are you doing, my son?',
        weight: 2.0,
        topic: Topic.wellbeing,
        intent: Intent.question,
        tone: ReplyTone.warm,
      ),
      DialogueLine("Are you eating well? You better be eating well.", weight: 1.5, topic: Topic.health, tone: ReplyTone.honest),
      DialogueLine('I had a dream about you last night. You were smiling. Made me so happy.', weight: 1.5, tone: ReplyTone.warm),
      DialogueLine(
        "It's been a week. A WEEK, mijo. You couldn't text me once?",
        when: _daysSinceReply7,
        weight: 1.5,
        topic: Topic.suspicion,
        tone: ReplyTone.cold,
      ),
      DialogueLine('I was making your favorite. The chicken with the peppers. Made me miss you.', weight: 1.5, topic: Topic.family, tone: ReplyTone.warm),
      DialogueLine('You know, sometimes I look at your baby pictures and I cry. Happy tears. Just so you know.', weight: 1.0, tone: ReplyTone.warm),
      DialogueLine(
        "I don't mean to worry you, but I've been feeling off lately. Maybe it's just my age.",
        trustMin: 60,
        weight: 1.5,
        topic: Topic.health,
        tone: ReplyTone.honest,
      ),
      DialogueLine('Can you call me? Not text. Call me. I miss your voice.', weight: 1.5, tone: ReplyTone.vague),
      DialogueLine("You've been on my mind all day. Just wanted you to know.", weight: 2.0, tone: ReplyTone.warm),
      DialogueLine('I made too much food. You should come eat with me. Bring your appetite.', weight: 1.5, topic: Topic.plans, tone: ReplyTone.warm),
      // Time-of-day variety — genuinely gated by CareerController.timeOfDay.
      DialogueLine('Good morning, mijo! I made your favorite pan dulce today.', timesOfDay: {TimeOfDay.morning}, weight: 1.5, topic: Topic.family, tone: ReplyTone.warm),
      DialogueLine("Rise and shine, mijo. Don't forget to eat breakfast.", timesOfDay: {TimeOfDay.morning}, weight: 1.0, topic: Topic.health, tone: ReplyTone.honest),
      DialogueLine("How's your day going so far, mijo?", timesOfDay: {TimeOfDay.afternoon}, weight: 1.0, topic: Topic.wellbeing, intent: Intent.question, tone: ReplyTone.honest),
      DialogueLine('Just took a break from cooking. Thought of you, mijo.', timesOfDay: {TimeOfDay.afternoon}, weight: 1.0, topic: Topic.family, tone: ReplyTone.warm),
      DialogueLine("Dinner's almost ready. Wish you were here to eat with me.", timesOfDay: {TimeOfDay.evening}, weight: 1.5, topic: Topic.plans, tone: ReplyTone.warm),
      DialogueLine('How was your day, mijo? Tell me about it tonight.', timesOfDay: {TimeOfDay.evening}, weight: 1.0, topic: Topic.wellbeing, intent: Intent.question, tone: ReplyTone.honest),
      DialogueLine("Can't sleep. Just thinking about you, mijo.", timesOfDay: {TimeOfDay.night}, weight: 1.0, tone: ReplyTone.warm),
      DialogueLine("It's late. Get some rest, mijo. I love you.", timesOfDay: {TimeOfDay.night}, weight: 1.5, tone: ReplyTone.warm),
      // Weekend variety — genuinely gated by CareerController.isWeekend.
      DialogueLine("It's the weekend! Come by for lunch if you're free.", requireWeekend: true, weight: 1.5, topic: Topic.plans, tone: ReplyTone.warm),
      DialogueLine('No work today, right? Perfect time to visit your mother.', requireWeekend: true, weight: 1.0, topic: Topic.plans, tone: ReplyTone.honest),
      DialogueLine('Weekends are so quiet without you here, mijo.', requireWeekend: true, weight: 1.0, tone: ReplyTone.vague),
      DialogueLine('Your cousins are coming this weekend. You should join us.', requireWeekend: true, weight: 1.0, topic: Topic.family, tone: ReplyTone.warm),
      // General variety — everyday texture of a mother's unprompted texts.
      DialogueLine('I made pozole today. Wish you could smell it from there.', weight: 1.0, topic: Topic.family, tone: ReplyTone.warm),
      DialogueLine("Your tía asked if you're seeing anyone. I told her that's your business.", weight: 1.0, topic: Topic.family, tone: ReplyTone.honest),
      DialogueLine('I found your old baseball glove cleaning the closet. Made me smile.', weight: 1.0, tone: ReplyTone.warm),
      DialogueLine("The neighbor's dog had puppies. You should come see them.", weight: 1.0, topic: Topic.plans, tone: ReplyTone.warm),
      DialogueLine('I planted tomatoes this year. You always loved my tomatoes.', weight: 1.0, tone: ReplyTone.warm),
      DialogueLine('Mass was beautiful today. I said a prayer for you.', weight: 1.0, tone: ReplyTone.warm),
      DialogueLine('I ran into your old teacher at the market. She still remembers you.', weight: 1.0, tone: ReplyTone.honest),
      DialogueLine('Your room is exactly how you left it, mijo. Whenever you want it.', weight: 1.5, topic: Topic.family, tone: ReplyTone.warm),
      DialogueLine("I've been listening to the radio station you used to like.", weight: 1.0, tone: ReplyTone.vague),
      DialogueLine('Found a picture of us at the beach. You were so little.', weight: 1.0, tone: ReplyTone.warm),
      DialogueLine('I keep the porch light on, just in case you decide to visit.', weight: 1.0, topic: Topic.plans, tone: ReplyTone.vague),
      DialogueLine("Your cousin got married last month. Wish you could've been there.", weight: 1.0, topic: Topic.family, tone: ReplyTone.vague),
      DialogueLine("I'm learning to use this phone better, mijo. Slowly but surely.", weight: 1.0, tone: ReplyTone.honest),
      DialogueLine('The church is doing a fundraiser. Thought you\'d want to know.', weight: 1.0, tone: ReplyTone.honest),
      DialogueLine('I saw a car like yours today and my heart skipped a beat.', weight: 1.0, tone: ReplyTone.vague),
      DialogueLine("Made extra tamales. There's a bag with your name on it in the freezer.", weight: 1.0, topic: Topic.family, tone: ReplyTone.warm),
      DialogueLine('Your abuela used to say prayers work faster with names attached. I say yours a lot.', weight: 1.0, topic: Topic.family, tone: ReplyTone.warm),
      DialogueLine("The garden's blooming. You'd love it right now.", weight: 1.0, tone: ReplyTone.warm),
      DialogueLine("I keep your baby shoes on the shelf. Don't ask me why.", weight: 1.0, tone: ReplyTone.warm),
      DialogueLine('Sundays feel long without hearing from you.', weight: 1.0, tone: ReplyTone.vague),
      DialogueLine('I ran into Doña Carmen. She asked about you too.', weight: 1.0, topic: Topic.family, tone: ReplyTone.honest),
      DialogueLine('Bought your favorite candy at the store out of habit.', weight: 1.0, tone: ReplyTone.warm),
      DialogueLine('I still make enough food for two, out of habit.', weight: 1.0, topic: Topic.family, tone: ReplyTone.vague),
      DialogueLine('Your padrino wants to see you sometime. He misses you.', weight: 1.0, topic: Topic.family, tone: ReplyTone.honest),
      DialogueLine('I was going through old photos and found one of you as a baby. So precious.', weight: 1.0, tone: ReplyTone.warm),
      // Proactive callbacks — surface when the player already brought up this topic today.
      DialogueLine(
        "You mentioned your health earlier — I've been thinking about it. Please take care of yourself, mijo.",
        when: _talkedHealthToday,
        weight: 2.5,
        topic: Topic.health,
        tone: ReplyTone.warm,
      ),
      DialogueLine(
        "You said something about the family today. It's been on my mind all afternoon.",
        when: _talkedFamilyToday,
        weight: 2.0,
        topic: Topic.family,
        tone: ReplyTone.honest,
      ),
      DialogueLine(
        "You mentioned your plans earlier. Are you still doing okay with all of that?",
        when: _talkedPlansToday,
        weight: 2.0,
        topic: Topic.plans,
        tone: ReplyTone.honest,
      ),
      DialogueLine(
        "Earlier you said something about how you were feeling. I just want to check in again — you sure you're okay?",
        when: _talkedWellbeingToday,
        weight: 2.5,
        topic: Topic.wellbeing,
        intent: Intent.question,
        tone: ReplyTone.warm,
      ),
      DialogueLine(
        "You brought up money earlier and I've been a little worried since. Is everything alright, mijo?",
        when: _talkedMoneyToday,
        weight: 2.0,
        topic: Topic.money,
        tone: ReplyTone.honest,
      ),
      DialogueLine(
        "You said something earlier that made me think you're stressed. Talk to me, mijo.",
        when: _talkedPlansToday,
        weight: 1.5,
        topic: Topic.plans,
        tone: ReplyTone.warm,
      ),
    ],
    questioning: [
      DialogueLine('Is everything okay, sweetheart? You seem different.', weight: 2.5, topic: Topic.suspicion, tone: ReplyTone.vague),
      DialogueLine("We barely talk anymore. What's going on with you?", weight: 2.0, topic: Topic.suspicion, tone: ReplyTone.vague),
      DialogueLine("You've gone quiet on me lately. That's not like you.", weight: 2.0, topic: Topic.suspicion, tone: ReplyTone.cold),
      DialogueLine(
        "You sounded so happy when we last talked. Now you sound... different.",
        when: _moodSoured,
        weight: 1.5,
        topic: Topic.suspicion,
        tone: ReplyTone.vague,
      ),
      DialogueLine('Mijo. Look at me. What\'s really going on?', weight: 2.0, topic: Topic.suspicion, tone: ReplyTone.honest),
      DialogueLine("I've been worried sick. You're not yourself.", weight: 2.0, topic: Topic.suspicion, tone: ReplyTone.vague),
      DialogueLine("Something's wrong. I can feel it in my gut. I'm always right.", weight: 1.5, topic: Topic.suspicion, tone: ReplyTone.honest),
      DialogueLine('You know you can tell me anything, right? ANYTHING.', weight: 1.5, topic: Topic.suspicion, tone: ReplyTone.warm),
      DialogueLine("I don't believe you're fine. I know you better than that.", weight: 1.5, topic: Topic.suspicion, tone: ReplyTone.cold),
      DialogueLine("Stop pushing me away. I'm your mother. I deserve better than this.", weight: 1.5, topic: Topic.suspicion, tone: ReplyTone.cold),
      DialogueLine("You've changed. And I need to understand why.", weight: 1.5, topic: Topic.suspicion, tone: ReplyTone.honest),
      DialogueLine("I'm not angry. I'm just... worried. That's all I ever am.", weight: 2.0, topic: Topic.suspicion, tone: ReplyTone.warm),
      DialogueLine('You used to tell me everything. What happened to that?', weight: 1.5, topic: Topic.suspicion, tone: ReplyTone.vague),
      DialogueLine("Is it something I did? Because if it is, I'm sorry.", weight: 1.0, topic: Topic.suspicion, tone: ReplyTone.cold),
      DialogueLine("I don't want to lose you. But I feel like I am.", weight: 2.0, topic: Topic.suspicion, tone: ReplyTone.vague),
      DialogueLine('Talk to me, mijo. Please.', weight: 1.5, tone: ReplyTone.vague),
      DialogueLine("Why won't you just tell me what's wrong?", weight: 1.5, topic: Topic.suspicion, tone: ReplyTone.honest),
      DialogueLine("I lay awake wondering what's going on with you.", weight: 1.0, topic: Topic.suspicion, tone: ReplyTone.vague),
      DialogueLine("You're my son. I know when something's off.", weight: 1.0, topic: Topic.suspicion, tone: ReplyTone.honest),
      DialogueLine("Please don't shut me out, mijo.", weight: 1.5, tone: ReplyTone.warm),
      DialogueLine("What am I supposed to think when you go quiet like this?", weight: 1.0, tone: ReplyTone.cold),
      DialogueLine("I've called three times. Why aren't you answering?", weight: 1.0, tone: ReplyTone.cold),
      DialogueLine("Is it something with the law? Please tell me it's not that.", weight: 1.5, topic: Topic.suspicion, tone: ReplyTone.honest),
      DialogueLine("Your silence is louder than anything you could say, mijo.", weight: 1.0, tone: ReplyTone.cold),
      DialogueLine('I raised you better than to shut your mother out.', weight: 1.0, tone: ReplyTone.cold),
      DialogueLine("Every day you don't call, I imagine the worst.", weight: 1.5, tone: ReplyTone.vague),
      DialogueLine("Whatever it is, it can't be worse than not knowing.", weight: 1.0, tone: ReplyTone.honest),
      DialogueLine('I need you to talk to me. Really talk to me.', weight: 1.5, tone: ReplyTone.honest),
      DialogueLine('You sound like a stranger lately, mijo.', weight: 1.0, tone: ReplyTone.vague),
      DialogueLine('I just want my son back. The one who told me things.', weight: 1.5, tone: ReplyTone.warm),
    ],
    distant: [
      DialogueLine('Ok.', weight: 2.5, tone: ReplyTone.cold),
      DialogueLine("It's fine, sweetheart. Take care.", weight: 2.0, tone: ReplyTone.cold),
      DialogueLine("...I don't know what to say to you anymore, mijo.", weight: 2.0, tone: ReplyTone.cold),
      DialogueLine('You made your choice. I have to live with it.', weight: 1.5, tone: ReplyTone.cold),
      DialogueLine("I don't recognize you. You're not my son.", weight: 1.5, tone: ReplyTone.cold),
      DialogueLine("I've prayed. I've cried. And you don't care.", weight: 1.5, tone: ReplyTone.cold),
      DialogueLine("Fine. Be that way. I'm done begging.", weight: 1.5, tone: ReplyTone.cold),
      DialogueLine("You broke my heart. And you don't even seem to notice.", weight: 2.0, tone: ReplyTone.cold),
      DialogueLine("I hope whatever you're doing is worth losing me.", weight: 1.5, tone: ReplyTone.cold),
      DialogueLine("...I'll be here. If you ever come back.", weight: 1.5, tone: ReplyTone.vague),
      DialogueLine("You're making a mistake. And you're going to regret it.", weight: 1.5, tone: ReplyTone.cold),
      DialogueLine("I don't even know who you are anymore. And that kills me.", weight: 2.0, tone: ReplyTone.cold),
      DialogueLine("You're not the boy I raised. That boy was kind. Sweet. You're cold.", weight: 1.5, tone: ReplyTone.cold),
      DialogueLine("I've given you everything. And this is what I get?", weight: 1.5, tone: ReplyTone.cold),
      DialogueLine("...Go. Just go. I can't do this anymore.", weight: 2.0, tone: ReplyTone.cold),
      DialogueLine("I don't even recognize your voice anymore.", weight: 1.5, tone: ReplyTone.cold),
      DialogueLine("You've made your choice clear.", weight: 1.5, tone: ReplyTone.cold),
      DialogueLine('I stopped waiting a while ago.', weight: 1.5, tone: ReplyTone.cold),
      DialogueLine("There's nothing left to say, is there?", weight: 1.0, tone: ReplyTone.cold),
      DialogueLine("I used to know everything about you. Now I know nothing.", weight: 1.5, tone: ReplyTone.cold),
      DialogueLine("You're a stranger to me now.", weight: 1.5, tone: ReplyTone.cold),
      DialogueLine("I don't even bother hoping anymore.", weight: 1.5, tone: ReplyTone.cold),
      DialogueLine("Whatever this is, it's not a mother and son anymore.", weight: 1.5, tone: ReplyTone.cold),
      DialogueLine("I've cried enough tears for you.", weight: 1.0, tone: ReplyTone.cold),
      DialogueLine("Go live your life. Clearly you don't need me in it.", weight: 1.5, tone: ReplyTone.cold),
      DialogueLine('...I don\'t know this version of you.', weight: 1.5, tone: ReplyTone.cold),
      DialogueLine('You buried the boy I raised somewhere along the way.', weight: 1.5, tone: ReplyTone.cold),
      DialogueLine('I stopped setting a plate for you at dinner.', weight: 1.0, tone: ReplyTone.cold),
      DialogueLine('...Maybe this is just how it is now.', weight: 1.0, tone: ReplyTone.vague),
      DialogueLine("I don't have the energy to fight for this anymore.", weight: 1.5, tone: ReplyTone.cold),
    ],
    confrontation: [
      DialogueLine("No answer. Days later your aunt calls crying... What did you DO to her, mijo?", weight: 2.5),
      DialogueLine("I've been calling you for days. Your aunt has been calling. You answer NOW?", weight: 2.0),
      DialogueLine("You think you can just disappear? You think we don't care?", weight: 2.0),
      DialogueLine("I don't even know where you are anymore. That's not okay.", weight: 2.0),
      DialogueLine("You promised me you'd stay in touch. And you broke that promise.", weight: 1.5),
      DialogueLine("I've been worried sick. SICK. And you didn't answer. You don't understand what that does to me.", weight: 2.5),
      DialogueLine('You need to explain yourself. RIGHT NOW.', weight: 2.0),
      DialogueLine('I thought you were dead. Do you understand what that feels like?', weight: 2.0),
      DialogueLine("You're lucky I'm still talking to you.", weight: 1.5),
      DialogueLine("I don't know what to say to you. I don't even know where to start.", weight: 1.5),
      DialogueLine("Do you know what it's like to bury your own child, mijo? Because that's what I've been imagining.", weight: 2.0),
      DialogueLine("Your aunt found out before I did. Do you know how that feels?", weight: 1.5),
      DialogueLine("I've aged ten years worrying about you. Ten years.", weight: 1.5),
      DialogueLine('This ends tonight. You tell me everything, right now.', weight: 2.0),
      DialogueLine("I don't care what it is. I just need to know you're alive.", weight: 2.0),
    ],
    goneQuietLine: [
      DialogueLine('She doesn\'t text anymore. Just silence.', weight: 3.0),
      DialogueLine("...I guess that's it then. You're done with me.", weight: 2.5),
      DialogueLine("I'll always love you. Even if you don't love me back.", weight: 2.5),
      DialogueLine('I miss you. I miss you so much it hurts.', weight: 2.0),
      DialogueLine("I don't know why you're doing this. But I accept it.", weight: 2.0),
      DialogueLine("I'll be here. Always. Even when you're not.", weight: 2.0),
      DialogueLine('You broke me. But I\'ll survive. I always do.', weight: 2.5),
      DialogueLine("I hope you're happy. I really do.", weight: 1.5),
      DialogueLine("I'll love you forever. Even if you don't want me to.", weight: 2.0),
      DialogueLine("...Goodbye, mijo. I'll always remember you the way you were.", weight: 2.0),
      DialogueLine('I check my phone a hundred times a day. Still nothing.', weight: 2.0),
      DialogueLine('Your room stays exactly the same. Waiting.', weight: 1.5),
      DialogueLine('I light a candle every night, just in case.', weight: 1.5),
      DialogueLine('Some mothers give up. I never will, mijo.', weight: 2.0),
      DialogueLine('The silence is the loudest thing in this house.', weight: 1.5),
    ],
    followUp: [
      DialogueLine("Mijo? You still there? Just tell me you're okay.", weight: 2.0, tone: ReplyTone.vague),
      DialogueLine('Hey... did you get my messages?', weight: 1.0, tone: ReplyTone.vague),
      DialogueLine("I know you're busy, but just a word would help, mijo.", weight: 1.0, tone: ReplyTone.honest),
      DialogueLine('You still breathing? Just say yes or no.', weight: 1.0, tone: ReplyTone.cold),
      DialogueLine("I'm not mad. I just need to know you're safe.", weight: 1.5, tone: ReplyTone.warm),
      DialogueLine('Please, mijo. Even just one word.', weight: 1.5, tone: ReplyTone.vague),
      DialogueLine("I'll stop bothering you after this. Just tell me you're okay.", weight: 1.0, tone: ReplyTone.vague),
      DialogueLine("It's been a few days, mijo. I'm starting to worry.", weight: 1.0, tone: ReplyTone.honest),
      DialogueLine("You don't have to explain anything. Just check in.", weight: 1.0, tone: ReplyTone.warm),
      DialogueLine("One text, mijo. That's all I ask.", weight: 1.0, tone: ReplyTone.vague),
      DialogueLine('I made your favorite. Come get it whenever, if you\'re okay.', weight: 1.0, tone: ReplyTone.warm),
      DialogueLine('Just a thumbs up would do, mijo. Anything.', weight: 1.0, tone: ReplyTone.vague),
      DialogueLine('I keep checking my phone. Nothing yet.', weight: 1.0, tone: ReplyTone.vague),
      DialogueLine("Mijo, please. Even a 'busy' would help.", weight: 1.0, tone: ReplyTone.vague),
      DialogueLine("I won't ask questions. Just let me know you're alive.", weight: 1.0, tone: ReplyTone.honest),
      DialogueLine('You know silence scares me more than bad news.', weight: 1.5, tone: ReplyTone.honest),
      DialogueLine("I'm still here, mijo. Whenever you're ready.", weight: 1.0, tone: ReplyTone.warm),
      DialogueLine('Just checking — everything alright?', weight: 1.0, tone: ReplyTone.honest),
      DialogueLine("Don't leave me hanging like this, mijo.", weight: 1.0, tone: ReplyTone.cold),
      DialogueLine('A mother needs to know. Please.', weight: 1.0, tone: ReplyTone.vague),
    ],
    spamReactions: [
      DialogueLine("Mijo, you just said that. Are you testing me?", weight: 2.0, tone: ReplyTone.honest),
      DialogueLine("You already sent that. Are you okay up there?", weight: 2.0, tone: ReplyTone.vague),
      DialogueLine("Did you mean to send that twice? My phone is going crazy.", weight: 1.5, tone: ReplyTone.honest),
      DialogueLine("Again? Mijo, I heard you the first time.", weight: 1.5, tone: ReplyTone.cold),
      DialogueLine("You're repeating yourself, sweetheart. Should I be worried?", weight: 1.5, tone: ReplyTone.vague),
      DialogueLine("That's the same thing you just said. Is something wrong?", weight: 1.5, tone: ReplyTone.honest),
      DialogueLine("Mijo, either your phone is broken or something's on your mind. Which is it?", weight: 1.5, tone: ReplyTone.honest),
      DialogueLine("You keep saying the same thing. I'm listening. You can tell me what's really going on.", weight: 2.0, tone: ReplyTone.warm),
      DialogueLine("Okay, you've said that three times now. Come on, what's really going on?", weight: 1.5, tone: ReplyTone.cold),
      DialogueLine("I think your phone is glitching, mijo. Or is there something you're trying to say?", weight: 1.5, tone: ReplyTone.vague),
      // Escalation lines — only surface at count ≥4, signalling patience is nearly gone.
      DialogueLine("Mijo. I'm going to stop answering this if you keep sending it.", when: _spamLevel4, weight: 2.0, tone: ReplyTone.cold),
      DialogueLine("I love you but I'm not going to keep responding to the same thing over and over.", when: _spamLevel4, weight: 2.0, tone: ReplyTone.cold),
      DialogueLine("This is the last time I'm responding to this, mijo. I mean it.", when: _spamLevel4, weight: 2.5, tone: ReplyTone.cold),
    ],
    dailyRepeatReactions: [
      DialogueLine("Wait — didn't you already ask me that today?", weight: 2.0, tone: ReplyTone.honest),
      DialogueLine("Mijo, you asked me that earlier. Are you sure you're okay?", weight: 2.0, tone: ReplyTone.vague),
      DialogueLine("You asked me the same thing this morning. Is something on your mind?", weight: 1.5, tone: ReplyTone.honest),
      DialogueLine("We talked about this already today, sweetheart. Did you forget?", weight: 1.5, tone: ReplyTone.warm),
      DialogueLine("You already said that to me today. I answered — you didn't see it?", weight: 1.5, tone: ReplyTone.honest),
      DialogueLine("I feel like we're going in circles, mijo. You okay?", weight: 1.5, tone: ReplyTone.vague),
    ],
    // Ungated on purpose — see RelationshipContent.fallbackReactions. This is
    // the net under every other pool, so it can't have a mood/trust/topic gate
    // that might leave pickLine() with nothing eligible again.
    fallbackReactions: [
      DialogueLine("I don't know what to say to that, mijo.", weight: 1.5, tone: ReplyTone.vague),
      DialogueLine("Honestly? I have no idea how to respond to that.", weight: 1.5, tone: ReplyTone.honest),
      DialogueLine("...I'm not really sure what you mean, mijo.", weight: 1.0, tone: ReplyTone.vague),
      DialogueLine("That one's got me stumped, mijo.", weight: 1.0, tone: ReplyTone.vague),
      DialogueLine("I don't even know how to answer that right now.", weight: 1.0, tone: ReplyTone.honest),
    ],
  ),
  'partner': RelationshipContent(
    openers: [
      DialogueLine("Dinner tonight? I booked the place you like.", topic: Topic.plans),
      DialogueLine("A package showed up at the house that I didn't order — was that you?", topic: Topic.money),
      DialogueLine("I miss you. I barely see you lately.", topic: Topic.affection),
      DialogueLine(
        "I keep thinking about what you said. I love you too, you know.",
        when: _rememberedFirstWarmAndWarmish,
        weight: 2.0,
        topic: Topic.affection,
        tone: ReplyTone.warm,
      ),
      DialogueLine(
        "Don't 'fine' me. Something's off and you know it.",
        when: _moodVerySourOrTwoRecentCold,
        weight: 2.0,
        topic: Topic.suspicion,
      ),
      DialogueLine(
        "Ever since that week, you've been someone else. What happened to us?",
        when: _rememberedCutOff,
        weight: 1.5,
        topic: Topic.suspicion,
      ),
      DialogueLine(
        "Kiko mentioned you've been off with him too. What's going on with you?",
        when: _heardAboutCutOff,
        weight: 1.5,
        topic: Topic.suspicion,
      ),
      DialogueLine(
        "Kiko said y'all had a whole blowup and wouldn't say about what. What happened?",
        when: _heardAboutConfrontation,
        weight: 1.5,
        topic: Topic.suspicion,
      ),
    ],
    questioning: [
      DialogueLine("Where did that money come from? Not complaining, but... weird.", topic: Topic.money),
      DialogueLine("You've been acting really strange. Is there something you want to tell me?", topic: Topic.suspicion),
      DialogueLine("You've barely said two words to me lately. What's going on?", topic: Topic.suspicion),
      DialogueLine("You've been cold for weeks now. Are we even okay?", when: _threeRecentCold, topic: Topic.suspicion),
    ],
    distant: [
      DialogueLine('Uh-huh.', tone: ReplyTone.cold),
      DialogueLine('Whatever you say.', tone: ReplyTone.cold),
      DialogueLine('Sure. Fine.', tone: ReplyTone.cold),
    ],
    confrontation: [DialogueLine("We need to talk. Tonight. I already know you've been lying to me — just tell me the truth.")],
    goneQuietLine: [DialogueLine("The chat's gone gray. They left without a word.")],
    followUp: [DialogueLine("Hello? Are you going to answer me or not.")],
  ),
  // ── friend/brother/oldfriend: original lines preserved verbatim, plus new
  // mood/memory-gated lines layered on top (same treatment as mama/partner)
  // and one new followUp line each. ──
  'friend': RelationshipContent(
    openers: [
      DialogueLine("Hey! We going out this weekend or what?", topic: Topic.plans),
      DialogueLine("I need you to lend me some cash, I'll pay you back next week.", topic: Topic.money),
      DialogueLine("lol what are you even doing that you don't even answer anymore? suspicious 👀", topic: Topic.suspicion),
      DialogueLine(
        "ngl that text hit different. love you too bro",
        when: _rememberedFirstWarmAndWarmish,
        weight: 2.0,
        topic: Topic.affection,
      ),
      DialogueLine(
        "yo you good? you've been mad short with me lately",
        when: _twoRecentCold,
        weight: 1.5,
        topic: Topic.suspicion,
      ),
      DialogueLine(
        "not gonna lie you've been distant since forever ago and I don't even know why",
        when: _rememberedCutOff,
        weight: 1.5,
        topic: Topic.suspicion,
      ),
      DialogueLine(
        "Vale said you've been weird with her lately. everything good?",
        when: _heardAboutCutOff,
        weight: 1.5,
        topic: Topic.suspicion,
      ),
      DialogueLine(
        "Vale told me y'all had a huge blowup and wouldn't say why. what happened man",
        when: _heardAboutConfrontation,
        weight: 1.5,
        topic: Topic.suspicion,
      ),
    ],
    questioning: [
      DialogueLine(
        "for real, what are you into? every time I see you, you've got more cash and you won't say where from",
        topic: Topic.money,
      ),
      DialogueLine("hey seriously, tell me what's going on with you", topic: Topic.suspicion),
      DialogueLine("ngl you've been acting different lately, what's up", topic: Topic.suspicion),
      DialogueLine("for real for real, what's going on. you've been off for weeks", when: _threeRecentCold, topic: Topic.suspicion),
    ],
    distant: [DialogueLine('ok bro'), DialogueLine("nah, I'm not even telling you anything anymore"), DialogueLine('whatever man')],
    confrontation: [DialogueLine('They told someone else "in confidence." Now there are people asking questions they shouldn\'t be.')],
    goneQuietLine: [DialogueLine("They stopped answering. People are saying things around town.")],
    followUp: [DialogueLine("bro you good? kinda weird you went silent")],
  ),
  'brother': RelationshipContent(
    openers: [
      DialogueLine("Can you lend me rent money? I swear I'll pay you back.", topic: Topic.money),
      DialogueLine("Hey, I know you're into something. I want in too.", topic: Topic.plans),
      DialogueLine("Everything good? I don't even see you at family get-togethers anymore.", topic: Topic.family),
      DialogueLine(
        "Didn't expect you to say that. Love you too, man.",
        when: _rememberedFirstWarmAndWarmish,
        weight: 2.0,
        topic: Topic.affection,
      ),
      DialogueLine(
        "You're pulling away and I don't like it. Let me in, or tell me why not.",
        when: _moodSour,
        weight: 1.5,
        topic: Topic.suspicion,
      ),
      DialogueLine(
        "You went cold on me out of nowhere. What'd I do?",
        when: _rememberedCutOff,
        weight: 1.5,
        topic: Topic.suspicion,
      ),
      DialogueLine(
        "Mamá said you've been off with her. What's going on?",
        when: _heardAboutCutOff,
        weight: 1.5,
        topic: Topic.family,
      ),
      DialogueLine(
        "Mamá's not herself. Something happened and nobody's telling me what. What did you do?",
        when: _heardAboutConfrontation,
        weight: 1.5,
        topic: Topic.family,
      ),
    ],
    questioning: [
      DialogueLine('I know you\'re not just a "driver." Tell me the truth.', topic: Topic.suspicion),
      DialogueLine("If you won't bring me in, I'll find my own way in.", topic: Topic.plans),
      DialogueLine("Something's off with you. What is it?", topic: Topic.suspicion),
      DialogueLine("You've gone cold on me. That mean something, or you just busy?", when: _threeRecentCold, topic: Topic.suspicion),
    ],
    distant: [DialogueLine('Whatever.'), DialogueLine("Doesn't matter anymore."), DialogueLine('Sure, whatever.')],
    confrontation: [DialogueLine("They got in on their own with the wrong people. Now it's your problem too.")],
    goneQuietLine: [DialogueLine("They've stopped answering. You heard they're running with other people now.")],
    followUp: [DialogueLine("you good? don't just leave me on read like that")],
  ),
  'oldfriend': RelationshipContent(
    openers: [
      DialogueLine("You should see the baby, she's walking now. You should come meet her.", topic: Topic.family),
      DialogueLine("Everything's calm here. Work, home, repeat. Can't complain about boring lol.", topic: Topic.plans),
      DialogueLine("You still in the same thing? You know there's always another way.", topic: Topic.plans),
      DialogueLine(
        "That really meant something, hearing that from you. Love you too, man.",
        when: _rememberedFirstWarmAndWarmish,
        weight: 2.0,
        topic: Topic.affection,
      ),
      DialogueLine(
        "You don't have to explain yourself to me. Just... take care of yourself, okay?",
        when: _twoRecentCold,
        weight: 1.5,
        topic: Topic.affection,
      ),
      DialogueLine(
        "Something changed between us a while back. I never figured out what.",
        when: _rememberedCutOff,
        weight: 1.5,
        topic: Topic.suspicion,
      ),
    ],
    questioning: [
      DialogueLine("Hey, seriously, are you okay? You've seemed weighed down lately.", topic: Topic.suspicion),
      DialogueLine("You don't have to tell me anything, but I'm here if you ever want out of that.", topic: Topic.plans),
      DialogueLine("You've been carrying something. Want to talk about it?", topic: Topic.suspicion),
      DialogueLine("You've been distant a while now. I'm not pushing, just... you good?", when: _threeRecentCold, topic: Topic.suspicion),
    ],
    distant: [DialogueLine('Take care.'), DialogueLine('Ok, good luck.'), DialogueLine('Alright, take it easy.')],
    confrontation: [DialogueLine("They stopped inviting you to family things. Guess they got their answer.")],
    goneQuietLine: [DialogueLine("They don't text anymore. They got tired of trying.")],
    followUp: [DialogueLine("hey, everything alright? haven't heard from you")],
  ),
};

// ── condition predicates used above — named so the map stays readable ──
// Spam escalation gates — only surface at higher consecutive-action counts.
bool _spamLevel4(DialogueContext ctx) => ctx.consecutiveActionCount >= 4;

// Within-day topic callbacks — used by mama's proactive opener lines.
bool _talkedHealthToday(DialogueContext ctx) => ctx.hasTopicToday(Topic.health);
bool _talkedFamilyToday(DialogueContext ctx) => ctx.hasTopicToday(Topic.family);
bool _talkedPlansToday(DialogueContext ctx) => ctx.hasTopicToday(Topic.plans);
bool _talkedWellbeingToday(DialogueContext ctx) => ctx.hasTopicToday(Topic.wellbeing);
bool _talkedMoneyToday(DialogueContext ctx) => ctx.hasTopicToday(Topic.money);

bool _rememberedFirstWarmAndWarm(DialogueContext ctx) => ctx.hasMemory(MemoryKind.firstWarmReply) && ctx.mood > 30;
bool _rememberedFirstWarmAndWarmish(DialogueContext ctx) => ctx.hasMemory(MemoryKind.firstWarmReply) && ctx.mood > 15;
bool _twoRecentColdButLowSuspicion(DialogueContext ctx) => ctx.countRecentTone(ReplyTone.cold) >= 2 && ctx.suspicion <= 40;
bool _daysSinceReply7(DialogueContext ctx) => ctx.daysSinceReply >= 7;
bool _twoRecentCold(DialogueContext ctx) => ctx.countRecentTone(ReplyTone.cold) >= 2;
bool _moodSoured(DialogueContext ctx) => ctx.mood < -10;
bool _moodSour(DialogueContext ctx) => ctx.mood < -20;
bool _moodVerySourOrTwoRecentCold(DialogueContext ctx) => ctx.mood < -25 || ctx.countRecentTone(ReplyTone.cold) >= 2;
bool _threeRecentCold(DialogueContext ctx) => ctx.countRecentTone(ReplyTone.cold) >= 3;
bool _rememberedCutOff(DialogueContext ctx) => ctx.hasMemory(MemoryKind.cutOff);
bool _heardAboutCutOff(DialogueContext ctx) => ctx.hasMemory(MemoryKind.heardAboutCutOff);
bool _heardAboutConfrontation(DialogueContext ctx) => ctx.hasMemory(MemoryKind.heardAboutConfrontation);
