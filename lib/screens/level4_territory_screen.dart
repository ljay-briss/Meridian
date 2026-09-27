import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
      children: [
        const ScreenHead('Territory'),
        if (g.doubleTroubleActive) ...[
          AppCard(
            child: Text(
              'Police and ${g.rivalCrewName} both circling — every distributor gets less reliable while both stay up.',
              style: AppText.sans(size: 13, weight: FontWeight.w600, color: c.neg, height: 1.4),
            ),
          ),
          const SizedBox(height: 14),
        ],
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
                    onTap: () {
                      HapticFeedback.heavyImpact();
                      g.respondIncursion('violence');
                    },
                    child: const Text('Send guys with guns'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: AppButton(
                    kind: BtnKind.ghost,
                    full: true,
                    onTap: () {
                      HapticFeedback.mediumImpact();
                      g.respondIncursion('negotiate');
                    },
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
            Align(
              alignment: Alignment.centerRight,
              child: Text(level4HeatTierLabel(level4HeatTierFor(g.policeHeat)),
                  style: AppText.sans(size: 11, weight: FontWeight.w600, color: riskColor(c, g.policeHeat), spacing: 0.5)),
            ),
            const SizedBox(height: 14),
            MeterBar(label: 'Cartel suspicion', value: g.cartelSuspicion, color: riskColor(c, g.cartelSuspicion)),
            const SizedBox(height: 14),
            MeterBar(label: 'Rival pressure', value: g.rivalPressure, color: riskColor(c, g.rivalPressure)),
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerRight,
              child: Text(level4RivalTierLabel(level4RivalTierFor(g.rivalPressure)),
                  style: AppText.sans(size: 11, weight: FontWeight.w600, color: riskColor(c, g.rivalPressure), spacing: 0.5)),
            ),
          ]),
        ),
      ],
    );
  }
}
