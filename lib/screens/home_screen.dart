import 'package:flutter/material.dart';
import '../theme.dart';
import '../controller.dart';
import '../widgets.dart';

/// Level 1 — Plaza Lookout.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final g = AppScope.of(context);
    final c = AppColors.of(context);
    final sighting = g.sighting;

    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Text(g.dayLabel, style: AppText.sans(size: 11, weight: FontWeight.w500, color: c.ink, spacing: 0.6)),
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerRight,
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Text('STRIKES ${g.strikes}/2', style: AppText.sans(size: 11, weight: FontWeight.w500, color: g.strikes > 0 ? c.neg : c.ink, spacing: 0.6)),
                      const SizedBox(width: 10),
                      Text('RISK ', style: AppText.sans(size: 11, weight: FontWeight.w500, color: c.ink, spacing: 0.6)),
                      Text(riskLabel(g.policeHeat), style: AppText.sans(size: 11, weight: FontWeight.w600, color: riskColor(c, g.policeHeat), spacing: 0.6)),
                    ]),
                  ),
                ),
              ]),
              const SizedBox(height: 18),
              Text('LEVEL 1 — PLAZA LOOKOUT', style: AppText.sans(size: 10, weight: FontWeight.w500, color: c.ink, spacing: 1.6)),
              const SizedBox(height: 14),
              const LevelProgressBar(),
              const SizedBox(height: 22),
              Text('BALANCE', style: AppText.sans(size: 11, weight: FontWeight.w500, color: c.ink, spacing: 1.2)),
              const SizedBox(height: 6),
              Text(money(g.cash), style: AppText.mono(size: 52, weight: FontWeight.w600, color: c.ink)),
              const SizedBox(height: 8),
              Text(
                'pay: \$100/week · day ${g.day} · sighting ${g.sightingsToday + 1}/${CareerController.sightingsPerDay}',
                style: AppText.sans(size: 11, weight: FontWeight.w500, color: c.ink),
              ),
              Container(height: 1, color: c.lineSoft, margin: const EdgeInsets.symmetric(vertical: 30)),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: c.sunken, borderRadius: BorderRadius.circular(10)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('KEY', style: AppText.label(c.inkFaint)),
                  const SizedBox(height: 8),
                  const _KeyRow('"bird"', 'Military trucks'),
                  const SizedBox(height: 5),
                  const _KeyRow('"snake"', 'Rival cartel SUVs'),
                  const SizedBox(height: 5),
                  const _KeyRow('"clear"', 'Nothing to report'),
                ]),
              ),
              const SizedBox(height: 22),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Row(children: [
                  Container(width: 6, height: 6, decoration: BoxDecoration(shape: BoxShape.circle, color: c.ink)),
                  const SizedBox(width: 7),
                  Text('ON WATCH', style: AppText.sans(size: 11, weight: FontWeight.w500, color: c.ink, spacing: 1.2)),
                ]),
                if (sighting != null)
                  Text('${g.secondsRemaining}s',
                      style: AppText.mono(size: 11, weight: FontWeight.w700, color: _countdownColor(c, g.secondsRemaining))),
              ]),
              const SizedBox(height: 8),
              if (sighting != null)
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: Stack(children: [
                    Container(height: 4, color: c.sunken),
                    FractionallySizedBox(
                      widthFactor: (g.secondsRemaining / CareerController.responseWindowSeconds).clamp(0, 1),
                      alignment: Alignment.centerLeft,
                      child: Container(height: 4, color: _countdownColor(c, g.secondsRemaining)),
                    ),
                  ]),
                ),
              const SizedBox(height: 12),
              Text(
                sighting == null
                    ? 'The road is quiet. Nothing to report — yet.'
                    : sighting.description,
                style: AppText.sans(size: 15, weight: FontWeight.w500, color: c.ink, height: 1.6),
              ),
              if (g.lastWarning != null) ...[
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: c.warn.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
                  child: Text(g.lastWarning!, style: AppText.sans(size: 12.5, weight: FontWeight.w600, color: c.warn, height: 1.4)),
                ),
              ],
              const SizedBox(height: 22),
              if (sighting != null)
                Wrap(spacing: 8, runSpacing: 8, children: [
                  AppButton(kind: BtnKind.ghost, onTap: () => g.respond('bird'), child: const Text('"bird"')),
                  AppButton(kind: BtnKind.ghost, onTap: () => g.respond('snake'), child: const Text('"snake"')),
                  AppButton(kind: BtnKind.ghost, onTap: () => g.respond('clear'), child: const Text('"clear"')),
                ]),
              const SizedBox(height: 20),
            ]),
          ),
        ),
        RoadAnimation(sighting: sighting, sightingSeq: g.sightingSeq),
      ],
    );
  }
}

Color _countdownColor(AppColors c, int secondsRemaining) {
  if (secondsRemaining <= 5) return c.neg;
  if (secondsRemaining <= 10) return c.warn;
  return c.inkSoft;
}

class _KeyRow extends StatelessWidget {
  final String word;
  final String meaning;
  const _KeyRow(this.word, this.meaning);
  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Row(children: [
      SizedBox(width: 62, child: Text(word, style: AppText.mono(size: 12, weight: FontWeight.w600, color: c.ink))),
      const SizedBox(width: 8),
      Expanded(child: Text(meaning, style: AppText.sans(size: 12, weight: FontWeight.w500, color: c.inkSoft))),
    ]);
  }
}
