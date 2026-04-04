@echo off
REM ============================================
REM Outlook Reparatur - Starter Script
REM Dieses Script auf Netzlaufwerk ablegen
REM User fuehrt nur diese Datei aus
REM ============================================

title Outlook Profil Reparatur
color 0A

echo.
echo  ============================================
echo       OUTLOOK PROFIL REPARATUR
echo  ============================================
echo.
echo  Dieses Tool loescht Ihr Outlook-Profil und
echo  richtet es automatisch neu ein.
echo.
echo  Was passiert:
echo   - Outlook wird geschlossen
echo   - Profil wird zurueckgesetzt
echo   - Lokaler Cache wird geloescht
echo   - Outlook startet neu mit vorkonfiguriertem
echo     Profil (PRF-Datei)
echo.
echo  HINWEIS: Ihre E-Mails gehen NICHT verloren!
echo           Sie sind sicher auf dem Server.
echo.
echo  ============================================
echo.

set /p CONFIRM="Moechten Sie fortfahren? (J/N): "
if /i not "%CONFIRM%"=="J" (
    echo.
    echo Abgebrochen.
    timeout /t 3
    exit /b 0
)

echo.
echo Starte Reparatur...
echo.

REM Pfad zum Ordner ermitteln (dort wo diese Batch liegt)
REM %~dp0 gibt den Pfad MIT abschliessendem Backslash
set "SCRIPT_DIR=%~dp0"

REM Debug: Zeige Pfade an
echo Script-Verzeichnis: %SCRIPT_DIR%

REM Vollstaendige Pfade zu den Dateien
set "PS_SCRIPT=%SCRIPT_DIR%Reset-OutlookProfile.ps1"
set "PRF_FILE=%SCRIPT_DIR%Outlook-AutoConfig.prf"

echo PowerShell-Script: %PS_SCRIPT%
echo PRF-Datei: %PRF_FILE%
echo.

REM Pruefen ob PowerShell-Script existiert
if not exist "%PS_SCRIPT%" (
    echo  FEHLER: PowerShell-Script nicht gefunden!
    echo  Erwartet: %PS_SCRIPT%
    echo.
    pause
    exit /b 1
)

REM Pruefen ob PRF-Datei existiert und entsprechend starten
if exist "%PRF_FILE%" (
    echo PRF-Datei gefunden - starte mit Profilimport...
    echo.
    powershell.exe -ExecutionPolicy Bypass -NoProfile -Command "Set-Location '%SCRIPT_DIR%'; & '%PS_SCRIPT%' -PrfFile '%PRF_FILE%'"
) else (
    echo Keine PRF-Datei gefunden - verwende Autodiscover...
    echo.
    powershell.exe -ExecutionPolicy Bypass -NoProfile -Command "& '%PS_SCRIPT%'"
)

if %errorlevel% neq 0 (
    echo.
    echo  ============================================
    echo   FEHLER bei der Ausfuehrung!
    echo  ============================================
    echo.
    echo  Bitte wenden Sie sich an den IT-Support.
    echo.
    pause
    exit /b 1
)

echo.
echo  ============================================
echo   FERTIG!
echo  ============================================
echo.
echo  Outlook sollte sich jetzt automatisch
echo  einrichten. Bitte melden Sie sich an,
echo  wenn Sie dazu aufgefordert werden.
echo.
echo  Bei Problemen: IT-Support kontaktieren
echo.
pause
