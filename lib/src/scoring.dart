// Scoring. Six triangles meet at every inner vertex of the lattice; naming
// those vertices is what lets the game spot the moment a placement closes one,
// which is the move the whole look of the board is built around.

import 'dart:math';
import 'dart:ui' show Offset;

import 'model.dart';

/// The three lattice vertices a cell's corners sit on, in corner order.
List<String> vertexIds(int r, int c) => isUp(r, c)
    ? <String>['${c + 1}.$r', '${c + 2}.${r + 1}', '$c.${r + 1}']
    : <String>['${c + 1}.${r + 1}', '$c.$r', '${c + 2}.$r'];

Offset vertexOffset(String id) {
  final int dot = id.indexOf('.');
  return Offset(
    int.parse(id.substring(0, dot)) * kW / 2,
    int.parse(id.substring(dot + 1)) * kH,
  );
}

Map<String, int> vertexCounts(Map<String, Placed> board) {
  final Map<String, int> counts = <String, int>{};
  for (final String k in board.keys) {
    final Point<int> p = parseCellKey(k);
    for (final String v in vertexIds(p.x, p.y)) {
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
///
/// Pass [counts] — a vertex tally taken once for the whole board — when scoring
/// many candidate moves in a row; recomputing it per move is what used to make
/// a bot turn walk the whole board dozens of times over.
Score scoreFor(
  Map<String, Placed> board,
  int r,
  int c, [
  Map<String, int>? counts,
]) {
  int touching = 0;
  for (final Neighbour nb in neighbours(r, c)) {
    if (board.containsKey(cellKey(nb.r, nb.c))) touching++;
  }
  final Map<String, int> before = counts ?? vertexCounts(board);
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
