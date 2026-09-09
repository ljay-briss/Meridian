// Mama's intent-chip catalog. A chip represents WHAT the player wants to
// communicate ([ConversationIntent]) — the engine decides HOW it's actually
// worded (via [phrasings], picked through the same pickLine() freshness
// machinery as every other line in the game) and how Mama reacts (via
// content/mama_reactions.dart, resolved in CareerController.personalReplyAction).
//
// This intentionally reuses PersonalReplyAction's gate shape
// (showWhenMoodBelow/Above, requiresThread, showWhenLevelMin/Max,
// showWhenTrustBelow/Above, showWhenSuspicionAbove, showWhenClosenessAbove)
// so CareerController can score/cut an IntentChip with the same logic it
// already uses for a PersonalReplyAction — see
// CareerController._intentChipScore, which mirrors _personalReplyOptionScore.
import '../content/mama_reactions.dart';
import '../data.dart';

/// Something that can occupy a slot in a personal thread's reply tray —
/// either an [IntentChip] (the player choosing what to say) or a
/// [StoryChipOption] (a specific thing that just happened, wrapping the
/// legacy [PersonalReplyAction] `_storyContextChips()` already produces). The
/// tray combines both; see relationships_screen.dart's `_ReplyTray`.
abstract class ReplyOption {
  /// The chip's button text — always a bracketed action name ("(Check-In)",
  /// "(Mention the Close Call)"), never the sentence it'll actually send;
  /// see [IntentChip.displayLabel]/[StoryChipOption.displayLabel].
  String displayLabel(RelationshipState rel, TimeOfDay tod);

  /// A short parenthetical read on how this will land right now (e.g.
  /// "playful" vs "cold" on the same Insult chip) — null when the chip
  /// doesn't have flavor branching built out, or isn't the kind of chip
  /// that needs one.
  String? toneHint(RelationshipState rel);
}

class IntentChip implements ReplyOption {
  final ConversationIntent intent;
  final String label;

  /// Candidate player-side wording — picked via pickLine() with the same
  /// freshness/mood/topic gating as any other DialogueLine pool, so the
  /// sentence actually sent varies turn to turn even though the chip itself
  /// always reads the same.
  final List<DialogueLine> phrasings;

  /// Fallback (tone, topics, intent) used only if the picked phrasing leaves
  /// one of them unset, and as the representative register for tray-scoring
  /// nudges (CareerController._intentChipScore) — the real per-turn values
  /// come from whichever phrasing line pickLine() actually chose.
  final ReplyTone primaryTone;
  final Set<Topic> primaryTopics;
  final Intent primaryIntent;
  final double intensity;

  final double? showWhenMoodBelow;
  final double? showWhenMoodAbove;
  final bool requiresThread;
  final int? showWhenLevelMin;
  final int? showWhenLevelMax;
  final double? showWhenTrustBelow;
  final double? showWhenTrustAbove;
  final double? showWhenSuspicionAbove;
  final double? showWhenClosenessAbove;

  final String Function(RelationshipState rel)? _toneHint;

  const IntentChip({
    required this.intent,
    required this.label,
    required this.phrasings,
    required this.primaryTone,
    this.primaryTopics = const {},
    required this.primaryIntent,
    this.intensity = 0.4,
    this.showWhenMoodBelow,
    this.showWhenMoodAbove,
    this.requiresThread = false,
    this.showWhenLevelMin,
    this.showWhenLevelMax,
    this.showWhenTrustBelow,
    this.showWhenTrustAbove,
    this.showWhenSuspicionAbove,
    this.showWhenClosenessAbove,
    String Function(RelationshipState rel)? toneHint,
  }) : _toneHint = toneHint;

  /// Parenthesized so a chip always reads as "what I want to say", never as
  /// the sentence itself — "(Insult)", or "(Insult · playful)" once a hint
  /// is available, distinct from a story chip's full resolved sentence.
  @override
  String displayLabel(RelationshipState rel, TimeOfDay tod) {
    final hint = toneHint(rel);
    return hint == null ? '($label)' : '($label · $hint)';
  }

  @override
  String? toneHint(RelationshipState rel) => _toneHint?.call(rel);
}

/// Adapts a legacy story-context [PersonalReplyAction] (still produced by
/// `CareerController._storyContextChips()`) into a [ReplyOption] so the tray
/// can mix it with [IntentChip]s without either side knowing about the other.
class StoryChipOption implements ReplyOption {
  final PersonalReplyAction action;
  const StoryChipOption(this.action);

  /// Bracketed, same as [IntentChip] — "(Mention the Close Call)", not the
  /// full sentence it'll actually send. Every chip in a tray reads as one
  /// consistent form (what the player wants to say), never a mix of that
  /// and the sentence itself; [action]'s picked [PersonalReplyAction.
  /// phrasings] line still supplies the real wording, just for the thread
  /// message once tapped, not the button.
  @override
  String displayLabel(RelationshipState rel, TimeOfDay tod) => '(${action.label})';

  @override
  String? toneHint(RelationshipState rel) => null;
}

/// The player asking Mama for a specific dollar amount — see
/// CareerController.resolveMoneyAsk. Unlike [IntentChip]/[StoryChipOption],
/// tapping this doesn't send a reply by itself: relationships_screen.dart's
/// reply-tray tap handler opens a number-entry dialog instead, and the reply
/// only goes out once the player types an amount and confirms.
class MoneyAskChipOption implements ReplyOption {
  const MoneyAskChipOption();

  @override
  String displayLabel(RelationshipState rel, TimeOfDay tod) => '(Ask for Money)';

  @override
  String? toneHint(RelationshipState rel) => null;
}

// Named top-level adapters, not lambdas — a lambda literal isn't a constant
// expression in Dart, and kIntentChips (below) is a const list, so each
// chip's toneHint has to be a plain function reference.
String _greetHint(RelationshipState r) => mamaGreetFlavor(mood: r.mood, trust: r.trust, closeness: r.closeness, suspicion: r.suspicion);
String _checkInHint(RelationshipState r) => mamaCheckInFlavor(mood: r.mood, trust: r.trust, closeness: r.closeness, suspicion: r.suspicion);
String _familyHint(RelationshipState r) => mamaFamilyFlavor(mood: r.mood, trust: r.trust, closeness: r.closeness, suspicion: r.suspicion);
String _apologizeHint(RelationshipState r) => mamaApologizeFlavor(mood: r.mood, trust: r.trust, closeness: r.closeness, suspicion: r.suspicion);
String _jokeHint(RelationshipState r) => mamaJokeFlavor(mood: r.mood, trust: r.trust, closeness: r.closeness, suspicion: r.suspicion);
String _insultHint(RelationshipState r) => mamaInsultFlavor(mood: r.mood, trust: r.trust, closeness: r.closeness, suspicion: r.suspicion);

/// Full catalog. Only offered to Mama — CareerController.personalReplyOptions
/// branches on contactId and leaves every other contact on the original
/// kPersonalReplyActions catalog untouched.
///
/// Gated in three level tiers via showWhenLevelMin, the same field
/// PersonalReplyAction already used for its own level-gated entries: small
/// talk from level 1, heavier conversational moves from level 3, and the
/// most loaded ones (loyalty, reconciliation) from level 5 — by which point
/// there's actually something to be loyal about or make peace over.
const List<IntentChip> kIntentChips = [
  // ── Continuation (always available, always scored to win a slot once a
  // thread is actually live — see CareerController._intentChipScore) ─────
  IntentChip(
    intent: ConversationIntent.elaborate,
    label: 'Explain More',
    primaryTone: ReplyTone.honest,
    primaryTopics: {},
    primaryIntent: Intent.statement,
    intensity: 0.4,
    // Every phrasing here is topic-tagged and actually says something — no
    // untagged/content-free filler. This chip means "explain what's live";
    // see [ConversationIntent.deflect] ("Not Right Now") for the player
    // declining to. pickLine()'s topic-tiering (see its doc comment in
    // dialogue_engine.dart) means the tag on each line below is now a hard
    // requirement, not just a weight boost — so this pool needs at least one
    // real line per [Topic] that can plausibly be the live thread when this
    // chip is offered, or tapping it on that topic would come back empty and
    // fall through to a DIFFERENT topic's line, which is its own kind of
    // non-sequitur. Keep that coverage in mind before removing a line here.
    phrasings: [
      // Topic.plans — the "new job"/vague-plans follow-up. The first one
      // establishes ConversationFact 'coverJob' = 'driving' (Phase 6) — a
      // representative example of the mechanism, not a full pass over every
      // line here; see kPersonalReactions['mama'][ReplyTone.honest]'s PLANS
      // section in data.dart for the matching requiredFacts-gated line.
      // subject: 'coverJob' (Phase 12) sets RelationshipState.topicSubject
      // via advanceTopic() so a later requiredSubject-gated opener (see
      // data.dart's matching callback) can tell "we're specifically on the
      // cover-job subject right now" apart from Topic.plans in general.
      DialogueLine(
        "It's mostly driving and running errands for now. Still getting the hang of it.",
        tone: ReplyTone.vague,
        topic: Topic.plans,
        subject: 'coverJob',
        establishesFacts: {'coverJob': 'driving'},
      ),
      DialogueLine("Nothing's really set in stone yet — still figuring out the details myself.", tone: ReplyTone.vague, topic: Topic.plans),
      DialogueLine("It pays better than the last thing. That's really all I can say right now.", tone: ReplyTone.honest, topic: Topic.plans),
      // Establishes 'coverJob' = 'restaurant' — deliberately conflicts with
      // the 'driving' phrasing above (Phase 8's ContradictionEvent example),
      // since pickLine() can land on either one turn to turn.
      DialogueLine(
        "Actually, it's changed — I'm working at a restaurant now.",
        tone: ReplyTone.honest,
        topic: Topic.plans,
        establishesFacts: {'coverJob': 'restaurant'},
      ),
      // Topic.wellbeing — "you okay?" follow-ups that were left vague.
      DialogueLine("I'm managing, Mamá. Just a lot going on that I can't fully get into.", tone: ReplyTone.vague, topic: Topic.wellbeing),
      DialogueLine("It's just been a lot to carry, and I didn't want to worry you with the details.", tone: ReplyTone.honest, topic: Topic.wellbeing),
      // Topic.goodNews — actually saying what the good news was, distinct
      // from Topic.wellbeing above: that's a hardship/check-in register,
      // this is a positive-update one.
      DialogueLine("Okay — I actually pulled something off today. Feels good to say out loud.", tone: ReplyTone.warm, topic: Topic.goodNews),
      DialogueLine("It's nothing huge, Mamá, but it actually went the way I wanted for once.", tone: ReplyTone.warm, topic: Topic.goodNews),
      DialogueLine("I don't know why it feels weird to say, but yeah — it actually worked out.", tone: ReplyTone.honest, topic: Topic.goodNews),
      // Topic.suspicion — when she's pushing on something that felt off.
      DialogueLine("It's nothing you need to worry about, I promise.", tone: ReplyTone.vague, topic: Topic.suspicion),
      DialogueLine("I know how it looks. It's not as bad as you're imagining.", tone: ReplyTone.honest, topic: Topic.suspicion),
      // Topic.money — follow-ups on a money comment that was left hanging.
      DialogueLine("Money's actually been a little better lately. That's the short version.", tone: ReplyTone.honest, topic: Topic.money),
      DialogueLine("I'd rather not get into the specifics, but it's under control.", tone: ReplyTone.vague, topic: Topic.money),
      // Topic.family — a real answer once she's actually pushed on family.
      DialogueLine("Tono and I talked. It's fine now, we worked it out.", tone: ReplyTone.honest, topic: Topic.family),
      DialogueLine("I've just been avoiding tía's calls. It's not serious.", tone: ReplyTone.vague, topic: Topic.family),
      // Topic.health — filling in a health mention that was left vague.
      DialogueLine("It's nothing major, just been run down lately.", tone: ReplyTone.vague, topic: Topic.health),
      DialogueLine("The doctor said it's mostly stress. I'm handling it.", tone: ReplyTone.honest, topic: Topic.health),
      // Topic.affection — actually saying more once she's pushed past a deflection.
      DialogueLine("I don't say it enough, but I do think about you a lot.", tone: ReplyTone.warm, topic: Topic.affection),
      DialogueLine("It's hard to put into words, but I care more than I show.", tone: ReplyTone.warm, topic: Topic.affection),
    ],
  ),
  IntentChip(
    intent: ConversationIntent.deflect,
    label: 'Not Right Now',
    primaryTone: ReplyTone.vague,
    primaryTopics: {},
    primaryIntent: Intent.dismissal,
    intensity: 0.3,
    // Only offered once a thread actually exists — declining to elaborate
    // makes no sense as an opener. Deliberately topic-agnostic: the whole
    // point of this chip is not naming what's being avoided, so unlike
    // [ConversationIntent.elaborate] it doesn't need per-[Topic] coverage.
    requiresThread: true,
    phrasings: [
      DialogueLine("I don't really want to get into it right now.", tone: ReplyTone.vague),
      DialogueLine("Can we just leave it for now?", tone: ReplyTone.vague),
      DialogueLine("Not really something I want to talk about right now.", tone: ReplyTone.vague),
      DialogueLine("I'd rather not get into that today.", tone: ReplyTone.vague),
    ],
  ),

  // ── Early (always available) ──────────────────────────────────────────
  IntentChip(
    intent: ConversationIntent.greet,
    label: 'Greet',
    primaryTone: ReplyTone.warm,
    primaryTopics: {Topic.greeting},
    primaryIntent: Intent.statement,
    intensity: 0.2,
    toneHint: _greetHint,
    // Style-tagged (Phase 17's DialogueStyle — see dialogue_engine.dart):
    // same action (greet Mama), same button, seven different registers a
    // real person might actually reach for depending who they are — pickLine()
    // leans toward whichever one this contact's CharacterPersonality favors
    // (see styleMatch), but any of them can still come up.
    phrasings: [
      DialogueLine('Morning, Mama.', tone: ReplyTone.warm, topic: Topic.greeting, timesOfDay: {TimeOfDay.morning}, style: DialogueStyle.warm),
      DialogueLine('Hey Mama.', tone: ReplyTone.warm, topic: Topic.greeting, style: DialogueStyle.warm),
      DialogueLine('Hey, you.', tone: ReplyTone.warm, topic: Topic.greeting, style: DialogueStyle.affectionate),
      DialogueLine("How you doing?", tone: ReplyTone.honest, topic: Topic.wellbeing, intent: Intent.question, style: DialogueStyle.serious),
      DialogueLine("What's good?", tone: ReplyTone.vague, topic: Topic.greeting, style: DialogueStyle.casual),
      DialogueLine('Yo.', tone: ReplyTone.vague, topic: Topic.greeting, style: DialogueStyle.short),
      DialogueLine("Look who remembered your number. 😏", tone: ReplyTone.warm, topic: Topic.greeting, style: DialogueStyle.funny),
      DialogueLine("Guess who's thinking about you right now?", tone: ReplyTone.warm, topic: Topic.greeting, style: DialogueStyle.playful),
    ],
  ),
  IntentChip(
    intent: ConversationIntent.checkIn,
    label: 'Check-In',
    primaryTone: ReplyTone.honest,
    primaryTopics: {Topic.wellbeing},
    primaryIntent: Intent.question,
    intensity: 0.3,
    toneHint: _checkInHint,
    // Style-tagged, same rationale as Greet above — this is the pool
    // dialogue_engine.dart's DialogueStyle doc comment uses as its own
    // worked example.
    phrasings: [
      DialogueLine('Hey mama, how you doing?', intent: Intent.question, tone: ReplyTone.warm, style: DialogueStyle.warm),
      DialogueLine('What\'s up ma?', intent: Intent.question, tone: ReplyTone.vague, style: DialogueStyle.casual),
      DialogueLine('You alive over there? 😂', intent: Intent.question, tone: ReplyTone.warm, style: DialogueStyle.funny),
      DialogueLine('Hey mama ❤️ How\'s your day going?', intent: Intent.question, tone: ReplyTone.warm, style: DialogueStyle.affectionate),
      DialogueLine('How you been?', intent: Intent.question, style: DialogueStyle.short),
      DialogueLine('I want to check in for real — how are you doing, honestly?', intent: Intent.question, tone: ReplyTone.honest, style: DialogueStyle.serious),
      DialogueLine('Aight, be honest — how\'s my favorite mother doing today?', intent: Intent.question, tone: ReplyTone.warm, style: DialogueStyle.playful),
    ],
  ),
  IntentChip(
    intent: ConversationIntent.askAboutFamily,
    label: 'Ask About Family',
    primaryTone: ReplyTone.honest,
    primaryTopics: {Topic.family},
    primaryIntent: Intent.question,
    intensity: 0.3,
    toneHint: _familyHint,
    phrasings: [
      DialogueLine("How's the family?", intent: Intent.question),
      DialogueLine("How's everyone doing?", intent: Intent.question),
      DialogueLine('Tell me about home.', tone: ReplyTone.warm),
      DialogueLine("How's tío and the rest?", intent: Intent.question),
    ],
  ),
  IntentChip(
    intent: ConversationIntent.thank,
    label: 'Thank',
    primaryTone: ReplyTone.warm,
    primaryTopics: {Topic.affection},
    primaryIntent: Intent.statement,
    intensity: 0.4,
    phrasings: [
      DialogueLine('Thank you, Mamá. For everything.', tone: ReplyTone.warm),
      DialogueLine("I don't say it enough, but thank you.", tone: ReplyTone.warm),
      DialogueLine('Really, thank you.', tone: ReplyTone.warm),
      DialogueLine('Appreciate you more than you know.', tone: ReplyTone.warm),
    ],
  ),
  IntentChip(
    intent: ConversationIntent.compliment,
    label: 'Compliment',
    primaryTone: ReplyTone.warm,
    primaryTopics: {Topic.affection},
    primaryIntent: Intent.statement,
    intensity: 0.4,
    phrasings: [
      DialogueLine('You always know what to say.', tone: ReplyTone.warm),
      DialogueLine("You're stronger than you give yourself credit for.", tone: ReplyTone.warm),
      DialogueLine("Not gonna lie, you're kind of amazing.", tone: ReplyTone.warm),
      DialogueLine('You did good raising me. Just saying.', tone: ReplyTone.honest),
    ],
  ),
  IntentChip(
    intent: ConversationIntent.apologize,
    label: 'Apologize',
    primaryTone: ReplyTone.warm,
    primaryTopics: {Topic.wellbeing},
    primaryIntent: Intent.promise,
    intensity: 0.6,
    requiresThread: true,
    toneHint: _apologizeHint,
    phrasings: [
      DialogueLine('I\'m sorry, Mamá.', tone: ReplyTone.warm, intent: Intent.promise),
      DialogueLine("I know I've been distant. I'm sorry.", tone: ReplyTone.honest, intent: Intent.promise),
      DialogueLine('That was on me. I\'m sorry.', tone: ReplyTone.honest, intent: Intent.promise),
      DialogueLine("I shouldn't have said that. Sorry.", tone: ReplyTone.warm, intent: Intent.promise),
    ],
  ),
  IntentChip(
    intent: ConversationIntent.sayGoodbye,
    label: 'Say Goodbye',
    primaryTone: ReplyTone.warm,
    primaryTopics: {Topic.greeting},
    primaryIntent: Intent.statement,
    intensity: 0.2,
    requiresThread: true,
    phrasings: [
      DialogueLine('Gotta go, Mamá. Love you.', tone: ReplyTone.warm),
      DialogueLine("I'll call you later, okay?", tone: ReplyTone.warm),
      DialogueLine('Talk soon.', tone: ReplyTone.vague),
      DialogueLine('Love you. Bye for now.', tone: ReplyTone.warm),
    ],
  ),

  // ── Mid (level 3+) ─────────────────────────────────────────────────────
  IntentChip(
    intent: ConversationIntent.askAboutWork,
    label: 'Ask About Work',
    primaryTone: ReplyTone.honest,
    primaryTopics: {Topic.plans},
    primaryIntent: Intent.question,
    intensity: 0.3,
    showWhenLevelMin: 3,
    phrasings: [
      DialogueLine("How's work been for you?", intent: Intent.question),
      DialogueLine('Still dealing with the same people at work?', intent: Intent.question),
      DialogueLine("How's everything at your job?", intent: Intent.question),
    ],
  ),
  IntentChip(
    intent: ConversationIntent.askWhatsGoingOn,
    label: "What's Going On",
    primaryTone: ReplyTone.honest,
    primaryTopics: {Topic.wellbeing},
    primaryIntent: Intent.question,
    intensity: 0.4,
    showWhenLevelMin: 3,
    phrasings: [
      DialogueLine("What's going on with you lately?", intent: Intent.question),
      DialogueLine("You've seemed off. What's up?", intent: Intent.question, topic: Topic.suspicion),
      DialogueLine('Something on your mind?', intent: Intent.question),
    ],
  ),
  IntentChip(
    intent: ConversationIntent.askAboutSomeone,
    label: 'Ask About Someone',
    primaryTone: ReplyTone.honest,
    primaryTopics: {Topic.family},
    primaryIntent: Intent.question,
    intensity: 0.3,
    showWhenLevelMin: 3,
    phrasings: [
      DialogueLine('Have you talked to Tono lately?', intent: Intent.question, topic: Topic.family),
      DialogueLine("How's tía doing these days?", intent: Intent.question, topic: Topic.family),
      DialogueLine("What's going on with the neighbors?", intent: Intent.question),
    ],
  ),
  IntentChip(
    intent: ConversationIntent.askForAdvice,
    label: 'Ask for Advice',
    primaryTone: ReplyTone.honest,
    primaryTopics: {Topic.plans},
    primaryIntent: Intent.question,
    intensity: 0.4,
    showWhenLevelMin: 3,
    phrasings: [
      DialogueLine('Can I ask you something? Need advice.', intent: Intent.question),
      DialogueLine('What would you do in my position?', intent: Intent.question),
      DialogueLine('I could use your advice on something.', tone: ReplyTone.honest),
    ],
  ),
  IntentChip(
    intent: ConversationIntent.askForHelp,
    label: 'Ask for Help',
    primaryTone: ReplyTone.honest,
    primaryTopics: {Topic.plans},
    primaryIntent: Intent.question,
    intensity: 0.5,
    showWhenLevelMin: 3,
    phrasings: [
      DialogueLine('I need a favor, Mamá.', intent: Intent.question),
      DialogueLine('Could you help me with something?', intent: Intent.question),
      DialogueLine('I hate to ask, but I need help.', tone: ReplyTone.honest, intent: Intent.question),
    ],
  ),
  IntentChip(
    intent: ConversationIntent.joke,
    label: 'Joke',
    primaryTone: ReplyTone.warm,
    primaryTopics: {Topic.affection},
    primaryIntent: Intent.statement,
    intensity: 0.3,
    showWhenLevelMin: 3,
    toneHint: _jokeHint,
    phrasings: [
      DialogueLine('Okay but hear me out—', tone: ReplyTone.warm),
      DialogueLine("You're gonna laugh at this one.", tone: ReplyTone.warm),
      DialogueLine('Got a joke for you.', tone: ReplyTone.warm),
      DialogueLine('Don\'t say I never make you laugh.', tone: ReplyTone.warm),
    ],
  ),
  IntentChip(
    intent: ConversationIntent.insult,
    label: 'Insult',
    primaryTone: ReplyTone.vague,
    primaryTopics: {},
    primaryIntent: Intent.dismissal,
    intensity: 0.5,
    showWhenLevelMin: 3,
    toneHint: _insultHint,
    phrasings: [
      DialogueLine("You're impossible, you know that?", tone: ReplyTone.warm),
      DialogueLine('Okay, you\'re a little annoying sometimes.', tone: ReplyTone.vague),
      DialogueLine('Honestly? You can be a lot.', tone: ReplyTone.cold),
      DialogueLine("You're ridiculous.", tone: ReplyTone.warm),
    ],
  ),
  IntentChip(
    intent: ConversationIntent.confront,
    label: 'Confront',
    primaryTone: ReplyTone.cold,
    primaryTopics: {Topic.suspicion},
    primaryIntent: Intent.statement,
    intensity: 0.6,
    showWhenLevelMin: 3,
    requiresThread: true,
    phrasings: [
      DialogueLine('We need to talk about something.', tone: ReplyTone.honest),
      DialogueLine('I need you to be straight with me.', tone: ReplyTone.honest, topic: Topic.suspicion),
      DialogueLine("Something's not adding up. Explain it.", tone: ReplyTone.cold, topic: Topic.suspicion),
    ],
  ),

  // ── Late (level 5+) ────────────────────────────────────────────────────
  IntentChip(
    intent: ConversationIntent.questionLoyalty,
    label: 'Question Loyalty',
    primaryTone: ReplyTone.cold,
    primaryTopics: {Topic.suspicion},
    primaryIntent: Intent.statement,
    intensity: 0.7,
    showWhenLevelMin: 5,
    showWhenTrustBelow: 60,
    requiresThread: true,
    phrasings: [
      DialogueLine('Are you even on my side anymore?', tone: ReplyTone.cold, topic: Topic.suspicion),
      DialogueLine('Do you actually trust me, or not?', tone: ReplyTone.honest, topic: Topic.suspicion, intent: Intent.question),
      DialogueLine('Sometimes I wonder whose side you\'re on.', tone: ReplyTone.vague, topic: Topic.suspicion),
    ],
  ),
  IntentChip(
    intent: ConversationIntent.reassure,
    label: 'Reassure',
    primaryTone: ReplyTone.warm,
    primaryTopics: {Topic.affection},
    primaryIntent: Intent.promise,
    intensity: 0.5,
    showWhenLevelMin: 5,
    phrasings: [
      DialogueLine("I've got this, Mamá. I promise.", tone: ReplyTone.warm, intent: Intent.promise),
      DialogueLine("You don't need to worry about me.", tone: ReplyTone.warm),
      DialogueLine('I\'m being careful. I promise.', tone: ReplyTone.warm, intent: Intent.promise),
    ],
  ),
  IntentChip(
    intent: ConversationIntent.makePeace,
    label: 'Make Peace',
    primaryTone: ReplyTone.warm,
    primaryTopics: {Topic.affection},
    primaryIntent: Intent.promise,
    intensity: 0.6,
    showWhenLevelMin: 5,
    showWhenMoodBelow: 10,
    requiresThread: true,
    phrasings: [
      DialogueLine("Let's not fight about this anymore.", tone: ReplyTone.warm, intent: Intent.promise),
      DialogueLine('Can we just be okay again?', tone: ReplyTone.warm, intent: Intent.question),
      DialogueLine("I don't want this between us.", tone: ReplyTone.honest),
    ],
  ),
  IntentChip(
    intent: ConversationIntent.sarcasm,
    label: 'Be Sarcastic',
    primaryTone: ReplyTone.vague,
    primaryTopics: {},
    primaryIntent: Intent.statement,
    intensity: 0.3,
    showWhenLevelMin: 5,
    phrasings: [
      DialogueLine("Oh sure, because that's totally how that works.", tone: ReplyTone.vague),
      DialogueLine('Yeah, no, that makes total sense.', tone: ReplyTone.vague),
      DialogueLine('Wow. Groundbreaking.', tone: ReplyTone.cold),
    ],
  ),
  IntentChip(
    intent: ConversationIntent.congratulate,
    label: 'Congratulate',
    primaryTone: ReplyTone.warm,
    primaryTopics: {Topic.affection},
    primaryIntent: Intent.statement,
    intensity: 0.3,
    showWhenLevelMin: 5,
    phrasings: [
      DialogueLine('Proud of you for that, seriously.', tone: ReplyTone.warm),
      DialogueLine("That's huge. Congrats, Mamá.", tone: ReplyTone.warm),
      DialogueLine('You deserve this. Congrats.', tone: ReplyTone.warm),
    ],
  ),
];

/// Bespoke reply-stance chips for something SPECIFIC Mama just said, keyed
/// by [DialogueLine.questionId]. When [RelationshipState.pendingQuestionId]
/// matches a key here, `reply_tray.dart`'s `personalReplyOptions` swaps the
/// entire tray to exactly this list instead of the generic catalog — the
/// tray responding to Mama's exact last line (plus thread/relationship/
/// recent-history state, via the usual gates on each chip below), not just
/// [RelationshipState.currentTopic] in the abstract. Despite the map's name,
/// this isn't limited to lines grammatically phrased as questions (see
/// [DialogueLine.questionId]'s own doc comment) — `'mama_brother_distant'`
/// below fires off a line that reads as a question, but the mechanism
/// doesn't require one.
///
/// Not every line Mama can say has an entry here — only the ones authored
/// (see `data.dart`'s clusters: every wellbeing "how are you / how was
/// your day" line shares `'mama_wellbeing_checkin'`, every suspicion
/// "something feels off with you" line shares `'mama_suspicion_distant'`,
/// the rare "your brother said you've been distant" callback shares
/// `'mama_brother_distant'`, and the everyday "did you talk to Tono?"
/// check-in shares `'mama_asked_about_tono'`). A pending id with no matching
/// key here falls through to the ordinary tray untouched — this is
/// additive, not a replacement for the general system.
///
/// `'mama_uncle_back'`/`'mama_uncle_stubborn'` (item 11) are a two-step
/// ACTION CHAIN, not a single tray: tapping "Ask About Uncle" from the
/// first sends a [PersonalReplyAction] whose own reply (see
/// `content/mama_reactions.dart`'s `ConversationIntent.askAboutUncle`)
/// carries a SECOND questionId, so `pendingQuestionId` gets set again and
/// the tray swaps a second time — no new engine mechanism, just a chip
/// whose reply happens to carry another id. Nothing stops a chain running
/// deeper than two steps, or converging back into an existing id instead of
/// opening a new leaf — `'mama_uncle_stubborn'`'s "Ask How Mama Is Doing"
/// does exactly that, routing back into `'mama_wellbeing_checkin'` above.
///
/// Each list runs 5 stances wide, the same shape every time: a positive
/// answer, a negative/honest answer, a fuller confession, a dodge (mirrors
/// [ConversationIntent.deflect]'s "Not Right Now" — `intent: Intent.dismissal`,
/// not [resolvesThread], so it reads as a genuine dodge to
/// [resolvePendingQuestion] and leaves the question pending rather than
/// closing it out), and a redirect back onto Mama. [resolvesThread] is set
/// on every stance except the dodge, so picking an actual answer — even a
/// defensive or evasive-sounding one — closes out the pending question
/// rather than leaving it hanging turn after turn.
const Map<String, List<PersonalReplyAction>> kQuestionAnswerChips = {
  'mama_wellbeing_checkin': [
    PersonalReplyAction(
      "Say It's Going Well",
      tone: ReplyTone.warm,
      topics: {Topic.wellbeing},
      intent: Intent.statement,
      intensity: 0.3,
      resolvesThread: true,
      phrasings: [
        DialogueLine("It's actually been going well. Can't complain."),
        DialogueLine("Honestly? Pretty good lately."),
      ],
    ),
    PersonalReplyAction(
      "Say It's Been Difficult",
      tone: ReplyTone.honest,
      topics: {Topic.wellbeing},
      intent: Intent.statement,
      intensity: 0.4,
      resolvesThread: true,
      phrasings: [
        DialogueLine("It's been hard, Mamá. Not gonna lie."),
        DialogueLine("Honestly, it's been a rough stretch."),
      ],
    ),
    PersonalReplyAction(
      'Tell Her What Happened',
      tone: ReplyTone.honest,
      topics: {Topic.wellbeing},
      intent: Intent.confession,
      intensity: 0.5,
      resolvesThread: true,
      phrasings: [
        DialogueLine("Okay, I'll tell you — some stuff happened and I've been dealing with it."),
        DialogueLine("Alright, here's what's actually going on with me."),
      ],
    ),
    PersonalReplyAction(
      'Avoid The Question',
      tone: ReplyTone.vague,
      topics: {Topic.wellbeing},
      intent: Intent.dismissal,
      intensity: 0.3,
      phrasings: [
        DialogueLine("Can we not get into that right now?"),
        DialogueLine("I'd rather not talk about it."),
      ],
    ),
    PersonalReplyAction(
      'Ask About Her Day',
      tone: ReplyTone.warm,
      topics: {Topic.wellbeing},
      intent: Intent.question,
      intensity: 0.3,
      resolvesThread: true,
      phrasings: [
        DialogueLine("I'm fine — how about you? How's your day been?"),
        DialogueLine("I'm okay. Enough about me, how are you doing?"),
      ],
    ),
  ],
  'mama_suspicion_distant': [
    PersonalReplyAction(
      "Deny Anything's Wrong",
      tone: ReplyTone.vague,
      topics: {Topic.suspicion},
      intent: Intent.statement,
      intensity: 0.4,
      resolvesThread: true,
      phrasings: [
        DialogueLine("Nothing's wrong, Mamá. I promise."),
        DialogueLine("Everything's fine, really."),
      ],
    ),
    PersonalReplyAction(
      "Admit Something's Off",
      tone: ReplyTone.honest,
      topics: {Topic.suspicion},
      intent: Intent.confession,
      intensity: 0.5,
      resolvesThread: true,
      phrasings: [
        DialogueLine("Okay... something has been off. But I'm handling it."),
        DialogueLine("Yeah, honestly, not everything's been right lately."),
      ],
    ),
    PersonalReplyAction(
      "Explain What's Really Going On",
      tone: ReplyTone.honest,
      topics: {Topic.suspicion},
      intent: Intent.confession,
      intensity: 0.7,
      resolvesThread: true,
      isVulnerableDisclosure: true,
      phrasings: [
        DialogueLine("Alright, Mamá — here's what's actually been going on."),
        DialogueLine("Okay, I'll stop dancing around it. Here's the truth."),
      ],
    ),
    PersonalReplyAction(
      'Get Defensive',
      tone: ReplyTone.cold,
      topics: {Topic.suspicion},
      intent: Intent.dismissal,
      intensity: 0.5,
      phrasings: [
        DialogueLine("Why does something always have to be wrong with me?"),
        DialogueLine("Can you stop reading into everything I say?"),
      ],
    ),
    PersonalReplyAction(
      'Reassure Her',
      tone: ReplyTone.warm,
      topics: {Topic.suspicion},
      intent: Intent.promise,
      intensity: 0.5,
      resolvesThread: true,
      phrasings: [
        DialogueLine("I hear you. I'm okay, I promise — you don't need to worry."),
        DialogueLine("I know you worry. I'm alright, Mamá, I promise."),
      ],
    ),
  ],
  'mama_brother_distant': [
    PersonalReplyAction(
      "Say Everything's Good",
      tone: ReplyTone.warm,
      topics: {Topic.family},
      intent: Intent.statement,
      intensity: 0.3,
      subject: 'brother',
      resolvesThread: true,
      phrasings: [
        DialogueLine("Yeah, everything's good. We're fine, Mamá."),
        DialogueLine("Everything's good with us, really — no need to worry."),
      ],
    ),
    PersonalReplyAction(
      "Say You've Been Busy With Work",
      tone: ReplyTone.honest,
      topics: {Topic.family},
      intent: Intent.statement,
      intensity: 0.4,
      subject: 'brother',
      resolvesThread: true,
      phrasings: [
        DialogueLine("I've just been slammed with work, that's all. Nothing's wrong."),
        DialogueLine("Work's been eating up all my time lately — that's the whole story."),
      ],
    ),
    PersonalReplyAction(
      'Admit You Had An Argument',
      tone: ReplyTone.honest,
      topics: {Topic.family},
      intent: Intent.confession,
      intensity: 0.5,
      subject: 'brother',
      resolvesThread: true,
      phrasings: [
        DialogueLine("We had an argument, actually. It's not a big deal, we'll work it out."),
        DialogueLine("Tono and I got into it. I've just been avoiding calling him since."),
      ],
    ),
    PersonalReplyAction(
      "Say You Don't Want To Talk About It",
      tone: ReplyTone.vague,
      topics: {Topic.family},
      intent: Intent.dismissal,
      intensity: 0.3,
      subject: 'brother',
      phrasings: [
        DialogueLine("I don't really want to get into it, Mamá."),
        DialogueLine("Can we not talk about that right now?"),
      ],
    ),
    PersonalReplyAction(
      'Ask About Her Brother',
      tone: ReplyTone.warm,
      topics: {Topic.family},
      intent: Intent.question,
      intensity: 0.3,
      subject: 'brother',
      resolvesThread: true,
      phrasings: [
        DialogueLine("What did he say exactly? Is he doing okay?"),
        DialogueLine("Did he seem upset when you talked to him?"),
      ],
    ),
  ],
  // Item 7's own worked example ("Did you talk to Marcus?" — a plain yes/no
  // factual question, `subject: 'Tono'` in the actual shipped line above
  // rather than the doc comments' placeholder name — see
  // PendingInteraction's doc comment in dialogue_engine.dart). The one
  // cluster of the four built so far that's genuinely a yes/no question
  // rather than an open-ended stance one, so "Answer Yes"/"Answer No" sit
  // where "Say It's Going Well"/"Say It's Been Difficult" did for
  // mama_wellbeing_checkin — same five-slot shape, different register.
  // "Change The Subject" is deliberately distinct from "Avoid The
  // Question": the former [resolvesThread]s (an active pivot still counts
  // as addressing the moment) while the latter is a genuine
  // [Intent.dismissal] dodge that leaves the question hanging — see this
  // map's own doc comment.
  'mama_asked_about_tono': [
    PersonalReplyAction(
      'Answer Yes',
      tone: ReplyTone.warm,
      topics: {Topic.family},
      intent: Intent.statement,
      intensity: 0.3,
      subject: 'Tono',
      resolvesThread: true,
      phrasings: [
        DialogueLine("Yeah, I talked to him. We're good."),
        DialogueLine("Yeah, actually — talked to him just the other day."),
      ],
    ),
    PersonalReplyAction(
      'Answer No',
      tone: ReplyTone.honest,
      topics: {Topic.family},
      intent: Intent.statement,
      intensity: 0.3,
      subject: 'Tono',
      resolvesThread: true,
      phrasings: [
        DialogueLine("No, not yet. I've been meaning to call him."),
        DialogueLine("Not yet, honestly. I'll reach out."),
      ],
    ),
    PersonalReplyAction(
      'Explain What Happened',
      tone: ReplyTone.honest,
      topics: {Topic.family},
      intent: Intent.confession,
      intensity: 0.5,
      subject: 'Tono',
      resolvesThread: true,
      phrasings: [
        DialogueLine("Okay — here's what happened. We haven't really talked since we got into it."),
        DialogueLine("I'll tell you what's actually going on between us."),
      ],
    ),
    PersonalReplyAction(
      'Avoid The Question',
      tone: ReplyTone.vague,
      topics: {Topic.family},
      intent: Intent.dismissal,
      intensity: 0.3,
      subject: 'Tono',
      phrasings: [
        DialogueLine("I'd rather not get into that right now."),
        DialogueLine("Can we talk about something else?"),
      ],
    ),
    PersonalReplyAction(
      'Change The Subject',
      tone: ReplyTone.vague,
      topics: {Topic.family},
      intent: Intent.statement,
      intensity: 0.2,
      resolvesThread: true,
      phrasings: [
        DialogueLine("Anyway — how's everything with you lately?"),
        DialogueLine("So, other than that, what's new with you?"),
      ],
    ),
  ],

  // Item 11's own worked example — first link of the "Ask About Uncle"
  // chain. "Ask About Uncle" carries conversationIntent so its own reply
  // comes from the isolated, one-line ConversationIntent.askAboutUncle pool
  // (mama_reactions.dart) rather than the generic Topic.family soup — that
  // reply is what carries the chain's second questionId
  // ('mama_uncle_stubborn', below). The other four chips are leaves: warm/
  // light/redirect responses that close out the moment without continuing
  // the chain further, exactly like any other bespoke tray's non-question chips.
  'mama_uncle_back': [
    PersonalReplyAction(
      'Ask About Uncle',
      tone: ReplyTone.honest,
      topics: {Topic.family},
      intent: Intent.question,
      intensity: 0.3,
      subject: 'uncle',
      resolvesThread: true,
      conversationIntent: ConversationIntent.askAboutUncle,
      phrasings: [
        DialogueLine("What's going on with tío's back?"),
        DialogueLine("Is tío okay? What happened?"),
      ],
    ),
    PersonalReplyAction(
      'Make A Joke About Uncle',
      tone: ReplyTone.warm,
      topics: {Topic.family},
      intent: Intent.statement,
      intensity: 0.3,
      subject: 'uncle',
      resolvesThread: true,
      phrasings: [
        DialogueLine("Tío's back has been 'bad' since before I was born, Mamá."),
        DialogueLine("Tío's back is more dramatic than a telenovela at this point."),
      ],
    ),
    PersonalReplyAction(
      'Ask About Grandma',
      tone: ReplyTone.honest,
      topics: {Topic.family},
      intent: Intent.question,
      intensity: 0.3,
      subject: 'grandma',
      resolvesThread: true,
      phrasings: [
        DialogueLine("How's Abuela doing?"),
        DialogueLine("And Abuela? How's she holding up?"),
      ],
    ),
    PersonalReplyAction(
      "Say You're Glad They're Okay",
      tone: ReplyTone.warm,
      topics: {Topic.family},
      intent: Intent.statement,
      intensity: 0.2,
      subject: 'uncle',
      resolvesThread: true,
      phrasings: [
        DialogueLine("Good, I'm glad everyone's okay."),
        DialogueLine("That's good to hear. Glad it's nothing serious."),
      ],
    ),
    PersonalReplyAction(
      'Change The Subject',
      tone: ReplyTone.vague,
      topics: {Topic.family},
      intent: Intent.statement,
      intensity: 0.2,
      resolvesThread: true,
      phrasings: [
        DialogueLine("Anyway — how are you doing?"),
        DialogueLine("So, what's new with you, Mamá?"),
      ],
    ),
  ],

  // Second link of the chain — reached only from 'mama_uncle_back''s "Ask
  // About Uncle." "Ask How Mama Is Doing" deliberately carries NO
  // conversationIntent of its own: its reply is
  // ConversationIntent.askIfMamaIsOkay's single line, which carries
  // questionId: 'mama_wellbeing_checkin' — converging the chain back into
  // an EXISTING bespoke tray instead of opening yet another new leaf.
  'mama_uncle_stubborn': [
    PersonalReplyAction(
      'Tell Her He Should Rest',
      tone: ReplyTone.honest,
      topics: {Topic.family},
      intent: Intent.statement,
      intensity: 0.3,
      subject: 'uncle',
      resolvesThread: true,
      phrasings: [
        DialogueLine("Somebody needs to make him actually rest for once."),
        DialogueLine("He should really just rest instead of pushing through it."),
      ],
    ),
    PersonalReplyAction(
      'Joke About His Stubbornness',
      tone: ReplyTone.warm,
      topics: {Topic.family},
      intent: Intent.statement,
      intensity: 0.3,
      subject: 'uncle',
      resolvesThread: true,
      phrasings: [
        DialogueLine("Stubborn? Tío? Never."),
        DialogueLine("Wonder where he gets THAT from."),
      ],
    ),
    PersonalReplyAction(
      "Ask If He's Seeing A Doctor",
      tone: ReplyTone.honest,
      topics: {Topic.family},
      intent: Intent.question,
      intensity: 0.3,
      subject: 'uncle',
      resolvesThread: true,
      phrasings: [
        DialogueLine("Has he actually gone to see a doctor about it?"),
        DialogueLine("Is he even getting it looked at?"),
      ],
    ),
    PersonalReplyAction(
      'Ask How Mama Is Doing',
      tone: ReplyTone.warm,
      topics: {Topic.wellbeing},
      intent: Intent.question,
      intensity: 0.3,
      resolvesThread: true,
      conversationIntent: ConversationIntent.askIfMamaIsOkay,
      phrasings: [
        DialogueLine("Enough about tío — how are YOU doing, Mamá?"),
        DialogueLine("Never mind him for a second. How are you holding up?"),
      ],
    ),
  ],
};
