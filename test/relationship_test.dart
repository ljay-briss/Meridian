import 'package:flutter_test/flutter_test.dart';
import 'package:meridian_private/content/mama_reactions.dart';
import 'package:meridian_private/controller.dart';
import 'package:meridian_private/conversation/intents.dart';
import 'package:meridian_private/conversation/reply_tray.dart';
import 'package:meridian_private/data.dart';

/// Advances the relationship engine by one beat using Level 4's monthly
/// cycle as a neutral driver (it has no strike/death risk when supply is
/// fully allocated to a single high-value distributor and heat starts at 0).
void _tick(CareerController g) {
  g.allocate('d1', 100);
  g.closeMonth();
  g.pendingIncursion = null;
  g.pendingTrouble = null;
  g.level4Busy = false; // this helper drives ticks instantly, not in real time
}

// Reply actions picked by (tone, topic, intent) for each test's purpose —
// personal threads are chosen from the fixed kPersonalReplyActions menu;
// each action declares its own (tone, topics, intent, intensity) directly
// rather than having them inferred from typed text (the free-text lexicon
// classifier this used to run through was removed as dead code once the
// chip-based reply system fully replaced free text).
final _warmAction = kPersonalReplyActions.firstWhere((a) => a.label == 'Reassure');
final _coldAction = kPersonalReplyActions.firstWhere((a) => a.label == 'Brush off');
final _honestAction = kPersonalReplyActions.firstWhere((a) => a.label == 'Be honest');
final _excuseAction = kPersonalReplyActions.firstWhere((a) => a.label == 'Make an excuse');
final _greetAction = kPersonalReplyActions.firstWhere((a) => a.label == 'Greet');
final _wellbeingAction = kPersonalReplyActions.firstWhere((a) => a.label == 'Ask how they are');
final _vagueAction = kPersonalReplyActions.firstWhere((a) => a.label == 'Stay vague');
final _deflectMoneyAction = kPersonalReplyActions.firstWhere((a) => a.label == 'Deflect about money');
final _settleMoneyAction = kPersonalReplyActions.firstWhere((a) => a.label == 'Talk about money');

/// Guards the Phase 2/3 near-miss documented at the top of
/// kPersonalReplyActions (data.dart): these labels are the generic,
/// high-traffic legacy actions this test file already uses above as neutral
/// (tone, topic, intent) fixtures to exercise the engine's cross-cutting
/// reactive machinery (acknowledgesDodge/acknowledgesToneShift/
/// acknowledgesAnsweredQuestion, requiredFacts, honesty/reliability gating,
/// the questionId bespoke-tray lines) — machinery that lives only in the
/// generic kPersonalReactions pool. Tagging any of them with a
/// conversationIntent silently reroutes Mama's reply to an isolated pool
/// that doesn't replicate any of that, which is a real behavior regression
/// (confirmed: doing this once broke ~10 engine tests), not just a
/// test-fixture inconvenience — so this is a standing guard, not a one-off.
const _mustStayGeneric = ['Greet', 'Reassure', 'Be honest', 'Ask how they are', 'Ask about family', 'Push for answers', 'Stay vague', 'Make an excuse', 'Brush off', 'Insult', 'Talk about money', 'Deflect about money', 'Check in', 'Reassure her'];

void main() {
  group('Relationship engine', () {
    test('warm reply raises closeness/trust and lowers suspicion', () {
      final g = CareerController();
      addTearDown(g.dispose);
      final rel = g.relationships['mama']!;
      rel.suspicion = 30;
      final before = (rel.closeness, rel.trust, rel.suspicion);
      g.personalReplyAction('mama', _warmAction);
      expect(rel.closeness, greaterThan(before.$1));
      expect(rel.trust, greaterThan(before.$2));
      expect(rel.suspicion, lessThan(before.$3));
    });

    test('cold reply lowers closeness/trust and raises suspicion', () {
      final g = CareerController();
      addTearDown(g.dispose);
      final rel = g.relationships['partner']!;
      final before = (rel.closeness, rel.trust, rel.suspicion);
      g.personalReplyAction('partner', _coldAction);
      expect(rel.closeness, lessThan(before.$1));
      expect(rel.trust, lessThan(before.$2));
      expect(rel.suspicion, greaterThan(before.$3));
    });

    test('ignoring someone at high suspicion eventually triggers the confrontation', () {
      final g = CareerController();
      addTearDown(g.dispose);
      g.devJumpToLevel(4);
      final rel = g.relationships['partner']!;
      rel.suspicion = 99;
      for (var i = 0; i < 60 && !rel.resolved; i++) {
        _tick(g);
      }
      expect(rel.resolved, isTrue);
      final thread = g.personalThreads['partner']!;
      expect(kRelationshipContent['partner']!.confrontation.map((l) => l.text), contains(thread.last.text));
    });

    test('trust hitting 0 makes the thread go quiet', () {
      final g = CareerController();
      addTearDown(g.dispose);
      g.devJumpToLevel(4);
      final rel = g.relationships['friend']!;
      rel.trust = 0;
      _tick(g);
      expect(rel.goneQuiet, isTrue);
      final thread = g.personalThreads['friend']!;
      expect(kRelationshipContent['friend']!.goneQuietLine.map((l) => l.text), contains(thread.last.text));
    });

    test('boss notices a close attachment from level 4 onward', () {
      final g = CareerController();
      addTearDown(g.dispose);
      g.devJumpToLevel(4);
      g.relationships['mama']!.closeness = 90;
      bool fired = false;
      for (var i = 0; i < 60 && !fired; i++) {
        _tick(g);
        if (g.attachmentWarningContactId != null) fired = true;
      }
      expect(fired, isTrue);
      expect(g.attachmentWarningContactId, 'mama');
    });

    test('reassuring the boss costs cash and resolves the warning', () {
      final g = CareerController();
      addTearDown(g.dispose);
      g.devJumpToLevel(4);
      g.cash = 100000;
      g.attachmentWarningContactId = 'mama';
      final before = g.cash;
      g.resolveAttachmentWarning('reassure');
      expect(g.cash, lessThan(before));
      expect(g.attachmentWarningContactId, isNull);
    });

    test('cutting a contact off tanks closeness and trust', () {
      final g = CareerController();
      addTearDown(g.dispose);
      g.devJumpToLevel(4);
      final rel = g.relationships['mama']!;
      rel.closeness = 90;
      rel.trust = 90;
      g.attachmentWarningContactId = 'mama';
      g.resolveAttachmentWarning('cut_off');
      expect(rel.closeness, lessThan(90));
      expect(rel.trust, lessThan(90));
    });

    test('cutting a contact off records a cutOff memory, but reassuring/ignoring does not', () {
      final g = CareerController();
      addTearDown(g.dispose);
      g.devJumpToLevel(4);
      g.cash = 100000;

      final cutRel = g.relationships['mama']!;
      g.attachmentWarningContactId = 'mama';
      g.resolveAttachmentWarning('cut_off');
      expect(cutRel.memories.where((m) => m.kind == MemoryKind.cutOff).length, 1);

      final reassureRel = g.relationships['partner']!;
      g.attachmentWarningContactId = 'partner';
      g.resolveAttachmentWarning('reassure');
      expect(reassureRel.memories.where((m) => m.kind == MemoryKind.cutOff), isEmpty);

      final ignoreRel = g.relationships['friend']!;
      g.attachmentWarningContactId = 'friend';
      g.resolveAttachmentWarning('ignore');
      expect(ignoreRel.memories.where((m) => m.kind == MemoryKind.cutOff), isEmpty);
    });

    test('cutting off a linked contact echoes to their connection', () {
      final g = CareerController();
      addTearDown(g.dispose);
      g.devJumpToLevel(4);
      final brotherRel = g.relationships['brother']!;
      final before = brotherRel.mood;
      g.attachmentWarningContactId = 'mama';
      g.resolveAttachmentWarning('cut_off');
      expect(brotherRel.mood, lessThan(before));
      expect(brotherRel.memories.where((m) => m.kind == MemoryKind.heardAboutCutOff).length, 1);
    });

    test('cutting off an unlinked contact (oldfriend) does not echo anywhere', () {
      final g = CareerController();
      addTearDown(g.dispose);
      g.devJumpToLevel(4);
      g.attachmentWarningContactId = 'oldfriend';
      g.resolveAttachmentWarning('cut_off');
      for (final id in ['mama', 'partner', 'friend', 'brother']) {
        expect(
          g.relationships[id]!.memories.where((m) => m.kind == MemoryKind.heardAboutCutOff),
          isEmpty,
          reason: id,
        );
      }
    });

    test('a confrontation echoes to the linked contact', () {
      final g = CareerController();
      addTearDown(g.dispose);
      g.devJumpToLevel(4);
      final partnerRel = g.relationships['partner']!;
      final friendRel = g.relationships['friend']!;
      partnerRel.suspicion = 99;
      final before = friendRel.mood;
      for (var i = 0; i < 60 && !partnerRel.resolved; i++) {
        _tick(g);
      }
      expect(partnerRel.resolved, isTrue);
      expect(friendRel.mood, lessThan(before));
      expect(friendRel.memories.where((m) => m.kind == MemoryKind.heardAboutConfrontation).length, 1);
    });

    test('mood rises after a warm reply and decays back toward neutral over subsequent ticks', () {
      final g = CareerController();
      addTearDown(g.dispose);
      g.devJumpToLevel(4);
      final rel = g.relationships['mama']!;
      g.personalReplyAction('mama', _warmAction);
      expect(rel.mood, greaterThan(0));
      final peak = rel.mood;
      for (var i = 0; i < 5; i++) {
        _tick(g);
      }
      expect(rel.mood.abs(), lessThan(peak.abs()));
    });

    test('the same-tone reaction line varies across repeated sends', () {
      final g = CareerController();
      addTearDown(g.dispose);
      final seen = <String>{};
      for (var i = 0; i < 30; i++) {
        final before = g.personalThreads['mama']!.length;
        g.personalReplyAction('mama', _warmAction);
        final reaction = g.personalThreads['mama']!.sublist(before).lastWhere((m) => !m.fromMe);
        seen.add(reaction.text);
      }
      expect(seen.length, greaterThan(1));
      for (final text in seen) {
        expect(kPersonalReactions['mama']![ReplyTone.warm]!.map((l) => l.text), contains(text));
      }
    });

    test('mama tracks the conversation topic and deepens it across consecutive on-topic turns', () {
      final g = CareerController();
      addTearDown(g.dispose);
      final rel = g.relationships['mama']!;

      g.personalReplyAction('mama', _greetAction);
      expect(rel.currentTopic, Topic.greeting);
      expect(rel.topicProgress, 1);

      // A new topic (a different action) switches the thread and resets
      // progression, rather than carrying the greeting stage forward.
      g.personalReplyAction('mama', _wellbeingAction);
      expect(rel.currentTopic, Topic.wellbeing);
      expect(rel.topicProgress, 1);

      // Picking the same-topic action again deepens it instead of resetting.
      g.personalReplyAction('mama', _wellbeingAction);
      expect(rel.currentTopic, Topic.wellbeing);
      expect(rel.topicProgress, 2);

      // An action with no topic tag holds the thread already in progress
      // rather than losing it.
      g.personalReplyAction('mama', _vagueAction);
      expect(rel.currentTopic, Topic.wellbeing);
      expect(rel.topicProgress, 2);
    });

    test('a deepened wellbeing thread surfaces progression-2 reaction lines that a fresh thread never can', () {
      final stage1OnlyPool = kPersonalReactions['mama']![ReplyTone.honest]!
          .where((l) => l.topic == Topic.wellbeing && l.progressionMin == null)
          .map((l) => l.text)
          .toSet();
      final stage2Pool = kPersonalReactions['mama']![ReplyTone.honest]!
          .where((l) => l.topic == Topic.wellbeing && l.progressionMin != null)
          .map((l) => l.text)
          .toSet();
      expect(stage1OnlyPool, isNotEmpty);
      expect(stage2Pool, isNotEmpty);

      final freshThreadReplies = <String>{};
      final deepThreadReplies = <String>{};
      for (var i = 0; i < 40; i++) {
        final fresh = CareerController();
        addTearDown(fresh.dispose);
        fresh.personalReplyAction('mama', _wellbeingAction); // progress -> 1
        freshThreadReplies.add(fresh.personalThreads['mama']!.last.text);

        final deep = CareerController();
        addTearDown(deep.dispose);
        deep.personalReplyAction('mama', _wellbeingAction); // progress -> 1
        deep.personalReplyAction('mama', _wellbeingAction); // progress -> 2
        deepThreadReplies.add(deep.personalThreads['mama']!.last.text);
      }

      // progressionMin:2 lines are gated out at progress 1 — a fresh thread
      // can never surface them.
      expect(freshThreadReplies.intersection(stage2Pool), isEmpty);
      // Once the thread has deepened, at least some of those trials should
      // surface a stage-2 line.
      expect(deepThreadReplies.intersection(stage2Pool), isNotEmpty);
    });

    test('a dismissal does not resolve a pending question', () {
      // The state-transition logic itself (any non-dismissal reply resolves
      // it) is covered directly and deterministically by
      // resolvePendingQuestion's own unit tests in dialogue_engine_test.dart
      // — this only checks the dismissal side end-to-end. A "real reply
      // resolves it" integration check isn't reliable here: mama's own
      // reply for that same turn can legitimately favor a line that itself
      // asks a new question (e.g. a suspicion-topic follow-up), which
      // re-arms lastQuestionAnswered as a separate, later step — that's the
      // conversation continuing, not a contradiction of the player having
      // answered.
      final g = CareerController();
      addTearDown(g.dispose);
      final rel = g.relationships['mama']!;
      rel.lastQuestionAnswered = false; // simulate mama having just asked something
      g.personalReplyAction('mama', _coldAction);
      expect(rel.lastQuestionAnswered, isFalse, reason: 'a dismissal does not resolve a pending question');
    });

    test('dismissing a pending question favors dodge-acknowledging reaction lines over an unprompted dismissal', () {
      final dodgeTaggedCold = kPersonalReactions['mama']![ReplyTone.cold]!
          .where((l) => l.acknowledgesDodge)
          .map((l) => l.text)
          .toSet();
      expect(dodgeTaggedCold, isNotEmpty);

      final withPendingQuestion = <String>{};
      final withoutPendingQuestion = <String>{};
      for (var i = 0; i < 40; i++) {
        final pending = CareerController();
        addTearDown(pending.dispose);
        pending.relationships['mama']!.lastQuestionAnswered = false;
        pending.personalReplyAction('mama', _coldAction);
        withPendingQuestion.add(pending.personalThreads['mama']!.last.text);

        final fresh = CareerController();
        addTearDown(fresh.dispose);
        fresh.personalReplyAction('mama', _coldAction);
        withoutPendingQuestion.add(fresh.personalThreads['mama']!.last.text);
      }

      expect(withPendingQuestion.intersection(dodgeTaggedCold), isNotEmpty);
      expect(
        withPendingQuestion.intersection(dodgeTaggedCold).length,
        greaterThan(withoutPendingQuestion.intersection(dodgeTaggedCold).length),
      );
    });

    test('a pending question with a bespoke answer-chip set fully replaces the tray', () {
      final g = CareerController();
      addTearDown(g.dispose);
      final rel = g.relationships['mama']!;
      rel.lastQuestionAnswered = false;
      rel.pendingQuestionId = 'mama_wellbeing_checkin';

      final options = g.personalReplyOptions('mama');
      final labels = options.map((o) => o.displayLabel(rel, g.timeOfDay)).toList();

      expect(options.length, kQuestionAnswerChips['mama_wellbeing_checkin']!.length);
      expect(labels, containsAll(["(Say It's Going Well)", "(Say It's Been Difficult)", '(Avoid The Question)']));
      // None of the ordinary tray's chips (context chips, Explain More, the
      // Mama legacy actions) leak in alongside the bespoke set — the whole
      // point is that the tray becomes exactly "how do you answer this."
      expect(labels, isNot(contains('(Explain More)')));
    });

    test('a pending question with no bespoke answer-chip set falls through to the ordinary tray', () {
      final g = CareerController();
      addTearDown(g.dispose);
      final rel = g.relationships['mama']!;
      rel.lastQuestionAnswered = false;
      rel.pendingQuestionId = 'some_question_nobody_authored_chips_for';

      final options = g.personalReplyOptions('mama');
      expect(options, isNotEmpty);
      expect(options.length, isNot(kQuestionAnswerChips['mama_wellbeing_checkin']!.length));
    });

    test('answering a bespoke question chip clears pendingQuestionId; dodging it does not', () {
      final answerChip = kQuestionAnswerChips['mama_wellbeing_checkin']!.firstWhere((a) => a.label == "Say It's Going Well");
      final dodgeChip = kQuestionAnswerChips['mama_wellbeing_checkin']!.firstWhere((a) => a.label == 'Avoid The Question');

      final answered = CareerController();
      addTearDown(answered.dispose);
      answered.relationships['mama']!.lastQuestionAnswered = false;
      answered.relationships['mama']!.pendingQuestionId = 'mama_wellbeing_checkin';
      answered.personalReplyAction('mama', answerChip);
      expect(answered.relationships['mama']!.pendingQuestionId, isNull);

      final dodged = CareerController();
      addTearDown(dodged.dispose);
      dodged.relationships['mama']!.lastQuestionAnswered = false;
      dodged.relationships['mama']!.pendingQuestionId = 'mama_wellbeing_checkin';
      dodged.personalReplyAction('mama', dodgeChip);
      expect(dodged.relationships['mama']!.pendingQuestionId, 'mama_wellbeing_checkin');
    });

    test('mama asking a wellbeing check-in question sets pendingQuestionId to mama_wellbeing_checkin', () {
      // _wellbeingAction ('Ask how they are') has no conversationIntent, so
      // it routes to kPersonalReactions['mama'][ReplyTone.honest] — exactly
      // the pool the wellbeing-checkin cluster is tagged in (data.dart), and
      // its `when: _playerAskedAQuestion` gate is satisfied by this action's
      // own Intent.question.
      final found = <bool>[];
      for (var i = 0; i < 40; i++) {
        final g = CareerController();
        addTearDown(g.dispose);
        g.personalReplyAction('mama', _wellbeingAction);
        if (g.relationships['mama']!.pendingQuestionId == 'mama_wellbeing_checkin') {
          found.add(true);
          break;
        }
      }
      expect(found, isNotEmpty, reason: 'expected at least one of 40 trials to land on a wellbeing_checkin-tagged reaction line');
    });

    test("Phase 2: 'Messed up at work' always routes to its own admitMistake pool, never the generic suspicion self-report cluster", () {
      // Regression for the exact bug that motivated the Phase 2 migration —
      // before ConversationIntent.admitMistake existed, this chip competed
      // in the generic Topic.wellbeing/honest pool, where pickLine()'s
      // tangent bucket could occasionally land on an unrelated
      // Topic.suspicion self-report line ("Okay fine, I've been a little
      // stressed"). Now that the chip carries conversationIntent, it's
      // routed straight to kMamaIntentReactions[admitMistake][honest] and
      // never touches the generic pool at all — checked across many trials
      // since pickLine is still randomized WITHIN that isolated pool.
      final admitMistakeTexts = kMamaIntentReactions[ConversationIntent.admitMistake]![ReplyTone.honest]!.map((l) => l.text).toSet();
      for (var i = 0; i < 40; i++) {
        final g = CareerController();
        addTearDown(g.dispose);
        g.strikes = 1;
        final chip = g.personalReplyOptions('mama').whereType<StoryChipOption>().firstWhere((o) => o.action.label == 'Messed up at work');
        g.personalReplyAction('mama', chip.action);
        expect(g.personalThreads['mama']!.last.text, isIn(admitMistakeTexts));
      }
    });

    test("mama's suspicion self-report lines ('I'm fine, don't worry about me') require the player to have actually asked a question", () {
      // Regression for the "Okay fine, I've been a little stressed" bug:
      // these lines are Mama answering FOR HERSELF, so pickLine()'s tangent
      // bucket could otherwise reach for one (they carry unusually high
      // weight, 2.0-3.0) as a non-sequitur reply to an unrelated confession
      // like "Had a rough one at work today. Almost blew it." Checked in
      // both pools that carry this cluster (warm and honest).
      const askedCtx = DialogueContext(
        mood: 0, closeness: 50, trust: 50, suspicion: 0, daysSinceReply: 0,
        recentTones: [], memories: [], playerIntent: Intent.question,
      );
      const statedCtx = DialogueContext(
        mood: 0, closeness: 50, trust: 50, suspicion: 0, daysSinceReply: 0,
        recentTones: [], memories: [], playerIntent: Intent.confession,
      );
      final warmLine = kPersonalReactions['mama']![ReplyTone.warm]!.firstWhere((l) => l.text.startsWith('Ay mijo, you always could tell'));
      final honestLine = kPersonalReactions['mama']![ReplyTone.honest]!.firstWhere((l) => l.text.startsWith('Okay fine.'));
      for (final line in [warmLine, honestLine]) {
        expect(line.isEligible(askedCtx), isTrue, reason: '${line.text} should be eligible once the player actually asked');
        expect(line.isEligible(statedCtx), isFalse, reason: '${line.text} should NOT be eligible for an unrelated confession/statement');
      }
    });

    test('the brother-distant opener line is tagged for its own bespoke reply-stance tray', () {
      // Deterministic content check (not a probabilistic pipeline run, since
      // this line only lives in the unprompted `openers` pool where a real
      // trial would compete against ~50 other untagged lines) — this is the
      // item 6 example ("your brother said you've been distant... is he
      // wrong, mijo?"): a rare, memory-gated callback, not a grammatical
      // question chosen for its own sake, still wired the same way.
      final matches = kRelationshipContent['mama']!.openers.where((l) => l.questionId == 'mama_brother_distant').toList();
      expect(matches, hasLength(1));
      expect(matches.single.intent, Intent.question);
      expect(matches.single.topic, Topic.family);
    });

    test('a pending mama_brother_distant question replaces the tray with the brother-specific stances', () {
      final g = CareerController();
      addTearDown(g.dispose);
      final rel = g.relationships['mama']!;
      rel.lastQuestionAnswered = false;
      rel.pendingQuestionId = 'mama_brother_distant';

      final options = g.personalReplyOptions('mama');
      final labels = options.map((o) => o.displayLabel(rel, g.timeOfDay)).toList();

      expect(options.length, kQuestionAnswerChips['mama_brother_distant']!.length);
      expect(
        labels,
        containsAll([
          "(Say Everything's Good)",
          "(Say You've Been Busy With Work)",
          '(Admit You Had An Argument)',
          "(Say You Don't Want To Talk About It)",
          '(Ask About Her Brother)',
        ]),
      );
    });

    test('the "did you talk to Tono" opener line is tagged for its own bespoke reply-stance tray', () {
      // Item 7's own worked example ("Did you talk to Marcus?", subject
      // tracked as 'Tono' in the actual shipped line) — an everyday,
      // ungated factual check-in, unlike mama_brother_distant's rare
      // memory-gated callback.
      final matches = kRelationshipContent['mama']!.openers.where((l) => l.questionId == 'mama_asked_about_tono').toList();
      expect(matches, hasLength(1));
      expect(matches.single.intent, Intent.question);
      expect(matches.single.subject, 'Tono');
    });

    test('a pending mama_asked_about_tono question replaces the tray with yes/no-shaped stances, then the generic tray returns once answered', () {
      final g = CareerController();
      addTearDown(g.dispose);
      final rel = g.relationships['mama']!;
      rel.lastQuestionAnswered = false;
      rel.pendingQuestionId = 'mama_asked_about_tono';

      final pending = g.personalReplyOptions('mama');
      final pendingLabels = pending.map((o) => o.displayLabel(rel, g.timeOfDay)).toList();
      expect(pending.length, kQuestionAnswerChips['mama_asked_about_tono']!.length);
      expect(
        pendingLabels,
        containsAll(['(Answer Yes)', '(Answer No)', '(Explain What Happened)', '(Avoid The Question)', '(Change The Subject)']),
      );

      // Answering (not dodging) resolves it — the generic tray, with its
      // much larger and differently-shaped option set, comes back.
      final answerYes = kQuestionAnswerChips['mama_asked_about_tono']!.firstWhere((a) => a.label == 'Answer Yes');
      g.personalReplyAction('mama', answerYes);
      expect(rel.pendingQuestionId, isNull);
      final afterAnswering = g.personalReplyOptions('mama');
      expect(afterAnswering.length, isNot(pending.length));
    });

    test('the generic high-traffic legacy actions never carry a conversationIntent (Phase 2/3 regression guard)', () {
      for (final label in _mustStayGeneric) {
        final action = kPersonalReplyActions.firstWhere((a) => a.label == label);
        expect(action.conversationIntent, isNull, reason: "'$label' must stay on the generic pool — see _mustStayGeneric's doc comment");
      }
    });

    test("'Tell her about your day''s morning phrasing is tagged affection/warm, not inherited wellbeing/honest", () {
      // Regression: this phrasing's text ("thinking of you, Mamá") is purely
      // affectionate, but it used to carry no topic/tone of its own, so it
      // fell back to the parent action's {Topic.wellbeing}/honest — which
      // let mama's reply land on a suspicion-toned "whatever's got you
      // worried" line for what was actually a warm morning greeting.
      final action = kPersonalReplyActions.firstWhere((a) => a.label == 'Tell her about your day');
      final morningLine = action.phrasings.firstWhere((l) => l.text.contains('already thinking of you'));
      expect(morningLine.topic, Topic.affection);
      expect(morningLine.tone, ReplyTone.warm);
    });

    test('the uncle-back chain-starter line is tagged for its bespoke tray', () {
      // Deterministic content check (same reasoning as the brother/Tono
      // equivalents) — this line lives in the generic honest/family pool,
      // not a gated cluster, so a live pipeline run would be probabilistic
      // against several competing same-topic lines.
      final matches = kPersonalReactions['mama']![ReplyTone.honest]!.where((l) => l.questionId == 'mama_uncle_back').toList();
      expect(matches, hasLength(1));
      expect(matches.single.topic, Topic.family);
    });

    test('item 11: a two-step action chain — Ask About Family -> Ask About Uncle -> Ask How Mama Is Doing -> converges into mama_wellbeing_checkin', () {
      final g = CareerController();
      addTearDown(g.dispose);
      final rel = g.relationships['mama']!;

      // Step 0: force the chain-starter directly (bypassing the probabilistic
      // draw from the generic pool, same as the other bespoke-tray tests) —
      // this is what personalReplyAction would eventually land on after
      // 'Ask about family', just made deterministic for the test.
      rel.pendingQuestionId = 'mama_uncle_back';
      final tray1 = g.personalReplyOptions('mama');
      expect(tray1.length, kQuestionAnswerChips['mama_uncle_back']!.length);
      expect(tray1.map((o) => o.displayLabel(rel, g.timeOfDay)), contains('(Ask About Uncle)'));

      // Step 1: tap "Ask About Uncle" — its own reply (isolated
      // ConversationIntent.askAboutUncle pool) carries the SECOND questionId.
      final askAboutUncle = kQuestionAnswerChips['mama_uncle_back']!.firstWhere((a) => a.label == 'Ask About Uncle');
      g.personalReplyAction('mama', askAboutUncle);
      expect(rel.pendingQuestionId, 'mama_uncle_stubborn', reason: 'the chain should have advanced to its second link');
      expect(g.personalThreads['mama']!.last.text, "He's stubborn. Refuses to rest.");

      final tray2 = g.personalReplyOptions('mama');
      expect(tray2.length, kQuestionAnswerChips['mama_uncle_stubborn']!.length);
      expect(tray2.map((o) => o.displayLabel(rel, g.timeOfDay)), contains('(Ask How Mama Is Doing)'));

      // Step 2: tap "Ask How Mama Is Doing" — converges the chain back into
      // the EXISTING mama_wellbeing_checkin tray (item 2) instead of a new leaf.
      final askIfOkay = kQuestionAnswerChips['mama_uncle_stubborn']!.firstWhere((a) => a.label == 'Ask How Mama Is Doing');
      g.personalReplyAction('mama', askIfOkay);
      expect(rel.pendingQuestionId, 'mama_wellbeing_checkin', reason: 'the chain should converge into the existing wellbeing-checkin tray');

      final tray3 = g.personalReplyOptions('mama');
      expect(tray3.length, kQuestionAnswerChips['mama_wellbeing_checkin']!.length);
      expect(tray3.map((o) => o.displayLabel(rel, g.timeOfDay)), contains("(Say It's Going Well)"));
    });

    test('greeting mama twice in one day draws from the greeting-aware daily-repeat lines, not the generic "you asked me that" ones', () {
      // Regression: dailyRepeatReactions used to be one untagged pool
      // written for a repeated QUESTION/STATEMENT ("you asked me that
      // earlier", "I answered — you didn't see it?") — a total non-sequitur
      // for a repeated bare greeting like tapping 'Greet' twice in a day.
      // Topic.greeting-tagged lines were added specifically so pickLine()'s
      // on-topic tier (Greet's own topics: {Topic.greeting} puts the thread
      // on that topic) prefers them over the generic ones for this case.
      final genericDailyRepeatTexts = kRelationshipContent['mama']!.dailyRepeatReactions.where((l) => l.topic == null).map((l) => l.text).toSet();
      final greetingDailyRepeatTexts = kRelationshipContent['mama']!.dailyRepeatReactions.where((l) => l.topic == Topic.greeting).map((l) => l.text).toSet();
      expect(genericDailyRepeatTexts, isNotEmpty);
      expect(greetingDailyRepeatTexts, isNotEmpty);

      // _topicTier is deliberately probabilistic, not a hard topic
      // exclusion (same design as every other topic-tiering fix in this
      // session) — the generic lines stay reachable sometimes (the
      // "initiative" bucket), just no longer dominant. So the meaningful
      // claim isn't "generic can never appear," it's "greeting-tagged lines
      // are now reachable at all, and win most of the time" (casual
      // register weights on-topic at 60% vs. initiative's 20%).
      var greetingHits = 0, genericHits = 0;
      for (var i = 0; i < 60; i++) {
        final g = CareerController();
        addTearDown(g.dispose);
        g.personalReplyAction('mama', _greetAction);
        // A different action in between keeps this a non-consecutive daily
        // repeat rather than tripping consecutiveActionCount's separate
        // spam-pool override (spam takes priority over dailyRepeat, and
        // triggers on just 2 in a row) — same shape as the reported
        // scenario, which had another message between the two greetings.
        g.personalReplyAction('mama', _vagueAction);
        g.personalReplyAction('mama', _greetAction); // second same-label send today -> isDailyRepeat
        final text = g.personalThreads['mama']!.last.text;
        if (greetingDailyRepeatTexts.contains(text)) greetingHits++;
        if (genericDailyRepeatTexts.contains(text)) genericHits++;
      }
      expect(greetingHits, greaterThan(0));
      expect(greetingHits, greaterThan(genericHits));
    });

    test('first warm reply records one milestone memory; a second warm reply does not duplicate it', () {
      final g = CareerController();
      addTearDown(g.dispose);
      final rel = g.relationships['mama']!;
      g.personalReplyAction('mama', _warmAction);
      g.personalReplyAction('mama', _warmAction);
      expect(rel.memories.where((m) => m.kind == MemoryKind.firstWarmReply).length, 1);
    });

    test('leaving mama on read sends exactly one follow-up line, not one per subsequent tick', () {
      final g = CareerController();
      addTearDown(g.dispose);
      g.devJumpToLevel(4);
      final thread = g.personalThreads['mama']!;
      thread.add(const Message('Hey, you there?', false));
      for (var i = 0; i < 8; i++) {
        _tick(g);
      }
      final followUpTexts = kRelationshipContent['mama']!.followUp.map((l) => l.text).toSet();
      final followUpCount = thread.where((m) => followUpTexts.contains(m.text)).length;
      expect(followUpCount, 1);
    });

    test('friend/brother/oldfriend keep the default initiative and moodSensitivity', () {
      for (final id in ['friend', 'brother', 'oldfriend']) {
        final p = kPersonalContact[id]!;
        expect(p.initiative, 0.4, reason: id);
        expect(p.moodSensitivity, 0.0, reason: id);
      }
    });

    test('friend/brother/oldfriend keep their original lines verbatim and always-eligible', () {
      const neutral = DialogueContext(
        mood: 0,
        closeness: 50,
        trust: 50,
        suspicion: 0,
        daysSinceReply: 0,
        recentTones: [],
        memories: [],
      );
      const originalOpeners = {
        'friend': [
          "Hey! We going out this weekend or what?",
          "I need you to lend me some cash, I'll pay you back next week.",
          "lol what are you even doing that you don't even answer anymore? suspicious 👀",
        ],
        'brother': [
          "Can you lend me rent money? I swear I'll pay you back.",
          "Hey, I know you're into something. I want in too.",
          "Everything good? I don't even see you at family get-togethers anymore.",
        ],
        'oldfriend': [
          "You should see the baby, she's walking now. You should come meet her.",
          "Everything's calm here. Work, home, repeat. Can't complain about boring lol.",
          "You still in the same thing? You know there's always another way.",
        ],
      };
      const originalDistant = {
        'friend': ['ok bro', "nah, I'm not even telling you anything anymore"],
        'brother': ['Whatever.', "Doesn't matter anymore."],
        'oldfriend': ['Take care.', 'Ok, good luck.'],
      };
      for (final id in ['friend', 'brother', 'oldfriend']) {
        final content = kRelationshipContent[id]!;
        // distant pools keep their original two lines verbatim, with a third
        // added on top (same treatment as openers) — not an exact-list pin.
        for (final text in originalDistant[id]!) {
          final line = content.distant.firstWhere(
            (l) => l.text == text,
            orElse: () => throw TestFailure('$id missing original distant line: $text'),
          );
          expect(line.when(neutral), isTrue, reason: '$id original distant line should stay always-eligible: $text');
        }
        for (final text in originalOpeners[id]!) {
          final line = content.openers.firstWhere(
            (l) => l.text == text,
            orElse: () => throw TestFailure('$id missing original opener: $text'),
          );
          expect(line.when(neutral), isTrue, reason: '$id original opener should stay always-eligible: $text');
        }
        for (final line in content.distant) {
          expect(line.when(neutral), isTrue, reason: '$id distant line should stay always-eligible: ${line.text}');
        }
      }
    });

    test('every pool has at least 3 always-eligible options, for every contact', () {
      // A pool with too few always-eligible lines reads as visibly scripted
      // once VarietyBoost's recency penalty is exhausted (see
      // dialogue_engine_test.dart). This pins the minimum content depth so it
      // can't silently regress as more contacts/content get added.
      const neutral = DialogueContext(
        mood: 0,
        closeness: 50,
        trust: 50,
        suspicion: 0,
        daysSinceReply: 0,
        recentTones: [],
        memories: [],
      );
      for (final p in kPersonalContacts) {
        final content = kRelationshipContent[p.id]!;
        final pools = {'openers': content.openers, 'questioning': content.questioning, 'distant': content.distant};
        pools.forEach((poolName, pool) {
          final alwaysEligible = pool.where((l) => l.when(neutral)).length;
          expect(alwaysEligible, greaterThanOrEqualTo(3), reason: '${p.id}.$poolName');
        });
        for (final tone in ReplyTone.values) {
          expect(kPersonalReactions[p.id]![tone]!.length, greaterThanOrEqualTo(3), reason: '${p.id} reaction $tone');
        }
      }
    });

    test('mama and partner have nonzero moodSensitivity', () {
      expect(kPersonalContact['mama']!.moodSensitivity, greaterThan(0));
      expect(kPersonalContact['partner']!.moodSensitivity, greaterThan(0));
    });
  });

  group('Fear / Respect / Debt', () {
    test('a cold reply raises fear from 0', () {
      final g = CareerController();
      addTearDown(g.dispose);
      final rel = g.relationships['friend']!;
      g.personalReplyAction('friend', _coldAction);
      expect(rel.fear, greaterThan(0));
    });

    test('a warm reply lowers an already-elevated fear', () {
      final g = CareerController();
      addTearDown(g.dispose);
      final rel = g.relationships['friend']!;
      rel.fear = 50;
      g.personalReplyAction('friend', _warmAction);
      expect(rel.fear, lessThan(50));
    });

    test('an honest reply raises respect from 0', () {
      final g = CareerController();
      addTearDown(g.dispose);
      final rel = g.relationships['friend']!;
      g.personalReplyAction('friend', _honestAction);
      expect(rel.respect, greaterThan(0));
    });

    test('an excuse reply lowers an already-elevated respect', () {
      final g = CareerController();
      addTearDown(g.dispose);
      final rel = g.relationships['friend']!;
      rel.respect = 50;
      g.personalReplyAction('friend', _excuseAction);
      expect(rel.respect, lessThan(50));
    });

    test('deflecting a money-related message raises debt', () {
      final g = CareerController();
      addTearDown(g.dispose);
      final rel = g.relationships['friend']!;
      g.personalReplyAction('friend', _deflectMoneyAction);
      expect(rel.debt, greaterThan(0));
    });

    test('settling a money-related message warmly lowers an already-elevated debt', () {
      final g = CareerController();
      addTearDown(g.dispose);
      final rel = g.relationships['friend']!;
      rel.debt = 50;
      g.personalReplyAction('friend', _settleMoneyAction);
      expect(rel.debt, lessThan(50));
    });

    test('a non-money message never moves debt', () {
      final g = CareerController();
      addTearDown(g.dispose);
      final rel = g.relationships['friend']!;
      g.personalReplyAction('friend', _wellbeingAction);
      expect(rel.debt, 0);
    });
  });

  group('Block consequence', () {
    test('two backfired excuses with low trust sets isBlocked and appends the block line', () {
      final g = CareerController();
      addTearDown(g.dispose);
      final rel = g.relationships['mama']!;
      rel.trust = 20;
      rel.suspicion = 60; // > 50 -> excuse backfires
      g.personalReplyAction('mama', _excuseAction);
      expect(rel.betrayalCount, 1);
      expect(rel.isBlocked, isFalse);

      g.personalReplyAction('mama', _excuseAction);
      expect(rel.betrayalCount, 2);
      expect(rel.trust, lessThan(15));
      expect(rel.isBlocked, isTrue);
      expect(g.personalThreads['mama']!.last.text, "You're dead to me. Don't contact me again.");
    });

    test('a blocked contact ignores further personalReplyAction calls', () {
      final g = CareerController();
      addTearDown(g.dispose);
      final rel = g.relationships['mama']!;
      rel.isBlocked = true;
      final before = g.personalThreads['mama']!.length;
      g.personalReplyAction('mama', _warmAction);
      expect(g.personalThreads['mama']!.length, before);
    });

    test('a blocked contact never fires initiative ticks', () {
      final g = CareerController();
      addTearDown(g.dispose);
      g.devJumpToLevel(4);
      final rel = g.relationships['mama']!;
      rel.isBlocked = true;
      final before = g.personalThreads['mama']!.length;
      for (var i = 0; i < 20; i++) {
        _tick(g);
      }
      expect(g.personalThreads['mama']!.length, before);
    });
  });

  group('Contextual reply options (legacy catalog — friend/brother/oldfriend)', () {
    test('offers half the full catalog, rounded up — capped by what this contact can actually see', () {
      final g = CareerController();
      addTearDown(g.dispose);
      // partner (Vale) moved onto the intent-chip system alongside mama —
      // see the group below — so this now exercises a contact still on the
      // original legacy-catalog path. Unlike partner, friend/brother/oldfriend
      // can't see the one partner-only entry (Flirt), so their eligible pool
      // is 1 short of the full catalog — the target slot count (half the
      // catalog, rounded up) still exceeds that, so .take() caps at whatever
      // is actually eligible rather than the full target.
      final shown = g.personalReplyOptions('friend').whereType<StoryChipOption>().toList();
      // Story-context chips (up to 3) are prepended on top of the scored
      // catalog cut, so filter those out by checking against the catalog.
      final catalogShown = shown.where((o) => kPersonalReplyActions.contains(o.action)).toList();
      final eligibleForFriend = kPersonalReplyActions.where((a) => a.allowedContacts == null || a.allowedContacts!.contains('friend')).length;
      expect(catalogShown.length, ((kPersonalReplyActions.length / 2).ceil()).clamp(0, eligibleForFriend));
    });

    test('flirt only ever surfaces for the romantic partner', () {
      final g = CareerController();
      addTearDown(g.dispose);
      for (final id in ['mama', 'friend', 'brother', 'oldfriend']) {
        expect(
          g.personalReplyOptions(id).whereType<StoryChipOption>().any((o) => o.action.label == 'Flirt'),
          isFalse,
          reason: id,
        );
      }
      // Vale is on the intent-chip system now, but Flirt (allowedContacts:
      // {'partner'}) still reaches her through the same legacy-overlay path
      // mama's deflection-only entries use (personalReplyOptions' eligibleLegacy).
      expect(g.personalReplyOptions('partner').whereType<StoryChipOption>().any((o) => o.action.label == 'Flirt'), isTrue);
    });

    // The original version of this test asserted debt=0 -> hidden, debt=80
    // -> visible, for 'mama'. That was actually a knife-edge artifact of
    // mama's now-removed 8 mama-only catalog entries changing which options
    // fell just inside/outside the scored top-half cut. Every other contact
    // already shows a debt-topic option at debt=0 regardless — isDebtTopic
    // has no visibility gate of its own, only a scoring nudge — and the
    // returned list is always re-sorted back to catalog order after the cut,
    // so relative position doesn't reveal the score change either. There's
    // no remaining contact/state combination where debt's effect on
    // _personalReplyOptionScore is independently observable through
    // personalReplyOptions' public surface, so this test is dropped rather
    // than replaced with an assertion that doesn't actually verify anything.

    test('is stable across repeated calls with no state change', () {
      final g = CareerController();
      addTearDown(g.dispose);
      final first = g.personalReplyOptions('partner').whereType<StoryChipOption>().map((o) => o.action.label);
      final second = g.personalReplyOptions('partner').whereType<StoryChipOption>().map((o) => o.action.label);
      expect(second, first);
    });
  });

  group('Contextual reply options (intent chips — mama)', () {
    test('offers at most 5 intent chips, and never zero', () {
      // Not a fixed count of 5 anymore: personalReplyOptions only surfaces an
      // intent chip once something about the current state actually favors
      // it (score > the 1.0 baseline every chip starts at) — a chip that's
      // merely available, with no contextual signal behind it, is left out
      // rather than padding the tray up to a fixed size. A fresh, empty-
      // thread conversation at level 1 only has a couple of chips (Greet,
      // Check-In) that clear that bar.
      final g = CareerController();
      addTearDown(g.dispose);
      final count = g.personalReplyOptions('mama').whereType<IntentChip>().length;
      expect(count, greaterThan(0));
      expect(count, lessThanOrEqualTo(5));
    });

    test('an empty thread at level 1 favors Greet; level-gated intents stay out of the cut', () {
      final g = CareerController();
      addTearDown(g.dispose);
      final chips = g.personalReplyOptions('mama').whereType<IntentChip>();
      expect(chips.any((c) => c.label == 'Greet'), isTrue);
      // Insult/Confront are gated to level 3+ — not reachable at level 1
      // regardless of scoring.
      expect(chips.any((c) => c.intent == ConversationIntent.insult), isFalse);
      expect(chips.any((c) => c.intent == ConversationIntent.confront), isFalse);
    });

    test('reaching level 3 unlocks mid-tier intents like Insult', () {
      final g = CareerController();
      addTearDown(g.dispose);
      g.devJumpToLevel(3);
      // Insult only actually wins one of the 5 tray slots once it's the
      // live topic or otherwise favored — assert eligibility, not the cut.
      final rel = g.relationships['mama']!;
      final chip = kIntentChips.firstWhere((c) => c.intent == ConversationIntent.insult);
      expect(chip.showWhenLevelMin, lessThanOrEqualTo(g.level));
      expect(rel.suspicion, 0); // sanity: nothing gates it off at this point
    });

    test('a live topic thread keeps surfacing the chip that continues it', () {
      final g = CareerController();
      addTearDown(g.dispose);
      final rel = g.relationships['mama']!;
      rel.currentTopic = Topic.family;
      rel.topicProgress = 2;
      expect(
        g.personalReplyOptions('mama').whereType<IntentChip>().any((c) => c.primaryTopics.contains(Topic.family)),
        isTrue,
      );
    });

    test('a pending question deprioritizes a dismissal-intent chip out of the cut', () {
      final g = CareerController();
      addTearDown(g.dispose);
      g.devJumpToLevel(3); // Insult (the only dismissal-intent chip) is gated to level 3+
      final rel = g.relationships['mama']!;
      g.personalReplyAction('mama', _wellbeingAction);
      rel.lastQuestionAnswered = false;
      expect(
        g.personalReplyOptions('mama').whereType<IntentChip>().any((c) => c.primaryIntent == Intent.dismissal),
        isFalse,
      );
    });

    test('is stable across repeated calls with no state change', () {
      final g = CareerController();
      addTearDown(g.dispose);
      final first = g.personalReplyOptions('mama').whereType<IntentChip>().map((c) => c.label);
      final second = g.personalReplyOptions('mama').whereType<IntentChip>().map((c) => c.label);
      expect(second, first);
    });
  });

  group('Tone-shift awareness', () {
    test('greeting then suddenly turning cold always gets a shift-acknowledging reply', () {
      // detectToneShift only counts polar-register swings — warm<->cold or
      // honest<->excuse (see its doc comment) — warm<->honest is documented,
      // deliberate natural drift, not a shift. "hey" (warm/greeting) then
      // "brush off" (cold) is the real polar swing a person would notice
      // mid-conversation. Since mama's cold pool carries shift-tagged lines,
      // the reaction is drawn from those exclusively — not just more likely,
      // guaranteed.
      final shiftTaggedCold = kPersonalReactions['mama']![ReplyTone.cold]!
          .where((l) => l.acknowledgesToneShift)
          .map((l) => l.text)
          .toSet();
      expect(shiftTaggedCold, isNotEmpty);

      final g = CareerController();
      addTearDown(g.dispose);
      g.personalReplyAction('mama', _greetAction);
      g.personalReplyAction('mama', _coldAction);
      expect(shiftTaggedCold, contains(g.personalThreads['mama']!.last.text));
    });

    test('the reverse shift (cold back to warm) also always gets a shift-acknowledging reply', () {
      final shiftTaggedWarm = kPersonalReactions['mama']![ReplyTone.warm]!
          .where((l) => l.acknowledgesToneShift)
          .map((l) => l.text)
          .toSet();
      expect(shiftTaggedWarm, isNotEmpty);

      final g = CareerController();
      addTearDown(g.dispose);
      g.personalReplyAction('mama', _coldAction);
      g.personalReplyAction('mama', _warmAction);
      expect(shiftTaggedWarm, contains(g.personalThreads['mama']!.last.text));
    });

    test('honest twice in a row (no shift) is not forced into the shift-only lines', () {
      final shiftTaggedHonest = kPersonalReactions['mama']![ReplyTone.honest]!
          .where((l) => l.acknowledgesToneShift)
          .map((l) => l.text)
          .toSet();

      final seen = <String>{};
      for (var i = 0; i < 20; i++) {
        final g = CareerController();
        addTearDown(g.dispose);
        g.personalReplyAction('mama', _honestAction);
        g.personalReplyAction('mama', _honestAction);
        seen.add(g.personalThreads['mama']!.last.text);
      }
      expect(seen.difference(shiftTaggedHonest), isNotEmpty);
    });

    test('picking the same tone as last turn is never treated as a shift', () {
      final g = CareerController();
      addTearDown(g.dispose);
      g.personalReplyAction('mama', _honestAction);
      expect(detectToneShift(previousTone: g.relationships['mama']!.recentTones.last, tone: ReplyTone.honest), isFalse);
    });

    test('every contact carries at least one shift-acknowledging line somewhere in their reaction pools', () {
      for (final p in kPersonalContacts) {
        final pools = kPersonalReactions[p.id]!;
        final hasAny = pools.values.any((pool) => pool.any((l) => l.acknowledgesToneShift));
        expect(hasAny, isTrue, reason: p.id);
      }
    });
  });

  group('Intent-chip conversation memory (mama)', () {
    const recallLine = "I'm alright. Better now that you're asking. And don't worry — your sister's fine, since you asked.";
    const phaseLine = "You've been quiet about what's really going on. Should I be worried?";

    test('a recent askAboutFamily turn makes checkIn favor the recall-tagged line far more often than without it', () {
      // recallMatch suppresses (0.2x), not excludes, an unsatisfied
      // requiresRecentIntent line — by design (a callback should be a
      // weighted possibility, not a guarantee), so this is a frequency
      // comparison across many trials, the same style every other
      // pickLine-weight test in this file already uses, not a hard
      // never-without assertion.
      var hitsWithRecall = 0;
      var hitsWithout = 0;
      for (var i = 0; i < 60; i++) {
        final withRecall = CareerController();
        addTearDown(withRecall.dispose);
        withRecall.sendIntent('mama', ConversationIntent.askAboutFamily);
        withRecall.sendIntent('mama', ConversationIntent.checkIn);
        if (withRecall.personalThreads['mama']!.last.text == recallLine) hitsWithRecall += 1;

        final without = CareerController();
        addTearDown(without.dispose);
        without.sendIntent('mama', ConversationIntent.checkIn);
        if (without.personalThreads['mama']!.last.text == recallLine) hitsWithout += 1;
      }
      expect(hitsWithRecall, greaterThan(0));
      expect(hitsWithRecall, greaterThan(hitsWithout));
    });

    test('checkIn surfaces the cusp-phase "been quiet" line only right after a major story beat', () {
      final seenNormalPhase = <String>{};
      final seenCusp = <String>{};
      for (var i = 0; i < 20; i++) {
        final normal = CareerController();
        addTearDown(normal.dispose);
        normal.relationships['mama']!.suspicion = 40;
        normal.sendIntent('mama', ConversationIntent.checkIn);
        seenNormalPhase.add(normal.personalThreads['mama']!.last.text);

        final cusp = CareerController();
        addTearDown(cusp.dispose);
        cusp.relationships['mama']!.suspicion = 40;
        cusp.recentStoryEvent = 'close_call'; // forces LevelPhase.cusp for this one turn
        cusp.sendIntent('mama', ConversationIntent.checkIn);
        seenCusp.add(cusp.personalThreads['mama']!.last.text);
      }
      expect(seenNormalPhase, isNot(contains(phaseLine)));
      expect(seenCusp, contains(phaseLine));
    });

    test("RecentConversationMemory (Phase 11) ages out low-importance turns after ~3 turns, keeps critical ones permanently", () {
      final g = CareerController();
      addTearDown(g.dispose);
      final rel = g.relationships['mama']!;
      g.sendIntent('mama', ConversationIntent.greet); // low importance, turn 1
      g.devJumpToLevel(5); // unlocks makePeace (critical importance) without disturbing turnCount semantics
      g.sendIntent('mama', ConversationIntent.makePeace); // critical importance -> promoted to permanent memory too, turn 2
      expect(rel.recentConversation.length, 2);
      expect(rel.memories.any((m) => m.kind == MemoryKind.promiseMade), isTrue);

      // Low-importance turns age out relative to turnCount (Phase 11), not
      // the calendar — advancing days alone (as the old day-based version of
      // this test did) no longer does anything for a low-importance turn.
      // 2 turns elapsed so far (greet at turn 1, makePeace at turn 2) —
      // send just enough more greets to sit one turn short of the window,
      // then one more to cross it.
      for (var i = 0; i < CareerController.kLowImportanceTurnWindow - 2; i++) {
        g.sendIntent('mama', ConversationIntent.greet);
      }
      expect(rel.recentConversation.any((e) => e.intent == ConversationIntent.greet && e.turn == 1), isTrue);
      g.sendIntent('mama', ConversationIntent.greet); // crosses kLowImportanceTurnWindow
      expect(rel.recentConversation.any((e) => e.intent == ConversationIntent.greet && e.turn == 1), isFalse);
      expect(rel.recentConversation.any((e) => e.intent == ConversationIntent.makePeace), isTrue); // critical -> never pruned by age
    });

    test('Explain More wins a tray slot once a topic thread is live', () {
      // Not asserting it's absent on a fresh thread — a harmless option
      // tying for a slot on default state isn't a problem the same way
      // being MISSING once there's something to continue would be. The
      // regression this guards against is the screenshot-reported one:
      // several turns into a live topic, nothing in the tray lets the
      // player continue it.
      final g = CareerController();
      addTearDown(g.dispose);
      final rel = g.relationships['mama']!;
      rel.currentTopic = Topic.plans;
      rel.topicProgress = 2;
      expect(
        g.personalReplyOptions('mama').whereType<IntentChip>().any((c) => c.intent == ConversationIntent.elaborate),
        isTrue,
      );
    });

    test('Explain More wins a tray slot whenever a question is left hanging, regardless of topic', () {
      final g = CareerController();
      addTearDown(g.dispose);
      final rel = g.relationships['mama']!;
      rel.lastQuestionAnswered = false;
      expect(
        g.personalReplyOptions('mama').whereType<IntentChip>().any((c) => c.intent == ConversationIntent.elaborate),
        isTrue,
      );
    });
  });

  group('PendingInteraction (questions/requests/promises)', () {
    // Mama's reaction line is drawn by pickLine() — it's *likely* to be
    // intent-tagged Intent.question after a question-toned reply (see
    // _playerAskedAQuestion's gated lines in data.dart, and intentMatch's
    // 5x boost for a matching intent), but never guaranteed on any single
    // turn. So these run many fresh-controller trials rather than assuming
    // one draw lands on a question-tagged line — the same reason other
    // pickLine-dependent tests in this file do. Fresh controller per trial,
    // not repeated calls on one controller: repeating the identical action
    // trips the consecutive-spam override (personalReplyAction routes to an
    // entirely different, non-question-tagged reaction pool once the same
    // label repeats), which would starve every retry after the first one or
    // two — a real trap this test tripped over before landing on this shape.
    test('mama asking a question opens a pending question interaction, unresolved', () {
      var opened = false;
      for (var trial = 0; trial < 60 && !opened; trial++) {
        final g = CareerController();
        g.personalReplyAction('mama', _wellbeingAction);
        final questions = g.relationships['mama']!.pendingInteractions.where((p) => p.type == InteractionType.question);
        if (questions.isNotEmpty && !questions.last.resolved) opened = true;
        g.dispose();
      }
      expect(opened, isTrue);
    });

    test('a non-dismissal reply to a pending question resolves it', () {
      CareerController? g;
      PendingInteraction? question;
      for (var trial = 0; trial < 60 && question == null; trial++) {
        final candidate = CareerController();
        candidate.personalReplyAction('mama', _wellbeingAction);
        final unresolved = candidate.relationships['mama']!.pendingInteractions
            .where((p) => p.type == InteractionType.question && !p.resolved);
        if (unresolved.isNotEmpty) {
          g = candidate;
          question = unresolved.last;
        } else {
          candidate.dispose();
        }
      }
      expect(question, isNotNull);
      addTearDown(g!.dispose);
      // A different label than _wellbeingAction, so this doesn't trip the
      // consecutive-spam override either.
      g.personalReplyAction('mama', _honestAction); // Intent.statement — a real answer, not a dismissal
      expect(question!.resolved, isTrue);
    });

    test('at most one question interaction is ever unresolved at a time (a fresh one supersedes a stale one)', () {
      // Alternates two distinct Intent.question-tagged actions (different
      // labels, different topics) turn to turn — never repeating the same
      // label back-to-back, so the consecutive-spam override never kicks in
      // and every turn actually gets a real shot at the generic tone pool.
      final pushForAnswers = kPersonalReplyActions.firstWhere((a) => a.label == 'Push for answers');
      for (var trial = 0; trial < 20; trial++) {
        final g = CareerController();
        addTearDown(g.dispose);
        final rel = g.relationships['mama']!;
        for (var turn = 0; turn < 6; turn++) {
          g.personalReplyAction('mama', turn.isEven ? _wellbeingAction : pushForAnswers);
          final stillOpen = rel.pendingInteractions.where((p) => p.type == InteractionType.question && !p.resolved);
          expect(stillOpen.length, lessThanOrEqualTo(1), reason: 'trial $trial, turn $turn');
        }
      }
    });

    test('sending a promise-tagged reply opens a pending promise interaction', () {
      final g = CareerController();
      addTearDown(g.dispose);
      final rel = g.relationships['mama']!;
      g.personalReplyAction('mama', _warmAction); // 'Reassure' -> Intent.promise, deterministic (not pickLine-dependent)
      final opened = rel.pendingInteractions.where((p) => p.type == InteractionType.promise).toList();
      expect(opened, isNotEmpty);
      expect(opened.last.resolved, isFalse);
      expect(opened.last.createdTurn, rel.turnCount); // both read after the same completed turn
    });

    test('a non-promise reply does not open a pending promise interaction', () {
      final g = CareerController();
      addTearDown(g.dispose);
      final rel = g.relationships['mama']!;
      g.personalReplyAction('mama', _honestAction);
      expect(rel.pendingInteractions.where((p) => p.type == InteractionType.promise), isEmpty);
    });

    test('asking for money opens and immediately resolves a pending request interaction', () {
      final g = CareerController();
      addTearDown(g.dispose);
      final rel = g.relationships['mama']!;
      g.resolveMoneyAsk('mama', 50); // <=100 is always granted
      final requests = rel.pendingInteractions.where((p) => p.type == InteractionType.request).toList();
      expect(requests, isNotEmpty);
      expect(requests.last.resolved, isTrue);
      expect(requests.last.topic, Topic.money);
      expect(requests.last.subject, 'money ask');
    });

    test('pendingInteractions is FIFO-capped so a long relationship history does not grow unbounded', () {
      final g = CareerController();
      addTearDown(g.dispose);
      final rel = g.relationships['mama']!;
      for (var i = 0; i < 30; i++) {
        g.personalReplyAction('mama', _wellbeingAction);
        g.personalReplyAction('mama', _honestAction);
      }
      expect(rel.pendingInteractions.length, lessThanOrEqualTo(20));
    });
  });

  group('Promise/request deadlines (Phase 10)', () {
    test('a promise-tagged reply opens its pending promise with a real deadline (not the old informational-only null)', () {
      final g = CareerController();
      addTearDown(g.dispose);
      final rel = g.relationships['mama']!;
      g.personalReplyAction('mama', _warmAction); // 'Reassure' -> Intent.promise
      final opened = rel.pendingInteractions.where((p) => p.type == InteractionType.promise).toList();
      expect(opened, isNotEmpty);
      expect(opened.last.deadlineTurn, opened.last.createdTurn + kDefaultPromiseDeadlineTurns);
    });

    test('an overdue unresolved promise breaks on the next reply to this contact, penalizing reliability and trust', () {
      final g = CareerController();
      addTearDown(g.dispose);
      final rel = g.relationships['mama']!;
      g.personalReplyAction('mama', _honestAction); // advances turnCount to 1
      rel.pendingInteractions.add(PendingInteraction(
        type: InteractionType.promise,
        subject: 'call Grandma',
        createdTurn: rel.turnCount,
        deadlineTurn: 0, // already passed as of the next reply (turnCount is 1 going in)
      ));
      final reliabilityBefore = rel.reliability;
      // A cold reply itself also lowers trust — using it here (rather than
      // a warm one) keeps the break's own trust penalty from being masked by
      // the triggering turn's own tone-driven trust gain, since both land in
      // the same personalReplyAction call as the break check.
      final trustBefore = rel.trust;
      g.personalReplyAction('mama', _coldAction);
      final interaction = rel.pendingInteractions.firstWhere((p) => p.subject == 'call Grandma');
      expect(interaction.resolved, isTrue);
      expect(interaction.broken, isTrue);
      expect(rel.reliability, lessThan(reliabilityBefore));
      expect(rel.trust, lessThan(trustBefore));
    });

    test('a promise not yet past its deadline is untouched by the break check', () {
      final g = CareerController();
      addTearDown(g.dispose);
      final rel = g.relationships['mama']!;
      rel.pendingInteractions.add(PendingInteraction(
        type: InteractionType.promise,
        subject: 'call Grandma',
        createdTurn: rel.turnCount,
        deadlineTurn: rel.turnCount + 50,
      ));
      g.personalReplyAction('mama', _greetAction);
      final interaction = rel.pendingInteractions.firstWhere((p) => p.subject == 'call Grandma');
      expect(interaction.resolved, isFalse);
      expect(interaction.broken, isFalse);
    });

    test('a pending question is never marked broken by the deadline check', () {
      final g = CareerController();
      addTearDown(g.dispose);
      final rel = g.relationships['mama']!;
      rel.pendingInteractions.add(PendingInteraction(
        type: InteractionType.question,
        createdTurn: rel.turnCount,
        deadlineTurn: 0,
      ));
      g.personalReplyAction('mama', _greetAction);
      expect(rel.pendingInteractions.first.broken, isFalse);
    });

    test('fulfilling a promise before its deadline resolves it without breaking it', () {
      final followedThrough = kPersonalReplyActions.firstWhere((a) => a.label == 'Followed through');
      final g = CareerController();
      addTearDown(g.dispose);
      final rel = g.relationships['mama']!;
      g.personalReplyAction('mama', _warmAction); // opens a promise with a fresh, far-off deadline
      g.personalReplyAction('mama', followedThrough);
      final resolved = rel.pendingInteractions.where((p) => p.type == InteractionType.promise).last;
      expect(resolved.resolved, isTrue);
      expect(resolved.broken, isFalse);
    });

    test('fulfillsPromise also resolves a pending request (e.g. a mama-initiated "promise me" ask), not just a self-made promise', () {
      final followedThrough = kPersonalReplyActions.firstWhere((a) => a.label == 'Followed through');
      final g = CareerController();
      addTearDown(g.dispose);
      final rel = g.relationships['mama']!;
      rel.pendingInteractions.add(PendingInteraction(
        type: InteractionType.request,
        subject: 'call Grandma',
        createdTurn: rel.turnCount,
        deadlineTurn: rel.turnCount + 50,
      ));
      g.personalReplyAction('mama', followedThrough);
      final request = rel.pendingInteractions.firstWhere((p) => p.subject == 'call Grandma');
      expect(request.resolved, isTrue);
      expect(request.broken, isFalse);
    });

    test('the mama openers pool includes a requestsPromise line asking her son to call his grandmother', () {
      final line = kRelationshipContent['mama']!.openers.firstWhere(
        (l) => l.requestsPromise,
        orElse: () => throw StateError('no requestsPromise opener found'),
      );
      expect(line.subject, 'call Grandma');
      expect(line.topic, Topic.family);
    });
  });

  group('Memory tiers (Phase 11)', () {
    test('a legacy free-text-derived turn (no ConversationIntent) is low importance', () {
      final g = CareerController();
      addTearDown(g.dispose);
      g.personalReplyAction('mama', _honestAction); // conversationIntent == null
      expect(g.relationships['mama']!.recentConversation.last.importance, MemoryImportance.low);
    });

    test('pure social-lubricant intents (greet, thank, sayGoodbye, joke, sarcasm) are low importance', () {
      const lowIntents = {
        ConversationIntent.greet,
        ConversationIntent.thank,
        ConversationIntent.sayGoodbye,
        ConversationIntent.joke,
        ConversationIntent.sarcasm,
      };
      for (final intent in lowIntents) {
        final g = CareerController();
        addTearDown(g.dispose);
        g.sendIntent('mama', intent);
        expect(g.relationships['mama']!.recentConversation.last.importance, MemoryImportance.low, reason: '$intent');
      }
    });

    test('conversational-continuity intents (checkIn, elaborate, deflect) are medium importance', () {
      const mediumIntents = {ConversationIntent.checkIn, ConversationIntent.elaborate, ConversationIntent.deflect};
      for (final intent in mediumIntents) {
        final g = CareerController();
        addTearDown(g.dispose);
        g.sendIntent('mama', intent);
        expect(g.relationships['mama']!.recentConversation.last.importance, MemoryImportance.medium, reason: '$intent');
      }
    });

    test('a real-exchange intent (apologize, insult, askAboutFamily) is high importance', () {
      const highIntents = {ConversationIntent.apologize, ConversationIntent.insult, ConversationIntent.askAboutFamily};
      for (final intent in highIntents) {
        final g = CareerController();
        addTearDown(g.dispose);
        g.sendIntent('mama', intent);
        expect(g.relationships['mama']!.recentConversation.last.importance, MemoryImportance.high, reason: '$intent');
      }
    });

    test('a milestone intent (confront, questionLoyalty, makePeace) is critical importance and is promoted to a permanent memory', () {
      final g = CareerController();
      addTearDown(g.dispose);
      g.devJumpToLevel(5); // unlocks makePeace/confront/questionLoyalty
      final rel = g.relationships['mama']!;
      g.sendIntent('mama', ConversationIntent.confront);
      expect(rel.recentConversation.last.importance, MemoryImportance.critical);
      expect(rel.memories.any((m) => m.kind == MemoryKind.deepConfession), isTrue);
    });

    test('asking for money is high importance (a real exchange, not idle chatter)', () {
      final g = CareerController();
      addTearDown(g.dispose);
      g.resolveMoneyAsk('mama', 50);
      final rel = g.relationships['mama']!;
      expect(rel.recentConversation.every((e) => e.importance == MemoryImportance.high), isTrue);
    });

    test('a medium-importance turn survives past kLowImportanceTurnWindow but ages out at kMediumImportanceTurnWindow', () {
      final g = CareerController();
      addTearDown(g.dispose);
      final rel = g.relationships['mama']!;
      g.sendIntent('mama', ConversationIntent.checkIn); // turn 1, medium
      for (var i = 0; i < CareerController.kMediumImportanceTurnWindow - 1; i++) {
        g.sendIntent('mama', ConversationIntent.greet); // low-importance filler turns, advancing turnCount only
      }
      // Still within the medium window (age == kMediumImportanceTurnWindow - 1).
      expect(rel.recentConversation.any((e) => e.turn == 1), isTrue);
      g.sendIntent('mama', ConversationIntent.greet); // crosses kMediumImportanceTurnWindow
      expect(rel.recentConversation.any((e) => e.turn == 1), isFalse);
    });

    test('a high-importance turn ages out after kHighImportanceDayWindow days, not turns', () {
      final g = CareerController();
      addTearDown(g.dispose);
      final rel = g.relationships['mama']!;
      g.sendIntent('mama', ConversationIntent.apologize); // high importance
      final createdDay = rel.recentConversation.last.day;

      // Many turns pass same-day — a high-importance turn is day-granular,
      // so turn count alone (even well past kLowImportanceTurnWindow/
      // kMediumImportanceTurnWindow) never prunes it.
      for (var i = 0; i < 20; i++) {
        g.sendIntent('mama', ConversationIntent.greet);
      }
      expect(rel.recentConversation.any((e) => e.turn == 1), isTrue);

      g.day += CareerController.kHighImportanceDayWindow;
      g.sendIntent('mama', ConversationIntent.greet); // any new turn re-triggers the prune check
      expect(rel.recentConversation.any((e) => e.day == createdDay && e.turn == 1), isFalse);
    });
  });

  group('Precise callbacks (Phase 12)', () {
    test('the elaborate/driving phrasing establishes coverJob AND sets topicSubject (previously latent — subject was never forwarded before)', () {
      CareerController? found;
      for (var trial = 0; trial < 100 && found == null; trial++) {
        final g = CareerController();
        g.sendIntent('mama', ConversationIntent.elaborate);
        if (g.relationships['mama']!.facts['coverJob']?.value == 'driving') {
          found = g;
        } else {
          g.dispose();
        }
      }
      expect(found, isNotNull);
      addTearDown(found!.dispose);
      expect(found.relationships['mama']!.topicSubject, 'coverJob');
    });

    test('the "How\'s driving going" callback opener only fires once the fact, a recent matching event, and the live thread subject all line up', () {
      const calloutText = "Driving all day, huh? Please tell me you're being careful out there.";
      bool everFiresInOneTick({required bool withFact, required bool withEvent, required bool withSubject}) {
        for (var trial = 0; trial < 200; trial++) {
          final g = CareerController();
          g.devJumpToLevel(4);
          final rel = g.relationships['mama']!;
          if (withFact) {
            rel.facts['coverJob'] = ConversationFact(key: 'coverJob', value: 'driving', firstMentionedTurn: 1, lastConfirmedTurn: 1);
          }
          if (withEvent) {
            rel.recentConversation.add(ConversationEvent(
              tone: ReplyTone.honest, intensity: 0.5, fromMe: true, turn: 1, day: g.day, level: g.level, topic: Topic.plans,
            ));
          }
          if (withSubject) {
            rel.currentTopic = Topic.plans;
            rel.topicSubject = 'coverJob';
          }
          _tick(g);
          final fired = g.personalThreads['mama']!.any((m) => m.text == calloutText);
          g.dispose();
          if (fired) return true;
        }
        return false;
      }

      expect(everFiresInOneTick(withFact: true, withEvent: true, withSubject: true), isTrue);
      expect(everFiresInOneTick(withFact: false, withEvent: true, withSubject: true), isFalse, reason: 'missing requiredFacts');
      expect(everFiresInOneTick(withFact: true, withEvent: false, withSubject: true), isFalse, reason: 'missing requiredEventTopic');
      expect(everFiresInOneTick(withFact: true, withEvent: true, withSubject: false), isFalse, reason: 'missing requiredSubject');
    });
  });

  group('Character personality (Phase 15)', () {
    test('each personal contact carries its own distinct CharacterPersonality, not the neutral default', () {
      for (final p in kPersonalContacts) {
        expect(p.personality, isNot(same(kNeutralPersonality)), reason: p.id);
      }
    });

    test("Kiko (the funny best friend) has the highest humor on the roster", () {
      final humors = {for (final p in kPersonalContacts) p.id: p.personality.humor};
      expect(humors['friend'], greaterThan(humors['mama']!));
      expect(humors['friend'], greaterThan(humors['oldfriend']!));
      expect(humors['friend'], greaterThanOrEqualTo(humors.values.reduce((a, b) => a > b ? a : b)));
    });

    test("Mamá has the highest warmth on the roster", () {
      final warmths = {for (final p in kPersonalContacts) p.id: p.personality.warmth};
      expect(warmths['mama'], greaterThanOrEqualTo(warmths.values.reduce((a, b) => a > b ? a : b)));
    });

    test('sending mama a joke reaches an isJoke-tagged reaction line at least sometimes (personality threading did not break the joke pool)', () {
      var sawJokeLine = false;
      for (var trial = 0; trial < 100 && !sawJokeLine; trial++) {
        final g = CareerController();
        g.sendIntent('mama', ConversationIntent.joke);
        final reply = g.personalThreads['mama']!.last.text;
        if (kMamaIntentReactions[ConversationIntent.joke]![ReplyTone.warm]!.any((l) => l.isJoke && l.text == reply)) {
          sawJokeLine = true;
        }
        g.dispose();
      }
      expect(sawJokeLine, isTrue);
    });
  });

  group('Conversation depth (Phase 16)', () {
    test('a fresh relationship starts at smallTalk', () {
      final g = CareerController();
      addTearDown(g.dispose);
      expect(g.relationships['mama']!.conversationDepth, ConversationDepth.smallTalk);
    });

    test('a moderate-intensity money reply deepens the conversation to personal', () {
      final g = CareerController();
      addTearDown(g.dispose);
      final talkAboutMoney = kPersonalReplyActions.firstWhere((a) => a.label == 'Talk about money'); // Topic.money, intensity 0.6
      g.personalReplyAction('mama', talkAboutMoney);
      expect(g.relationships['mama']!.conversationDepth, ConversationDepth.personal);
    });

    test('a high-intensity, topic-tagged reply deepens the conversation to serious', () {
      final g = CareerController();
      addTearDown(g.dispose);
      final apologizeForReal = kPersonalReplyActions.firstWhere((a) => a.label == 'Apologize for real'); // tagged topics, intensity 0.9
      g.personalReplyAction('mama', apologizeForReal);
      expect(g.relationships['mama']!.conversationDepth, ConversationDepth.serious);
    });

    test('isVulnerableDisclosure floors the conversation at vulnerable regardless of intensity', () {
      final g = CareerController();
      addTearDown(g.dispose);
      final openUp = kPersonalReplyActions.firstWhere((a) => a.label == 'Open up'); // isVulnerableDisclosure: true, intensity only 0.6
      g.personalReplyAction('mama', openUp);
      expect(g.relationships['mama']!.conversationDepth, ConversationDepth.vulnerable);
    });

    test('depth de-escalates only one step per turn after a deep moment, not an instant reset', () {
      final g = CareerController();
      addTearDown(g.dispose);
      final rel = g.relationships['mama']!;
      final openUp = kPersonalReplyActions.firstWhere((a) => a.label == 'Open up');
      g.personalReplyAction('mama', openUp);
      expect(rel.conversationDepth, ConversationDepth.vulnerable);
      g.personalReplyAction('mama', _greetAction); // Topic.greeting -> classifies as smallTalk
      expect(rel.conversationDepth, ConversationDepth.serious); // stepped down one level, not straight to smallTalk
    });

    test('the vulnerable-gated "glad you told me" reaction line is unreachable during ordinary wellbeing chatter, reachable once the conversation is actually vulnerable', () {
      const gatedLine = "That's a heavy thing to carry. I'm glad you told me instead of hiding it.";
      // Ordinary wellbeing chatter (classifies as casual) never surfaces it, however many trials.
      for (var i = 0; i < 30; i++) {
        final g = CareerController();
        g.personalReplyAction('mama', _wellbeingAction);
        expect(g.personalThreads['mama']!.last.text, isNot(gatedLine), reason: 'trial $i');
        g.dispose();
      }
      // Once the conversation is actually vulnerable, it's reachable — one
      // candidate among several wellbeing-tagged honest reactions, so retry.
      var sawGatedLine = false;
      final openUp = kPersonalReplyActions.firstWhere((a) => a.label == 'Open up');
      for (var i = 0; i < 200 && !sawGatedLine; i++) {
        final g = CareerController();
        g.personalReplyAction('mama', openUp);
        if (g.personalThreads['mama']!.last.text == gatedLine) sawGatedLine = true;
        g.dispose();
      }
      expect(sawGatedLine, isTrue);
    });
  });

  group('Response Planner (Phase 5)', () {
    test('lastResponsePlan is populated after a reply', () {
      final g = CareerController();
      addTearDown(g.dispose);
      g.personalReplyAction('mama', _wellbeingAction);
      expect(g.relationships['mama']!.lastResponsePlan, isNotNull);
    });

    test('asking mama a direct question plans as answerQuestion', () {
      final g = CareerController();
      addTearDown(g.dispose);
      g.personalReplyAction('mama', _wellbeingAction); // Intent.question
      expect(g.relationships['mama']!.lastResponsePlan!.intent, ResponseIntent.answerQuestion);
    });

    test('a loaded ConversationIntent (Confront) plans as challenge even mid-thread', () {
      // Needs conversationIntent set, which only intent-chip-originated
      // actions carry (see PersonalReplyAction.conversationIntent's doc
      // comment) — kPersonalReplyActions' legacy catalog entries (including
      // ones that read like a confrontation, e.g. 'Push for answers') are
      // never tagged this way, so this constructs one directly instead.
      const confrontAction = PersonalReplyAction(
        'Confront',
        phrasings: [DialogueLine("Something's not adding up. Explain it.")],
        tone: ReplyTone.cold,
        topics: {Topic.suspicion},
        intent: Intent.statement,
        conversationIntent: ConversationIntent.confront,
      );
      final g = CareerController();
      addTearDown(g.dispose);
      g.personalReplyAction('mama', confrontAction);
      expect(g.relationships['mama']!.lastResponsePlan!.intent, ResponseIntent.challenge);
    });

    test('rel.thread reflects the live topic/stage after a reply, and is null before any thread exists', () {
      final g = CareerController();
      addTearDown(g.dispose);
      final rel = g.relationships['mama']!;
      expect(rel.thread, isNull);
      g.personalReplyAction('mama', _wellbeingAction);
      g.personalReplyAction('mama', _wellbeingAction);
      final thread = rel.thread;
      expect(thread, isNotNull);
      expect(thread!.topic, Topic.wellbeing);
      expect(thread.stage, 2);
    });

    test(
      'a genuinely answered question makes the reaction more likely to draw from '
      'acknowledgesAnsweredQuestion-tagged lines than when nothing was pending',
      () {
        // Regression-guard for the exact mistake this session made and caught:
        // this must be a SOFT frequency shift, not a guarantee — a hard
        // pool-narrowing here (mirroring tone-shift's) was tried and reverted
        // because ResponseIntent.answerQuestion fires on nearly every
        // question-asking turn, which would have excluded the entire existing
        // pool of question-answering content instead of just nudging it.
        final answerTagged = kPersonalReactions['mama']![ReplyTone.honest]!
            .where((l) => l.acknowledgesAnsweredQuestion)
            .map((l) => l.text)
            .toSet();
        expect(answerTagged, isNotEmpty);

        var hitsWithAnswer = 0;
        var hitsWithout = 0;
        const trials = 80;
        for (var i = 0; i < trials; i++) {
          // "With": retry (fresh controllers, per this file's established
          // pattern for pickLine-dependent setup) until a real pending
          // question opens, then answer it honestly.
          CareerController? withPending;
          for (var attempt = 0; attempt < 20 && withPending == null; attempt++) {
            final candidate = CareerController();
            candidate.personalReplyAction('mama', _wellbeingAction);
            if (!candidate.relationships['mama']!.lastQuestionAnswered) {
              withPending = candidate;
            } else {
              candidate.dispose();
            }
          }
          if (withPending != null) {
            withPending.personalReplyAction('mama', _honestAction);
            if (answerTagged.contains(withPending.personalThreads['mama']!.last.text)) hitsWithAnswer++;
            withPending.dispose();
          }

          // "Without": a fresh controller, nothing pending, straight to honest.
          final withoutPending = CareerController();
          withoutPending.personalReplyAction('mama', _honestAction);
          if (answerTagged.contains(withoutPending.personalThreads['mama']!.last.text)) hitsWithout++;
          withoutPending.dispose();
        }
        expect(hitsWithAnswer, greaterThan(hitsWithout));
      },
    );
  });

  group('ConversationFact (Phase 6)', () {
    test('sending the elaborate phrasing that establishes coverJob=driving records the fact', () {
      // The elaborate chip's phrasings are topic-tiered (see pickLine's
      // _topicTier) — putting the thread on Topic.plans first, same as
      // other tests in this file do by setting currentTopic directly,
      // favors its two Topic.plans candidates over every other topic's.
      // Still probabilistic between those two, so retry with fresh
      // controllers per this file's established pattern.
      CareerController? g;
      for (var attempt = 0; attempt < 60 && g == null; attempt++) {
        final candidate = CareerController();
        candidate.relationships['mama']!.currentTopic = Topic.plans;
        candidate.sendIntent('mama', ConversationIntent.elaborate);
        if (candidate.relationships['mama']!.facts['coverJob']?.value == 'driving') {
          g = candidate;
        } else {
          candidate.dispose();
        }
      }
      expect(g, isNotNull);
      addTearDown(g!.dispose);
      final fact = g.relationships['mama']!.facts['coverJob']!;
      expect(fact.value, 'driving');
      expect(fact.confidence, 1.0);
    });

    test('a requiredFacts-gated reaction line is unreachable without the fact, reachable once it is known', () {
      const gatedLine = "Driving all day, huh? At least you're out and about, not stuck behind some desk.";

      // Without the fact: requiredFacts is a hard eligibility gate (unlike
      // anyRequiredMemories/recallMatch's soft suppression), so this line
      // should never appear — not just rarely.
      for (var i = 0; i < 40; i++) {
        final g = CareerController();
        g.relationships['mama']!.currentTopic = Topic.plans;
        g.personalReplyAction('mama', _honestAction); // empty .topics -> holds Topic.plans, see advanceTopic
        expect(g.personalThreads['mama']!.last.text, isNot(gatedLine), reason: 'trial $i');
        g.dispose();
      }

      // With the fact known, it becomes reachable — one candidate among
      // several Topic.plans honest lines, so retry across trials rather
      // than asserting on a single draw.
      var sawGatedLine = false;
      for (var i = 0; i < 200 && !sawGatedLine; i++) {
        final g = CareerController();
        final rel = g.relationships['mama']!;
        rel.currentTopic = Topic.plans;
        recordFact(rel.facts, 'coverJob', 'driving', 1);
        g.personalReplyAction('mama', _honestAction);
        if (g.personalThreads['mama']!.last.text == gatedLine) sawGatedLine = true;
        g.dispose();
      }
      expect(sawGatedLine, isTrue);
    });
  });

  group('Contradictions (Phase 8)', () {
    test('a fact that later contradicts drives the plan and routes the reaction to kMamaContradictionReactions', () {
      // Constructed directly rather than via sendIntent/the elaborate chip's
      // real phrasings — those are useful for proving the real content is
      // wired correctly (see the next test), but sending the same chip label
      // twice in a row trips this file's other well-known trap (consecutive-
      // spam routing overriding the reaction pool entirely, see the
      // PendingInteraction group's own comment on this). Different labels
      // here sidestep that so this test can be a fully deterministic proof
      // of the mechanism itself.
      const drivingAction = PersonalReplyAction(
        'Cover story A',
        phrasings: [DialogueLine("It's driving.")],
        tone: ReplyTone.honest,
        intent: Intent.statement,
        establishesFacts: {'coverJob': 'driving'},
      );
      const restaurantAction = PersonalReplyAction(
        'Cover story B',
        phrasings: [DialogueLine("Actually it's a restaurant now.")],
        tone: ReplyTone.honest,
        intent: Intent.statement,
        establishesFacts: {'coverJob': 'restaurant'},
      );

      final g = CareerController();
      addTearDown(g.dispose);
      final rel = g.relationships['mama']!;

      g.personalReplyAction('mama', drivingAction);
      expect(rel.facts['coverJob']!.value, 'driving');
      expect(rel.lastResponsePlan!.contradiction, isNull);

      g.personalReplyAction('mama', restaurantAction);
      expect(rel.facts['coverJob']!.value, 'restaurant');
      final contradiction = rel.lastResponsePlan!.contradiction;
      expect(contradiction, isNotNull);
      expect(contradiction!.key, 'coverJob');
      expect(contradiction.oldValue, 'driving');
      expect(contradiction.newValue, 'restaurant');

      final expectedPool = kMamaContradictionReactions[rel.lastResponsePlan!.intent]!.map((l) => l.text).toSet();
      expect(expectedPool, contains(g.personalThreads['mama']!.last.text));
    });

    test('the elaborate chip carries two coverJob phrasings that would genuinely contradict each other', () {
      final plansPhrasings = kIntentChips
          .firstWhere((c) => c.intent == ConversationIntent.elaborate)
          .phrasings
          .where((l) => l.topic == Topic.plans && l.establishesFacts?.containsKey('coverJob') == true)
          .toList();
      expect(plansPhrasings.length, 2);
      final values = plansPhrasings.map((l) => l.establishesFacts!['coverJob']).toSet();
      expect(values, {'driving', 'restaurant'});
    });
  });

  group('Behavioral reputation (Phase 9)', () {
    test('honesty rises after a sustained honest-tone pattern, on the periodic tick — not immediately per-turn', () {
      final g = CareerController();
      addTearDown(g.dispose);
      g.devJumpToLevel(4); // _tick() drives level 4's monthly cycle — see its own doc comment
      final rel = g.relationships['mama']!;
      for (var i = 0; i < 3; i++) {
        g.personalReplyAction('mama', _honestAction);
      }
      expect(rel.honesty, 50); // unchanged — the pattern is recorded, not yet evaluated
      _tick(g);
      expect(rel.honesty, greaterThan(50));
    });

    test('honesty does not move on a mixed-tone history (no sustained pattern)', () {
      final g = CareerController();
      addTearDown(g.dispose);
      g.devJumpToLevel(4);
      final rel = g.relationships['mama']!;
      g.personalReplyAction('mama', _honestAction);
      g.personalReplyAction('mama', _coldAction);
      g.personalReplyAction('mama', _honestAction);
      _tick(g);
      expect(rel.honesty, 50);
    });

    test('a dodge pattern raises suspicion beyond whatever a single dodge already would', () {
      final g = CareerController();
      addTearDown(g.dispose);
      final rel = g.relationships['mama']!;
      rel.lastQuestionAnswered = false; // a question is pending going into both dodges
      g.personalReplyAction('mama', _coldAction);
      final afterFirstDodge = rel.suspicion;
      rel.lastQuestionAnswered = false; // a fresh question pending for the second dodge too
      g.personalReplyAction('mama', _coldAction);
      // The pattern-specific nudge (nudgeSuspicionFromDodgePattern) only
      // fires at consecutiveDodgeCount >= 2, i.e. the second dodge — so the
      // jump from dodge 1 to dodge 2 should exceed a typical single-dodge
      // increment, not just repeat it.
      expect(rel.consecutiveDodgeCount, 2);
      expect(rel.suspicion, greaterThan(afterFirstDodge));
    });

    test('consecutiveDodgeCount resets on a non-dodge reply', () {
      final g = CareerController();
      addTearDown(g.dispose);
      final rel = g.relationships['mama']!;
      rel.lastQuestionAnswered = false;
      g.personalReplyAction('mama', _coldAction);
      expect(rel.consecutiveDodgeCount, 1);
      g.personalReplyAction('mama', _honestAction);
      expect(rel.consecutiveDodgeCount, 0);
    });

    test('fulfilling a promise resolves it, raises reliability and trust', () {
      final followedThrough = kPersonalReplyActions.firstWhere((a) => a.label == 'Followed through');
      final g = CareerController();
      addTearDown(g.dispose);
      final rel = g.relationships['mama']!;

      g.personalReplyAction('mama', _warmAction); // 'Reassure' -> Intent.promise, opens a pending promise
      final openPromise = rel.pendingInteractions.where((p) => p.type == InteractionType.promise && !p.resolved);
      expect(openPromise, isNotEmpty);
      final trustBefore = rel.trust;

      g.personalReplyAction('mama', followedThrough);
      expect(rel.reliability, closeTo(51.0, 0.001));
      // Not an exact delta check — 'Followed through' is itself honest-toned,
      // so the normal per-tone trust delta (switch (action.tone) in
      // personalReplyAction) also fires on top of fulfillsPromise's own +0.5;
      // this only confirms trust moved, which is what fulfillsPromise adds.
      expect(rel.trust, greaterThan(trustBefore));
      expect(rel.pendingInteractions.where((p) => p.type == InteractionType.promise && !p.resolved), isEmpty);
    });

    test('a prompt reply raises responsiveness; a late one lowers it', () {
      final g = CareerController();
      addTearDown(g.dispose);
      final rel = g.relationships['mama']!;
      g.personalReplyAction('mama', _honestAction); // daysSinceReply is 0 going in -> prompt
      expect(rel.responsiveness, closeTo(51.0, 0.001));

      rel.daysSinceReply = 5; // simulate having gone quiet for a while
      g.personalReplyAction('mama', _honestAction);
      expect(rel.responsiveness, closeTo(50.0, 0.001)); // net: +1 then -1
    });

    test('the honestyMin-gated reaction line is unreachable below the threshold, reachable once earned', () {
      const gatedLine = "You know, you've really been good about telling me the truth lately. It means a lot.";
      // Below threshold: a hard eligibility gate, so this should never appear.
      for (var i = 0; i < 30; i++) {
        final g = CareerController();
        g.relationships['mama']!.honesty = 64;
        g.personalReplyAction('mama', _honestAction);
        expect(g.personalThreads['mama']!.last.text, isNot(gatedLine), reason: 'trial $i');
        g.dispose();
      }
      // At/above threshold: reachable — one candidate among several honest
      // lines, so retry across trials rather than asserting on one draw.
      var sawGatedLine = false;
      for (var i = 0; i < 200 && !sawGatedLine; i++) {
        final g = CareerController();
        g.relationships['mama']!.honesty = 65;
        g.personalReplyAction('mama', _honestAction);
        if (g.personalThreads['mama']!.last.text == gatedLine) sawGatedLine = true;
        g.dispose();
      }
      expect(sawGatedLine, isTrue);
    });
  });
}
