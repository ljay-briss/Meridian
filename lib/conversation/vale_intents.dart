// Vale's intent-chip catalog — the partner's equivalent of intents.dart's
// kIntentChips. Same 21 [ConversationIntent] verbs (asking for advice means
// the same thing regardless of who you're texting) but every phrasing here
// is written for a romantic partner, not a parent — no "Mamá" references,
// and the family/duty register Mama's chips lean on is replaced with the
// couple-specific one (jealousy, exclusivity, reassurance) that matches
// Vale's suspicionRate: 1.4 / emotionalVolatility: 0.7 in kPersonalContacts.
import 'intents.dart';
import '../content/vale_reactions.dart';
import '../data.dart';

// Named top-level adapters, not lambdas — a lambda literal isn't a constant
// expression in Dart, and kValeIntentChips (below) is a const list, so each
// chip's toneHint has to be a plain function reference (same pattern as
// intents.dart's _greetHint etc.).
String _valeGreetHint(RelationshipState r) => valeGreetFlavor(mood: r.mood, trust: r.trust, closeness: r.closeness, suspicion: r.suspicion);
String _valeCheckInHint(RelationshipState r) => valeCheckInFlavor(mood: r.mood, trust: r.trust, closeness: r.closeness, suspicion: r.suspicion);
String _valeInsultHint(RelationshipState r) => valeInsultFlavor(mood: r.mood, trust: r.trust, closeness: r.closeness, suspicion: r.suspicion);
String _valeConfrontHint(RelationshipState r) => valeConfrontFlavor(mood: r.mood, trust: r.trust, closeness: r.closeness, suspicion: r.suspicion);

const List<IntentChip> kValeIntentChips = [
  // ── Continuation (always available) ───────────────────────────────────
  IntentChip(
    intent: ConversationIntent.elaborate,
    label: 'Explain More',
    primaryTone: ReplyTone.honest,
    primaryTopics: {},
    primaryIntent: Intent.statement,
    intensity: 0.4,
    phrasings: [
      DialogueLine('Let me explain.', tone: ReplyTone.honest),
      DialogueLine("It's kind of a long story, but okay.", tone: ReplyTone.honest),
      DialogueLine("Here's the thing —", tone: ReplyTone.honest),
      DialogueLine("Okay, I'll actually tell you what's going on.", tone: ReplyTone.warm),
      DialogueLine("I don't really want to get into it right now.", tone: ReplyTone.vague),
      // Topic.suspicion — the jealousy-defusing follow-up, central to Vale.
      DialogueLine("It's not what it looks like, I swear.", tone: ReplyTone.honest, topic: Topic.suspicion),
      DialogueLine("You're spiraling over nothing, I promise.", tone: ReplyTone.vague, topic: Topic.suspicion),
      DialogueLine("Okay, fine — here's exactly what happened.", tone: ReplyTone.honest, topic: Topic.suspicion),
      // Topic.plans
      DialogueLine("It's mostly driving and running errands for now.", tone: ReplyTone.vague, topic: Topic.plans),
      DialogueLine("Pays better than the last thing. That's really all I can say.", tone: ReplyTone.honest, topic: Topic.plans),
      // Topic.money
      DialogueLine("Money's actually been a little better lately.", tone: ReplyTone.honest, topic: Topic.money),
      DialogueLine("I'd rather not get into the specifics, it's under control.", tone: ReplyTone.vague, topic: Topic.money),
      // Topic.affection
      DialogueLine("I don't say it enough, but I'm crazy about you.", tone: ReplyTone.warm, topic: Topic.affection),
      DialogueLine("It's hard to put into words, but you're it for me.", tone: ReplyTone.warm, topic: Topic.affection),
      // Topic.wellbeing
      DialogueLine("I'm managing, just a lot going on I can't fully get into.", tone: ReplyTone.vague, topic: Topic.wellbeing),
      DialogueLine("Some days are harder than others, but I'm okay.", tone: ReplyTone.honest, topic: Topic.wellbeing),
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
    toneHint: _valeGreetHint,
    phrasings: [
      DialogueLine('Morning, beautiful.', tone: ReplyTone.warm, topic: Topic.greeting, timesOfDay: {TimeOfDay.morning}),
      DialogueLine('Hey you.', tone: ReplyTone.warm, topic: Topic.greeting),
      DialogueLine("Thinking about you.", tone: ReplyTone.warm, topic: Topic.greeting),
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
    toneHint: _valeCheckInHint,
    phrasings: [
      DialogueLine('Just checking in. You good?', intent: Intent.question),
      DialogueLine('How are you holding up?', intent: Intent.question),
      DialogueLine('Thinking about you today.', tone: ReplyTone.warm),
      DialogueLine('You good over there?', intent: Intent.question),
    ],
  ),
  IntentChip(
    intent: ConversationIntent.askAboutFamily,
    label: 'Ask About Family',
    primaryTone: ReplyTone.honest,
    primaryTopics: {Topic.family},
    primaryIntent: Intent.question,
    intensity: 0.3,
    phrasings: [
      DialogueLine("How's your family doing?", intent: Intent.question),
      DialogueLine("Everything good with your parents?", intent: Intent.question),
      DialogueLine('Tell me how everyone at home is doing.', tone: ReplyTone.warm),
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
      DialogueLine('Thank you. For everything.', tone: ReplyTone.warm),
      DialogueLine("I don't say it enough, but thank you.", tone: ReplyTone.warm),
      DialogueLine('Really, thank you for putting up with me lately.', tone: ReplyTone.warm),
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
      DialogueLine("You're stunning, you know that?", tone: ReplyTone.warm),
      DialogueLine("Don't know what I'd do without you.", tone: ReplyTone.warm),
      DialogueLine("Not gonna lie, you're kind of amazing.", tone: ReplyTone.warm),
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
    phrasings: [
      DialogueLine("I'm sorry.", tone: ReplyTone.warm, intent: Intent.promise),
      DialogueLine("I know I've been distant. I'm sorry.", tone: ReplyTone.honest, intent: Intent.promise),
      DialogueLine('That was on me. I\'m sorry.', tone: ReplyTone.honest, intent: Intent.promise),
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
      DialogueLine('Gotta go. Love you.', tone: ReplyTone.warm),
      DialogueLine("I'll call you later, okay?", tone: ReplyTone.warm),
      DialogueLine('Talk soon.', tone: ReplyTone.vague),
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
      DialogueLine('Have you talked to your mom lately?', intent: Intent.question, topic: Topic.family),
      DialogueLine("How's your best friend doing?", intent: Intent.question),
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
      DialogueLine('I need a favor.', intent: Intent.question),
      DialogueLine('Could you help me with something?', intent: Intent.question),
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
    phrasings: [
      DialogueLine('Okay but hear me out—', tone: ReplyTone.warm),
      DialogueLine("You're gonna laugh at this one.", tone: ReplyTone.warm),
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
    toneHint: _valeInsultHint,
    phrasings: [
      DialogueLine("You're impossible, you know that?", tone: ReplyTone.warm),
      DialogueLine('Okay, you\'re a little annoying sometimes.', tone: ReplyTone.vague),
      DialogueLine('Honestly? You can be a lot.', tone: ReplyTone.cold),
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
    toneHint: _valeConfrontHint,
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
      DialogueLine('Are you even still into this?', tone: ReplyTone.cold, topic: Topic.suspicion),
      DialogueLine('Do you actually trust me, or not?', tone: ReplyTone.honest, topic: Topic.suspicion, intent: Intent.question),
      DialogueLine('Sometimes I wonder if you even want this anymore.', tone: ReplyTone.vague, topic: Topic.suspicion),
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
      DialogueLine("You don't need to worry about me.", tone: ReplyTone.warm),
      DialogueLine("I'm not going anywhere. I promise.", tone: ReplyTone.warm, intent: Intent.promise),
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
      DialogueLine("That's huge. Congrats.", tone: ReplyTone.warm),
    ],
  ),
];
