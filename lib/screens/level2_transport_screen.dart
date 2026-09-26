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
          const _IdlePanel(),
        ] else ...[
          MeterBar(label: 'This run\'s risk', value: g.runRisk.clamp(0.0, 1.0) * 100, color: riskColor(c, g.runRisk.clamp(0.0, 1.0) * 100)),
          const SizedBox(height: 18),
          Text('CHECKPOINT ${stage + 1}/${kCheckpoints.length}', style: AppText.label(c.inkFaint)),
          const SizedBox(height: 14),
          switch (g.checkpointPhase) {
            CheckpointPhase.gather => const _GatherPanel(),
            CheckpointPhase.approach => const _ApproachPanel(),
            CheckpointPhase.inspection => const _InspectionPanel(),
            CheckpointPhase.result => const _CheckpointResultPanel(),
          },
        ],
        // Only while the truck's idle between runs — mid-checkpoint isn't a
        // moment to duck out for a side job.
        if (g.sideHustleAvailable && stage == null) ...[
          const SizedBox(height: 14),
          const SideHustleCard(),
        ],
      ],
    );
  }
}

/// "Truck is loaded" idle screen — optional pre-run prep, then Begin run.
class _IdlePanel extends StatelessWidget {
  const _IdlePanel();

  @override
  Widget build(BuildContext context) {
    final g = AppScope.of(context);
    final c = AppColors.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('The truck is loaded. Eight hours to the crossing.', style: AppText.sans(size: 15, weight: FontWeight.w500, color: c.ink, height: 1.6)),
      const SizedBox(height: 18),
      Row(children: [
        Expanded(
          child: _PrepChip(
            label: 'Clean documents',
            cost: CareerController.kPrepDocsCost,
            active: g.prepDocsClean,
            onTap: g.prepCleanDocuments,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _PrepChip(
            label: 'Vehicle prep',
            cost: CareerController.kPrepVehicleCost,
            active: g.prepVehicleReady,
            onTap: g.prepVehicle,
          ),
        ),
      ]),
      const SizedBox(height: 20),
      AppButton(kind: BtnKind.dark, full: true, height: 50, onTap: g.beginRun, child: const Text('Begin run')),
    ]);
  }
}

class _PrepChip extends StatelessWidget {
  final String label;
  final int cost;
  final bool active;
  final VoidCallback onTap;
  const _PrepChip({required this.label, required this.cost, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final g = AppScope.of(context);
    final c = AppColors.of(context);
    final affordable = active || g.cash >= cost;
    return AppButton(
      kind: active ? BtnKind.primary : BtnKind.ghost,
      full: true,
      height: null,
      onTap: active || !affordable ? null : onTap,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(label, textAlign: TextAlign.center),
        const SizedBox(height: 3),
        Text(active ? 'READY' : money(cost),
            style: AppText.sans(size: 11, weight: FontWeight.w500, color: active ? c.primaryInk.withValues(alpha: 0.7) : c.inkFaint)),
      ]),
    );
  }
}

/// OBSERVE / CHECK VEHICLE / CONTINUE — the info-gathering beat before the
/// player has to commit to an approach.
class _GatherPanel extends StatelessWidget {
  const _GatherPanel();

  @override
  Widget build(BuildContext context) {
    final g = AppScope.of(context);
    final c = AppColors.of(context);
    final scenario = g.currentScenario;
    final memoryLine = g.checkpointMemoryLine;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        Text(scenario.title, style: AppText.sans(size: 16, weight: FontWeight.w700, color: c.ink, spacing: 0.2)),
        const SizedBox(width: 8),
        AppChip(tone: _kindTone(scenario.kind), child: Text(checkpointKindLabel(scenario.kind))),
      ]),
      const SizedBox(height: 14),
      KVRow('Patrol', Text(scenario.patrol, style: AppText.mono(size: 13, color: _statColor(c, scenario.patrol)))),
      KVRow('Traffic', Text(scenario.traffic, style: AppText.mono(size: 13, color: _statColor(c, scenario.traffic)))),
      KVRow('Inspection', Text(scenario.inspectionLevel, style: AppText.mono(size: 13, color: _statColor(c, scenario.inspectionLevel)))),
      const SizedBox(height: 16),
      Text(scenario.scene, style: AppText.sans(size: 14.5, weight: FontWeight.w500, color: c.ink, height: 1.6)),
      if (memoryLine != null) ...[
        const SizedBox(height: 8),
        Text(memoryLine, style: AppText.sans(size: 12.5, weight: FontWeight.w500, color: c.inkFaint, height: 1.4)),
      ],
      if (g.observedThisStop) ...[
        const SizedBox(height: 12),
        _InfoReveal(scenario.observeReveal),
      ],
      if (g.checkedVehicleThisStop) ...[
        const SizedBox(height: 12),
        _InfoReveal(g.vehicleRevealText),
      ],
      const SizedBox(height: 20),
      Row(children: [
        Expanded(
          child: AppButton(
            kind: BtnKind.ghost,
            full: true,
            onTap: g.observedThisStop ? null : g.observeCheckpoint,
            child: const Text('Observe'),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: AppButton(
            kind: BtnKind.ghost,
            full: true,
            onTap: g.checkedVehicleThisStop ? null : g.checkVehicle,
            child: const Text('Check vehicle'),
          ),
        ),
      ]),
      const SizedBox(height: 10),
      AppButton(kind: BtnKind.dark, full: true, height: 50, onTap: g.proceedToApproach, child: const Text('Continue')),
    ]);
  }

  ChipTone _kindTone(CheckpointKind k) => switch (k) {
        CheckpointKind.routine => ChipTone.neutral,
        CheckpointKind.unusual => ChipTone.warn,
        CheckpointKind.heightened => ChipTone.warn,
        CheckpointKind.trap => ChipTone.neg,
      };

  Color _statColor(AppColors c, String level) => switch (level) {
        'LOW' => c.pos,
        'HIGH' => c.neg,
        _ => c.warn,
      };
}

/// A revealed OBSERVE/CHECK VEHICLE detail, styled like the run's warning
/// banner but quieter — informational, not a caution.
class _InfoReveal extends StatelessWidget {
  final String text;
  const _InfoReveal(this.text);
  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Container(
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(color: c.surfaceAlt, borderRadius: BorderRadius.circular(10), border: Border.all(color: c.line)),
      child: Text(text, style: AppText.sans(size: 12.5, weight: FontWeight.w500, color: c.inkSoft, height: 1.4)),
    );
  }
}

/// WHAT'S YOUR MOVE? — the real decision: which approach, and what it costs.
class _ApproachPanel extends StatelessWidget {
  const _ApproachPanel();

  @override
  Widget build(BuildContext context) {
    final g = AppScope.of(context);
    final c = AppColors.of(context);
    final checkpoint = kCheckpoints[g.runStage!];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('WHAT\'S YOUR MOVE?', style: AppText.label(c.inkFaint)),
      const SizedBox(height: 14),
      for (final approach in checkpoint.approaches)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: AppButton(
            kind: BtnKind.ghost,
            full: true,
            height: null,
            onTap: g.cash >= approach.cost ? () => g.chooseApproach(approach) : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(approach.label),
                const SizedBox(height: 4),
                Text(
                  [
                    approach.cost > 0 ? '-${money(approach.cost)}' : '\$0',
                    'risk +${(approach.riskDelta * 100).round()}',
                    if (approach.heatDelta > 0) 'heat +${approach.heatDelta.toStringAsFixed(1)}',
                    if (approach.skipsInspection) 'skips inspection',
                  ].join(' · '),
                  style: AppText.sans(size: 11, weight: FontWeight.w500, color: c.inkFaint),
                ),
              ]),
            ),
          ),
        ),
    ]);
  }
}

/// BORDER INSPECTION — the officer's question and the player's read on it.
class _InspectionPanel extends StatelessWidget {
  const _InspectionPanel();

  @override
  Widget build(BuildContext context) {
    final g = AppScope.of(context);
    final c = AppColors.of(context);
    final checkpoint = kCheckpoints[g.runStage!];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(g.currentScenario.title.contains('K9') ? 'K9 CHECK' : 'INSPECTION', style: AppText.label(c.inkFaint)),
      const SizedBox(height: 14),
      Text('Officer:', style: AppText.sans(size: 12, weight: FontWeight.w600, color: c.inkFaint)),
      const SizedBox(height: 6),
      Text('"${checkpoint.officerQuestion}"', style: AppText.sans(size: 16, weight: FontWeight.w600, color: c.ink, height: 1.4)),
      const SizedBox(height: 20),
      for (final response in checkpoint.responses)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: AppButton(
            kind: BtnKind.ghost,
            full: true,
            onTap: () => g.respondToInspection(response),
            child: Text(response.label),
          ),
        ),
    ]);
  }
}

/// CLEAR / SECONDARY INSPECTION / CHECKPOINT FAILED — the quick beat a
/// checkpoint stop ends on before moving to the next one (or the run's own
/// resolution panel, for a failed stop).
class _CheckpointResultPanel extends StatelessWidget {
  const _CheckpointResultPanel();

  @override
  Widget build(BuildContext context) {
    final g = AppScope.of(context);
    final c = AppColors.of(context);
    final headline = g.checkpointHeadline ?? 'CLEAR';
    final color = headline == 'CLEAR' ? c.pos : (headline == 'SECONDARY INSPECTION' ? c.warn : c.neg);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (g.suspicion > 0) ...[
        _SuspicionDots(level: g.suspicion),
        const SizedBox(height: 16),
      ],
      Text(headline, style: AppText.sans(size: 19, weight: FontWeight.w700, color: color, spacing: 0.6)),
      const SizedBox(height: 10),
      Text(g.checkpointBody ?? '', style: AppText.sans(size: 13.5, weight: FontWeight.w500, color: c.inkSoft, height: 1.4)),
      const SizedBox(height: 22),
      AppButton(kind: BtnKind.dark, full: true, height: 50, onTap: g.advanceCheckpoint, child: const Text('Continue')),
    ]);
  }
}

class _SuspicionDots extends StatelessWidget {
  final int level; // 0..5
  const _SuspicionDots({required this.level});
  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final dotColor = level >= 3 ? c.neg : c.warn;
    return Row(children: [
      Text('SUSPICION ', style: AppText.label(c.inkFaint)),
      for (int i = 0; i < 5; i++)
        Padding(
          padding: const EdgeInsets.only(right: 4),
          child: Text(i < level ? '●' : '○', style: TextStyle(fontSize: 14, color: i < level ? dotColor : c.line)),
        ),
    ]);
  }
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
