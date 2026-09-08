// PUZZLES NUMERAL — a triangle matching game.
//
// A digital build of the wooden tile game: every triangle carries a coloured,
// numbered wedge in each of its three corners, and a triangle may only be laid
// against one already on the table when the corners they share agree.
//
// Single file, no packages beyond the Flutter SDK.

import 'dart:math';
import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';

void main() => runApp(const PuzzlesNumeralApp());

// ─────────────────────────────────────────────────────────────
// Palette
//
// Colours are written as plain 0xAARRGGBB literals rather than built with
// runtime helpers, so the file compiles on every Flutter 3.x without touching
// APIs that have been renamed along the way (withOpacity / withValues).
// ─────────────────────────────────────────────────────────────
const Color kFelt = Color(0xFF123029);
const Color kFeltDark = Color(0xFF0C211C);
const Color kIvory = Color(0xFFF2EADB);
const Color kInk = Color(0xFF1E1C18);
const Color kBrass = Color(0xFFC69A4E);
const Color kBrassInk = Color(0xFF20180A);

const int _rgbIvory = 0xF2EADB;
const int _rgbBrass = 0xC69A4E;
const int _rgbWhite = 0xFFFFFF;
const int _rgbBlack = 0x000000;

/// An opaque-colour channel plus an alpha, folded into one ARGB value.
///
/// Uses only the `Color(int)` constructor, which has never changed signature.
Color rgba(int rgb, double alpha) {
  final int a = (alpha * 255.0).round();
  final int clamped = a < 0
      ? 0
      : a > 255
          ? 255
          : a;
  return Color((clamped << 24) | (rgb & 0xFFFFFF));
}

Color ivory(double a) => rgba(_rgbIvory, a);
Color brass(double a) => rgba(_rgbBrass, a);
Color white(double a) => rgba(_rgbWhite, a);
Color black(double a) => rgba(_rgbBlack, a);

const List<Color> kColors = <Color>[
  Color(0xFFE14B4B), // red
  Color(0xFF3B82D9), // blue
  Color(0xFF2FA46B), // green
  Color(0xFFE2A32B), // amber
  Color(0xFF9A64D0), // violet
];
const List<String> kColorNames = <String>['Red', 'Blue', 'Green', 'Amber', 'Violet'];

// Board geometry
const int kRows = 11;
const int kCols = 21;
const double kW = 74; // triangle base
const double kH = kW * 0.866; // triangle height

const double kBoardW = kCols * kW / 2 + kW / 2;
const double kBoardH = kRows * kH;

/// Corner wedge radius, as a fraction of the triangle's side. Must stay below
/// 0.5 — at 0.5 the wedges of two corners on the same edge would touch.
const double kWedge = 0.45;

// ─────────────────────────────────────────────────────────────
// Model
// ─────────────────────────────────────────────────────────────

/// One corner of a triangle. [color] and [number] are -1 for a joker corner.
class TCorner {
  final int color;
  final int number;

  const TCorner(this.color, this.number);
  const TCorner.joker()
      : color = -1,
        number = -1;

  bool get isJoker => color < 0;
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
}

class Placed {
  final Tile tile;
  final List<TCorner> corners; // already rotated into place

  const Placed(this.tile, this.corners);
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

class Neighbour {
  final int r;
  final int c;

  /// Pairs of [myCornerIndex, theirCornerIndex] along the shared edge.
  final List<List<int>> pairs;

  const Neighbour(this.r, this.c, this.pairs);
}

List<Neighbour> neighbours(int r, int c) {
  if (isUp(r, c)) {
    return <Neighbour>[
      Neighbour(r, c - 1, const <List<int>>[<int>[0, 2], <int>[2, 0]]),
      Neighbour(r, c + 1, const <List<int>>[<int>[0, 1], <int>[1, 0]]),
      Neighbour(r + 1, c, const <List<int>>[<int>[1, 2], <int>[2, 1]]),
    ];
  }
  return <Neighbour>[
    Neighbour(r, c - 1, const <List<int>>[<int>[1, 0], <int>[0, 1]]),
    Neighbour(r, c + 1, const <List<int>>[<int>[2, 0], <int>[0, 2]]),
    Neighbour(r - 1, c, const <List<int>>[<int>[2, 1], <int>[1, 2]]),
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

List<Point<int>> legalCells(
  Map<String, Placed> board,
  List<TCorner> corners,
  MatchMode mode,
) {
  final List<Point<int>> out = <Point<int>>[];
  for (int r = 0; r < kRows; r++) {
    for (int c = 0; c < kCols; c++) {
      if (canPlace(board, r, c, corners, mode)) out.add(Point<int>(r, c));
    }
  }
  return out;
}

// ─────────────────────────────────────────────────────────────
// Scoring
// ─────────────────────────────────────────────────────────────

/// Six triangles meet at every inner vertex of the lattice. Naming those
/// vertices lets us spot the moment a placement closes one, which is the move
/// the whole look of the board is built around.
List<String> vertexIds(int r, int c) => isUp(r, c)
    ? <String>['${c + 1}.$r', '${c + 2}.${r + 1}', '$c.${r + 1}']
    : <String>['${c + 1}.${r + 1}', '$c.$r', '${c + 2}.$r'];

Offset vertexOffset(String id) {
  final List<String> parts = id.split('.');
  return Offset(int.parse(parts[0]) * kW / 2, int.parse(parts[1]) * kH);
}

Map<String, int> vertexCounts(Map<String, Placed> board) {
  final Map<String, int> counts = <String, int>{};
  for (final String k in board.keys) {
    final List<String> rc = k.split(',');
    for (final String v in vertexIds(int.parse(rc[0]), int.parse(rc[1]))) {
      counts[v] = (counts[v] ?? 0) + 1;
    }
  }
  return counts;
}

/// Points by how many tiles the new one leans against.
const List<int> kTouchPoints = <int>[0, 1, 3, 6];
const int kCircleBonus = 5;

/// Docked per triangle still in hand when the game ends.
const int kLeftoverPenalty = 2;

/// Emptying your hand ends the game, but it does not win it — the score does.
/// Otherwise the points on screen would be decoration while the race decided
/// the result, which makes a game of judgement feel like a game of shuffle.
int finalScore(int score, List<Tile> hand) => score - kLeftoverPenalty * hand.length;

/// -1 for a tie, otherwise the index of the winner.
int settle(List<int> scores, List<List<Tile>> hands) {
  final int a = finalScore(scores[0], hands[0]);
  final int b = finalScore(scores[1], hands[1]);
  return a == b ? -1 : (a > b ? 0 : 1);
}

class Score {
  final int touching;
  final int points;
  final List<String> closed;

  const Score(this.touching, this.points, this.closed);
}

/// What a placement is worth, and which circles it closes.
Score scoreFor(Map<String, Placed> board, int r, int c) {
  int touching = 0;
  for (final Neighbour nb in neighbours(r, c)) {
    if (board.containsKey(cellKey(nb.r, nb.c))) touching++;
  }
  final Map<String, int> before = vertexCounts(board);
  final List<String> closed =
      vertexIds(r, c).where((String v) => (before[v] ?? 0) == 5).toList();
  return Score(touching, kTouchPoints[touching] + closed.length * kCircleBonus, closed);
}

/// The corners a placement matches against its neighbours — flashed after a
/// move so the player can see why it was legal.
List<String> matchedVertices(Map<String, Placed> board, int r, int c) {
  final Set<String> out = <String>{};
  final List<String> mine = vertexIds(r, c);
  for (final Neighbour nb in neighbours(r, c)) {
    if (!board.containsKey(cellKey(nb.r, nb.c))) continue;
    for (final List<int> p in nb.pairs) {
      out.add(mine[p[0]]);
    }
  }
  return out.toList();
}

class Move {
  final int handIndex;
  final int rot;
  final int r;
  final int c;
  final Score score;

  const Move(this.handIndex, this.rot, this.r, this.c, this.score);
}

enum BotLevel { easy, normal, hard }

String botLevelLabel(BotLevel l) {
  switch (l) {
    case BotLevel.easy:
      return 'Easy — plays anywhere';
    case BotLevel.normal:
      return 'Normal — keeps it tight';
    case BotLevel.hard:
      return 'Hard — plays for points';
  }
}

/// Every legal placement, with what each is worth.
List<Move> allMoves(Map<String, Placed> board, List<Tile> hand, MatchMode mode) {
  final List<Move> out = <Move>[];
  for (int h = 0; h < hand.length; h++) {
    for (int k = 0; k < 3; k++) {
      for (final Point<int> p in legalCells(board, hand[h].rotated(k), mode)) {
        out.add(Move(h, k, p.x, p.y, scoreFor(board, p.x, p.y)));
      }
    }
  }
  return out;
}

/// How the opponent picks. Easy wanders, normal tightens the board, hard plays
/// for points and unloads whichever triangle has the fewest other homes.
Move? bestMove(
  Map<String, Placed> board,
  List<Tile> hand,
  MatchMode mode,
  BotLevel level, [
  Random? rnd,
]) {
  final List<Move> moves = allMoves(board, hand, mode);
  if (moves.isEmpty) return null;
  switch (level) {
    case BotLevel.easy:
      return moves[(rnd ?? Random()).nextInt(moves.length)];
    case BotLevel.normal:
      return moves.reduce((Move a, Move b) => b.score.touching > a.score.touching ? b : a);
    case BotLevel.hard:
      final List<int> homes = <int>[
        for (int h = 0; h < hand.length; h++)
          moves.where((Move m) => m.handIndex == h).length,
      ];
      return moves.reduce((Move a, Move b) {
        if (b.score.points != a.score.points) {
          return b.score.points > a.score.points ? b : a;
        }
        return homes[b.handIndex] < homes[a.handIndex] ? b : a;
      });
  }
}

Move? findAnyMove(Map<String, Placed> board, List<Tile> hand, MatchMode mode) {
  for (int h = 0; h < hand.length; h++) {
    for (int k = 0; k < 3; k++) {
      final List<Point<int>> cells = legalCells(board, hand[h].rotated(k), mode);
      if (cells.isNotEmpty) {
        return Move(h, k, cells.first.x, cells.first.y,
            scoreFor(board, cells.first.x, cells.first.y));
      }
    }
  }
  return null;
}

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
/// given to build on, and how thick the pile is with jokers. Fewer triangles and
/// a wide root make a short, forgiving game; a hundred triangles on a bare root
/// is a long one where a bad stretch is hard to recover from.
enum Level { easy, normal, hard, devil }

class LevelPlan {
  final int minTiles;
  final int maxTiles;
  final RootShape root;
  final double jokerShare;
  final String label;

  const LevelPlan(this.minTiles, this.maxTiles, this.root, this.jokerShare, this.label);
}

const Map<Level, LevelPlan> kLevels = <Level, LevelPlan>{
  Level.easy: LevelPlan(20, 40, RootShape.wide, 0.28, 'Easy — 20 to 40 triangles'),
  Level.normal: LevelPlan(40, 60, RootShape.small, 0.20, 'Normal — 40 to 60'),
  Level.hard: LevelPlan(60, 80, RootShape.bare, 0.12, 'Hard — 60 to 80'),
  Level.devil: LevelPlan(80, 100, RootShape.bare, 0.05, 'Devil — 80 to 100'),
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
// Deck
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
    for (int c = 0; c < kColors.length; c++)
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

/// How open a root is: how many placements it offers, and — the part that
/// matters — how many different triangles in hand can answer it. One playable
/// triangle is a forced move, not a choice.
class Openness {
  final int moves;
  final int tiles;

  const Openness(this.moves, this.tiles);
}

Openness openness(Map<String, Placed> board, List<Tile> hand, MatchMode mode) {
  final List<Move> moves = allMoves(board, hand, mode);
  return Openness(moves.length, moves.map((Move m) => m.handIndex).toSet().length);
}

/// Everything a single move changes, kept so it can be taken back.
class Snapshot {
  final Map<String, Placed> board;
  final List<Tile> deck;
  final List<List<Tile>> hands;
  final int turn;
  final int passes;
  final List<int> scores;
  final List<int> circles;
  final Point<int>? last;
  final int? winner;

  const Snapshot(this.board, this.deck, this.hands, this.turn, this.passes,
      this.scores, this.circles, this.last, this.winner);
}

// ─────────────────────────────────────────────────────────────
// App
// ─────────────────────────────────────────────────────────────

class PuzzlesNumeralApp extends StatelessWidget {
  const PuzzlesNumeralApp({super.key});

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = ColorScheme.fromSeed(
      seedColor: kBrass,
      brightness: Brightness.dark,
    ).copyWith(surface: kFelt);

    return MaterialApp(
      title: 'Puzzles Numeral',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        colorScheme: scheme,
        scaffoldBackgroundColor: kFelt,
        sliderTheme: SliderThemeData(
          activeTrackColor: kBrass,
          thumbColor: kBrass,
          inactiveTrackColor: brass(0.24),
        ),
      ),
      home: const GamePage(),
    );
  }
}

class GamePage extends StatefulWidget {
  const GamePage({super.key});

  @override
  State<GamePage> createState() => _GamePageState();
}

class _GamePageState extends State<GamePage> with SingleTickerProviderStateMixin {
  // ── settings ──
  int seed = 7;
  int handSize = 5;
  int typeCount = 8;
  Level level = Level.normal;
  MatchMode mode = MatchMode.colourAndNumber;
  bool vsBot = true;
  BotLevel botLevel = BotLevel.normal;

  // ── state ──
  final Map<String, Placed> board = <String, Placed>{};
  List<Tile> deck = <Tile>[];
  List<List<Tile>> hands = <List<Tile>>[<Tile>[], <Tile>[]];
  int turn = 0;
  int? sel;
  int rot = 0;
  Point<int>? last;
  int? winner;
  int passes = 0;
  String message = '';

  List<int> scores = <int>[0, 0];
  List<int> circles = <int>[0, 0];
  final List<Snapshot> history = <Snapshot>[];
  Point<int>? hint;

  // What to flash after a move: the joins that matched, and any circle closed.
  List<String> flashJoins = <String>[];
  List<String> flashClosed = <String>[];

  final TransformationController _viewer = TransformationController();
  late final AnimationController _flash;
  bool _fitted = false;

  @override
  void initState() {
    super.initState();
    _flash = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    );
    newGame();
  }

  @override
  void dispose() {
    _flash.dispose();
    _viewer.dispose();
    super.dispose();
  }

  // ── setting up a round ────────────────────────────────────

  void newGame() {
    final DeckPlan plan = deckPlan(level, seed, handSize);
    final List<Tile> d = makeDeck(
      seed: seed,
      jokers: plan.jokers,
      regulars: plan.regulars,
      typeCount: typeCount,
    );
    final List<Tile> h0 = d.sublist(0, handSize);
    final List<Tile> h1 = d.sublist(handSize, handSize * 2);
    final List<Tile> rest = d.sublist(handSize * 2);
    final Random rnd = Random(seed * 977 + 13);
    final List<TCorner> palette = paletteOf(d);

    // Lay roots until one gives the opening player a real choice rather than a
    // single forced move. Same seeded stream, so a seed still replays exactly.
    Map<String, Placed> root = <String, Placed>{};
    int bestTiles = -1;
    int bestMoves = -1;
    for (int i = 0; i < 40; i++) {
      final Map<String, Placed> candidate = buildRoot(rnd, palette, plan.root);
      final Openness open = openness(candidate, h0, mode);
      if (open.tiles > bestTiles || (open.tiles == bestTiles && open.moves > bestMoves)) {
        bestTiles = open.tiles;
        bestMoves = open.moves;
        root = candidate;
      }
      if (open.tiles >= 2 && open.moves >= 4) break;
    }

    setState(() {
      board
        ..clear()
        ..addAll(root);
      deck = rest;
      hands = <List<Tile>>[h0, h1];
      turn = 0;
      sel = null;
      rot = 0;
      last = const Point<int>(5, 10);
      winner = null;
      passes = 0;
      scores = <int>[0, 0];
      circles = <int>[0, 0];
      history.clear();
      hint = null;
      flashJoins = <String>[];
      flashClosed = <String>[];
      message = '${kLevels[level]!.label.split(' —').first}: '
          '${plan.total} triangles in play. Root is down — '
          '$bestTiles of yours fit it, $bestMoves ways in all.';
    });
  }

  // ── derived state ─────────────────────────────────────────

  List<Tile> get hand => hands[turn];

  Tile? get selTile {
    final int? s = sel;
    if (s == null || s < 0 || s >= hand.length) return null;
    return hand[s];
  }

  Set<String> get strongCells {
    final Tile? t = selTile;
    if (t == null) return <String>{};
    return legalCells(board, t.rotated(rot), mode)
        .map((Point<int> p) => cellKey(p.x, p.y))
        .toSet();
  }

  Set<String> get weakCells {
    final Tile? t = selTile;
    if (t == null) return <String>{};
    final Set<String> strong = strongCells;
    final Set<String> out = <String>{};
    for (int k = 0; k < 3; k++) {
      if (k == rot) continue;
      for (final Point<int> p in legalCells(board, t.rotated(k), mode)) {
        final String key = cellKey(p.x, p.y);
        if (!strong.contains(key)) out.add(key);
      }
    }
    return out;
  }

  bool get stuck => winner == null && findAnyMove(board, hand, mode) == null;

  // ── moves ─────────────────────────────────────────────────

  void place(int r, int c) {
    final Tile? t = selTile;
    final int? s = sel;
    if (t == null || s == null || winner != null) return;

    int useRot = rot;
    if (!canPlace(board, r, c, t.rotated(useRot), mode)) {
      final List<int> alt = <int>[0, 1, 2]
          .where((int k) => canPlace(board, r, c, t.rotated(k), mode))
          .toList();
      if (alt.isEmpty) return;
      useRot = alt.first;
    }

    final Score sc = scoreFor(board, r, c);
    final List<String> joins = matchedVertices(board, r, c);
    _pushHistory();

    setState(() {
      board[cellKey(r, c)] = Placed(t, t.rotated(useRot));
      hands[turn].removeAt(s);
      last = Point<int>(r, c);
      sel = null;
      rot = 0;
      passes = 0;
      hint = null;
      scores[turn] += sc.points;
      circles[turn] += sc.closed.length;
      flashJoins = joins;
      flashClosed = sc.closed;
      if (hands[turn].isEmpty) {
        winner = settle(scores, hands);
        message = 'You went out — the score settles it.';
        return;
      }
      turn = 1 - turn;
      message = _scoreLine(sc);
    });

    _flash.forward(from: 0);
    _maybeBot();
  }

  String _scoreLine(Score sc) {
    if (sc.closed.length > 1) {
      return '${sc.closed.length} circles closed at once — +${sc.points}.';
    }
    if (sc.closed.length == 1) return 'Circle closed — +${sc.points}.';
    if (sc.touching == 3) return 'Snug in a gap, three sides touching — +${sc.points}.';
    if (sc.touching == 2) return 'Two sides touching — +${sc.points}.';
    return '+${sc.points}.';
  }

  void _pushHistory() {
    history.add(Snapshot(
      Map<String, Placed>.from(board),
      List<Tile>.from(deck),
      <List<Tile>>[List<Tile>.from(hands[0]), List<Tile>.from(hands[1])],
      turn,
      passes,
      List<int>.from(scores),
      List<int>.from(circles),
      last,
      winner,
    ));
    if (history.length > 40) history.removeAt(0);
  }

  void undo() {
    if (history.isEmpty) return;
    final Snapshot p = history.removeLast();
    setState(() {
      board
        ..clear()
        ..addAll(p.board);
      deck = p.deck;
      hands = p.hands;
      turn = p.turn;
      passes = p.passes;
      scores = p.scores;
      circles = p.circles;
      last = p.last;
      winner = p.winner;
      sel = null;
      rot = 0;
      hint = null;
      flashJoins = <String>[];
      flashClosed = <String>[];
      message = 'Took that move back.';
    });
  }

  /// Points at the best move on the table right now.
  void showHint() {
    final Move? mv = bestMove(board, hand, mode, BotLevel.hard);
    setState(() {
      if (mv == null) {
        message = 'Nothing in your hand fits. Drawing is the only move.';
        return;
      }
      sel = mv.handIndex;
      rot = mv.rot;
      hint = Point<int>(mv.r, mv.c);
      message = 'Try the ringed space — worth ${mv.score.points}.';
    });
  }

  /// Drawing is the whole turn: take one triangle from the pile and hand over.
  /// No drawing twice in a row — but if the one drawn fits, play it now.
  void draw() {
    if (winner != null) return;
    if (deck.isNotEmpty) _pushHistory();

    setState(() {
      if (deck.isEmpty) {
        passes++;
        sel = null;
        if (passes >= 2) {
          winner = settle(scores, hands);
          message = 'Pile empty and nothing fits. The score settles it.';
          return;
        }
        message = 'The pile is empty and nothing fits. Turn passes.';
        turn = 1 - turn;
        return;
      }
      hands[turn].add(deck.removeAt(0));
      sel = null;
      rot = 0;
      passes = 0;
      hint = null;
      flashJoins = <String>[];
      flashClosed = <String>[];
      if (findAnyMove(board, hands[turn], mode) != null) {
        message = 'You drew one that fits — play it.';
        return;
      }
      turn = 1 - turn;
      message = 'Drew one triangle, nothing fits. Turn passes.';
    });

    _maybeBot();
  }

  void _maybeBot() {
    if (!vsBot || turn != 1 || winner != null) return;
    Future<void>.delayed(const Duration(milliseconds: 650), () {
      if (!mounted || !vsBot || turn != 1 || winner != null) return;
      final Move? mv = bestMove(board, hands[1], mode, botLevel);
      bool played = false;

      setState(() {
        if (mv != null) {
          final Tile t = hands[1][mv.handIndex];
          flashJoins = matchedVertices(board, mv.r, mv.c);
          flashClosed = mv.score.closed;
          board[cellKey(mv.r, mv.c)] = Placed(t, t.rotated(mv.rot));
          hands[1].removeAt(mv.handIndex);
          last = Point<int>(mv.r, mv.c);
          scores[1] += mv.score.points;
          circles[1] += mv.score.closed.length;
          passes = 0;
          played = true;
          if (hands[1].isEmpty) {
            winner = settle(scores, hands);
            message = 'The bot went out — the score settles it.';
          } else {
            turn = 0;
            message = mv.score.closed.isNotEmpty
                ? 'Bot closed a circle for ${mv.score.points}. Your turn.'
                : 'Bot scored ${mv.score.points}. Your turn.';
          }
        } else if (deck.isNotEmpty) {
          hands[1].add(deck.removeAt(0));
          passes = 0;
          if (findAnyMove(board, hands[1], mode) != null) {
            message = 'Bot drew one that fits…';
          } else {
            turn = 0;
            message = 'Bot had no match, drew one and passed. Your turn.';
          }
        } else {
          passes++;
          if (passes >= 2) {
            winner = settle(scores, hands);
            message = 'Pile empty and nothing fits. The score settles it.';
          } else {
            turn = 0;
            message = 'Bot passed. Your turn.';
          }
        }
      });

      if (played) _flash.forward(from: 0);
      _maybeBot();
    });
  }

  // ── UI ────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final bool botThinking = vsBot && turn == 1 && winner == null;

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment.topCenter,
            radius: 1.2,
            colors: <Color>[kFelt, kFeltDark],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: <Widget>[
              _header(),
              _statusStrip(),
              Expanded(child: _boardView()),
              _messageLine(),
              _rack(botThinking),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header() => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
        child: Row(
          children: <Widget>[
            const Flexible(
              child: Text(
                'Puzzles Numeral',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: kIvory,
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.4,
                ),
              ),
            ),
            const Spacer(),
            IconButton(
              onPressed: _openSettings,
              icon: const Icon(Icons.tune, color: kBrass),
              tooltip: 'Rules and settings',
            ),
            TextButton(
              onPressed: newGame,
              style: TextButton.styleFrom(
                backgroundColor: kBrass,
                foregroundColor: kBrassInk,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: const Text('New game'),
            ),
          ],
        ),
      );

  Widget _statusStrip() => Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: Row(
          children: <Widget>[
            Flexible(child: _playerChip('You', hands[0].length, scores[0], turn == 0)),
            const SizedBox(width: 14),
            Flexible(
              child: _playerChip(
                  vsBot ? 'Bot' : 'Player 2', hands[1].length, scores[1], turn == 1),
            ),
            const SizedBox(width: 10),
            Text('Pile · ${deck.length}',
                style: TextStyle(color: ivory(0.5), fontSize: 13)),
          ],
        ),
      );

  Widget _playerChip(String name, int count, int score, bool active) => Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(
            width: 9,
            height: 9,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: active ? kBrass : ivory(0.3),
            ),
          ),
          const SizedBox(width: 7),
          Flexible(
            child: Text(
              '$name · $score pts · $count left',
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: ivory(active ? 1 : 0.5), fontSize: 13),
            ),
          ),
        ],
      );

  /// Sets the initial pan and zoom so the whole lattice is visible at once,
  /// rather than opening on the top-left corner of an 814×705 board.
  void _fitBoard(Size view) {
    if (view.width <= 0 || view.height <= 0) return;
    final double s = min(view.width / kBoardW, view.height / kBoardH) * 0.96;
    final double dx = (view.width - kBoardW * s) / 2;
    final double dy = (view.height - kBoardH * s) / 2;
    final Matrix4 m = Matrix4.identity();
    m.setEntry(0, 0, s);
    m.setEntry(1, 1, s);
    m.setEntry(0, 3, dx);
    m.setEntry(1, 3, dy);
    _viewer.value = m;
  }

  Widget _boardView() {
    final Set<String> strong = strongCells;
    final Set<String> weak = weakCells;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: black(0.22),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: white(0.07)),
      ),
      clipBehavior: Clip.antiAlias,
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints cons) {
          if (!_fitted && cons.hasBoundedWidth && cons.hasBoundedHeight) {
            _fitted = true;
            final Size view = cons.biggest;
            WidgetsBinding.instance.addPostFrameCallback((Duration _) {
              if (mounted) _fitBoard(view);
            });
          }
          return InteractiveViewer(
            transformationController: _viewer,
            constrained: false,
            minScale: 0.15,
            maxScale: 3.0,
            boundaryMargin: const EdgeInsets.all(600),
            child: SizedBox(
              width: kBoardW,
              height: kBoardH,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapUp: (TapUpDetails d) =>
                    _handleBoardTap(d.localPosition, strong, weak),
                child: AnimatedBuilder(
                  animation: _flash,
                  builder: (BuildContext _, Widget? __) => CustomPaint(
                    painter: BoardPainter(
                      board: board,
                      strong: strong,
                      weak: weak,
                      last: last,
                      hint: hint,
                      joins: flashJoins,
                      closed: flashClosed,
                      t: _flash.value,
                    ),
                    size: const Size(kBoardW, kBoardH),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  void _handleBoardTap(Offset p, Set<String> strong, Set<String> weak) {
    for (int r = 0; r < kRows; r++) {
      for (int c = 0; c < kCols; c++) {
        final String key = cellKey(r, c);
        if (!strong.contains(key) && !weak.contains(key)) continue;
        if (pointInTriangle(p, cellVerts(r, c))) {
          place(r, c);
          return;
        }
      }
    }
  }

  Widget _messageLine() => Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
        child: SizedBox(
          height: 20,
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              winner == null
                  ? message
                  : '${winner == -1 ? "Tied." : winner == 0 ? "You win." : "You lose."} $message',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: winner == null ? ivory(0.7) : kBrass,
                fontSize: 13,
              ),
            ),
          ),
        ),
      );

  Widget _rack(bool botThinking) {
    final bool locked = botThinking || winner != null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      child: Container(
        height: 156,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: <Color>[Color(0xFF3B2A1B), Color(0xFF2A1E13)],
          ),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: brass(0.25)),
        ),
        child: locked ? _lockedRack() : _liveRack(),
      ),
    );
  }

  Widget _lockedRack() {
    if (winner == null) {
      return Center(
        child: Text('Bot is thinking…',
            style: TextStyle(color: ivory(0.55), fontSize: 13)),
      );
    }
    final String headline = winner == -1
        ? 'Tied game'
        : winner == 0
            ? 'You win'
            : vsBot
                ? 'Bot wins'
                : 'Player 2 wins';
    return Center(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(headline,
                style: const TextStyle(
                    color: kBrass, fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Text(
              'You — ${finalScore(scores[0], hands[0])} '
              '(${scores[0]} scored, ${hands[0].length} left, ${circles[0]} circles)\n'
              '${vsBot ? "Bot" : "Player 2"} — ${finalScore(scores[1], hands[1])} '
              '(${scores[1]} scored, ${hands[1].length} left, ${circles[1]} circles)',
              textAlign: TextAlign.center,
              style: TextStyle(color: ivory(0.75), fontSize: 12),
            ),
            const SizedBox(height: 4),
            Text('${board.length} triangles on the table',
                style: TextStyle(color: ivory(0.45), fontSize: 11)),
            const SizedBox(height: 6),
            TextButton(
              onPressed: newGame,
              style: TextButton.styleFrom(
                  backgroundColor: kBrass, foregroundColor: kBrassInk),
              child: const Text('Play again'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _liveRack() => Row(
        children: <Widget>[
          Expanded(
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: hand.length,
              separatorBuilder: (BuildContext _, int __) => const SizedBox(width: 6),
              itemBuilder: (BuildContext _, int i) => _rackTile(i),
            ),
          ),
          const SizedBox(width: 8),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              OutlinedButton(
                onPressed: sel == null ? null : () => setState(() => rot = (rot + 1) % 3),
                style: OutlinedButton.styleFrom(
                  foregroundColor: kBrass,
                  side: BorderSide(color: brass(0.45)),
                  visualDensity: VisualDensity.compact,
                ),
                child: const Text('Rotate'),
              ),
              const SizedBox(height: 6),
              TextButton(
                onPressed: draw,
                style: TextButton.styleFrom(
                  backgroundColor: stuck ? kBrass : Colors.transparent,
                  foregroundColor: stuck ? kBrassInk : ivory(0.5),
                  visualDensity: VisualDensity.compact,
                ),
                child: Text(stuck ? 'No match — draw' : 'Draw & pass'),
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  TextButton(
                    onPressed: showHint,
                    style: TextButton.styleFrom(
                      foregroundColor: ivory(0.6),
                      visualDensity: VisualDensity.compact,
                    ),
                    child: const Text('Hint'),
                  ),
                  TextButton(
                    onPressed: history.isEmpty ? null : undo,
                    style: TextButton.styleFrom(
                      foregroundColor: ivory(0.6),
                      visualDensity: VisualDensity.compact,
                    ),
                    child: const Text('Undo'),
                  ),
                ],
              ),
            ],
          ),
        ],
      );

  Widget _rackTile(int i) {
    final bool selected = sel == i;
    return GestureDetector(
      onTap: () => setState(() {
        if (selected) {
          rot = (rot + 1) % 3;
        } else {
          sel = i;
          rot = 0;
        }
      }),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        transform: Matrix4.translationValues(0, selected ? -6 : 0, 0),
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: selected ? brass(0.2) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: selected ? kBrass : Colors.transparent, width: 1.5),
        ),
        child: CustomPaint(
          size: const Size(92, 82),
          painter: TilePainter(hand[i].rotated(selected ? rot : 0)),
        ),
      ),
    );
  }

  // ── rules and settings ────────────────────────────────────

  void _openSettings() {
    // The sheet edits its own copies, and only writes them back when a new
    // game actually starts. That keeps a half-changed setting from applying to
    // a round already in progress.
    int nSeed = seed;
    int nHand = handSize;
    int nTypes = typeCount;
    Level nLevel = level;
    MatchMode nMode = mode;
    bool nVsBot = vsBot;
    BotLevel nBot = botLevel;

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: kFeltDark,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (BuildContext sheetCtx) => StatefulBuilder(
        builder: (BuildContext ctx, StateSetter setSheet) {
          final DeckPlan preview = deckPlan(nLevel, nSeed, nHand);
          return Padding(
            padding: EdgeInsets.fromLTRB(
                20, 20, 20, MediaQuery.of(ctx).viewInsets.bottom + 24),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Text('How it plays',
                      style: TextStyle(
                          color: kIvory, fontSize: 18, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  Text(
                    'Every triangle carries a colour and a number in each corner. '
                    'The board opens on a root laid out before play — bigger on an '
                    'easier level, and seeded with jokers to give you a way in. Each '
                    'player holds $nHand triangles.\n\n'
                    'Add a triangle so it touches one already down. Where two '
                    'triangles meet they share two corners, and BOTH pairs must '
                    'match. A joker carries all five colours and fits anything.\n\n'
                    'No match anywhere in your hand? Draw one triangle — never twice '
                    'in a row — but if the one you drew fits, play it straight away '
                    'rather than losing the turn.\n\n'
                    'Going out — placing your last triangle — ends the game, but it '
                    'does not win it: the higher score does, minus $kLeftoverPenalty '
                    'for every triangle still in your hand. So go out when you are '
                    'ahead, and keep scoring while you are behind.\n\n'
                    'Scoring rewards tucking triangles in rather than trailing across '
                    'the table. Leaning on one triangle is 1 point, two is 3, three is '
                    '6. Six triangles meet at every inner vertex, so closing one of '
                    'those circles is worth $kCircleBonus more, and one triangle can '
                    'close two at once.\n\n'
                    'All five colours and numbers 1–5 exist, but one round only deals '
                    '$nTypes of the 25 possible corner types. That is what makes an '
                    'exact colour-and-number match findable — raise it past about 10 '
                    'and hands grow faster than they empty.',
                    style: TextStyle(color: ivory(0.7), fontSize: 13, height: 1.5),
                  ),
                  Divider(height: 32, color: white(0.15)),
                  _dropdown<MatchMode>(
                    label: 'Matching rule',
                    value: nMode,
                    items: MatchMode.values,
                    labelOf: matchModeLabel,
                    onChanged: (MatchMode v) => setSheet(() => nMode = v),
                  ),
                  const SizedBox(height: 12),
                  _slider('Hand size', nHand.toDouble(), 3, 9,
                      (double v) => setSheet(() => nHand = v.round())),
                  _slider('Corner types per round', nTypes.toDouble(), 3, 25,
                      (double v) => setSheet(() => nTypes = v.round())),
                  _slider('Shuffle seed', nSeed.toDouble(), 1, 99,
                      (double v) => setSheet(() => nSeed = v.round())),
                  const SizedBox(height: 4),
                  _dropdown<Level>(
                    label: 'Level',
                    value: nLevel,
                    items: Level.values,
                    labelOf: (Level l) => kLevels[l]!.label,
                    onChanged: (Level v) => setSheet(() => nLevel = v),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'This round: ${preview.total} triangles, ${preview.jokers} of them '
                    'jokers, ${rootShapeLabel(preview.root).split(' —').first.toLowerCase()} root',
                    style: TextStyle(color: ivory(0.6), fontSize: 13),
                  ),
                  const SizedBox(height: 12),
                  _dropdown<BotLevel>(
                    label: 'Bot skill',
                    value: nBot,
                    items: BotLevel.values,
                    labelOf: botLevelLabel,
                    onChanged: (BotLevel v) => setSheet(() => nBot = v),
                  ),
                  const SizedBox(height: 12),
                  _toggleRow(
                    'Play against the bot',
                    nVsBot,
                    (bool v) => setSheet(() => nVsBot = v),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                          backgroundColor: kBrass, foregroundColor: kBrassInk),
                      onPressed: () {
                        Navigator.of(ctx).pop();
                        setState(() {
                          seed = nSeed;
                          handSize = nHand;
                          typeCount = nTypes;
                          level = nLevel;
                          mode = nMode;
                          vsBot = nVsBot;
                          botLevel = nBot;
                        });
                        newGame();
                      },
                      child: const Text('Start a new game'),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text('Settings apply when a new game starts.',
                      style: TextStyle(color: ivory(0.4), fontSize: 12)),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _dropdown<T>({
    required String label,
    required T value,
    required List<T> items,
    required String Function(T) labelOf,
    required ValueChanged<T> onChanged,
  }) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(label, style: TextStyle(color: ivory(0.6), fontSize: 13)),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: kFelt,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: white(0.15)),
            ),
            child: DropdownButton<T>(
              value: value,
              isExpanded: true,
              underline: const SizedBox.shrink(),
              dropdownColor: kFeltDark,
              iconEnabledColor: kBrass,
              style: const TextStyle(color: kIvory, fontSize: 14),
              items: items
                  .map((T m) => DropdownMenuItem<T>(
                        value: m,
                        child: Text(labelOf(m),
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: kIvory, fontSize: 14)),
                      ))
                  .toList(),
              onChanged: (T? v) {
                if (v != null) onChanged(v);
              },
            ),
          ),
        ],
      );

  /// A hand-rolled switch. The Material one has renamed its colour parameters
  /// more than once, and this keeps the file building on any Flutter 3.x.
  Widget _toggleRow(String label, bool value, ValueChanged<bool> onChanged) =>
      InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => onChanged(!value),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Text(label,
                    style: const TextStyle(color: kIvory, fontSize: 14)),
              ),
              AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                width: 46,
                height: 26,
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: value ? kBrass : white(0.16),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Align(
                  alignment: value ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    width: 20,
                    height: 20,
                    decoration: const BoxDecoration(
                      color: kIvory,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );

  Widget _slider(
    String label,
    double value,
    double min,
    double max,
    ValueChanged<double> onChanged,
  ) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('$label — ${value.round()}',
              style: TextStyle(color: ivory(0.6), fontSize: 13)),
          Slider(
            value: value.clamp(min, max).toDouble(),
            min: min,
            max: max,
            divisions: (max - min).round(),
            activeColor: kBrass,
            onChanged: onChanged,
          ),
        ],
      );
}

// ─────────────────────────────────────────────────────────────
// Painters
// ─────────────────────────────────────────────────────────────

/// Draws corner [i] of the triangle with vertices [v] as a pie slice pinned to
/// the vertex itself, spanning the triangle's interior angle there — 60°, i.e.
/// one sixth of a circle. Six triangles meet at every vertex of the grid, so
/// their six wedges close into one whole circle; the tile outlines become the
/// spokes. A matched vertex therefore reads as a single solid disc.
///
/// [r] is the wedge radius and must stay under half the triangle's side, or
/// neighbouring corners of the same tile would run into each other.
void paintCornerWedge(
  Canvas canvas,
  List<Offset> v,
  int i,
  TCorner corner,
  double r,
) {
  final Offset o = v[i];
  final Offset toNext = v[(i + 1) % 3] - o;
  final Offset toPrev = v[(i + 2) % 3] - o;

  // Sweep from one edge to the other, taking the short way round so the wedge
  // lands inside the triangle whichever way the tile points.
  final double start = atan2(toNext.dy, toNext.dx);
  double sweep = atan2(toPrev.dy, toPrev.dx) - start;
  while (sweep <= -pi) {
    sweep += 2 * pi;
  }
  while (sweep > pi) {
    sweep -= 2 * pi;
  }

  final Rect rect = Rect.fromCircle(center: o, radius: r);

  if (corner.isJoker) {
    // All five colours stacked outward from the vertex, one band per colour.
    // Painted largest first so each smaller disc lands on top of the last.
    final int n = kColors.length;
    for (int k = n - 1; k >= 0; k--) {
      canvas.drawArc(
        Rect.fromCircle(center: o, radius: r * (k + 1) / n),
        start,
        sweep,
        true,
        Paint()..color = kColors[k],
      );
    }
  } else {
    canvas.drawArc(rect, start, sweep, true, Paint()..color = kColors[corner.color]);
  }

  canvas.drawArc(
    rect,
    start,
    sweep,
    true,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = r * 0.06
      ..strokeJoin = StrokeJoin.round
      ..color = black(0.3),
  );

  if (corner.isJoker) return;

  // The number sits on the bisector, far enough out to have room across the
  // wedge.
  final double mid = start + sweep / 2;
  final Offset p = o + Offset(cos(mid), sin(mid)) * (r * 0.6);
  final TextPainter tp = TextPainter(
    text: TextSpan(
      text: '${corner.number}',
      style: TextStyle(
        color: const Color(0xFFFFFFFF),
        fontSize: r * 0.5,
        fontWeight: FontWeight.w700,
        fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  tp.paint(canvas, p - Offset(tp.width / 2, tp.height / 2));
}

Path trianglePath(List<Offset> v) => Path()
  ..moveTo(v[0].dx, v[0].dy)
  ..lineTo(v[1].dx, v[1].dy)
  ..lineTo(v[2].dx, v[2].dy)
  ..close();

class BoardPainter extends CustomPainter {
  final Map<String, Placed> board;
  final Set<String> strong;
  final Set<String> weak;
  final Point<int>? last;
  final Point<int>? hint;
  final List<String> joins;
  final List<String> closed;
  final double t; // 0 → 1 over the life of the flash

  BoardPainter({
    required this.board,
    required this.strong,
    required this.weak,
    this.last,
    this.hint,
    this.joins = const <String>[],
    this.closed = const <String>[],
    this.t = 1,
  });

  @override
  void paint(Canvas canvas, Size size) {
    for (int r = 0; r < kRows; r++) {
      for (int c = 0; c < kCols; c++) {
        final String key = cellKey(r, c);
        final List<Offset> v = cellVerts(r, c);
        final Path path = trianglePath(v);
        final Placed? placed = board[key];

        if (placed != null) {
          final Point<int>? l = last;
          final bool isLast = l != null && l.x == r && l.y == c;
          canvas.drawPath(path, Paint()..color = kIvory);
          canvas.drawPath(
            path,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = isLast ? 3.5 : 2
              ..strokeJoin = StrokeJoin.round
              ..color = isLast ? kBrass : kInk,
          );
          for (int i = 0; i < 3; i++) {
            paintCornerWedge(canvas, v, i, placed.corners[i], kW * kWedge);
          }
        } else {
          final bool isStrong = strong.contains(key);
          final bool isWeak = weak.contains(key);
          canvas.drawPath(
            path,
            Paint()
              ..color = isStrong
                  ? brass(0.34)
                  : isWeak
                      ? brass(0.13)
                      : white(0.028),
          );
          canvas.drawPath(
            path,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = isStrong ? 2.5 : 1
              ..color = isStrong
                  ? kBrass
                  : isWeak
                      ? brass(0.5)
                      : white(0.07),
          );
        }
      }
    }
    _paintFeedback(canvas);
  }

  /// Rings the joins that matched, pops any circle that just closed, and marks
  /// the hinted space. All driven by [t] so it fades out on its own.
  void _paintFeedback(Canvas canvas) {
    if (t < 1) {
      final double fade = (1 - t).clamp(0.0, 1.0).toDouble();
      for (final String v in joins) {
        canvas.drawCircle(
          vertexOffset(v),
          kW * kWedge * 0.55,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..color = white(0.9 * fade),
        );
      }
      // A closed circle swells, then settles.
      final double grow =
          t < 0.35 ? 0.4 + (t / 0.35) * 0.85 : 1.25 - ((t - 0.35) / 0.65) * 0.25;
      for (final String v in closed) {
        canvas.drawCircle(
          vertexOffset(v),
          kW * kWedge * grow,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 4
            ..color = brass(fade),
        );
      }
    }

    final Point<int>? h = hint;
    if (h != null) {
      final List<Offset> v = cellVerts(h.x, h.y);
      final Offset centre = Offset(
        (v[0].dx + v[1].dx + v[2].dx) / 3,
        (v[0].dy + v[1].dy + v[2].dy) / 3,
      );
      canvas.drawCircle(
        centre,
        kW * 0.42,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..color = brass(0.85),
      );
    }
  }

  @override
  bool shouldRepaint(covariant BoardPainter old) =>
      old.board.length != board.length ||
      old.strong.length != strong.length ||
      old.weak.length != weak.length ||
      old.last != last ||
      old.hint != hint ||
      old.t != t ||
      old.joins != joins ||
      old.closed != closed;
}

/// Draws a single upward triangle filling the given size — used by the rack.
class TilePainter extends CustomPainter {
  final List<TCorner> corners;

  TilePainter(this.corners);

  @override
  void paint(Canvas canvas, Size size) {
    final double w = size.width;
    final double h = w * 0.866;
    final double top = (size.height - h) / 2;
    final List<Offset> v = <Offset>[
      Offset(w / 2, top),
      Offset(w - 2, top + h),
      Offset(2, top + h),
    ];
    final Path path = trianglePath(v);
    canvas.drawPath(path, Paint()..color = kIvory);
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeJoin = StrokeJoin.round
        ..color = kInk,
    );
    for (int i = 0; i < 3; i++) {
      paintCornerWedge(canvas, v, i, corners[i], w * kWedge);
    }
  }

  @override
  bool shouldRepaint(covariant TilePainter old) => true;
}
