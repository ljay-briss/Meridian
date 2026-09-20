import 'package:flutter/material.dart';
import '../theme.dart';
import '../controller.dart';
import '../data.dart';
import '../widgets.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool vibration = true;
  bool notifications = true;

  @override
  Widget build(BuildContext context) {
    final g = AppScope.of(context);
    final c = AppColors.of(context);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
      children: [
        const ScreenHead('Settings'),
        AppCard(
          padding: EdgeInsets.zero,
          child: Column(children: [
            _SwitchRow(label: 'Vibration', value: vibration, onChanged: (v) => setState(() => vibration = v)),
            Container(height: 1, color: c.lineSoft),
            _SwitchRow(label: 'Notifications', value: notifications, onChanged: (v) => setState(() => notifications = v)),
          ]),
        ),
        const SizedBox(height: 14),
        const SectionHead('Status'),
        AppCard(
          padding: const EdgeInsets.all(16),
          child: Column(children: [
            KVRow('Level', Text('${g.level}', style: AppText.mono(size: 14, color: c.ink))),
            if (g.careerPath != null)
              KVRow('Career path', Text(kCareerPaths.firstWhere((p) => p.id == g.careerPath).label, style: AppText.mono(size: 14, color: c.ink))),
            KVRow('Day', Text(g.dayLabel, style: AppText.mono(size: 14, color: c.ink))),
            KVRow('Cash on hand', Text(money(g.cash), style: AppText.mono(size: 14, color: cashColor(c, g.cash)))),
            KVRow('Laundered', Text(money(g.cleanBalance), style: AppText.mono(size: 14, color: c.ink))),
            KVRow('Police heat', Text(riskLabel(g.policeHeat), style: AppText.mono(size: 14, color: riskColor(c, g.policeHeat)))),
            KVRow('Cartel suspicion', Text(riskLabel(g.cartelSuspicion), style: AppText.mono(size: 14, color: riskColor(c, g.cartelSuspicion)))),
            KVRow('Rival heat (${g.rivalCrewName})', Text(riskLabel(g.rivalPressure), style: AppText.mono(size: 14, color: riskColor(c, g.rivalPressure)))),
          ]),
        ),
        if (g.rivalPressure > 0) ...[
          const SizedBox(height: 14),
          AppButton(
            kind: BtnKind.ghost,
            full: true,
            height: 48,
            onTap: g.cash > 0 ? g.payOffRival : null,
            child: Text('Pay off ${g.rivalCrewName}'),
          ),
        ],
        const SizedBox(height: 14),
        AppButton(
          kind: BtnKind.ghost,
          full: true,
          height: 48,
          onTap: () => showLevelTutorialDialog(context, g.level),
          child: const Text('How to play'),
        ),
        const SizedBox(height: 14),
        const SectionHead('Legacy'),
        AppCard(
          padding: const EdgeInsets.all(16),
          child: Column(children: [
            KVRow('Careers started', Text('${g.legacyRuns + 1}', style: AppText.mono(size: 14, color: c.ink))),
            KVRow('Best level reached', Text('${g.peakLevelEver}', style: AppText.mono(size: 14, color: c.ink))),
          ]),
        ),
        if (g.level > 1) ...[
          const SizedBox(height: 14),
          AppButton(
            kind: BtnKind.ghost,
            full: true,
            height: 48,
            onTap: g.startNewCareer,
            child: const Text('Start a new career'),
          ),
        ],
        const SizedBox(height: 14),
        const SectionHead('Danger zone'),
        AppButton(
          kind: BtnKind.danger,
          full: true,
          height: 48,
          onTap: () => _confirmWipe(context, g),
          child: const Text('Wipe phone'),
        ),
        const SizedBox(height: 14),
        const SectionHead('Dev: jump to level'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (int lvl = 1; lvl <= 7; lvl++)
              AppButton(kind: BtnKind.ghost, onTap: () => g.devJumpToLevel(lvl), child: Text('L$lvl')),
          ],
        ),
        const SizedBox(height: 14),
        const SectionHead('Dev: relationship stats (hidden in real UI)'),
        AppCard(
          padding: const EdgeInsets.all(16),
          child: Column(children: [
            for (final p in kPersonalContacts) ...[
              _RelStatRow(p),
              if (p != kPersonalContacts.last) Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Divider(height: 1, color: c.lineSoft)),
            ],
          ]),
        ),
        const SizedBox(height: 20),
        Center(
          child: Column(children: [
            Text('CARTEL', style: AppText.sans(size: 11, weight: FontWeight.w600, color: c.inkFaint, spacing: 1.6)),
            const SizedBox(height: 4),
            Text('v1.0.0', style: AppText.sans(size: 11, weight: FontWeight.w500, color: c.inkFaint)),
          ]),
        ),
      ],
    );
  }

  void _confirmWipe(BuildContext context, CareerController g) {
    final c = AppColors.of(context);
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: c.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: BorderSide(color: c.line)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 30),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Wipe phone?', style: AppText.sans(size: 17, weight: FontWeight.w700, color: c.ink)),
            const SizedBox(height: 10),
            Text('This clears every message, job, and dollar on this device. It cannot be undone.',
                style: AppText.sans(size: 13, weight: FontWeight.w500, color: c.inkSoft, height: 1.5)),
            const SizedBox(height: 18),
            Row(children: [
              Expanded(child: AppButton(kind: BtnKind.ghost, full: true, onTap: () => Navigator.pop(ctx), child: const Text('Cancel'))),
              const SizedBox(width: 10),
              Expanded(
                child: AppButton(
                  kind: BtnKind.danger,
                  full: true,
                  onTap: () {
                    g.restart();
                    Navigator.pop(ctx);
                  },
                  child: const Text('Wipe'),
                ),
              ),
            ]),
          ]),
        ),
      ),
    );
  }
}

class _RelStatRow extends StatelessWidget {
  final PersonalContact contact;
  const _RelStatRow(this.contact);
  @override
  Widget build(BuildContext context) {
    final g = AppScope.of(context);
    final c = AppColors.of(context);
    final rel = g.relationships[contact.id]!;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('${contact.name} · ${contact.relation}${rel.goneQuiet ? ' (gone quiet)' : rel.resolved ? ' (resolved)' : ''}',
          style: AppText.sans(size: 13, weight: FontWeight.w600, color: c.ink)),
      const SizedBox(height: 8),
      MeterBar(label: 'Closeness', value: rel.closeness, color: c.pos),
      const SizedBox(height: 8),
      MeterBar(label: 'Trust', value: rel.trust, color: c.primary),
      const SizedBox(height: 8),
      MeterBar(label: 'Suspicion', value: rel.suspicion, color: riskColor(c, rel.suspicion)),
    ]);
  }
}

class _SwitchRow extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  const _SwitchRow({required this.label, required this.value, required this.onChanged});
  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(label, style: AppText.sans(size: 14, weight: FontWeight.w500, color: c.ink)),
        Switch(value: value, onChanged: onChanged, activeThumbColor: c.ink, activeTrackColor: c.surfaceAlt),
      ]),
    );
  }
}
