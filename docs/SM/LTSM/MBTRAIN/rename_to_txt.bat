@echo off
cd /d "%~dp0"
ren *.sv *.txt
echo Renamed all .sv files to .txt in %CD%
pause
