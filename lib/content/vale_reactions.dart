// Vale-specific reaction pools keyed by [ConversationIntent] — the partner's
// equivalent of content/mama_reactions.dart's kMamaIntentReactions. Same
// override-tier contract: CareerController.personalReplyAction uses these
// INSTEAD of the generic kPersonalReactions['partner'] tone pool whenever an
// entry exists for (intent, tone), and falls back to that generic pool
// automatically whenever it doesn't.
//
// Vale's register, distinct from Mama's: a partner, not a parent — jealousy
// and reassurance carry the emotional weight here the way family/duty do for
// Mama (see her suspicionRate: 1.4 and emotionalVolatility: 0.7 in
// kPersonalContacts, both the highest of any personal contact — she reads
// into things fast and swings hard once she does). Texting register is
// modern-casual (lowercase asides, "ngl"/"lol"), lighter than Kiko's
// full-slang voice but well past Mama's formality.
import '../dialogue_engine.dart';

const Map<ConversationIntent, Map<ReplyTone, List<DialogueLine>>> kValeIntentReactions = {
  ConversationIntent.greet: {
    ReplyTone.warm: [
      DialogueLine('Hey you.', weight: 1.4),
      DialogueLine("There's my favorite text of the day.", weight: 1.5, closenessMin: 55),
      DialogueLine('omg hi, I was just thinking about you', weight: 1.3, closenessMin: 40, moodMin: 0),
      DialogueLine("Miss me?", weight: 1.1, closenessMin: 50),
    ],
    ReplyTone.vague: [
      DialogueLine('hey', weight: 1.2),
      DialogueLine("oh. hi.", weight: 1.4, moodMax: -10),
      DialogueLine('hi, everything ok?', weight: 1.1, suspicionMin: 30),
    ],
    ReplyTone.cold: [
      DialogueLine('hi.', weight: 1.0),
      DialogueLine("oh now you text me.", weight: 1.4, trustMax: 35),
      DialogueLine('yeah hey. what do you need.', weight: 1.3, moodMax: -20),
    ],
  },

  ConversationIntent.checkIn: {
    ReplyTone.warm: [
      DialogueLine("I'm good, better now.", weight: 1.3, closenessMin: 40),
      DialogueLine("aw, you checking on me first for once? I could get used to that.", weight: 1.4, closenessMin: 55),
      DialogueLine("I'm okay. Just wish you did this more.", weight: 1.1),
    ],
    ReplyTone.honest: [
      DialogueLine("Honestly kind of a long week. But I'm okay.", weight: 1.2),
      DialogueLine("Ngl I've been a little in my head. Glad you asked.", weight: 1.3, suspicionMin: 25),
    ],
    ReplyTone.vague: [
      DialogueLine("I'm around.", weight: 1.1),
      DialogueLine("fine ig", weight: 1.2, moodMax: 0),
    ],
    ReplyTone.cold: [
      DialogueLine("I'm fine.", weight: 1.0),
      DialogueLine("Since when do you check on me.", weight: 1.4, trustMax: 30),
      DialogueLine("I'm fine. Was that all.", weight: 1.3, moodMax: -20),
    ],
  },

  ConversationIntent.askAboutFamily: {
    ReplyTone.warm: [
      DialogueLine("They're good. My mom asked about you again, actually.", weight: 1.3, topic: Topic.family),
      DialogueLine("Everyone's fine. It's sweet you asked.", weight: 1.4, topic: Topic.family, closenessMin: 40),
    ],
    ReplyTone.honest: [
      DialogueLine("Things are okay. A little stressful with my dad, but okay.", weight: 1.3, topic: Topic.family),
    ],
    ReplyTone.vague: [
      DialogueLine("Same as always. Nothing new.", weight: 1.1, topic: Topic.family),
    ],
    ReplyTone.cold: [
      DialogueLine("They're fine. Why.", weight: 1.0, topic: Topic.family),
      DialogueLine("Why the sudden interest in my family.", weight: 1.3, topic: Topic.family, trustMax: 30),
    ],
  },

  ConversationIntent.thank: {
    ReplyTone.warm: [
      DialogueLine("You don't have to thank me, that's what I'm here for.", weight: 1.4),
      DialogueLine("Stop, you're gonna make me all soft.", weight: 1.3, closenessMin: 45),
      DialogueLine("Okay that's actually really sweet. Thank YOU.", weight: 1.2),
    ],
  },

  ConversationIntent.compliment: {
    ReplyTone.warm: [
      DialogueLine("Stop it. ...don't actually stop it.", weight: 1.3),
      DialogueLine("You always know exactly what to say to me.", weight: 1.2, closenessMin: 50),
    ],
    ReplyTone.honest: [
      DialogueLine("You're just saying that because you want something, right?", weight: 1.3, trustMax: 55),
      DialogueLine("I needed that today, actually. Thank you.", weight: 1.2),
    ],
  },

  ConversationIntent.apologize: {
    ReplyTone.warm: [
      DialogueLine("Okay. Thank you for saying that.", weight: 1.0),
      DialogueLine("Okay. Come here. I forgive you.", weight: 1.4, closenessMin: 45, moodMax: 20),
      DialogueLine("That's all I needed to hear, honestly.", weight: 1.3, trustMin: 40),
    ],
    ReplyTone.honest: [
      DialogueLine("I hear you. It still hurt, but I hear you.", weight: 1.3, moodMax: 0),
      DialogueLine("Thank you for actually saying it instead of just moving on.", weight: 1.2),
    ],
    ReplyTone.vague: [
      DialogueLine("Okay.", weight: 1.0),
    ],
    ReplyTone.cold: [
      DialogueLine("We'll see.", weight: 1.0),
      DialogueLine("That's what you're telling me now?", weight: 1.5, trustMax: 30),
      DialogueLine("Sorry doesn't undo how the last few days felt.", weight: 1.4, moodMax: -25),
    ],
  },

  ConversationIntent.sayGoodbye: {
    ReplyTone.warm: [
      DialogueLine("Okay. Love you, be safe.", weight: 1.5),
      DialogueLine("Text me when you're free later?", weight: 1.2, closenessMin: 40),
    ],
    ReplyTone.vague: [
      DialogueLine("ok bye", weight: 1.0),
      DialogueLine("k.", weight: 1.2, moodMax: 0),
      DialogueLine("sure, talk later I guess", weight: 1.3, trustMax: 40),
    ],
  },

  ConversationIntent.askAboutWork: {
    ReplyTone.honest: [
      DialogueLine("It's work. Same as always, honestly.", weight: 1.2),
      DialogueLine("Busy. Tired. But it's fine.", weight: 1.1),
      DialogueLine("Better ask about YOUR work for once.", weight: 1.4, suspicionMin: 25),
    ],
  },

  ConversationIntent.askWhatsGoingOn: {
    ReplyTone.honest: [
      DialogueLine("Nothing much. Why, is something up with you?", weight: 1.2),
      DialogueLine("Honestly? I've been a little off. Glad you asked.", weight: 1.3, suspicionMin: 20),
      DialogueLine("You're asking ME? That's usually my line.", weight: 1.5, suspicionMin: 40),
    ],
  },

  ConversationIntent.askAboutSomeone: {
    ReplyTone.honest: [
      DialogueLine("She's good, actually asked about you last week.", weight: 1.2, topic: Topic.family),
      DialogueLine("They're fine. Why do you ask?", weight: 1.0),
    ],
  },

  ConversationIntent.askForAdvice: {
    ReplyTone.honest: [
      DialogueLine("Of course, what's going on?", weight: 1.4),
      DialogueLine("Okay, I'm listening. Lay it on me.", weight: 1.2, closenessMin: 35),
    ],
  },

  ConversationIntent.askForHelp: {
    ReplyTone.honest: [
      DialogueLine("Tell me what you need.", weight: 1.0),
      DialogueLine("Of course. What's up?", weight: 1.4, closenessMin: 40),
      DialogueLine("Depends what it is. Talk to me first.", weight: 1.2, trustMax: 55),
    ],
  },

  ConversationIntent.joke: {
    ReplyTone.warm: [
      DialogueLine("lol ok that was decent.", weight: 1.0),
      DialogueLine("Okay that was actually funny, I hate that you got me.", weight: 1.4, moodMin: 0),
      DialogueLine("lol stop, I'm supposed to be mad at you rn", weight: 1.2, closenessMin: 45),
    ],
    ReplyTone.vague: [
      DialogueLine("lol ok.", weight: 1.2),
    ],
    ReplyTone.cold: [
      DialogueLine("mm.", weight: 1.0),
      DialogueLine("Not really in the mood for jokes right now.", weight: 1.5, moodMax: -15),
    ],
  },

  ConversationIntent.insult: {
    ReplyTone.warm: [
      DialogueLine("wow ok.", weight: 1.0),
      DialogueLine("Excuse me? Say that to my face.", weight: 1.4, closenessMin: 55, moodMin: 0),
      DialogueLine("Wow, okay. You're lucky you're cute.", weight: 1.2, closenessMin: 60),
    ],
    ReplyTone.vague: [
      DialogueLine("Wow. Ok. Noted.", weight: 1.2),
    ],
    ReplyTone.cold: [
      DialogueLine("Not funny.", weight: 1.0),
      DialogueLine("That's actually not funny to me right now.", weight: 1.4, moodMax: 0),
      DialogueLine("Cool, talk to me like that again and see what happens.", weight: 1.5, trustMax: 40),
    ],
  },

  ConversationIntent.confront: {
    ReplyTone.honest: [
      DialogueLine("Okay. I'm listening. What's going on.", weight: 1.4),
      DialogueLine("Finally. I've been waiting for you to bring this up.", weight: 1.5, suspicionMin: 30, topic: Topic.suspicion),
    ],
    ReplyTone.cold: [
      DialogueLine("Fine. What is it.", weight: 1.0),
      DialogueLine("Oh so NOW you want to talk.", weight: 1.4, moodMax: -10),
      DialogueLine("Okay but I already know I'm not gonna like this.", weight: 1.5, suspicionMin: 40, topic: Topic.suspicion),
    ],
  },

  ConversationIntent.questionLoyalty: {
    ReplyTone.cold: [
      DialogueLine("Are you serious right now.", weight: 1.6, topic: Topic.suspicion),
      DialogueLine("Wow. After everything, you're asking me that?", weight: 1.5, closenessMin: 40),
    ],
    ReplyTone.honest: [
      DialogueLine("I'm here. I've always been here. Why would you even ask that.", weight: 1.6, topic: Topic.suspicion),
    ],
    ReplyTone.vague: [
      DialogueLine("...why would you even ask me that.", weight: 1.3, trustMax: 40),
      DialogueLine("I don't know what you want me to say to that.", weight: 1.1),
    ],
  },

  ConversationIntent.reassure: {
    ReplyTone.warm: [
      DialogueLine("Okay. I believe you. Just don't make me regret it.", weight: 1.4, trustMin: 35),
      DialogueLine("That's all I needed, honestly.", weight: 1.3, closenessMin: 45),
      DialogueLine("I still worry. But okay.", weight: 1.0),
    ],
  },

  ConversationIntent.makePeace: {
    ReplyTone.warm: [
      DialogueLine("Okay. We're okay.", weight: 1.0),
      DialogueLine("Okay. Come here. I don't want to fight either.", weight: 1.5, moodMax: 20),
      DialogueLine("I hate when we're like this. Yes. Okay. We're good.", weight: 1.4, closenessMin: 40),
    ],
    ReplyTone.honest: [
      DialogueLine("Okay. We're okay. But we ARE finishing this conversation later.", weight: 1.3),
    ],
  },

  ConversationIntent.sarcasm: {
    ReplyTone.vague: [
      DialogueLine("wow. hilarious.", weight: 1.2),
      DialogueLine("mm k.", weight: 1.1, moodMax: 10),
    ],
    ReplyTone.cold: [
      DialogueLine("Not in the mood.", weight: 1.0),
      DialogueLine("Cute. Real cute.", weight: 1.3, trustMax: 35),
    ],
  },

  ConversationIntent.congratulate: {
    ReplyTone.warm: [
      DialogueLine("Omg thank you, that actually means a lot.", weight: 1.4),
      DialogueLine("See, this is why I keep you around.", weight: 1.3, closenessMin: 45),
    ],
  },

  ConversationIntent.elaborate: {
    ReplyTone.honest: [
      DialogueLine("Okay. I'm listening.", weight: 1.4),
      DialogueLine("Take your time. I'm not going anywhere.", weight: 1.3, closenessMin: 40),
      DialogueLine("Finally. Go on.", weight: 1.3, suspicionMin: 30),
      // Topic.suspicion — the register that actually matters most for Vale
      // (suspicionRate 1.4, the highest of any contact) — a real answer to a
      // jealousy spiral, not a generic listening line.
      DialogueLine("Okay... I want to believe you.", weight: 2.2, topic: Topic.suspicion),
      DialogueLine("That actually helps. Thank you for telling me.", weight: 1.8, topic: Topic.suspicion, trustMin: 40, acknowledgesAnsweredQuestion: true),
      DialogueLine("I still don't love it, but okay. I hear you.", weight: 1.8, topic: Topic.suspicion, moodMax: 0),
      // Topic.plans
      DialogueLine("Driving and errands, got it. Just be careful out there.", weight: 2.0, topic: Topic.plans),
      // Topic.money
      DialogueLine("Better is good. I was starting to worry a little.", weight: 2.0, topic: Topic.money),
      // Topic.affection
      DialogueLine("...I wasn't expecting that. I feel the same, you know.", weight: 2.0, topic: Topic.affection),
    ],
    ReplyTone.warm: [
      DialogueLine("There you go. That's all I wanted.", weight: 1.4, closenessMin: 45),
      DialogueLine("I love when you actually talk to me instead of shutting down.", weight: 1.3, closenessMin: 55),
      DialogueLine("Okay. I believe you.", weight: 2.0, topic: Topic.suspicion, trustMin: 45),
      DialogueLine("...babe. Now I'm blushing, stop it.", weight: 2.0, topic: Topic.affection),
    ],
    ReplyTone.vague: [
      DialogueLine("Fine. But I'm not letting this go.", weight: 1.4, suspicionMin: 30),
      DialogueLine("Okay... if that's how it's gonna be.", weight: 1.3, moodMax: 10),
      DialogueLine("That's it? That's all I get?", weight: 2.2, topic: Topic.suspicion, suspicionMin: 20),
      DialogueLine("You're really not gonna tell me the whole thing, huh.", weight: 1.8, topic: Topic.suspicion),
      DialogueLine("Vague as always. Cool.", weight: 1.6, topic: Topic.plans),
    ],
    ReplyTone.cold: [
      DialogueLine("Wow. Okay.", weight: 1.0),
      DialogueLine("Save it.", weight: 1.3, trustMax: 35),
      DialogueLine("That's not an answer and you know it.", weight: 2.0, topic: Topic.suspicion, suspicionMin: 40),
    ],
  },
};

// ── Chip tone hints ─────────────────────────────────────────────────────
// Same purpose as mama_reactions.dart's — a short parenthetical read on how
// a loaded chip will land, thresholds mirrored from the pool above.

String valeGreetFlavor({required double mood, required double trust, required double closeness, required double suspicion}) {
  if (trust <= 35 && mood <= -20) return 'cold';
  if (suspicion >= 30) return 'wary';
  if (closeness >= 55) return 'warm';
  return 'easy';
}

String valeCheckInFlavor({required double mood, required double trust, required double closeness, required double suspicion}) {
  if (trust <= 30 && mood <= -20) return 'guarded';
  if (suspicion >= 40) return 'searching';
  if (closeness >= 55) return 'affectionate';
  return 'even';
}

String valeInsultFlavor({required double mood, required double trust, required double closeness, required double suspicion}) {
  if (closeness >= 55 && mood >= 0) return 'playful';
  if (mood <= -10) return 'serious';
  return 'sarcastic';
}

String valeConfrontFlavor({required double mood, required double trust, required double closeness, required double suspicion}) {
  if (suspicion >= 40) return 'tense';
  if (trust <= 40) return 'guarded';
  return 'direct';
}
