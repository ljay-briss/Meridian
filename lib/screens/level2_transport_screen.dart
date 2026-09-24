import 'package:flutter/material.dart';
import '../theme.dart';
import '../controller.dart';
import '../data.dart';
import '../widgets.dart';
import 'level2_bribe_tap_screen.dart';

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
                Text('RISK ', style: AppText.sans(size: 11, weight: FontWeight.w500, color: c.ink, spacing: 0.6)),
                Text(riskLabel(g.policeHeat), style: AppText.sans(size: 11, weight: FontWeight.w600, color: riskColor(c, g.policeHeat), spacing: 0.6)),
              ]),
            ),
          ),
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
        Text('pay: \$1,000/run · ${g.successfulRuns} runs clean',
            style: AppText.sans(size: 11, weight: FontWeight.w500, color: c.ink)),
        Container(height: 1, color: c.lineSoft, margin: const EdgeInsets.symmetric(vertical: 26)),
        // Suppressed while the result panel is up — it already says this.
        if (g.lastWarning != null && g.lastRunOutcome == null) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: c.warn.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
            child: Text(g.lastWarning!, style: AppText.sans(size: 12.5, weight: FontWeight.w600, color: c.warn, height: 1.4)),
          ),
          const SizedBox(height: 16),
        ],
        if (g.lastRunOutcome != null) ...[
          _RunResultPanel(outcome: g.lastRunOutcome!),
        ] else if (stage == null) ...[
          Text('The truck is loaded. Eight hours to the crossing.', style: AppText.sans(size: 15, weight: FontWeight.w500, color: c.ink, height: 1.6)),
          const SizedBox(height: 20),
          AppButton(kind: BtnKind.dark, full: true, height: 50, onTap: g.beginRun, child: const Text('Begin run')),
        ] else ...[
          Builder(builder: (context) {
            final checkpoint = kCheckpoints[stage];
            return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('CHECKPOINT ${stage + 1}/${kCheckpoints.length}', style: AppText.label(c.inkFaint)),
              const SizedBox(height: 10),
              MeterBar(label: 'This run\'s risk', value: g.runRisk.clamp(0.0, 1.0) * 100, color: riskColor(c, g.runRisk.clamp(0.0, 1.0) * 100)),
              const SizedBox(height: 18),
              Text(g.checkpointVariantAt(stage).scene, style: AppText.sans(size: 15, weight: FontWeight.w500, color: c.ink, height: 1.6)),
              const SizedBox(height: 20),
              for (final choice in checkpoint.choices)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: AppButton(
                    kind: BtnKind.ghost,
                    full: true,
                    onTap: choice.cost == 0 || g.cash >= choice.cost
                        ? () => choice.cost > 0 ? _attemptBribe(context, g, choice) : g.chooseCheckpoint(choice)
                        : null,
                    child: Text(choice.cost > 0 ? '${choice.label} (${money(choice.cost)})' : choice.label),
                  ),
                ),
            ]);
          }),
        ],
        // Always on offer, whether the truck is idle or mid-checkpoint —
        // not just while waiting for the next run to begin.
        if (g.sideHustleAvailable) ...[
          const SizedBox(height: 14),
          const SideHustleCard(),
        ],
      ],
    );
  }
}

/// Sends the player through the timing-tap before actually committing to a
/// bribe choice — a null result means they backed out of that screen
/// without playing, so nothing is spent and the checkpoint doesn't advance.
Future<void> _attemptBribe(BuildContext context, CareerController g, CheckpointChoice choice) async {
  final won = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => const BribeTapScreen()));
  if (won == null) return;
  g.chooseCheckpoint(choice, tapSucceeded: won);
}

/// The resolution beat a run ends on — clean or caught, in the player's
/// face for a moment instead of silently updating the balance and dropping
/// back to idle. Mirrors the win/lose panel the side-hustle minigames use.
class _RunResultPanel extends StatelessWidget {
  final RunOutcome outcome;
  const _RunResultPanel({required this.outcome});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final g = AppScope.of(context);
    final color = outcome.caught ? c.neg : c.pos;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(outcome.caught ? 'CAUGHT' : 'CLEAN RUN', style: AppText.sans(size: 20, weight: FontWeight.w700, color: color, spacing: 1)),
      const SizedBox(height: 12),
      Text(signedMoney(outcome.cashDelta), style: AppText.mono(size: 34, weight: FontWeight.w700, color: color)),
      if (outcome.caught) ...[
        const SizedBox(height: 10),
        Text('Had to pay your way out — no cargo, no pay this run.', style: AppText.sans(size: 13, weight: FontWeight.w500, color: c.inkSoft, height: 1.4)),
      ],
      const SizedBox(height: 24),
      AppButton(kind: BtnKind.dark, full: true, height: 50, onTap: g.acknowledgeRunOutcome, child: const Text('Continue')),
    ]);
  }
}
