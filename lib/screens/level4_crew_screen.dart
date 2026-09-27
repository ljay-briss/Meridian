import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme.dart';
import '../controller.dart';
import '../data.dart';
import '../widgets.dart';

/// Level 4 — Crew tab: roster, loyalty, and discipline events.
class Level4CrewScreen extends StatelessWidget {
  const Level4CrewScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final g = AppScope.of(context);
    final c = AppColors.of(context);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
      children: [
        const ScreenHead('Crew', sub: '10 men on the payroll'),
        if (g.pendingTrouble != null) ...[
          AppCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const AppChip(tone: ChipTone.warn, child: Text('TROUBLE')),
              const SizedBox(height: 10),
              Text(
                kCrewTroubleEvents[g.pendingTrouble.hashCode % kCrewTroubleEvents.length].replaceFirst('{name}', g.pendingTrouble!),
                style: AppText.sans(size: 14, weight: FontWeight.w500, color: c.ink, height: 1.5),
              ),
              const SizedBox(height: 16),
              Row(children: [
                Expanded(
                  child: AppButton(
                    kind: BtnKind.ghost,
                    full: true,
                    onTap: () {
                      HapticFeedback.mediumImpact();
                      g.discipline(g.pendingTrouble!, 'beating');
                    },
                    child: const Text('Beat him'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: AppButton(
                    kind: BtnKind.danger,
                    full: true,
                    onTap: () {
                      HapticFeedback.heavyImpact();
                      g.discipline(g.pendingTrouble!, 'kill');
                    },
                    child: const Text('Kill him'),
                  ),
                ),
              ]),
            ]),
          ),
          const SizedBox(height: 14),
        ],
        for (final name in g.crewNames) ...[
          AppCard(
            padding: const EdgeInsets.all(14),
            child: Row(children: [
              ContactAvatar(name.substring(0, 1)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(name, style: AppText.sans(size: 14, weight: FontWeight.w600, color: c.ink)),
                  const SizedBox(height: 6),
                  MeterBar(label: 'Loyalty', value: (g.crewLoyalty[name] ?? 0) * 100, color: c.pos),
                ]),
              ),
            ]),
          ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}
