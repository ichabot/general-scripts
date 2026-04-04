# Outlook Profil Reset Scripts

Scripts zum automatischen Löschen und Neueinrichten von Outlook-Profilen.

## Enthaltene Dateien

| Datei | Beschreibung |
|-------|--------------|
| `Reset-OutlookProfile.ps1` | PowerShell-Script für lokale Ausführung |
| `Reset-OutlookProfile.bat` | Einfache Batch-Version für einzelne User |
| `Outlook-AutoConfig.prf` | PRF-Datei für automatische Profilkonfiguration |
| `Deploy-OutlookReset.ps1` | Remote-Deployment auf mehrere Clients |

## Verwendung

### Einzelner Client (lokal)

**PowerShell (empfohlen):**
```powershell
# Standard-Reset mit Neustart
.\Reset-OutlookProfile.ps1

# Mit Backup, ohne Outlook-Neustart
.\Reset-OutlookProfile.ps1 -BackupProfile -NoRestart
```

**Batch (einfach):**
```cmd
Reset-OutlookProfile.bat
```

### Mehrere Clients (remote)

```powershell
# Einzelne Computer
.\Deploy-OutlookReset.ps1 -ComputerName "PC001", "PC002", "PC003"

# Aus Datei (ein Computername pro Zeile)
.\Deploy-OutlookReset.ps1 -InputFile "computers.txt"

# Mit alternativen Credentials
.\Deploy-OutlookReset.ps1 -ComputerName "PC001" -Credential (Get-Credential)
```

### Per GPO/Logonscript

1. Script auf Netzwerkfreigabe kopieren: `\\server\netlogon\Reset-OutlookProfile.ps1`
2. Gruppenrichtlinie erstellen
3. Unter **Benutzerkonfiguration → Richtlinien → Windows-Einstellungen → Skripts → Anmelden**
4. PowerShell-Script hinzufügen

### Mit PRF-Datei

```cmd
outlook.exe /importprf "\\server\share\Outlook-AutoConfig.prf"
```

## Was wird gemacht?

1. **Outlook beenden** - Schließt alle laufenden Outlook-Prozesse
2. **Profile löschen** - Entfernt alle Profile aus `HKCU:\Software\Microsoft\Office\16.0\Outlook\Profiles`
3. **OST-Dateien löschen** - Entfernt lokale Kopien aus `%LOCALAPPDATA%\Microsoft\Outlook\`
4. **Credentials löschen** - Entfernt gespeicherte Anmeldedaten (Microsoft, Outlook, Office, Exchange)
5. **Outlook neu starten** - Autodiscover richtet automatisch neues Profil ein

## Voraussetzungen

- Windows 10/11
- Office 2016/2019/365
- PowerShell 5.1+
- Für Remote-Deployment: PowerShell-Remoting aktiviert (`Enable-PSRemoting`)

## Hinweise

- **PST-Dateien** werden NICHT gelöscht (nur OST)
- **Signaturen** bleiben erhalten
- **Regeln** und **Schnellschritte** sind im Exchange-Postfach gespeichert und werden wiederhergestellt
- Bei Shared Mailboxes müssen diese nach dem Reset ggf. neu hinzugefügt werden

## Troubleshooting

**Outlook startet nicht nach Reset:**
- Prüfen ob Autodiscover funktioniert: `Test-OutlookWebServices -Identity user@domain.de`
- DNS-Einträge für Autodiscover prüfen

**Remote-Ausführung fehlgeschlagen:**
- PowerShell-Remoting aktivieren: `Enable-PSRemoting -Force`
- Firewall-Regeln prüfen (WinRM: Port 5985/5986)
