@echo off
setlocal enabledelayedexpansion
cd /d "%~dp0"

echo ============================================
echo   PUZZLES NUMERAL - project setup
echo ============================================
echo.

where flutter >nul 2>nul
if errorlevel 1 (
  echo [X] Flutter is not on your PATH.
  echo     Install it from https://docs.flutter.dev/get-started/install/windows
  echo     then open a NEW terminal and run this file again.
  pause
  exit /b 1
)

echo [1/6] Backing up the game source...
if not exist _setup_backup mkdir _setup_backup
copy /Y lib\main.dart            _setup_backup\main.dart            >nul
copy /Y pubspec.yaml             _setup_backup\pubspec.yaml         >nul
copy /Y analysis_options.yaml    _setup_backup\analysis_options.yaml>nul
if exist README.md copy /Y README.md _setup_backup\README.md >nul

echo [2/6] Generating the platform folders with YOUR Flutter version...
call flutter create --project-name puzzles_numeral --platforms=android,ios,web,windows .
if errorlevel 1 (
  echo [X] flutter create failed. See the message above.
  pause
  exit /b 1
)

echo [3/6] Restoring the game source over the template...
copy /Y _setup_backup\main.dart            lib\main.dart          >nul
copy /Y _setup_backup\pubspec.yaml         pubspec.yaml           >nul
copy /Y _setup_backup\analysis_options.yaml analysis_options.yaml >nul
if exist _setup_backup\README.md copy /Y _setup_backup\README.md README.md >nul
rem The template drops in a counter-app test that does not belong to this game.
if exist test\widget_test.dart del /Q test\widget_test.dart
rmdir /s /q _setup_backup

echo [4/6] Fetching packages...
call flutter pub get
if errorlevel 1 (
  echo [X] flutter pub get failed.
  pause
  exit /b 1
)

echo [5/6] Analysing...
call flutter analyze

echo [6/6] Running the tests...
call flutter test

echo.
echo ============================================
echo   Done. Start the game with one of:
echo      flutter run -d windows
echo      flutter run -d chrome
echo      flutter run              (a connected phone or emulator)
echo ============================================
pause
