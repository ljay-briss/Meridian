import 'dart:math';
import 'package:flutter/material.dart';
import '../../theme.dart';
import 'side_hustle_game_shell.dart';

/// Watch a short sequence light up across 4 tiles, then tap them back in the
/// same order — sequential memory, distinct from Read the Tell's single
/// positional recall.
class SequenceGameScreen extends StatelessWidget {
  const SequenceGameScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return SideHustleGameShell(
      title: 'Remember the order',
      instructions: 'Watch the tiles light up, then tap them back in the same order.',
      builder: (context, resolve) => _SequenceGame(onResolve: resolve),
    );
  }
}

class _SequenceGame extends StatefulWidget {
  final void Function(bool won) onResolve;
  const _SequenceGame({required this.onResolve});
  @override
  State<_SequenceGame> createState() => _SequenceGameState();
}

class _SequenceGameState extends State<_SequenceGame> {
  static const _tileCount = 4;
  static const _sequenceLength = 5;
  static const _marks = ['●', '▲', '■', '✕'];
  final _rng = Random();
  late final List<int> _sequence;
  int _highlighted = -1;
  bool _showing = true;
  int _inputIndex = 0;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _sequence = List.generate(_sequenceLength, (_) => _rng.nextInt(_tileCount));
    _playback();
  }

  Future<void> _playback() async {
    await Future.delayed(const Duration(milliseconds: 400));
    for (final tile in _sequence) {
      if (!mounted) return;
      setState(() => _highlighted = tile);
      await Future.delayed(const Duration(milliseconds: 420));
      if (!mounted) return;
      setState(() => _highlighted = -1);
      await Future.delayed(const Duration(milliseconds: 180));
    }
    if (!mounted) return;
    setState(() => _showing = false);
  }

  void _tap(int tile) {
    if (_showing || _failed) return;
    if (tile != _sequence[_inputIndex]) {
      setState(() => _failed = true);
      Future.delayed(const Duration(milliseconds: 400), () => widget.onResolve(false));
      return;
    }
    setState(() {
      _highlighted = tile;
      _inputIndex += 1;
    });
    Future.delayed(const Duration(milliseconds: 150), () {
      if (mounted) setState(() => _highlighted = -1);
    });
    if (_inputIndex >= _sequence.length) {
      Future.delayed(const Duration(milliseconds: 300), () => widget.onResolve(true));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Text(_showing ? 'Watch...' : 'Your turn', style: AppText.sans(size: 12.5, weight: FontWeight.w600, color: c.inkSoft)),
      const SizedBox(height: 16),
      SizedBox(
        width: 160,
        height: 160,
        child: GridView.count(
          crossAxisCount: 2,
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          physics: const NeverScrollableScrollPhysics(),
          children: [
            for (var i = 0; i < _tileCount; i++)
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _tap(i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  decoration: BoxDecoration(
                    color: _highlighted == i ? c.primarySoft : c.surfaceAlt,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: _highlighted == i ? c.ink : c.line, width: _highlighted == i ? 2 : 1.5),
                  ),
                  alignment: Alignment.center,
                  child: Text(_marks[i], style: AppText.sans(size: 22, weight: FontWeight.w700, color: _highlighted == i ? c.ink : c.inkFaint)),
                ),
              ),
          ],
        ),
      ),
    ]);
  }
}
