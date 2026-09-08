// PUZZLES NUMERAL
//
// A digital build of the wooden triangle-matching game: every triangle carries
// a coloured, numbered wedge in each of its three corners, and a triangle may
// only be laid against one already on the table when the corners they share
// agree.
//
// The game is split across lib/src; this file wires it together and re-exports
// the lot, so `package:puzzles_numeral/main.dart` remains the one import
// anything — including the tests — needs.

import 'package:flutter/material.dart';

import 'src/game_page.dart';
import 'src/theme.dart';

export 'src/ai.dart';
export 'src/deck.dart';
export 'src/effects.dart';
export 'src/game_page.dart';
export 'src/model.dart';
export 'src/painters.dart';
export 'src/scoring.dart';
export 'src/theme.dart';
export 'src/widgets.dart';

void main() => runApp(const PuzzlesNumeralApp());

class PuzzlesNumeralApp extends StatelessWidget {
  const PuzzlesNumeralApp({super.key});

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = ColorScheme.fromSeed(
      seedColor: kGold,
      brightness: Brightness.dark,
    ).copyWith(surface: kBgDeep);

    return MaterialApp(
      title: 'Puzzles Numeral',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        colorScheme: scheme,
        scaffoldBackgroundColor: kBgDeep,
        // One family for the whole game so nothing shifts weight between the
        // head-up display and the board.
        textTheme: Typography.whiteMountainView.apply(
          bodyColor: kCream,
          displayColor: kCream,
        ),
      ),
      home: const GamePage(),
    );
  }
}
