import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import '../../theme.dart';
import 'side_hustle_game_shell.dart';

/// Shell game — track which cup the coin ends up under after a few swaps.
class CupsGameScreen extends StatelessWidget {
  const CupsGameScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return SideHustleGameShell(
      title: 'Find the coin',
      instructions: 'A cup lifts to show you the coin. Track that cup through the swap, then tap the one you think it\'s under.',
      builder: (context, resolve) => _CupsGame(onResolve: resolve),
    );
  }
}

class _CupsGame extends StatefulWidget {
  final void Function(bool won) onResolve;
  const _CupsGame({required this.onResolve});
  @override
  State<_CupsGame> createState() => _CupsGameState();
}

class _CupsGameState extends State<_CupsGame> {
  static const _slotX = [0.0, 100.0, 200.0];
  static const _liftHeight = 52.0;
  final _rng = Random();
  late int _winningCup; // fixed identity, 0-2
  late List<int> _cupSlot; // cupSlot[cupId] = current slot index 0-2
  int? _liftedCup; // which cup (by identity) is currently lifted to show what's under it
  bool _canTap = false;
  String _status = 'Watch closely...';

  @override
  void initState() {
    super.initState();
    _winningCup = _rng.nextInt(3);
    _cupSlot = [0, 1, 2];
    _run();
  }

  Future<void> _run() async {
    // Lift the winning cup to show the coin underneath, hold, then set it back down.
    await Future.delayed(const Duration(milliseconds: 500));
    if (!mounted) return;
    setState(() => _liftedCup = _winningCup);
    await Future.delayed(const Duration(milliseconds: 1200));
    if (!mounted) return;
    setState(() {
      _liftedCup = null;
      _status = 'Tracking...';
    });
    await Future.delayed(const Duration(milliseconds: 500));

    final swaps = 3 + _rng.nextInt(2); // 3-4 swaps
    for (var i = 0; i < swaps; i++) {
      if (!mounted) return;
      final a = _rng.nextInt(3);
      var b = _rng.nextInt(3);
      while (b == a) {
        b = _rng.nextInt(3);
      }
      setState(() {
        // Find the two cups currently sitting at slots a and b, and swap their slots.
        final cupA = _cupSlot.indexWhere((s) => s == a);
        final cupB = _cupSlot.indexWhere((s) => s == b);
        _cupSlot[cupA] = b;
        _cupSlot[cupB] = a;
      });
      await Future.delayed(const Duration(milliseconds: 280));
    }
    if (!mounted) return;
    setState(() {
      _canTap = true;
      _status = 'Which cup?';
    });
  }

  void _tap(int slot) {
    if (!_canTap) return;
    final tappedCup = _cupSlot.indexWhere((s) => s == slot);
    setState(() {
      _canTap = false;
      _liftedCup = tappedCup;
      _status = tappedCup == _winningCup ? 'There it is.' : 'Not this one.';
    });
    Future.delayed(const Duration(milliseconds: 900), () {
      widget.onResolve(tappedCup == _winningCup);
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Text(_status, style: AppText.sans(size: 12.5, weight: FontWeight.w600, color: c.inkSoft)),
      const SizedBox(height: 16),
      SizedBox(
        width: 260,
        height: 160,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            for (var cupId = 0; cupId < 3; cupId++)
              AnimatedPositioned(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeInOut,
                left: _slotX[_cupSlot[cupId]],
                top: 40,
                child: SizedBox(
                  width: 60,
                  height: 100,
                  child: Stack(clipBehavior: Clip.none, alignment: Alignment.bottomCenter, children: [
                    // The coin sits on the table — only ever visible while this cup is lifted.
                    Positioned(
                      bottom: 6,
                      child: AnimatedOpacity(
                        duration: const Duration(milliseconds: 200),
                        opacity: _liftedCup == cupId && cupId == _winningCup ? 1 : 0,
                        child: Container(width: 18, height: 18, decoration: BoxDecoration(shape: BoxShape.circle, color: c.warn)),
                      ),
                    ),
                    AnimatedPositioned(
                      duration: const Duration(milliseconds: 380),
                      curve: Curves.easeOut,
                      bottom: _liftedCup == cupId ? _liftHeight : 0,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => _tap(_cupSlot[cupId]),
                        child: Container(
                          width: 60,
                          height: 60,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: _canTap ? c.line : c.lineSoft, width: 1.5),
                          ),
                        ),
                      ),
                    ),
                  ]),
                ),
              ),
          ],
        ),
      ),
    ]);
  }
}
