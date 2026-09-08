#!/usr/bin/env bash
# PUZZLES NUMERAL — project setup (macOS / Linux).
set -euo pipefail
cd "$(dirname "$0")"

if ! command -v flutter >/dev/null 2>&1; then
  echo "Flutter is not on your PATH. Install it from https://docs.flutter.dev/get-started/install"
  exit 1
fi

echo "[1/6] Backing up the game source..."
mkdir -p _setup_backup
cp lib/main.dart pubspec.yaml analysis_options.yaml _setup_backup/
[ -f README.md ] && cp README.md _setup_backup/ || true

echo "[2/6] Generating the platform folders with YOUR Flutter version..."
flutter create --project-name puzzles_numeral --platforms=android,ios,web,linux,macos .

echo "[3/6] Restoring the game source over the template..."
cp _setup_backup/main.dart lib/main.dart
cp _setup_backup/pubspec.yaml pubspec.yaml
cp _setup_backup/analysis_options.yaml analysis_options.yaml
[ -f _setup_backup/README.md ] && cp _setup_backup/README.md README.md || true
# The template drops in a counter-app test that does not belong to this game.
rm -f test/widget_test.dart
rm -rf _setup_backup

echo "[4/6] Fetching packages..."
flutter pub get

echo "[5/6] Analysing..."
flutter analyze

echo "[6/6] Running the tests..."
flutter test

echo
echo "Done. Start the game with:  flutter run -d chrome   (or -d macos, -d linux)"
