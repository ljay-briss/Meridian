import 'package:flutter/material.dart';
import '../data.dart';
import '../theme.dart';
import '../widgets.dart';

/// One-time "what am I looking at" reference, shown before the player's
/// first Level 1 shift. Sighting text deliberately never names the vehicle
/// kind — this screen, plus the persistent KEY legend on the home screen,
/// is where that reading skill actually gets taught. Both draw the exact
/// same silhouettes via [vehicleShapeFor] as the road strip does in play.
class VehicleFieldGuideScreen extends StatelessWidget {
  final VoidCallback onDone;
  const VehicleFieldGuideScreen({super.key, required this.onDone});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Scaffold(
      backgroundColor: c.appBg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Know the road', style: AppText.sans(size: 22, weight: FontWeight.w700, color: c.ink)),
            const SizedBox(height: 10),
            Text(
              'The radio won\'t spell it out for you. Learn the shapes — that\'s what you\'ll actually have to go on.',
              style: AppText.sans(size: 13.5, weight: FontWeight.w500, color: c.inkSoft, height: 1.5),
            ),
            const SizedBox(height: 32),
            const _GuideRow(kind: SightingKind.military, title: 'Military convoy', body: 'Big, heavy, slow-moving. Takes up the whole lane.', word: 'bird'),
            const SizedBox(height: 22),
            const _GuideRow(kind: SightingKind.rival, title: 'Rival SUV', body: 'Low to the ground, tinted glass, boxy cabin.', word: 'snake'),
            const SizedBox(height: 22),
            const _GuideRow(kind: SightingKind.civilian, title: 'Everything else', body: 'Tall and plain — regular traffic, nothing to report.', word: 'clear'),
            const Spacer(),
            AppButton(
              full: true,
              height: 52,
              onTap: onDone,
              child: const Text('Got it — I\'m watching the road'),
            ),
          ]),
        ),
      ),
    );
  }
}

class _GuideRow extends StatelessWidget {
  final SightingKind kind;
  final String title, body, word;
  const _GuideRow({required this.kind, required this.title, required this.body, required this.word});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
      Container(
        width: 72,
        height: 56,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: c.sunken, borderRadius: BorderRadius.circular(10)),
        child: vehicleShapeFor(kind, c, scale: 1.3),
      ),
      const SizedBox(width: 16),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text(title, style: AppText.sans(size: 14.5, weight: FontWeight.w700, color: c.ink)),
            const SizedBox(width: 8),
            AppChip(child: Text('"$word"')),
          ]),
          const SizedBox(height: 4),
          Text(body, style: AppText.sans(size: 12.5, weight: FontWeight.w500, color: c.inkSoft, height: 1.4)),
        ]),
      ),
    ]);
  }
}
