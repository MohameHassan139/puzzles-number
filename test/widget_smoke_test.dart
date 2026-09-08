// Startup tests: the app must build, lay out and paint a fresh round without
// throwing, and the controls must be wired up.
//
// Nothing here taps the board or plays a tile: the bot answers on a 650 ms
// timer, and a widget test fails if a timer is still pending when it ends.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:puzzles_numeral/main.dart';

void main() {
  testWidgets('the app starts on a dealt round', (WidgetTester tester) async {
    await tester.pumpWidget(const PuzzlesNumeralApp());
    await tester.pump();

    expect(find.text('Puzzles Numeral'), findsOneWidget);
    expect(find.text('New game'), findsOneWidget);
    expect(find.text('Rotate'), findsOneWidget);
    expect(find.text('Hint'), findsOneWidget);
    expect(find.text('Undo'), findsOneWidget);

    // The board and the rack tiles are painted.
    expect(find.byType(CustomPaint), findsWidgets);

    // It is the player's turn, so the pile line is showing.
    expect(find.textContaining('Pile ·'), findsOneWidget);
    expect(find.textContaining('You ·'), findsOneWidget);
  });

  testWidgets('the hint button names a playable space', (WidgetTester tester) async {
    await tester.pumpWidget(const PuzzlesNumeralApp());
    await tester.pump();

    await tester.tap(find.text('Hint'));
    await tester.pump();

    // Either it found a move, or it honestly says there is none. Both are fine;
    // what matters is that asking never throws.
    expect(
      find.textContaining(RegExp(r'ringed space|Nothing in your hand')),
      findsOneWidget,
    );
  });

  testWidgets('New game deals a fresh round without throwing',
      (WidgetTester tester) async {
    await tester.pumpWidget(const PuzzlesNumeralApp());
    await tester.pump();

    await tester.tap(find.text('New game'));
    await tester.pump();

    expect(find.textContaining('triangles in play'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the rules sheet opens and closes', (WidgetTester tester) async {
    await tester.pumpWidget(const PuzzlesNumeralApp());
    await tester.pump();

    await tester.tap(find.byIcon(Icons.tune));
    await tester.pumpAndSettle();
    expect(find.text('How it plays'), findsOneWidget);

    await tester.ensureVisible(find.text('Start a new game'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Start a new game'));
    await tester.pumpAndSettle();
    expect(find.text('How it plays'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
