import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import '../../theme.dart';
import '../../widgets.dart';
import 'side_hustle_game_shell.dart';

/// Add up a few betting slips before the clock runs out, then tap the right
/// total among close decoys. Speed arithmetic — a different skill entirely
/// from anything else on offer.
class NumbersRacketGameScreen extends StatelessWidget {
  const NumbersRacketGameScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return SideHustleGameShell(
      title: 'Run the numbers',
      instructions: 'Add up the slips, then tap the right total before time runs out. The decoys are close — actually add it up.',
      builder: (context, resolve) => _NumbersRacketGame(onResolve: resolve),
    );
  }
}

class _NumbersRacketGame extends StatefulWidget {
  final void Function(bool won) onResolve;
  const _NumbersRacketGame({required this.onResolve});
  @override
  State<_NumbersRacketGame> createState() => _NumbersRacketGameState();
}

class _NumbersRacketGameState extends State<_NumbersRacketGame> {
  static const _answerSeconds = 6;
  final _rng = Random();
  late final List<int> _numbers;
  late final int _total;
  late final List<int> _options;
  bool _canTap = true;
  int _secondsLeft = _answerSeconds;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _numbers = List.generate(3, (_) => 10 + _rng.nextInt(80)); // 10-89 each
    _total = _numbers.fold(0, (a, b) => a + b);
    final decoys = <int>{};
    while (decoys.length < 3) {
      final delta = (1 + _rng.nextInt(9)) * (_rng.nextBool() ? 1 : -1);
      final candidate = _total + delta;
      if (candidate > 0 && candidate != _total) decoys.add(candidate);
    }
    _options = [_total, ...decoys]..shuffle(_rng);
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

  void _resolve(int picked) {
    if (!_canTap) return;
    _canTap = false;
    _timer?.cancel();
    widget.onResolve(picked == _total);
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Text('$_secondsLeft', style: AppText.mono(size: 13, weight: FontWeight.w700, color: c.warn)),
      const SizedBox(height: 16),
      Wrap(spacing: 10, alignment: WrapAlignment.center, children: [
        for (final n in _numbers)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(color: c.surfaceAlt, borderRadius: BorderRadius.circular(8), border: Border.all(color: c.line)),
            child: Text('$n', style: AppText.mono(size: 18, weight: FontWeight.w700, color: c.ink)),
          ),
      ]),
      const SizedBox(height: 26),
      Wrap(spacing: 10, runSpacing: 10, alignment: WrapAlignment.center, children: [
        for (final option in _options) AppButton(kind: BtnKind.ghost, onTap: () => _resolve(option), child: Text('$option')),
      ]),
    ]);
  }
}
