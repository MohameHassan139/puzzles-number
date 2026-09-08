// Tests for the three things that changed in this pass: the faster scan, the
// pile that looks after a stuck player, and the opponent that reads the
// position it is leaving behind.

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:puzzles_numeral/main.dart';

/// The old exhaustive scan, kept here as the thing the fast one is checked
/// against. If these two ever disagree, the optimisation is wrong.
List<Point<int>> legalCellsByFullScan(
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

Map<String, Placed> rootFor(int seed, RootShape shape, List<Tile> deck) =>
    buildRoot(Random(seed), paletteOf(deck), shape);

String show(List<Point<int>> cells) =>
    cells.map((Point<int> p) => '${p.x},${p.y}').join(' ');

void main() {
  group('the fast scan', () {
    test('gives exactly what a full 231-cell sweep gives', () {
      int queries = 0;
      for (int seed = 1; seed <= 8; seed++) {
        final List<Tile> deck =
            makeDeck(seed: seed, jokers: 4, regulars: 40, typeCount: 8);
        final Map<String, Placed> board = rootFor(seed, RootShape.small, deck);
        for (final MatchMode mode in MatchMode.values) {
          for (final Tile t in deck.take(6)) {
            for (int k = 0; k < 3; k++) {
              final List<TCorner> corners = t.rotated(k);
              expect(
                show(legalCells(board, corners, mode)),
                show(legalCellsByFullScan(board, corners, mode)),
                reason: 'frontier scan disagreed with the full sweep',
              );
              queries++;
            }
          }
        }
      }
      expect(queries, greaterThan(400));
    });

    test('the frontier is every empty cell touching the table, and only those',
        () {
      final List<Tile> deck = makeDeck(seed: 5, jokers: 3, regulars: 30, typeCount: 8);
      final Map<String, Placed> board = rootFor(5, RootShape.wide, deck);
      final List<Point<int>> front = frontierCells(board);

      for (final Point<int> p in front) {
        expect(board.containsKey(cellKey(p.x, p.y)), isFalse);
        final bool touches = neighbours(p.x, p.y)
            .any((Neighbour nb) => board.containsKey(cellKey(nb.r, nb.c)));
        expect(touches, isTrue);
      }
      // and nothing eligible was left out
      int eligible = 0;
      for (int r = 0; r < kRows; r++) {
        for (int c = 0; c < kCols; c++) {
          if (board.containsKey(cellKey(r, c))) continue;
          if (neighbours(r, c)
              .any((Neighbour nb) => board.containsKey(cellKey(nb.r, nb.c)))) {
            eligible++;
          }
        }
      }
      expect(front.length, eligible);
    });
  });

  group('the kind pile', () {
    test('hands over a triangle that fits, even when the top one does not', () {
      final List<Tile> source =
          makeDeck(seed: 12, jokers: 2, regulars: 40, typeCount: 8);
      final Map<String, Placed> board = rootFor(12, RootShape.small, source);

      // A tile that cannot possibly go anywhere: three corners of a colour and
      // number the round never dealt.
      const Tile dud = Tile(900, <TCorner>[
        TCorner(4, 5),
        TCorner(4, 5),
        TCorner(4, 5),
      ]);
      const MatchMode mode = MatchMode.colourAndNumber;

      // Only run the check when that tile really is dead against this board.
      if (tileFits(board, dud, mode)) return;

      final Tile good = source.firstWhere((Tile t) => tileFits(board, t, mode));
      final List<Tile> deck = <Tile>[dud, dud, good];

      final Draw drawn = drawTile(deck, board, mode);
      expect(drawn.rescued, isTrue);
      expect(drawn.jokerised, isFalse);
      expect(tileFits(board, drawn.tile, mode), isTrue);
      expect(deck.length, 2, reason: 'exactly one triangle leaves the pile');
    });

    test('takes the top one untouched when the top one already fits', () {
      final List<Tile> source =
          makeDeck(seed: 4, jokers: 3, regulars: 40, typeCount: 8);
      final Map<String, Placed> board = rootFor(4, RootShape.small, source);
      const MatchMode mode = MatchMode.colourAndNumber;

      final Tile good = source.firstWhere((Tile t) => tileFits(board, t, mode));
      final List<Tile> deck = <Tile>[good, ...source.take(3)];

      final Draw drawn = drawTile(deck, board, mode);
      expect(drawn.rescued, isFalse);
      expect(drawn.jokerised, isFalse);
      expect(identical(drawn.tile, good), isTrue);
    });

    test('turns the triangle into a joker when the whole pile is dead', () {
      final List<Tile> source =
          makeDeck(seed: 8, jokers: 1, regulars: 30, typeCount: 8);
      final Map<String, Placed> board = rootFor(8, RootShape.small, source);
      const MatchMode mode = MatchMode.colourAndNumber;
      const Tile dud = Tile(901, <TCorner>[
        TCorner(4, 5),
        TCorner(4, 5),
        TCorner(4, 5),
      ]);
      if (tileFits(board, dud, mode)) return;

      final List<Tile> deck = <Tile>[dud, dud];
      final Draw drawn = drawTile(deck, board, mode);
      expect(drawn.jokerised, isTrue);
      expect(drawn.tile.isJoker, isTrue);
      expect(tileFits(board, drawn.tile, mode), isTrue,
          reason: 'a joker fits anywhere there is a space');
    });

    test('switched off, it just takes the top card', () {
      final List<Tile> source =
          makeDeck(seed: 6, jokers: 2, regulars: 30, typeCount: 8);
      final Map<String, Placed> board = rootFor(6, RootShape.small, source);
      final List<Tile> deck = List<Tile>.from(source);
      final Tile top = deck.first;
      final Draw drawn =
          drawTile(deck, board, MatchMode.colourAndNumber, rescue: false);
      expect(identical(drawn.tile, top), isTrue);
      expect(drawn.rescued, isFalse);
    });

    test('nobody ever wastes a turn while the pile still has triangles', () {
      int wasted = 0;
      int games = 0;
      for (final Level level in Level.values) {
        for (final MatchMode mode in MatchMode.values) {
          final int seed = level.index * 17 + mode.index + 3;
          wasted += _playOut(level, mode, seed, kind: true).wastedTurns;
          games++;
        }
      }
      expect(games, 16);
      expect(wasted, 0,
          reason: 'with the kind pile on, a draw always produces a playable tile');
    });
  });

  group('the sharp bot', () {
    test('rates every candidate with a real number and picks a legal one', () {
      for (int seed = 1; seed <= 6; seed++) {
        final List<Tile> deck =
            makeDeck(seed: seed, jokers: 4, regulars: 40, typeCount: 8);
        final Map<String, Placed> board = rootFor(seed, RootShape.small, deck);
        final List<Tile> hand = deck.sublist(0, 5);
        const MatchMode mode = MatchMode.colourAndNumber;

        final List<Move> moves = allMoves(board, hand, mode);
        if (moves.isEmpty) continue;
        final List<int> homes = <int>[
          for (int h = 0; h < hand.length; h++)
            moves.where((Move m) => m.handIndex == h).length,
        ];
        for (final Move m in moves) {
          final double v = moveValue(board, hand, m, mode, homes);
          expect(v.isFinite, isTrue);
        }

        final Move? pick = bestMove(board, hand, mode, BotLevel.hard);
        expect(pick, isNotNull);
        expect(
          canPlace(board, pick!.r, pick.c, hand[pick.handIndex].rotated(pick.rot), mode),
          isTrue,
        );
      }
    });

    test('beats the wandering bot far more often than not', () {
      int sharp = 0;
      int wander = 0;
      int played = 0;
      for (final Level level in Level.values) {
        for (int seed = 1; seed <= 6; seed++) {
          final _Result r = _playOut(
            level,
            MatchMode.colourAndNumber,
            seed,
            kind: true,
            skills: const <BotLevel>[BotLevel.hard, BotLevel.easy],
          );
          played++;
          if (r.winner == 0) sharp++;
          if (r.winner == 1) wander++;
        }
      }
      expect(played, 24);
      // The simulator has it around nine in ten; two thirds is a floor that
      // leaves room for the shuffle without letting a regression through.
      expect(sharp, greaterThan(played * 2 ~/ 3),
          reason: 'sharp won $sharp of $played (wandering won $wander)');
    });

    test('gives away far fewer free circles than the bot that only tightens',
        () {
      // The measurable difference between "keeps it tight" and "thinks a move
      // ahead": a vertex left sitting on five triangles is five free points for
      // whoever plays next. Both bots are shown the same positions.
      int sharpGifts = 0;
      int tightGifts = 0;
      int sharpPoints = 0;
      int tightPoints = 0;
      int positions = 0;

      const MatchMode mode = MatchMode.colourAndNumber;
      final Random rnd = Random(7);

      for (int seed = 1; seed <= 24; seed++) {
        final List<Tile> d = makeDeck(seed: seed, jokers: 4, regulars: 50, typeCount: 8);
        final Map<String, Placed> board =
            buildRoot(Random(seed), paletteOf(d), RootShape.small);
        final List<Tile> hand = d.sublist(0, 6);
        final List<Tile> pool = d.sublist(6);

        for (int step = 0; step < 12; step++) {
          if (allMoves(board, hand, mode).isEmpty) break;
          positions++;

          final Move sharp = bestMove(board, hand, mode, BotLevel.hard, rnd)!;
          final Move tight = bestMove(board, hand, mode, BotLevel.normal, rnd)!;
          sharpGifts += _giftedVertices(board, hand, sharp);
          tightGifts += _giftedVertices(board, hand, tight);
          sharpPoints += sharp.score.points;
          tightPoints += tight.score.points;

          final Tile t = hand[sharp.handIndex];
          board[cellKey(sharp.r, sharp.c)] = Placed(t, t.rotated(sharp.rot), 1);
          hand.removeAt(sharp.handIndex);
          if (pool.isNotEmpty) hand.add(pool.removeAt(0));
        }
      }

      expect(positions, greaterThan(150));
      expect(sharpGifts, lessThan(tightGifts),
          reason: 'sharp left $sharpGifts vertices on five, tight left $tightGifts');
      // and it does not pay for that restraint in points
      expect(sharpPoints, greaterThanOrEqualTo(tightPoints));
    });
  });
}

/// How many lattice vertices a move leaves sitting on five triangles — that is,
/// how many free circle bonuses it hands to whoever plays next.
int _giftedVertices(Map<String, Placed> board, List<Tile> hand, Move mv) {
  final Tile t = hand[mv.handIndex];
  final Map<String, Placed> after = Map<String, Placed>.from(board);
  after[cellKey(mv.r, mv.c)] = Placed(t, t.rotated(mv.rot));
  final Map<String, int> counts = vertexCounts(after);
  int gifts = 0;
  for (final String v in vertexIds(mv.r, mv.c)) {
    if (counts[v] == 5) gifts++;
  }
  return gifts;
}

class _Result {
  final int? winner;
  final int wastedTurns;
  final int placed;

  const _Result(this.winner, this.wastedTurns, this.placed);
}

/// A whole game played out head to head, used by several tests above.
_Result _playOut(
  Level level,
  MatchMode mode,
  int seed, {
  required bool kind,
  List<BotLevel> skills = const <BotLevel>[BotLevel.hard, BotLevel.hard],
  int handSize = 5,
}) {
  final DeckPlan plan = deckPlan(level, seed, handSize);
  final List<Tile> d = makeDeck(
      seed: seed, jokers: plan.jokers, regulars: plan.regulars, typeCount: 8);
  final List<List<Tile>> hands = <List<Tile>>[
    d.sublist(0, handSize),
    d.sublist(handSize, handSize * 2),
  ];
  final List<Tile> deck = d.sublist(handSize * 2);
  final Map<String, Placed> board = buildRoot(Random(seed), paletteOf(d), plan.root);

  final List<int> scores = <int>[0, 0];
  final Random rnd = Random(seed * 31 + 7);
  int turn = 0;
  int passes = 0;
  int wasted = 0;
  int? winner;
  int steps = 0;

  while (winner == null) {
    steps++;
    if (steps > 5000) {
      throw StateError('the game did not terminate');
    }
    final Move? mv = bestMove(board, hands[turn], mode, skills[turn], rnd);
    if (mv != null) {
      final Tile t = hands[turn][mv.handIndex];
      if (!canPlace(board, mv.r, mv.c, t.rotated(mv.rot), mode)) {
        throw StateError('illegal placement at ${mv.r},${mv.c}');
      }
      board[cellKey(mv.r, mv.c)] = Placed(t, t.rotated(mv.rot), turn);
      hands[turn].removeAt(mv.handIndex);
      scores[turn] += mv.score.points;
      passes = 0;
      if (hands[turn].isEmpty) {
        winner = settle(scores, hands);
        break;
      }
      turn = 1 - turn;
    } else if (deck.isNotEmpty) {
      final Draw drawn = drawTile(deck, board, mode, rescue: kind);
      hands[turn].add(drawn.tile);
      passes = 0;
      if (findAnyMove(board, hands[turn], mode) == null) {
        wasted++;
        turn = 1 - turn;
      }
    } else {
      passes++;
      if (passes >= 2) {
        winner = settle(scores, hands);
        break;
      }
      turn = 1 - turn;
    }
  }

  return _Result(winner, wasted, board.length);
}
