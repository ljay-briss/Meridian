import 'package:flutter/material.dart';
import '../theme.dart';
import '../controller.dart';
import '../data.dart';
import '../widgets.dart';

/// Level 4 — Cell Leader (Home tab): monthly situation, distributor orders,
/// supply allocation, and the month-close payoff.
class CellLeaderScreen extends StatelessWidget {
  const CellLeaderScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final g = AppScope.of(context);
    final c = AppColors.of(context);
    final blocked = g.pendingIncursion != null || g.pendingTrouble != null;
    final remaining = g.stashKg - g.allocatedKg;
    final heatTier = level4HeatTierFor(g.policeHeat);
    final rivalTier = level4RivalTierFor(g.rivalPressure);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
      children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text('LEVEL 4 — CELL LEADER', style: AppText.sans(size: 10, weight: FontWeight.w500, color: c.ink, spacing: 1.6)),
          Text(level4HeatTierLabel(heatTier), style: AppText.sans(size: 11, weight: FontWeight.w600, color: riskColor(c, g.policeHeat), spacing: 0.6)),
        ]),
        const SizedBox(height: 14),
        const LevelProgressBar(),
        const SizedBox(height: 18),
        MeterBar(label: 'Police heat', value: g.policeHeat, color: riskColor(c, g.policeHeat)),
        const SizedBox(height: 4),
        Align(
          alignment: Alignment.centerRight,
          child: Text(level4HeatTierLabel(heatTier),
              style: AppText.sans(size: 11, weight: FontWeight.w600, color: riskColor(c, g.policeHeat), spacing: 0.5)),
        ),
        const SizedBox(height: 14),
        MeterBar(label: 'Rival pressure', value: g.rivalPressure, color: riskColor(c, g.rivalPressure)),
        const SizedBox(height: 4),
        Align(
          alignment: Alignment.centerRight,
          child: Text(level4RivalTierLabel(rivalTier),
              style: AppText.sans(size: 11, weight: FontWeight.w600, color: riskColor(c, g.rivalPressure), spacing: 0.5)),
        ),
        if (g.doubleTroubleActive) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(color: c.neg.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
            child: Text('Police and rivals are both circling — every distributor gets shakier while this holds.',
                style: AppText.sans(size: 12, weight: FontWeight.w600, color: c.neg, height: 1.35)),
          ),
        ],
        const SizedBox(height: 18),
        Text('BALANCE', style: AppText.sans(size: 11, weight: FontWeight.w500, color: c.ink, spacing: 1.2)),
        const SizedBox(height: 6),
        Text(money(g.cash), style: AppText.mono(size: 44, weight: FontWeight.w600, color: cashColor(c, g.cash))),
        const SizedBox(height: 6),
        Text('month ${g.monthsAsLeader + 1} · last take ${money(g.lastMonthTake)}', style: AppText.sans(size: 11, weight: FontWeight.w500, color: c.ink)),
        Container(height: 1, color: c.lineSoft, margin: const EdgeInsets.symmetric(vertical: 22)),
        if (g.currentSituation != null && !blocked) ...[
          const _SituationCard(),
          const SizedBox(height: 18),
        ],
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
            _DistributorCard(distributor: d),
            const SizedBox(height: 10),
          ],
          const SizedBox(height: 8),
          const _ProjectedOutcomeCard(),
          const SizedBox(height: 12),
          AppButton(
            kind: BtnKind.dark,
            full: true,
            height: 50,
            onTap: g.level4Busy ? null : () => _closeMonth(context, g),
            child: Text(g.level4Busy ? 'Settling up…' : 'Close out the month'),
          ),
        ],
        // Always on offer, even with a crew/territory crisis blocking the
        // month-close button — not just while otherwise idle.
        if (g.sideHustleAvailable) ...[
          const SizedBox(height: 14),
          const SideHustleCard(),
        ],
      ],
    );
  }

  Future<void> _closeMonth(BuildContext context, CareerController g) async {
    final resolution = g.closeMonth();
    if (resolution == null || g.gameOver || !context.mounted) return;
    await showAppSheet(context, 'MONTH ${resolution.monthNumber} COMPLETE', (ctx) => _MonthResolutionBody(resolution: resolution));
  }
}

/// The month's decision point — see [CareerController.currentSituation]. Shows
/// the options until one is picked (or the month closes without one, at
/// which point the resolution card explains what got applied by default).
class _SituationCard extends StatelessWidget {
  const _SituationCard();
  @override
  Widget build(BuildContext context) {
    final g = AppScope.of(context);
    final c = AppColors.of(context);
    final situation = g.currentSituation;
    if (situation == null) return const SizedBox.shrink();
    final chosen = g.currentSituationChoiceId;

    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          AppChip(tone: chosen == null ? ChipTone.warn : ChipTone.neutral, child: Text(situation.title)),
          if (chosen != null) Text('DECIDED', style: AppText.sans(size: 10.5, weight: FontWeight.w600, color: c.inkFaint, spacing: 0.8)),
        ]),
        const SizedBox(height: 10),
        Text(g.currentSituationDescription ?? '', style: AppText.sans(size: 14, weight: FontWeight.w500, color: c.ink, height: 1.5)),
        const SizedBox(height: 14),
        if (chosen == null)
          Column(children: [
            for (final option in situation.options) ...[
              _situationOptionButton(context, g, c, option),
              const SizedBox(height: 8),
            ],
          ])
        else
          Text(
            _filledResult(situation.options.firstWhere((o) => o.id == chosen, orElse: () => situation.options.last).resultLine, g),
            style: AppText.sans(size: 13, weight: FontWeight.w500, color: c.inkSoft, height: 1.4),
          ),
      ]),
    );
  }

  String _filledResult(String line, CareerController g) =>
      line.replaceAll('{rival}', g.rivalCrewName).replaceAll('{distributor}', _focusName(g));

  String _focusName(CareerController g) {
    final id = g.currentSituationFocusId;
    if (id == null) return '';
    return kDistributors.firstWhere((d) => d.id == id, orElse: () => kDistributors.first).name;
  }

  Widget _situationOptionButton(BuildContext context, CareerController g, AppColors c, MonthlySituationOption option) {
    final affordable = option.cashCost <= 0 || g.cash >= option.cashCost;
    final costLabel = option.cashCost > 0
        ? ' (${money(option.cashCost)})'
        : (option.cashCost < 0 ? ' (+${money(-option.cashCost)})' : '');
    return AppButton(
      kind: BtnKind.ghost,
      full: true,
      onTap: affordable ? () => g.chooseSituationOption(option.id) : null,
      child: Text('${option.label}$costLabel'),
    );
  }
}

class _ProjectedOutcomeCard extends StatelessWidget {
  const _ProjectedOutcomeCard();
  @override
  Widget build(BuildContext context) {
    final g = AppScope.of(context);
    final c = AppColors.of(context);
    final projection = g.projectedOutcome;
    final riskColorForLabel = switch (projection.riskLabel) {
      'HIGH' => c.neg,
      'MEDIUM' => c.warn,
      _ => c.pos,
    };
    return AppCard(
      child: Column(children: [
        KVRow('PROJECTED TAKE', Text(money(projection.projectedTake), style: AppText.mono(size: 14, weight: FontWeight.w600, color: c.ink))),
        KVRow('POLICE HEAT', Text('+${projection.projectedPoliceHeatDelta.round()}', style: AppText.mono(size: 14, weight: FontWeight.w600, color: c.warn))),
        KVRow('RIVAL PRESSURE', Text('+${projection.projectedRivalPressureDelta.round()}', style: AppText.mono(size: 14, weight: FontWeight.w600, color: c.warn))),
        KVRow('DISTRIBUTOR RISK', Text(projection.riskLabel, style: AppText.sans(size: 12.5, weight: FontWeight.w700, color: riskColorForLabel, spacing: 0.6))),
      ]),
    );
  }
}

class _DistributorCard extends StatelessWidget {
  final Distributor distributor;
  const _DistributorCard({required this.distributor});

  @override
  Widget build(BuildContext context) {
    final g = AppScope.of(context);
    final c = AppColors.of(context);
    final kg = g.allocated[distributor.id] ?? 0;
    final remaining = g.stashKg - g.allocatedKg;
    final wanted = g.demandFor(distributor.id);
    final reliability = (g.effectiveReliability(distributor) * 100).round();
    final price = g.effectivePricePerKg(distributor).round();
    final lost = g.distributorLostToRival.contains(distributor.id);
    final exposureTone = switch (distributor.exposure) {
      DistributorExposure.low => ChipTone.pos,
      DistributorExposure.medium => ChipTone.warn,
      DistributorExposure.high => ChipTone.neg,
    };
    final exposureLabel = switch (distributor.exposure) {
      DistributorExposure.low => 'LOW',
      DistributorExposure.medium => 'MEDIUM',
      DistributorExposure.high => 'HIGH',
    };

    return AppCard(
      padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Text(distributor.name.toUpperCase(), style: AppText.sans(size: 14, weight: FontWeight.w700, color: c.ink, spacing: 0.4)),
                if (lost) ...[
                  const SizedBox(width: 8),
                  AppChip(tone: ChipTone.neg, child: Text('SUPPLYING ${g.rivalCrewName.toUpperCase()}')),
                ],
              ]),
              const SizedBox(height: 3),
              Text('Wants $wanted KG · ${money(price)} / KG', style: AppText.sans(size: 11.5, weight: FontWeight.w500, color: c.inkFaint)),
              const SizedBox(height: 3),
              Row(children: [
                Text('Reliability $reliability%', style: AppText.sans(size: 11.5, weight: FontWeight.w500, color: c.inkSoft)),
                const SizedBox(width: 10),
                AppChip(tone: exposureTone, child: Text('EXPOSURE $exposureLabel')),
              ]),
            ]),
          ),
        ]),
        const SizedBox(height: 10),
        Row(mainAxisAlignment: MainAxisAlignment.end, children: [
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
      ]),
    );
  }
}

/// Body of the "month complete" sheet — the payoff [showAppSheet] shows
/// after [CareerController.closeMonth] instead of jumping straight to next month.
class _MonthResolutionBody extends StatelessWidget {
  final MonthResolution resolution;
  const _MonthResolutionBody({required this.resolution});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(signedMoney(resolution.take), style: AppText.mono(size: 32, weight: FontWeight.w700, color: cashColor(c, resolution.take))),
      const SizedBox(height: 18),
      if (resolution.situationSummary != null) ...[
        const TLabel('This month'),
        const SizedBox(height: 6),
        Text(resolution.situationSummary!, style: AppText.sans(size: 13, weight: FontWeight.w500, color: c.inkSoft, height: 1.4)),
        const SizedBox(height: 16),
      ],
      if (resolution.deliveries.isNotEmpty) ...[
        const TLabel('Deliveries'),
        const SizedBox(height: 6),
        for (final d in resolution.deliveries)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text('${d.distributorName} ${d.detail} — ${money(d.revenue)}',
                style: AppText.sans(size: 13, weight: FontWeight.w500, color: c.ink, height: 1.4)),
          ),
        const SizedBox(height: 16),
      ],
      if (resolution.policeHeatReasons.isNotEmpty) ...[
        const TLabel('Police'),
        const SizedBox(height: 6),
        for (final r in resolution.policeHeatReasons)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text('${signedMoney(r.amount).replaceFirst('\$', '')} — ${r.label}',
                style: AppText.sans(size: 13, weight: FontWeight.w500, color: r.amount >= 0 ? c.warn : c.pos, height: 1.4)),
          ),
        const SizedBox(height: 16),
      ],
      if (resolution.rivalPressureReasons.isNotEmpty) ...[
        const TLabel('Territory'),
        const SizedBox(height: 6),
        for (final r in resolution.rivalPressureReasons)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text('${signedMoney(r.amount).replaceFirst('\$', '')} — ${r.label}',
                style: AppText.sans(size: 13, weight: FontWeight.w500, color: r.amount >= 0 ? c.warn : c.pos, height: 1.4)),
          ),
        const SizedBox(height: 16),
      ],
      if (resolution.crewLines.isNotEmpty) ...[
        const TLabel('Crew'),
        const SizedBox(height: 6),
        for (final line in resolution.crewLines)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(line, style: AppText.sans(size: 13, weight: FontWeight.w500, color: c.ink, height: 1.4)),
          ),
        const SizedBox(height: 16),
      ],
      AppButton(full: true, height: 48, onTap: () => Navigator.pop(context), child: const Text('Next month')),
    ]);
  }
}
