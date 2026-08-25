import 'package:flutter/material.dart';
import '../theme.dart';
import '../controller.dart';
import '../data.dart';
import '../widgets.dart';

/// Levels 5-7 — Org tab: cell leaders (L5) or inner-circle paranoia (L6-7).
class StrategicOrgScreen extends StatelessWidget {
  const StrategicOrgScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final g = AppScope.of(context);
    final c = AppColors.of(context);

    if (g.level == 5) {
      final checkInsLeft = CareerController.maxCheckInsPerCycle - g.checkedInThisCycle.length;
      return ListView(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
        children: [
          const ScreenHead('Cell leaders', sub: 'Five cells reporting up to you'),
          if (g.pendingCellSkim != null) ...[
            _CellEventCard(
              tone: ChipTone.warn,
              label: 'SKIMMING',
              text: '${g.pendingCellSkim} has been skimming product and cash off the top.',
              primaryLabel: 'Discipline him',
              onPrimary: () => g.resolveCellSkim('discipline'),
              secondaryLabel: 'Let it slide',
              onSecondary: () => g.resolveCellSkim('ignore'),
            ),
            const SizedBox(height: 10),
          ],
          if (g.pendingCellPoach != null) ...[
            _CellEventCard(
              tone: ChipTone.neg,
              label: 'POACHING',
              text: 'A rival crew is trying to pull ${g.pendingCellPoach} away from you.',
              primaryLabel: 'Reassure him (${money(100000)})',
              onPrimary: () => g.resolveCellPoach('reassure'),
              secondaryLabel: 'Let it ride',
              onSecondary: () => g.resolveCellPoach('let_it_ride'),
            ),
            const SizedBox(height: 10),
          ],
          if (g.pendingCellShortage != null) ...[
            _CellEventCard(
              tone: ChipTone.warn,
              label: 'SHORTAGE',
              text: '${g.pendingCellShortage} is running short on product and can\'t move what they don\'t have.',
              primaryLabel: 'Reallocate supply (${money(50000)})',
              onPrimary: () => g.resolveCellShortage('reallocate'),
              secondaryLabel: 'Let them figure it out',
              onSecondary: () => g.resolveCellShortage('ignore'),
            ),
            const SizedBox(height: 10),
          ],
          Text('$checkInsLeft check-in${checkInsLeft == 1 ? '' : 's'} left this month', style: AppText.label(c.inkFaint)),
          const SizedBox(height: 10),
          for (final leader in g.cellLeaders) ...[
            _CellLeaderRow(
              leader: leader,
              checkedIn: g.checkedInThisCycle.contains(leader.name),
              canCheckIn: checkInsLeft > 0,
              onCheckIn: () => g.checkInOnCell(leader.name),
            ),
            const SizedBox(height: 8),
          ],
        ],
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
      children: [
        const ScreenHead('Inner circle'),
        AppCard(
          child: Text(
            g.level == 6
                ? 'Your security lead, your accountant, your right hand — any of them could be talking to the DEA. You watch, and you wait, and you rarely sleep.'
                : 'You rotate safe houses every three days. Even your own children might not recognize your face anymore.',
            style: AppText.sans(size: 14, weight: FontWeight.w500, color: c.inkSoft, height: 1.6),
          ),
        ),
        const SizedBox(height: 14),
        for (final id in g.innerCircleIds) ...[
          _CircleRow(member: kInnerCircle.firstWhere((m) => m.id == id), flagged: g.paranoiaTargetId == id),
          const SizedBox(height: 8),
        ],
        const SizedBox(height: 6),
        AppCard(
          child: Column(children: [
            MeterBar(label: 'Cartel suspicion of you', value: g.cartelSuspicion, color: riskColor(c, g.cartelSuspicion)),
          ]),
        ),
      ],
    );
  }
}

class _CellEventCard extends StatelessWidget {
  final ChipTone tone;
  final String label, text, primaryLabel, secondaryLabel;
  final VoidCallback onPrimary, onSecondary;
  const _CellEventCard({
    required this.tone,
    required this.label,
    required this.text,
    required this.primaryLabel,
    required this.onPrimary,
    required this.secondaryLabel,
    required this.onSecondary,
  });

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        AppChip(tone: tone, child: Text(label)),
        const SizedBox(height: 10),
        Text(text, style: AppText.sans(size: 14, weight: FontWeight.w500, color: c.ink, height: 1.5)),
        const SizedBox(height: 16),
        Row(children: [
          Expanded(child: AppButton(kind: BtnKind.ghost, full: true, onTap: onPrimary, child: Text(primaryLabel))),
          const SizedBox(width: 8),
          Expanded(child: AppButton(kind: BtnKind.danger, full: true, onTap: onSecondary, child: Text(secondaryLabel))),
        ]),
      ]),
    );
  }
}

class _CellLeaderRow extends StatelessWidget {
  final CellLeaderRecord leader;
  final bool checkedIn;
  final bool canCheckIn;
  final VoidCallback onCheckIn;
  const _CellLeaderRow({required this.leader, required this.checkedIn, required this.canCheckIn, required this.onCheckIn});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return AppCard(
      padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(leader.name, style: AppText.sans(size: 14, weight: FontWeight.w600, color: c.ink))),
          if (checkedIn)
            const AppChip(tone: ChipTone.pos, child: Text('CHECKED IN'))
          else
            AppButton(
              kind: BtnKind.ghost,
              height: 32,
              onTap: canCheckIn ? onCheckIn : null,
              child: const Text('Check in'),
            ),
        ]),
        const SizedBox(height: 10),
        MeterBar(label: 'Performance', value: leader.performance * 100, color: c.pos),
        const SizedBox(height: 10),
        MeterBar(label: 'Loyalty', value: leader.loyalty * 100, color: c.primary),
      ]),
    );
  }
}

class _CircleRow extends StatelessWidget {
  final InnerCircleMember member;
  final bool flagged;
  const _CircleRow({required this.member, required this.flagged});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return AppCard(
      padding: const EdgeInsets.all(14),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(member.name, style: AppText.sans(size: 14, weight: FontWeight.w600, color: c.ink)),
            Text(member.role, style: AppText.sans(size: 11.5, weight: FontWeight.w500, color: c.inkFaint)),
          ]),
        ),
        if (flagged) const AppChip(tone: ChipTone.warn, child: Text('SOMETHING\'S OFF')),
      ]),
    );
  }
}
