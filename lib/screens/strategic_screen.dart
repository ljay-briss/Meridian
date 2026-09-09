import 'package:flutter/material.dart';
import '../theme.dart';
import '../controller.dart';
import '../widgets.dart';

const _titles = {5: 'REGIONAL OPERATOR', 6: 'PLAZA BOSS', 7: 'CARTEL LEADER'};

/// Levels 5-7 — strategic dashboard (Home tab).
class StrategicScreen extends StatelessWidget {
  const StrategicScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final g = AppScope.of(context);
    final c = AppColors.of(context);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
      children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text('LEVEL ${g.level} — ${_titles[g.level]}', style: AppText.sans(size: 10, weight: FontWeight.w500, color: c.ink, spacing: 1.6)),
          Text('RISK ${riskLabel(g.policeHeat)}', style: AppText.sans(size: 11, weight: FontWeight.w600, color: riskColor(c, g.policeHeat), spacing: 0.6)),
        ]),
        const SizedBox(height: 14),
        const LevelProgressBar(),
        const SizedBox(height: 18),
        Text('CASH ON HAND', style: AppText.sans(size: 11, weight: FontWeight.w500, color: c.ink, spacing: 1.2)),
        const SizedBox(height: 6),
        Text(money(g.cash), style: AppText.mono(size: 40, weight: FontWeight.w600, color: c.ink)),
        const SizedBox(height: 4),
        Text('laundered: ${money(g.cleanBalance)}', style: AppText.sans(size: 11, weight: FontWeight.w500, color: c.ink)),
        if (g.lastLaunderFront != null)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text('last run through ${g.lastLaunderFront}', style: AppText.sans(size: 11, weight: FontWeight.w500, color: c.inkFaint)),
          ),
        Container(height: 1, color: c.lineSoft, margin: const EdgeInsets.symmetric(vertical: 22)),
        Text('~${money(g.strategicMonthlyRevenue)}/month moving through the operation', style: AppText.sans(size: 13, weight: FontWeight.w500, color: c.inkSoft, height: 1.5)),
        const SizedBox(height: 20),
        if (g.level == 5 && (g.pendingCellSkim != null || g.pendingCellPoach != null || g.pendingCellShortage != null))
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: c.warn.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
            child: Text(
              'Something needs your attention before you can close the month — check Org.',
              style: AppText.sans(size: 13, weight: FontWeight.w600, color: c.warn, height: 1.4),
            ),
          )
        else if (g.strategicEvent != null)
          _EventCard(g: g, c: c)
        else ...[
          AppButton(
            kind: BtnKind.dark,
            full: true,
            height: 50,
            onTap: g.strategicBusy ? null : g.advanceStrategicCycle,
            child: Text(g.strategicBusy ? 'Word is still traveling…' : 'Advance the month'),
          ),
          const SizedBox(height: 10),
          AppButton(
            kind: BtnKind.ghost,
            full: true,
            height: 48,
            onTap: g.cash > 0 ? () => g.launderFunds((g.cash * 0.5).round()) : null,
            child: const Text('Launder half of cash on hand'),
          ),
        ],
      ],
    );
  }
}

class _EventCard extends StatelessWidget {
  final CareerController g;
  final AppColors c;
  const _EventCard({required this.g, required this.c});

  @override
  Widget build(BuildContext context) {
    final kind = g.strategicEventKind;
    final choices = switch (kind) {
      'investigation' => switch (g.investigationStage) {
          1 => const [
              ('bribe_judge', 'Bribe a judge', 1500000),
              ('go_dark', 'Go dark for a while', 0),
              ('ignore', 'Ignore it', 0),
            ],
          2 => const [
              ('flip_witness', 'Flip a witness', 3000000),
              ('bribe_judge', 'Bribe the judge', 5000000),
              ('ignore', 'Ignore it', 0),
            ],
          _ => const [
              ('go_to_ground', 'Go to ground — lose 25% of cash', 0),
              ('make_a_stand', 'Make a stand', 0),
              ('ignore', 'Do nothing', 0),
            ],
        },
      'raid_territory' => const [
          ('defend', 'Defend it — violence', 0),
          ('payoff', 'Pay them to back off', 1000000),
          ('abandon', 'Abandon it', 0),
        ],
      'bribe' => const [('pay', 'Pay the fee', 2000000), ('risk', 'Refuse', 0)],
      'diplomacy' => const [('accept', 'Accept the split', 0), ('risk', 'Refuse — hold the line', 0)],
      'paranoia' => const [('execute', 'Have them removed', 0), ('ignore', 'Let it go', 0)],
      _ => const [('risk', 'Acknowledge', 0)],
    };
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        AppChip(tone: kind == 'investigation' ? ChipTone.neg : ChipTone.warn, child: const Text('DECISION')),
        const SizedBox(height: 10),
        Text(g.strategicEvent!, style: AppText.sans(size: 14, weight: FontWeight.w500, color: c.ink, height: 1.5)),
        const SizedBox(height: 16),
        for (final choice in choices)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: AppButton(
              kind: BtnKind.ghost,
              full: true,
              onTap: g.cash >= choice.$3 ? () => g.resolveStrategicEvent(choice.$1) : null,
              child: Text(choice.$3 > 0 ? '${choice.$2} (${money(choice.$3)})' : choice.$2),
            ),
          ),
      ]),
    );
  }
}
