// Mama-specific reaction pools keyed by [ConversationIntent], layered on top
// of — never replacing — the generic per-tone pools in data.dart's
// kPersonalReactions['mama']. See CareerController.personalReplyAction: when
// the player's action carries a ConversationIntent and this map has entries
// for (intent, tone), those entries are used INSTEAD of the generic tone
// pool for that turn, the same override-tier pattern spamReactions and
// dailyRepeatReactions already use. Falls back to the generic 400+ line pool
// automatically whenever an intent has no entry for the tone actually
// picked, so a thin intent bucket never dead-ends pickLine.
//
// Every bucket branches by mood/trust/closeness/suspicion so the SAME
// (intent, tone) — e.g. (greet, warm) — reads differently depending on how
// things stand between them right now: a cheerful greeting lands warm when
// she's warm on you and clipped when she isn't, independent of which tone
// the player's own phrasing carried. That's what makes "even harmless
// intents can get an irritated response" possible without a special case.
import '../dialogue_engine.dart';

const Map<ConversationIntent, Map<ReplyTone, List<DialogueLine>>> kMamaIntentReactions = {
  ConversationIntent.greet: {
    ReplyTone.warm: [
      DialogueLine('Morning, baby. You finally decided to show your face.', weight: 1.5, closenessMin: 60, timesOfDay: {TimeOfDay.morning}),
      DialogueLine('There he is. I was starting to think you finally learned how to behave.', weight: 1.5, closenessMin: 60, moodMin: 10),
      DialogueLine('Ay, mijo! Perfect timing, I was just thinking about you.', weight: 1.3, closenessMin: 40),
      DialogueLine("Hey you. Don't be a stranger, okay?", weight: 1.2),
      DialogueLine("Oh, so you do know my number.", weight: 1.0, tone: ReplyTone.honest, trustMax: 60, closenessMax: 55),
      DialogueLine("You don't usually check in this early. What's going on?", weight: 1.4, suspicionMin: 45),
      DialogueLine('What do you want?', weight: 1.6, moodMax: -25, trustMax: 35),
      DialogueLine("Look who remembered he has a mother.", weight: 1.2, moodMax: -5, moodMin: -30),
    ],
    ReplyTone.vague: [
      DialogueLine("Hey. What's this about?", weight: 1.2, suspicionMin: 40),
      DialogueLine('Hi, mijo. Everything okay?', weight: 1.0),
      DialogueLine("Yeah. Hi.", weight: 1.5, moodMax: -20),
    ],
    ReplyTone.cold: [
      DialogueLine('Yeah. Hi. What do you need?', weight: 1.6, moodMax: -15),
      DialogueLine("Oh, now you say hi.", weight: 1.3, trustMax: 30),
    ],
  },

  ConversationIntent.checkIn: {
    ReplyTone.warm: [
      DialogueLine("I'm alright. Better now that you're asking.", weight: 1.3, closenessMin: 45),
      DialogueLine("Boy, don't make me come find you myself — I'm fine, just worried about YOU.", weight: 1.4, closenessMin: 65),
      DialogueLine("I'm okay, mijo. Tired, but okay. You checking on me first is a nice change.", weight: 1.2, moodMin: -10, moodMax: 30),
      DialogueLine("You know I'm always alright as long as I know you are.", weight: 1.1),
      // Recall demonstration: only eligible/boosted when the player asked
      // about family recently enough to still be worth referencing back.
      DialogueLine(
        "I'm alright. Better now that you're asking. And don't worry — your sister's fine, since you asked.",
        weight: 2.5,
        requiresRecentIntent: ConversationIntent.askAboutFamily,
        recallWithinTurns: 6,
      ),
      // Phase demonstration: only surfaces right after a major story beat or
      // late in a level, when there's actually something to be quiet about.
      DialogueLine(
        "You've been quiet about what's really going on. Should I be worried?",
        weight: 4.0, // dominant once eligible — a beat this specific to the moment shouldn't get lost among routine chatter
        phases: {LevelPhase.cusp, LevelPhase.late},
        suspicionMin: 25,
      ),
    ],
    ReplyTone.honest: [
      DialogueLine("Honestly? Been a long week. But I'm managing.", weight: 1.2),
      DialogueLine("Not gonna lie, mijo, I've been worried about you. Glad you asked.", weight: 1.3, suspicionMin: 30),
      DialogueLine("I'm fine. Are YOU fine? Because you don't check in like this for no reason.", weight: 1.5, suspicionMin: 50),
    ],
    ReplyTone.vague: [
      DialogueLine("I'm around. You know how it is.", weight: 1.1),
      DialogueLine("Fine, I guess. Same as always.", weight: 1.2, moodMax: 0),
    ],
    ReplyTone.cold: [
      DialogueLine("Since when do you check in on me?", weight: 1.4, trustMax: 30),
      DialogueLine("I'm fine. Was there something else?", weight: 1.3, moodMax: -20),
    ],
  },

  ConversationIntent.askAboutFamily: {
    ReplyTone.warm: [
      DialogueLine('Your sister asks about you every week, you know.', weight: 1.3, topic: Topic.family),
      DialogueLine("Family's good, mijo. Your tío finally fixed that truck of his.", weight: 1.1, topic: Topic.family),
      DialogueLine("Everyone's fine. Everyone misses you, but everyone's fine.", weight: 1.4, topic: Topic.family, closenessMin: 40),
      DialogueLine("You asking about the family? That's my boy.", weight: 1.2, topic: Topic.family, closenessMin: 55),
    ],
    ReplyTone.honest: [
      DialogueLine("Things are okay. Money's tight for your tía but we're managing.", weight: 1.3, topic: Topic.family),
      DialogueLine("I won't lie to you — everyone's worried about you, not the other way around.", weight: 1.2, topic: Topic.family, suspicionMin: 35),
    ],
    ReplyTone.vague: [
      DialogueLine("Everyone's the same. Nothing new to report.", weight: 1.1, topic: Topic.family),
    ],
    ReplyTone.cold: [
      DialogueLine("Why do you care all of a sudden?", weight: 1.3, topic: Topic.family, trustMax: 30),
    ],
  },

  ConversationIntent.insult: {
    ReplyTone.warm: [
      DialogueLine("Oh, you got jokes now? Watch it, mijo.", weight: 1.5, closenessMin: 60, moodMin: 0),
      DialogueLine("Excuse me? I made you. I can unmake you.", weight: 1.4, closenessMin: 65, moodMin: 10),
      DialogueLine("Keep talking. See what happens when I see you next.", weight: 1.2, closenessMin: 55),
      DialogueLine("You're lucky you're cute. That's the only thing saving you right now.", weight: 1.1, closenessMin: 70, moodMin: 15),
    ],
    ReplyTone.vague: [
      DialogueLine("Wow. Okay. I see how it is.", weight: 1.3, closenessMax: 55),
      DialogueLine("Cute. Real cute.", weight: 1.1, closenessMin: 40, moodMin: -10),
    ],
    ReplyTone.cold: [
      DialogueLine("That's not funny.", weight: 1.4, closenessMax: 50, moodMax: 10),
      DialogueLine("You really enjoy talking reckless to your mother, don't you?", weight: 1.6, trustMax: 40),
      DialogueLine("I raised you better than that.", weight: 1.5, moodMax: -10),
      DialogueLine("Okay. That one actually hurt.", weight: 1.3, moodMax: -25, closenessMax: 45),
    ],
  },

  ConversationIntent.joke: {
    ReplyTone.warm: [
      DialogueLine("Ay, you're too much, mijo. Too much.", weight: 1.4, closenessMin: 45, moodMin: 0),
      DialogueLine("I'm putting that one in my collection. You're funnier than your father, don't tell him.", weight: 1.3, closenessMin: 55, moodMin: 10),
      DialogueLine("Okay THAT one made me laugh out loud. I mean it.", weight: 1.2),
      DialogueLine("You get that sense of humor from me, you know.", weight: 1.0, closenessMin: 50),
    ],
    ReplyTone.vague: [
      DialogueLine("Ha. Okay.", weight: 1.3, moodMax: 0),
      DialogueLine("You're something else, mijo.", weight: 1.1),
    ],
    ReplyTone.cold: [
      DialogueLine("Not really in the mood for jokes right now, mijo.", weight: 1.5, moodMax: -20),
      DialogueLine("Hilarious. Truly.", weight: 1.2, moodMax: -10, trustMax: 40),
    ],
  },

  ConversationIntent.apologize: {
    ReplyTone.warm: [
      DialogueLine("Oh, mijo. Come here. I forgive you, I always do.", weight: 1.4, closenessMin: 50, moodMax: 20),
      DialogueLine("That's all I needed to hear. Thank you for saying it.", weight: 1.3, trustMin: 40),
      DialogueLine("I appreciate you saying sorry. That's not nothing.", weight: 1.2),
    ],
    ReplyTone.honest: [
      DialogueLine("I hear you. It still stung, but I hear you.", weight: 1.3, moodMax: 0),
      DialogueLine("Thank you. I mean that. It's been sitting heavy on me.", weight: 1.2, moodMax: -10),
    ],
    ReplyTone.vague: [
      DialogueLine("Okay. Noted.", weight: 1.1, trustMax: 40),
    ],
    ReplyTone.cold: [
      DialogueLine("That's what you're telling me now?", weight: 1.5, trustMax: 30),
      DialogueLine("Sorry doesn't fix everything, mijo.", weight: 1.4, moodMax: -25),
    ],
  },

  ConversationIntent.elaborate: {
    ReplyTone.honest: [
      DialogueLine("Okay. I'm listening, mijo.", weight: 1.4),
      DialogueLine("Take your time. I'm not going anywhere.", weight: 1.3, closenessMin: 45),
      DialogueLine("That's more like it. Go on.", weight: 1.3, suspicionMin: 30),
      DialogueLine("Mmhm. Keep going.", weight: 1.1),
      DialogueLine("Finally. Okay, I'm all ears.", weight: 1.2, suspicionMin: 45, trustMax: 50),
      // Topic.plans — a real (if partial) answer about the vague "new job",
      // as opposed to the generic listening lines above which say nothing
      // about what was actually explained.
      DialogueLine("Driving and errands, huh? Just be careful out there, mijo.", weight: 2.0, topic: Topic.plans),
      DialogueLine("As long as it pays honest, I don't care what it is.", weight: 1.8, topic: Topic.plans),
      DialogueLine("Better pay is good. Just don't let it change who you are.", weight: 1.8, topic: Topic.plans),
      DialogueLine("Okay. That's more than you were giving me before, at least.", weight: 1.6, topic: Topic.plans),
    ],
    ReplyTone.warm: [
      DialogueLine("There you go. That's all I wanted, mijo.", weight: 1.4, closenessMin: 50),
      DialogueLine("See? Wasn't so hard, was it?", weight: 1.2, closenessMin: 55, moodMin: 0),
      DialogueLine("I love when you actually talk to me.", weight: 1.3, closenessMin: 60),
      DialogueLine("Look at you, moving forward. I'm proud of you, mijo.", weight: 1.8, topic: Topic.plans),
      DialogueLine("A new start is a good thing. I just want you safe in it.", weight: 1.6, topic: Topic.plans),
    ],
    ReplyTone.vague: [
      DialogueLine("Fine. But I'm not going to stop asking.", weight: 1.4, suspicionMin: 30),
      DialogueLine("Okay... if that's how it's gonna be.", weight: 1.3, moodMax: 10),
      DialogueLine("Mijo. You know that just makes me worry more, right?", weight: 1.5, suspicionMin: 45, trustMax: 55),
      DialogueLine("Alright, alright. I'll drop it. For now.", weight: 1.1, closenessMin: 40),
      // Topic.plans — reacting to "still figuring it out"/no-real-details
      // specifically, instead of a generic non-answer callout.
      DialogueLine("'Still figuring it out' — that's what worries me, mijo.", weight: 2.0, topic: Topic.plans),
      DialogueLine("Okay. I don't love how vague that sounds, but okay.", weight: 1.8, topic: Topic.plans),
      DialogueLine("New job, no details. Sounds about right for you lately.", weight: 1.6, topic: Topic.plans, moodMax: 0),
    ],
  },
};

// ── Chip tone hints ─────────────────────────────────────────────────────
// Short words shown on an intent chip (e.g. "(Insult · playful)") so the
// player has *some* read on how a loaded intent will land before tapping it,
// without the chip literally being the sentence. Each function's thresholds
// mirror the mood/trust/closeness gates on the pool above it, so the hint
// never promises a register the reaction pool wouldn't actually pick. Take
// plain doubles rather than RelationshipState so this file stays as
// dependency-light as dialogue_engine.dart itself — conversation/intents.dart
// adapts a RelationshipState into these at the call site.

String mamaGreetFlavor({required double mood, required double trust, required double closeness, required double suspicion}) {
  if (suspicion >= 45) return 'wary';
  if (mood <= -25 && trust <= 35) return 'cold';
  if (mood <= -5) return 'clipped';
  if (closeness >= 60) return 'warm';
  return 'easy';
}

String mamaCheckInFlavor({required double mood, required double trust, required double closeness, required double suspicion}) {
  if (trust <= 30 && mood <= -20) return 'guarded';
  if (suspicion >= 50) return 'searching';
  if (closeness >= 65) return 'affectionate';
  if (mood >= -10 && mood <= 30) return 'grateful';
  return 'even';
}

String mamaFamilyFlavor({required double mood, required double trust, required double closeness, required double suspicion}) {
  if (trust <= 30) return 'suspicious';
  if (closeness >= 55) return 'warm';
  if (suspicion >= 35) return 'pointed';
  return 'plain';
}

String mamaInsultFlavor({required double mood, required double trust, required double closeness, required double suspicion}) {
  if (closeness >= 60 && mood >= 0) return 'playful';
  if (trust <= 40) return 'wounded';
  if (mood <= -10 && closeness <= 50) return 'serious';
  return 'sarcastic';
}

String mamaJokeFlavor({required double mood, required double trust, required double closeness, required double suspicion}) {
  if (mood <= -20) return 'flat';
  if (mood <= -10 && trust <= 40) return 'humorless';
  if (closeness >= 55 && mood >= 10) return 'delighted';
  return 'amused';
}

String mamaApologizeFlavor({required double mood, required double trust, required double closeness, required double suspicion}) {
  if (trust <= 30) return 'skeptical';
  if (mood <= -25) return 'still hurt';
  if (mood <= 0) return 'hearing you out';
  if (closeness >= 50) return 'forgiving';
  return 'gracious';
}
