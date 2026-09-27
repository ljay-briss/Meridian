import 'package:flutter/material.dart';
import '../theme.dart';
import '../controller.dart';
import '../data.dart';
import '../widgets.dart';

String _signed(double v) => '${v >= 0 ? '+' : ''}${v.round()}';

/// Level 4 — Cell Leader (Home tab): the monthly decision loop. A pending
/// situation (if any) blocks distribution the same way crew trouble /
/// incursions already do; otherwise this is balance + exposure at a glance,
/// a live projected outcome, and the distributor allocation itself.
class CellLeaderScreen extends StatelessWidget {
  const CellLeaderScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final g = AppScope.of(context);
    final c = AppColors.of(context);
    final blocked = g.pendingIncursion != null || g.pendingTrouble != null;
    final situation = g.pendingSituation;
    final remaining = g.stashKg - g.allocatedKg;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
      children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text('LEVEL 4 — CELL LEADER', style: AppText.sans(size: 10, weight: FontWeight.w500, color: c.ink, spacing: 1.6)),
          Text('MONTH ${g.monthsAsLeader + 1}', style: AppText.sans(size: 11, weight: FontWeight.w600, color: c.inkFaint, spacing: 0.6)),
        ]),
        const SizedBox(height: 14),
        const LevelProgressBar(),
        const SizedBox(height: 18),
        Text('BALANCE', style: AppText.sans(size: 11, weight: FontWeight.w500, color: c.ink, spacing: 1.2)),
        const SizedBox(height: 6),
        Text(money(g.cash), style: AppText.mono(size: 44, weight: FontWeight.w600, color: cashColor(c, g.cash))),
        const SizedBox(height: 6),
        Text('last take ${money(g.lastMonthTake)}', style: AppText.sans(size: 11, weight: FontWeight.w500, color: c.ink)),
        Container(height: 1, color: c.lineSoft, margin: const EdgeInsets.symmetric(vertical: 18)),
        _TierMeter(label: 'Police heat', value: g.policeHeat, tierLabel: policeHeatTierLabel(g.policeHeat)),
        const SizedBox(height: 14),
        _TierMeter(label: 'Rival pressure', value: g.rivalPressure, tierLabel: rivalTierLabel(g.rivalPressure)),
        const SizedBox(height: 14),
        Text('SUPPLY: $remaining / ${g.stashKg} KG UNALLOCATED', style: AppText.label(c.inkFaint)),
        const SizedBox(height: 16),
        if (g.lastSituationOutcome != null) ...[
          _DismissibleNote(text: g.lastSituationOutcome!),
          const SizedBox(height: 14),
        ],
        if (situation != null)
          _SituationCard(situation: situation)
        else if (blocked)
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: c.warn.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
            child: Text(
              'Something needs your attention before you can close the month — check Crew or Territory.',
              style: AppText.sans(size: 13, weight: FontWeight.w600, color: c.warn, height: 1.4),
            ),
          )
        else ...[
          const _ProjectedOutcomePanel(),
          const SizedBox(height: 14),
          for (final d in kDistributors) ...[
            _DistributorRow(distributor: d),
            const SizedBox(height: 10),
          ],
          const SizedBox(height: 4),
          AppButton(
            kind: BtnKind.dark,
            full: true,
            height: 50,
            onTap: g.level4Busy ? null : g.closeMonth,
            child: Text(g.level4Busy ? 'Settling up…' : 'Close out the month'),
          ),
        ],
        // Always on offer, even with a crisis blocking the month-close button.
        if (g.sideHustleAvailable) ...[
          const SizedBox(height: 14),
          const SideHustleCard(),
        ],
      ],
    );
  }
}

/// A 0-100 meter with its named threshold band underneath (WATCHED, ACTIVE
/// INVESTIGATION, …) instead of a generic LOW/ELEVATED/HIGH read — the
/// band is what actually drives Level 4's math, so it's what's shown.
class _TierMeter extends StatelessWidget {
  final String label;
  final double value;
  final String tierLabel;
  const _TierMeter({required this.label, required this.value, required this.tierLabel});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final color = riskColor(c, value);
    final emphasize = value >= 60;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      MeterBar(label: label, value: value, color: color),
      const SizedBox(height: 4),
      Text(
        tierLabel,
        style: AppText.sans(size: 11, weight: emphasize ? FontWeight.w700 : FontWeight.w500, color: color, spacing: 0.6),
      ),
    ]);
  }
}

class _DismissibleNote extends StatelessWidget {
  final String text;
  const _DismissibleNote({required this.text});
  @override
  Widget build(BuildContext context) {
    final g = AppScope.of(context);
    final c = AppColors.of(context);
    return AppCard(
      padding: const EdgeInsets.all(12),
      child: Row(children: [
        Expanded(child: Text(text, style: AppText.sans(size: 12.5, weight: FontWeight.w500, color: c.inkSoft, height: 1.4))),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: g.dismissSituationOutcome,
          child: Icon(Icons.close, size: 16, color: c.inkFaint),
        ),
      ]),
    );
  }
}

class _SituationCard extends StatelessWidget {
  final MonthlySituation situation;
  const _SituationCard({required this.situation});

  @override
  Widget build(BuildContext context) {
    final g = AppScope.of(context);
    final c = AppColors.of(context);
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const AppChip(tone: ChipTone.warn, child: Text('THIS MONTH')),
        const SizedBox(height: 10),
        Text(situation.title, style: AppText.sans(size: 15, weight: FontWeight.w700, color: c.ink, spacing: 0.3)),
        const SizedBox(height: 6),
        Text(g.fillSituationText(situation.body), style: AppText.sans(size: 13.5, weight: FontWeight.w500, color: c.inkSoft, height: 1.5)),
        const SizedBox(height: 16),
        for (final option in situation.options) ...[
          AppButton(
            kind: BtnKind.ghost,
            full: true,
            height: null,
            onTap: () => g.respondSituation(option.id),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(children: [
                Text(option.label, style: AppText.sans(size: 13.5, weight: FontWeight.w700, color: c.ink)),
                const SizedBox(height: 2),
                Text(g.fillSituationText(option.subtext), textAlign: TextAlign.center, style: AppText.sans(size: 11.5, weight: FontWeight.w500, color: c.inkSoft, height: 1.35)),
              ]),
            ),
          ),
          if (option != situation.options.last) const SizedBox(height: 8),
        ],
      ]),
    );
  }
}

/// Updates live as the player drags allocations around — the "do I want
/// another $1,500 if it pushes me into the next heat tier?" panel.
class _ProjectedOutcomePanel extends StatelessWidget {
  const _ProjectedOutcomePanel();
  @override
  Widget build(BuildContext context) {
    final g = AppScope.of(context);
    final c = AppColors.of(context);
    final risk = g.projectedDistributorRisk;
    final riskTone = switch (risk) {
      'HIGH' => ChipTone.neg,
      'MEDIUM' => ChipTone.warn,
      'LOW' => ChipTone.pos,
      _ => ChipTone.neutral,
    };
    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Column(children: [
        KVRow('Projected take', Text(money(g.projectedTake), style: AppText.mono(size: 14, color: c.ink))),
        KVRow('Police heat', Text(_signed(g.projectedPoliceHeatDelta), style: AppText.mono(size: 14, color: riskColor(c, g.policeHeat + g.projectedPoliceHeatDelta)))),
        KVRow('Rival pressure', Text(_signed(g.projectedRivalPressureDelta), style: AppText.mono(size: 14, color: riskColor(c, g.rivalPressure + g.projectedRivalPressureDelta)))),
        KVRow('Distributor risk', AppChip(tone: riskTone, child: Text(risk))),
      ]),
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
    final st = g.distributorState[distributor.id];
    final reliability = g.distributorReliability(distributor.id);
    final wants = st?.orderKg ?? distributor.baseOrderKg;
    final chainStage = st?.chainStage ?? 0;

    return AppCard(
      padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(distributor.name, style: AppText.sans(size: 14.5, weight: FontWeight.w700, color: c.ink)),
              const SizedBox(height: 2),
              Text('Wants $wants KG · ${money(distributor.basePricePerKg.round())}/kg', style: AppText.sans(size: 11.5, weight: FontWeight.w500, color: c.inkFaint)),
            ]),
          ),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text('${(reliability * 100).round()}%', style: AppText.mono(size: 13, weight: FontWeight.w600, color: c.ink)),
            Text('RELIABILITY', style: AppText.sans(size: 8.5, weight: FontWeight.w600, color: c.inkFaint, spacing: 0.8)),
          ]),
          const SizedBox(width: 10),
          AppChip(tone: _exposureTone(distributor.exposure), child: Text(exposureLabel(distributor.exposure))),
        ]),
        if (chainStage > 0) ...[
          const SizedBox(height: 8),
          AppChip(
            tone: chainStage >= 2 ? ChipTone.neg : ChipTone.warn,
            child: Text(chainStage >= 2 ? 'SUPPLYING A RIVAL' : 'LOSING PATIENCE'),
          ),
        ],
        const SizedBox(height: 10),
        Row(children: [
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
          const Spacer(),
          if ((st?.trust ?? 1.0) < 0.6)
            IconButton(
              icon: Icon(Icons.handshake_outlined, size: 20, color: g.cash >= 1200 ? c.pos : c.inkFaint),
              tooltip: 'Rebuild trust — \$1,200',
              onPressed: g.cash >= 1200 ? () => g.reassureDistributor(distributor.id) : null,
            ),
        ]),
      ]),
    );
  }

  ChipTone _exposureTone(ExposureLevel e) {
    switch (e) {
      case ExposureLevel.low:
        return ChipTone.pos;
      case ExposureLevel.medium:
        return ChipTone.warn;
      case ExposureLevel.high:
        return ChipTone.neg;
    }
  }
}
