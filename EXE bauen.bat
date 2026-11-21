@echo off
rem Knopf zum Bauen: Doppelklick erzeugt build\ZombieShooter.exe jedes Mal neu.
title Zombie-Shooter: EXE bauen
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0build.ps1"
set RC=%errorlevel%
echo.
if not "%RC%"=="0" (
    echo Der Bau ist fehlgeschlagen. Die Meldung steht oben.
) else (
    echo Die EXE liegt im Ordner "build". Der Ordner wird jetzt geoeffnet.
    start "" explorer "%~dp0build"
)
echo.
pause
