import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import '../../theme.dart';
import 'side_hustle_game_shell.dart';

/// A grid of near-identical bills, one missing its mark — find it before
/// time runs out. Visual search/discrimination under pressure, distinct
/// from Read the Tell's memory recall (nothing here ever hides).
class SpotFakeGameScreen extends StatelessWidget {
  const SpotFakeGameScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return SideHustleGameShell(
      title: 'Spot the fake',
      instructions: 'Every genuine bill has a mark in the corner. One doesn\'t. Find it before the clock runs out.',
      builder: (context, resolve) => _SpotFakeGame(onResolve: resolve),
    );
  }
}

class _SpotFakeGame extends StatefulWidget {
  final void Function(bool won) onResolve;
  const _SpotFakeGame({required this.onResolve});
  @override
  State<_SpotFakeGame> createState() => _SpotFakeGameState();
}

class _SpotFakeGameState extends State<_SpotFakeGame> {
  static const _count = 9;
  static const _answerSeconds = 5;
  final _rng = Random();
  late final int _fake;
  bool _canTap = true;
  int _secondsLeft = _answerSeconds;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _fake = _rng.nextInt(_count);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      setState(() => _secondsLeft -= 1);
      if (_secondsLeft <= 0) {
        t.cancel();
        _resolve(-1);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _resolve(int tapped) {
    if (!_canTap) return;
    _canTap = false;
    _timer?.cancel();
    widget.onResolve(tapped == _fake);
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Text('$_secondsLeft', style: AppText.mono(size: 13, weight: FontWeight.w700, color: c.warn)),
      const SizedBox(height: 14),
      SizedBox(
        width: 240,
        height: 190,
        child: GridView.count(
          crossAxisCount: 3,
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 1.3, // bills read wider than tall, and it keeps 3 rows inside the box height
          physics: const NeverScrollableScrollPhysics(),
          children: [
            for (var i = 0; i < _count; i++)
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _resolve(i),
                child: _Bill(fake: i == _fake),
              ),
          ],
        ),
      ),
    ]);
  }
}

class _Bill extends StatelessWidget {
  final bool fake;
  const _Bill({required this.fake});
  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Container(
      decoration: BoxDecoration(color: c.surfaceAlt, borderRadius: BorderRadius.circular(6), border: Border.all(color: c.line)),
      padding: const EdgeInsets.all(6),
      child: Stack(children: [
        Center(
          child: Container(
            width: 22,
            height: 14,
            decoration: BoxDecoration(border: Border.all(color: c.inkFaint), borderRadius: BorderRadius.circular(2)),
          ),
        ),
        // Genuine bills carry this corner mark; the fake is missing it.
        if (!fake)
          Positioned(
            right: 0,
            top: 0,
            child: Container(width: 5, height: 5, decoration: BoxDecoration(shape: BoxShape.circle, color: c.inkFaint)),
          ),
      ]),
    );
  }
}
