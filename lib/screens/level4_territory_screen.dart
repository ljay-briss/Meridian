import 'package:flutter/material.dart';
import '../theme.dart';
import '../controller.dart';
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
            const SizedBox(height: 14),
            MeterBar(label: 'Cartel suspicion', value: g.cartelSuspicion, color: riskColor(c, g.cartelSuspicion)),
          ]),
        ),
      ],
    );
  }
}
