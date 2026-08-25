import 'package:flutter/material.dart';
import '../theme.dart';
import '../controller.dart';
import '../data.dart';
import '../widgets.dart';

/// Level 4 — Cell Leader (Home tab): monthly product breakdown & distribution.
class CellLeaderScreen extends StatelessWidget {
  const CellLeaderScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final g = AppScope.of(context);
    final c = AppColors.of(context);
    final blocked = g.pendingIncursion != null || g.pendingTrouble != null;
    final remaining = g.stashKg - g.allocatedKg;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
      children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text('LEVEL 4 — CELL LEADER', style: AppText.sans(size: 10, weight: FontWeight.w500, color: c.ink, spacing: 1.6)),
          Text('RISK ${riskLabel(g.policeHeat)}', style: AppText.sans(size: 11, weight: FontWeight.w600, color: riskColor(c, g.policeHeat), spacing: 0.6)),
        ]),
        const SizedBox(height: 14),
        const LevelProgressBar(),
        const SizedBox(height: 18),
        Text('BALANCE', style: AppText.sans(size: 11, weight: FontWeight.w500, color: c.ink, spacing: 1.2)),
        const SizedBox(height: 6),
        Text(money(g.cash), style: AppText.mono(size: 44, weight: FontWeight.w600, color: c.ink)),
        const SizedBox(height: 6),
        Text('month ${g.monthsAsLeader + 1} · last take ${money(g.lastMonthTake)}', style: AppText.sans(size: 11, weight: FontWeight.w500, color: c.ink)),
        Container(height: 1, color: c.lineSoft, margin: const EdgeInsets.symmetric(vertical: 22)),
        Text('SUPPLY: $remaining / ${g.stashKg} KG UNALLOCATED', style: AppText.label(c.inkFaint)),
        const SizedBox(height: 12),
        if (blocked)
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: c.warn.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
            child: Text(
              'Something needs your attention before you can close the month — check Crew or Territory.',
              style: AppText.sans(size: 13, weight: FontWeight.w600, color: c.warn, height: 1.4),
            ),
          )
        else ...[
          for (final d in kDistributors) ...[
            _DistributorRow(distributor: d),
            const SizedBox(height: 10),
          ],
          const SizedBox(height: 12),
          AppButton(kind: BtnKind.dark, full: true, height: 50, onTap: g.closeMonth, child: const Text('Close out the month')),
        ],
      ],
    );
  }
}

class _DistributorRow extends StatelessWidget {
  final Distributor distributor;
  const _DistributorRow({required this.distributor});

  @override
  Widget build(BuildContext context) {
    final g = AppScope.of(context);
    final c = AppColors.of(context);
    final kg = g.allocated[distributor.id] ?? 0;
    final remaining = g.stashKg - g.allocatedKg;

    return AppCard(
      padding: const EdgeInsets.all(14),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(distributor.name, style: AppText.sans(size: 14, weight: FontWeight.w600, color: c.ink)),
            Text('${money(distributor.pricePerKg.round())}/kg', style: AppText.sans(size: 11.5, weight: FontWeight.w500, color: c.inkFaint)),
          ]),
        ),
        IconButton(
          icon: Icon(Icons.remove_circle_outline, size: 20, color: kg > 0 ? c.ink : c.inkFaint),
          onPressed: kg > 0 ? () => g.allocate(distributor.id, kg - 5) : null,
        ),
        SizedBox(width: 34, child: Text('$kg', textAlign: TextAlign.center, style: AppText.mono(size: 14, color: c.ink))),
        IconButton(
          icon: Icon(Icons.add_circle_outline, size: 20, color: remaining > 0 ? c.ink : c.inkFaint),
          onPressed: remaining > 0 ? () => g.allocate(distributor.id, kg + 5) : null,
        ),
        const SizedBox(width: 4),
        IconButton(
          icon: Icon(Icons.keyboard_double_arrow_up, size: 20, color: remaining > 0 ? c.ink : c.inkFaint),
          tooltip: 'Send it all here',
          onPressed: remaining > 0 ? () => g.allocate(distributor.id, kg + remaining) : null,
        ),
      ]),
    );
  }
}
