// The board, the tiles, and the one rule that decides everything: two triangles
// may touch only when both corners they share agree.

import 'dart:math';
import 'dart:ui' show Offset;

/// Five colours, numbers 1–5: twenty-five possible corner types in all.
const int kColourCount = 5;

// Board geometry.
const int kRows = 11;
const int kCols = 21;
const double kW = 74; // triangle base
const double kH = kW * 0.866; // triangle height

const double kBoardW = kCols * kW / 2 + kW / 2;
const double kBoardH = kRows * kH;

/// Corner wedge radius, as a fraction of the triangle's side. Must stay below
/// 0.5 — at 0.5 the wedges of two corners on the same edge would touch.
const double kWedge = 0.45;

/// One corner of a triangle. [color] and [number] are -1 for a joker corner.
class TCorner {
  final int color;
  final int number;

  const TCorner(this.color, this.number);
  const TCorner.joker()
      : color = -1,
        number = -1;

  bool get isJoker => color < 0;

  @override
  String toString() => isJoker ? 'joker' : 'c$color/$number';
}

const TCorner kJoker = TCorner.joker();
const List<TCorner> kJokerCorners = <TCorner>[kJoker, kJoker, kJoker];

class Tile {
  final int id;
  final List<TCorner> corners; // clockwise, 3 entries

  const Tile(this.id, this.corners);

  /// Corners after turning the tile [k] notches (120° each).
  List<TCorner> rotated(int k) =>
      <TCorner>[for (int i = 0; i < 3; i++) corners[(i + k) % 3]];

  bool get isJoker => corners.every((TCorner c) => c.isJoker);

  /// The same tile with every corner turned into a joker. Used by the silent
  /// rescue when the pile has nothing left that fits.
  Tile asJoker() => Tile(id, kJokerCorners);
}

class Placed {
  final Tile tile;
  final List<TCorner> corners; // already rotated into place

  /// Which player laid it: 0 for you, 1 for the opponent, -1 for the root.
  final int owner;

  const Placed(this.tile, this.corners, [this.owner = -1]);
}

enum MatchMode { colourAndNumber, colourOrNumber, colourOnly, numberOnly }

String matchModeLabel(MatchMode m) {
  switch (m) {
    case MatchMode.colourAndNumber:
      return 'Same colour and same number';
    case MatchMode.colourOrNumber:
      return 'Same colour or same number';
    case MatchMode.colourOnly:
      return 'Same colour only';
    case MatchMode.numberOnly:
      return 'Same number only';
  }
}

String matchModeShort(MatchMode m) {
  switch (m) {
    case MatchMode.colourAndNumber:
      return 'Colour + number';
    case MatchMode.colourOrNumber:
      return 'Colour or number';
    case MatchMode.colourOnly:
      return 'Colour only';
    case MatchMode.numberOnly:
      return 'Number only';
  }
}

bool cornersMatch(TCorner a, TCorner b, MatchMode m) {
  if (a.isJoker || b.isJoker) return true;
  switch (m) {
    case MatchMode.colourAndNumber:
      return a.color == b.color && a.number == b.number;
    case MatchMode.colourOrNumber:
      return a.color == b.color || a.number == b.number;
    case MatchMode.colourOnly:
      return a.color == b.color;
    case MatchMode.numberOnly:
      return a.number == b.number;
  }
}

// ─────────────────────────────────────────────────────────────
// Geometry
// ─────────────────────────────────────────────────────────────

bool isUp(int r, int c) => (r + c) % 2 == 0;

String cellKey(int r, int c) => '$r,$c';

Point<int> parseCellKey(String key) {
  final int i = key.indexOf(',');
  return Point<int>(
    int.parse(key.substring(0, i)),
    int.parse(key.substring(i + 1)),
  );
}

bool inBounds(int r, int c) => r >= 0 && r < kRows && c >= 0 && c < kCols;

/// Vertices in clockwise order; index i is corner i.
/// Up triangle:   0 = top,    1 = bottom-right, 2 = bottom-left
/// Down triangle: 0 = bottom, 1 = top-left,     2 = top-right
List<Offset> cellVerts(int r, int c) {
  final double x0 = c * kW / 2;
  final double y0 = r * kH;
  if (isUp(r, c)) {
    return <Offset>[
      Offset(x0 + kW / 2, y0),
      Offset(x0 + kW, y0 + kH),
      Offset(x0, y0 + kH),
    ];
  }
  return <Offset>[
    Offset(x0 + kW / 2, y0 + kH),
    Offset(x0, y0),
    Offset(x0 + kW, y0),
  ];
}

Offset cellCentre(int r, int c) {
  final List<Offset> v = cellVerts(r, c);
  return Offset(
    (v[0].dx + v[1].dx + v[2].dx) / 3,
    (v[0].dy + v[1].dy + v[2].dy) / 3,
  );
}

class Neighbour {
  final int r;
  final int c;

  /// Pairs of [myCornerIndex, theirCornerIndex] along the shared edge.
  final List<List<int>> pairs;

  const Neighbour(this.r, this.c, this.pairs);
}

const List<List<int>> _upLeft = <List<int>>[<int>[0, 2], <int>[2, 0]];
const List<List<int>> _upRight = <List<int>>[<int>[0, 1], <int>[1, 0]];
const List<List<int>> _upDown = <List<int>>[<int>[1, 2], <int>[2, 1]];
const List<List<int>> _dnLeft = <List<int>>[<int>[1, 0], <int>[0, 1]];
const List<List<int>> _dnRight = <List<int>>[<int>[2, 0], <int>[0, 2]];
const List<List<int>> _dnUp = <List<int>>[<int>[2, 1], <int>[1, 2]];

List<Neighbour> neighbours(int r, int c) {
  if (isUp(r, c)) {
    return <Neighbour>[
      Neighbour(r, c - 1, _upLeft),
      Neighbour(r, c + 1, _upRight),
      Neighbour(r + 1, c, _upDown),
    ];
  }
  return <Neighbour>[
    Neighbour(r, c - 1, _dnLeft),
    Neighbour(r, c + 1, _dnRight),
    Neighbour(r - 1, c, _dnUp),
  ];
}

bool pointInTriangle(Offset p, List<Offset> v) {
  double cross(Offset a, Offset b, Offset c) =>
      (b.dx - a.dx) * (c.dy - a.dy) - (b.dy - a.dy) * (c.dx - a.dx);
  final double d1 = cross(v[0], v[1], p);
  final double d2 = cross(v[1], v[2], p);
  final double d3 = cross(v[2], v[0], p);
  final bool hasNeg = d1 < 0 || d2 < 0 || d3 < 0;
  final bool hasPos = d1 > 0 || d2 > 0 || d3 > 0;
  return !(hasNeg && hasPos);
}

// ─────────────────────────────────────────────────────────────
// Rules
// ─────────────────────────────────────────────────────────────

bool canPlace(
  Map<String, Placed> board,
  int r,
  int c,
  List<TCorner> corners,
  MatchMode mode,
) {
  if (!inBounds(r, c) || board.containsKey(cellKey(r, c))) return false;
  int touching = 0;
  for (final Neighbour nb in neighbours(r, c)) {
    final Placed? other = board[cellKey(nb.r, nb.c)];
    if (other == null) continue;
    touching++;
    for (final List<int> p in nb.pairs) {
      if (!cornersMatch(corners[p[0]], other.corners[p[1]], mode)) return false;
    }
  }
  return touching > 0;
}

/// The empty cells that touch something already on the table.
///
/// A placement is only ever legal against a tile already down, so this is the
/// complete set of candidates — and it is a few dozen cells rather than the
/// lattice's 231, which is what keeps a hint, a bot turn and the highlight
/// pass cheap enough to run inside a frame.
///
/// Returned in row-major order so results stay identical to a full scan.
List<Point<int>> frontierCells(Map<String, Placed> board) {
  final Set<String> seen = <String>{};
  final List<Point<int>> out = <Point<int>>[];
  for (final String k in board.keys) {
    final Point<int> p = parseCellKey(k);
    for (final Neighbour nb in neighbours(p.x, p.y)) {
      if (!inBounds(nb.r, nb.c)) continue;
      final String key = cellKey(nb.r, nb.c);
      if (board.containsKey(key) || !seen.add(key)) continue;
      out.add(Point<int>(nb.r, nb.c));
    }
  }
  out.sort((Point<int> a, Point<int> b) =>
      a.x != b.x ? a.x.compareTo(b.x) : a.y.compareTo(b.y));
  return out;
}

List<Point<int>> legalCells(
  Map<String, Placed> board,
  List<TCorner> corners,
  MatchMode mode,
) {
  final List<Point<int>> out = <Point<int>>[];
  for (final Point<int> p in frontierCells(board)) {
    if (canPlace(board, p.x, p.y, corners, mode)) out.add(p);
  }
  return out;
}

/// Whether a single tile has anywhere to go, in any of its three turns.
bool tileFits(Map<String, Placed> board, Tile tile, MatchMode mode) {
  final List<Point<int>> frontier = frontierCells(board);
  for (int k = 0; k < 3; k++) {
    final List<TCorner> corners = tile.rotated(k);
    for (final Point<int> p in frontier) {
      if (canPlace(board, p.x, p.y, corners, mode)) return true;
    }
  }
  return false;
}
