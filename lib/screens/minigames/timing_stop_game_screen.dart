import 'dart:math';
import 'package:flutter/material.dart';
import '../../theme.dart';
import '../../widgets.dart';
import 'side_hustle_game_shell.dart';

/// A marker sweeps across a bar; stop it inside the highlighted zone.
class TimingStopGameScreen extends StatelessWidget {
  const TimingStopGameScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return SideHustleGameShell(
      title: 'Stick the stop',
      instructions: 'Tap when the marker is inside the highlighted zone.',
      builder: (context, resolve) => _TimingStopGame(onResolve: resolve),
    );
  }
}

class _TimingStopGame extends StatefulWidget {
  final void Function(bool won) onResolve;
  const _TimingStopGame({required this.onResolve});
  @override
  State<_TimingStopGame> createState() => _TimingStopGameState();
}

class _TimingStopGameState extends State<_TimingStopGame> with SingleTickerProviderStateMixin {
  static const _barWidth = 260.0;
  late final AnimationController _c;
  late double _zoneStart; // 0..1
  late double _zoneWidth; // 0..1
  bool _stopped = false;

  @override
  void initState() {
    super.initState();
    final rng = Random();
    _zoneWidth = 0.08 + rng.nextDouble() * 0.05; // a narrow slice of the bar — this is the real difficulty
    _zoneStart = rng.nextDouble() * (1 - _zoneWidth);
    // The shell's "I'm ready" gate handles the reading pause, so this speed
    // is purely a difficulty knob — quick enough that reading the sweep,
    // not reaction time alone, is what separates a hit from a miss.
    _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 650))..repeat(reverse: true);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _stop() {
    if (_stopped) return;
    _stopped = true;
    final pos = _c.value;
    final won = pos >= _zoneStart && pos <= _zoneStart + _zoneWidth;
    _c.stop();
    widget.onResolve(won);
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Column(mainAxisSize: MainAxisSize.min, children: [
      SizedBox(
        width: _barWidth,
        height: 40,
        child: Stack(clipBehavior: Clip.none, children: [
          Positioned(
            top: 16,
            left: 0,
            right: 0,
            child: Container(height: 8, decoration: BoxDecoration(color: c.sunken, borderRadius: BorderRadius.circular(4))),
          ),
          Positioned(
            top: 16,
            left: _zoneStart * _barWidth,
            width: _zoneWidth * _barWidth,
            child: Container(height: 8, decoration: BoxDecoration(color: c.pos.withValues(alpha: 0.5), borderRadius: BorderRadius.circular(4))),
          ),
          AnimatedBuilder(
            animation: _c,
            builder: (context, _) => Positioned(
              left: _c.value * _barWidth - 2,
              top: 4,
              child: Container(width: 4, height: 32, decoration: BoxDecoration(color: c.ink, borderRadius: BorderRadius.circular(2))),
            ),
          ),
        ]),
      ),
      const SizedBox(height: 24),
      AppButton(kind: BtnKind.dark, height: 50, onTap: _stop, child: const Text('Stop')),
    ]);
  }
}
