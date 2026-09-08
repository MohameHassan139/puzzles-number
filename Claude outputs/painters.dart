// Everything the board and the rack are drawn with.
//
// The painters take the clock as their `repaint` listenable, so a frame costs
// one call to paint() and no widget rebuild at all. Between frames they hang on
// to the lattice path and the digit layouts, which is the difference between
// 900 fresh allocations per frame and none.

import 'dart:math';

import 'package:flutter/material.dart';

import 'effects.dart';
import 'model.dart';
import 'theme.dart';

// ─────────────────────────────────────────────────────────────
// Shapes
// ─────────────────────────────────────────────────────────────

Offset _towards(Offset from, Offset to, double dist) {
  final Offset d = to - from;
  final double len = d.distance;
  if (len <= 0.0001) return from;
  return from + d * (dist / len);
}

/// A triangle with its points taken off — the single change that stops the
/// board reading as cut glass and starts it reading as sweets.
Path candyTrianglePath(List<Offset> v, double radius) {
  final Path p = Path();
  for (int i = 0; i < 3; i++) {
    final Offset here = v[i];
    final Offset prev = v[(i + 2) % 3];
    final Offset next = v[(i + 1) % 3];
    final Offset inPoint = _towards(here, prev, radius);
    final Offset outPoint = _towards(here, next, radius);
    if (i == 0) {
      p.moveTo(inPoint.dx, inPoint.dy);
    } else {
      p.lineTo(inPoint.dx, inPoint.dy);
    }
    p.quadraticBezierTo(here.dx, here.dy, outPoint.dx, outPoint.dy);
  }
  p.close();
  return p;
}

Path trianglePath(List<Offset> v) => Path()
  ..moveTo(v[0].dx, v[0].dy)
  ..lineTo(v[1].dx, v[1].dy)
  ..lineTo(v[2].dx, v[2].dy)
  ..close();

// ─────────────────────────────────────────────────────────────
// Digits
// ─────────────────────────────────────────────────────────────

final Map<String, TextPainter> _digitCache = <String, TextPainter>{};

TextPainter _digit(int n, double size, Color colour) {
  final String key = '$n|${size.toStringAsFixed(1)}|${colour.toString()}';
  final TextPainter? hit = _digitCache[key];
  if (hit != null) return hit;
  final TextPainter tp = TextPainter(
    text: TextSpan(
      text: '$n',
      style: TextStyle(
        color: colour,
        fontSize: size,
        fontWeight: FontWeight.w900,
        height: 1,
        shadows: <Shadow>[Shadow(color: black(0.35), blurRadius: 2, offset: const Offset(0, 1.4))],
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  if (_digitCache.length > 60) _digitCache.clear();
  _digitCache[key] = tp;
  return tp;
}

// ─────────────────────────────────────────────────────────────
// One corner
// ─────────────────────────────────────────────────────────────

/// Draws corner [i] as a pie slice pinned to the vertex, spanning the interior
/// angle there — 60°, one sixth of a circle. Six triangles meet at every vertex
/// of the lattice, so their six wedges close into one whole disc and the tile
/// outlines become the spokes.
///
/// The gloss is three flat arcs rather than a gradient shader: a rim, the body,
/// and a highlight near the vertex. It reads the same and costs nothing, which
/// matters when a full board draws three hundred of them.
void paintCornerWedge(
  Canvas canvas,
  List<Offset> v,
  int i,
  TCorner corner,
  double r, {
  double alpha = 1,
}) {
  final Offset o = v[i];
  final Offset toNext = v[(i + 1) % 3] - o;
  final Offset toPrev = v[(i + 2) % 3] - o;

  // Sweep from one edge to the other the short way round, so the wedge lands
  // inside the triangle whichever way it points.
  final double start = atan2(toNext.dy, toNext.dx);
  double sweep = atan2(toPrev.dy, toPrev.dx) - start;
  while (sweep <= -pi) {
    sweep += 2 * pi;
  }
  while (sweep > pi) {
    sweep -= 2 * pi;
  }

  void slice(double radius, int rgb) {
    canvas.drawArc(
      Rect.fromCircle(center: o, radius: radius),
      start,
      sweep,
      true,
      Paint()..color = rgba(rgb, alpha),
    );
  }

  if (corner.isJoker) {
    // Every colour, stacked outward from the vertex — the rainbow tile.
    for (int k = kCandies.length - 1; k >= 0; k--) {
      final double band = r * (k + 1) / kCandies.length;
      slice(band, kCandies[k].base);
      slice(band * 0.82, kCandies[k].light);
    }
  } else {
    final Candy candy = kCandies[corner.color % kCandies.length];
    slice(r, candy.dark);
    slice(r * 0.93, candy.base);
    slice(r * 0.52, candy.light);
  }

  // The rim that separates one corner from the next.
  canvas.drawArc(
    Rect.fromCircle(center: o, radius: r),
    start,
    sweep,
    true,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = r * 0.055
      ..strokeJoin = StrokeJoin.round
      ..color = rgba(rgbInk, 0.30 * alpha),
  );

  if (corner.isJoker) return;

  final double mid = start + sweep / 2;
  final Offset p = o + Offset(cos(mid), sin(mid)) * (r * 0.62);
  final TextPainter tp = _digit(corner.number, r * 0.52, white(alpha));
  tp.paint(canvas, p - Offset(tp.width / 2, tp.height / 2));
}

// ─────────────────────────────────────────────────────────────
// One tile
// ─────────────────────────────────────────────────────────────

/// A whole triangle: shadow, glossy face, three wedges, outline.
void paintCandyTile(
  Canvas canvas,
  List<Offset> v,
  List<TCorner> corners,
  double wedgeR, {
  int edge = rgbInk,
  double edgeWidth = 2.4,
  double shadow = 3,
  double alpha = 1,
  bool blurShadow = false,
}) {
  final double round = wedgeR * 0.22;
  final Path path = candyTrianglePath(v, round);

  if (shadow > 0) {
    final Paint sp = Paint()..color = black(0.26 * alpha);
    if (blurShadow) sp.maskFilter = const MaskFilter.blur(BlurStyle.normal, 5);
    canvas.save();
    canvas.translate(0, shadow);
    canvas.drawPath(path, sp);
    canvas.restore();
  }

  canvas.drawPath(path, Paint()..color = cream(alpha));

  // Wedges are clipped to the rounded outline so nothing spills past the tips.
  canvas.save();
  canvas.clipPath(path);
  for (int i = 0; i < 3; i++) {
    paintCornerWedge(canvas, v, i, corners[i], wedgeR, alpha: alpha);
  }
  canvas.restore();

  canvas.drawPath(
    path,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = edgeWidth
      ..strokeJoin = StrokeJoin.round
      ..color = rgba(edge, alpha),
  );
}

// ─────────────────────────────────────────────────────────────
// The board
// ─────────────────────────────────────────────────────────────

class BoardPainter extends CustomPainter {
  final Map<String, Placed> board;
  final Set<String> strong;
  final Set<String> weak;
  final Map<String, double> placedAt;
  final List<Fx> fx;
  final ValueListenable<double> clock;
  final Point<int>? last;
  final Point<int>? hint;

  BoardPainter({
    required this.board,
    required this.strong,
    required this.weak,
    required this.placedAt,
    required this.fx,
    required this.clock,
    this.last,
    this.hint,
  }) : super(repaint: clock);

  Path? _latticeCache;

  /// The faint empty lattice, batched into a single path. Rebuilding 231 little
  /// paths every frame was the one thing standing between this and 60fps.
  Path _lattice() {
    final Path? hit = _latticeCache;
    if (hit != null) return hit;
    final Path p = Path();
    for (int r = 0; r < kRows; r++) {
      for (int c = 0; c < kCols; c++) {
        final String k = cellKey(r, c);
        if (board.containsKey(k) || strong.contains(k) || weak.contains(k)) continue;
        p.addPath(candyTrianglePath(cellVerts(r, c), 5), Offset.zero);
      }
    }
    _latticeCache = p;
    return p;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final double now = clock.value;

    // 1. the empty lattice, in one go
    final Path lattice = _lattice();
    canvas.drawPath(lattice, Paint()..color = white(0.035));
    canvas.drawPath(
      lattice,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = white(0.06),
    );

    // 2. spaces this tile could go
    final double pulse = 0.5 + 0.5 * sin(now * 3.4);
    for (final String k in weak) {
      final Point<int> p = parseCellKey(k);
      final Path path = candyTrianglePath(cellVerts(p.x, p.y), 6);
      canvas.drawPath(path, Paint()..color = gold(0.10 + 0.05 * pulse));
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6
          ..strokeJoin = StrokeJoin.round
          ..color = gold(0.34),
      );
    }
    for (final String k in strong) {
      final Point<int> p = parseCellKey(k);
      final Path path = candyTrianglePath(cellVerts(p.x, p.y), 7);
      canvas.drawPath(path, Paint()..color = gold(0.22 + 0.16 * pulse));
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.6 + 0.8 * pulse
          ..strokeJoin = StrokeJoin.round
          ..color = gold(0.75 + 0.25 * pulse),
      );
      final Offset centre = cellCentre(p.x, p.y);
      canvas.drawCircle(centre, 4.5 + 1.6 * pulse, Paint()..color = white(0.5 + 0.3 * pulse));
    }

    // 3. the tiles
    board.forEach((String k, Placed placed) {
      final Point<int> p = parseCellKey(k);
      final List<Offset> v = cellVerts(p.x, p.y);
      final Point<int>? l = last;
      final bool isLast = l != null && l.x == p.x && l.y == p.y;

      final double? born = placedAt[k];
      final double s = born == null ? 1 : popScale((now - born) / 0.42);

      canvas.save();
      if (s != 1) {
        final Offset centre = cellCentre(p.x, p.y);
        canvas.translate(centre.dx, centre.dy);
        canvas.scale(s);
        canvas.translate(-centre.dx, -centre.dy);
      }
      paintCandyTile(
        canvas,
        v,
        placed.corners,
        kW * kWedge,
        edge: isLast ? rgbGoldDeep : rgbInk,
        edgeWidth: isLast ? 3.4 : 2.2,
      );
      canvas.restore();
    });

    // 4. the hinted space
    final Point<int>? h = hint;
    if (h != null) {
      final Offset centre = cellCentre(h.x, h.y);
      final double ring = 0.5 + 0.5 * sin(now * 4.2);
      canvas.drawCircle(
        centre,
        kW * 0.36 + 5 * ring,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3.4
          ..color = gold(0.5 + 0.5 * ring),
      );
    }

    // 5. the juice
    _paintFx(canvas, now);
  }

  void _paintFx(Canvas canvas, double now) {
    for (final Fx f in fx) {
      final double a = f.age(now);
      if (a < 0 || a >= 1) continue;
      switch (f.kind) {
        case FxKind.wave:
          final double e = easeOut(a);
          canvas.drawCircle(
            f.at,
            kW * 0.24 + kW * 0.62 * e,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 5 * (1 - e)
              ..color = rgba(f.rgb, 0.55 * fadeOut(a)),
          );
          break;

        case FxKind.join:
          canvas.drawCircle(
            f.at,
            kW * kWedge * (0.4 + 0.34 * easeOut(a)),
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2.6
              ..color = white(0.95 * fadeOut(a)),
          );
          break;

        case FxKind.sparkle:
          final double e = easeOut(a);
          // the gold ring
          canvas.drawCircle(
            f.at,
            kW * kWedge * (0.5 + 1.05 * e),
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 6 * (1 - e * 0.8)
              ..color = gold(0.95 * fadeOut(a)),
          );
          // and the sparks off it
          final double t = a * f.life;
          for (int i = 0; i < kSparkCount; i++) {
            final Spark sp = Spark.of(f.seed, i, kSparkCount);
            final Offset at = f.at + sp.at(t);
            final double sz = sp.size * (1 - a);
            if (sz <= 0.2) continue;
            canvas.save();
            canvas.translate(at.dx, at.dy);
            canvas.rotate(sp.spin * t);
            final Paint paint = Paint()..color = gold(fadeOut(a));
            canvas.drawRRect(
              RRect.fromRectAndRadius(
                Rect.fromCenter(center: Offset.zero, width: sz * 2.4, height: sz * 0.8),
                Radius.circular(sz * 0.4),
              ),
              paint,
            );
            canvas.drawRRect(
              RRect.fromRectAndRadius(
                Rect.fromCenter(center: Offset.zero, width: sz * 0.8, height: sz * 2.4),
                Radius.circular(sz * 0.4),
              ),
              paint,
            );
            canvas.restore();
          }
          break;

        case FxKind.score:
          final double rise = 54 * easeOut(a);
          final double scale = a < 0.18 ? 0.6 + 2.2 * a : 1.0;
          final TextPainter tp = TextPainter(
            text: TextSpan(
              text: f.text,
              style: TextStyle(
                color: rgba(f.rgb, fadeOut(a)),
                fontSize: 30,
                fontWeight: FontWeight.w900,
                height: 1,
                shadows: <Shadow>[
                  Shadow(color: black(0.5 * fadeOut(a)), blurRadius: 4, offset: const Offset(0, 2)),
                ],
              ),
            ),
            textDirection: TextDirection.ltr,
          )..layout();
          canvas.save();
          canvas.translate(f.at.dx, f.at.dy - rise);
          canvas.scale(scale);
          tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
          canvas.restore();
          break;
      }
    }
  }

  @override
  bool shouldRepaint(covariant BoardPainter old) => true;
}

// ─────────────────────────────────────────────────────────────
// A rack tile
// ─────────────────────────────────────────────────────────────

class TilePainter extends CustomPainter {
  final List<TCorner> corners;
  final bool selected;
  final double lift;

  TilePainter(this.corners, {this.selected = false, this.lift = 0});

  @override
  void paint(Canvas canvas, Size size) {
    final double w = size.width;
    final double h = w * 0.866;
    final double top = (size.height - h) / 2 - lift;
    final List<Offset> v = <Offset>[
      Offset(w / 2, top),
      Offset(w - 3, top + h),
      Offset(3, top + h),
    ];
    paintCandyTile(
      canvas,
      v,
      corners,
      w * kWedge,
      edge: selected ? rgbGoldDeep : rgbInk,
      edgeWidth: selected ? 3.2 : 2.4,
      shadow: selected ? 6 : 3,
      blurShadow: true,
    );
  }

  @override
  bool shouldRepaint(covariant TilePainter old) =>
      old.selected != selected || old.lift != lift || old.corners != corners;
}
