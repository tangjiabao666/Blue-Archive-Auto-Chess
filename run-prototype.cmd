@echo off
setlocal EnableExtensions DisableDelayedExpansion
rem These sentinels catch a source-only checkout, not an incomplete asset import.
for %%R in (data/character-presentations.json data/character_skills.json shaders/native_body_layer4.gdshader) do (
  if not exist "%~dp0%%R" (
    >&2 echo Missing runtime input: %%R
    >&2 echo See docs/ASSET_IMPORT.zh-CN.md to prepare authorized local inputs.
    >&2 echo This early guard is not full asset validation.
    exit /b 2
  )
)
rem Use GODOT_EXE, the adjacent executable, or PATH; ignore an inherited GODOT.
set "GODOT="
if defined GODOT_EXE set "GODOT=%GODOT_EXE%"
if not defined GODOT if exist "%~dp0Godot.exe" set "GODOT=%~dp0Godot.exe"
if not defined GODOT set "GODOT=godot"
"%GODOT%" --version >nul 2>&1
if errorlevel 1 (
  >&2 echo Godot executable not found or version check failed. Install Godot 4.6.3 stable or set GODOT_EXE to its full executable path.
  exit /b %errorlevel%
)
set "GODOT_VERSION="
set "GODOT_SUPPORTED="
for /f "delims=" %%V in ('""%GODOT%" --version"') do set "GODOT_VERSION=%%V"
for /f "tokens=1-4 delims=." %%A in ("%GODOT_VERSION%") do if "%%A.%%B.%%C.%%D"=="4.6.3.stable" set "GODOT_SUPPORTED=1"
if not defined GODOT_SUPPORTED (
  >&2 echo Expected Godot 4.6.3 stable; found: "%GODOT_VERSION%".
  exit /b 2
)
"%GODOT%" --headless --editor --path "%~dp0." --import
if errorlevel 1 exit /b %errorlevel%
"%GODOT%" --path "%~dp0." %*
exit /b %errorlevel%
