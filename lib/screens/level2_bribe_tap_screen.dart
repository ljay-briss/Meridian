import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import '../theme.dart';
import '../widgets.dart';

/// The quick timing-tap standing in for actually pulling off a bribe at a
/// level-2 checkpoint. Pushed as its own route so [chooseCheckpoint] can
/// wait on a real result instead of treating "paid" as "worked" — pops
/// `true`/`false` once the player stops the marker, or `null` if they back
/// out before playing (no cost is taken in that case).
class BribeTapScreen extends StatefulWidget {
  const BribeTapScreen({super.key});
  @override
  State<BribeTapScreen> createState() => _BribeTapScreenState();
}

class _BribeTapScreenState extends State<BribeTapScreen> with SingleTickerProviderStateMixin {
  static const _barWidth = 260.0;
  late final AnimationController _c;
  late double _zoneStart; // 0..1
  late double _zoneWidth; // 0..1
  bool _started = false;
  bool _stopped = false;

  @override
  void initState() {
    super.initState();
    final rng = Random();
    _zoneWidth = 0.08 + rng.nextDouble() * 0.05;
    _zoneStart = rng.nextDouble() * (1 - _zoneWidth);
    _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 550))..repeat(reverse: true);
    // A short beat before the sweep starts so the player isn't ambushed the
    // instant this screen mounts.
    _c.stop();
    Timer(const Duration(milliseconds: 500), () {
      if (!mounted) return;
      setState(() => _started = true);
      _c.repeat(reverse: true);
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _stop() {
    if (_stopped || !_started) return;
    _stopped = true;
    final pos = _c.value;
    final won = pos >= _zoneStart && pos <= _zoneStart + _zoneWidth;
    _c.stop();
    Navigator.of(context).pop(won);
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
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
            Text('Time the handoff', style: AppText.sans(size: 20, weight: FontWeight.w700, color: c.ink)),
            const SizedBox(height: 8),
            Text(
              'Stop the marker in the zone to sell it clean. Miss it and the money\'s spent for nothing.',
              style: AppText.sans(size: 13, weight: FontWeight.w500, color: c.inkSoft, height: 1.4),
            ),
            const SizedBox(height: 28),
            Expanded(
              child: Center(
                child: SizedBox(
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
                    if (_started)
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
              ),
            ),
            AppButton(kind: BtnKind.dark, full: true, height: 50, onTap: _stop, child: const Text('Stop')),
          ]),
        ),
      ),
    );
  }
}
