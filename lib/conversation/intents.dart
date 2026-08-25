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
  /// The chip's button text. An [IntentChip] returns its short label
  /// ("Check-In"); a [StoryChipOption] returns the full resolved sentence,
  /// same as before intent chips existed — a story chip already names a
  /// specific thing, so it doesn't need the same is-this-what-I-mean cover.
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
  /// and the sentence itself; [action.resolveText] still supplies the real
  /// wording, just for the thread message once tapped, not the button.
  @override
  String displayLabel(RelationshipState rel, TimeOfDay tod) => '(${action.label})';

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
    // Most of these stay untagged/topic-agnostic on purpose — this chip has
    // to fit whatever the live thread is actually about, not one specific
    // subject. But untagged-only meant tapping it while the thread was on a
    // real subject (e.g. Topic.plans right after "Started something new,
    // still figuring it out.") sent a content-free placeholder instead of
    // anything that actually addressed what was asked. The topic-tagged
    // lines below fix that: topicMatch() gives a matching-topic line a 16x
    // weight boost over the untagged ones, so pickLine() favors them
    // whenever the thread is actually on that subject, while the untagged
    // lines remain the fallback for topics with no specific line yet.
    phrasings: [
      DialogueLine('Let me explain.', tone: ReplyTone.honest),
      DialogueLine("It's kind of a long story, but okay.", tone: ReplyTone.honest),
      DialogueLine("Here's the thing —", tone: ReplyTone.honest),
      DialogueLine("Alright, I'll tell you more about it.", tone: ReplyTone.warm),
      DialogueLine('Honestly, there\'s more to it than that.', tone: ReplyTone.honest),
      DialogueLine("I don't really want to get into it right now.", tone: ReplyTone.vague),
      // Topic.plans — the "new job"/vague-plans follow-up.
      DialogueLine("It's mostly driving and running errands for now. Still getting the hang of it.", tone: ReplyTone.vague, topic: Topic.plans),
      DialogueLine("Nothing's really set in stone yet — still figuring out the details myself.", tone: ReplyTone.vague, topic: Topic.plans),
      DialogueLine("It pays better than the last thing. That's really all I can say right now.", tone: ReplyTone.honest, topic: Topic.plans),
      // Topic.wellbeing — "you okay?" follow-ups that were left vague.
      DialogueLine("I'm managing, Mamá. Just a lot going on that I can't fully get into.", tone: ReplyTone.vague, topic: Topic.wellbeing),
      DialogueLine("Some days are harder than others, but I'm handling it.", tone: ReplyTone.honest, topic: Topic.wellbeing),
      // Topic.suspicion — when she's pushing on something that felt off.
      DialogueLine("It's nothing you need to worry about, I promise.", tone: ReplyTone.vague, topic: Topic.suspicion),
      DialogueLine("I know how it looks. It's not as bad as you're imagining.", tone: ReplyTone.honest, topic: Topic.suspicion),
      // Topic.money — follow-ups on a money comment that was left hanging.
      DialogueLine("Money's actually been a little better lately. That's the short version.", tone: ReplyTone.honest, topic: Topic.money),
      DialogueLine("I'd rather not get into the specifics, but it's under control.", tone: ReplyTone.vague, topic: Topic.money),
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
    phrasings: [
      DialogueLine('Morning, Mama.', tone: ReplyTone.warm, topic: Topic.greeting, timesOfDay: {TimeOfDay.morning}),
      DialogueLine('Hey Mama.', tone: ReplyTone.warm, topic: Topic.greeting),
      DialogueLine('There you are.', tone: ReplyTone.warm, topic: Topic.greeting),
      DialogueLine('Hey, you.', tone: ReplyTone.warm, topic: Topic.greeting),
      DialogueLine("How you doing?", tone: ReplyTone.honest, topic: Topic.wellbeing, intent: Intent.question),
      DialogueLine("What's good?", tone: ReplyTone.vague, topic: Topic.greeting),
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
    phrasings: [
      DialogueLine('Just checking in. You good?', intent: Intent.question),
      DialogueLine('How are you holding up?', intent: Intent.question),
      DialogueLine('Thinking about you today.', tone: ReplyTone.warm),
      DialogueLine('You good over there?', intent: Intent.question),
      DialogueLine('Checking in on you, Mamá.', tone: ReplyTone.warm),
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
