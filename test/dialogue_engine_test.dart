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
}) =>
    DialogueContext(
      mood: mood,
      closeness: closeness,
      trust: trust,
      suspicion: suspicion,
      daysSinceReply: daysSinceReply,
      recentTones: recentTones,
      memories: memories,
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

    test('requiredMemories gates eligibility on presence of any listed kind', () {
      final rng = Random(7);
      final pool = [const DialogueLine('remembers', requiredMemories: {MemoryKind.cutOff})];
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

    test('an old requiredMemories match weighs a line down relative to a fresh one', () {
      final rng = Random(46);
      final pool = [
        const DialogueLine('stale_memory_line', requiredMemories: {MemoryKind.cutOff}),
        const DialogueLine('fresh_memory_line', requiredMemories: {MemoryKind.heardAboutCutOff}),
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

  group('classifyMessage', () {
    test('classifies warm text as warm tone', () {
      final msg = classifyMessage("I'm sorry, I love you so much", knownEntityNames: const []);
      expect(msg.tone, ReplyTone.warm);
    });

    test('classifies dismissive short text as cold tone', () {
      final msg = classifyMessage('not now', knownEntityNames: const []);
      expect(msg.tone, ReplyTone.cold);
    });

    test('classifies a bare greeting as warm, not cold', () {
      for (final text in ['hi', 'hey', 'hello', 'hey mom', 'Hi!']) {
        expect(classifyMessage(text, knownEntityNames: const []).tone, ReplyTone.warm, reason: text);
      }
    });

    test('a greeting-shaped substring inside an unrelated word does not false-positive', () {
      // "hi" appears inside "this" — must not be read as a greeting.
      final msg = classifyMessage('this is not a good time', knownEntityNames: const []);
      expect(msg.tone, isNot(ReplyTone.warm));
      expect(msg.tone, isNot(ReplyTone.honest)); // and shouldn't misfire as a question either
    });

    test('a caring question with no tone-lexicon match reads as honest, not vague/cold', () {
      // Regression: these used to fall into the generic "vague" bucket and
      // draw a "stop dodging me" reaction, which makes no sense as a reply
      // to a genuine question directed at the NPC.
      for (final text in ['how you doing today', 'how so?', 'worried about what', 'are you okay']) {
        expect(classifyMessage(text, knownEntityNames: const []).tone, ReplyTone.honest, reason: text);
      }
    });

    test('classifies excuse language as excuse tone', () {
      final msg = classifyMessage('it was just a long meeting, I swear nothing happened', knownEntityNames: const []);
      expect(msg.tone, ReplyTone.excuse);
    });

    test('classifies honest framing as honest tone', () {
      final msg = classifyMessage('honestly, the truth is I needed space', knownEntityNames: const []);
      expect(msg.tone, ReplyTone.honest);
    });

    test('detects money and family topics from keywords', () {
      final msg = classifyMessage('mom, can you send some cash for rent?', knownEntityNames: const []);
      expect(msg.topics, contains(Topic.money));
      expect(msg.topics, contains(Topic.family));
    });

    test('a bare greeting is tagged with the greeting topic', () {
      for (final text in ['hi', 'hey', 'hello', 'hey mom']) {
        expect(classifyMessage(text, knownEntityNames: const []).topics, contains(Topic.greeting), reason: text);
      }
    });

    test('"hi" inside an unrelated word does not tag the greeting topic', () {
      final msg = classifyMessage('this is not a good time', knownEntityNames: const []);
      expect(msg.topics, isNot(contains(Topic.greeting)));
    });

    test('"how are you"-shaped questions are tagged with the wellbeing topic', () {
      for (final text in [
        'how are you', 'how you doing today', "how's it going", 'you doing ok?', "how's your day", 'hows your day',
      ]) {
        expect(classifyMessage(text, knownEntityNames: const []).topics, contains(Topic.wellbeing), reason: text);
      }
    });

    test('a reciprocal answer to a wellbeing question is itself tagged wellbeing', () {
      // Regression: "How's your day been?" -> "good and yours?" used to
      // classify with no topic at all, since none of the "how ..."-shaped
      // phrases match a reply that only answers back.
      for (final text in ['good and yours?', 'good, and you?', 'how about you', 'what about you']) {
        expect(classifyMessage(text, knownEntityNames: const []).topics, contains(Topic.wellbeing), reason: text);
      }
    });

    test('"what\'s wrong"-shaped questions are tagged with the suspicion/concern topic', () {
      for (final text in ["what's wrong", 'whats wrong']) {
        expect(classifyMessage(text, knownEntityNames: const []).topics, contains(Topic.suspicion), reason: text);
      }
    });

    test('question mark -> question intent', () {
      expect(classifyMessage('are you free tonight?', knownEntityNames: const []).intent, Intent.question);
    });

    test('casual check-ins with no "?" or question word still read as a question, not a dismissal', () {
      // Regression: "you ok" used to score Intent.dismissal purely because
      // the dismissal lexicon's bare 'k' entry substring-matched inside
      // "ok" — the same false-positive class as 'what' inside "whatever".
      for (final text in ['you ok', 'you good', 'you okay', 'you alright', 'everything okay', 'whats up']) {
        expect(classifyMessage(text, knownEntityNames: const []).intent, Intent.question, reason: text);
      }
    });

    test('"whatever" reads as a dismissal, not a question, despite containing "what"', () {
      expect(classifyMessage('whatever', knownEntityNames: const []).intent, Intent.dismissal);
    });

    test('a lone "ok"/"k" still reads as a dismissal (the bare-word fix only removes false substring hits)', () {
      for (final text in ['ok', 'k', 'kk']) {
        expect(classifyMessage(text, knownEntityNames: const []).intent, Intent.dismissal, reason: text);
      }
    });

    test('an ordinary word containing "k" is not misread as a dismissal', () {
      for (final text in ['I like that a lot honestly', 'we should make plans this weekend sometime soon']) {
        expect(classifyMessage(text, knownEntityNames: const []).intent, isNot(Intent.dismissal), reason: text);
      }
    });

    test('"I\'ll ..." -> promise intent', () {
      expect(classifyMessage("I'll come by this weekend", knownEntityNames: const []).intent, Intent.promise);
    });

    test('"I love you" -> confession intent', () {
      expect(classifyMessage('I love you, always have', knownEntityNames: const []).intent, Intent.confession);
    });

    test('extracts a known entity name mentioned in the text', () {
      final msg = classifyMessage('Kiko told me you called', knownEntityNames: const ['Kiko', 'Vale']);
      expect(msg.entities, contains('Kiko'));
      expect(msg.entities, isNot(contains('Vale')));
    });

    test('intensity on the returned message matches computeIntensity', () {
      const text = 'I NEVER want to see you again!!!';
      final msg = classifyMessage(text, knownEntityNames: const []);
      expect(msg.intensity, computeIntensity(text));
    });
  });

  group('computeIntensity', () {
    test('neutral short text sits near the 0.5 baseline', () {
      expect(computeIntensity('okay'), closeTo(0.5, 0.15));
    });

    test('strong words raise intensity', () {
      expect(computeIntensity('I hate this'), greaterThan(computeIntensity('I think this')));
    });

    test('all-caps raises intensity over the same text in lowercase', () {
      expect(computeIntensity('LEAVE ME ALONE'), greaterThan(computeIntensity('leave me alone')));
    });

    test('a bare exclamation point raises intensity', () {
      expect(computeIntensity('fine!'), greaterThan(computeIntensity('fine')));
    });

    test('repeated exclamation marks raise intensity further than one', () {
      expect(computeIntensity('no!!!'), greaterThan(computeIntensity('no!')));
    });

    test('trailing off with "..." lowers intensity slightly', () {
      expect(computeIntensity('I guess...'), lessThan(computeIntensity('I guess')));
    });

    test('longer messages score higher than short ones, all else equal', () {
      expect(computeIntensity('word ' * 30), greaterThan(computeIntensity('word')));
    });

    test('clamps to [0, 1]', () {
      expect(computeIntensity('HATE HATE HATE HATE!!!! ${'x' * 200}'), lessThanOrEqualTo(1.0));
      expect(computeIntensity(''), 0.0);
    });
  });

  group('isDebtTopic', () {
    test('true for money-related keywords', () {
      for (final text in ['you still owe me', 'can you lend me cash', 'pay your rent', "I'll pay you back"]) {
        expect(isDebtTopic(text), isTrue, reason: text);
      }
    });

    test('false for unrelated text', () {
      expect(isDebtTopic('are we still on for dinner?'), isFalse);
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

    test('warm -> honest is natural drift, not a shift (only warm<->cold/excuse count)', () {
      expect(detectToneShift(previousTone: ReplyTone.warm, tone: ReplyTone.honest), isFalse);
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
