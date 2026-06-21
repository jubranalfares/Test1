@echo off
setlocal enabledelayedexpansion
title Jarvis - iPhone HTTPS Setup (Mikrofon)

echo.
echo  ===================================================
echo   JARVIS - iPhone HTTPS Setup
echo   (benoetigt fuer Mikrofon in Safari)
echo  ===================================================
echo.
echo  Dieses Skript erstellt sichere HTTPS-Tunnel via Cloudflare,
echo  damit Safari auf dem iPhone das Mikrofon erlaubt.
echo.

REM Pruefe ob cloudflared installiert ist
cloudflared --version >nul 2>&1
if errorlevel 1 (
    echo [INFO] cloudflared nicht gefunden. Wird jetzt installiert...
    echo.
    winget install Cloudflare.cloudflared
    if errorlevel 1 (
        echo.
        echo [MANUELL] Falls winget nicht funktioniert:
        echo   1. Gehe zu: https://github.com/cloudflare/cloudflared/releases/latest
        echo   2. Lade "cloudflared-windows-amd64.exe" herunter
        echo   3. Benenne es in "cloudflared.exe" um
        echo   4. Verschiebe es nach C:\Windows\System32\
        echo   5. Starte dieses Skript erneut
        echo.
        pause
        exit /b 1
    )
)

cd /d "%~dp0.."

echo  Starte Backend (Docker)...
docker compose up -d >nul 2>&1

echo  Starte Flutter Web...
cd /d "%~dp0..\mobile\flutter_app"
start "Jarvis Flutter Web" cmd /k "flutter run -d web-server --web-port 3000 --web-hostname 0.0.0.0"
cd /d "%~dp0"

echo.
echo  Warte kurz bis die Dienste hochgefahren sind...
timeout /t 8 /nobreak >nul

echo.
echo  Starte HTTPS-Tunnel fuer Backend (Port 8080)...
start "Jarvis API Tunnel" cmd /k "cloudflared tunnel --url http://localhost:8080"

timeout /t 3 /nobreak >nul

echo  Starte HTTPS-Tunnel fuer Flutter Web (Port 3000)...
start "Jarvis Web Tunnel" cmd /k "cloudflared tunnel --url http://localhost:3000"

echo.
echo  ===================================================
echo   WAS JETZT TUN:
echo  ===================================================
echo.
echo  In den beiden neuen Fenstern siehst du nach ca. 5 Sekunden:
echo.
echo    "trycloudflare.com" URLs - das sind deine HTTPS-Links!
echo.
echo  Zum Beispiel:
echo    Backend: https://random-name-abc.trycloudflare.com
echo    Web App: https://random-name-xyz.trycloudflare.com
echo.
echo  So nutzt du sie auf dem iPhone:
echo    1. Oeffne die "Web App" URL in Safari
echo    2. Erlaube Mikrofon wenn Safari fragt
echo    3. Gib im Login als Server-Adresse die "Backend" URL ein
echo    4. Logge dich ein und geniesse Jarvis!
echo.
echo  TIPP: Die URLs aendern sich bei jedem Neustart.
echo        Speichere sie kurz als Lesezeichen.
echo.
pause
