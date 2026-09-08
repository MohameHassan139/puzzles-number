// Levels, the pile, and the root the board opens on.

import 'dart:math';

import 'model.dart';
import 'scoring.dart';

// ─────────────────────────────────────────────────────────────
// The root
// ─────────────────────────────────────────────────────────────

/// The board does not open on one random triangle. It opens on a *root*: a
/// small arrangement laid out before anyone plays, sized by the level.
///
/// Neighbouring triangles share lattice vertices, so giving every vertex of the
/// root a corner type and reading each cell's three labels back off produces an
/// arrangement that is legal by construction — nothing to search for.
///
/// Jokers are then dropped into the root. A joker edge fits anything, so each
/// one is a guaranteed opening: that is how an easier level helps the player in.
enum RootShape { wide, small, bare }

class RootPlan {
  final List<Point<int>> cells;
  final int jokers;

  const RootPlan(this.cells, this.jokers);
}

const Map<RootShape, RootPlan> kRoots = <RootShape, RootPlan>{
  RootShape.wide: RootPlan(<Point<int>>[
    Point<int>(5, 9),
    Point<int>(5, 10),
    Point<int>(5, 11),
    Point<int>(6, 9),
    Point<int>(6, 10),
    Point<int>(6, 11),
  ], 2),
  RootShape.small: RootPlan(<Point<int>>[
    Point<int>(5, 9),
    Point<int>(5, 10),
    Point<int>(5, 11),
  ], 1),
  RootShape.bare: RootPlan(<Point<int>>[Point<int>(5, 10)], 0),
};

String rootShapeLabel(RootShape s) {
  switch (s) {
    case RootShape.wide:
      return 'Generous — six triangles, two jokers';
    case RootShape.small:
      return 'Standard — three triangles, one joker';
    case RootShape.bare:
      return 'Bare — a single triangle';
  }
}

// ─────────────────────────────────────────────────────────────
// Levels
// ─────────────────────────────────────────────────────────────

/// One dial. It sets how many triangles are in play, how much of a root you are
/// given to build on, and how thick the pile is with jokers.
enum Level { easy, normal, hard, devil }

class LevelPlan {
  final int minTiles;
  final int maxTiles;
  final RootShape root;
  final double jokerShare;
  final String label;
  final String short;

  const LevelPlan(
      this.minTiles, this.maxTiles, this.root, this.jokerShare, this.label, this.short);
}

const Map<Level, LevelPlan> kLevels = <Level, LevelPlan>{
  Level.easy:
      LevelPlan(20, 40, RootShape.wide, 0.28, 'Easy — 20 to 40 triangles', 'Easy'),
  Level.normal: LevelPlan(40, 60, RootShape.small, 0.20, 'Normal — 40 to 60', 'Normal'),
  Level.hard: LevelPlan(60, 80, RootShape.bare, 0.12, 'Hard — 60 to 80', 'Hard'),
  Level.devil: LevelPlan(80, 100, RootShape.bare, 0.05, 'Devil — 80 to 100', 'Devil'),
};

class DeckPlan {
  final int total;
  final int jokers;
  final int regulars;
  final RootShape root;

  const DeckPlan(this.total, this.jokers, this.regulars, this.root);
}

/// How big this round's pile is, and how much of it is jokers. The count is
/// drawn from the level's range on the seed, so a seed still replays exactly.
/// The floor keeps a small easy deck from being swallowed by the two hands.
DeckPlan deckPlan(Level level, int seed, int handSize) {
  final LevelPlan lv = kLevels[level]!;
  final Random rnd = Random(seed * 7919 + 3);
  final int drawn = lv.minTiles + rnd.nextInt(lv.maxTiles - lv.minTiles + 1);
  final int total = max(drawn, handSize * 2 + 8);
  final int jokers = max(1, (total * lv.jokerShare).round());
  return DeckPlan(total, jokers, total - jokers, lv.root);
}

// ─────────────────────────────────────────────────────────────
// The pile
// ─────────────────────────────────────────────────────────────

/// All five colours and numbers 1–5 exist in the game, but a single round only
/// uses [typeCount] of the 25 possible corner types. With strict matching that
/// is what keeps the game winnable: using all 25 means players draw far more
/// tiles than they can place, so a hand never empties.
List<Tile> makeDeck({
  required int seed,
  required int jokers,
  int regulars = 70,
  int typeCount = 8,
}) {
  final Random rnd = Random(seed);

  final List<TCorner> allTypes = <TCorner>[
    for (int c = 0; c < kColourCount; c++)
      for (int n = 1; n <= 5; n++) TCorner(c, n),
  ]..shuffle(rnd);

  final int wanted = typeCount < 3
      ? 3
      : typeCount > allTypes.length
          ? allTypes.length
          : typeCount;
  final List<TCorner> palette = allTypes.take(wanted).toList();

  final List<Tile> deck = <Tile>[];
  int id = 0;
  for (int i = 0; i < regulars; i++) {
    deck.add(Tile(id++, <TCorner>[
      for (int k = 0; k < 3; k++) palette[rnd.nextInt(palette.length)],
    ]));
  }
  for (int i = 0; i < jokers; i++) {
    deck.add(Tile(id++, kJokerCorners));
  }
  deck.shuffle(rnd);
  return deck;
}

/// The distinct corner types this deck was actually dealt.
List<TCorner> paletteOf(List<Tile> deck) {
  final Map<String, TCorner> seen = <String, TCorner>{};
  for (final Tile t in deck) {
    for (final TCorner c in t.corners) {
      if (!c.isJoker) seen['${c.color}:${c.number}'] = c;
    }
  }
  return seen.values.toList();
}

Map<String, Placed> buildRoot(Random rnd, List<TCorner> palette, RootShape shape) {
  final RootPlan plan = kRoots[shape]!;

  // An all-joker deck would leave nothing to label the root with. It cannot
  // happen with the shipped level table, but the fallback keeps the function
  // total rather than letting it throw on a hand-tuned deck.
  final List<TCorner> pool =
      palette.isEmpty ? const <TCorner>[TCorner(0, 1), TCorner(1, 2)] : palette;

  final Map<String, TCorner> labels = <String, TCorner>{};
  for (final Point<int> cell in plan.cells) {
    for (final String v in vertexIds(cell.x, cell.y)) {
      labels[v] ??= pool[rnd.nextInt(pool.length)];
    }
  }

  final Map<String, Placed> board = <String, Placed>{};
  for (int i = 0; i < plan.cells.length; i++) {
    final Point<int> cell = plan.cells[i];
    final List<TCorner> corners = <TCorner>[
      for (final String v in vertexIds(cell.x, cell.y)) labels[v]!,
    ];
    board[cellKey(cell.x, cell.y)] = Placed(Tile(-1 - i, corners), corners);
  }

  // Scatter the jokers through the root.
  final List<int> order = <int>[for (int i = 0; i < plan.cells.length; i++) i]
    ..shuffle(rnd);
  for (final int i in order.take(plan.jokers)) {
    final Point<int> cell = plan.cells[i];
    board[cellKey(cell.x, cell.y)] = Placed(Tile(-1 - i, kJokerCorners), kJokerCorners);
  }
  return board;
}
