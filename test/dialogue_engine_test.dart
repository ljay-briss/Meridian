import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:meridian_private/dialogue_engine.dart';

DialogueContext _ctx({
  double mood = 0,
  double closeness = 50,
  double trust = 50,
  double suspicion = 0,
  int daysSinceReply = 0,
  List<ReplyTone> recentTones = const [],
  List<MemoryEvent> memories = const [],
  Map<String, ConversationFact> facts = const {},
  double honesty = 50,
  double reliability = 50,
  double responsiveness = 50,
}) =>
    DialogueContext(
      mood: mood,
      closeness: closeness,
      trust: trust,
      suspicion: suspicion,
      daysSinceReply: daysSinceReply,
      recentTones: recentTones,
      memories: memories,
      facts: facts,
      honesty: honesty,
      reliability: reliability,
      responsiveness: responsiveness,
    );

void main() {
  group('pickLine eligibility', () {
    test('never returns a line whose when() is false', () {
      final rng = Random(1);
      final pool = [
        const DialogueLine('always'),
        DialogueLine('never', when: (ctx) => false),
      ];
      final ctx = _ctx();
      for (var i = 0; i < 200; i++) {
        final line = pickLine(rng, pool, ctx, currentDay: 1);
        expect(line!.text, 'always');
      }
    });

    test('returns null when nothing in the pool is eligible', () {
      final rng = Random(3);
      final pool = [DialogueLine('never', when: (ctx) => false)];
      expect(pickLine(rng, pool, _ctx(), currentDay: 1), isNull);
    });

    test('moodMin/moodMax gate eligibility', () {
      final rng = Random(4);
      final pool = [const DialogueLine('cheerful', moodMin: 20)];
      expect(pickLine(rng, pool, _ctx(mood: 10), currentDay: 1), isNull);
      expect(pickLine(rng, pool, _ctx(mood: 30), currentDay: 1)!.text, 'cheerful');
    });

    test('trustMin/trustMax gate eligibility', () {
      final rng = Random(5);
      final pool = [const DialogueLine('confides', trustMin: 60, trustMax: 100)];
      expect(pickLine(rng, pool, _ctx(trust: 50), currentDay: 1), isNull);
      expect(pickLine(rng, pool, _ctx(trust: 70), currentDay: 1)!.text, 'confides');
    });

    test('suspicionMin/suspicionMax gate eligibility', () {
      final rng = Random(6);
      final pool = [const DialogueLine('accuses', suspicionMin: 80)];
      expect(pickLine(rng, pool, _ctx(suspicion: 50), currentDay: 1), isNull);
      expect(pickLine(rng, pool, _ctx(suspicion: 90), currentDay: 1)!.text, 'accuses');
    });

    test('anyRequiredMemories gates eligibility on presence of any listed kind', () {
      final rng = Random(7);
      final pool = [const DialogueLine('remembers', anyRequiredMemories: {MemoryKind.cutOff})];
      expect(pickLine(rng, pool, _ctx(), currentDay: 1), isNull);
      final withMemory = _ctx(memories: [const MemoryEvent(MemoryKind.cutOff, 1)]);
      expect(pickLine(rng, pool, withMemory, currentDay: 1)!.text, 'remembers');
    });

    test('forbiddenMemories excludes a line once any listed kind is present', () {
      final rng = Random(8);
      final pool = [const DialogueLine('fresh_take', forbiddenMemories: {MemoryKind.cutOff})];
      expect(pickLine(rng, pool, _ctx(), currentDay: 1)!.text, 'fresh_take');
      final withMemory = _ctx(memories: [const MemoryEvent(MemoryKind.cutOff, 1)]);
      expect(pickLine(rng, pool, withMemory, currentDay: 1), isNull);
    });

    test('requiredFacts gates eligibility, and requires EVERY listed key to match (AND, unlike anyRequiredMemories)', () {
      final rng = Random(20);
      final pool = [const DialogueLine('knows_both', requiredFacts: {'brotherName': 'Marcus', 'coverJob': 'driving'})];
      // Neither fact known yet.
      expect(pickLine(rng, pool, _ctx(), currentDay: 1), isNull);
      // Only one of the two required facts known.
      final oneFact = _ctx(facts: {
        'brotherName': ConversationFact(key: 'brotherName', value: 'Marcus', firstMentionedTurn: 1, lastConfirmedTurn: 1),
      });
      expect(pickLine(rng, pool, oneFact, currentDay: 1), isNull);
      // A fact present under the right key but the WRONG value still fails.
      final wrongValue = _ctx(facts: {
        'brotherName': ConversationFact(key: 'brotherName', value: 'Marcus', firstMentionedTurn: 1, lastConfirmedTurn: 1),
        'coverJob': ConversationFact(key: 'coverJob', value: 'mechanic', firstMentionedTurn: 1, lastConfirmedTurn: 1),
      });
      expect(pickLine(rng, pool, wrongValue, currentDay: 1), isNull);
      // Both facts known with the exact required values.
      final bothFacts = _ctx(facts: {
        'brotherName': ConversationFact(key: 'brotherName', value: 'Marcus', firstMentionedTurn: 1, lastConfirmedTurn: 1),
        'coverJob': ConversationFact(key: 'coverJob', value: 'driving', firstMentionedTurn: 1, lastConfirmedTurn: 1),
      });
      expect(pickLine(rng, pool, bothFacts, currentDay: 1)!.text, 'knows_both');
    });

    test('honestyMin/reliabilityMin/responsivenessMin gate eligibility, same shape as trustMin etc. (Phase 9)', () {
      final rng = Random(21);
      final pool = [const DialogueLine('earned_it', honestyMin: 65, reliabilityMin: 60, responsivenessMin: 55)];
      expect(pickLine(rng, pool, _ctx(honesty: 65, reliability: 60, responsiveness: 55), currentDay: 1)!.text, 'earned_it');
      expect(pickLine(rng, pool, _ctx(honesty: 64, reliability: 60, responsiveness: 55), currentDay: 1), isNull);
      expect(pickLine(rng, pool, _ctx(honesty: 65, reliability: 59, responsiveness: 55), currentDay: 1), isNull);
      expect(pickLine(rng, pool, _ctx(honesty: 65, reliability: 60, responsiveness: 54), currentDay: 1), isNull);
    });

    test('progressionMin/progressionMax gate eligibility on topicProgress', () {
      final rng = Random(9);
      const pool = [DialogueLine('deepens', progressionMin: 2)];
      const shallow = DialogueContext(
        mood: 0, closeness: 50, trust: 50, suspicion: 0, daysSinceReply: 0,
        recentTones: [], memories: [], topicProgress: 1,
      );
      const deep = DialogueContext(
        mood: 0, closeness: 50, trust: 50, suspicion: 0, daysSinceReply: 0,
        recentTones: [], memories: [], topicProgress: 2,
      );
      expect(pickLine(rng, pool, shallow, currentDay: 1), isNull);
      expect(pickLine(rng, pool, deep, currentDay: 1)!.text, 'deepens');
    });
  });

  group('pickLine FinalWeight scoring', () {
    test('a just-used line is picked less often than an unused one of equal weight', () {
      final rng = Random(42);
      final pool = [const DialogueLine('used'), const DialogueLine('fresh')];
      final ctx = _ctx();
      var usedCount = 0;
      const trials = 4000;
      for (var i = 0; i < trials; i++) {
        final line = pickLine(rng, pool, ctx, currentDay: 10, recentLineHistory: const ['used']);
        if (line!.text == 'used') usedCount++;
      }
      // recentUses=1 -> 10% penalty vs a line with no recent-use/day penalty at all.
      expect(usedCount / trials, lessThan(0.5));
    });

    test('a line unused for a long time scores higher than one used yesterday', () {
      final rng = Random(43);
      final pool = [const DialogueLine('stale'), const DialogueLine('recent')];
      final ctx = _ctx();
      var staleCount = 0;
      const trials = 4000;
      for (var i = 0; i < trials; i++) {
        final line = pickLine(
          rng,
          pool,
          ctx,
          currentDay: 20,
          lineLastUsedDay: const {'stale': 1, 'recent': 19},
        );
        if (line!.text == 'stale') staleCount++;
      }
      expect(staleCount / trials, greaterThan(0.5));
    });

    test('weighted pick favors a higher-BaseWeight line roughly proportionally', () {
      final rng = Random(44);
      final pool = [
        const DialogueLine('heavy', weight: 2.0),
        const DialogueLine('light', weight: 1.0),
      ];
      final ctx = _ctx();
      var heavy = 0;
      const trials = 4000;
      for (var i = 0; i < trials; i++) {
        if (pickLine(rng, pool, ctx, currentDay: 1)!.text == 'heavy') heavy++;
      }
      final ratio = heavy / trials;
      expect(ratio, greaterThan(0.55));
      expect(ratio, lessThan(0.78));
    });

    test('ToneMatch favors a line tagged with the player\'s most recent tone', () {
      final rng = Random(45);
      final pool = [
        const DialogueLine('warm_line', tone: ReplyTone.warm),
        const DialogueLine('cold_line', tone: ReplyTone.cold),
      ];
      final ctx = _ctx(recentTones: const [ReplyTone.warm]);
      var warmCount = 0;
      const trials = 4000;
      for (var i = 0; i < trials; i++) {
        if (pickLine(rng, pool, ctx, currentDay: 1)!.text == 'warm_line') warmCount++;
      }
      // same-tone (1.3x) vs. direct-opposite (1.0x) -> clearly favored but not deterministic.
      expect(warmCount / trials, greaterThan(0.5));
    });

    test('an old anyRequiredMemories match weighs a line down relative to a fresh one', () {
      final rng = Random(46);
      final pool = [
        const DialogueLine('stale_memory_line', anyRequiredMemories: {MemoryKind.cutOff}),
        const DialogueLine('fresh_memory_line', anyRequiredMemories: {MemoryKind.heardAboutCutOff}),
      ];
      final ctx = _ctx(memories: [
        const MemoryEvent(MemoryKind.cutOff, 1), // 39 days old at currentDay 40 -> floor 0.1
        const MemoryEvent(MemoryKind.heardAboutCutOff, 38), // 2 days old -> full 1.0
      ]);
      var freshCount = 0;
      const trials = 4000;
      for (var i = 0; i < trials; i++) {
        if (pickLine(rng, pool, ctx, currentDay: 40)!.text == 'fresh_memory_line') freshCount++;
      }
      expect(freshCount / trials, greaterThan(0.8));
    });
  });

  group('recordLineUse', () {
    test('sets lastUsedDay and appends to recentLineHistory, capped at 5', () {
      final lastUsedDay = <String, int>{};
      final history = <String>[];
      for (var i = 0; i < 7; i++) {
        recordLineUse(lastUsedDay, history, DialogueLine('line$i'), i);
      }
      expect(lastUsedDay['line6'], 6);
      expect(history.length, 5);
      expect(history, ['line2', 'line3', 'line4', 'line5', 'line6']);
    });
  });

  group('memoryWeight', () {
    test('full weight within the first 5 days', () {
      expect(memoryWeight(const MemoryEvent(MemoryKind.cutOff, 10), 12), 1.0);
    });

    test('decays toward the 0.1 floor by day 30', () {
      final w = memoryWeight(const MemoryEvent(MemoryKind.cutOff, 0), 40);
      expect(w, 0.1);
    });

    test('monotonically decreases with age past the grace window', () {
      final near = memoryWeight(const MemoryEvent(MemoryKind.cutOff, 0), 10);
      final far = memoryWeight(const MemoryEvent(MemoryKind.cutOff, 0), 20);
      expect(far, lessThan(near));
    });
  });

  group('detectRelationshipType', () {
    test('love: high closeness and trust', () {
      expect(
        detectRelationshipType(closeness: 90, trust: 70, fear: 0, respect: 0, debt: 0),
        RelationshipType.love,
      );
    });

    test('respect: high respect and trust, below love thresholds', () {
      expect(
        detectRelationshipType(closeness: 50, trust: 55, fear: 0, respect: 80, debt: 0),
        RelationshipType.respect,
      );
    });

    test('fear: high fear, low trust', () {
      expect(
        detectRelationshipType(closeness: 50, trust: 20, fear: 80, respect: 0, debt: 0),
        RelationshipType.fear,
      );
    });

    test('trust: high trust, low fear, below love/respect thresholds', () {
      expect(
        detectRelationshipType(closeness: 50, trust: 75, fear: 10, respect: 0, debt: 0),
        RelationshipType.trust,
      );
    });

    test('hatred: low closeness and trust', () {
      expect(
        detectRelationshipType(closeness: 10, trust: 10, fear: 0, respect: 0, debt: 0),
        RelationshipType.hatred,
      );
    });

    test('indebted: high debt, none of the above', () {
      expect(
        detectRelationshipType(closeness: 50, trust: 50, fear: 0, respect: 0, debt: 60),
        RelationshipType.indebted,
      );
    });

    test('neutral: nothing stands out', () {
      expect(
        detectRelationshipType(closeness: 50, trust: 50, fear: 0, respect: 0, debt: 0),
        RelationshipType.neutral,
      );
    });
  });

  group('toneMatch', () {
    test('exact tone match scores 1.3', () {
      expect(toneMatch(ReplyTone.warm, [ReplyTone.warm]), closeTo(1.3, 1e-9));
    });

    test('direct opposite scores 1.0 (no boost)', () {
      expect(toneMatch(ReplyTone.cold, [ReplyTone.warm]), closeTo(1.0, 1e-9));
      expect(toneMatch(ReplyTone.excuse, [ReplyTone.honest]), closeTo(1.0, 1e-9));
    });

    test('everything else scores 1.15', () {
      expect(toneMatch(ReplyTone.vague, [ReplyTone.warm]), closeTo(1.15, 1e-9));
    });

    test('a line with no tone tag is neutral (1.0)', () {
      expect(toneMatch(null, [ReplyTone.warm]), 1.0);
    });

    test('no player tones yet is neutral (1.0)', () {
      expect(toneMatch(ReplyTone.warm, []), 1.0);
    });
  });

  group('topicMatch', () {
    test('a line with no topic tag is neutral (1.0)', () {
      expect(topicMatch(null, Topic.family, {Topic.family}), 1.0);
    });

    test('a line matching the conversation\'s current topic scores highest', () {
      expect(topicMatch(Topic.family, Topic.family, {Topic.family}), closeTo(16.0, 1e-9));
    });

    test('a line matching a topic freshly raised by the player, but not yet current, scores a smaller boost', () {
      expect(topicMatch(Topic.health, Topic.family, {Topic.health}), closeTo(6.0, 1e-9));
    });

    test('a line tagged with a topic that is neither current nor raised scores a heavy penalty', () {
      expect(topicMatch(Topic.money, Topic.family, {Topic.health}), closeTo(0.15, 1e-9));
    });
  });

  group('intentMatch', () {
    test('a line with no intent tag is neutral (1.0)', () {
      expect(intentMatch(null, Intent.question), 1.0);
    });

    test('no player intent yet is neutral (1.0)', () {
      expect(intentMatch(Intent.question, null), 1.0);
    });

    test('matching intent scores 5.0', () {
      expect(intentMatch(Intent.question, Intent.question), closeTo(5.0, 1e-9));
    });

    test('mismatched intent scores 0.3', () {
      expect(intentMatch(Intent.question, Intent.statement), closeTo(0.3, 1e-9));
    });
  });

  group('dodgeMatch', () {
    test('a line that does not acknowledge a dodge is always neutral (1.0)', () {
      expect(dodgeMatch(false, true), 1.0);
      expect(dodgeMatch(false, false), 1.0);
    });

    test('a dodge-acknowledging line is boosted right when a question was just dodged', () {
      expect(dodgeMatch(true, true), closeTo(3.0, 1e-9));
    });

    test('a dodge-acknowledging line is suppressed when nothing was actually dodged', () {
      expect(dodgeMatch(true, false), closeTo(0.5, 1e-9));
    });
  });

  group('toneShiftMatch', () {
    test('a line that does not acknowledge a tone shift is always neutral (1.0)', () {
      expect(toneShiftMatch(false, true), 1.0);
      expect(toneShiftMatch(false, false), 1.0);
    });

    test('a shift-acknowledging line is boosted right when the tone just shifted', () {
      expect(toneShiftMatch(true, true), closeTo(3.0, 1e-9));
    });

    test('a shift-acknowledging line is suppressed when nothing actually shifted', () {
      expect(toneShiftMatch(true, false), closeTo(0.5, 1e-9));
    });
  });

  group('detectToneShift', () {
    test('no prior tone yet -> never a shift', () {
      expect(detectToneShift(previousTone: null, tone: ReplyTone.warm), isFalse);
    });

    test('same tone as last turn -> not a shift', () {
      expect(detectToneShift(previousTone: ReplyTone.warm, tone: ReplyTone.warm), isFalse);
    });

    test('a polar-opposite tone than last turn -> a shift, e.g. warm suddenly turning cold', () {
      expect(detectToneShift(previousTone: ReplyTone.warm, tone: ReplyTone.cold), isTrue);
    });

    test('warm -> honest is natural drift, not a shift', () {
      expect(detectToneShift(previousTone: ReplyTone.warm, tone: ReplyTone.honest), isFalse);
    });

    test('honest -> excuse is a shift, same polar-opposite class as warm <-> cold', () {
      // Regression: detectToneShift used to only recognize warm<->cold/excuse
      // as opposite, even though toneMatch's own _oppositeTonePairs already
      // treated honest/excuse as opposite for scoring purposes — someone
      // being direct and then suddenly making excuses is exactly this kind
      // of polar tell, especially mid-suspicion.
      expect(detectToneShift(previousTone: ReplyTone.honest, tone: ReplyTone.excuse), isTrue);
      expect(detectToneShift(previousTone: ReplyTone.excuse, tone: ReplyTone.honest), isTrue);
    });

    test('vague sits between the poles either direction -> never a shift', () {
      for (final other in [ReplyTone.warm, ReplyTone.honest, ReplyTone.cold, ReplyTone.excuse]) {
        expect(detectToneShift(previousTone: ReplyTone.vague, tone: other), isFalse, reason: '$other');
      }
    });
  });

  group('answeredQuestionMatch', () {
    test('neutral (1.0) for a line that does not acknowledge an answered question', () {
      expect(answeredQuestionMatch(false, true), 1.0);
      expect(answeredQuestionMatch(false, false), 1.0);
    });

    test('boosted (3.0) when a question was genuinely just answered', () {
      expect(answeredQuestionMatch(true, true), 3.0);
    });

    test('suppressed (0.5) when nothing was actually pending/answered', () {
      expect(answeredQuestionMatch(true, false), 0.5);
    });
  });

  group('planResponse', () {
    // Every scenario below constructs the minimal signal set that decides
    // ResponseIntent, per planResponse()'s own documented priority order.
    const openThread = ConversationThread(topic: Topic.wellbeing, stage: 2, unresolved: true);

    test('loaded ConversationIntents win outright, even with a question pending', () {
      const cases = {
        ConversationIntent.confront: ResponseIntent.challenge,
        ConversationIntent.questionLoyalty: ResponseIntent.challenge,
        ConversationIntent.insult: ResponseIntent.challenge,
        ConversationIntent.sarcasm: ResponseIntent.challenge,
        ConversationIntent.apologize: ResponseIntent.apologize,
        ConversationIntent.joke: ResponseIntent.joke,
        ConversationIntent.sayGoodbye: ResponseIntent.closeConversation,
        ConversationIntent.makePeace: ResponseIntent.comfort,
        ConversationIntent.reassure: ResponseIntent.comfort,
      };
      cases.forEach((actionIntent, expected) {
        final plan = planResponse(
          actionIntent: actionIntent,
          questionJustAnswered: true, // should be outranked regardless
          questionJustAsked: true,
          thread: openThread,
          topicJustChanged: true,
          hasCallbackOpportunity: true,
        );
        expect(plan.intent, expected, reason: '$actionIntent');
      });
    });

    test('a genuinely answered question outranks generic topic continuation', () {
      final plan = planResponse(
        actionIntent: null,
        questionJustAnswered: true,
        questionJustAsked: false,
        thread: openThread,
        topicJustChanged: false,
        hasCallbackOpportunity: false,
      );
      expect(plan.intent, ResponseIntent.answerQuestion);
    });

    test('the player asking mama something directly also plans as answerQuestion', () {
      // The reverse direction of the same ResponseIntent — see its own doc
      // comment for why both count.
      final plan = planResponse(
        actionIntent: ConversationIntent.askAboutFamily,
        questionJustAnswered: false,
        questionJustAsked: true,
        thread: null,
        topicJustChanged: false,
        hasCallbackOpportunity: false,
      );
      expect(plan.intent, ResponseIntent.answerQuestion);
    });

    test('elaborate plans as followUp when no question is in play', () {
      final plan = planResponse(
        actionIntent: ConversationIntent.elaborate,
        questionJustAnswered: false,
        questionJustAsked: false,
        thread: openThread,
        topicJustChanged: false,
        hasCallbackOpportunity: false,
      );
      expect(plan.intent, ResponseIntent.followUp);
    });

    test('deflect plans as acknowledge', () {
      final plan = planResponse(
        actionIntent: ConversationIntent.deflect,
        questionJustAnswered: false,
        questionJustAsked: false,
        thread: openThread,
        topicJustChanged: false,
        hasCallbackOpportunity: false,
      );
      expect(plan.intent, ResponseIntent.acknowledge);
    });

    test('a topic switch plans as changeTopic when nothing sharper applies', () {
      final plan = planResponse(
        actionIntent: null,
        questionJustAnswered: false,
        questionJustAsked: false,
        thread: openThread,
        topicJustChanged: true,
        hasCallbackOpportunity: false,
      );
      expect(plan.intent, ResponseIntent.changeTopic);
    });

    test('a live callback opportunity plans as callback when no sharper signal applies', () {
      final plan = planResponse(
        actionIntent: null,
        questionJustAnswered: false,
        questionJustAsked: false,
        thread: openThread,
        topicJustChanged: false,
        hasCallbackOpportunity: true,
      );
      expect(plan.intent, ResponseIntent.callback);
    });

    test('deepening an unresolved thread plans as continueTopic, the weakest fallback ahead of acknowledge', () {
      final plan = planResponse(
        actionIntent: null,
        questionJustAnswered: false,
        questionJustAsked: false,
        thread: openThread, // stage: 2, unresolved: true
        topicJustChanged: false,
        hasCallbackOpportunity: false,
      );
      expect(plan.intent, ResponseIntent.continueTopic);
    });

    test('with no sharper signal and no active thread, plans as acknowledge', () {
      final plan = planResponse(
        actionIntent: null,
        questionJustAnswered: false,
        questionJustAsked: false,
        thread: null,
        topicJustChanged: false,
        hasCallbackOpportunity: false,
      );
      expect(plan.intent, ResponseIntent.acknowledge);
    });

    test('the plan carries the thread\'s topic through for a future selection step to read', () {
      final plan = planResponse(
        actionIntent: null,
        questionJustAnswered: true,
        questionJustAsked: false,
        thread: openThread,
        topicJustChanged: false,
        hasCallbackOpportunity: false,
      );
      expect(plan.topic, Topic.wellbeing);
      expect(plan.thread, openThread);
    });

    group('contradiction handling (Phase 8)', () {
      const aContradiction = ContradictionEvent(key: 'coverJob', oldValue: 'driving', newValue: 'restaurant', turn: 5);

      test('a contradiction resolves to one of challenge/acknowledge/clarify, weighted 30/40/30, given a seeded rng', () {
        final counts = <ResponseIntent, int>{};
        const trials = 3000;
        for (var seed = 0; seed < trials; seed++) {
          final plan = planResponse(
            actionIntent: null,
            questionJustAnswered: false,
            questionJustAsked: false,
            thread: null,
            topicJustChanged: false,
            hasCallbackOpportunity: false,
            contradiction: aContradiction,
            rng: Random(seed),
          );
          counts[plan.intent] = (counts[plan.intent] ?? 0) + 1;
        }
        // Loose bands, not exact — this is checking the split is roughly
        // 30/40/30 and that all three outcomes are actually reachable, not
        // pinning an exact distribution to a specific RNG implementation.
        expect(counts[ResponseIntent.challenge], inInclusiveRange((trials * 0.24).round(), (trials * 0.36).round()));
        expect(counts[ResponseIntent.acknowledge], inInclusiveRange((trials * 0.33).round(), (trials * 0.47).round()));
        expect(counts[ResponseIntent.clarify], inInclusiveRange((trials * 0.24).round(), (trials * 0.36).round()));
      });

      test('every planned outcome carries the ContradictionEvent that drove it', () {
        final plan = planResponse(
          actionIntent: null,
          questionJustAnswered: false,
          questionJustAsked: false,
          thread: null,
          topicJustChanged: false,
          hasCallbackOpportunity: false,
          contradiction: aContradiction,
          rng: Random(1),
        );
        expect(plan.contradiction, aContradiction);
      });

      test('a loaded ConversationIntent still wins outright over a pending contradiction', () {
        final plan = planResponse(
          actionIntent: ConversationIntent.joke,
          questionJustAnswered: false,
          questionJustAsked: false,
          thread: null,
          topicJustChanged: false,
          hasCallbackOpportunity: false,
          contradiction: aContradiction,
          rng: Random(1),
        );
        expect(plan.intent, ResponseIntent.joke);
      });

      test('a contradiction outranks a genuine question exchange', () {
        final plan = planResponse(
          actionIntent: null,
          questionJustAnswered: true,
          questionJustAsked: false,
          thread: null,
          topicJustChanged: false,
          hasCallbackOpportunity: false,
          contradiction: aContradiction,
          rng: Random(1),
        );
        expect(plan.intent, isNot(ResponseIntent.answerQuestion));
        expect(plan.contradiction, aContradiction);
      });

      test('omitting rng still resolves to a valid outcome (defaults to a fresh Random, same pattern as CareerController)', () {
        final plan = planResponse(
          actionIntent: null,
          questionJustAnswered: false,
          questionJustAsked: false,
          thread: null,
          topicJustChanged: false,
          hasCallbackOpportunity: false,
          contradiction: aContradiction,
        );
        expect(
          plan.intent,
          anyOf(ResponseIntent.challenge, ResponseIntent.acknowledge, ResponseIntent.clarify),
        );
      });
    });
  });

  group('advanceTopic', () {
    test('a message with no detected topic holds the thread already in progress', () {
      final result = advanceTopic(currentTopic: Topic.family, currentProgress: 2, messageTopics: const {});
      expect(result.topic, Topic.family);
      expect(result.progress, 2);
    });

    test('mentioning the topic already in play deepens it', () {
      final result = advanceTopic(currentTopic: Topic.health, currentProgress: 1, messageTopics: {Topic.health});
      expect(result.topic, Topic.health);
      expect(result.progress, 2);
    });

    test('raising a different topic switches the thread and resets to stage 1', () {
      final result = advanceTopic(currentTopic: Topic.family, currentProgress: 3, messageTopics: {Topic.money});
      expect(result.topic, Topic.money);
      expect(result.progress, 1);
    });

    test('no active thread yet, message raises a topic -> starts at stage 1', () {
      final result = advanceTopic(currentTopic: null, currentProgress: 0, messageTopics: {Topic.greeting});
      expect(result.topic, Topic.greeting);
      expect(result.progress, 1);
    });

    test('a bare greeting co-detected only with family (e.g. "hey mom") stays a greeting', () {
      final result = advanceTopic(
        currentTopic: null,
        currentProgress: 0,
        messageTopics: {Topic.family, Topic.greeting},
      );
      expect(result.topic, Topic.greeting);
      expect(result.progress, 1);
    });

    test('a greeting alongside real substantive content defers to that content, not greeting', () {
      // Topic.health first, matching how _classifyTopics actually builds
      // the set — lexicon topics are matched before Topic.greeting is
      // appended, so this is the true insertion order for "hey, not feeling
      // well today" (health content alongside an incidental greeting word).
      final result = advanceTopic(
        currentTopic: null,
        currentProgress: 0,
        messageTopics: {Topic.health, Topic.greeting},
      );
      expect(result.topic, isNot(Topic.greeting));
    });

    test('family alone (no greeting) is unaffected by the carve-out', () {
      final result = advanceTopic(currentTopic: null, currentProgress: 0, messageTopics: {Topic.family});
      expect(result.topic, Topic.family);
    });

    test('a fresh topic with a declared subject carries it, and starts unresolved with turnsActive 1', () {
      final result = advanceTopic(
        currentTopic: null,
        currentProgress: 0,
        messageTopics: {Topic.money},
        messageSubject: 'rent',
      );
      expect(result.subject, 'rent');
      expect(result.unresolved, isTrue);
      expect(result.turnsActive, 1);
    });

    test('deepening the same topic keeps the old subject when the new turn does not declare one', () {
      final result = advanceTopic(
        currentTopic: Topic.money,
        currentProgress: 1,
        messageTopics: {Topic.money},
        currentSubject: 'rent',
        currentTurnsActive: 1,
      );
      expect(result.subject, 'rent');
      expect(result.turnsActive, 2);
    });

    test('deepening the same topic with a new declared subject narrows it further (rent -> borrowing from brother)', () {
      final result = advanceTopic(
        currentTopic: Topic.money,
        currentProgress: 1,
        messageTopics: {Topic.money},
        currentSubject: 'rent',
        messageSubject: 'borrowing from brother',
      );
      expect(result.subject, 'borrowing from brother');
    });

    test('resolves clears the subject and flips unresolved false, even while staying on-topic', () {
      final result = advanceTopic(
        currentTopic: Topic.money,
        currentProgress: 2,
        messageTopics: {Topic.money},
        currentSubject: 'debt',
        currentUnresolved: true,
        resolves: true,
      );
      expect(result.subject, isNull);
      expect(result.unresolved, isFalse);
    });

    test('switching to a genuinely different topic drops the old subject and resets turnsActive to 1', () {
      final result = advanceTopic(
        currentTopic: Topic.family,
        currentProgress: 3,
        messageTopics: {Topic.money},
        currentSubject: 'a family argument',
        currentTurnsActive: 5,
      );
      expect(result.subject, isNull);
      expect(result.turnsActive, 1);
    });

    test('turnsActive climbs on a hold turn (no topic mentioned) as long as a thread is open', () {
      final result = advanceTopic(
        currentTopic: Topic.money,
        currentProgress: 2,
        messageTopics: const {},
        currentTurnsActive: 2,
      );
      expect(result.turnsActive, 3);
      expect(result.progress, 2); // progress itself does not move on a hold
    });

    test('turnsActive stays 0 on a hold turn when there is no active thread at all', () {
      final result = advanceTopic(currentTopic: null, currentProgress: 0, messageTopics: const {});
      expect(result.turnsActive, 0);
    });
  });

  group('resolvePendingQuestion', () {
    test('no question was pending -> stays answered regardless of intent', () {
      final result = resolvePendingQuestion(wasAnswered: true, messageIntent: Intent.dismissal);
      expect(result.answered, isTrue);
      expect(result.justDodged, isFalse);
    });

    test('a pending question dismissed -> stays unanswered, and this turn counts as just dodged', () {
      final result = resolvePendingQuestion(wasAnswered: false, messageIntent: Intent.dismissal);
      expect(result.answered, isFalse);
      expect(result.justDodged, isTrue);
    });

    test('a pending question met with any non-dismissal reply -> resolves, not a dodge', () {
      for (final intent in Intent.values.where((i) => i != Intent.dismissal)) {
        final result = resolvePendingQuestion(wasAnswered: false, messageIntent: intent);
        expect(result.answered, isTrue, reason: '$intent');
        expect(result.justDodged, isFalse, reason: '$intent');
      }
    });
  });

  group('decayMood', () {
    test('moves a nonzero mood toward 0 and eventually reaches exactly 0 by default', () {
      var mood = 50.0;
      for (var i = 0; i < 200; i++) {
        final next = decayMood(mood);
        expect(next.abs(), lessThanOrEqualTo(mood.abs()));
        mood = next;
      }
      expect(mood, 0);
    });

    test('converges to baselineAttraction / rate when a nonzero baseline is given', () {
      var mood = 0.0;
      const rate = 0.2, baseline = 0.5;
      for (var i = 0; i < 200; i++) {
        mood = decayMood(mood, rate: rate, baselineAttraction: baseline);
      }
      expect(mood, closeTo(baseline / rate, 1e-9));
    });
  });

  group('nudgeMood', () {
    test('warm increases mood, cold decreases it', () {
      expect(nudgeMood(0, ReplyTone.warm), greaterThan(0));
      expect(nudgeMood(0, ReplyTone.cold), lessThan(0));
    });

    test('clamps at -100 and 100', () {
      expect(nudgeMood(95, ReplyTone.warm), 100);
      expect(nudgeMood(-95, ReplyTone.cold), -100);
    });

    test('personalityModifier scales the delta', () {
      final base = nudgeMood(0, ReplyTone.warm);
      final volatile = nudgeMood(0, ReplyTone.warm, personalityModifier: 2.0);
      expect(volatile, greaterThan(base));
    });
  });

  group('personalityModifier / baselineAttraction / impactMultiplier', () {
    test('personalityModifier(0.5) sits at the midpoint of the 0.5-1.0 range', () {
      expect(personalityModifier(0.5), 0.75);
    });

    test('personalityModifier ranges from 0.5 to 1.0 across volatility 0..1', () {
      expect(personalityModifier(0.0), 0.5);
      expect(personalityModifier(1.0), 1.0);
    });

    test('baselineAttraction(50) is 0 (neutral warmth, old default behavior)', () {
      expect(baselineAttraction(50), 0.0);
    });

    test('baselineAttraction is positive above 50 warmth, negative below', () {
      expect(baselineAttraction(80), greaterThan(0));
      expect(baselineAttraction(20), lessThan(0));
    });

    test('impactMultiplier ranges from 0.5 to 1.0 across intensity 0..1', () {
      expect(impactMultiplier(0.0), 0.5);
      expect(impactMultiplier(1.0), 1.0);
    });
  });

  group('nudgeFear / nudgeRespect / nudgeDebt', () {
    test('cold raises fear, warm lowers it', () {
      expect(nudgeFear(50, ReplyTone.cold, 0.5), greaterThan(50));
      expect(nudgeFear(50, ReplyTone.warm, 0.5), lessThan(50));
    });

    test('fear clamps to [0, 100]', () {
      expect(nudgeFear(99, ReplyTone.cold, 1.0), 100);
      expect(nudgeFear(1, ReplyTone.warm, 1.0), 0);
    });

    test('honest raises respect, excuse lowers it', () {
      expect(nudgeRespect(50, ReplyTone.honest, 0.5), greaterThan(50));
      expect(nudgeRespect(50, ReplyTone.excuse, 0.5), lessThan(50));
    });

    test('respect clamps to [0, 100]', () {
      expect(nudgeRespect(99, ReplyTone.honest, 1.0), 100);
      expect(nudgeRespect(1, ReplyTone.excuse, 1.0), 0);
    });

    test('debt only moves on a debt-topic message', () {
      expect(nudgeDebt(50, isDebtTopic: false, tone: ReplyTone.cold), 50);
    });

    test('deflecting a debt-topic message raises debt; settling it lowers debt', () {
      expect(nudgeDebt(50, isDebtTopic: true, tone: ReplyTone.cold), 65);
      expect(nudgeDebt(50, isDebtTopic: true, tone: ReplyTone.warm), 35);
    });

    test('debt clamps to [0, 100]', () {
      expect(nudgeDebt(95, isDebtTopic: true, tone: ReplyTone.cold), 100);
      expect(nudgeDebt(5, isDebtTopic: true, tone: ReplyTone.warm), 0);
    });
  });

  group('recordMemory', () {
    test('once:true never duplicates a MemoryKind', () {
      final memories = <MemoryEvent>[];
      recordMemory(memories, const MemoryEvent(MemoryKind.firstWarmReply, 1), once: true);
      recordMemory(memories, const MemoryEvent(MemoryKind.firstWarmReply, 5), once: true);
      expect(memories.length, 1);
    });

    test('without once, respects cap by dropping the oldest entry first', () {
      final memories = <MemoryEvent>[];
      for (var i = 0; i < 5; i++) {
        recordMemory(memories, MemoryEvent(MemoryKind.firstWarmReply, i), cap: 3);
      }
      expect(memories.length, 3);
    });
  });

  group('Behavioral reputation (Phase 9)', () {
    group('nudgeHonesty', () {
      test('below threshold (default 3) does nothing, at or above it nudges up by delta', () {
        expect(nudgeHonesty(50, 2), 50);
        expect(nudgeHonesty(50, 3), closeTo(50.3, 0.001));
        expect(nudgeHonesty(50, 5), closeTo(50.3, 0.001)); // same delta regardless of how far past threshold
      });

      test('clamps at 100', () {
        expect(nudgeHonesty(99.9, 3), 100);
      });

      test('a custom threshold/delta is honored', () {
        expect(nudgeHonesty(50, 4, threshold: 5), 50);
        expect(nudgeHonesty(50, 5, threshold: 5, delta: 2.0), 52);
      });
    });

    group('nudgeSuspicionFromDodgePattern', () {
      test('below threshold (default 2) does nothing, at or above it nudges up by delta', () {
        expect(nudgeSuspicionFromDodgePattern(20, 1), 20);
        expect(nudgeSuspicionFromDodgePattern(20, 2), 21);
        expect(nudgeSuspicionFromDodgePattern(20, 4), 21);
      });

      test('clamps at 100', () {
        expect(nudgeSuspicionFromDodgePattern(99.5, 2, delta: 1.0), 100);
      });
    });

    group('nudgeReliability', () {
      test('always applies delta (not gated on a streak/threshold — a promise kept is a discrete event)', () {
        expect(nudgeReliability(50), closeTo(51.0, 0.001));
        expect(nudgeReliability(50, delta: 3.0), 53);
      });

      test('clamps at 100', () {
        expect(nudgeReliability(99.5), 100);
      });
    });

    group('nudgeResponsiveness', () {
      test('a prompt reply (<=1 day) nudges up', () {
        expect(nudgeResponsiveness(50, 0), 51);
        expect(nudgeResponsiveness(50, 1), 51);
      });

      test('a late reply (>=3 days) nudges down', () {
        expect(nudgeResponsiveness(50, 3), 49);
        expect(nudgeResponsiveness(50, 10), 49);
      });

      test('an ordinary gap (2 days) is neutral', () {
        expect(nudgeResponsiveness(50, 2), 50);
      });

      test('clamps to [0, 100]', () {
        expect(nudgeResponsiveness(99.5, 0), 100);
        expect(nudgeResponsiveness(0.5, 5), 0);
      });
    });
  });

  group('recordFact', () {
    test('a brand-new key is inserted with full confidence, first == last confirmed turn, and returns no contradiction', () {
      final facts = <String, ConversationFact>{};
      final result = recordFact(facts, 'brotherName', 'Marcus', 5);
      expect(result, isNull);
      final fact = facts['brotherName']!;
      expect(fact.value, 'Marcus');
      expect(fact.confidence, 1.0);
      expect(fact.firstMentionedTurn, 5);
      expect(fact.lastConfirmedTurn, 5);
    });

    test('re-confirming the same value advances lastConfirmedTurn, nudges confidence up capped at 1.0, and returns no contradiction', () {
      final facts = <String, ConversationFact>{};
      // correctionConfidence only applies on the contradicting-value path
      // below, not a fresh insert (that's always full 1.0 confidence) — so
      // to observe the upward nudge at all, first drive confidence down via
      // a genuine correction, then re-confirm that.
      recordFact(facts, 'brotherName', 'Marco', 1);
      recordFact(facts, 'brotherName', 'Marcus', 5, correctionConfidence: 0.5);
      final reconfirmResult = recordFact(facts, 'brotherName', 'Marcus', 9);
      expect(reconfirmResult, isNull);
      final fact = facts['brotherName']!;
      expect(fact.lastConfirmedTurn, 9);
      expect(fact.firstMentionedTurn, 5); // reset by the correction at turn 5, untouched by the re-confirm
      expect(fact.confidence, closeTo(0.6, 0.001));

      // Confidence starts at 1.0 for a fresh key, so re-confirming repeatedly
      // must clamp rather than overshoot.
      recordFact(facts, 'jobSteady', 'true', 1);
      recordFact(facts, 'jobSteady', 'true', 2);
      recordFact(facts, 'jobSteady', 'true', 3);
      expect(facts['jobSteady']!.confidence, 1.0);
    });

    test('a contradicting value replaces it, resets firstMentionedTurn, lowers confidence, and returns the ContradictionEvent', () {
      final facts = <String, ConversationFact>{};
      recordFact(facts, 'worksNightShift', 'true', 2);
      final result = recordFact(facts, 'worksNightShift', 'false', 10);
      final fact = facts['worksNightShift']!;
      expect(fact.value, 'false');
      expect(fact.firstMentionedTurn, 10); // a new claim, starting its own history
      expect(fact.lastConfirmedTurn, 10);
      expect(fact.confidence, lessThan(1.0));

      expect(result, isNotNull);
      expect(result!.key, 'worksNightShift');
      expect(result.oldValue, 'true');
      expect(result.newValue, 'false');
      expect(result.turn, 10);
    });

    test('important carries forward through a correction once set', () {
      final facts = <String, ConversationFact>{};
      recordFact(facts, 'brotherName', 'Marcus', 1, important: true);
      recordFact(facts, 'brotherName', 'Marco', 4); // a correction, important not re-passed
      expect(facts['brotherName']!.important, isTrue);
    });
  });

  group('pushRecentTone', () {
    test('respects capacity and keeps most-recent-last order', () {
      final buf = <ReplyTone>[];
      pushRecentTone(buf, ReplyTone.warm, capacity: 3);
      pushRecentTone(buf, ReplyTone.honest, capacity: 3);
      pushRecentTone(buf, ReplyTone.cold, capacity: 3);
      pushRecentTone(buf, ReplyTone.vague, capacity: 3);
      expect(buf, [ReplyTone.honest, ReplyTone.cold, ReplyTone.vague]);
    });
  });

  group('effectiveInitiative', () {
    test('moodSensitivity 0 and no trust/closeness reproduces the base chance regardless of mood', () {
      for (final mood in [-100.0, -50.0, 0.0, 50.0, 100.0]) {
        expect(effectiveInitiative(0.4, mood, 0.0), 0.4);
      }
    });

    test('nonzero moodSensitivity swings the chance with mood', () {
      expect(effectiveInitiative(0.45, 100, 0.6), 1.0); // clamped
      expect(effectiveInitiative(0.45, -100, 0.6), closeTo(0.0, 1e-9));
    });

    test('high trust and closeness add up to a +0.2 relationship modifier', () {
      expect(effectiveInitiative(0.3, 0, 0, trust: 100, closeness: 100), closeTo(0.5, 1e-9));
    });
  });

  group('TimeOfDay', () {
    test('timeOfDayForTick cycles morning -> afternoon -> evening -> night -> morning', () {
      expect(timeOfDayForTick(0), TimeOfDay.morning);
      expect(timeOfDayForTick(1), TimeOfDay.afternoon);
      expect(timeOfDayForTick(2), TimeOfDay.evening);
      expect(timeOfDayForTick(3), TimeOfDay.night);
      expect(timeOfDayForTick(4), TimeOfDay.morning);
      expect(timeOfDayForTick(9), TimeOfDay.afternoon);
    });

    test('isWeekendForTick is true for the last 2 of every 7 cycle-days', () {
      // Each cycle-day is 4 ticks (one full TimeOfDay cycle).
      for (var cycleDay = 0; cycleDay < 5; cycleDay++) {
        expect(isWeekendForTick(cycleDay * 4), isFalse, reason: 'cycleDay $cycleDay');
      }
      expect(isWeekendForTick(5 * 4), isTrue); // cycleDay 5
      expect(isWeekendForTick(6 * 4), isTrue); // cycleDay 6
      expect(isWeekendForTick(7 * 4), isFalse); // wraps to cycleDay 0 of the next week
    });

    test('a DialogueLine gated to a specific timesOfDay is only eligible then', () {
      final rng = Random(50);
      final pool = [const DialogueLine('morning_only', timesOfDay: {TimeOfDay.morning})];
      final morningCtx = _ctx();
      const eveningCtx = DialogueContext(
        mood: 0, closeness: 50, trust: 50, suspicion: 0, daysSinceReply: 0,
        recentTones: [], memories: [], timeOfDay: TimeOfDay.evening,
      );
      expect(pickLine(rng, pool, morningCtx, currentDay: 1)!.text, 'morning_only');
      expect(pickLine(rng, pool, eveningCtx, currentDay: 1), isNull);
    });

    test('a DialogueLine gated to requireWeekend only fires on a weekend context', () {
      final rng = Random(51);
      final pool = [const DialogueLine('weekend_only', requireWeekend: true)];
      final weekdayCtx = _ctx();
      const weekendCtx = DialogueContext(
        mood: 0, closeness: 50, trust: 50, suspicion: 0, daysSinceReply: 0,
        recentTones: [], memories: [], isWeekend: true,
      );
      expect(pickLine(rng, pool, weekdayCtx, currentDay: 1), isNull);
      expect(pickLine(rng, pool, weekendCtx, currentDay: 1)!.text, 'weekend_only');
    });
  });
}
