import 'dart:math';
import 'package:flutter/material.dart';
import '../../theme.dart';
import '../../widgets.dart';
import 'side_hustle_game_shell.dart';

/// Guess whether the next card beats the one on the table. Aces are high —
/// a low current card favors "higher," a high one favors "lower," so the
/// read is a real probability call, not a coin flip.
class HigherLowerGameScreen extends StatelessWidget {
  const HigherLowerGameScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return SideHustleGameShell(
      title: 'Higher or lower',
      instructions: 'Guess whether the next card beats this one — ties go to the house. A low card favors "higher," a high one favors "lower."',
      builder: (context, resolve) => _HigherLowerGame(onResolve: resolve),
    );
  }
}

class _Card {
  final String rank, suit;
  final int value; // 2-14, ace high
  const _Card(this.rank, this.suit, this.value);
}

class _HigherLowerGame extends StatefulWidget {
  final void Function(bool won) onResolve;
  const _HigherLowerGame({required this.onResolve});
  @override
  State<_HigherLowerGame> createState() => _HigherLowerGameState();
}

class _HigherLowerGameState extends State<_HigherLowerGame> {
  static const _ranks = ['2', '3', '4', '5', '6', '7', '8', '9', '10', 'J', 'Q', 'K', 'A'];
  static const _suits = ['♠', '♥', '♦', '♣'];
  final _rng = Random();
  late final List<_Card> _deck;
  late final _Card _current;
  _Card? _next;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _deck = [
      for (var i = 0; i < _ranks.length; i++)
        for (final s in _suits) _Card(_ranks[i], s, i + 2),
    ]..shuffle(_rng);
    _current = _deck.removeLast();
  }

  void _guess(bool guessHigher) {
    if (_done) return;
    final next = _deck.removeLast();
    final won = guessHigher ? next.value > _current.value : next.value < _current.value;
    setState(() {
      _next = next;
      _done = true;
    });
    Future.delayed(const Duration(milliseconds: 800), () => widget.onResolve(won));
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Row(mainAxisSize: MainAxisSize.min, children: [
        _CardFace(card: _current),
        const SizedBox(width: 16),
        Icon(Icons.arrow_forward, size: 18, color: c.inkFaint),
        const SizedBox(width: 16),
        _next != null
            ? _CardFace(card: _next!)
            : Container(
                width: 56,
                height: 76,
                decoration: BoxDecoration(color: c.sunken, borderRadius: BorderRadius.circular(6), border: Border.all(color: c.lineSoft)),
              ),
      ]),
      const SizedBox(height: 28),
      if (!_done)
        Row(mainAxisSize: MainAxisSize.min, children: [
          AppButton(kind: BtnKind.ghost, onTap: () => _guess(false), child: const Text('Lower')),
          const SizedBox(width: 10),
          AppButton(kind: BtnKind.dark, onTap: () => _guess(true), child: const Text('Higher')),
        ]),
    ]);
  }
}

class _CardFace extends StatelessWidget {
  final _Card card;
  const _CardFace({required this.card});
  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final red = card.suit == '♥' || card.suit == '♦';
    return Container(
      width: 56,
      height: 76,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(6), border: Border.all(color: c.line)),
      child: Text('${card.rank}${card.suit}', style: AppText.mono(size: 16, weight: FontWeight.w700, color: red ? c.neg : c.ink)),
    );
  }
}
