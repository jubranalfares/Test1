@echo off
setlocal enabledelayedexpansion
title Jarvis - iPhone Setup

echo.
echo  ===================================================
echo   JARVIS - iPhone / Handy Zugang
echo  ===================================================
echo.

REM --- Finde die lokale IP-Adresse des PCs ---
for /f "tokens=2 delims=:" %%a in ('ipconfig ^| findstr /i "IPv4"') do (
    set RAW=%%a
    set RAW=!RAW: =!
    REM Nur 192.168.x.x oder 10.x.x.x (LAN)
    echo !RAW! | findstr /r "^192\.168\." >nul && set LOCAL_IP=!RAW!
    echo !RAW! | findstr /r "^10\."       >nul && set LOCAL_IP=!RAW!
    echo !RAW! | findstr /r "^172\."      >nul && set LOCAL_IP=!RAW!
)

if not defined LOCAL_IP (
    echo [FEHLER] Keine lokale IP gefunden. Stelle sicher, dass du im WLAN bist.
    echo Gib deine IP manuell ein (ipconfig im Terminal):
    set /p LOCAL_IP=IP-Adresse:
)

echo.
echo  Deine PC-IP im Heimnetz: %LOCAL_IP%
echo.
echo  ===================================================
echo   Schritt 1: Backend starten (Docker)
echo  ===================================================
echo.

cd /d "%~dp0.."
docker compose up -d
if errorlevel 1 (
    echo [FEHLER] Docker ist nicht gestartet oder docker-compose.yml fehlt.
    echo Starte Docker Desktop und versuche es erneut.
    pause
    exit /b 1
)

echo.
echo  Backend laeuft auf http://%LOCAL_IP%:8080
echo.
echo  ===================================================
echo   Schritt 2: Flutter Web App starten
echo  ===================================================
echo.

cd /d "%~dp0..\mobile\flutter_app"

REM Pruefe ob Flutter installiert ist
flutter --version >nul 2>&1
if errorlevel 1 (
    echo [FEHLER] Flutter nicht gefunden. Stelle sicher, dass Flutter im PATH ist.
    pause
    exit /b 1
)

echo Starte Flutter Web auf Port 3000 (erreichbar im Heimnetz)...
echo.

REM Flutter Web auf allen Interfaces starten (0.0.0.0), nicht nur localhost
start "Jarvis Flutter Web" cmd /k "flutter run -d web-server --web-port 3000 --web-hostname 0.0.0.0"

timeout /t 5 /nobreak >nul

echo.
echo  ===================================================
echo   FERTIG - So verbindest du dich mit dem iPhone
echo  ===================================================
echo.
echo  1. Stelle sicher, dass dein iPhone im SELBEN WLAN ist wie dieser PC.
echo.
echo  2. Oeffne Safari auf dem iPhone und gehe zu:
echo.
echo       http://%LOCAL_IP%:3000
echo.
echo  3. Im Login-Screen:
echo       - Passwort: (dein Jarvis-Passwort aus der .env Datei)
echo       - Server-Adresse: http://%LOCAL_IP%:8080
echo.
echo  4. Tippe auf dem Live-Gespraech-Bildschirm auf "Freihändig" -
echo     das iPhone hat eingebaute Echo-Unterdrückung, also kein Echo!
echo.
echo  TIPP: Seite als App speichern:
echo    Safari Menu > "Zum Home-Bildschirm" hinzufuegen
echo.
echo  ===================================================
echo.
echo  WICHTIG - Mikrofon in Safari erlauben:
echo    Wenn Safari nach dem Mikrofon fragt, tippe auf "Erlauben".
echo    Falls nicht gefragt wird: Einstellungen > Safari > Mikrofon > Erlauben
echo.
echo  Druecke eine Taste um dieses Fenster zu schliessen...
pause >nul
