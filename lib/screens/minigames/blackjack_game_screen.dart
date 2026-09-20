import 'dart:math';
import 'package:flutter/material.dart';
import '../../theme.dart';
import '../../widgets.dart';
import 'side_hustle_game_shell.dart';

/// One simplified hand of blackjack — hit or stand against a dealer that
/// hits until 17. No betting/splitting/doubling; closest to 21 without
/// busting wins, dealer wins ties.
class BlackjackGameScreen extends StatelessWidget {
  const BlackjackGameScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return SideHustleGameShell(
      title: 'One hand',
      instructions: 'Hit or stand. Get closer to 21 than the dealer without going over — the dealer wins ties.',
      builder: (context, resolve) => _BlackjackGame(onResolve: resolve),
    );
  }
}

class _Card {
  final String rank; // '2'..'10','J','Q','K','A'
  final String suit; // one glyph
  final int value; // ace counted as 11 here; hand value adjusts for busts
  const _Card(this.rank, this.suit, this.value);
}

class _BlackjackGame extends StatefulWidget {
  final void Function(bool won) onResolve;
  const _BlackjackGame({required this.onResolve});
  @override
  State<_BlackjackGame> createState() => _BlackjackGameState();
}

class _BlackjackGameState extends State<_BlackjackGame> {
  final _rng = Random();
  late List<_Card> _deck;
  late List<_Card> _player;
  late List<_Card> _dealer;
  bool _dealerHidden = true;
  bool _done = false;
  String? _statusLine;

  static const _ranks = ['2', '3', '4', '5', '6', '7', '8', '9', '10', 'J', 'Q', 'K', 'A'];
  static const _suits = ['♠', '♥', '♦', '♣'];

  @override
  void initState() {
    super.initState();
    _deck = [
      for (final r in _ranks)
        for (final s in _suits) _Card(r, s, r == 'A' ? 11 : (int.tryParse(r) ?? 10)),
    ]..shuffle(_rng);
    _player = [_draw(), _draw()];
    _dealer = [_draw(), _draw()];
  }

  _Card _draw() => _deck.removeLast();

  int _handValue(List<_Card> hand) {
    var total = hand.fold<int>(0, (a, c) => a + c.value);
    var aces = hand.where((c) => c.rank == 'A').length;
    while (total > 21 && aces > 0) {
      total -= 10;
      aces -= 1;
    }
    return total;
  }

  void _hit() {
    if (_done) return;
    setState(() => _player.add(_draw()));
    if (_handValue(_player) > 21) {
      setState(() {
        _dealerHidden = false;
        _statusLine = 'Bust.';
        _done = true;
      });
      Future.delayed(const Duration(milliseconds: 700), () => widget.onResolve(false));
    }
  }

  void _stand() {
    if (_done) return;
    setState(() => _dealerHidden = false);
    while (_handValue(_dealer) < 17) {
      _dealer.add(_draw());
    }
    final playerTotal = _handValue(_player);
    final dealerTotal = _handValue(_dealer);
    final dealerBust = dealerTotal > 21;
    final won = dealerBust || playerTotal > dealerTotal;
    setState(() {
      _statusLine = dealerBust ? 'Dealer busts.' : (won ? 'You\'re closer.' : 'Dealer\'s closer.');
      _done = true;
    });
    Future.delayed(const Duration(milliseconds: 700), () => widget.onResolve(won));
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Column(mainAxisSize: MainAxisSize.min, children: [
      _HandRow(label: 'DEALER', hand: _dealer, hideLast: _dealerHidden, total: _dealerHidden ? null : _handValue(_dealer)),
      const SizedBox(height: 28),
      _HandRow(label: 'YOU', hand: _player, hideLast: false, total: _handValue(_player)),
      const SizedBox(height: 20),
      if (_statusLine != null) Text(_statusLine!, style: AppText.sans(size: 13, weight: FontWeight.w600, color: c.inkSoft)),
      const SizedBox(height: 16),
      if (!_done)
        Row(mainAxisSize: MainAxisSize.min, children: [
          AppButton(kind: BtnKind.ghost, onTap: _hit, child: const Text('Hit')),
          const SizedBox(width: 10),
          AppButton(kind: BtnKind.dark, onTap: _stand, child: const Text('Stand')),
        ]),
    ]);
  }
}

class _HandRow extends StatelessWidget {
  final String label;
  final List<_Card> hand;
  final bool hideLast;
  final int? total;
  const _HandRow({required this.label, required this.hand, required this.hideLast, required this.total});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Column(children: [
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        Text(label, style: AppText.label(c.inkFaint)),
        if (total != null) ...[
          const SizedBox(width: 8),
          Text('$total', style: AppText.mono(size: 12.5, weight: FontWeight.w700, color: c.ink)),
        ],
      ]),
      const SizedBox(height: 8),
      Row(mainAxisSize: MainAxisSize.min, children: [
        for (var i = 0; i < hand.length; i++) ...[
          if (i > 0) const SizedBox(width: 6),
          _CardFace(card: hand[i], hidden: hideLast && i == hand.length - 1),
        ],
      ]),
    ]);
  }
}

class _CardFace extends StatelessWidget {
  final _Card card;
  final bool hidden;
  const _CardFace({required this.card, required this.hidden});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final red = card.suit == '♥' || card.suit == '♦';
    return Container(
      width: 42,
      height: 58,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: hidden ? c.surfaceAlt : c.surface,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: c.line),
      ),
      child: hidden
          ? null
          : Text('${card.rank}${card.suit}', style: AppText.mono(size: 13, weight: FontWeight.w700, color: red ? c.neg : c.ink)),
    );
  }
}
