# Puzzles Numeral

A Flutter build of the wooden triangle-matching game in the video: every
triangle carries a coloured, numbered wedge in each of its three corners, and a
triangle may only be laid against one already on the table when the corners
they share agree. Play is against a bot, on four levels, with four matching
rules.

---

## Run it (first time)

You need Flutter on your PATH — <https://docs.flutter.dev/get-started/install>.
Check with `flutter --version`; anything from Flutter 3.10 onward works.

**Windows — double-click `setup.bat`.**
macOS or Linux — run `./setup.sh`.

The script generates the `android/`, `ios/`, `web/` and `windows/` folders using
*your* Flutter version, restores the game source over the template, then runs
`flutter pub get`, `flutter analyze` and `flutter test`.

Generating the platform folders locally rather than shipping them is deliberate:
those files are tied to the exact Flutter, Gradle and Xcode versions on your
machine, and a mismatched set is the single most common source of build errors.

### Then, any time

```
flutter run -d windows     # desktop app
flutter run -d chrome      # in the browser
flutter run                # a connected phone or emulator
```

### Or do it by hand instead of the script

```
flutter create --project-name puzzles_numeral --platforms=android,ios,web,windows .
git checkout lib/main.dart pubspec.yaml     # or copy them back from a backup
del test\widget_test.dart                   # the template's counter test
flutter pub get
flutter run
```

`flutter create` overwrites `lib/main.dart` and `pubspec.yaml` with its template,
which is why the script backs both up first. Keep a copy before running it.

---

## How the game plays

- **The opening.** The board opens on a *root* — a small arrangement laid out
  before anyone plays, sized by the level, with jokers scattered through it. It
  is legal by construction: the root is built by labelling lattice vertices and
  reading each triangle's three labels back off, so there is nothing to search
  for. Roots are re-laid up to 40 times until one offers the opening player a
  real choice rather than a single forced move.
- **A turn.** Tap a triangle in your rack to pick it up, tap again to rotate.
  Bright spaces on the board fit as-is; faint spaces fit after a rotation and
  will turn for you. Where two triangles meet they share **two** corners, and
  **both** pairs must match.
- **Jokers** carry all five colours and fit against anything.
- **Stuck?** Draw one triangle — never twice in a row. If the one you drew fits,
  play it straight away rather than losing the turn.
- **Scoring** rewards tucking triangles in rather than trailing across the
  table: leaning on one triangle is 1 point, two is 3, three is 6. Six triangles
  meet at every inner vertex, so closing one of those circles is worth 5 more,
  and a single triangle can close two at once.
- **Winning.** Going out — placing your last triangle — *ends* the game but does
  not win it. The higher score wins, minus 2 for every triangle still in your
  hand. So go out when you are ahead, and keep scoring while you are behind.

Settings (the dial icon): matching rule, hand size, corner types per round,
shuffle seed, level and bot skill. A seed replays a round exactly.

**Corner types.** All five colours and numbers 1–5 exist, but one round only
deals 8 of the 25 possible corner types. That is what makes an exact
colour-and-number match findable; past about 10, hands grow faster than they
empty and nobody ever goes out.

---

## Layout

```
lib/main.dart               the whole game — model, rules, scoring, bot, painters
test/game_logic_test.dart   rules-engine tests
test/widget_smoke_test.dart startup and control tests
pubspec.yaml                no third-party packages at all
setup.bat / setup.sh        one-shot project generation
```

`lib/main.dart` is deliberately one file and deliberately dependency-free:
everything it needs ships with the Flutter SDK, so `flutter pub get` cannot fail
on a version conflict.

### On not tripping the analyzer

`analysis_options.yaml` leaves out the usual
`include: package:flutter_lints/flutter.yaml`. Those are *style* lints, and
`flutter analyze` exits non-zero on them — which makes a perfectly healthy build
look broken. Add it back whenever you like; the note in that file says how.

The UI code also sticks to Flutter APIs that have not been renamed across 3.x.
Colours are written as plain `0xAARRGGBB` values rather than `withOpacity()` or
`withValues()`; the settings sheet uses `DropdownButton` rather than
`DropdownButtonFormField`, whose `value` parameter became `initialValue`; and
the "play against the bot" toggle is hand-rolled rather than a `SwitchListTile`,
whose colour parameters have been renamed twice. That is what keeps one source
file building on both an older and a current SDK.

---

## What was checked

The rules engine was ported line-for-line and simulated over **240 complete
games** — all four levels × four matching rules × three bot skills × five seeds
— plus a sweep of every hand size 3–9 against corner-type counts 3, 8, 12 and 25.
Across all of them:

- no illegal placement was ever made,
- every game terminated,
- every root was legal on every matching rule,
- no lattice vertex ever held more than the six triangles that fit there,
- every root offered the opening player at least two playable triangles.

`test/` re-checks all of that in Dart, plus corner matching in each mode, the
mutuality of neighbours, rotation, the touch-point and circle-closing scores,
the leftover penalty, and that the app starts, hints, re-deals and opens its
rules sheet without throwing.
