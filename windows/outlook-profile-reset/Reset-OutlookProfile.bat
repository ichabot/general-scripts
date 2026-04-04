@echo off
REM ============================================
REM Outlook Profil Reset - Batch Version
REM Einfache Variante für einzelne User
REM ============================================

echo.
echo === Outlook Profil Reset ===
echo.

REM Outlook beenden
echo [1/4] Beende Outlook...
taskkill /f /im outlook.exe 2>nul
if %errorlevel%==0 (
    echo      Outlook wurde beendet.
) else (
    echo      Outlook war nicht geöffnet.
)
timeout /t 2 /nobreak >nul

REM Profile löschen
echo [2/4] Loesche Outlook-Profile...
reg delete "HKCU\Software\Microsoft\Office\16.0\Outlook\Profiles" /f 2>nul
if %errorlevel%==0 (
    echo      Profile geloescht.
) else (
    echo      Keine Profile gefunden oder bereits geloescht.
)

REM OST-Dateien löschen
echo [3/4] Loesche OST-Dateien...
del /f /q "%LOCALAPPDATA%\Microsoft\Outlook\*.ost" 2>nul
echo      OST-Dateien geloescht.

REM Credentials löschen (optional, etwas aufwendiger in Batch)
echo [4/4] Loesche gespeicherte Anmeldedaten...
for /f "tokens=2 delims=: " %%a in ('cmdkey /list ^| findstr /i "Microsoft Outlook Office"') do (
    cmdkey /delete:%%a 2>nul
)
echo      Anmeldedaten geloescht.

echo.
echo === Reset abgeschlossen ===
echo.

REM Outlook starten
set /p STARTEN="Outlook jetzt starten? (J/N): "
if /i "%STARTEN%"=="J" (
    echo Starte Outlook...
    start outlook.exe
    echo Outlook wird durch Autodiscover automatisch eingerichtet.
)

echo.
pause
