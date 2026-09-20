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
        Text(money(g.cash), style: AppText.mono(size: 44, weight: FontWeight.w600, color: cashColor(c, g.cash))),
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
          onTap: allResolved && !g.collectorBusy ? g.reportToBoss : null,
          child: Text(g.collectorBusy ? 'On the road…' : 'Report to the boss'),
        ),
      ],
    );
  }
}

class _TargetCard extends StatelessWidget {
  final CollectionTarget target;
  const _TargetCard({required this.target});

  @override
  Widget build(BuildContext context) {
    final g = AppScope.of(context);
    final c = AppColors.of(context);
    final state = g.targetState[target.id] ?? 'pending';

    return AppCard(
      padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(target.name, style: AppText.sans(size: 14.5, weight: FontWeight.w600, color: c.ink)),
            Text('${target.kind} · owes ${money(target.owed)}', style: AppText.sans(size: 11.5, weight: FontWeight.w500, color: c.inkFaint)),
          ]),
          _StateChip(state: state),
        ]),
        if (state == 'resisting') ...[
          const SizedBox(height: 10),
          Text('"${g.targetExcuse[target.id]}"', style: AppText.sans(size: 13, weight: FontWeight.w500, color: c.inkSoft, height: 1.4)),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: AppButton(kind: BtnKind.ghost, full: true, onTap: g.collectorBusy ? null : () => g.threaten(target.id), child: const Text('Threaten'))),
            const SizedBox(width: 8),
            Expanded(child: AppButton(kind: BtnKind.ghost, full: true, onTap: g.collectorBusy ? null : () => _vandalizeSheet(context, g, target), child: const Text('Vandalize'))),
          ]),
        ] else if (state == 'refused') ...[
          const SizedBox(height: 10),
          AppButton(kind: BtnKind.ghost, full: true, onTap: g.collectorBusy ? null : () => _vandalizeSheet(context, g, target), child: const Text('Vandalize')),
        ] else if (state == 'pending') ...[
          const SizedBox(height: 10),
          AppButton(kind: BtnKind.dark, full: true, onTap: g.collectorBusy ? null : () => g.visit(target.id), child: Text(g.collectorBusy ? 'On the road…' : 'Visit')),
        ],
      ]),
    );
  }

  void _vandalizeSheet(BuildContext context, CareerController g, CollectionTarget target) {
    showAppSheet(context, 'Text the crew', (ctx) {
      final c = AppColors.of(ctx);
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('${target.name} — pick the time.', style: AppText.sans(size: 13.5, weight: FontWeight.w500, color: c.inkSoft, height: 1.5)),
        const SizedBox(height: 16),
        AppButton(
          kind: BtnKind.ghost,
          full: true,
          onTap: () {
            g.vandalize(target.id, now: true);
            Navigator.pop(ctx);
          },
          child: const Text('Now — daylight, risk of arrest'),
        ),
        const SizedBox(height: 10),
        AppButton(
          kind: BtnKind.ghost,
          full: true,
          onTap: () {
            g.vandalize(target.id, now: false);
            Navigator.pop(ctx);
          },
          child: const Text('Tonight — safer, slower'),
        ),
      ]);
    });
  }
}

class _StateChip extends StatelessWidget {
  final String state;
  const _StateChip({required this.state});
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
