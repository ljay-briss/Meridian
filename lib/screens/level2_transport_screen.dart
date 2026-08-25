import 'package:flutter/material.dart';
import '../theme.dart';
import '../controller.dart';
import '../data.dart';
import '../widgets.dart';

/// Level 2 — Transporter.
class TransportScreen extends StatelessWidget {
  const TransportScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final g = AppScope.of(context);
    final c = AppColors.of(context);
    final stage = g.runStage;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
      children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text('LEVEL 2 — TRANSPORTER', style: AppText.sans(size: 10, weight: FontWeight.w500, color: c.ink, spacing: 1.6)),
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Text('STRIKES ${g.transportStrikes}/2', style: AppText.sans(size: 11, weight: FontWeight.w500, color: g.transportStrikes > 0 ? c.neg : c.ink, spacing: 0.6)),
                const SizedBox(width: 10),
                Text('RISK ', style: AppText.sans(size: 11, weight: FontWeight.w500, color: c.ink, spacing: 0.6)),
                Text(riskLabel(g.policeHeat), style: AppText.sans(size: 11, weight: FontWeight.w600, color: riskColor(c, g.policeHeat), spacing: 0.6)),
              ]),
            ),
          ),
        ]),
        const SizedBox(height: 14),
        const LevelProgressBar(),
        const SizedBox(height: 18),
        Text('BALANCE', style: AppText.sans(size: 11, weight: FontWeight.w500, color: c.ink, spacing: 1.2)),
        const SizedBox(height: 6),
        Text(money(g.cash), style: AppText.mono(size: 44, weight: FontWeight.w600, color: c.ink)),
        const SizedBox(height: 6),
        Text('pay: \$3,000/run · ${g.successfulRuns} runs clean',
            style: AppText.sans(size: 11, weight: FontWeight.w500, color: c.ink)),
        Container(height: 1, color: c.lineSoft, margin: const EdgeInsets.symmetric(vertical: 26)),
        if (g.lastWarning != null) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: c.warn.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
            child: Text(g.lastWarning!, style: AppText.sans(size: 12.5, weight: FontWeight.w600, color: c.warn, height: 1.4)),
          ),
          const SizedBox(height: 16),
        ],
        if (stage == null) ...[
          Text('The truck is loaded. Eight hours to the crossing.', style: AppText.sans(size: 15, weight: FontWeight.w500, color: c.ink, height: 1.6)),
          const SizedBox(height: 20),
          AppButton(kind: BtnKind.dark, full: true, height: 50, onTap: g.beginRun, child: const Text('Begin run')),
        ] else ...[
          Builder(builder: (context) {
            final checkpoint = kCheckpoints[stage];
            return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('CHECKPOINT ${stage + 1}/${kCheckpoints.length}', style: AppText.label(c.inkFaint)),
              const SizedBox(height: 10),
              Text(checkpoint.scene, style: AppText.sans(size: 15, weight: FontWeight.w500, color: c.ink, height: 1.6)),
              const SizedBox(height: 20),
              for (final choice in checkpoint.choices)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: AppButton(
                    kind: BtnKind.ghost,
                    full: true,
                    onTap: g.cash >= choice.cost ? () => g.chooseCheckpoint(choice) : null,
                    child: Text(choice.cost > 0 ? '${choice.label} (${money(choice.cost)})' : choice.label),
                  ),
                ),
            ]);
          }),
        ],
      ],
    );
  }
}
