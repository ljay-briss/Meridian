import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import '../../theme.dart';
import 'side_hustle_game_shell.dart';

/// One chip is marked for a moment while all 5 are face-up, then everything
/// flips face-down and looks identical — tap the one you remember being
/// marked before the clock runs out.
class ReadTheTellGameScreen extends StatelessWidget {
  const ReadTheTellGameScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return SideHustleGameShell(
      title: 'Read the tell',
      instructions: 'One chip is marked — it\'ll only flash for a second. Remember which one, then find it again once they\'re all turned down.',
      builder: (context, resolve) => _ReadTheTellGame(onResolve: resolve),
    );
  }
}

class _ReadTheTellGame extends StatefulWidget {
  final void Function(bool won) onResolve;
  const _ReadTheTellGame({required this.onResolve});
  @override
  State<_ReadTheTellGame> createState() => _ReadTheTellGameState();
}

class _ReadTheTellGameState extends State<_ReadTheTellGame> {
  static const _count = 7;
  static const _answerSeconds = 3;
  final _rng = Random();
  late int _marked;
  bool _faceUp = true;
  bool _canTap = false;
  int _secondsLeft = _answerSeconds;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _marked = _rng.nextInt(_count);
    // The shell's "I'm ready" gate already covers reading the instructions —
    // this pause is a genuinely quick flash, not a casual look.
    Future.delayed(const Duration(milliseconds: 700), () {
      if (!mounted) return;
      setState(() {
        _faceUp = false;
        _canTap = true;
      });
      _timer = Timer.periodic(const Duration(seconds: 1), (t) {
        setState(() => _secondsLeft -= 1);
        if (_secondsLeft <= 0) {
          t.cancel();
          _resolve(-1);
        }
      });
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
    widget.onResolve(tapped == _marked);
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Column(mainAxisSize: MainAxisSize.min, children: [
      if (_canTap) Text('$_secondsLeft', style: AppText.mono(size: 13, weight: FontWeight.w700, color: c.warn)),
      const SizedBox(height: 14),
      Row(mainAxisSize: MainAxisSize.min, children: [
        for (var i = 0; i < _count; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _resolve(i),
            child: _Chip(marked: _faceUp && i == _marked, faceUp: _faceUp),
          ),
        ],
      ]),
    ]);
  }
}

class _Chip extends StatelessWidget {
  final bool marked;
  final bool faceUp;
  const _Chip({required this.marked, required this.faceUp});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: faceUp ? c.surface : c.surfaceAlt,
        border: Border.all(color: marked ? c.warn : c.line, width: marked ? 2.5 : 1.5),
      ),
      alignment: Alignment.center,
      child: marked ? Container(width: 7, height: 7, decoration: BoxDecoration(shape: BoxShape.circle, color: c.warn)) : null,
    );
  }
}
