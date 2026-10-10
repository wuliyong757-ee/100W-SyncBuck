@echo off
rem ---------------------------------------------------------------
rem  Rebuild the tablet study pack on the Desktop.
rem
rem  Produces (names are Chinese, but they are created by Python,
rem  NOT written in here -- a batch file holding Chinese text gets
rem  mangled by the console code page and makes a garbage folder):
rem
rem    Desktop\<pack>\        the html pages + index.html
rem    Desktop\<pack>.zip     the same thing, zipped
rem
rem  Just double-click this file. Edit the .md docs, double-click
rem  again, and both are rebuilt.
rem ---------------------------------------------------------------
cd /d "%~dp0"

where python >nul 2>nul
if errorlevel 1 (
  echo.
  echo   [FAILED] "python" is not on PATH.
  echo   Install Python 3, or edit this file to use the full path.
  echo.
  pause
  exit /b 1
)

rem No output path on purpose -- md2html.py defaults to the Desktop.
python "%~dp0md2html.py" --bundle "%~dp0.."

if errorlevel 1 (
  echo.
  echo   [FAILED] see the message above.
) else (
  echo.
  echo   [OK] Rebuilt. Details are printed above.
  echo        Send the .zip to your tablet, unzip, open index.html first.
)
echo.
pause
