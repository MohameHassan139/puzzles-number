@echo off
setlocal
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
if exist "_setup_backup" rmdir /s /q "_setup_backup"
mkdir "_setup_backup"
xcopy /E /I /Y /Q lib  "_setup_backup\lib"  >nul
xcopy /E /I /Y /Q test "_setup_backup\test" >nul
copy /Y pubspec.yaml          "_setup_backup\" >nul
copy /Y analysis_options.yaml "_setup_backup\" >nul
if exist README.md copy /Y README.md "_setup_backup\" >nul

echo [2/6] Generating the platform folders with YOUR Flutter version...
rem Flutter can exit non-zero here purely because its own version check
rem ("git fetch --tags") could not reach github. The project is still created,
rem so the exit code is deliberately not treated as fatal - step 4 checks
rem whether the work actually landed.
call flutter create --project-name puzzles_numeral --platforms=android,ios,web,windows .

echo [3/6] Restoring the game source over the template...
rem flutter create overwrites lib\main.dart with its counter app and drops a
rem test\widget_test.dart that refers to a class called MyApp. Copying the whole
rem backup back puts the real game - and the real tests - on top of both.
xcopy /E /I /Y /Q "_setup_backup\lib"  lib  >nul
xcopy /E /I /Y /Q "_setup_backup\test" test >nul
copy /Y "_setup_backup\pubspec.yaml"          pubspec.yaml          >nul
copy /Y "_setup_backup\analysis_options.yaml" analysis_options.yaml >nul
if exist "_setup_backup\README.md" copy /Y "_setup_backup\README.md" README.md >nul
rmdir /s /q "_setup_backup"

echo [4/6] Checking the project is complete...
if not exist "lib\main.dart"      goto :broken
if not exist "lib\src\model.dart" goto :broken
if not exist "pubspec.yaml"       goto :broken
if not exist "web"                echo   [!] no web\ folder - flutter create may not have finished
echo   ok

echo [5/6] Fetching packages...
call flutter pub get
if errorlevel 1 (
  echo [X] flutter pub get failed.
  pause
  exit /b 1
)

echo [6/6] Analysing and testing...
call flutter analyze
call flutter test

echo.
echo ============================================
echo   Done. Start the game with one of:
echo      flutter run -d windows
echo      flutter run -d chrome
echo      flutter run              ^(a connected phone or emulator^)
echo ============================================
pause
exit /b 0

:broken
echo.
echo [X] The project is missing files that should be there.
echo     Nothing was deleted - check the folder and run this again.
pause
exit /b 1
