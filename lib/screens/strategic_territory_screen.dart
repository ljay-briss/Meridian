import 'package:flutter/material.dart';
import '../theme.dart';
import '../controller.dart';
import '../widgets.dart';

/// Levels 5-7 — Territory tab: map of controlled plazas + exposure.
class StrategicTerritoryScreen extends StatelessWidget {
  const StrategicTerritoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final g = AppScope.of(context);
    final c = AppColors.of(context);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
      children: [
        const ScreenHead('Territory'),
        if (g.territories.isEmpty)
          AppCard(child: Text('No territory map yet at this level.', style: AppText.sans(size: 13, weight: FontWeight.w500, color: c.inkFaint)))
        else
          for (final t in g.territories) ...[
            AppCard(
              padding: const EdgeInsets.all(14),
              child: Row(children: [
                Expanded(child: Text(t.name, style: AppText.sans(size: 14, weight: FontWeight.w600, color: c.ink))),
                if (t.controlled)
                  const AppChip(tone: ChipTone.pos, child: Text('CONTROLLED'))
                else
                  AppButton(
                    kind: BtnKind.ghost,
                    onTap: g.cash >= 3000000 ? () => g.seizeTerritory(t) : null,
                    child: const Text('Seize (\$3M)'),
                  ),
              ]),
            ),
            const SizedBox(height: 8),
          ],
        const SizedBox(height: 14),
        const SectionHead('Exposure'),
        AppCard(
          child: Column(children: [
            MeterBar(label: 'Police heat', value: g.policeHeat, color: riskColor(c, g.policeHeat)),
            const SizedBox(height: 14),
            MeterBar(label: 'Cartel suspicion', value: g.cartelSuspicion, color: riskColor(c, g.cartelSuspicion)),
            const SizedBox(height: 14),
            MeterBar(label: 'Rival heat', value: g.rivalPressure, color: riskColor(c, g.rivalPressure)),
          ]),
        ),
      ],
    );
  }
}
