import 'package:flutter/material.dart';
import '../theme.dart';
import '../controller.dart';
import '../widgets.dart';

class GameOverScreen extends StatelessWidget {
  const GameOverScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final g = AppScope.of(context);
    final c = AppColors.of(context);
    return Scaffold(
      backgroundColor: c.appBg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(g.arrested ? 'ARRESTED' : 'DEAD', style: AppText.sans(size: 34, weight: FontWeight.w700, color: c.neg, spacing: -0.5)),
            const SizedBox(height: 14),
            Text('Level ${g.level} — day ${g.day}', style: AppText.sans(size: 12, weight: FontWeight.w600, color: c.inkFaint, spacing: 0.8)),
            if (g.peakLevelEver > 1) ...[
              const SizedBox(height: 4),
              Text('Best career: Level ${g.peakLevelEver}', style: AppText.sans(size: 12, weight: FontWeight.w600, color: c.inkFaint, spacing: 0.8)),
            ],
            const SizedBox(height: 18),
            Text(g.gameOverReason, style: AppText.sans(size: 15.5, weight: FontWeight.w500, color: c.ink, height: 1.6)),
            if (g.arrested && g.level >= 7) ...[
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: c.surfaceAlt, borderRadius: BorderRadius.circular(12), border: Border.all(color: c.line)),
                child: Text(
                  "This is where the sentence would begin. Prison hasn't been built yet — for now, this is the end of the run.",
                  style: AppText.sans(size: 12.5, weight: FontWeight.w500, color: c.inkSoft, height: 1.5),
                ),
              ),
            ],
            const SizedBox(height: 28),
            AppButton(kind: BtnKind.dark, full: true, height: 50, onTap: g.restart, child: const Text('Start over')),
            if (g.level > 1) ...[
              const SizedBox(height: 10),
              AppButton(kind: BtnKind.ghost, full: true, height: 50, onTap: g.startNewCareer, child: const Text('Start a new career')),
            ],
          ]),
        ),
      ),
    );
  }
}
