// The screen, and the turn it drives.

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import 'ai.dart';
import 'deck.dart';
import 'effects.dart';
import 'model.dart';
import 'painters.dart';
import 'scoring.dart';
import 'theme.dart';
import 'widgets.dart';

class GamePage extends StatefulWidget {
  const GamePage({super.key});

  @override
  State<GamePage> createState() => GamePageState();
}

class GamePageState extends State<GamePage> with SingleTickerProviderStateMixin {
  // ── settings ──
  int seed = 7;
  int handSize = 5;
  int typeCount = 8;
  Level level = Level.normal;
  MatchMode mode = MatchMode.colourAndNumber;
  bool vsBot = true;
  BotLevel botLevel = BotLevel.hard;

  /// The pile looks after whoever is stuck — both sides, identically. Off, and
  /// a dead draw costs you the turn, the way it used to.
  bool kindPile = true;

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
  List<int> streaks = <int>[0, 0];
  String message = '';

  List<int> scores = <int>[0, 0];
  List<int> circles = <int>[0, 0];
  final List<Snapshot> history = <Snapshot>[];
  Point<int>? hint;
  bool botThinking = false;

  // ── the look ──
  final List<Fx> fx = <Fx>[];
  final Map<String, double> placedAt = <String, double>{};
  final ValueNotifier<double> clock = ValueNotifier<double>(0);
  late final Ticker _ticker;
  double _now = 0;
  double _clockBase = 0;
  int _fxSeed = 1;

  Set<String> _strong = <String>{};
  Set<String> _weak = <String>{};

  final TransformationController _viewer = TransformationController();
  bool _fitted = false;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_tick);
    newGame();
  }

  @override
  void dispose() {
    // A Ticker must be stopped before it is disposed, or the framework asserts.
    _ticker
      ..stop()
      ..dispose();
    _viewer.dispose();
    clock.dispose();
    super.dispose();
  }

  // ── the clock ────────────────────────────────────────────
  //
  // One ticker drives every animation on the board, and it only runs while
  // there is something to animate. A game sitting idle costs nothing.

  void _tick(Duration elapsed) {
    _now = _clockBase + elapsed.inMicroseconds / 1000000.0;
    fx.removeWhere((Fx f) => !f.alive(_now));
    clock.value = _now;
    if (!_clockNeeded) _ticker.stop();
  }

  bool get _clockNeeded =>
      fx.isNotEmpty ||
      _strong.isNotEmpty ||
      _weak.isNotEmpty ||
      hint != null ||
      _placingRecently;

  bool get _placingRecently {
    for (final double t in placedAt.values) {
      if (_now - t < 0.55) return true;
    }
    return false;
  }

  void _wake() {
    if (_ticker.isActive) return;
    _clockBase = _now;
    _ticker.start();
  }

  int get _nextFxSeed => _fxSeed++;

  // ── setting up a round ───────────────────────────────────

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
      last = null;
      winner = null;
      passes = 0;
      streaks = <int>[0, 0];
      scores = <int>[0, 0];
      circles = <int>[0, 0];
      history.clear();
      hint = null;
      botThinking = false;
      fx.clear();
      placedAt.clear();
      // The root drops in with the same pop a played tile gets, staggered, so
      // a new round arrives rather than simply being there.
      int i = 0;
      for (final String k in board.keys) {
        placedAt[k] = _now + i * 0.045;
        i++;
      }
      message = '${kLevels[level]!.short} · ${plan.total} triangles. Pick one and find its place.';
      _recompute();
    });
    _wake();
  }

  void _recompute() {
    final Tile? t = selTile;
    if (t == null) {
      _strong = <String>{};
      _weak = <String>{};
      return;
    }
    final Set<String> strong = legalCells(board, t.rotated(rot), mode)
        .map((Point<int> p) => cellKey(p.x, p.y))
        .toSet();
    final Set<String> weak = <String>{};
    for (int k = 0; k < 3; k++) {
      if (k == rot) continue;
      for (final Point<int> p in legalCells(board, t.rotated(k), mode)) {
        final String key = cellKey(p.x, p.y);
        if (!strong.contains(key)) weak.add(key);
      }
    }
    _strong = strong;
    _weak = weak;
  }

  // ── derived ──────────────────────────────────────────────

  List<Tile> get hand => hands[turn];

  Tile? get selTile {
    final int? s = sel;
    if (s == null || s < 0 || s >= hand.length) return null;
    return hand[s];
  }

  bool get stuck => winner == null && findAnyMove(board, hand, mode) == null;

  bool get myTurn => winner == null && (!vsBot || turn == 0);

  // ── effects ──────────────────────────────────────────────

  void _placeFx(int r, int c, Score sc, List<String> joins, int who) {
    final Offset centre = cellCentre(r, c);
    final int accent = who == 0 ? rgbYou : rgbFoe;

    fx.add(Fx(kind: FxKind.wave, at: centre, start: _now, life: 0.55, rgb: accent));
    for (final String v in joins) {
      fx.add(Fx(kind: FxKind.join, at: vertexOffset(v), start: _now + 0.05, life: 0.6));
    }
    for (final String v in sc.closed) {
      fx.add(Fx(
        kind: FxKind.sparkle,
        at: vertexOffset(v),
        start: _now + 0.08,
        life: 0.95,
        seed: _nextFxSeed,
      ));
    }
    if (sc.points > 0) {
      fx.add(Fx(
        kind: FxKind.score,
        at: centre,
        start: _now + 0.1,
        life: 1.0,
        rgb: sc.closed.isNotEmpty ? rgbGold : rgbWhite,
        text: '+${sc.points}',
      ));
    }
    if (streaks[who] >= 2 && sc.points > 0) {
      fx.add(Fx(
        kind: FxKind.score,
        at: centre + const Offset(0, -34),
        start: _now + 0.3,
        life: 1.0,
        rgb: accent,
        text: 'x${streaks[who]}',
      ));
    }
    placedAt[cellKey(r, c)] = _now;
    _wake();
  }

  void _buzz(Score sc) {
    if (sc.closed.isNotEmpty) {
      HapticFeedback.mediumImpact();
    } else {
      HapticFeedback.lightImpact();
    }
  }

  // ── moves ────────────────────────────────────────────────

  void place(int r, int c) {
    final Tile? t = selTile;
    final int? s = sel;
    if (t == null || s == null || winner != null || !myTurn) return;

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
      board[cellKey(r, c)] = Placed(t, t.rotated(useRot), turn);
      hands[turn].removeAt(s);
      last = Point<int>(r, c);
      sel = null;
      rot = 0;
      passes = 0;
      hint = null;
      scores[turn] += sc.points;
      circles[turn] += sc.closed.length;
      streaks[turn] = sc.points > 0 ? streaks[turn] + 1 : 0;
      _placeFx(r, c, sc, joins, turn);
      if (hands[turn].isEmpty) {
        winner = settle(scores, hands);
        message = 'You went out — the score settles it.';
        _recompute();
        return;
      }
      turn = 1 - turn;
      message = _scoreLine(sc);
      _recompute();
    });

    _buzz(sc);
    _maybeBot();
  }

  String _scoreLine(Score sc) {
    if (sc.closed.length > 1) return 'Two circles at once! +${sc.points}';
    if (sc.closed.length == 1) return 'Circle closed! +${sc.points}';
    if (sc.touching == 3) return 'Snug in the gap — three sides. +${sc.points}';
    if (sc.touching == 2) return 'Two sides touching. +${sc.points}';
    return '+${sc.points}';
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
      List<int>.from(streaks),
    ));
    if (history.length > 40) history.removeAt(0);
  }

  void undo() {
    if (history.isEmpty || botThinking) return;
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
      streaks = p.streaks;
      sel = null;
      rot = 0;
      hint = null;
      fx.clear();
      message = 'Taken back.';
      _recompute();
    });
    _wake();
  }

  /// Points at the best move on the table right now.
  void showHint() {
    if (!myTurn) return;
    final Move? mv = bestMove(board, hand, mode, BotLevel.hard);
    setState(() {
      if (mv == null) {
        message = 'Nothing fits — take one from the pile.';
        return;
      }
      sel = mv.handIndex;
      rot = mv.rot;
      hint = Point<int>(mv.r, mv.c);
      message = 'Try the ringed space — worth ${mv.score.points}.';
      _recompute();
    });
    _wake();
    HapticFeedback.selectionClick();
  }

  /// Drawing is the whole turn — unless what you drew fits, in which case play
  /// it now. With the kind pile on, it always will.
  void draw() {
    if (winner != null || !myTurn) return;
    if (deck.isNotEmpty) _pushHistory();

    setState(() {
      if (deck.isEmpty) {
        passes++;
        sel = null;
        streaks[turn] = 0;
        if (passes >= 2) {
          winner = settle(scores, hands);
          message = 'Pile empty, nothing fits. The score settles it.';
          _recompute();
          return;
        }
        message = 'Pile empty and nothing fits. Turn passes.';
        turn = 1 - turn;
        _recompute();
        return;
      }

      final Draw drawn = drawTile(deck, board, mode, rescue: kindPile);
      hands[turn].add(drawn.tile);
      sel = null;
      rot = 0;
      passes = 0;
      hint = null;
      if (findAnyMove(board, hands[turn], mode) != null) {
        sel = hands[turn].length - 1;
        message = 'Lucky one — that fits. Play it.';
        _recompute();
        return;
      }
      streaks[turn] = 0;
      turn = 1 - turn;
      message = 'Drew one, nothing fits. Turn passes.';
      _recompute();
    });

    _wake();
    HapticFeedback.selectionClick();
    _maybeBot();
  }

  void _maybeBot() {
    if (!vsBot || turn != 1 || winner != null) return;
    setState(() => botThinking = true);
    Future<void>.delayed(const Duration(milliseconds: 420), () {
      if (!mounted || !vsBot || turn != 1 || winner != null) {
        if (mounted) setState(() => botThinking = false);
        return;
      }
      final Move? mv = bestMove(board, hands[1], mode, botLevel);

      setState(() {
        botThinking = false;
        if (mv != null) {
          final Tile t = hands[1][mv.handIndex];
          final Score sc = mv.score;
          final List<String> joins = matchedVertices(board, mv.r, mv.c);
          board[cellKey(mv.r, mv.c)] = Placed(t, t.rotated(mv.rot), 1);
          hands[1].removeAt(mv.handIndex);
          last = Point<int>(mv.r, mv.c);
          scores[1] += sc.points;
          circles[1] += sc.closed.length;
          passes = 0;
          streaks[1] = sc.points > 0 ? streaks[1] + 1 : 0;
          _placeFx(mv.r, mv.c, sc, joins, 1);
          if (hands[1].isEmpty) {
            winner = settle(scores, hands);
            message = 'The bot went out — the score settles it.';
          } else {
            turn = 0;
            message = sc.closed.isNotEmpty
                ? 'Bot closed a circle for ${sc.points}. Your turn.'
                : 'Bot scored ${sc.points}. Your turn.';
          }
        } else if (deck.isNotEmpty) {
          final Draw drawn = drawTile(deck, board, mode, rescue: kindPile);
          hands[1].add(drawn.tile);
          passes = 0;
          if (findAnyMove(board, hands[1], mode) != null) {
            message = 'Bot found one in the pile…';
          } else {
            turn = 0;
            message = 'Bot drew and passed. Your turn.';
          }
        } else {
          passes++;
          if (passes >= 2) {
            winner = settle(scores, hands);
            message = 'Pile empty, nothing fits. The score settles it.';
          } else {
            turn = 0;
            message = 'Bot passed. Your turn.';
          }
        }
        _recompute();
      });

      _wake();
      _maybeBot();
    });
  }

  // ─────────────────────────────────────────────────────────
  // The screen
  // ─────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: <Widget>[
          const _Background(),
          SafeArea(
            child: Column(
              children: <Widget>[
                _topBar(),
                _hud(),
                Expanded(child: _boardPanel()),
                _statusLine(),
                _tray(),
                _actions(),
                const SizedBox(height: 8),
              ],
            ),
          ),
          if (winner != null) _winOverlay(),
        ],
      ),
    );
  }

  Widget _topBar() => Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 10, 4),
        child: Row(
          children: <Widget>[
            const Expanded(
              child: Text(
                'Puzzles Numeral',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: kCream,
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.3,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Chip2(kLevels[level]!.short,
                icon: Icons.local_fire_department_rounded, tint: kGold),
            IconButton(
              onPressed: _openSettings,
              icon: Icon(Icons.tune_rounded, color: white(0.75)),
              tooltip: 'Rules and settings',
            ),
            IconButton(
              onPressed: newGame,
              icon: Icon(Icons.refresh_rounded, color: white(0.75)),
              tooltip: 'New game',
            ),
          ],
        ),
      );

  Widget _hud() => Padding(
        padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
        child: Row(
          children: <Widget>[
            Expanded(
              child: PlayerCard(
                name: 'YOU',
                score: scores[0],
                tiles: hands[0].length,
                active: turn == 0 && winner == null,
                accent: kYouColor,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: PlayerCard(
                name: vsBot ? 'BOT' : 'P2',
                score: scores[1],
                tiles: hands[1].length,
                active: turn == 1 && winner == null,
                accent: kFoeColor,
                thinking: botThinking,
              ),
            ),
            const SizedBox(width: 8),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(Icons.layers_rounded, size: 18, color: white(0.55)),
                const SizedBox(height: 2),
                Text('${deck.length}',
                    style: TextStyle(
                        color: white(0.72), fontSize: 13, fontWeight: FontWeight.w800)),
              ],
            ),
          ],
        ),
      );

  /// Sets the opening pan and zoom so the whole lattice is on screen, rather
  /// than dropping the player on the top-left corner of an 814×705 board.
  void _fitBoard(Size view) {
    if (view.width <= 0 || view.height <= 0) return;
    final double s = min(view.width / kBoardW, view.height / kBoardH) * 0.98;
    final Matrix4 m = Matrix4.identity();
    m.setEntry(0, 0, s);
    m.setEntry(1, 1, s);
    m.setEntry(0, 3, (view.width - kBoardW * s) / 2);
    m.setEntry(1, 3, (view.height - kBoardH * s) / 2);
    _viewer.value = m;
  }

  Widget _boardPanel() => Panel(
        margin: const EdgeInsets.symmetric(horizontal: 12),
        radius: 26,
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
              maxScale: 3.2,
              boundaryMargin: const EdgeInsets.all(700),
              child: SizedBox(
                width: kBoardW,
                height: kBoardH,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapUp: (TapUpDetails d) => _handleBoardTap(d.localPosition),
                  child: RepaintBoundary(
                    child: CustomPaint(
                      painter: BoardPainter(
                        board: board,
                        strong: _strong,
                        weak: _weak,
                        placedAt: placedAt,
                        fx: fx,
                        clock: clock,
                        last: last,
                        hint: hint,
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

  void _handleBoardTap(Offset p) {
    for (final String key in <String>[..._strong, ..._weak]) {
      final Point<int> cell = parseCellKey(key);
      if (pointInTriangle(p, cellVerts(cell.x, cell.y))) {
        place(cell.x, cell.y);
        return;
      }
    }
  }

  Widget _statusLine() => Padding(
        padding: const EdgeInsets.fromLTRB(18, 9, 18, 5),
        child: SizedBox(
          height: 20,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            child: Text(
              message,
              key: ValueKey<String>(message),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: white(0.82),
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      );

  Widget _tray() => Container(
        height: 116,
        margin: const EdgeInsets.symmetric(horizontal: 12),
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: <Color>[kTrayTop, kTrayBottom],
          ),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: white(0.18), width: 1.4),
          boxShadow: <BoxShadow>[
            BoxShadow(color: black(0.35), blurRadius: 16, offset: const Offset(0, 6)),
          ],
        ),
        child: botThinking
            ? Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2.4, color: white(0.6)),
                    ),
                    const SizedBox(width: 10),
                    Text('Bot is thinking…',
                        style: TextStyle(
                            color: white(0.7), fontSize: 14, fontWeight: FontWeight.w700)),
                  ],
                ),
              )
            : ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(vertical: 6),
                itemCount: hand.length,
                separatorBuilder: (BuildContext _, int __) => const SizedBox(width: 4),
                itemBuilder: (BuildContext _, int i) => _trayTile(i),
              ),
      );

  Widget _trayTile(int i) {
    final bool selected = sel == i && myTurn;
    final List<Tile> myHand = hand;
    if (i >= myHand.length) return const SizedBox.shrink();
    return GestureDetector(
      onTap: () {
        if (!myTurn) return;
        HapticFeedback.selectionClick();
        setState(() {
          if (selected) {
            rot = (rot + 1) % 3;
          } else {
            sel = i;
            rot = 0;
          }
          hint = null;
          _recompute();
        });
        _wake();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 170),
        curve: Curves.easeOutBack,
        width: 92,
        transform: Matrix4.translationValues(0, selected ? -7 : 0, 0),
        padding: const EdgeInsets.symmetric(horizontal: 2),
        decoration: BoxDecoration(
          color: selected ? gold(0.20) : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? kGold : Colors.transparent,
            width: 2,
          ),
        ),
        child: CustomPaint(
          painter: TilePainter(
            myHand[i].rotated(selected ? rot : 0),
            selected: selected,
          ),
          size: const Size(88, 92),
        ),
      ),
    );
  }

  Widget _actions() {
    final bool canPlay = myTurn && !botThinking;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      child: Row(
        children: <Widget>[
          _iconAction(
            Icons.rotate_right_rounded,
            'Turn it',
            canPlay && sel != null
                ? () {
                    HapticFeedback.selectionClick();
                    setState(() {
                      rot = (rot + 1) % 3;
                      _recompute();
                    });
                    _wake();
                  }
                : null,
          ),
          const SizedBox(width: 8),
          _iconAction(Icons.lightbulb_rounded, 'Hint', canPlay ? showHint : null),
          const SizedBox(width: 8),
          _iconAction(Icons.undo_rounded, 'Undo',
              canPlay && history.isNotEmpty ? undo : null),
          const SizedBox(width: 10),
          Expanded(
            child: CandyButton(
              label: stuck ? 'Draw one!' : 'Draw',
              icon: Icons.style_rounded,
              compact: true,
              glow: stuck,
              onTap: canPlay ? draw : null,
            ),
          ),
        ],
      ),
    );
  }

  /// A square button. Icons rather than words for the three side actions:
  /// four labelled pills do not fit across a phone without one of them being
  /// cut to "Rot…", and a cropped label looks like a bug.
  Widget _iconAction(IconData icon, String tip, VoidCallback? onTap) {
    final bool enabled = onTap != null;
    return Tooltip(
      message: tip,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          width: 46,
          height: 42,
          decoration: BoxDecoration(
            color: white(enabled ? 0.18 : 0.07),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: white(enabled ? 0.24 : 0.08), width: 1.3),
          ),
          child: Icon(icon, size: 20, color: white(enabled ? 0.92 : 0.28)),
        ),
      ),
    );
  }

  // ── the end of a round ───────────────────────────────────

  Widget _winOverlay() {
    final int you = finalScore(scores[0], hands[0]);
    final int foe = finalScore(scores[1], hands[1]);
    final int margin = you - foe;
    final int stars = winner == 0
        ? (margin >= 18 ? 3 : (margin >= 8 ? 2 : 1))
        : (winner == -1 ? 1 : 0);
    final String headline = winner == -1
        ? 'Dead heat'
        : winner == 0
            ? 'You win!'
            : (vsBot ? 'Bot wins' : 'Player 2 wins');

    return Positioned.fill(
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: 0, end: 1),
        duration: const Duration(milliseconds: 380),
        curve: Curves.easeOutBack,
        builder: (BuildContext _, double t, Widget? child) => Opacity(
          opacity: t.clamp(0.0, 1.0).toDouble(),
          child: Transform.scale(scale: 0.85 + 0.15 * t, child: child),
        ),
        child: Container(
          color: black(0.62),
          alignment: Alignment.center,
          padding: const EdgeInsets.all(26),
          child: Panel(
            radius: 28,
            gradient: const <Color>[kBgTop, kBgDeep],
            child: Padding(
              padding: const EdgeInsets.fromLTRB(26, 24, 26, 22),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      for (int i = 0; i < 3; i++)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 3),
                          child: Icon(
                            i < stars ? Icons.star_rounded : Icons.star_outline_rounded,
                            size: i == 1 ? 46 : 38,
                            color: i < stars ? kGold : white(0.22),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(headline,
                      style: const TextStyle(
                          color: kCream, fontSize: 27, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 14),
                  _finalRow('You', you, scores[0], hands[0].length, circles[0], kYouColor),
                  const SizedBox(height: 6),
                  _finalRow(vsBot ? 'Bot' : 'Player 2', foe, scores[1], hands[1].length,
                      circles[1], kFoeColor),
                  const SizedBox(height: 18),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: CandyButton(
                          label: 'Play again',
                          icon: Icons.replay_rounded,
                          onTap: newGame,
                        ),
                      ),
                      const SizedBox(width: 10),
                      CandyButton(
                        label: 'Settings',
                        colors: <Color>[white(0.22), white(0.13)],
                        textColor: kCream,
                        onTap: _openSettings,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _finalRow(String name, int total, int scored, int left, int rings, Color accent) =>
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: white(0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: accent, width: 1.2),
        ),
        child: Row(
          children: <Widget>[
            Text(name,
                style: TextStyle(
                    color: accent, fontSize: 14, fontWeight: FontWeight.w800)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '$scored scored · $left left · $rings ○',
                textAlign: TextAlign.right,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: white(0.5), fontSize: 11.5),
              ),
            ),
            const SizedBox(width: 12),
            Text('$total',
                style: const TextStyle(
                    color: kCream, fontSize: 20, fontWeight: FontWeight.w900)),
          ],
        ),
      );

  // ── rules and settings ───────────────────────────────────

  void _openSettings() {
    // The sheet edits its own copies and only writes them back when a new game
    // actually starts, so a half-changed setting can never land on a round
    // already in progress.
    int nSeed = seed;
    int nHand = handSize;
    int nTypes = typeCount;
    Level nLevel = level;
    MatchMode nMode = mode;
    bool nVsBot = vsBot;
    BotLevel nBot = botLevel;
    bool nKind = kindPile;

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (BuildContext sheetCtx) => StatefulBuilder(
        builder: (BuildContext ctx, StateSetter setSheet) {
          final DeckPlan preview = deckPlan(nLevel, nSeed, nHand);
          return Container(
            margin: EdgeInsets.only(top: MediaQuery.of(ctx).size.height * 0.08),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: <Color>[kBgMid, kBgDeep],
              ),
              borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Container(
                  width: 44,
                  height: 5,
                  margin: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    color: white(0.3),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                Flexible(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.fromLTRB(
                        22, 4, 22, MediaQuery.of(ctx).viewInsets.bottom + 18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        const Text('How it plays',
                            style: TextStyle(
                                color: kCream, fontSize: 20, fontWeight: FontWeight.w900)),
                        const SizedBox(height: 10),
                        _rules(nHand, nTypes),
                        const SizedBox(height: 18),
                        Divider(color: white(0.12), height: 1),
                        const SizedBox(height: 18),
                        _choice<MatchMode>(
                          label: 'Matching rule',
                          value: nMode,
                          items: MatchMode.values,
                          labelOf: matchModeShort,
                          onChanged: (MatchMode v) => setSheet(() => nMode = v),
                        ),
                        const SizedBox(height: 14),
                        _choice<Level>(
                          label: 'Level',
                          value: nLevel,
                          items: Level.values,
                          labelOf: (Level l) => kLevels[l]!.short,
                          onChanged: (Level v) => setSheet(() => nLevel = v),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '${preview.total} triangles, ${preview.jokers} of them jokers, '
                          '${rootShapeLabel(preview.root).split(' —').first.toLowerCase()} opening',
                          style: TextStyle(color: white(0.5), fontSize: 12.5),
                        ),
                        const SizedBox(height: 14),
                        _choice<BotLevel>(
                          label: 'Opponent',
                          value: nBot,
                          items: BotLevel.values,
                          labelOf: botLevelShort,
                          onChanged: (BotLevel v) => setSheet(() => nBot = v),
                        ),
                        const SizedBox(height: 16),
                        _slider('Hand size', nHand.toDouble(), 3, 9,
                            (double v) => setSheet(() => nHand = v.round())),
                        _slider('Corner types per round', nTypes.toDouble(), 3, 25,
                            (double v) => setSheet(() => nTypes = v.round())),
                        _slider('Shuffle seed', nSeed.toDouble(), 1, 99,
                            (double v) => setSheet(() => nSeed = v.round())),
                        const SizedBox(height: 6),
                        _toggle(
                          'A kind pile',
                          'When nothing in your hand fits, what you draw will. '
                              'The same holds for your opponent.',
                          nKind,
                          (bool v) => setSheet(() => nKind = v),
                        ),
                        const SizedBox(height: 8),
                        _toggle('Play against the bot', '', nVsBot,
                            (bool v) => setSheet(() => nVsBot = v)),
                        const SizedBox(height: 20),
                        SizedBox(
                          width: double.infinity,
                          child: CandyButton(
                            label: 'Start a new game',
                            icon: Icons.play_arrow_rounded,
                            onTap: () {
                              Navigator.of(ctx).pop();
                              setState(() {
                                seed = nSeed;
                                handSize = nHand;
                                typeCount = nTypes;
                                level = nLevel;
                                mode = nMode;
                                vsBot = nVsBot;
                                botLevel = nBot;
                                kindPile = nKind;
                              });
                              newGame();
                            },
                          ),
                        ),
                        const SizedBox(height: 10),
                        Center(
                          child: Text('Settings apply when a new game starts.',
                              style: TextStyle(color: white(0.35), fontSize: 12)),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _rules(int nHand, int nTypes) => Text(
        'Every triangle carries a colour and a number in each corner. The board '
        'opens on a small arrangement laid out before play, seeded with jokers to '
        'give you a way in. Each player holds $nHand.\n\n'
        'Tap a triangle to pick it up, tap again to turn it. Bright spaces fit as '
        'it stands; faint ones fit after a turn, and the game will turn it for '
        'you. Where two triangles meet they share two corners, and BOTH pairs '
        'must match. A joker carries every colour and fits anything.\n\n'
        'Tuck triangles in rather than trailing them across the table: leaning on '
        'one is 1 point, two is 3, three is 6. Six triangles meet at every inner '
        'vertex, so closing one of those circles is worth $kCircleBonus more — and '
        'one triangle can close two at once.\n\n'
        'Going out ends the game but does not win it. The higher score wins, minus '
        '$kLeftoverPenalty for every triangle still in your hand. So go out when '
        'you are ahead, and keep scoring while you are behind.\n\n'
        'All five colours and numbers 1–5 exist, but one round only deals $nTypes '
        'of the 25 possible corner types. That is what makes an exact match '
        'findable — past about 10, hands grow faster than they empty.',
        style: TextStyle(color: white(0.68), fontSize: 13, height: 1.55),
      );

  /// A row of pills instead of a dropdown: everything is on screen, one tap
  /// away, and nothing opens a menu over the thing you are trying to read.
  Widget _choice<T>({
    required String label,
    required T value,
    required List<T> items,
    required String Function(T) labelOf,
    required ValueChanged<T> onChanged,
  }) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(label,
              style: TextStyle(
                  color: white(0.5), fontSize: 12, fontWeight: FontWeight.w700)),
          const SizedBox(height: 7),
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: <Widget>[
              for (final T item in items)
                GestureDetector(
                  onTap: () => onChanged(item),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                    decoration: BoxDecoration(
                      color: item == value ? kGold : white(0.09),
                      borderRadius: BorderRadius.circular(13),
                      border: Border.all(
                        color: item == value ? kGold : white(0.14),
                        width: 1.4,
                      ),
                    ),
                    child: Text(
                      labelOf(item),
                      style: TextStyle(
                        color: item == value ? kGoldInk : white(0.8),
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      );

  Widget _toggle(String label, String note, bool value, ValueChanged<bool> onChanged) =>
      GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => onChanged(!value),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(label,
                        style: const TextStyle(
                            color: kCream, fontSize: 14, fontWeight: FontWeight.w800)),
                    if (note.isNotEmpty) ...<Widget>[
                      const SizedBox(height: 2),
                      Text(note,
                          style: TextStyle(color: white(0.42), fontSize: 11.5, height: 1.35)),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 14),
              // Hand-rolled rather than a SwitchListTile: the Material switch has
              // had its colour parameters renamed twice across Flutter 3.x, and
              // this one builds on every version.
              AnimatedContainer(
                duration: const Duration(milliseconds: 170),
                curve: Curves.easeOut,
                width: 50,
                height: 29,
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: value ? kGold : white(0.16),
                  borderRadius: BorderRadius.circular(15),
                  boxShadow: value
                      ? <BoxShadow>[BoxShadow(color: gold(0.45), blurRadius: 12)]
                      : null,
                ),
                child: AnimatedAlign(
                  duration: const Duration(milliseconds: 170),
                  curve: Curves.easeOutBack,
                  alignment: value ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    width: 23,
                    height: 23,
                    decoration: const BoxDecoration(
                        color: kCream, shape: BoxShape.circle),
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
    double lo,
    double hi,
    ValueChanged<double> onChanged,
  ) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('$label — ${value.round()}',
              style: TextStyle(
                  color: white(0.5), fontSize: 12, fontWeight: FontWeight.w700)),
          SliderTheme(
            data: SliderThemeData(
              activeTrackColor: kGold,
              inactiveTrackColor: white(0.14),
              thumbColor: kCream,
              overlayColor: gold(0.18),
              trackHeight: 5,
            ),
            child: Slider(
              value: value.clamp(lo, hi).toDouble(),
              min: lo,
              max: hi,
              divisions: (hi - lo).round(),
              onChanged: onChanged,
            ),
          ),
        ],
      );
}

/// The sweet-shop backdrop: a warm purple wash with a soft light at the top.
class _Background extends StatelessWidget {
  const _Background();

  @override
  Widget build(BuildContext context) => const DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: <Color>[kBgTop, kBgMid, kBgDeep],
            stops: <double>[0, 0.45, 1],
          ),
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: Alignment(0, -0.85),
              radius: 1.0,
              colors: <Color>[Color(0x558A5CE0), Color(0x008A5CE0)],
            ),
          ),
          child: SizedBox.expand(),
        ),
      );
}
