# Puzzles Numeral

A Flutter build of the wooden triangle-matching game in the video: every
triangle carries a coloured, numbered wedge in each of its three corners, and a
triangle may only be laid against one already on the table when the corners
they share agree.

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

---

## How the game plays

- **The opening.** The board opens on a *root* — a small arrangement laid out
  before anyone plays, sized by the level, with jokers scattered through it. It
  is legal by construction: the root is built by labelling lattice vertices and
  reading each triangle's three labels back off, so there is nothing to search
  for. Roots are re-laid up to 40 times until one offers the opening player a
  real choice rather than a single forced move.
- **A turn.** Tap a triangle in the tray to pick it up, tap again to turn it.
  Bright spaces fit as it stands; faint spaces fit after a turn, and the game
  will turn it for you. Where two triangles meet they share **two** corners, and
  **both** pairs must match.
- **Jokers** carry every colour and fit against anything.
- **Stuck?** Draw. See *A kind pile* below.
- **Scoring** rewards tucking triangles in rather than trailing across the
  table: leaning on one triangle is 1 point, two is 3, three is 6. Six triangles
  meet at every inner vertex, so closing one of those circles is worth 5 more,
  and a single triangle can close two at once.
- **Winning.** Going out — placing your last triangle — *ends* the game but does
  not win it. The higher score wins, minus 2 for every triangle still in your
  hand. So go out when you are ahead, and keep scoring while you are behind.

---

## What changed in this pass

### A kind pile — nobody ever wastes a turn

The old rule was harsh: no match anywhere in your hand meant you drew one
triangle, it probably did not fit either, and your turn was simply gone.

Now, when a player has nothing to play, the pile is searched for a triangle that
*does* have a legal home, and that is the one handed over. If the whole pile is
dead against the board, the triangle arrives with joker corners instead, which
fit anywhere. Nothing about this shows on screen — it reads as a lucky draw,
because that is exactly what it is.

**It runs for you and for the bot through the same function call**, so neither
side is being helped more than the other. Over 64 simulated games covering every
level and every matching rule, **zero** turns were wasted while the pile still
had triangles in it — against a stream of them before.

It can be switched off under *A kind pile* in the settings, which restores the
old draw-and-pass rule exactly.

### An opponent that thinks about what it leaves behind

The sharp bot no longer just grabs the biggest number. It plays the move out,
then reads the position it has created:

- **a vertex left sitting on five triangles is five free points** for whoever
  moves next, so it avoids leaving them;
- **a board with fewer open spaces has fewer answers in it**, so it tightens;
- between two moves worth the same it spends the triangle with the fewest other
  homes, and keeps its jokers back for something that scores.

It never looks at your hand. That would be cheating, and it would feel like it —
it reads the *board*, which is information you have too.

Measured over 305 identical positions, the sharp bot leaves **62** vertices
sitting on five where the old "keeps it tight" bot leaves **102** — 39% fewer
free circles handed over — while taking exactly the same number of points for
itself. Head to head it wins about **9 games in 10** against the wandering bot.

Three settings remain: *Easy* wanders, *Normal* tightens, *Sharp* thinks ahead.

### The look

Rebuilt as a sweet-shop board: rounded glossy triangles on a warm purple wash,
wedges shaded through three tones so they read as sugar rather than pie chart,
and a gold pulse under every space a triangle can go.

Everything moves now. A triangle drops into place with an overshoot bounce; a
ring pushes out from where it landed; each corner that matched flashes white; a
closed circle throws a gold burst and thirteen tumbling sparks; the score floats
up and fades. Scores in the head-up display roll to their new value instead of
jumping. Buttons squash under the thumb. The whole round deals itself in with a
staggered pop. There is a small haptic tap on selection and a heavier one when a
circle closes.

All of it runs off **one ticker that stops when nothing is moving**, so an idle
game costs nothing.

### Speed

The engine used to test all 231 cells of the lattice for every question it
asked. But a placement is only ever legal against a triangle already on the
table, so the real candidate set is the *frontier* — the few dozen empty cells
touching something. Scoring also recomputed the whole vertex tally per candidate
move; it now takes one tally per turn.

The two together make the rules engine about **6× faster**, which is what pays
for the animation. `test/rules_upgrade_test.dart` checks the fast scan returns
character-for-character what the old exhaustive sweep returned, over 400+
queries, so the speed is not bought with a behaviour change.

---

## Layout

```
lib/main.dart               app entry; re-exports everything below
lib/src/model.dart          tiles, geometry, the matching rule, the frontier
lib/src/scoring.dart        vertices, circles, the score
lib/src/deck.dart           levels, the pile, the opening root
lib/src/ai.dart             move generation, the opponent, the kind draw
lib/src/theme.dart          the candy palette
lib/src/effects.dart        timed visual events and spark maths
lib/src/painters.dart       the board and tray painters
lib/src/widgets.dart        buttons, player cards, panels
lib/src/game_page.dart      the screen and the turn it drives
test/                       three suites, described below
pubspec.yaml                no third-party packages at all
setup.bat / setup.sh        one-shot project generation
```

Everything the game needs ships with the Flutter SDK, so `flutter pub get`
cannot fail on a version conflict.

### On not tripping the analyzer

`analysis_options.yaml` leaves out the usual
`include: package:flutter_lints/flutter.yaml`. Those are *style* lints, and
`flutter analyze` exits non-zero on them — which makes a perfectly healthy build
look broken. Add it back whenever you like; the note in that file says how.

The UI also sticks to Flutter APIs that have not been renamed across 3.x.
Colours are carried as plain `0xRRGGBB` integers and rebuilt with the `Color(int)`
constructor, because every way of reading channels *off* a `Color` — `.value`,
`.red`, `.withOpacity` — has been deprecated at some point; the settings screen
uses tappable pills rather than `DropdownButtonFormField`, whose `value`
parameter became `initialValue`; and both toggles are hand-rolled rather than
`SwitchListTile`, whose colour parameters have been renamed twice.

---

## What was checked

The rules engine was ported line-for-line to a second implementation and
simulated. Across every level × every matching rule × every bot skill:

- no illegal placement was ever made, and every game terminated;
- every root was legal on every matching rule, and always offered the opening
  player at least two playable triangles;
- no lattice vertex ever held more than the six triangles that fit there;
- the frontier scan returned exactly what the exhaustive sweep returned;
- with the kind pile on, not one turn was wasted while the pile had cards.

`test/` re-checks all of it in Dart:

- **`game_logic_test.dart`** — corner matching in each mode, the mutuality of
  neighbours, rotation, touch-point and circle-closing scores, the leftover
  penalty, deck composition, root legality, and a bot-versus-bot game per level.
- **`rules_upgrade_test.dart`** — the fast scan against the full sweep, all four
  behaviours of the kind draw, that nobody wastes a turn with it on, and that
  the sharp bot both wins the head-to-head and gives away measurably fewer free
  circles than the bot that only tightens.
- **`widget_smoke_test.dart`** — that the app opens on a dealt round, hints,
  rotates, re-deals and opens its rules sheet without throwing.
