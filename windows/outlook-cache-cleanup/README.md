# Outlook Autovervollständigung bereinigen

PowerShell-Script zum Bereinigen des Outlook AutoComplete-Cache. Optimiert für NinjaRMM-Deployment.

## Features

- AutoComplete-Cache löschen (NK2-Dateien + Stream_AutoComplete)
- Outlook automatisch beenden und optional neu starten
- Alle Outlook-Versionen (2010–365) unterstützt
- Detailliertes Logging mit Zeitstempeln
- WhatIf-Modus zum Testen ohne Änderungen
- Exit-Codes für RMM-Monitoring

## Verwendung

**Standard-Deployment** (nur AutoComplete löschen):
```powershell
.\Outlook-Cache-Cleanup.ps1
```

**Mit Outlook-Neustart:**
```powershell
.\Outlook-Cache-Cleanup.ps1 -RestartOutlook
```

**Alle Caches löschen** (umfassend):
```powershell
.\Outlook-Cache-Cleanup.ps1 -ClearAllCaches
```

**Test-Modus** (keine Änderungen):
```powershell
.\Outlook-Cache-Cleanup.ps1 -WhatIf
```

**Kombination:**
```powershell
.\Outlook-Cache-Cleanup.ps1 -ClearAllCaches -RestartOutlook
```

## RMM-Deployment

> **Wichtig:** Das Script muss im **Benutzerkontext** laufen, nicht als SYSTEM, da die Outlook-Profile benutzerspezifisch sind.

| RMM-Tool | Einstellung |
|----------|-------------|
| NinjaRMM | „Run as logged-on user" |
| Datto RMM | User Context aktivieren |
| Atera | Run as User |
| Kaseya/Connectwise | Deploy as User |

**Silent-Deployment** (ohne Fenster):
```powershell
powershell.exe -ExecutionPolicy Bypass -WindowStyle Hidden -File "\\server\scripts\Outlook-Cache-Cleanup.ps1" -ClearAllCaches
```

**Log-Datei an zentralem Ort:**
```powershell
.\Outlook-Cache-Cleanup.ps1 -LogPath "\\fileserver\logs\$env:COMPUTERNAME-outlook-cleanup.log"
```

## Exit-Codes

| Code | Bedeutung |
|------|-----------|
| 0 | Erfolgreich / nichts zu tun |
| 1 | Fehler (falscher Kontext, Outlook nicht beendbar) |
| 2 | Mit Fehlern abgeschlossen |

## Log-Dateien

Logs werden unter `%ProgramData%\NinjaRMMAgent\Logs\` gespeichert. Logs älter als 30 Tage werden automatisch aufgeräumt.
