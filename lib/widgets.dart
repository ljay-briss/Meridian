import 'dart:async';
import 'dart:typed_data';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'controller.dart';
import 'data.dart';
import 'theme.dart';

/// Surface card.
class AppCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  final bool flat;
  final VoidCallback? onTap;
  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.flat = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final card = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.line),
      ),
      child: child,
    );
    if (onTap == null) return card;
    return GestureDetector(onTap: onTap, behavior: HitTestBehavior.opaque, child: card);
  }
}

class TLabel extends StatelessWidget {
  final String text;
  final Color? color;
  const TLabel(this.text, {super.key, this.color});
  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Text(text.toUpperCase(), style: AppText.label(color ?? c.inkFaint));
  }
}

enum BtnKind { primary, dark, ghost, danger }

class AppButton extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  final BtnKind kind;
  final bool full;
  final double? height; // null sizes to content — needed for multi-line labels
  const AppButton(
      {super.key,
      required this.child,
      this.onTap,
      this.kind = BtnKind.primary,
      this.full = false,
      this.height = 44});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final disabled = onTap == null;
    Color bg, fg;
    BoxBorder? border;
    switch (kind) {
      case BtnKind.primary:
        bg = c.primary;
        fg = c.primaryInk;
        break;
      case BtnKind.dark:
        bg = c.surfaceAlt;
        fg = c.ink;
        border = Border.all(color: c.line);
        break;
      case BtnKind.ghost:
        bg = Colors.transparent;
        fg = c.ink;
        border = Border.all(color: c.line);
        break;
      case BtnKind.danger:
        bg = Colors.transparent;
        fg = c.neg;
        border = Border.all(color: c.neg.withValues(alpha: 0.4));
        break;
    }
    return Opacity(
      opacity: disabled ? 0.4 : 1,
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Container(
            height: height,
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: height == null ? 12 : 0),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: border),
            alignment: Alignment.center,
            child: DefaultTextStyle(
              style: AppText.sans(size: 13.5, weight: FontWeight.w600, color: fg, spacing: 0.3),
              child: IconTheme(
                data: IconThemeData(color: fg, size: 17),
                child: child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

enum ChipTone { neutral, pos, neg, warn }

class AppChip extends StatelessWidget {
  final Widget child;
  final ChipTone tone;
  const AppChip({super.key, required this.child, this.tone = ChipTone.neutral});
  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    Color bg, fg;
    switch (tone) {
      case ChipTone.pos:
        bg = c.pos.withValues(alpha: 0.14);
        fg = c.pos;
        break;
      case ChipTone.neg:
        bg = c.neg.withValues(alpha: 0.14);
        fg = c.neg;
        break;
      case ChipTone.warn:
        bg = c.warn.withValues(alpha: 0.16);
        fg = c.warn;
        break;
      case ChipTone.neutral:
        bg = c.chipBg;
        fg = c.inkSoft;
    }
    return Container(
      height: 22,
      padding: const EdgeInsets.symmetric(horizontal: 9),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6)),
      alignment: Alignment.center,
      child: DefaultTextStyle(
        style: AppText.sans(size: 11, weight: FontWeight.w600, color: fg, spacing: 0.4),
        child: child,
      ),
    );
  }
}

/// Labeled 0-100 meter bar (heat, suspicion, loyalty, etc).
class MeterBar extends StatelessWidget {
  final String label;
  final double value; // 0..100
  final Color color;
  const MeterBar({super.key, required this.label, required this.value, required this.color});
  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        TLabel(label),
        Text('${value.round()}', style: AppText.mono(size: 12.5, weight: FontWeight.w600, color: color)),
      ]),
      const SizedBox(height: 6),
      ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: Stack(children: [
          Container(height: 6, color: c.sunken),
          FractionallySizedBox(
            widthFactor: (value / 100).clamp(0, 1),
            child: AnimatedContainer(duration: const Duration(milliseconds: 400), height: 6, color: color),
          ),
        ]),
      ),
    ]);
  }
}

/// Promotion-progress strip for a level's home screen. Reads straight off
/// the controller and renders nothing once there's no further promotion
/// (level 7).
class LevelProgressBar extends StatelessWidget {
  const LevelProgressBar({super.key});
  @override
  Widget build(BuildContext context) {
    final g = AppScope.of(context);
    final c = AppColors.of(context);
    final progress = g.levelProgress;
    final label = g.levelProgressLabel;
    if (progress == null || label == null) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text('PROMOTION', style: AppText.sans(size: 10, weight: FontWeight.w600, color: c.inkFaint, spacing: 1.2)),
        Text(label, style: AppText.sans(size: 11, weight: FontWeight.w500, color: c.inkSoft)),
      ]),
      const SizedBox(height: 6),
      ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: Stack(children: [
          Container(height: 5, color: c.sunken),
          FractionallySizedBox(
            widthFactor: progress,
            child: AnimatedContainer(duration: const Duration(milliseconds: 400), height: 5, color: c.primary),
          ),
        ]),
      ),
    ]);
  }
}

/// "Something to do while this settles" card — shown on a level's home
/// screen whenever [CareerController.sideHustleAvailable] is true (i.e.
/// during that level's built-in pacing gap), across every level.
/// Self-contained: reads and calls the controller directly.
class SideHustleCard extends StatelessWidget {
  const SideHustleCard({super.key});
  @override
  Widget build(BuildContext context) {
    final g = AppScope.of(context);
    final c = AppColors.of(context);
    return AppCard(
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const TLabel('Side hustle'),
            const SizedBox(height: 4),
            Text('Something on the side while this settles.', style: AppText.sans(size: 12.5, weight: FontWeight.w500, color: c.inkSoft)),
          ]),
        ),
        const SizedBox(width: 12),
        AppButton(kind: BtnKind.ghost, onTap: g.runSideHustle, child: const Text('Run it')),
      ]),
    );
  }
}

/// Key/value row used inside cards & sheets.
class KVRow extends StatelessWidget {
  final String label;
  final Widget value;
  const KVRow(this.label, this.value, {super.key});
  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(label, style: AppText.sans(size: 13, weight: FontWeight.w500, color: c.inkSoft)),
        value,
      ]),
    );
  }
}

/// Section header (uppercase label + optional action).
class SectionHead extends StatelessWidget {
  final String label;
  final Widget? action;
  const SectionHead(this.label, {super.key, this.action});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 0, 2, 9),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, crossAxisAlignment: CrossAxisAlignment.end, children: [
        TLabel(label),
        if (action != null) action!,
      ]),
    );
  }
}

/// Screen title header.
class ScreenHead extends StatelessWidget {
  final String title;
  final String? sub;
  final Widget? right;
  const ScreenHead(this.title, {super.key, this.sub, this.right});
  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 8, 2, 16),
      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: AppText.sans(size: 24, weight: FontWeight.w700, color: c.ink, spacing: -0.3)),
            if (sub != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text(sub!, style: AppText.sans(size: 12, weight: FontWeight.w500, color: c.inkFaint))),
          ]),
        ),
        if (right != null) right!,
      ]),
    );
  }
}

/// Bottom sheet helper with grabber + title.
Future<T?> showAppSheet<T>(BuildContext context, String title, Widget Function(BuildContext) builder) {
  final c = AppColors.of(context);
  return showModalBottomSheet<T>(
    context: context,
    backgroundColor: c.appBg,
    isScrollControlled: true,
    shape: RoundedRectangleBorder(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
        side: BorderSide(color: c.line)),
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(
          left: 18, right: 18, top: 10, bottom: MediaQuery.of(ctx).viewInsets.bottom + 28),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Center(child: Container(width: 36, height: 4, margin: const EdgeInsets.only(top: 6, bottom: 14), decoration: BoxDecoration(color: c.line, borderRadius: BorderRadius.circular(4)))),
        Text(title, style: AppText.sans(size: 17, weight: FontWeight.w700, color: c.ink)),
        const SizedBox(height: 14),
        builder(ctx),
      ]),
    ),
  );
}

/// Round initials avatar for a contact.
class ContactAvatar extends StatelessWidget {
  final String initials;
  final double size;
  const ContactAvatar(this.initials, {super.key, this.size = 40});
  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
          shape: BoxShape.circle, color: c.surfaceAlt, border: Border.all(color: c.line)),
      child: Text(initials, style: AppText.mono(size: size * 0.36, weight: FontWeight.w600, color: c.inkSoft)),
    );
  }
}

/// Chat message bubble.
class MessageBubble extends StatelessWidget {
  final String text;
  final bool fromMe;
  final bool warm; // true for personal threads — warm-toned incoming bubbles
  const MessageBubble({super.key, required this.text, required this.fromMe, this.warm = false});
  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Align(
      alignment: fromMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        constraints: const BoxConstraints(maxWidth: 280),
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
        decoration: BoxDecoration(
          color: fromMe ? c.ink : (warm ? c.personalSurface : c.surfaceAlt),
          borderRadius: BorderRadius.circular(14),
          border: fromMe ? null : Border.all(color: warm ? c.personalLine : c.line),
        ),
        child: Text(text, style: AppText.sans(size: 13.5, weight: FontWeight.w500, height: 1.4, color: fromMe ? c.primaryInk : c.ink)),
      ),
    );
  }
}

/// Rundown dialog for a level — shown from Settings > How to play.
void showLevelTutorialDialog(BuildContext context, int level) {
  final c = AppColors.of(context);
  showDialog(
    context: context,
    builder: (ctx) => Dialog(
      backgroundColor: c.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: BorderSide(color: c.line)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 28),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('LEVEL $level — ${kLevelTitles[level]}', style: AppText.sans(size: 11, weight: FontWeight.w600, color: c.inkFaint, spacing: 1.2)),
          const SizedBox(height: 10),
          Text(kTutorialBody[level]!, style: AppText.sans(size: 13.5, weight: FontWeight.w500, color: c.inkSoft, height: 1.5)),
          const SizedBox(height: 18),
          AppButton(full: true, height: 48, onTap: () => Navigator.pop(ctx), child: const Text('Got it')),
        ]),
      ),
    ),
  );
}

final AudioPlayer _chimePlayer = AudioPlayer();
Uint8List? _chimeBytes;

/// Plays the notification chime, independent of whether the banner widget
/// itself ends up mounting — a dropped frame shouldn't cost you the sound.
/// Loaded via rootBundle rather than AssetSource, since audioplayers'
/// AssetSource resolves paths through AudioCache, which on web
/// double-prefixes with "assets/". mimeType is required: audioplayers' web
/// data-URI fallback defaults to audio/mpeg, which silently fails to decode
/// actual WAV bytes.
Future<void> _playNotificationChime() async {
  try {
    _chimeBytes ??= (await rootBundle.load('assets/sounds/notification.wav')).buffer.asUint8List();
    await _chimePlayer.play(BytesSource(_chimeBytes!, mimeType: 'audio/wav'), volume: 0.6);
  } catch (_) {
    // Sound is a nice-to-have; never let a playback hiccup take the banner down.
  }
}

/// Drops the boss's "new assignment" text in as an iOS-style banner over
/// whatever screen is currently open — slides down, auto-dismisses, and
/// (like a real notification) hands off to [onOpen] on tap rather than
/// popping anything itself. The completer's future resolves once the
/// banner is gone, so callers know when it's safe to show another.
Future<void> showTutorialNotificationBanner(BuildContext context, int level, {required VoidCallback onOpen}) {
  _playNotificationChime();
  final overlay = Overlay.of(context);
  final completer = Completer<void>();
  late OverlayEntry entry;
  entry = OverlayEntry(
    builder: (ctx) => _TutorialBanner(
      level: level,
      onDismissed: () {
        entry.remove();
        if (!completer.isCompleted) completer.complete();
      },
      onOpen: onOpen,
    ),
  );
  overlay.insert(entry);
  return completer.future;
}

class _TutorialBanner extends StatefulWidget {
  final int level;
  final VoidCallback onDismissed;
  final VoidCallback onOpen;
  const _TutorialBanner({required this.level, required this.onDismissed, required this.onOpen});
  @override
  State<_TutorialBanner> createState() => _TutorialBannerState();
}

class _TutorialBannerState extends State<_TutorialBanner> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 320));
  late final Animation<Offset> _slide =
      Tween(begin: const Offset(0, -1), end: Offset.zero).animate(CurvedAnimation(parent: _c, curve: Curves.easeOutCubic));
  Timer? _autoDismiss;
  double _dragDy = 0;

  @override
  void initState() {
    super.initState();
    _c.forward();
    _autoDismiss = Timer(const Duration(seconds: 5), _dismiss);
  }

  @override
  void dispose() {
    _autoDismiss?.cancel();
    _c.dispose();
    super.dispose();
  }

  void _dismiss() {
    _autoDismiss?.cancel();
    _c.reverse().whenComplete(widget.onDismissed);
  }

  void _open() {
    _autoDismiss?.cancel();
    _c.reverse().whenComplete(() {
      widget.onDismissed();
      widget.onOpen();
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final handler = kContact['handler']!;
    return Positioned(
      top: 0,
      left: 8,
      right: 8,
      child: Material(
        type: MaterialType.transparency,
        child: SafeArea(
          bottom: false,
          child: SlideTransition(
            position: _slide,
            child: GestureDetector(
              onTap: _open,
              onVerticalDragUpdate: (d) {
                if (d.delta.dy < 0) setState(() => _dragDy += d.delta.dy);
              },
              onVerticalDragEnd: (_) {
                if (_dragDy < -18) {
                  _dismiss();
                } else {
                  setState(() => _dragDy = 0);
                }
              },
              child: Transform.translate(
                offset: Offset(0, _dragDy),
                child: Container(
                  margin: const EdgeInsets.only(top: 6),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: c.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: c.line),
                    boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.28), blurRadius: 22, offset: const Offset(0, 10))],
                  ),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    ContactAvatar(handler.initials, size: 34),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          Expanded(child: Text(handler.name, style: AppText.sans(size: 13, weight: FontWeight.w700, color: c.ink))),
                          Text('now', style: AppText.sans(size: 11, weight: FontWeight.w500, color: c.inkFaint)),
                        ]),
                        const SizedBox(height: 2),
                        Text(
                          kTutorialBody[widget.level]!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.sans(size: 12.5, weight: FontWeight.w500, color: c.inkSoft, height: 1.3),
                        ),
                      ]),
                    ),
                  ]),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// ── Tab bar glyphs — hand-drawn shapes matching the burner-phone mockup ──

class HomeGlyph extends StatelessWidget {
  final Color color;
  const HomeGlyph(this.color, {super.key});
  @override
  Widget build(BuildContext context) {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      CustomPaint(size: const Size(13, 8), painter: _RoofPainter(color)),
      Container(width: 13, height: 8, margin: const EdgeInsets.only(top: 1), color: color),
    ]);
  }
}

class _RoofPainter extends CustomPainter {
  final Color color;
  _RoofPainter(this.color);
  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(size.width / 2, 0)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_RoofPainter old) => old.color != color;
}

class MessagesGlyph extends StatelessWidget {
  final Color color;
  final bool unread;
  const MessagesGlyph(this.color, {super.key, this.unread = false});
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 21,
      height: 16,
      child: Stack(clipBehavior: Clip.none, children: [
        Center(
          child: Container(
            width: 17,
            height: 12,
            decoration: BoxDecoration(
              border: Border.all(color: color, width: 1.5),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(3),
                topRight: Radius.circular(3),
                bottomRight: Radius.circular(3),
                bottomLeft: Radius.circular(1),
              ),
            ),
          ),
        ),
        if (unread)
          Positioned(
            top: -2,
            right: 0,
            child: Container(width: 6, height: 6, decoration: BoxDecoration(shape: BoxShape.circle, color: color)),
          ),
      ]),
    );
  }
}

class ContactsGlyph extends StatelessWidget {
  final Color color;
  const ContactsGlyph(this.color, {super.key});
  @override
  Widget build(BuildContext context) {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 7, height: 7, decoration: BoxDecoration(shape: BoxShape.circle, color: color)),
      Container(
          width: 14,
          height: 7,
          margin: const EdgeInsets.only(top: 2),
          decoration: BoxDecoration(color: color, borderRadius: const BorderRadius.vertical(top: Radius.circular(7)))),
    ]);
  }
}

class SettingsGlyph extends StatelessWidget {
  final Color color;
  const SettingsGlyph(this.color, {super.key});
  @override
  Widget build(BuildContext context) {
    return Icon(Icons.settings_outlined, size: 17, color: color);
  }
}

/// ── Animated road strip that shows the actual sighting on watch ──
///
/// One vehicle crosses per sighting, styled by [Sighting.kind], timed to the
/// same [CareerController.responseWindowSeconds] window as the countdown —
/// so what's on the road always matches what the player is being asked about.

class RoadAnimation extends StatefulWidget {
  final Sighting? sighting;
  final int sightingSeq;
  const RoadAnimation({super.key, required this.sighting, required this.sightingSeq});
  @override
  State<RoadAnimation> createState() => _RoadAnimationState();
}

class _RoadAnimationState extends State<RoadAnimation> with SingleTickerProviderStateMixin {
  static const _truckWidth = 42.0, _suvWidth = 30.0, _vanWidth = 26.0;

  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(seconds: CareerController.responseWindowSeconds),
  );

  @override
  void initState() {
    super.initState();
    if (widget.sighting != null) _c.forward(from: 0);
  }

  @override
  void didUpdateWidget(covariant RoadAnimation old) {
    super.didUpdateWidget(old);
    if (widget.sightingSeq != old.sightingSeq && widget.sighting != null) {
      _c.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final sighting = widget.sighting;
    return Container(
      height: 60,
      clipBehavior: Clip.hardEdge,
      decoration: BoxDecoration(
        color: c.sunken,
        border: Border.symmetric(horizontal: BorderSide(color: c.line)),
      ),
      child: LayoutBuilder(builder: (context, constraints) {
        final w = constraints.maxWidth;
        return Stack(children: [
          Positioned(
            top: 0,
            bottom: 0,
            left: 0,
            right: 0,
            child: Center(
              child: CustomPaint(size: Size(w, 2), painter: _CenterlinePainter(c.line)),
            ),
          ),
          if (sighting != null)
            AnimatedBuilder(
              animation: _c,
              builder: (context, _) {
                final width = _vehicleWidth(sighting.kind);
                final forward = sighting.description.hashCode.isEven;
                final travel = w + width + 40;
                final x = forward ? -width - 20 + _c.value * travel : w + 20 - _c.value * travel;
                final opacity = _c.value < 0.94 ? 1.0 : ((1 - _c.value) / 0.06).clamp(0.0, 1.0);
                return Positioned(
                  bottom: 14,
                  left: x,
                  child: Opacity(
                    opacity: opacity,
                    // Trucks and vans have a front — mirror them so the cab
                    // leads whichever way they're actually driving.
                    child: Transform.flip(flipX: !forward, child: _vehicleShape(sighting.kind, c)),
                  ),
                );
              },
            ),
        ]);
      }),
    );
  }

  double _vehicleWidth(SightingKind kind) {
    switch (kind) {
      case SightingKind.military:
        return _truckWidth;
      case SightingKind.rival:
        return _suvWidth;
      case SightingKind.civilian:
        return _vanWidth;
    }
  }

  Widget _vehicleShape(SightingKind kind, AppColors c) {
    switch (kind) {
      case SightingKind.military:
        return _TruckShape(width: _truckWidth, height: 16, color: c.ink);
      case SightingKind.rival:
        return _SuvShape(width: _suvWidth, height: 12, color: c.inkSoft, glass: c.sunken);
      case SightingKind.civilian:
        return _VanShape(width: _vanWidth, height: 18, color: c.inkFaint, glass: c.surface);
    }
  }
}

class _CenterlinePainter extends CustomPainter {
  final Color color;
  _CenterlinePainter(this.color);
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2;
    const dash = 14.0, gap = 14.0;
    double x = 0;
    while (x < size.width) {
      canvas.drawLine(Offset(x, 1), Offset(x + dash, 1), paint);
      x += dash + gap;
    }
  }

  @override
  bool shouldRepaint(_CenterlinePainter old) => old.color != color;
}

/// Shared wheel dot used by every road-vehicle silhouette below.
Widget _wheel(double size, Color color) =>
    Container(width: size, height: size, decoration: BoxDecoration(shape: BoxShape.circle, color: color));

/// Military convoy — a cargo box trailing a shorter cab, front on the right.
class _TruckShape extends StatelessWidget {
  final double width, height;
  final Color color;
  const _TruckShape({required this.width, required this.height, required this.color});
  @override
  Widget build(BuildContext context) {
    final wheel = width * 0.16;
    final cabWidth = width * 0.34;
    final cargoWidth = width - cabWidth;
    return SizedBox(
      width: width,
      height: height + wheel * 0.6,
      child: Stack(clipBehavior: Clip.none, children: [
        Positioned(
          left: 0,
          bottom: 0,
          child: Container(
            width: cargoWidth,
            height: height,
            decoration: BoxDecoration(color: color, borderRadius: const BorderRadius.horizontal(left: Radius.circular(2))),
          ),
        ),
        Positioned(
          right: 0,
          bottom: 0,
          child: Container(
            width: cabWidth,
            height: height * 0.7,
            decoration: BoxDecoration(color: color, borderRadius: const BorderRadius.horizontal(right: Radius.circular(3))),
          ),
        ),
        Positioned(bottom: -wheel * 0.3, left: cargoWidth * 0.24, child: _wheel(wheel, color)),
        Positioned(bottom: -wheel * 0.3, right: cabWidth * 0.3, child: _wheel(wheel, color)),
      ]),
    );
  }
}

/// Rival SUV — a low body with a tinted, boxier cabin raised on top.
class _SuvShape extends StatelessWidget {
  final double width, height;
  final Color color;
  final Color glass;
  const _SuvShape({required this.width, required this.height, required this.color, required this.glass});
  @override
  Widget build(BuildContext context) {
    final wheel = width * 0.2;
    final cabinWidth = width * 0.58;
    final cabinHeight = height * 0.8;
    return SizedBox(
      width: width,
      height: height + cabinHeight * 0.6 + wheel * 0.5,
      child: Stack(clipBehavior: Clip.none, alignment: Alignment.bottomCenter, children: [
        Positioned(
          bottom: 0,
          child: Container(
            width: width,
            height: height,
            decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3)),
          ),
        ),
        Positioned(
          bottom: height * 0.5,
          child: Container(
            width: cabinWidth,
            height: cabinHeight,
            decoration: BoxDecoration(color: glass, borderRadius: BorderRadius.circular(3), border: Border.all(color: color, width: 1.5)),
          ),
        ),
        Positioned(bottom: -wheel * 0.3, left: width * 0.1, child: _wheel(wheel, color)),
        Positioned(bottom: -wheel * 0.3, right: width * 0.1, child: _wheel(wheel, color)),
      ]),
    );
  }
}

/// Civilian delivery van — tall and boxy, with a windshield notch up front.
class _VanShape extends StatelessWidget {
  final double width, height;
  final Color color;
  final Color glass;
  const _VanShape({required this.width, required this.height, required this.color, required this.glass});
  @override
  Widget build(BuildContext context) {
    final wheel = width * 0.22;
    return SizedBox(
      width: width,
      height: height + wheel * 0.6,
      child: Stack(clipBehavior: Clip.none, children: [
        Container(
          width: width,
          height: height,
          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2)),
        ),
        Positioned(
          right: width * 0.08,
          top: height * 0.12,
          child: Container(
            width: width * 0.24,
            height: height * 0.32,
            decoration: BoxDecoration(color: glass, borderRadius: BorderRadius.circular(1.5)),
          ),
        ),
        Positioned(bottom: -wheel * 0.3, left: width * 0.18, child: _wheel(wheel, color)),
        Positioned(bottom: -wheel * 0.3, right: width * 0.18, child: _wheel(wheel, color)),
      ]),
    );
  }
}
