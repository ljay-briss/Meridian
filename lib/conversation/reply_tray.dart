// Everything that decides what appears in a personal thread's reply tray —
// the row(s) of chips relationships_screen.dart's `_ReplyTray` renders at the
// bottom of the screen (see its `options: g.personalReplyOptions(contactId)`
// call). This file owns SELECTION: which chips are eligible right now and
// which of those actually earn a slot. It does not own the candidate pools
// themselves (kPersonalReplyActions lives in ../data.dart, kIntentChips in
// intents.dart, kValeIntentChips in vale_intents.dart) or what happens once a
// chip is tapped (CareerController.sendIntent/resolveMoneyAsk/
// personalReplyAction, still in ../controller.dart — tapping a chip is a
// different concern from offering it).
import '../controller.dart';
import '../data.dart';
import 'intents.dart';
import 'vale_intents.dart';

extension ReplyTray on CareerController {
  /// Generates story-contextual chips for the personal chat tray based on
  /// current game state. These are injected at the front of the tray so they
  /// always surface, regardless of the static catalog's scoring. Each chip is
  /// a fully valid [PersonalReplyAction] — it routes through the same dialogue
  /// engine as any static chip when the player taps it.
  ///
  /// Ordering: most urgent / specific events first (a bribe that just happened
  /// beats a generic "bored" chip), falling back to time-of-day and mood chips,
  /// with deflection chips ("just missed you") always at the end as a way out.
  List<PersonalReplyAction> _storyContextChips(String contactId) {
    final chips = <PersonalReplyAction>[];
    final rel = relationships[contactId]!;
    final thread = personalThreads[contactId]!;

    // ── 1. Event-reactive (most specific/urgent) ───────────────────────────
    // Phase 2: each cluster below now carries its own `conversationIntent`
    // (ConversationIntent, dialogue_engine.dart) so CareerController routes
    // it to an isolated reaction pool in content/mama_reactions.dart instead
    // of the generic (tone, topic) soup — see that enum's own doc comment
    // for why. `topic`/`tone` stay as-is; they're still read as secondary
    // filters within the isolated pool, just no longer the only thing
    // selecting it.
    switch (recentStoryEvent) {
      case 'bribed':
        chips.add(const PersonalReplyAction('Paid someone off', tone: ReplyTone.honest, topics: {Topic.money}, intent: Intent.confession, intensity: 0.6, conversationIntent: ConversationIntent.admitBribe, phrasings: [
          DialogueLine("I had to pay someone off today. Felt weird about it."),
          DialogueLine("Had to grease a palm today just to keep things moving."),
        ]));
        chips.add(const PersonalReplyAction('Had to grease someone', tone: ReplyTone.vague, topics: {Topic.money}, intent: Intent.statement, intensity: 0.5, conversationIntent: ConversationIntent.admitBribe, phrasings: [
          DialogueLine("Slipped someone some cash today to make a problem go away."),
          DialogueLine("Had to spend money I didn't want to just to smooth things over."),
        ]));
        break;
      case 'close_call':
        chips.add(const PersonalReplyAction('Close call', tone: ReplyTone.honest, topics: {Topic.wellbeing}, intent: Intent.statement, intensity: 0.6, conversationIntent: ConversationIntent.reportCloseCall, phrasings: [
          DialogueLine("Had a close call today. I'm okay though."),
          DialogueLine("Something almost went really wrong today. I'm fine now."),
        ]));
        chips.add(const PersonalReplyAction('Shook up', tone: ReplyTone.honest, topics: {Topic.wellbeing}, intent: Intent.statement, intensity: 0.6, conversationIntent: ConversationIntent.reportCloseCall, phrasings: [
          DialogueLine("Something happened today that had me scared for a second. I'm fine."),
          DialogueLine("My heart's still racing a little from earlier. I'm okay though."),
        ]));
        chips.add(const PersonalReplyAction('Too close', tone: ReplyTone.vague, topics: {Topic.wellbeing}, intent: Intent.statement, intensity: 0.5, conversationIntent: ConversationIntent.reportCloseCall, phrasings: [
          DialogueLine("Almost messed up bad today. Keeping it together though."),
          DialogueLine("That was too close for comfort today. Still shaking it off."),
        ]));
        break;
      case 'run_success':
        chips.add(const PersonalReplyAction('Something went right', tone: ReplyTone.warm, topics: {Topic.goodNews}, intent: Intent.statement, intensity: 0.4, conversationIntent: ConversationIntent.reportSuccess, phrasings: [
          DialogueLine("Something I had to do today actually worked out."),
          DialogueLine("For once, today actually went according to plan."),
        ]));
        chips.add(const PersonalReplyAction('Getting it done', tone: ReplyTone.warm, topics: {Topic.goodNews}, intent: Intent.statement, intensity: 0.4, conversationIntent: ConversationIntent.reportSuccess, phrasings: [
          DialogueLine("Pulled off something today I wasn't sure I could."),
          DialogueLine("Surprised myself today — actually got it done."),
        ]));
        chips.add(const PersonalReplyAction('Getting the hang of it', tone: ReplyTone.warm, topics: {Topic.goodNews}, intent: Intent.statement, intensity: 0.3, conversationIntent: ConversationIntent.reportSuccess, phrasings: [
          DialogueLine("Starting to get the hang of things. Feels good."),
          DialogueLine("Finally feels like I know what I'm doing out there."),
        ]));
        break;
      case 'crossed_line':
        chips.add(const PersonalReplyAction('Crossed a line', tone: ReplyTone.honest, topics: {Topic.wellbeing}, intent: Intent.confession, intensity: 0.7, conversationIntent: ConversationIntent.admitCrossedLine, phrasings: [
          DialogueLine("I did something today I can't really undo."),
          DialogueLine("Crossed a line today I told myself I never would."),
        ]));
        chips.add(const PersonalReplyAction('Not proud of it', tone: ReplyTone.honest, topics: {Topic.wellbeing}, intent: Intent.confession, intensity: 0.6, conversationIntent: ConversationIntent.admitCrossedLine, phrasings: [
          DialogueLine("Had to handle something the hard way. Not proud of it."),
          DialogueLine("Did what I had to do today. Doesn't sit right with me though."),
        ]));
        chips.add(const PersonalReplyAction('Had to do it', tone: ReplyTone.honest, topics: {Topic.wellbeing}, intent: Intent.confession, intensity: 0.7, conversationIntent: ConversationIntent.admitCrossedLine, phrasings: [
          DialogueLine("I told myself I'd never do something like that. Then I did."),
          DialogueLine("Never thought I'd actually go through with something like that."),
        ]));
        break;
      case 'crew_violence':
        chips.add(const PersonalReplyAction('Had to get rough', tone: ReplyTone.vague, topics: {Topic.suspicion}, intent: Intent.statement, intensity: 0.6, conversationIntent: ConversationIntent.admitViolence, phrasings: [
          DialogueLine("Had to handle something the hard way today."),
          DialogueLine("Things got physical today. I'm okay, just handled it."),
        ]));
        chips.add(const PersonalReplyAction('Ugly situation', tone: ReplyTone.honest, topics: {Topic.wellbeing}, intent: Intent.statement, intensity: 0.6, conversationIntent: ConversationIntent.admitViolence, phrasings: [
          DialogueLine("Things got ugly today. I handled it. But still."),
          DialogueLine("Today got messier than I wanted. I'm fine, just shaken."),
        ]));
        chips.add(const PersonalReplyAction('People push you', tone: ReplyTone.vague, topics: {Topic.suspicion}, intent: Intent.statement, intensity: 0.5, conversationIntent: ConversationIntent.admitViolence, phrasings: [
          DialogueLine("Some people push you until you have no choice."),
          DialogueLine("Some people don't leave you any other option."),
        ]));
        break;
      case 'refused':
        chips.add(const PersonalReplyAction('Someone pushed back', tone: ReplyTone.honest, topics: {Topic.suspicion}, intent: Intent.statement, intensity: 0.5, conversationIntent: ConversationIntent.reportPushback, phrasings: [
          DialogueLine("Someone gave me a hard time today. Had to deal with it."),
          DialogueLine("Ran into some pushback today. Handled it, though."),
        ]));
        chips.add(const PersonalReplyAction('People are difficult', tone: ReplyTone.vague, topics: {Topic.suspicion}, intent: Intent.statement, intensity: 0.4, conversationIntent: ConversationIntent.reportPushback, phrasings: [
          DialogueLine("Not everyone plays ball. Learning that the hard way."),
          DialogueLine("Some people just aren't going to cooperate, no matter what."),
        ]));
        break;
      case 'crew_trouble':
        chips.add(const PersonalReplyAction('Team drama', tone: ReplyTone.vague, topics: {Topic.plans}, intent: Intent.statement, intensity: 0.5, conversationIntent: ConversationIntent.reportCrewTrouble, phrasings: [
          DialogueLine("Someone on my team is causing problems. Dealing with it."),
          DialogueLine("Got some drama with the people I work with. It's fine."),
        ]));
        chips.add(const PersonalReplyAction('Managing people', tone: ReplyTone.honest, topics: {Topic.plans}, intent: Intent.statement, intensity: 0.4, conversationIntent: ConversationIntent.reportCrewTrouble, phrasings: [
          DialogueLine("Managing people is harder than I thought."),
          DialogueLine("Keeping everyone in line is a full-time job by itself."),
        ]));
        chips.add(const PersonalReplyAction('Trust issues', tone: ReplyTone.vague, topics: {Topic.suspicion}, intent: Intent.statement, intensity: 0.5, conversationIntent: ConversationIntent.reportCrewTrouble, phrasings: [
          DialogueLine("One person can mess up the whole thing. Hate that."),
          DialogueLine("Hard to trust everyone around me lately, honestly."),
        ]));
        break;
      case 'incursion':
        chips.add(const PersonalReplyAction('Things are tense', tone: ReplyTone.vague, topics: {Topic.suspicion}, intent: Intent.statement, intensity: 0.5, conversationIntent: ConversationIntent.reportIncursion, phrasings: [
          DialogueLine("Things have been tense in my area lately."),
          DialogueLine("There's been a lot of tension around here lately."),
        ]));
        chips.add(const PersonalReplyAction('People testing me', tone: ReplyTone.vague, topics: {Topic.suspicion}, intent: Intent.statement, intensity: 0.5, conversationIntent: ConversationIntent.reportIncursion, phrasings: [
          DialogueLine("Someone's testing me right now. Seeing how I respond."),
          DialogueLine("Feels like someone's trying to see what I'll do."),
        ]));
        break;
    }

    // ── 2. Time-of-day aware ───────────────────────────────────────────────
    switch (timeOfDay) {
      case TimeOfDay.night:
        chips.add(const PersonalReplyAction("Can't sleep", tone: ReplyTone.honest, topics: {Topic.wellbeing}, intent: Intent.statement, intensity: 0.3, conversationIntent: ConversationIntent.reportCantSleep, phrasings: [
          DialogueLine("Can't really sleep. Brain won't shut off."),
          DialogueLine("Wide awake and I don't even know why."),
        ]));
        chips.add(const PersonalReplyAction('Night thoughts', tone: ReplyTone.honest, topics: {Topic.wellbeing}, intent: Intent.statement, intensity: 0.3, conversationIntent: ConversationIntent.reportCantSleep, phrasings: [
          DialogueLine("Everything feels heavier at night for some reason."),
          DialogueLine("My thoughts always get loudest this late."),
        ]));
        chips.add(const PersonalReplyAction('Wide awake', tone: ReplyTone.honest, topics: {Topic.wellbeing}, intent: Intent.statement, intensity: 0.3, conversationIntent: ConversationIntent.reportCantSleep, phrasings: [
          DialogueLine("It's late and I should be asleep but my head won't slow down."),
          DialogueLine("Should be asleep by now, but here I am."),
        ]));
        break;
      case TimeOfDay.morning:
        if (level >= 2) {
          chips.add(const PersonalReplyAction('Big day ahead', tone: ReplyTone.warm, topics: {Topic.plans}, intent: Intent.statement, intensity: 0.4, conversationIntent: ConversationIntent.reportBigDayAhead, phrasings: [
            DialogueLine("Got a lot going on today. Wish me luck."),
            DialogueLine("Big one today. Send good energy my way."),
          ]));
          chips.add(const PersonalReplyAction('Up early', tone: ReplyTone.honest, topics: {Topic.plans}, intent: Intent.statement, intensity: 0.3, conversationIntent: ConversationIntent.reportBigDayAhead, phrasings: [
            DialogueLine("Up early. Can't stop thinking about what's ahead."),
            DialogueLine("Couldn't sleep in — too much on my mind today."),
          ]));
        }
        break;
      case TimeOfDay.evening:
        chips.add(const PersonalReplyAction('Long day', tone: ReplyTone.honest, topics: {Topic.wellbeing}, intent: Intent.statement, intensity: 0.4, conversationIntent: ConversationIntent.reportLongDay, phrasings: [
          DialogueLine("Today was a lot. Don't even know where to start."),
          DialogueLine("Long one today. Glad it's finally winding down."),
        ]));
        chips.add(const PersonalReplyAction('Finally breathing', tone: ReplyTone.warm, topics: {Topic.wellbeing}, intent: Intent.statement, intensity: 0.3, conversationIntent: ConversationIntent.reportLongDay, phrasings: [
          DialogueLine("Finally getting to breathe a little. It's been a day."),
          DialogueLine("First quiet moment I've had all day, honestly."),
        ]));
        chips.add(const PersonalReplyAction('Day done', tone: ReplyTone.honest, topics: {Topic.wellbeing}, intent: Intent.statement, intensity: 0.3, conversationIntent: ConversationIntent.reportLongDay, phrasings: [
          DialogueLine("Glad today is almost over honestly."),
          DialogueLine("Ready for today to be done, if I'm honest."),
        ]));
        break;
      case TimeOfDay.afternoon:
        break;
    }

    // ── 3. Cash state ─────────────────────────────────────────────────────
    if (cash < 300 && level >= 2) {
      chips.add(const PersonalReplyAction('Broke', tone: ReplyTone.honest, topics: {Topic.money}, intent: Intent.statement, intensity: 0.5, subject: 'being broke', conversationIntent: ConversationIntent.reportBroke, phrasings: [
        DialogueLine("Money's been really tight lately."),
        DialogueLine("Not gonna lie, funds are pretty low right now."),
      ]));
      chips.add(const PersonalReplyAction('Struggling financially', tone: ReplyTone.honest, topics: {Topic.money}, intent: Intent.statement, intensity: 0.5, conversationIntent: ConversationIntent.reportBroke, phrasings: [
        DialogueLine("Things have been rough financially. Not gonna lie."),
        DialogueLine("Money's been a real struggle for me lately."),
      ]));
      chips.add(const PersonalReplyAction('Debt stress', tone: ReplyTone.honest, topics: {Topic.money}, intent: Intent.statement, intensity: 0.5, subject: 'debt', conversationIntent: ConversationIntent.reportBroke, phrasings: [
        DialogueLine("I owe people. It's sitting heavy on me."),
        DialogueLine("The debt situation is really weighing on me right now."),
      ]));
    } else if (cash > 50000) {
      chips.add(const PersonalReplyAction('Doing well', tone: ReplyTone.warm, topics: {Topic.money}, intent: Intent.statement, intensity: 0.4, resolvesThread: true, conversationIntent: ConversationIntent.reportDoingWell, phrasings: [
        DialogueLine("Things have been going well for me lately. Money-wise."),
        DialogueLine("Honestly, money hasn't been a worry lately."),
      ]));
      chips.add(const PersonalReplyAction('Good stretch', tone: ReplyTone.warm, topics: {Topic.goodNews}, intent: Intent.statement, intensity: 0.3, conversationIntent: ConversationIntent.reportDoingWell, phrasings: [
        DialogueLine("Had a good stretch recently. Can't complain."),
        DialogueLine("Things have been looking up lately, financially."),
      ]));
    } else if (cash > 8000 && level <= 3) {
      chips.add(const PersonalReplyAction('Good week', tone: ReplyTone.warm, topics: {Topic.goodNews}, intent: Intent.statement, intensity: 0.4, conversationIntent: ConversationIntent.reportDoingWell, phrasings: [
        DialogueLine("Actually had a decent week financially."),
        DialogueLine("Money's been okay this week, actually."),
      ]));
    }

    // ── 4. Heat / being watched ────────────────────────────────────────────
    if (policeHeat > 75) {
      chips.add(const PersonalReplyAction('Need to be careful', tone: ReplyTone.honest, topics: {Topic.suspicion}, intent: Intent.statement, intensity: 0.7, conversationIntent: ConversationIntent.reportHeatHigh, phrasings: [
        DialogueLine("I need to be more careful. Things are getting risky."),
        DialogueLine("Things are getting dangerous. I have to watch my step."),
      ]));
      chips.add(const PersonalReplyAction('Heat is on', tone: ReplyTone.vague, topics: {Topic.suspicion}, intent: Intent.statement, intensity: 0.6, conversationIntent: ConversationIntent.reportHeatHigh, phrasings: [
        DialogueLine("There's a lot of attention on me right now. Gotta stay low."),
        DialogueLine("Way too much attention on me right now."),
      ]));
    } else if (policeHeat > 50) {
      chips.add(const PersonalReplyAction('Watched', tone: ReplyTone.vague, topics: {Topic.suspicion}, intent: Intent.statement, intensity: 0.5, conversationIntent: ConversationIntent.reportFeelingWatched, phrasings: [
        DialogueLine("I feel like people have been watching me lately."),
        DialogueLine("Been getting this feeling that someone's keeping tabs on me."),
      ]));
      chips.add(const PersonalReplyAction('Something feels off', tone: ReplyTone.vague, topics: {Topic.suspicion}, intent: Intent.statement, intensity: 0.5, conversationIntent: ConversationIntent.reportFeelingWatched, phrasings: [
        DialogueLine("Something feels off. Like someone's paying attention."),
        DialogueLine("Can't shake the feeling something's not right."),
      ]));
      chips.add(const PersonalReplyAction('Eyes on me', tone: ReplyTone.vague, topics: {Topic.suspicion}, intent: Intent.statement, intensity: 0.4, conversationIntent: ConversationIntent.reportFeelingWatched, phrasings: [
        DialogueLine("I've just been feeling... observed. Can't explain it."),
        DialogueLine("Weird feeling lately, like eyes are on me."),
      ]));
    }

    // ── 5. Relationship-reactive ───────────────────────────────────────────
    if (rel.suspicion > 50) {
      // Reuses ConversationIntent.reassure — same "you don't need to worry,
      // I'm being careful" register its existing warm pool already covers.
      chips.add(const PersonalReplyAction("You don't have to worry", tone: ReplyTone.warm, topics: {Topic.wellbeing}, intent: Intent.statement, intensity: 0.4, conversationIntent: ConversationIntent.reassure, phrasings: [
        DialogueLine("I feel like you've been worried about me. You don't have to be."),
        DialogueLine("I can tell you've been worrying. It's really okay."),
      ]));
      chips.add(const PersonalReplyAction('I know you worry', tone: ReplyTone.warm, topics: {Topic.wellbeing}, intent: Intent.promise, intensity: 0.4, conversationIntent: ConversationIntent.reassure, phrasings: [
        DialogueLine("I know you worry. I'm being careful. I promise."),
        DialogueLine("I know it's hard not to worry. I'm careful, I promise."),
      ]));
    }
    if (rel.mood < -20) {
      chips.add(const PersonalReplyAction('Know I messed up', tone: ReplyTone.honest, topics: {Topic.affection}, intent: Intent.confession, intensity: 0.5, conversationIntent: ConversationIntent.admitPullingAway, phrasings: [
        DialogueLine("I know I've been letting you down lately."),
        DialogueLine("I know things between us haven't been great lately."),
      ]));
      chips.add(const PersonalReplyAction('Been distant', tone: ReplyTone.warm, topics: {Topic.affection}, intent: Intent.confession, intensity: 0.4, conversationIntent: ConversationIntent.admitPullingAway, phrasings: [
        DialogueLine("I've been distant. I know. I'm sorry."),
        DialogueLine("I know I've pulled away lately. I'm sorry for that."),
      ]));
      chips.add(const PersonalReplyAction('Trying to do better', tone: ReplyTone.warm, topics: {Topic.affection}, intent: Intent.promise, intensity: 0.4, conversationIntent: ConversationIntent.admitPullingAway, phrasings: [
        DialogueLine("I want to do better by you. I mean that."),
        DialogueLine("I'm going to try harder. You deserve that."),
      ]));
    }
    if (rel.daysSinceReply > 2 && thread.isNotEmpty) {
      chips.add(const PersonalReplyAction('Been MIA', tone: ReplyTone.warm, topics: {Topic.wellbeing}, intent: Intent.statement, intensity: 0.4, conversationIntent: ConversationIntent.apologizeForGoingQuiet, phrasings: [
        DialogueLine("I know I've been MIA. Things have been a lot."),
        DialogueLine("Sorry for going quiet. It's been a lot lately."),
      ]));
      chips.add(const PersonalReplyAction('Sorry been quiet', tone: ReplyTone.warm, topics: {Topic.affection}, intent: Intent.statement, intensity: 0.4, conversationIntent: ConversationIntent.apologizeForGoingQuiet, phrasings: [
        DialogueLine("Sorry I've been quiet. It's been one of those stretches."),
        DialogueLine("My bad for disappearing. Just been a rough stretch."),
      ]));
      chips.add(const PersonalReplyAction('Checked out for a bit', tone: ReplyTone.warm, topics: {Topic.affection}, intent: Intent.statement, intensity: 0.3, conversationIntent: ConversationIntent.apologizeForGoingQuiet, phrasings: [
        DialogueLine("I kind of checked out for a while. I'm back though."),
        DialogueLine("I went quiet for a bit. I'm here now, though."),
      ]));
    }

    // ── 6. Level-specific story context ───────────────────────────────────
    switch (level) {
      case 1:
        if (strikes > 0) {
          // Phase 2's flagship example (see ConversationIntent.admitMistake's
          // own doc comment) — this exact chip is what produced the "Okay
          // fine, I've been a little stressed" non-sequitur bug: the generic
          // Topic.wellbeing honest pool let an unrelated Topic.suspicion
          // self-report line win the tangent-bucket draw.
          chips.add(const PersonalReplyAction('Messed up at work', tone: ReplyTone.honest, topics: {Topic.wellbeing}, intent: Intent.confession, intensity: 0.5, conversationIntent: ConversationIntent.admitMistake, phrasings: [
            DialogueLine("I messed up at work today. Wasn't fatal but it was close."),
            DialogueLine("Had a rough one at work today. Almost blew it."),
          ]));
          chips.add(const PersonalReplyAction('Slipped up', tone: ReplyTone.honest, topics: {Topic.wellbeing}, intent: Intent.statement, intensity: 0.4, conversationIntent: ConversationIntent.admitMistake, phrasings: [
            DialogueLine("Made a mistake at work. Won't happen again."),
            DialogueLine("Small slip-up at work today. Learned from it."),
          ]));
        }
        if (cleanWeeks >= 1) {
          chips.add(const PersonalReplyAction('Work going okay', tone: ReplyTone.warm, topics: {Topic.wellbeing}, intent: Intent.statement, intensity: 0.3, conversationIntent: ConversationIntent.reportWorkGoingOkay, phrasings: [
            DialogueLine("Things at work have been going okay lately."),
            DialogueLine("Work's been steady lately, actually."),
          ]));
        }
        chips.add(const PersonalReplyAction('New job', tone: ReplyTone.honest, topics: {Topic.plans}, intent: Intent.statement, intensity: 0.3, conversationIntent: ConversationIntent.reportNewJob, phrasings: [
          DialogueLine("Started something new. Still figuring it out."),
          DialogueLine("New thing I'm working on. Still learning the ropes."),
        ]));
        break;
      case 2:
        if (runStage != null) {
          chips.add(const PersonalReplyAction('In the middle of something', tone: ReplyTone.vague, topics: {Topic.plans}, intent: Intent.statement, intensity: 0.5, conversationIntent: ConversationIntent.tooBusyRightNow, phrasings: [
            DialogueLine("Can't really talk right now. In the middle of something."),
            DialogueLine("Kind of tied up right now, can we talk later?"),
          ]));
          chips.add(const PersonalReplyAction('Kind of tense right now', tone: ReplyTone.vague, topics: {Topic.suspicion}, intent: Intent.statement, intensity: 0.5, conversationIntent: ConversationIntent.tooBusyRightNow, phrasings: [
            DialogueLine("Things are a little tense right now. I'll explain later."),
            DialogueLine("It's a bit stressful right this second. Later, okay?"),
          ]));
        }
        chips.add(const PersonalReplyAction('Long drives', tone: ReplyTone.vague, topics: {Topic.plans}, intent: Intent.statement, intensity: 0.3, conversationIntent: ConversationIntent.reportJobRoutine, phrasings: [
          DialogueLine("Been doing a lot of driving lately. Long ones."),
          DialogueLine("Spending way too much time on the road lately."),
        ]));
        chips.add(const PersonalReplyAction('Checkpoints', tone: ReplyTone.vague, topics: {Topic.suspicion}, intent: Intent.statement, intensity: 0.4, conversationIntent: ConversationIntent.reportJobRoutine, phrasings: [
          DialogueLine("Lot of people asking me questions lately. At work."),
          DialogueLine("Getting stopped and questioned more than I'd like."),
        ]));
        break;
      case 3:
        if (targetState.values.any((s) => s == 'refused' || s == 'lost')) {
          chips.add(const PersonalReplyAction('Difficult people', tone: ReplyTone.honest, topics: {Topic.suspicion}, intent: Intent.statement, intensity: 0.5, conversationIntent: ConversationIntent.reportDifficultPeople, phrasings: [
            DialogueLine("Some people just make things harder than they need to be."),
            DialogueLine("Dealing with some difficult people this week."),
          ]));
          chips.add(const PersonalReplyAction('Not everyone cooperates', tone: ReplyTone.vague, topics: {Topic.suspicion}, intent: Intent.statement, intensity: 0.4, conversationIntent: ConversationIntent.reportDifficultPeople, phrasings: [
            DialogueLine("Not everyone's cooperative. Having to push sometimes."),
            DialogueLine("Some people just won't play along, no matter what."),
          ]));
        }
        chips.add(const PersonalReplyAction('Different stress', tone: ReplyTone.vague, topics: {Topic.wellbeing}, intent: Intent.statement, intensity: 0.4, conversationIntent: ConversationIntent.reportFieldWorkStress, phrasings: [
          DialogueLine("Work's been... a different kind of stress lately."),
          DialogueLine("A new kind of stressful, this job. Hard to explain."),
        ]));
        chips.add(const PersonalReplyAction('Going door to door', tone: ReplyTone.vague, topics: {Topic.plans}, intent: Intent.statement, intensity: 0.3, conversationIntent: ConversationIntent.reportFieldWorkStress, phrasings: [
          DialogueLine("Been doing a lot of face-to-face stuff for work. Tiring."),
          DialogueLine("Lots of in-person work lately. Wears you down."),
        ]));
        break;
      case 4:
        // Reuses ConversationIntent.reportCrewTrouble/reportIncursion/
        // reportSuccess (Phase 2) — same underlying disclosures as the
        // matching recentStoryEvent chips, just surfacing from ongoing
        // state instead of a one-turn event.
        if (pendingTrouble != null) {
          chips.add(const PersonalReplyAction('Someone causing problems', tone: ReplyTone.vague, topics: {Topic.plans}, intent: Intent.statement, intensity: 0.5, conversationIntent: ConversationIntent.reportCrewTrouble, phrasings: [
            DialogueLine("Someone I work with is giving me problems. Have to deal with it."),
            DialogueLine("Got someone on my team causing me headaches."),
          ]));
        }
        if (pendingIncursion != null) {
          chips.add(const PersonalReplyAction('Competition', tone: ReplyTone.vague, topics: {Topic.suspicion}, intent: Intent.statement, intensity: 0.5, conversationIntent: ConversationIntent.reportIncursion, phrasings: [
            DialogueLine("Someone's trying to move into my space at work. Handling it."),
            DialogueLine("Got some competition moving in on my territory."),
          ]));
        }
        if (lastMonthTake > 80000) {
          chips.add(const PersonalReplyAction('Best month yet', tone: ReplyTone.warm, topics: {Topic.money}, intent: Intent.statement, intensity: 0.4, conversationIntent: ConversationIntent.reportSuccess, phrasings: [
            DialogueLine("Had my best month financially. By a lot."),
            DialogueLine("This was my best month yet, honestly."),
          ]));
        }
        chips.add(const PersonalReplyAction('Managing people', tone: ReplyTone.honest, topics: {Topic.plans}, intent: Intent.statement, intensity: 0.4, conversationIntent: ConversationIntent.reportNewResponsibility, phrasings: [
          DialogueLine("Managing people is harder than I thought it'd be."),
          DialogueLine("Being in charge of people is more work than I expected."),
        ]));
        chips.add(const PersonalReplyAction('In charge now', tone: ReplyTone.honest, topics: {Topic.plans}, intent: Intent.statement, intensity: 0.4, conversationIntent: ConversationIntent.reportNewResponsibility, phrasings: [
          DialogueLine("A lot of people are depending on me right now. It's a lot."),
          DialogueLine("There's a lot resting on me these days."),
        ]));
        break;
      case 5:
      case 6:
      case 7:
        if (investigationStage > 0) {
          // Reuses ConversationIntent.reportHeatHigh — same "serious
          // attention on me" register as the policeHeat>75 cluster above.
          chips.add(const PersonalReplyAction('Under a microscope', tone: ReplyTone.vague, topics: {Topic.suspicion}, intent: Intent.statement, intensity: 0.7, conversationIntent: ConversationIntent.reportHeatHigh, phrasings: [
            DialogueLine("I feel like I'm under a microscope lately."),
            DialogueLine("Feels like every move I make is being watched."),
          ]));
          chips.add(const PersonalReplyAction('Heat is serious', tone: ReplyTone.vague, topics: {Topic.suspicion}, intent: Intent.statement, intensity: 0.7, conversationIntent: ConversationIntent.reportHeatHigh, phrasings: [
            DialogueLine("There are serious people paying close attention to me right now."),
            DialogueLine("This is more serious attention than I'm used to."),
          ]));
          chips.add(const PersonalReplyAction('Got to lay low', tone: ReplyTone.vague, topics: {Topic.plans}, intent: Intent.statement, intensity: 0.6, conversationIntent: ConversationIntent.reportHeatHigh, phrasings: [
            DialogueLine("Can't be as visible as I was. Got to pull back for a bit."),
            DialogueLine("Need to keep a lower profile for a while."),
          ]));
        }
        chips.add(const PersonalReplyAction('In deep', tone: ReplyTone.honest, topics: {Topic.wellbeing}, intent: Intent.confession, intensity: 0.6, conversationIntent: ConversationIntent.admitInOverHead, phrasings: [
          DialogueLine("Sometimes I feel like I'm in over my head."),
          DialogueLine("Honestly, some days I feel like this is too much."),
        ]));
        chips.add(const PersonalReplyAction('Hard to separate', tone: ReplyTone.honest, topics: {Topic.wellbeing}, intent: Intent.confession, intensity: 0.6, conversationIntent: ConversationIntent.admitInOverHead, phrasings: [
          DialogueLine("It's getting harder to keep different parts of my life separate."),
          DialogueLine("Everything's starting to bleed together. Hard to manage."),
        ]));
        chips.add(const PersonalReplyAction('People around me', tone: ReplyTone.vague, topics: {Topic.suspicion}, intent: Intent.statement, intensity: 0.5, conversationIntent: ConversationIntent.reportNewCrowd, phrasings: [
          DialogueLine("The people around me lately... it's a different world."),
          DialogueLine("The company I keep these days is different, that's for sure."),
        ]));
        break;
    }

    // ── 7. Guilt / moral reflection (level-gated) ─────────────────────────
    if (level >= 3) {
      // Reuses ConversationIntent.deflect — "doing things I can't get into"
      // is the same not-elaborating register as tapping "Not Right Now."
      chips.add(const PersonalReplyAction('Been doing things', tone: ReplyTone.vague, topics: {Topic.suspicion}, intent: Intent.statement, intensity: 0.5, conversationIntent: ConversationIntent.deflect, phrasings: [
        DialogueLine("I've been doing things lately I can't really talk about."),
        DialogueLine("There's stuff going on I just can't get into right now."),
      ]));
    }
    if (level >= 4) {
      chips.add(const PersonalReplyAction('Reflecting', tone: ReplyTone.honest, topics: {Topic.wellbeing}, intent: Intent.confession, intensity: 0.5, conversationIntent: ConversationIntent.admitSelfDoubt, phrasings: [
        DialogueLine("I've been thinking about the choices I've been making lately."),
        DialogueLine("Been doing a lot of thinking about where I'm headed."),
      ]));
      chips.add(const PersonalReplyAction('Who am I becoming', tone: ReplyTone.honest, topics: {Topic.wellbeing}, intent: Intent.confession, intensity: 0.6, conversationIntent: ConversationIntent.admitSelfDoubt, phrasings: [
        DialogueLine("Sometimes I wonder if I'm turning into someone I wouldn't recognize."),
        DialogueLine("I barely recognize myself some days, honestly."),
      ]));
      // Reuses ConversationIntent.reportNewCrowd (same disclosure as level
      // 5-7's "People around me" above, just surfacing one level earlier).
      chips.add(const PersonalReplyAction("The people I'm around", tone: ReplyTone.vague, topics: {Topic.suspicion}, intent: Intent.statement, intensity: 0.4, conversationIntent: ConversationIntent.reportNewCrowd, phrasings: [
        DialogueLine("I've been spending time around some new people. Different crowd."),
        DialogueLine("Different circle of people lately. Not what you'd expect."),
      ]));
    }
    if (level >= 5) {
      chips.add(const PersonalReplyAction('Worth it?', tone: ReplyTone.honest, topics: {Topic.wellbeing}, intent: Intent.confession, intensity: 0.7, conversationIntent: ConversationIntent.admitDeepDoubt, phrasings: [
        DialogueLine("I don't know if what I'm doing is worth it anymore."),
        DialogueLine("Some days I really question if this is all worth it."),
      ]));
      chips.add(const PersonalReplyAction('Point of no return', tone: ReplyTone.honest, topics: {Topic.wellbeing}, intent: Intent.confession, intensity: 0.7, conversationIntent: ConversationIntent.admitDeepDoubt, phrasings: [
        DialogueLine("I've passed a point where I can't really go back to who I was."),
        DialogueLine("There's no going back to how things used to be. I know that now."),
      ]));
      chips.add(const PersonalReplyAction('Carrying a lot', tone: ReplyTone.honest, topics: {Topic.wellbeing}, intent: Intent.confession, intensity: 0.6, conversationIntent: ConversationIntent.admitDeepDoubt, phrasings: [
        DialogueLine("There's a lot I carry around that nobody knows about."),
        DialogueLine("I hold onto a lot that I never talk about."),
      ]));
    }

    // ── 8. Deflection — always available, always last ──────────────────────
    // Several of these reuse an existing intent rather than getting a new
    // one — see each entry's own comment for which and why.
    chips.addAll([
      const PersonalReplyAction('Just missed you', tone: ReplyTone.warm, topics: {Topic.affection}, intent: Intent.statement, intensity: 0.2, conversationIntent: ConversationIntent.reachOutNoReason, phrasings: [
        DialogueLine("Nothing crazy. Just wanted to hear your voice."),
        DialogueLine("No big reason. Just wanted to talk to you."),
      ]),
      const PersonalReplyAction('No reason', tone: ReplyTone.warm, topics: {Topic.affection}, intent: Intent.statement, intensity: 0.2, conversationIntent: ConversationIntent.reachOutNoReason, phrasings: [
        DialogueLine("No reason. Just missed you."),
        DialogueLine("Nothing really — just thinking of you."),
      ]),
      // Reuses ConversationIntent.checkIn — "what are you up to"/"how's
      // everything" is the same low-pressure check-in register.
      const PersonalReplyAction('Bored', tone: ReplyTone.warm, topics: {Topic.greeting}, intent: Intent.question, intensity: 0.2, conversationIntent: ConversationIntent.checkIn, phrasings: [
        DialogueLine("Bored honestly. What are you up to?"),
        DialogueLine("Nothing going on over here. What about you?"),
      ]),
      const PersonalReplyAction('Had you on my mind', tone: ReplyTone.warm, topics: {Topic.affection}, intent: Intent.statement, intensity: 0.2, conversationIntent: ConversationIntent.reachOutNoReason, phrasings: [
        DialogueLine("Just had you on my mind."),
        DialogueLine("You crossed my mind, so I figured I'd say hi."),
      ]),
      // Reuses ConversationIntent.reportLongDay — same "describing my
      // uneventful/tiring day" register as the TimeOfDay.evening cluster.
      const PersonalReplyAction('Slow day', tone: ReplyTone.honest, topics: {Topic.wellbeing}, intent: Intent.statement, intensity: 0.2, conversationIntent: ConversationIntent.reportLongDay, phrasings: [
        DialogueLine("Nothing interesting going on today honestly."),
        DialogueLine("Pretty slow day over here, nothing much to report."),
      ]),
      // Reuses ConversationIntent.deflect — quietly in one's own head fits
      // the same not-elaborating register as "Not Right Now."
      const PersonalReplyAction('In my head', tone: ReplyTone.vague, topics: {Topic.wellbeing}, intent: Intent.statement, intensity: 0.3, conversationIntent: ConversationIntent.deflect, phrasings: [
        DialogueLine("I've been quiet lately. Just been in my head."),
        DialogueLine("Been a little in my own head lately, that's all."),
      ]),
      const PersonalReplyAction('Just checking in', tone: ReplyTone.warm, topics: {Topic.greeting}, intent: Intent.question, intensity: 0.2, conversationIntent: ConversationIntent.checkIn, phrasings: [
        DialogueLine("Just wanted to check in. See how you're doing."),
        DialogueLine("Checking in on you — how's everything?"),
      ]),
      const PersonalReplyAction('Today was a lot', tone: ReplyTone.honest, topics: {Topic.wellbeing}, intent: Intent.statement, intensity: 0.3, conversationIntent: ConversationIntent.reportLongDay, phrasings: [
        DialogueLine("Today was a lot. Don't even know where to start."),
        DialogueLine("It's been a lot today, honestly."),
      ]),
    ]);

    return chips;
  }

  /// How many options [personalReplyOptions] surfaces at once — half the
  /// full catalog, rounded up. A proportion rather than a fixed number, so
  /// it stays "half the menu" if the catalog's size ever changes.
  static int get _personalReplyOptionCount => (kPersonalReplyActions.length / 2).ceil();

  /// The subset of [kPersonalReplyActions] offered for [contactId] right
  /// now — narrowed to [_personalReplyOptionCount] options by contact fit
  /// (some options, like flirting, only make sense for certain relations)
  /// and by the live conversation's context: what the thread's on, whether
  /// a question is hanging, how tense/broke/distant things are, and the
  /// time of day. Recomputed from current state on every call (no
  /// randomness), so the same state always offers the same options, and the
  /// menu shifts only when the conversation itself does. Returned in the
  /// catalog's own order, not score order, so the menu reads consistently.
  ///
  /// [expanded] is the "see everything" escape hatch (relationships_screen.dart's
  /// tray-expand chip): every cap and the intent-chip relevance filter below
  /// are lifted, so this returns every option that's ELIGIBLE right now (the
  /// hard mood/trust/level/suspicion/closeness/thread gates still apply —
  /// those aren't about relevance, they're about whether an option makes any
  /// sense at all), not just the best-scoring handful. A pending bespoke
  /// question tray (see below) still fully replaces the menu either way —
  /// there's nothing further to expand into once the tray is already down to
  /// exactly the chips that answer what was just asked.
  List<ReplyOption> personalReplyOptions(String contactId, {bool expanded = false}) {
    final rel = relationships[contactId]!;
    final threadEmpty = personalThreads[contactId]!.isEmpty;
    final tod = timeOfDay;
    final lv = level;

    // Mama just asked something specific and bespoke answer-stance chips
    // exist for exactly that question (see conversation/intents.dart's
    // kQuestionAnswerChips) — swap the ENTIRE tray to those, rather than
    // blending them into the usual context/intent chips below. The whole
    // point is that the tray stops being the same always-available menu and
    // becomes "how do you want to answer THIS" for the turn; mixing in the
    // generic chips would bury that behind unrelated options. Falls through
    // to the ordinary tray untouched whenever no bespoke set is authored for
    // the pending question, or none is pending at all.
    final pendingId = rel.pendingQuestionId;
    if (pendingId != null) {
      final bespoke = kQuestionAnswerChips[pendingId];
      if (bespoke != null) return bespoke.map(StoryChipOption.new).toList();
    }

    // Inject story-contextual chips at the front (up to 3), for every
    // contact — these are generated in priority order so the most
    // urgent/specific chips come first. We don't dedupe against the rest of
    // the tray — a context chip and a general one can have similar intent,
    // but the context one is always more specific and earns its slot
    // independently.
    final allContextChips = _storyContextChips(contactId);
    final contextChips = (expanded ? allContextChips : allContextChips.take(3)).map(StoryChipOption.new).toList();

    // Mama and Vale get the intent-chip catalog — see conversation/intents.dart
    // (Mama's kIntentChips) and conversation/vale_intents.dart (Vale's
    // kValeIntentChips). Every other contact keeps the exact original
    // kPersonalReplyActions catalog and scoring below, untouched.
    if (contactId == 'mama' || contactId == 'partner') {
      final chips = contactId == 'mama' ? kIntentChips : kValeIntentChips;

      // Contact-specific legacy actions ('Change the subject', 'Come clean (a
      // little)', 'Deny everything', 'Brush it off', etc. — see the
      // allowedContacts entries in kPersonalReplyActions) predate the
      // intent-chip system and were never migrated into it. They cover
      // exactly the deflection/answer register the generic intent-chip
      // catalog doesn't have (nothing in kIntentChips/kValeIntentChips lets
      // the player lie about or partially explain a suspicion-raising topic)
      // — without them, a pointed follow-up like "what are the actual
      // plans?" had no chip that actually addressed it. Scored/gated
      // identically to every other contact's kPersonalReplyActions tray
      // below, just restricted to entries tagged for this contact. (Vale has
      // none of these yet, so this is simply empty for her today.)
      final eligibleLegacy = [
        for (var i = 0; i < kPersonalReplyActions.length; i++)
          if (kPersonalReplyActions[i].allowedContacts?.contains(contactId) ?? false)
            if (kPersonalReplyActions[i].showWhenMoodBelow == null || rel.mood < kPersonalReplyActions[i].showWhenMoodBelow!)
              if (kPersonalReplyActions[i].showWhenMoodAbove == null || rel.mood > kPersonalReplyActions[i].showWhenMoodAbove!)
                if (!kPersonalReplyActions[i].requiresThread || !threadEmpty)
                  if (kPersonalReplyActions[i].showWhenLevelMin == null || lv >= kPersonalReplyActions[i].showWhenLevelMin!)
                    if (kPersonalReplyActions[i].showWhenLevelMax == null || lv <= kPersonalReplyActions[i].showWhenLevelMax!)
                      if (kPersonalReplyActions[i].showWhenTrustBelow == null || rel.trust < kPersonalReplyActions[i].showWhenTrustBelow!)
                        if (kPersonalReplyActions[i].showWhenTrustAbove == null || rel.trust > kPersonalReplyActions[i].showWhenTrustAbove!)
                          if (kPersonalReplyActions[i].showWhenSuspicionAbove == null || rel.suspicion > kPersonalReplyActions[i].showWhenSuspicionAbove!)
                            if (kPersonalReplyActions[i].showWhenClosenessAbove == null || rel.closeness > kPersonalReplyActions[i].showWhenClosenessAbove!)
                              (index: i, action: kPersonalReplyActions[i]),
      ];
      final scoredLegacy = [
        for (final e in eligibleLegacy) (index: e.index, action: e.action, score: _personalReplyOptionScore(e.action, rel: rel, threadEmpty: threadEmpty, tod: tod, level: lv)),
      ]..sort((a, b) {
          final byScore = b.score.compareTo(a.score);
          return byScore != 0 ? byScore : a.index.compareTo(b.index);
        });
      final pickedLegacy = (expanded ? scoredLegacy : scoredLegacy.take(_mamaLegacyActionCount)).toList()..sort((a, b) => a.index.compareTo(b.index));
      final legacyChips = pickedLegacy.map((p) => StoryChipOption(p.action));

      final eligible = [
        for (var i = 0; i < chips.length; i++)
          if (chips[i].showWhenMoodBelow == null || rel.mood < chips[i].showWhenMoodBelow!)
            if (chips[i].showWhenMoodAbove == null || rel.mood > chips[i].showWhenMoodAbove!)
              if (!chips[i].requiresThread || !threadEmpty)
                if (chips[i].showWhenLevelMin == null || lv >= chips[i].showWhenLevelMin!)
                  if (chips[i].showWhenLevelMax == null || lv <= chips[i].showWhenLevelMax!)
                    if (chips[i].showWhenTrustBelow == null || rel.trust < chips[i].showWhenTrustBelow!)
                      if (chips[i].showWhenTrustAbove == null || rel.trust > chips[i].showWhenTrustAbove!)
                        if (chips[i].showWhenSuspicionAbove == null || rel.suspicion > chips[i].showWhenSuspicionAbove!)
                          if (chips[i].showWhenClosenessAbove == null || rel.closeness > chips[i].showWhenClosenessAbove!)
                            (index: i, chip: chips[i]),
      ];
      final scored = [
        for (final e in eligible) (index: e.index, chip: e.chip, score: _intentChipScore(e.chip, rel: rel, threadEmpty: threadEmpty, tod: tod, level: lv)),
      ]..sort((a, b) {
          final byScore = b.score.compareTo(a.score);
          return byScore != 0 ? byScore : a.index.compareTo(b.index);
        });
      // _intentChipScore starts every chip at a baseline of 1.0 and only adds
      // from there — a chip still sitting at exactly 1.0 got no contextual
      // signal at all (nothing about mood/topic/time-of-day/level favors it
      // right now), so it isn't relevant to this turn, just generically
      // available. Filtering those out means the tray only ever contains
      // chips something about the current state actually justifies, instead
      // of always padding up to _intentChipCount with whatever was left.
      // The single top-scored chip is kept even at baseline as a floor, so
      // the tray is never completely empty when truly nothing stands out.
      final relevant = scored.where((e) => e.score > 1.0).toList();
      // expanded: every eligible chip, not just the ones something about
      // the current state actually favors — see this method's own doc
      // comment on [expanded].
      final picked = expanded ? scored : (relevant.isNotEmpty ? relevant : scored.take(1).toList()).take(_intentChipCount);
      // Kept in score order (highest first), not re-sorted back to catalog
      // order — whichever chip is actually the best fit for what just
      // happened leads, whether that's Explain More after a real topic gets
      // raised or something else entirely after a plain Greet. `scored` is
      // already sorted this way (see above), so this just carries that
      // order through instead of discarding it.
      final pickedChips = picked.map((p) => p.chip).toList();
      // Mama-only for now: resolveMoneyAsk's reaction pool (kMamaMoneyAskReactions)
      // is written in her voice specifically, so surfacing this for Vale
      // would send her replies in the wrong character's voice. Surfaced
      // whenever the live thread is actually on money and the weekly cap
      // isn't spent — see resolveMoneyAsk. Placed right after the context
      // chips so it's easy to spot the turn it's actually relevant, rather
      // than buried among the always-present intent chips.
      final moneyAskChip = (contactId == 'mama' && rel.currentTopic == Topic.money && moneyAsksRemaining(contactId) > 0)
          ? const [MoneyAskChipOption()]
          : const <ReplyOption>[];
      return [...contextChips, ...moneyAskChip, ...legacyChips, ...pickedChips];
    }

    final eligible = [
      for (var i = 0; i < kPersonalReplyActions.length; i++)
        if (kPersonalReplyActions[i].allowedContacts == null || kPersonalReplyActions[i].allowedContacts!.contains(contactId))
          // Visibility gates: mood, thread-presence, level, trust, suspicion, closeness.
          if (kPersonalReplyActions[i].showWhenMoodBelow == null || rel.mood < kPersonalReplyActions[i].showWhenMoodBelow!)
            if (kPersonalReplyActions[i].showWhenMoodAbove == null || rel.mood > kPersonalReplyActions[i].showWhenMoodAbove!)
              if (!kPersonalReplyActions[i].requiresThread || !threadEmpty)
                if (kPersonalReplyActions[i].showWhenLevelMin == null || lv >= kPersonalReplyActions[i].showWhenLevelMin!)
                  if (kPersonalReplyActions[i].showWhenLevelMax == null || lv <= kPersonalReplyActions[i].showWhenLevelMax!)
                    if (kPersonalReplyActions[i].showWhenTrustBelow == null || rel.trust < kPersonalReplyActions[i].showWhenTrustBelow!)
                      if (kPersonalReplyActions[i].showWhenTrustAbove == null || rel.trust > kPersonalReplyActions[i].showWhenTrustAbove!)
                        if (kPersonalReplyActions[i].showWhenSuspicionAbove == null || rel.suspicion > kPersonalReplyActions[i].showWhenSuspicionAbove!)
                          if (kPersonalReplyActions[i].showWhenClosenessAbove == null || rel.closeness > kPersonalReplyActions[i].showWhenClosenessAbove!)
                            (index: i, action: kPersonalReplyActions[i]),
    ];
    final scored = [
      for (final e in eligible) (index: e.index, action: e.action, score: _personalReplyOptionScore(e.action, rel: rel, threadEmpty: threadEmpty, tod: tod, level: lv)),
    ]..sort((a, b) {
        final byScore = b.score.compareTo(a.score);
        return byScore != 0 ? byScore : a.index.compareTo(b.index);
      });
    final picked = (expanded ? scored : scored.take(_personalReplyOptionCount)).toList()..sort((a, b) => a.index.compareTo(b.index));
    final staticChips = picked.map((p) => StoryChipOption(p.action));

    return [...contextChips, ...staticChips];
  }

  /// How many [IntentChip]s [personalReplyOptions] surfaces at once for
  /// Mama, on top of up to 3 story chips — a fixed tray size rather than a
  /// proportion of the 20-entry catalog (unlike [_personalReplyOptionCount]):
  /// half of 20 is a tray nobody can scan at a glance.
  static const int _intentChipCount = 5;

  /// How many of Mama's orphaned legacy [kPersonalReplyActions] entries
  /// (allowedContacts: {'mama'}) [personalReplyOptions] surfaces alongside
  /// her intent chips — small on purpose, since these exist to plug specific
  /// deflection/answer gaps the generic intent-chip catalog doesn't cover,
  /// not to duplicate it wholesale.
  static const int _mamaLegacyActionCount = 2;

  /// Mirrors [_personalReplyOptionScore], adapted to an [IntentChip]'s
  /// (primaryTone, primaryTopics, primaryIntent) — the representative
  /// register used for tray-ranking nudges only; the actual turn plays out
  /// with whichever phrasing line pickLine() ends up choosing.
  static double _intentChipScore(
    IntentChip a, {
    required RelationshipState rel,
    required bool threadEmpty,
    required TimeOfDay tod,
    required int level,
  }) {
    var score = 1.0;

    if (threadEmpty) {
      if (a.primaryTopics.contains(Topic.greeting)) score += 5;
      if (a.primaryIntent == Intent.dismissal) score -= 3;
    }

    if (rel.currentTopic != null && a.primaryTopics.contains(rel.currentTopic)) score += 4;
    if (!rel.lastQuestionAnswered && a.primaryIntent == Intent.dismissal) score -= 3;

    // Elaborate exists specifically to answer "say more" — it should win a
    // slot whenever there's actually a thread to continue or a question
    // hanging, so the player is never left with nothing that flows with
    // what Mama just said. Outweighs the empty-thread greeting bonus above
    // on purpose: a live topic or pending question only exists once the
    // thread already has content, so the two conditions never fight.
    // Topic.greeting is excluded on purpose — a plain "hey" isn't a subject
    // worth "explaining more" about, so it shouldn't make elaborate look
    // like the best reply just because some topic happens to be set.
    if (a.intent == ConversationIntent.elaborate) {
      if (rel.topicProgress >= 1 && rel.currentTopic != Topic.greeting) score += 8;
      if (!rel.lastQuestionAnswered) score += 6;
    }

    if (rel.fear > 40 && a.primaryTone == ReplyTone.warm) score += 2;
    if (rel.suspicion > 50 && (a.primaryTone == ReplyTone.warm || a.primaryTone == ReplyTone.honest)) score += 2;
    if (rel.trust < 30 && a.primaryTone == ReplyTone.honest) score += 2;

    if (rel.mood < -30 && (a.primaryTone == ReplyTone.warm || a.primaryIntent == Intent.promise)) score += 4;
    if (rel.mood < -30 && (a.primaryTone == ReplyTone.cold || a.primaryIntent == Intent.dismissal)) score -= 4;
    if (rel.mood < -10 && a.primaryIntent == Intent.dismissal) score -= 2;
    if (rel.mood > 30 && a.primaryTopics.contains(Topic.affection)) score += 2;
    if (rel.mood > 30 && (a.primaryTopics.contains(Topic.wellbeing) || a.primaryTopics.contains(Topic.goodNews))) score += 1;

    switch (tod) {
      case TimeOfDay.morning:
        if (a.primaryTopics.contains(Topic.greeting) || a.primaryTopics.contains(Topic.wellbeing)) score += 2;
        break;
      case TimeOfDay.afternoon:
        if (a.primaryTopics.contains(Topic.family) || a.primaryTopics.contains(Topic.suspicion)) score += 2;
        break;
      case TimeOfDay.evening:
      case TimeOfDay.night:
        if (a.primaryTopics.contains(Topic.affection) || a.primaryIntent == Intent.promise) score += 2;
        break;
    }

    if (a.showWhenLevelMin != null && level >= a.showWhenLevelMin!) score += 2;
    if (a.showWhenLevelMax != null && level <= a.showWhenLevelMax!) score += 1;
    if (a.showWhenSuspicionAbove != null && rel.suspicion > (a.showWhenSuspicionAbove! + 15)) score += 2;
    if (a.showWhenTrustAbove != null && rel.trust > (a.showWhenTrustAbove! + 10)) score += 1;
    if (a.showWhenClosenessAbove != null && rel.closeness > (a.showWhenClosenessAbove! + 10)) score += 1;

    return score;
  }

  /// Higher favors surfacing [a] in [personalReplyOptions] right now.
  /// Additive nudges on a base of 1.0 — not a formal formula like the
  /// engine's [pickLine] weights, just enough of a thumb on the scale that
  /// contextually sensible options rise to the top of the cut.
  static double _personalReplyOptionScore(
    PersonalReplyAction a, {
    required RelationshipState rel,
    required bool threadEmpty,
    required TimeOfDay tod,
    required int level,
  }) {
    var score = 1.0;

    if (threadEmpty) {
      // Opening a conversation favors a greeting; leading with a dismissal
      // reads as a non-sequitur when nothing's been said yet.
      if (a.topics.contains(Topic.greeting)) score += 5;
      if (a.intent == Intent.dismissal) score -= 3;
    }

    // Staying on the thread's live topic favors continuing it.
    if (rel.currentTopic != null && a.topics.contains(rel.currentTopic)) score += 4;

    // A question left hanging favors an actual answer over a dodge.
    if (!rel.lastQuestionAnswered && a.intent == Intent.dismissal) score -= 3;

    // Money already on the table favors the money-tagged options.
    if (a.isDebtTopic && (rel.debt > 25 || rel.currentTopic == Topic.money)) score += 4;

    // Tense or fraying favors de-escalating; low trust favors honesty.
    if (rel.fear > 40 && a.tone == ReplyTone.warm) score += 2;
    if (rel.suspicion > 50 && (a.tone == ReplyTone.warm || a.tone == ReplyTone.honest)) score += 2;
    if (rel.trust < 30 && a.tone == ReplyTone.honest) score += 2;

    // Mood-aware nudges — when she's hurt, warm/repair options rise; cold sinks.
    if (rel.mood < -30 && (a.tone == ReplyTone.warm || a.intent == Intent.promise)) score += 4;
    if (rel.mood < -30 && (a.tone == ReplyTone.cold || a.intent == Intent.dismissal)) score -= 4;
    if (rel.mood < -10 && a.intent == Intent.dismissal) score -= 2;
    if (rel.mood > 30 && a.topics.contains(Topic.affection)) score += 2;
    if (rel.mood > 30 && (a.topics.contains(Topic.wellbeing) || a.topics.contains(Topic.goodNews))) score += 1;

    // Time of day colors what reads naturally to bring up.
    switch (tod) {
      case TimeOfDay.morning:
        if (a.topics.contains(Topic.greeting) || a.topics.contains(Topic.wellbeing)) score += 2;
        break;
      case TimeOfDay.afternoon:
        if (a.topics.contains(Topic.family) || a.topics.contains(Topic.suspicion) || a.isDebtTopic) score += 2;
        break;
      case TimeOfDay.evening:
      case TimeOfDay.night:
        if (a.topics.contains(Topic.affection) || a.intent == Intent.promise) score += 2;
        break;
    }

    // Story-level nudges — options that fit the current level of tension
    // score higher so the most contextually appropriate ones rise to the top
    // of the cut without needing to hard-exclude others.
    if (a.showWhenLevelMin != null && level >= a.showWhenLevelMin!) score += 2;
    if (a.showWhenLevelMax != null && level <= a.showWhenLevelMax!) score += 1;
    // High-suspicion options score higher when the character is already worried.
    if (a.showWhenSuspicionAbove != null && rel.suspicion > (a.showWhenSuspicionAbove! + 15)) score += 2;
    // Trust-gated options score higher when trust matches their intent.
    if (a.showWhenTrustAbove != null && rel.trust > (a.showWhenTrustAbove! + 10)) score += 1;
    if (a.showWhenClosenessAbove != null && rel.closeness > (a.showWhenClosenessAbove! + 10)) score += 1;

    return score;
  }
}
