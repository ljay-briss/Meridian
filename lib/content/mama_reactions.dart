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
      DialogueLine('Hi.', weight: 1.0),
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
      DialogueLine("I'm fine.", weight: 1.0),
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
      DialogueLine("I don't feel like talking about the family right now.", weight: 1.0, topic: Topic.family),
      DialogueLine("Why do you care all of a sudden?", weight: 1.3, topic: Topic.family, trustMax: 30),
    ],
  },

  ConversationIntent.insult: {
    ReplyTone.warm: [
      DialogueLine('Ha. Okay, tough guy.', weight: 1.0),
      DialogueLine("Oh, you got jokes now? Watch it, mijo.", weight: 1.5, closenessMin: 60, moodMin: 0),
      DialogueLine("Excuse me? I made you. I can unmake you.", weight: 1.4, closenessMin: 65, moodMin: 10),
      DialogueLine("Keep talking. See what happens when I see you next.", weight: 1.2, closenessMin: 55),
      DialogueLine("You're lucky you're cute. That's the only thing saving you right now.", weight: 1.1, closenessMin: 70, moodMin: 15),
    ],
    ReplyTone.vague: [
      DialogueLine('Okay, mijo.', weight: 1.0),
      DialogueLine("Wow. Okay. I see how it is.", weight: 1.3, closenessMax: 55),
      DialogueLine("Cute. Real cute.", weight: 1.1, closenessMin: 40, moodMin: -10),
    ],
    ReplyTone.cold: [
      DialogueLine('Excuse me?', weight: 1.0),
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
      DialogueLine('Mm.', weight: 1.0),
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
      DialogueLine('Okay. Thank you for saying that.', weight: 1.0),
      DialogueLine("I hear you. It still stung, but I hear you.", weight: 1.3, moodMax: 0),
      DialogueLine("Thank you. I mean that. It's been sitting heavy on me.", weight: 1.2, moodMax: -10),
    ],
    ReplyTone.vague: [
      DialogueLine('Okay.', weight: 1.0),
      DialogueLine("Okay. Noted.", weight: 1.1, trustMax: 40),
    ],
    ReplyTone.cold: [
      DialogueLine("We'll see.", weight: 1.0),
      DialogueLine("That's what you're telling me now?", weight: 1.5, trustMax: 30),
      DialogueLine("Sorry doesn't fix everything, mijo.", weight: 1.4, moodMax: -25),
    ],
  },

  // The 6 blocks below only cover the tone(s) each chip's phrasings in
  // conversation/intents.dart can actually produce (line.tone ?? chip.primaryTone
  // — see CareerController.sendIntent) — e.g. every askAboutWork phrasing is
  // untoned, so it always resolves to chip.primaryTone (honest) and a
  // warm/cold/vague bucket here would just be permanently-dead content.
  ConversationIntent.thank: {
    ReplyTone.warm: [
      DialogueLine("Aww, mijo, you don't have to thank me. That's what mothers are for.", weight: 1.4),
      DialogueLine('Hearing you say that means more than you know.', weight: 1.3, closenessMin: 40),
      DialogueLine("You're welcome, baby. Always.", weight: 1.2),
      DialogueLine("Well look at you, being sweet today. I like it.", weight: 1.1, moodMin: 0),
      DialogueLine("Okay, now I know something's up — you only get this sweet when you need something.", weight: 1.5, suspicionMin: 30, trustMax: 60),
      DialogueLine("That's all I ever wanted to hear from you, mijo.", weight: 1.6, closenessMin: 60, moodMin: 10),
    ],
  },

  ConversationIntent.compliment: {
    ReplyTone.warm: [
      DialogueLine('Aw, mijo. Look at you being sweet.', weight: 1.3),
      DialogueLine("I know, I know. I'm amazing. Somebody had to say it.", weight: 1.2, closenessMin: 45, moodMin: 0),
      DialogueLine("That's a good boy. Keep talking like that.", weight: 1.1, closenessMin: 55),
    ],
    ReplyTone.honest: [
      DialogueLine("You're just saying that because you want something, aren't you?", weight: 1.4, trustMax: 55),
      DialogueLine('I appreciate that, mijo. Really.', weight: 1.2),
      DialogueLine('I did try my best with you. Glad it shows sometimes.', weight: 1.3, moodMax: 20),
    ],
  },

  ConversationIntent.sayGoodbye: {
    ReplyTone.warm: [
      DialogueLine('Okay, mijo. Love you. Be safe out there.', weight: 1.5),
      DialogueLine('Bye, baby. Call your mother.', weight: 1.3, closenessMin: 40),
      DialogueLine('Love you too. Talk later, okay?', weight: 1.2),
      DialogueLine("Don't be a stranger now.", weight: 1.1, closenessMin: 55),
    ],
    ReplyTone.vague: [
      DialogueLine('Alright, mijo. Bye.', weight: 1.0),
      DialogueLine('Mm. Okay.', weight: 1.2, moodMax: 0),
      DialogueLine('Sure. Talk later, I guess.', weight: 1.3, trustMax: 40),
      DialogueLine('Okay. Bye.', weight: 1.0, suspicionMin: 30),
    ],
  },

  ConversationIntent.askAboutWork: {
    ReplyTone.honest: [
      DialogueLine("It's work, mijo. Same as always. Why, you asking for a reason?", weight: 1.3, topic: Topic.plans),
      DialogueLine('Busy. Tired. The usual. But it pays the bills.', weight: 1.2, topic: Topic.plans),
      DialogueLine('Better ask about YOUR work instead of mine.', weight: 1.4, suspicionMin: 25),
      DialogueLine('Same people, same headaches. But I like the routine.', weight: 1.1, moodMin: -10, topic: Topic.plans),
      DialogueLine("Slower this week, actually. Which I don't mind.", weight: 1.0, moodMin: 10),
    ],
  },

  ConversationIntent.askWhatsGoingOn: {
    ReplyTone.honest: [
      DialogueLine('Nothing much, mijo. Same as every day. Why do you ask?', weight: 1.2),
      DialogueLine('Honestly? Just tired. Nothing dramatic.', weight: 1.1),
      DialogueLine("You're asking ME what's going on? That's usually my line.", weight: 1.5, suspicionMin: 20),
      DialogueLine('A little stressed about your tía, but nothing you need to worry about.', weight: 1.3, closenessMin: 40, topic: Topic.family),
      DialogueLine("Same as always. You're the one who's been quiet lately.", weight: 1.4, suspicionMin: 40),
    ],
  },

  ConversationIntent.askAboutSomeone: {
    ReplyTone.honest: [
      DialogueLine("Tono's fine, still causing trouble as usual.", weight: 1.3, topic: Topic.family),
      DialogueLine("Tía's doing better this week, thank God.", weight: 1.2, topic: Topic.family),
      DialogueLine('The neighbors are the neighbors. Nothing new.', weight: 1.0),
      DialogueLine('Why the sudden interest in everyone, mijo?', weight: 1.4, suspicionMin: 25),
    ],
  },

  ConversationIntent.askForAdvice: {
    ReplyTone.honest: [
      DialogueLine("Of course, mijo. Tell me what's going on.", weight: 1.4),
      DialogueLine("You're asking ME for advice? Miracles happen.", weight: 1.3, closenessMin: 40, moodMin: 0),
      DialogueLine("I'll tell you what I think, but you don't always listen.", weight: 1.2, trustMax: 60),
      DialogueLine('Whatever it is, be honest with me first.', weight: 1.5, suspicionMin: 35),
    ],
  },

  ConversationIntent.askForHelp: {
    ReplyTone.honest: [
      DialogueLine('Tell me what you need, mijo.', weight: 1.0),
      DialogueLine('Of course, baby. What do you need?', weight: 1.5, closenessMin: 40),
      DialogueLine('Depends what it is. Tell me first.', weight: 1.3, trustMax: 55),
      DialogueLine('Is this a money thing again, mijo?', weight: 1.6, suspicionMin: 30, topic: Topic.money),
      DialogueLine('Anything for you, you know that.', weight: 1.2, closenessMin: 60, moodMin: 0),
      DialogueLine("I'll help, but we need to talk about why you keep needing it.", weight: 1.4, suspicionMin: 45, trustMax: 50),
    ],
  },

  ConversationIntent.confront: {
    ReplyTone.honest: [
      DialogueLine("Okay. I'm listening. What's this about?", weight: 1.4),
      DialogueLine("You want to talk? Fine, let's talk.", weight: 1.3, moodMin: -10),
      DialogueLine("I've been waiting for you to bring this up.", weight: 1.5, suspicionMin: 30, topic: Topic.suspicion),
    ],
    ReplyTone.cold: [
      DialogueLine('Fine. What is it.', weight: 1.0),
      DialogueLine('Watch your tone with me, mijo.', weight: 1.4, trustMax: 40),
      DialogueLine('You want to "talk"? Now you want to talk?', weight: 1.3, moodMax: -10),
      DialogueLine("Fine. But I don't like where this is going.", weight: 1.5, suspicionMin: 40, topic: Topic.suspicion),
    ],
  },

  ConversationIntent.questionLoyalty: {
    ReplyTone.cold: [
      DialogueLine("Don't you dare question that.", weight: 1.0),
      DialogueLine('How dare you ask me that.', weight: 1.6, trustMin: 40, topic: Topic.suspicion),
      DialogueLine("After everything I've done for you, you're asking me THAT?", weight: 1.5, closenessMin: 40),
    ],
    ReplyTone.honest: [
      DialogueLine("I'm always on your side, mijo. Always. Even when I don't like what you do.", weight: 1.6, topic: Topic.suspicion),
      DialogueLine("I don't always agree with you, but I never stopped being your mother.", weight: 1.4),
    ],
    ReplyTone.vague: [
      DialogueLine('...Why would you even ask me something like that?', weight: 1.3, trustMax: 40),
      DialogueLine("I don't know what you want me to say to that.", weight: 1.1),
    ],
  },

  ConversationIntent.reassure: {
    ReplyTone.warm: [
      DialogueLine("You'd better be careful. I mean it.", weight: 1.4),
      DialogueLine('Okay. I believe you. Just... be smart, mijo.', weight: 1.3, trustMin: 40),
      DialogueLine("That's all I needed to hear.", weight: 1.2, closenessMin: 45),
      DialogueLine('I still worry. That\'s my job. But okay.', weight: 1.5, suspicionMin: 20),
    ],
  },

  ConversationIntent.makePeace: {
    ReplyTone.warm: [
      DialogueLine("Okay. Let's not fight anymore.", weight: 1.0),
      DialogueLine("Okay, mijo. Come here. Let's not do this anymore.", weight: 1.5, moodMax: 20),
      DialogueLine('I don\'t want to fight either. I love you too much for that.', weight: 1.4, closenessMin: 40),
    ],
    ReplyTone.honest: [
      DialogueLine("Okay. We're okay. But we're not done talking about it.", weight: 1.3),
      DialogueLine("I don't want this between us either.", weight: 1.2),
    ],
  },

  ConversationIntent.sarcasm: {
    ReplyTone.vague: [
      DialogueLine('Mmhm. Sure, mijo.', weight: 1.2),
      DialogueLine('Cute. Very mature.', weight: 1.1, moodMax: 10),
    ],
    ReplyTone.cold: [
      DialogueLine('Not now, mijo.', weight: 1.0),
      DialogueLine("I don't have the patience for that today.", weight: 1.4, moodMax: -15),
      DialogueLine('Watch it.', weight: 1.3, trustMax: 35),
    ],
  },

  ConversationIntent.congratulate: {
    ReplyTone.warm: [
      DialogueLine('Aww, thank you, mijo! That means a lot coming from you.', weight: 1.4),
      DialogueLine('See? I told everyone you had it in you.', weight: 1.3, closenessMin: 45),
      DialogueLine('Look at you, being supportive. I like this version of you.', weight: 1.2, moodMin: 0),
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
      // Topic.wellbeing — a real answer instead of the generic listening lines.
      DialogueLine("Stress happens, mijo. Just don't let it eat you alive.", weight: 2.0, topic: Topic.wellbeing),
      DialogueLine("Some days are harder, I get it. I've had those too.", weight: 1.8, topic: Topic.wellbeing),
      // Topic.goodNews — reacting to actually hearing what went right, as
      // opposed to the Topic.wellbeing lines above, which are written for
      // hardship and would read as a total non-sequitur to good news.
      DialogueLine("There it is! I knew something was up the good way. Tell me you're proud of yourself.", weight: 2.0, topic: Topic.goodNews),
      DialogueLine("See, this is what I like to hear, mijo. Don't be shy about the good stuff.", weight: 1.8, topic: Topic.goodNews),
      // Topic.suspicion — she notices "nothing" took three sentences to say.
      DialogueLine("Nothing? Mijo, 'nothing' doesn't usually need three sentences to explain.", weight: 2.0, topic: Topic.suspicion),
      DialogueLine("Okay. I'm listening, but I'm not fully convinced yet.", weight: 1.8, topic: Topic.suspicion),
      // Topic.money — an actual read on "better lately"/"under control".
      DialogueLine("Better lately is good to hear. Keep it that way.", weight: 2.0, topic: Topic.money),
      DialogueLine("Okay. As long as it's really under control and not just talk.", weight: 1.8, topic: Topic.money),
      // Topic.family — acknowledging what she was actually just told.
      DialogueLine("Good, mijo. That's how family's supposed to work — you talk it out.", weight: 2.0, topic: Topic.family),
      DialogueLine("I'm glad you're checking in on them. That matters.", weight: 1.8, topic: Topic.family),
      // Topic.health — reacting to the "stress"/"run down" admission specifically.
      DialogueLine("Stress'll wear you down faster than you think, mijo. Slow down.", weight: 2.0, topic: Topic.health),
      DialogueLine("Doctor's right. You need to actually rest, not just say you will.", weight: 1.8, topic: Topic.health),
      // Topic.affection — she already half-knew, but hearing it still lands.
      DialogueLine("I know you do, mijo. I feel it, even when you don't say it.", weight: 2.0, topic: Topic.affection),
      DialogueLine("You don't have to say it perfectly. I already know.", weight: 1.8, topic: Topic.affection),
    ],
    ReplyTone.warm: [
      DialogueLine("There you go. That's all I wanted, mijo.", weight: 1.4, closenessMin: 50),
      DialogueLine("See? Wasn't so hard, was it?", weight: 1.2, closenessMin: 55, moodMin: 0),
      DialogueLine("I love when you actually talk to me.", weight: 1.3, closenessMin: 60),
      DialogueLine("Look at you, moving forward. I'm proud of you, mijo.", weight: 1.8, topic: Topic.plans),
      DialogueLine("A new start is a good thing. I just want you safe in it.", weight: 1.6, topic: Topic.plans),
      DialogueLine("There it is. Thank you for actually telling me how you're doing.", weight: 1.8, topic: Topic.wellbeing),
      DialogueLine("Ay, mijo! Now THAT'S what I wanted to hear. I'm so happy for you.", weight: 2.0, topic: Topic.goodNews),
      DialogueLine("See, that wasn't so hard. I feel better already.", weight: 1.8, topic: Topic.suspicion),
      DialogueLine("Good. That's a relief to hear, mijo.", weight: 1.8, topic: Topic.money),
      DialogueLine("That's my boy. Family always comes first.", weight: 1.8, topic: Topic.family),
      DialogueLine("Good. Take care of yourself, please. For me.", weight: 1.8, topic: Topic.health),
      DialogueLine("Ay, mijo. Now you're gonna make me cry.", weight: 2.0, topic: Topic.affection),
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
      DialogueLine("'Handling it' isn't the same as okay, mijo.", weight: 1.8, topic: Topic.wellbeing),
      DialogueLine("Still not convinced, but fine. Have it your way.", weight: 1.8, topic: Topic.suspicion),
      DialogueLine("'Under control' is what everyone says right before it isn't.", weight: 1.8, topic: Topic.money),
      DialogueLine("That's it? That's all you're giving me about family?", weight: 1.8, topic: Topic.family),
      DialogueLine("Doctor said stress? That's not nothing, mijo.", weight: 1.8, topic: Topic.health),
      DialogueLine("Hard to put into words, or hard to say to me?", weight: 1.8, topic: Topic.affection),
    ],
  },

  // Every "Not Right Now" phrasing is untoned/topic-agnostic (see
  // conversation/intents.dart), so it always resolves to the chip's own
  // primaryTone (vague) — same one-bucket pattern as thank/compliment/
  // sayGoodbye above, for the same reason: a warm/honest/cold bucket here
  // would just be permanently-dead content.
  ConversationIntent.deflect: {
    ReplyTone.vague: [
      DialogueLine("Okay. I won't push today.", weight: 1.4),
      DialogueLine("Fine. But I'm not going to stop asking, mijo.", weight: 1.3, suspicionMin: 25),
      DialogueLine("Mmhm. Whenever you're ready, I'm here.", weight: 1.2, closenessMin: 40),
      DialogueLine("Alright. I'll let it go. For now.", weight: 1.1),
      // Topic-aware — she notices what specifically got waved off, instead
      // of a flat "okay" regardless of subject.
      DialogueLine("Okay, we don't have to talk about money right now.", weight: 1.8, topic: Topic.money),
      DialogueLine("Fine — but something's going on, mijo. I can tell.", weight: 1.8, topic: Topic.suspicion, suspicionMin: 20),
      DialogueLine("Okay. Just don't shut me out completely, okay?", weight: 1.8, topic: Topic.wellbeing),
      DialogueLine("Alright, we can leave family out of it. For now.", weight: 1.6, topic: Topic.family),
    ],
  },
};

// ── "Ask for Money" reactions ───────────────────────────────────────────
// Distinct from [kMamaIntentReactions] above: the "(Ask for Money)" chip
// (see conversation/intents.dart's MoneyAskChipOption and
// CareerController.resolveMoneyAsk) hands the player a free-form dollar
// amount, not a pre-written phrasing — so there's no fixed ConversationIntent
// to key a reaction off. Instead the reaction branches on the AMOUNT itself
// (via CareerController._resolveMoneyAskOutcome), then on mood/trust/
// closeness/suspicion within that outcome the same way every other pool here
// does. Every tier keeps at least one fully ungated line, same lesson as
// kMamaIntentReactions: a tier where every line is gated can leave
// resolveMoneyAsk's pickLine() call with nothing eligible.
enum MoneyAskOutcome { granted, reluctant, refused }

const Map<MoneyAskOutcome, List<DialogueLine>> kMamaMoneyAskReactions = {
  MoneyAskOutcome.granted: [
    DialogueLine("Okay, mijo. I've got you.", weight: 1.0),
    DialogueLine("Of course. I'll send it today.", weight: 1.3, closenessMin: 40),
    DialogueLine("Done. Don't worry about it, baby.", weight: 1.2, closenessMin: 55, moodMin: 0),
    DialogueLine("That's manageable. Consider it handled.", weight: 1.1, trustMin: 50),
    DialogueLine("Okay. Just pay me back when you can, alright?", weight: 1.3, suspicionMin: 20),
  ],
  MoneyAskOutcome.reluctant: [
    DialogueLine("Fine. But this can't keep happening, mijo.", weight: 1.0),
    DialogueLine("That's a lot to ask, but okay. This time.", weight: 1.3, trustMin: 40),
    DialogueLine("I'll send it. I just wish I understood what's going on with you.", weight: 1.2, suspicionMin: 30),
    DialogueLine("Okay, mijo. I'm doing this because I love you, not because I'm not worried.", weight: 1.1, closenessMin: 45),
  ],
  MoneyAskOutcome.refused: [
    DialogueLine("I can't do that, mijo. I'm sorry.", weight: 1.0),
    DialogueLine("That's too much. I don't have that kind of money just lying around.", weight: 1.4),
    DialogueLine("No. And I need you to tell me why you need that much.", weight: 1.5, suspicionMin: 30),
    DialogueLine("Absolutely not. What is going on with you?", weight: 1.4, moodMax: 0),
    DialogueLine("I love you, but that number scares me. The answer's no.", weight: 1.3, trustMax: 50),
  ],
};

/// Phase 8: reactions for the three ways a ConversationFact contradiction
/// (planResponse's weighted challenge/acknowledge/clarify pick) can land.
/// Keyed by ResponseIntent rather than a dedicated outcome enum the way
/// kMamaMoneyAskReactions is — there's no separate "ContradictionOutcome"
/// type, planResponse's own output already names the three possibilities.
/// Only these three keys are ever populated or consulted; the other nine
/// ResponseIntent values have no entry here and never will.
///
/// Currently only proven against one contradiction pair — 'coverJob'
/// driving -> restaurant (see conversation/intents.dart's elaborate
/// phrasings) — so every line below reads generically enough to fit
/// whatever fact/value pair actually contradicted, rather than hard-coding
/// "driving" or "restaurant" into the text itself.
const Map<ResponseIntent, List<DialogueLine>> kMamaContradictionReactions = {
  ResponseIntent.challenge: [
    DialogueLine("Wait, that's not what you told me before. Which is it, mijo?", weight: 1.0),
    DialogueLine("Hold on — that's different from what you said last time. What changed?", weight: 1.0),
  ],
  ResponseIntent.acknowledge: [
    DialogueLine("Oh, okay. Things change, I guess. Thanks for keeping me posted.", weight: 1.0),
    DialogueLine("Alright, noted. Different from what I remembered, but okay.", weight: 1.0),
  ],
  ResponseIntent.clarify: [
    DialogueLine("Wait, I want to make sure I've got this right — can you say that again?", weight: 1.0),
    DialogueLine("Hold on, I don't think I'm remembering that the same way. Tell me again?", weight: 1.0),
  ],
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
