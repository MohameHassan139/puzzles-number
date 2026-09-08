// Rules-engine tests. These cover the parts of the game that a person cannot
// eyeball: that a placement is only ever legal when both shared corner pairs
// agree, that scoring counts what it claims to, and that a full game between
// two bots always terminates without an illegal move.

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:puzzles_numeral/main.dart';

/// Every cell of the lattice whose three corners include [vertex].
List<Point<int>> cellsAtVertex(String vertex) {
  final List<Point<int>> out = <Point<int>>[];
  for (int r = 0; r < kRows; r++) {
    for (int c = 0; c < kCols; c++) {
      if (vertexIds(r, c).contains(vertex)) out.add(Point<int>(r, c));
    }
  }
  return out;
}

Placed jokerAt() => const Placed(Tile(-99, kJokerCorners), kJokerCorners);

void main() {
  group('corner matching', () {
    const TCorner red3 = TCorner(0, 3);
    const TCorner red4 = TCorner(0, 4);
    const TCorner blue3 = TCorner(1, 3);

    test('a joker fits anything, in every mode', () {
      for (final MatchMode m in MatchMode.values) {
        expect(cornersMatch(kJoker, red3, m), isTrue);
        expect(cornersMatch(blue3, kJoker, m), isTrue);
      }
    });

    test('colour and number is the strictest rule', () {
      expect(cornersMatch(red3, red3, MatchMode.colourAndNumber), isTrue);
      expect(cornersMatch(red3, red4, MatchMode.colourAndNumber), isFalse);
      expect(cornersMatch(red3, blue3, MatchMode.colourAndNumber), isFalse);
    });

    test('the looser rules accept a half match', () {
      expect(cornersMatch(red3, red4, MatchMode.colourOrNumber), isTrue);
      expect(cornersMatch(red3, blue3, MatchMode.colourOrNumber), isTrue);
      expect(cornersMatch(red3, red4, MatchMode.colourOnly), isTrue);
      expect(cornersMatch(red3, red4, MatchMode.numberOnly), isFalse);
      expect(cornersMatch(red3, blue3, MatchMode.numberOnly), isTrue);
    });
  });

  group('geometry', () {
    test('up and down triangles alternate along a row', () {
      expect(isUp(0, 0), isTrue);
      expect(isUp(0, 1), isFalse);
      expect(isUp(1, 0), isFalse);
    });

    test('neighbours are mutual, and name the same shared corners', () {
      for (int r = 1; r < kRows - 1; r++) {
        for (int c = 1; c < kCols - 1; c++) {
          for (final Neighbour nb in neighbours(r, c)) {
            final Iterable<Neighbour> back = neighbours(nb.r, nb.c)
                .where((Neighbour n) => n.r == r && n.c == c);
            expect(back.length, 1,
                reason: '($r,$c) and (${nb.r},${nb.c}) must be mutual neighbours');
            for (final List<int> p in nb.pairs) {
              expect(vertexIds(r, c)[p[0]], vertexIds(nb.r, nb.c)[p[1]],
                  reason: 'a shared edge must name the same lattice vertex');
            }
          }
        }
      }
    });

    test('exactly six triangles meet at an inner vertex', () {
      expect(cellsAtVertex('10.5').length, 6);
      expect(cellsAtVertex('8.4').length, 6);
    });

    test('a point inside a triangle is recognised, one outside is not', () {
      final List<Offset> v = cellVerts(5, 10);
      final Offset centre =
          Offset((v[0].dx + v[1].dx + v[2].dx) / 3, (v[0].dy + v[1].dy + v[2].dy) / 3);
      expect(pointInTriangle(centre, v), isTrue);
      expect(pointInTriangle(centre + const Offset(0, -400), v), isFalse);
    });
  });

  group('placement rules', () {
    test('a triangle may not float free of the table', () {
      final Map<String, Placed> empty = <String, Placed>{};
      expect(canPlace(empty, 5, 10, kJokerCorners, MatchMode.colourAndNumber), isFalse);
    });

    test('a taken cell, or one off the board, is refused', () {
      final Map<String, Placed> board = <String, Placed>{cellKey(5, 10): jokerAt()};
      expect(canPlace(board, 5, 10, kJokerCorners, MatchMode.colourAndNumber), isFalse);
      expect(canPlace(board, -1, 10, kJokerCorners, MatchMode.colourAndNumber), isFalse);
      expect(canPlace(board, 5, kCols, kJokerCorners, MatchMode.colourAndNumber), isFalse);
    });

    test('both shared corners must agree, not just one', () {
      const TCorner a = TCorner(0, 1);
      const TCorner b = TCorner(1, 2);
      const TCorner c = TCorner(2, 3);
      // (5,10) points down; (5,9) points up and shares corners [0,1] / [1,0].
      final Map<String, Placed> board = <String, Placed>{
        cellKey(5, 10): Placed(const Tile(1, <TCorner>[a, b, c]), const <TCorner>[a, b, c]),
      };
      final List<TCorner> exact = <TCorner>[b, a, c];
      expect(canPlace(board, 5, 9, exact, MatchMode.colourAndNumber), isTrue,
          reason: 'both pairs line up');
      final List<TCorner> halfRight = <TCorner>[b, c, c];
      expect(canPlace(board, 5, 9, halfRight, MatchMode.colourAndNumber), isFalse,
          reason: 'one pair agrees, the other does not — still illegal');
    });

    test('rotating three notches returns the tile to where it started', () {
      const Tile t = Tile(0, <TCorner>[TCorner(0, 1), TCorner(1, 2), TCorner(2, 3)]);
      expect(t.rotated(3).map((TCorner c) => '${c.color}${c.number}').join(),
          t.rotated(0).map((TCorner c) => '${c.color}${c.number}').join());
      expect(t.rotated(1)[0].number, 2);
    });
  });

  group('scoring', () {
    test('points rise with how many triangles the new one leans on', () {
      expect(kTouchPoints, <int>[0, 1, 3, 6]);
      final List<Point<int>> fan = cellsAtVertex('10.5');
      final Map<String, Placed> board = <String, Placed>{
        cellKey(fan[0].x, fan[0].y): jokerAt(),
      };
      expect(scoreFor(board, fan[1].x, fan[1].y).points, 1);
    });

    test('the sixth triangle at a vertex closes the circle', () {
      final List<Point<int>> fan = cellsAtVertex('10.5');
      final Map<String, Placed> board = <String, Placed>{};
      for (int i = 0; i < 5; i++) {
        board[cellKey(fan[i].x, fan[i].y)] = jokerAt();
      }
      final Score sc = scoreFor(board, fan[5].x, fan[5].y);
      expect(sc.closed, contains('10.5'));
      expect(sc.points, greaterThanOrEqualTo(kCircleBonus));
      expect(vertexCounts(board)['10.5'], 5);
    });

    test('leftovers are docked, and the higher final score wins', () {
      const Tile spare = Tile(0, kJokerCorners);
      expect(finalScore(10, <Tile>[spare, spare]), 10 - 2 * kLeftoverPenalty);
      // 20 with three left (14) still beats 15 with nothing left.
      expect(
        settle(<int>[20, 15], <List<Tile>>[
          <Tile>[spare, spare, spare],
          <Tile>[],
        ]),
        1,
      );
      expect(settle(<int>[12, 12], <List<Tile>>[<Tile>[], <Tile>[]]), -1);
    });
  });

  group('deck and root', () {
    test('the deck is exactly as big as the plan says', () {
      for (final Level level in Level.values) {
        for (final int seed in <int>[1, 7, 42]) {
          final DeckPlan plan = deckPlan(level, seed, 5);
          expect(plan.total, plan.regulars + plan.jokers);
          expect(plan.total, greaterThanOrEqualTo(5 * 2 + 8));
          final List<Tile> deck = makeDeck(
              seed: seed, jokers: plan.jokers, regulars: plan.regulars, typeCount: 8);
          expect(deck.length, plan.total);
          expect(deck.where((Tile t) => t.isJoker).length, plan.jokers);
        }
      }
    });

    test('a round only deals the requested number of corner types', () {
      final List<Tile> deck = makeDeck(seed: 3, jokers: 2, regulars: 60, typeCount: 6);
      expect(paletteOf(deck).length, lessThanOrEqualTo(6));
      // Out-of-range requests are pinned rather than throwing.
      expect(paletteOf(makeDeck(seed: 3, jokers: 1, regulars: 40, typeCount: 0)).length,
          lessThanOrEqualTo(3));
      expect(paletteOf(makeDeck(seed: 3, jokers: 1, regulars: 400, typeCount: 99)).length,
          lessThanOrEqualTo(25));
    });

    test('every root is legal by construction, on every shape and mode', () {
      for (final MatchMode mode in MatchMode.values) {
        for (final RootShape shape in RootShape.values) {
          for (int seed = 1; seed <= 12; seed++) {
            final List<Tile> deck =
                makeDeck(seed: seed, jokers: 4, regulars: 40, typeCount: 8);
            final Map<String, Placed> root =
                buildRoot(Random(seed), paletteOf(deck), shape);
            expect(root.length, kRoots[shape]!.cells.length);
            root.forEach((String k, Placed cell) {
              final List<String> rc = k.split(',');
              final int r = int.parse(rc[0]);
              final int c = int.parse(rc[1]);
              for (final Neighbour nb in neighbours(r, c)) {
                final Placed? other = root[cellKey(nb.r, nb.c)];
                if (other == null) continue;
                for (final List<int> p in nb.pairs) {
                  expect(
                    cornersMatch(cell.corners[p[0]], other.corners[p[1]], mode),
                    isTrue,
                    reason: 'root cell ($r,$c) clashes with (${nb.r},${nb.c})',
                  );
                }
              }
            });
          }
        }
      }
    });
  });

  group('the bot', () {
    test('every move it offers is legal, at every skill', () {
      for (final BotLevel skill in BotLevel.values) {
        final List<Tile> deck =
            makeDeck(seed: 9, jokers: 4, regulars: 40, typeCount: 8);
        final Map<String, Placed> board =
            buildRoot(Random(9), paletteOf(deck), RootShape.small);
        final List<Tile> hand = deck.sublist(0, 5);
        final Move? mv =
            bestMove(board, hand, MatchMode.colourAndNumber, skill, Random(4));
        if (mv == null) continue;
        expect(
          canPlace(board, mv.r, mv.c, hand[mv.handIndex].rotated(mv.rot),
              MatchMode.colourAndNumber),
          isTrue,
        );
      }
    });

    test('a bot-versus-bot game always ends, and never plays an illegal move', () {
      for (final Level level in Level.values) {
        for (final MatchMode mode in MatchMode.values) {
          final int seed = level.index * 13 + mode.index + 1;
          final DeckPlan plan = deckPlan(level, seed, 5);
          final List<Tile> d = makeDeck(
              seed: seed,
              jokers: plan.jokers,
              regulars: plan.regulars,
              typeCount: 8);
          final List<List<Tile>> hands = <List<Tile>>[
            d.sublist(0, 5),
            d.sublist(5, 10),
          ];
          final List<Tile> deck = d.sublist(10);
          final Map<String, Placed> board =
              buildRoot(Random(seed), paletteOf(d), plan.root);

          final List<int> scores = <int>[0, 0];
          int turn = 0;
          int passes = 0;
          int? winner;
          int steps = 0;

          while (winner == null) {
            steps++;
            expect(steps, lessThan(4000), reason: 'the game must terminate');
            final Move? mv = bestMove(board, hands[turn], mode, BotLevel.hard);
            if (mv != null) {
              final Tile t = hands[turn][mv.handIndex];
              expect(canPlace(board, mv.r, mv.c, t.rotated(mv.rot), mode), isTrue,
                  reason: 'illegal placement at (${mv.r},${mv.c})');
              board[cellKey(mv.r, mv.c)] = Placed(t, t.rotated(mv.rot));
              hands[turn].removeAt(mv.handIndex);
              scores[turn] += mv.score.points;
              passes = 0;
              if (hands[turn].isEmpty) {
                winner = settle(scores, hands);
                break;
              }
              turn = 1 - turn;
            } else if (deck.isNotEmpty) {
              hands[turn].add(deck.removeAt(0));
              passes = 0;
              if (findAnyMove(board, hands[turn], mode) == null) turn = 1 - turn;
            } else {
              passes++;
              if (passes >= 2) {
                winner = settle(scores, hands);
                break;
              }
              turn = 1 - turn;
            }
          }

          expect(winner, anyOf(-1, 0, 1));
          // No vertex may ever hold more than the six triangles that fit there.
          final Map<String, int> counts = vertexCounts(board);
          for (final int n in counts.values) {
            expect(n, lessThanOrEqualTo(6));
          }
        }
      }
    });
  });
}
