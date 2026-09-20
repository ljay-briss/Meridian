import 'package:flutter/material.dart';
import '../../controller.dart';
import '../../data.dart';
import '../../theme.dart';
import '../../widgets.dart';

/// Shared full-screen frame every side-hustle minigame renders inside —
/// title/instructions up top, the game itself in the middle, and a
/// consistent win/lose result panel once [resolve] is called. Each game
/// screen owns its own win/lose logic and calls [SideHustleGameShellState.resolve]
/// when the player's play (not a hidden roll) decides the outcome.
class SideHustleGameShell extends StatefulWidget {
  final String title;
  final String instructions;
  final Widget Function(BuildContext context, void Function(bool won) resolve) builder;
  const SideHustleGameShell({super.key, required this.title, required this.instructions, required this.builder});

  @override
  State<SideHustleGameShell> createState() => _SideHustleGameShellState();
}

class _SideHustleGameShellState extends State<SideHustleGameShell> {
  bool? _won;
  // The game itself doesn't mount (and its own internal timers/sequences
  // don't start) until the player taps in — so reading the instructions
  // never eats into a game clock. No auto-advancing countdown here.
  bool _started = false;

  void _resolve(bool won) {
    if (_won != null) return; // already resolved — ignore late taps/timers
    final g = AppScope.of(context);
    g.resolveSideHustle(won);
    setState(() => _won = won);
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final g = AppScope.of(context);
    return Scaffold(
      backgroundColor: c.appBg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              GestureDetector(
                onTap: () => Navigator.of(context).pop(),
                behavior: HitTestBehavior.opaque,
                child: Icon(Icons.close, color: c.inkFaint, size: 22),
              ),
            ]),
            const SizedBox(height: 14),
            Text(widget.title, style: AppText.sans(size: 20, weight: FontWeight.w700, color: c.ink)),
            const SizedBox(height: 8),
            Text(widget.instructions, style: AppText.sans(size: 13, weight: FontWeight.w500, color: c.inkSoft, height: 1.4)),
            const SizedBox(height: 28),
            Expanded(
              child: Center(
                child: !_started
                    ? _ReadyGate(onReady: () => setState(() => _started = true))
                    : (_won == null ? widget.builder(context, _resolve) : _ResultPanel(won: _won!, level: g.level)),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

class _ReadyGate extends StatelessWidget {
  final VoidCallback onReady;
  const _ReadyGate({required this.onReady});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Text('Take your time reading the above.', style: AppText.sans(size: 12.5, weight: FontWeight.w500, color: c.inkFaint)),
      const SizedBox(height: 18),
      SizedBox(
        width: 220,
        child: AppButton(kind: BtnKind.dark, full: true, height: 50, onTap: onReady, child: const Text('I\'m ready')),
      ),
    ]);
  }
}

class _ResultPanel extends StatelessWidget {
  final bool won;
  final int level;
  const _ResultPanel({required this.won, required this.level});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final amount = won ? (kSideHustlePayout[level] ?? 0) : (kSideHustleLossPayout[level] ?? 0);
    final color = won ? c.pos : c.neg;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Text(won ? 'YOU WON' : 'YOU LOST', style: AppText.sans(size: 20, weight: FontWeight.w700, color: color, spacing: 1)),
      const SizedBox(height: 12),
      Text('${won ? '+' : '-'}${money(amount)}', style: AppText.mono(size: 34, weight: FontWeight.w700, color: color)),
      if (!won) ...[
        const SizedBox(height: 6),
        Text('and the heat\'s up a little', style: AppText.sans(size: 12, weight: FontWeight.w500, color: c.inkFaint)),
      ],
      const SizedBox(height: 32),
      SizedBox(
        width: 200,
        child: AppButton(kind: BtnKind.dark, full: true, height: 48, onTap: () => Navigator.of(context).pop(), child: const Text('Done')),
      ),
    ]);
  }
}
