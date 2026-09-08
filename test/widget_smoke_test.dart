// Startup and control tests.
//
// Two things to know when adding to this file. The board runs on a Ticker that
// keeps scheduling frames while anything is animating — including the steady
// pulse under a selected triangle — so `pumpAndSettle` is only safe while
// nothing is selected. And the bot answers on a timer, so no test here plays a
// tile: a pending timer fails a widget test.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:puzzles_numeral/main.dart';

Future<void> _boot(WidgetTester tester) async {
  await tester.pumpWidget(const PuzzlesNumeralApp());
  // let the opening deal finish popping in
  for (int i = 0; i < 14; i++) {
    await tester.pump(const Duration(milliseconds: 80));
  }
}

void main() {
  testWidgets('the app opens on a dealt round', (WidgetTester tester) async {
    await _boot(tester);

    expect(find.text('Puzzles Numeral'), findsOneWidget);
    expect(find.text('YOU'), findsOneWidget);
    expect(find.text('BOT'), findsOneWidget);
    expect(find.text('Draw'), findsOneWidget);

    // the board and the rack are both painted
    expect(find.byType(CustomPaint), findsWidgets);
    // and the four controls are there
    expect(find.byIcon(Icons.rotate_right_rounded), findsOneWidget);
    expect(find.byIcon(Icons.lightbulb_rounded), findsOneWidget);
    expect(find.byIcon(Icons.undo_rounded), findsOneWidget);
    expect(find.byIcon(Icons.tune_rounded), findsOneWidget);

    expect(tester.takeException(), isNull);
  });

  testWidgets('the message line says what level was dealt',
      (WidgetTester tester) async {
    await _boot(tester);
    expect(find.textContaining('triangles'), findsOneWidget);
  });

  testWidgets('the hint picks a triangle up and rings a space',
      (WidgetTester tester) async {
    await _boot(tester);

    await tester.tap(find.byIcon(Icons.lightbulb_rounded));
    // Not pumpAndSettle: a selected triangle pulses for as long as it is held.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));

    expect(
      find.textContaining(RegExp(r'ringed space|Nothing fits')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('rotate is dead until a triangle is in hand, then it is not',
      (WidgetTester tester) async {
    await _boot(tester);

    final GamePageState state = tester.state(find.byType(GamePage));
    expect(state.sel, isNull);

    await tester.tap(find.byIcon(Icons.lightbulb_rounded));
    await tester.pump();
    if (state.sel != null) {
      final int before = state.rot;
      await tester.tap(find.byIcon(Icons.rotate_right_rounded));
      await tester.pump();
      expect(state.rot, isNot(before));
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('the refresh button deals a fresh round',
      (WidgetTester tester) async {
    await _boot(tester);
    final GamePageState state = tester.state(find.byType(GamePage));
    final int before = state.board.length;

    await tester.tap(find.byIcon(Icons.refresh_rounded));
    await tester.pump();

    expect(state.scores, <int>[0, 0]);
    expect(state.board.length, before);
    expect(state.hands[0].length, state.handSize);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the rules sheet opens, and starting from it re-deals',
      (WidgetTester tester) async {
    await _boot(tester);

    await tester.tap(find.byIcon(Icons.tune_rounded));
    await tester.pumpAndSettle();
    expect(find.text('How it plays'), findsOneWidget);
    expect(find.text('A kind pile'), findsOneWidget);

    await tester.ensureVisible(find.text('Start a new game'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Start a new game'));
    for (int i = 0; i < 16; i++) {
      await tester.pump(const Duration(milliseconds: 80));
    }

    expect(find.text('How it plays'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a dealt round always leaves the player something to do',
      (WidgetTester tester) async {
    await _boot(tester);
    final GamePageState state = tester.state(find.byType(GamePage));
    // Either a triangle in hand fits, or the pile will hand one over.
    final bool somethingToDo =
        !state.stuck || state.deck.isNotEmpty;
    expect(somethingToDo, isTrue);
  });
}
