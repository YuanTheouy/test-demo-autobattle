@echo off
setlocal
set "SKY_GODOT=%USERPROFILE%\Downloads\Godot_v4.6.2-stable_win64.exe\Godot_v4.6.2-stable_win64.exe"
if exist "%SKY_GODOT%" (
  start "" "%SKY_GODOT%" --path "%~dp0."
  exit /b
)
where godot >nul 2>nul
if not errorlevel 1 (
  start "" godot --path "%~dp0."
  exit /b
)
echo Please open project.godot in Godot 4.6 and press F5.
pause
