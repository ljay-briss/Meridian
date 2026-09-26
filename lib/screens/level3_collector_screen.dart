import 'package:flutter/material.dart';
import '../theme.dart';
import '../controller.dart';
import '../data.dart';
import '../widgets.dart';

/// Level 3 — Collector.
class CollectorScreen extends StatelessWidget {
  const CollectorScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final g = AppScope.of(context);
    final c = AppColors.of(context);
    final allResolved = kCollectionRoute.every((t) => g.targetState[t.id] != 'pending' && g.targetState[t.id] != 'resisting');
    final nightOver = !allResolved && g.routeStalled;
    final locked = g.collectorLocked;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
      children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text('LEVEL 3 — COLLECTOR', style: AppText.sans(size: 10, weight: FontWeight.w500, color: c.ink, spacing: 1.6)),
          Text('RISK ${riskLabel(g.policeHeat)}', style: AppText.sans(size: 11, weight: FontWeight.w600, color: riskColor(c, g.policeHeat), spacing: 0.6)),
        ]),
        const SizedBox(height: 14),
        const LevelProgressBar(),
        const SizedBox(height: 14),
        MeterBar(label: 'Rival heat', value: g.rivalPressure, color: riskColor(c, g.rivalPressure)),
        const SizedBox(height: 18),
        Text('BALANCE', style: AppText.sans(size: 11, weight: FontWeight.w500, color: c.ink, spacing: 1.2)),
        const SizedBox(height: 6),
        AnimatedMoney(value: g.cash, styleFor: (v) => AppText.mono(size: 44, weight: FontWeight.w600, color: cashColor(c, v))),
        const SizedBox(height: 6),
        Text('collected ${money(g.collectedTotal)} / ${money(g.expectedTotal)} owed this week',
            style: AppText.sans(size: 11, weight: FontWeight.w500, color: c.ink)),
        Container(height: 1, color: c.lineSoft, margin: const EdgeInsets.symmetric(vertical: 22)),
        const _NightClock(),
        const SizedBox(height: 14),
        const _FavourCard(),
        const SizedBox(height: 14),
        if (g.sideHustleAvailable) ...[
          const SideHustleCard(),
          const SizedBox(height: 14),
        ],
        for (final target in kCollectionRoute) ...[
          _TargetCard(target: target),
          const SizedBox(height: 10),
        ],
        const SizedBox(height: 10),
        AppButton(
          kind: BtnKind.dark,
          full: true,
          height: 50,
          onTap: locked ? null : g.reportToBoss,
          child: Text(locked
              ? 'On the road…'
              : allResolved
                  ? 'Report to the boss'
                  : nightOver
                      ? 'Night\'s over — report in'
                      : 'Call it a night'),
        ),
        if (!allResolved && !locked) ...[
          const SizedBox(height: 8),
          Text('Stops you haven\'t finished pay nothing, and the gap comes out of your pocket.',
              textAlign: TextAlign.center, style: AppText.sans(size: 11, weight: FontWeight.w500, color: c.inkFaint, height: 1.4)),
        ],
      ],
    );
  }
}

String _clock(int seconds) => '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';

/// The night's remaining time budget — every action spends some of it, so
/// the player has to decide who's worth chasing and who to leave behind.
class _NightClock extends StatelessWidget {
  const _NightClock();

  @override
  Widget build(BuildContext context) {
    final g = AppScope.of(context);
    final c = AppColors.of(context);
    final left = g.routeSecondsLeft;
    final timesUp = g.routeStalled && g.targetState.values.any((s) => s == 'pending' || s == 'resisting');
    final color = left < 30 ? c.neg : left < 60 ? c.warn : c.ink;
    return AppCard(
      padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text('NIGHT REMAINING', style: AppText.sans(size: 11, weight: FontWeight.w500, color: c.ink, spacing: 1.2)),
          AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 250),
            style: AppText.mono(size: 26, weight: FontWeight.w700, color: color),
            child: Text(_clock(left)),
          ),
        ]),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: Container(
            height: 6,
            color: c.lineSoft,
            alignment: Alignment.centerLeft,
            child: AnimatedFractionallySizedBox(
              duration: const Duration(milliseconds: 250),
              widthFactor: (left / g.routeBudget).clamp(0.0, 1.0),
              child: Container(color: color),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Visit −${CareerController.visitSeconds}s · Threaten −${CareerController.threatenSeconds}s · '
          'Vandalize −${CareerController.vandalizeSeconds}s · Side hustle −${CareerController.sideHustleSeconds}s',
          style: AppText.sans(size: 11, weight: FontWeight.w500, color: c.inkFaint, height: 1.4),
        ),
        if (g.routePenaltySeconds > 0) ...[
          const SizedBox(height: 6),
          Text('The boss cut ${g.routePenaltySeconds}s off tonight after last week\'s shortfall.',
              style: AppText.sans(size: 11, weight: FontWeight.w500, color: c.warn, height: 1.4)),
        ],
        if (timesUp) ...[
          const SizedBox(height: 6),
          Text('Time\'s up — anyone you didn\'t reach pays nothing. Report in with what you\'ve got.',
              style: AppText.sans(size: 11.5, weight: FontWeight.w600, color: c.neg, height: 1.4)),
        ],
      ]),
    );
  }
}

/// The one-shot emergency resource — obvious, priced, and gone once spent.
class _FavourCard extends StatelessWidget {
  const _FavourCard();

  void _pick(BuildContext context, CareerController g) {
    showAppSheet(context, 'Call in a favour', (ctx) {
      final c = AppColors.of(ctx);
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Who cooperates? They\'ll pay in full. Cost: +${CareerController.kFavourSuspicion.round()} suspicion. You only get one.',
            style: AppText.sans(size: 13.5, weight: FontWeight.w500, color: c.inkSoft, height: 1.5)),
        const SizedBox(height: 16),
        for (final t in g.favourTargets) ...[
          AppButton(
            kind: BtnKind.ghost,
            full: true,
            onTap: () {
              Navigator.pop(ctx);
              g.callInFavour(t.id);
            },
            child: Text('${t.name} — ${money(g.effectiveOwed(t))}'),
          ),
          const SizedBox(height: 10),
        ],
      ]);
    });
  }

  @override
  Widget build(BuildContext context) {
    final g = AppScope.of(context);
    final c = AppColors.of(context);
    final used = g.favourUsed;
    final canUse = !used && !g.collectorLocked && g.favourTargets.isNotEmpty;
    return AppCard(
      padding: const EdgeInsets.all(14),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
              Text('CALL IN A FAVOUR', style: AppText.sans(size: 11, weight: FontWeight.w500, color: c.ink, spacing: 1.2)),
              AppChip(tone: used ? ChipTone.neg : ChipTone.warn, child: Text(used ? 'USED' : '1 LEFT')),
            ]),
            const SizedBox(height: 4),
            Text(
              used
                  ? 'Spent. No more favours this level.'
                  : 'A target still holding out will pay in full. Cost: +${CareerController.kFavourSuspicion.round()} suspicion. One use per level.',
              style: AppText.sans(size: 12, weight: FontWeight.w500, color: c.inkSoft, height: 1.4),
            ),
          ]),
        ),
        const SizedBox(width: 12),
        AppButton(kind: BtnKind.ghost, onTap: canUse ? () => _pick(context, g) : null, child: const Text('Use')),
      ]),
    );
  }
}

class _TargetCard extends StatefulWidget {
  final CollectionTarget target;
  const _TargetCard({required this.target});
  @override
  State<_TargetCard> createState() => _TargetCardState();
}

class _TargetCardState extends State<_TargetCard> {
  // The transient three-stage beat a consequential action plays through —
  // ACTION (verb) while suspense holds, then OUTCOME + CONSEQUENCE once the
  // real roll has happened — before settling back into the card's normal
  // persistent look.
  String? _beatVerb;
  String? _beatOutcome;
  int? _beatCashDelta;
  List<MapEntry<String, int>> _beatConsequences = const [];

  Future<void> _runBeat(CareerController g, String verb, VoidCallback action) async {
    g.beginCollectorAction();
    setState(() {
      _beatVerb = verb;
      _beatOutcome = null;
    });
    await Future.delayed(const Duration(milliseconds: 650));
    if (!mounted) return;

    // Snapshot every track the action could move, so whatever changes can
    // be read back as a plain delta — no new controller-side bookkeeping.
    final heatBefore = g.policeHeat;
    final suspicionBefore = g.cartelSuspicion;
    final rivalBefore = g.rivalPressure;
    final collectedBefore = g.collected[widget.target.id] ?? 0;
    final timeBefore = g.routeSecondsLeft;

    g.endCollectorAction();
    action(); // the real visit/threaten/vandalize call — resolves synchronously

    final consequences = <MapEntry<String, int>>[
      for (final e in [
        MapEntry('HEAT', (g.policeHeat - heatBefore).round()),
        MapEntry('SUSPICION', (g.cartelSuspicion - suspicionBefore).round()),
        MapEntry('RIVAL', (g.rivalPressure - rivalBefore).round()),
        MapEntry('TIME', g.routeSecondsLeft - timeBefore),
      ])
        if (e.value != 0) e,
    ];
    final cashDelta = (g.collected[widget.target.id] ?? 0) - collectedBefore;

    if (!mounted) return;
    setState(() {
      _beatVerb = null;
      _beatOutcome = g.targetState[widget.target.id];
      _beatCashDelta = cashDelta > 0 ? cashDelta : null;
      _beatConsequences = consequences;
    });

    // Let the beat sit long enough to actually read, then hand back to the
    // card's normal PAID/RESISTING/etc. rendering.
    await Future.delayed(const Duration(milliseconds: 1500));
    if (!mounted) return;
    setState(() {
      _beatOutcome = null;
      _beatCashDelta = null;
      _beatConsequences = const [];
    });
  }

  void _vandalizeSheet(BuildContext context, CareerController g) {
    final target = widget.target;
    showAppSheet(context, 'Text the crew', (ctx) {
      final c = AppColors.of(ctx);
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('${target.name} — pick the time. Costs ${CareerController.vandalizeSeconds}s of the night either way.',
            style: AppText.sans(size: 13.5, weight: FontWeight.w500, color: c.inkSoft, height: 1.5)),
        const SizedBox(height: 16),
        AppButton(
          kind: BtnKind.ghost,
          full: true,
          onTap: () {
            Navigator.pop(ctx);
            _runBeat(g, 'Sending the crew', () => g.vandalize(target.id, now: true));
          },
          child: const Text('Now — daylight, risk of arrest'),
        ),
        const SizedBox(height: 10),
        AppButton(
          kind: BtnKind.ghost,
          full: true,
          onTap: () {
            Navigator.pop(ctx);
            _runBeat(g, 'Sending the crew', () => g.vandalize(target.id, now: false));
          },
          child: const Text('Tonight — safer, slower'),
        ),
      ]);
    });
  }

  @override
  Widget build(BuildContext context) {
    final g = AppScope.of(context);
    final c = AppColors.of(context);
    final target = widget.target;
    final state = g.targetState[target.id] ?? 'pending';
    final locked = g.collectorLocked;
    final underRivalWatch = g.targetUnderRivalWatch.contains(target.id);
    final onEdge = g.targetOnEdge.contains(target.id);
    final open = state == 'pending' || state == 'resisting';
    final oddsLine = state == 'pending'
        ? 'Visit odds ${(g.visitOdds(target.id) * 100).round()}%'
        : 'Threaten odds ${(g.threatenOdds(target.id) * 100).round()}%';

    return AppCard(
      padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(target.name, style: AppText.sans(size: 14.5, weight: FontWeight.w600, color: c.ink)),
              Text('${target.kind} · owes ${money(g.effectiveOwed(target))}', style: AppText.sans(size: 11.5, weight: FontWeight.w500, color: c.inkFaint)),
              if (open && (underRivalWatch || onEdge)) ...[
                const SizedBox(height: 6),
                Wrap(spacing: 6, runSpacing: 6, children: [
                  // The rival crew's hold on this target — every action taken
                  // here feeds their pressure, and it makes the visit harder.
                  if (underRivalWatch) const AppChip(tone: ChipTone.warn, child: Text('RIVAL CREW IS WATCHING')),
                  // Word of an earlier threat or vandalism reached this stop.
                  if (onEdge) const AppChip(tone: ChipTone.warn, child: Text('ON EDGE')),
                ]),
              ] else if (underRivalWatch) ...[
                const SizedBox(height: 4),
                // The lasting mark a rival crew noticing this target's pattern
                // leaves behind — visible every week, not just the once.
                AppChip(tone: ChipTone.warn, child: Text('${g.rivalCrewName.toUpperCase()} SKIMS THIS ONE')),
              ],
              if (open) ...[
                const SizedBox(height: 6),
                Text(oddsLine, style: AppText.sans(size: 11.5, weight: FontWeight.w600, color: c.inkSoft, height: 1.4)),
                if (underRivalWatch)
                  Text('Every action here adds +${CareerController.kWatchedActionPressure.round()} rival heat.',
                      style: AppText.sans(size: 11, weight: FontWeight.w500, color: c.inkFaint, height: 1.4)),
                if (onEdge)
                  Text('Word got around — visit −${(CareerController.kOnEdgeVisitPenalty * 100).round()}%, threats +${(CareerController.kOnEdgeThreatenBonus * 100).round()}%.',
                      style: AppText.sans(size: 11, weight: FontWeight.w500, color: c.inkFaint, height: 1.4)),
              ],
            ]),
          ),
          const SizedBox(width: 8),
          // A little pop on every state change — paying off a card should
          // feel like something happened, not just a label swap.
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 260),
            transitionBuilder: (child, anim) => ScaleTransition(scale: anim, child: FadeTransition(opacity: anim, child: child)),
            child: _StateChip(key: ValueKey(state), state: state),
          ),
        ]),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          transitionBuilder: (child, anim) => FadeTransition(opacity: anim, child: child),
          child: _beatVerb != null
              ? _BeatVerb(key: const ValueKey('verb'), label: _beatVerb!)
              : _beatOutcome != null
                  ? _BeatResult(key: const ValueKey('result'), outcome: _beatOutcome!, cashDelta: _beatCashDelta, consequences: _beatConsequences)
                  : _RestingBody(
                      key: const ValueKey('resting'),
                      target: target,
                      state: state,
                      collected: g.collected[target.id],
                      effectiveOwed: g.effectiveOwed(target),
                      excuse: g.targetExcuse[target.id],
                      locked: locked,
                      onVisit: () => _runBeat(g, 'Collecting', () => g.visit(target.id)),
                      onThreaten: () => _runBeat(g, 'Threatening', () => g.threaten(target.id)),
                      onVandalize: () => _vandalizeSheet(context, g),
                    ),
        ),
      ]),
    );
  }
}

/// The card's normal, persistent look once no beat is playing — same
/// pending/resisting/refused/paid/lost branches it always had.
class _RestingBody extends StatelessWidget {
  final CollectionTarget target;
  final String state;
  final int? collected;
  final int effectiveOwed;
  final String? excuse;
  final bool locked;
  final VoidCallback onVisit;
  final VoidCallback onThreaten;
  final VoidCallback onVandalize;
  const _RestingBody({
    super.key,
    required this.target,
    required this.state,
    required this.collected,
    required this.effectiveOwed,
    required this.excuse,
    required this.locked,
    required this.onVisit,
    required this.onThreaten,
    required this.onVandalize,
  });

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final g = AppScope.of(context);
    final canThreaten = g.canAffordRouteTime(CareerController.threatenSeconds);
    final canVandalize = g.canAffordRouteTime(CareerController.vandalizeSeconds);
    final canVisit = g.canAffordRouteTime(CareerController.visitSeconds);
    switch (state) {
      case 'paid':
        return Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Text('+${money(collected ?? effectiveOwed)}', style: AppText.mono(size: 20, weight: FontWeight.w700, color: c.pos)),
        );
      case 'missed':
        return Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Text('The night ran out before you got here.', style: AppText.sans(size: 12.5, weight: FontWeight.w500, color: c.inkFaint, height: 1.4)),
        );
      case 'lost':
        return Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Text('The crew got made — nothing collected here.', style: AppText.sans(size: 12.5, weight: FontWeight.w500, color: c.inkFaint, height: 1.4)),
        );
      case 'resisting':
        return Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('"$excuse"', style: AppText.sans(size: 13, weight: FontWeight.w500, color: c.inkSoft, height: 1.4)),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                  child: AppButton(
                      kind: BtnKind.ghost,
                      full: true,
                      onTap: locked || !canThreaten ? null : onThreaten,
                      child: const Text('Threaten · ${CareerController.threatenSeconds}s'))),
              const SizedBox(width: 8),
              Expanded(
                  child: AppButton(
                      kind: BtnKind.ghost,
                      full: true,
                      onTap: locked || !canVandalize ? null : onVandalize,
                      child: const Text('Vandalize · ${CareerController.vandalizeSeconds}s'))),
            ]),
          ]),
        );
      case 'refused':
        return Padding(
          padding: const EdgeInsets.only(top: 10),
          child: AppButton(
              kind: BtnKind.ghost,
              full: true,
              onTap: locked || !canVandalize ? null : onVandalize,
              child: const Text('Vandalize · ${CareerController.vandalizeSeconds}s')),
        );
      default: // pending
        return Padding(
          padding: const EdgeInsets.only(top: 10),
          child: AppButton(
              kind: BtnKind.dark,
              full: true,
              onTap: locked || !canVisit ? null : onVisit,
              child: Text(locked ? 'On the road…' : 'Visit · ${CareerController.visitSeconds}s')),
        );
    }
  }
}

/// Stage one of the beat — a pulsing present-tense verb while the outcome
/// is deliberately held back for a beat of suspense.
class _BeatVerb extends StatefulWidget {
  final String label;
  const _BeatVerb({super.key, required this.label});
  @override
  State<_BeatVerb> createState() => _BeatVerbState();
}

class _BeatVerbState extends State<_BeatVerb> with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 550))..repeat(reverse: true);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: FadeTransition(
        opacity: Tween(begin: 0.4, end: 1.0).animate(CurvedAnimation(parent: _c, curve: Curves.easeInOut)),
        child: Text('${widget.label.toUpperCase()}…', style: AppText.sans(size: 13, weight: FontWeight.w700, color: c.inkSoft, spacing: 0.8)),
      ),
    );
  }
}

/// Stages two and three of the beat, together — OUTCOME as a bold headline
/// (using the same words the persistent chip settles into, for continuity)
/// plus CONSEQUENCE as the cash delta and whatever heat/suspicion/rival
/// tracks the roll actually moved.
class _BeatResult extends StatelessWidget {
  final String outcome;
  final int? cashDelta;
  final List<MapEntry<String, int>> consequences;
  const _BeatResult({super.key, required this.outcome, required this.cashDelta, required this.consequences});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final color = switch (outcome) {
      'paid' => c.pos,
      'resisting' => c.warn,
      _ => c.neg,
    };
    final headline = switch (outcome) {
      'paid' => 'PAID',
      'resisting' => 'PUSHED BACK',
      'refused' => 'REFUSED',
      'lost' => 'LOST',
      _ => outcome.toUpperCase(),
    };
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(headline, style: AppText.sans(size: 17, weight: FontWeight.w800, color: color, spacing: 0.6)),
        if (cashDelta != null) ...[
          const SizedBox(height: 4),
          Text('+${money(cashDelta!)}', style: AppText.mono(size: 20, weight: FontWeight.w700, color: c.pos)),
        ],
        if (consequences.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final e in consequences)
              AppChip(tone: ChipTone.warn, child: Text('${e.key} ${e.value > 0 ? '+' : e.value < 0 ? '−' : ''}${e.value.abs()}${e.key == 'TIME' ? 's' : ''}')),
          ]),
        ],
      ]),
    );
  }
}

class _StateChip extends StatelessWidget {
  final String state;
  const _StateChip({super.key, required this.state});
  @override
  Widget build(BuildContext context) {
    switch (state) {
      case 'paid':
        return const AppChip(tone: ChipTone.pos, child: Text('PAID'));
      case 'lost':
        return const AppChip(tone: ChipTone.neg, child: Text('LOST'));
      case 'resisting':
        return const AppChip(tone: ChipTone.warn, child: Text('RESISTING'));
      case 'refused':
        return const AppChip(tone: ChipTone.neg, child: Text('REFUSED'));
      case 'missed':
        return const AppChip(tone: ChipTone.neg, child: Text('MISSED'));
      default:
        return const AppChip(child: Text('PENDING'));
    }
  }
}
