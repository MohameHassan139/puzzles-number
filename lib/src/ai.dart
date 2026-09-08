// Move generation, the opponent, and the draw.

import 'dart:math';

import 'model.dart';
import 'scoring.dart';

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
      return 'Hard — thinks a move ahead';
  }
}

String botLevelShort(BotLevel l) {
  switch (l) {
    case BotLevel.easy:
      return 'Easy';
    case BotLevel.normal:
      return 'Normal';
    case BotLevel.hard:
      return 'Sharp';
  }
}

/// Every legal placement, with what each is worth.
List<Move> allMoves(Map<String, Placed> board, List<Tile> hand, MatchMode mode) {
  final List<Point<int>> frontier = frontierCells(board);
  final Map<String, int> counts = vertexCounts(board);
  final List<Move> out = <Move>[];
  for (int h = 0; h < hand.length; h++) {
    for (int k = 0; k < 3; k++) {
      final List<TCorner> corners = hand[h].rotated(k);
      for (final Point<int> p in frontier) {
        if (canPlace(board, p.x, p.y, corners, mode)) {
          out.add(Move(h, k, p.x, p.y, scoreFor(board, p.x, p.y, counts)));
        }
      }
    }
  }
  return out;
}

Move? findAnyMove(Map<String, Placed> board, List<Tile> hand, MatchMode mode) {
  final List<Point<int>> frontier = frontierCells(board);
  for (int h = 0; h < hand.length; h++) {
    for (int k = 0; k < 3; k++) {
      final List<TCorner> corners = hand[h].rotated(k);
      for (final Point<int> p in frontier) {
        if (canPlace(board, p.x, p.y, corners, mode)) {
          return Move(h, k, p.x, p.y, scoreFor(board, p.x, p.y));
        }
      }
    }
  }
  return null;
}

// ─────────────────────────────────────────────────────────────
// How the opponent thinks
// ─────────────────────────────────────────────────────────────

/// Weights for the sharp bot. Tuned so that taking a circle still beats almost
/// everything, but handing one over is the thing it most wants to avoid.
const double _wPoints = 100.0;
const double _wGift = 58.0; // per vertex left sitting on five
const double _wOpen = 1.4; // per open space handed to the opponent
const double _wHomes = 3.0; // per other place the tile it played could have gone
const double _wJoker = 30.0; // for spending a joker on a cheap move

/// What a move is worth to the sharp bot, once it has looked at the position it
/// leaves behind.
///
/// It never peeks at your hand — that would be cheating and it would feel like
/// it. It reads the *board* instead: a vertex left on five is a free five
/// points for whoever moves next, and a board with fewer open spaces is a board
/// with fewer answers in it. Between two moves worth the same, it spends the
/// triangle that had the fewest other homes and keeps its jokers back.
double moveValue(
  Map<String, Placed> board,
  List<Tile> hand,
  Move mv,
  MatchMode mode,
  List<int> homes,
) {
  final Tile tile = hand[mv.handIndex];
  final Map<String, Placed> after = Map<String, Placed>.from(board);
  after[cellKey(mv.r, mv.c)] = Placed(tile, tile.rotated(mv.rot));

  // Vertices this move leaves one triangle short of a circle: whoever plays
  // next can close them for the bonus.
  final Map<String, int> countsAfter = vertexCounts(after);
  int gifts = 0;
  for (final String v in vertexIds(mv.r, mv.c)) {
    if (countsAfter[v] == 5) gifts++;
  }

  final int openAfter = frontierCells(after).length;

  double value = _wPoints * mv.score.points -
      _wGift * gifts -
      _wOpen * openAfter -
      _wHomes * homes[mv.handIndex];

  if (tile.isJoker && mv.score.points < kCircleBonus) value -= _wJoker;

  return value;
}

/// How the opponent picks. Easy wanders, normal tightens the board, and the
/// sharp one weighs what it leaves behind.
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

      // Only the plausible moves get the expensive read. Anything more than a
      // couple of points off the best raw score cannot come back from it.
      final int topPoints =
          moves.map((Move m) => m.score.points).reduce((int a, int b) => a > b ? a : b);
      final List<Move> shortlist =
          moves.where((Move m) => m.score.points >= topPoints - 3).toList();
      final List<Move> considered = shortlist.length > 40
          ? shortlist.sublist(0, 40)
          : (shortlist.isEmpty ? moves : shortlist);

      Move best = considered.first;
      double bestValue = moveValue(board, hand, best, mode, homes);
      for (int i = 1; i < considered.length; i++) {
        final double v = moveValue(board, hand, considered[i], mode, homes);
        if (v > bestValue) {
          bestValue = v;
          best = considered[i];
        }
      }
      return best;
  }
}

// ─────────────────────────────────────────────────────────────
// The draw
// ─────────────────────────────────────────────────────────────

/// One triangle taken from the pile, and how it came.
class Draw {
  final Tile tile;

  /// The pile was searched past the top card to find one that fits.
  final bool rescued;

  /// Nothing in the pile fitted, so the tile arrived with joker corners.
  final bool jokerised;

  const Draw(this.tile, this.rescued, this.jokerised);
}

/// Take one triangle from [deck], removing it.
///
/// With [rescue] on — the game's normal setting — a player who has nothing to
/// play never draws a dud. The pile is searched for a triangle that has a legal
/// home and that is the one handed over; if the whole pile is dead, the top
/// triangle arrives with joker corners instead, which fits anywhere.
///
/// This runs for the player and for the bot through the same call, so neither
/// side is being helped more than the other, and nothing about it shows on
/// screen: it reads as a lucky draw, because that is exactly what it is.
Draw drawTile(
  List<Tile> deck,
  Map<String, Placed> board,
  MatchMode mode, {
  bool rescue = true,
}) {
  if (deck.isEmpty) {
    throw StateError('drawTile called on an empty pile — check deck.isNotEmpty first');
  }
  if (!rescue) return Draw(deck.removeAt(0), false, false);

  final List<Point<int>> frontier = frontierCells(board);

  bool fits(Tile t) {
    for (int k = 0; k < 3; k++) {
      final List<TCorner> corners = t.rotated(k);
      for (final Point<int> p in frontier) {
        if (canPlace(board, p.x, p.y, corners, mode)) return true;
      }
    }
    return false;
  }

  if (fits(deck.first)) return Draw(deck.removeAt(0), false, false);

  for (int i = 1; i < deck.length; i++) {
    if (fits(deck[i])) return Draw(deck.removeAt(i), true, false);
  }

  // The whole pile is dead against this board. Rather than let the game stall,
  // the triangle comes up a joker.
  return Draw(deck.removeAt(0).asJoker(), true, true);
}

// ─────────────────────────────────────────────────────────────
// Openness, and taking a move back
// ─────────────────────────────────────────────────────────────

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
  final List<int> streaks;

  const Snapshot(this.board, this.deck, this.hands, this.turn, this.passes,
      this.scores, this.circles, this.last, this.winner, this.streaks);
}
