// The furniture: buttons that squash when you press them, player cards whose
// score rolls up, and the panel every one of them sits on.

import 'package:flutter/material.dart';

import 'theme.dart';

/// A pill that presses in. Nothing else in the game gives back that much for
/// so little — a button that does not move under the thumb feels broken next to
/// one that does.
class CandyButton extends StatefulWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onTap;
  final List<Color> colors;
  final Color textColor;
  final bool compact;
  final bool glow;

  const CandyButton({
    super.key,
    required this.label,
    this.icon,
    this.onTap,
    this.colors = const <Color>[Color(0xFFFFD452), Color(0xFFF0A81E)],
    this.textColor = kGoldInk,
    this.compact = false,
    this.glow = false,
  });

  @override
  State<CandyButton> createState() => _CandyButtonState();
}

class _CandyButtonState extends State<CandyButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final bool enabled = widget.onTap != null;
    final double h = widget.compact ? 42 : 52;

    return GestureDetector(
      onTapDown: enabled ? (TapDownDetails _) => setState(() => _down = true) : null,
      onTapUp: enabled ? (TapUpDetails _) => setState(() => _down = false) : null,
      onTapCancel: enabled ? () => setState(() => _down = false) : null,
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _down ? 0.94 : 1,
        duration: const Duration(milliseconds: 90),
        curve: Curves.easeOut,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          height: h,
          padding: EdgeInsets.symmetric(horizontal: widget.compact ? 14 : 20),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: enabled
                  ? widget.colors
                  : <Color>[white(0.13), white(0.08)],
            ),
            borderRadius: BorderRadius.circular(h / 2),
            border: Border.all(color: white(enabled ? 0.35 : 0.12), width: 1.4),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: black(_down ? 0.18 : 0.34),
                blurRadius: _down ? 6 : 12,
                offset: Offset(0, _down ? 2 : 5),
              ),
              if (widget.glow && enabled)
                BoxShadow(color: gold(0.5), blurRadius: 22, spreadRadius: 1),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              if (widget.icon != null) ...<Widget>[
                Icon(widget.icon,
                    size: widget.compact ? 17 : 19,
                    color: enabled ? widget.textColor : white(0.35)),
                const SizedBox(width: 7),
              ],
              Flexible(
                child: Text(
                  widget.label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: enabled ? widget.textColor : white(0.35),
                    fontSize: widget.compact ? 14 : 16,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.1,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A number that rolls to its new value instead of jumping. Scores that tick up
/// are read as *earned*; scores that snap are read as bookkeeping.
class RollingNumber extends StatelessWidget {
  final int value;
  final TextStyle style;

  const RollingNumber(this.value, this.style, {super.key});

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: value.toDouble(), end: value.toDouble()),
        duration: const Duration(milliseconds: 420),
        curve: Curves.easeOutCubic,
        builder: (BuildContext _, double v, Widget? __) =>
            Text('${v.round()}', style: style),
      );
}

/// One side's card in the head-up display.
class PlayerCard extends StatelessWidget {
  final String name;
  final int score;
  final int tiles;
  final bool active;
  final Color accent;
  final bool thinking;

  const PlayerCard({
    super.key,
    required this.name,
    required this.score,
    required this.tiles,
    required this.active,
    required this.accent,
    this.thinking = false,
  });

  @override
  Widget build(BuildContext context) => AnimatedContainer(
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOut,
        padding: const EdgeInsets.fromLTRB(10, 8, 12, 8),
        decoration: BoxDecoration(
          color: white(active ? 0.16 : 0.07),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: active ? accent : white(0.10),
            width: active ? 2 : 1.2,
          ),
          boxShadow: active
              ? <BoxShadow>[BoxShadow(color: black(0.28), blurRadius: 14, offset: const Offset(0, 5))]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            AnimatedContainer(
              duration: const Duration(milliseconds: 260),
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: active ? accent : white(0.28),
                boxShadow: active
                    ? <BoxShadow>[BoxShadow(color: accent, blurRadius: 10)]
                    : null,
              ),
            ),
            const SizedBox(width: 9),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  thinking ? '$name · thinking…' : name,
                  style: TextStyle(
                    color: white(active ? 0.95 : 0.55),
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.3,
                  ),
                ),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: <Widget>[
                    RollingNumber(
                      score,
                      TextStyle(
                        color: active ? kCream : white(0.62),
                        fontSize: 21,
                        fontWeight: FontWeight.w900,
                        height: 1.05,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text('· $tiles left',
                        style: TextStyle(color: white(0.42), fontSize: 11)),
                  ],
                ),
              ],
            ),
          ],
        ),
      );
}

/// The frosted panel the board and the tray sit in.
class Panel extends StatelessWidget {
  final Widget child;
  final EdgeInsets margin;
  final double radius;
  final List<Color>? gradient;

  const Panel({
    super.key,
    required this.child,
    this.margin = EdgeInsets.zero,
    this.radius = 24,
    this.gradient,
  });

  @override
  Widget build(BuildContext context) => Container(
        margin: margin,
        decoration: BoxDecoration(
          color: gradient == null ? black(0.20) : null,
          gradient: gradient == null
              ? null
              : LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: gradient!,
                ),
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(color: white(0.10), width: 1.2),
          boxShadow: <BoxShadow>[
            BoxShadow(color: black(0.30), blurRadius: 18, offset: const Offset(0, 8)),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: child,
      );
}

/// A small label chip — level, matching rule, pile count.
class Chip2 extends StatelessWidget {
  final String text;
  final IconData? icon;
  final Color? tint;

  const Chip2(this.text, {super.key, this.icon, this.tint});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: white(0.10),
          borderRadius: BorderRadius.circular(11),
          border: Border.all(color: white(0.12)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (icon != null) ...<Widget>[
              Icon(icon, size: 13, color: tint ?? white(0.6)),
              const SizedBox(width: 5),
            ],
            Text(text,
                style: TextStyle(
                    color: tint ?? white(0.72),
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700)),
          ],
        ),
      );
}
