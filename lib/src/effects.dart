// The bits of the game that exist purely to feel good: the pop a triangle
// makes when it lands, the sparks off a closed circle, the score that floats
// away. All of it is data — a list of little timed events with a birthday —
// so the painter can draw the whole thing from one clock and nothing needs a
// controller of its own.

import 'dart:math';

import 'package:flutter/material.dart';

enum FxKind {
  /// An expanding ring where a triangle landed.
  wave,

  /// A white ring on each corner that matched.
  join,

  /// A gold burst plus flying sparks: a circle just closed.
  sparkle,

  /// "+8" drifting upward.
  score,
}

class Fx {
  final FxKind kind;
  final Offset at;
  final double start; // seconds, on the game clock
  final double life; // seconds
  final int rgb;
  final String text;
  final int seed;

  const Fx({
    required this.kind,
    required this.at,
    required this.start,
    required this.life,
    this.rgb = 0xFFFFFF,
    this.text = '',
    this.seed = 0,
  });

  /// 0 at birth, 1 at death, above 1 once it should be dropped.
  double age(double now) => (now - start) / life;

  bool alive(double now) => age(now) < 1;
}

/// How a triangle grows into its place: up past full size, then back down.
double popScale(double a) {
  if (a >= 1) return 1;
  if (a <= 0) return 0.25;
  return 0.25 + 0.75 * Curves.easeOutBack.transform(a);
}

double easeOut(double a) => a <= 0 ? 0 : (a >= 1 ? 1 : Curves.easeOutCubic.transform(a));

double fadeOut(double a) => a <= 0 ? 1 : (a >= 1 ? 0 : 1 - Curves.easeInQuad.transform(a));

/// A spark thrown off a closing circle. Deterministic in [seed] and [i] so the
/// same burst redraws identically every frame without storing anything.
class Spark {
  final double angle;
  final double speed;
  final double size;
  final double spin;

  const Spark(this.angle, this.speed, this.size, this.spin);

  static Spark of(int seed, int i, int count) {
    final Random r = Random(seed * 7919 + i * 31);
    final double slice = 2 * pi / count;
    return Spark(
      i * slice + r.nextDouble() * slice,
      70 + r.nextDouble() * 95,
      3.2 + r.nextDouble() * 3.4,
      (r.nextDouble() - 0.5) * 9,
    );
  }

  /// Where the spark is [t] seconds after the burst, relative to its origin.
  Offset at(double t) => Offset(
        cos(angle) * speed * t,
        sin(angle) * speed * t + 210 * t * t, // a little gravity
      );
}

const int kSparkCount = 13;
