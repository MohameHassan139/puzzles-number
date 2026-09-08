@echo off
setlocal
cd /d "%~dp0"

echo ============================================
echo   Removing files that are not part of the
echo   project but sit inside its folder.
echo ============================================
echo.

if exist "_setup_backup" (
  rmdir /s /q "_setup_backup"
  echo   removed  _setup_backup\        ^(left behind by an interrupted setup^)
)

rem The desktop app saves files sent in chat into "Claude outputs". Loose copies
rem of lib\src\*.dart there cannot resolve their imports, so the analyzer reports
rem hundreds of errors about code the app never builds. The real files live in
rem lib\src - these are duplicates.
if exist "Claude outputs\ai.dart"        del /q "Claude outputs\ai.dart"        && echo   removed  "Claude outputs\ai.dart"
if exist "Claude outputs\model.dart"     del /q "Claude outputs\model.dart"     && echo   removed  "Claude outputs\model.dart"
if exist "Claude outputs\scoring.dart"   del /q "Claude outputs\scoring.dart"   && echo   removed  "Claude outputs\scoring.dart"
if exist "Claude outputs\deck.dart"      del /q "Claude outputs\deck.dart"      && echo   removed  "Claude outputs\deck.dart"
if exist "Claude outputs\theme.dart"     del /q "Claude outputs\theme.dart"     && echo   removed  "Claude outputs\theme.dart"
if exist "Claude outputs\effects.dart"   del /q "Claude outputs\effects.dart"   && echo   removed  "Claude outputs\effects.dart"
if exist "Claude outputs\painters.dart"  del /q "Claude outputs\painters.dart"  && echo   removed  "Claude outputs\painters.dart"
if exist "Claude outputs\widgets.dart"   del /q "Claude outputs\widgets.dart"   && echo   removed  "Claude outputs\widgets.dart"
if exist "Claude outputs\game_page.dart" del /q "Claude outputs\game_page.dart" && echo   removed  "Claude outputs\game_page.dart"
if exist "Claude outputs\main.dart"      del /q "Claude outputs\main.dart"      && echo   removed  "Claude outputs\main.dart"

echo.
echo   README.md copies and anything else in "Claude outputs" were left alone.
echo   analysis_options.yaml also excludes that folder, so future downloads
echo   there cannot break the analyzer again.
echo.
echo Now run:  flutter analyze
echo.
pause
