#!/usr/bin/env bash
# PUZZLES NUMERAL — project setup (macOS / Linux).
set -uo pipefail
cd "$(dirname "$0")"

if ! command -v flutter >/dev/null 2>&1; then
  echo "Flutter is not on your PATH. Install it from https://docs.flutter.dev/get-started/install"
  exit 1
fi

echo "[1/6] Backing up the game source..."
rm -rf _setup_backup && mkdir -p _setup_backup
cp -R lib test pubspec.yaml analysis_options.yaml _setup_backup/
[ -f README.md ] && cp README.md _setup_backup/

echo "[2/6] Generating the platform folders with YOUR Flutter version..."
# A non-zero exit here is often just Flutter's own version check failing to
# reach github; step 4 checks whether the work actually landed.
flutter create --project-name puzzles_numeral --platforms=android,ios,web,linux,macos . || true

echo "[3/6] Restoring the game source over the template..."
cp -R _setup_backup/lib/. lib/
cp -R _setup_backup/test/. test/
cp _setup_backup/pubspec.yaml _setup_backup/analysis_options.yaml .
[ -f _setup_backup/README.md ] && cp _setup_backup/README.md .
rm -rf _setup_backup

echo "[4/6] Checking the project is complete..."
for f in lib/main.dart lib/src/model.dart pubspec.yaml; do
  [ -f "$f" ] || { echo "[X] missing $f — nothing was deleted, check the folder"; exit 1; }
done
echo "  ok"

echo "[5/6] Fetching packages..."
flutter pub get || exit 1

echo "[6/6] Analysing and testing..."
flutter analyze
flutter test

echo
echo "Done. Start the game with:  flutter run -d chrome   (or -d macos, -d linux)"
