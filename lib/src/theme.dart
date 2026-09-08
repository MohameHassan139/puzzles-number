// The candy palette.
//
// Colours are written as plain 0xAARRGGBB literals and built with the
// `Color(int)` constructor only, so nothing here depends on an API that has
// been renamed across Flutter 3.x (withOpacity / withValues).

import 'package:flutter/material.dart';

// Background and furniture.
const Color kBgTop = Color(0xFF5B3AA6);
const Color kBgMid = Color(0xFF3A2276);
const Color kBgDeep = Color(0xFF1B1140);
const Color kGlow = Color(0xFF8A5CE0);

const Color kInk = Color(0xFF2A1750);
const Color kCream = Color(0xFFFFFBF2);
const Color kCreamWarm = Color(0xFFFFEFD6);
const Color kGold = Color(0xFFFFD452);
const Color kGoldDeep = Color(0xFFE09A12);
const Color kGoldInk = Color(0xFF4A2E00);

const Color kTrayTop = Color(0xFF7B4BC9);
const Color kTrayBottom = Color(0xFF4B2A8F);

const int _rgbWhite = 0xFFFFFF;
const int _rgbBlack = 0x000000;
const int _rgbCream = 0xFFFBF2;
const int _rgbGold = 0xFFD452;
const int _rgbInk = 0x2A1750;

/// A colour channel plus an alpha, folded into one ARGB value.
Color rgba(int rgb, double alpha) {
  final int a = (alpha * 255.0).round();
  final int clamped = a < 0
      ? 0
      : a > 255
          ? 255
          : a;
  return Color((clamped << 24) | (rgb & 0xFFFFFF));
}

Color white(double a) => rgba(_rgbWhite, a);
Color black(double a) => rgba(_rgbBlack, a);
Color cream(double a) => rgba(_rgbCream, a);
Color gold(double a) => rgba(_rgbGold, a);
Color ink(double a) => rgba(_rgbInk, a);

/// One candy colour, held as plain 0xRRGGBB channels.
///
/// Ints rather than [Color] objects on purpose: fading a colour then means
/// rebuilding it from its channels, and every way of reading channels *off* a
/// Color — `.value`, `.red`, `.withOpacity` — has been deprecated at some point
/// in Flutter 3.x. Keeping the numbers means the drawing code never has to.
class Candy {
  final int light;
  final int base;
  final int dark;

  const Candy(this.light, this.base, this.dark);
}

const List<Candy> kCandies = <Candy>[
  Candy(0xFF9DAF, 0xFF4D6D, 0xC81E43), // strawberry
  Candy(0x8FD3FF, 0x2E9BFF, 0x0B62C4), // blueberry
  Candy(0x95F3BE, 0x2ECC71, 0x0F9350), // apple
  Candy(0xFFE18C, 0xFFB627, 0xD07C00), // honey
  Candy(0xDCB4FF, 0x9B5DE5, 0x6A2FB0), // grape
];

// Plain RGB twins of the furniture colours, for the same reason.
const int rgbInk = 0x2A1750;
const int rgbGold = 0xFFD452;
const int rgbGoldDeep = 0xE09A12;
const int rgbWhite = 0xFFFFFF;
const int rgbCream = 0xFFFBF2;
const int rgbYou = 0x37E1B0;
const int rgbFoe = 0xFF7BA8;

/// Kept under the old name so the rest of the game — and the tests — can still
/// ask for "the colour of corner n".
const List<Color> kColors = <Color>[
  Color(0xFFFF4D6D),
  Color(0xFF2E9BFF),
  Color(0xFF2ECC71),
  Color(0xFFFFB627),
  Color(0xFF9B5DE5),
];

const List<String> kColorNames = <String>[
  'Strawberry',
  'Blueberry',
  'Apple',
  'Honey',
  'Grape',
];

/// The two player colours, for the HUD and for the trail a tile leaves.
const Color kYouColor = Color(0xFF37E1B0);
const Color kFoeColor = Color(0xFFFF7BA8);


TextStyle display(double size, {Color color = kCream, FontWeight w = FontWeight.w800}) =>
    TextStyle(
      color: color,
      fontSize: size,
      fontWeight: w,
      letterSpacing: -0.2,
      height: 1.15,
    );

/// The soft double shadow that lifts every card off the background.
List<BoxShadow> lift({double y = 6, double blur = 18, double alpha = 0.32}) =>
    <BoxShadow>[
      BoxShadow(color: black(alpha), blurRadius: blur, offset: Offset(0, y)),
    ];
