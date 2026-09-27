import 'package:flutter/material.dart';
import '../theme.dart';
import '../controller.dart';
import '../data.dart';
import '../widgets.dart';

/// Level 4 — Territory tab: incursion response + exposure overview.
class Level4TerritoryScreen extends StatelessWidget {
  const Level4TerritoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final g = AppScope.of(context);
    final c = AppColors.of(context);
    final bothHigh = g.policeHeat >= 60 && g.rivalPressure >= 60;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
      children: [
        const ScreenHead('Territory'),
        if (g.pendingIncursion != null) ...[
          AppCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const AppChip(tone: ChipTone.neg, child: Text('INCURSION')),
              const SizedBox(height: 10),
              Text(g.pendingIncursion!, style: AppText.sans(size: 14, weight: FontWeight.w500, color: c.ink, height: 1.5)),
              const SizedBox(height: 16),
              Row(children: [
                Expanded(
                  child: AppButton(
                    kind: BtnKind.danger,
                    full: true,
                    onTap: () => g.respondIncursion('violence'),
                    child: const Text('Send guys with guns'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: AppButton(
                    kind: BtnKind.ghost,
                    full: true,
                    onTap: () => g.respondIncursion('negotiate'),
                    child: const Text('Pay them off'),
                  ),
                ),
              ]),
            ]),
          ),
          const SizedBox(height: 14),
        ] else
          AppCard(
            child: Text('The corner is quiet for now.', style: AppText.sans(size: 14, weight: FontWeight.w500, color: c.inkSoft)),
          ),
        const SizedBox(height: 14),
        const SectionHead('Exposure'),
        AppCard(
          child: Column(children: [
            MeterBar(label: 'Police heat', value: g.policeHeat, color: riskColor(c, g.policeHeat)),
            const SizedBox(height: 4),
            Align(alignment: Alignment.centerLeft, child: Text(policeHeatTierLabel(g.policeHeat), style: AppText.sans(size: 11, weight: FontWeight.w600, color: riskColor(c, g.policeHeat), spacing: 0.6))),
            const SizedBox(height: 16),
            MeterBar(label: 'Cartel suspicion', value: g.cartelSuspicion, color: riskColor(c, g.cartelSuspicion)),
            const SizedBox(height: 16),
            MeterBar(label: 'Rival pressure', value: g.rivalPressure, color: riskColor(c, g.rivalPressure)),
            const SizedBox(height: 4),
            Align(alignment: Alignment.centerLeft, child: Text(rivalTierLabel(g.rivalPressure), style: AppText.sans(size: 11, weight: FontWeight.w600, color: riskColor(c, g.rivalPressure), spacing: 0.6))),
          ]),
        ),
        if (bothHigh) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: c.neg.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
            child: Text(
              'Police and rivals are both a real problem right now. Every distributor is less reliable while both stay this high.',
              style: AppText.sans(size: 12.5, weight: FontWeight.w600, color: c.neg, height: 1.4),
            ),
          ),
        ],
        const SizedBox(height: 14),
        const SectionHead('Ease off'),
        Row(children: [
          Expanded(
            child: AppButton(
              kind: BtnKind.ghost,
              full: true,
              height: null,
              onTap: g.policeHeat > 0 && g.cash >= g.policeHeatReliefCost ? g.reducePoliceHeat : null,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(children: [
                  const Text('Lay low'),
                  const SizedBox(height: 2),
                  Text('-${money(g.policeHeatReliefCost)}', style: AppText.sans(size: 11, weight: FontWeight.w500, color: c.inkFaint)),
                ]),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: AppButton(
              kind: BtnKind.ghost,
              full: true,
              height: null,
              onTap: g.rivalPressure > 0 && g.cash >= g.rivalPayoffCost ? g.payOffRival : null,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(children: [
                  const Text('Pay off rivals'),
                  const SizedBox(height: 2),
                  Text('-${money(g.rivalPayoffCost)}', style: AppText.sans(size: 11, weight: FontWeight.w500, color: c.inkFaint)),
                ]),
              ),
            ),
          ),
        ]),
      ],
    );
  }
}
