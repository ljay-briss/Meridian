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
    final locked = g.collectorBusy || g.actionInFlight;

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
          onTap: allResolved && !locked ? g.reportToBoss : null,
          child: Text(locked ? 'On the road…' : 'Report to the boss'),
        ),
      ],
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

    g.endCollectorAction();
    action(); // the real visit/threaten/vandalize call — resolves synchronously

    final consequences = <MapEntry<String, int>>[
      for (final e in [
        MapEntry('HEAT', (g.policeHeat - heatBefore).round()),
        MapEntry('SUSPICION', (g.cartelSuspicion - suspicionBefore).round()),
        MapEntry('RIVAL', (g.rivalPressure - rivalBefore).round()),
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
        Text('${target.name} — pick the time.', style: AppText.sans(size: 13.5, weight: FontWeight.w500, color: c.inkSoft, height: 1.5)),
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
    final locked = g.collectorBusy || g.actionInFlight;
    final underRivalWatch = g.targetUnderRivalWatch.contains(target.id);

    return AppCard(
      padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(target.name, style: AppText.sans(size: 14.5, weight: FontWeight.w600, color: c.ink)),
            Text('${target.kind} · owes ${money(g.effectiveOwed(target))}', style: AppText.sans(size: 11.5, weight: FontWeight.w500, color: c.inkFaint)),
            if (underRivalWatch) ...[
              const SizedBox(height: 4),
              // The lasting mark a rival crew noticing this target's pattern
              // leaves behind — visible every week, not just the once.
              AppChip(tone: ChipTone.warn, child: Text('${g.rivalCrewName.toUpperCase()} SKIMS THIS ONE')),
            ],
          ]),
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
    switch (state) {
      case 'paid':
        return Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Text('+${money(collected ?? effectiveOwed)}', style: AppText.mono(size: 20, weight: FontWeight.w700, color: c.pos)),
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
              Expanded(child: AppButton(kind: BtnKind.ghost, full: true, onTap: locked ? null : onThreaten, child: const Text('Threaten'))),
              const SizedBox(width: 8),
              Expanded(child: AppButton(kind: BtnKind.ghost, full: true, onTap: locked ? null : onVandalize, child: const Text('Vandalize'))),
            ]),
          ]),
        );
      case 'refused':
        return Padding(
          padding: const EdgeInsets.only(top: 10),
          child: AppButton(kind: BtnKind.ghost, full: true, onTap: locked ? null : onVandalize, child: const Text('Vandalize')),
        );
      default: // pending
        return Padding(
          padding: const EdgeInsets.only(top: 10),
          child: AppButton(kind: BtnKind.dark, full: true, onTap: locked ? null : onVisit, child: Text(locked ? 'On the road…' : 'Visit')),
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
            for (final e in consequences) AppChip(tone: ChipTone.warn, child: Text('${e.key} ${e.value > 0 ? '+' : ''}${e.value}')),
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
      default:
        return const AppChip(child: Text('PENDING'));
    }
  }
}
