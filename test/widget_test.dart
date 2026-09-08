// `flutter create` drops a counter-app test in at this path, and it refers to a
// class called MyApp that this project does not have — which is where the
// `The name 'MyApp' isn't a class` error came from.
//
// Rather than leave an empty file where the template will keep landing, this
// checks the things nothing else does: that the one public import really does
// expose the whole game, and that the tuning tables are internally consistent.

import 'package:flutter_test/flutter_test.dart';
import 'package:puzzles_numeral/main.dart';

void main() {
  test('one import exposes the whole game', () {
    // Model, scoring, deck, ai, theme, effects, painters, widgets, page.
    expect(const TCorner(2, 4).isJoker, isFalse);
    expect(kTouchPoints.length, 4);
    expect(deckPlan(Level.normal, 7, 5).total, greaterThan(0));
    expect(makeDeck(seed: 1, jokers: 2, regulars: 20).length, 22);
    expect(botLevelShort(BotLevel.hard), isNotEmpty);
    expect(kCandies.length, kColors.length);
    expect(popScale(1), 1);
    expect(const PuzzlesNumeralApp(), isNotNull);
    expect(const GamePage(), isNotNull);
  });

  test('the level table is internally consistent', () {
    for (final Level level in Level.values) {
      final LevelPlan plan = kLevels[level]!;
      expect(plan.minTiles, lessThanOrEqualTo(plan.maxTiles));
      expect(plan.jokerShare, inInclusiveRange(0.0, 1.0));
      expect(plan.short, isNotEmpty);
      expect(kRoots[plan.root], isNotNull);
      // Every level must deal enough to fill both hands with room to spare.
      for (int handSize = 3; handSize <= 9; handSize++) {
        final DeckPlan deal = deckPlan(level, 7, handSize);
        expect(deal.total, greaterThanOrEqualTo(handSize * 2 + 8));
        expect(deal.regulars + deal.jokers, deal.total);
        expect(deal.regulars, greaterThan(0));
      }
    }
  });

  test('the scoring table cannot pay for a placement that touches nothing', () {
    expect(kTouchPoints[0], 0);
    for (int i = 1; i < kTouchPoints.length; i++) {
      expect(kTouchPoints[i], greaterThan(kTouchPoints[i - 1]));
    }
    expect(kCircleBonus, greaterThan(kTouchPoints.last - kTouchPoints[2]));
  });
}
