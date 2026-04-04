#Requires -Version 5.1
<#
.SYNOPSIS
    Löscht Outlook-Profile und richtet sie neu ein via Autodiscover.

.DESCRIPTION
    - Schließt Outlook
    - Löscht alle Outlook-Profile aus der Registry
    - Löscht OST-Dateien
    - Löscht gespeicherte Credentials
    - Startet Outlook neu (Autodiscover richtet Profil automatisch ein)

.PARAMETER NoRestart
    Outlook wird nach dem Reset nicht automatisch gestartet.

.PARAMETER BackupProfile
    Erstellt ein Backup der Profil-Registry vor dem Löschen.

.EXAMPLE
    .\Reset-OutlookProfile.ps1

.EXAMPLE
    .\Reset-OutlookProfile.ps1 -NoRestart -BackupProfile
#>

[CmdletBinding()]
param(
    [switch]$NoRestart,
    [switch]$BackupProfile,
    [string]$PrfFile
)

$ErrorActionPreference = "Stop"

# Log-Datei Pfad (einmalig setzen)
$script:LogFile = "$env:TEMP\OutlookProfileReset.log"

# Logging-Funktion
function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Level] $Message"
    Write-Host $logMessage -ForegroundColor $(switch($Level) {
        "ERROR" { "Red" }
        "WARN"  { "Yellow" }
        "SUCCESS" { "Green" }
        default { "White" }
    })

    # In Datei loggen (mit Try-Catch um Fehler abzufangen)
    try {
        $logMessage | Out-File -FilePath $script:LogFile -Append -Encoding UTF8
    } catch {
        # Logging-Fehler ignorieren, Hauptfunktion soll weiterlaufen
    }
}

# Office-Version ermitteln (15.0 = 2013, 16.0 = 2016/2019/365)
function Get-OfficeVersion {
    $versions = @("16.0", "15.0", "14.0")
    foreach ($ver in $versions) {
        if (Test-Path "HKCU:\Software\Microsoft\Office\$ver\Outlook") {
            return $ver
        }
    }
    return "16.0" # Default
}

try {
    Write-Log "=== Outlook Profil Reset gestartet ===" "INFO"

    $officeVersion = Get-OfficeVersion
    Write-Log "Office Version erkannt: $officeVersion"

    $profilePath = "HKCU:\Software\Microsoft\Office\$officeVersion\Outlook\Profiles"

    # 1. Outlook beenden
    Write-Log "Schließe Outlook..."
    $outlookProcess = Get-Process Outlook -ErrorAction SilentlyContinue
    if ($outlookProcess) {
        $outlookProcess | Stop-Process -Force
        Start-Sleep -Seconds 3
        Write-Log "Outlook wurde beendet" "SUCCESS"
    } else {
        Write-Log "Outlook war nicht geöffnet"
    }

    # 2. Backup erstellen (optional)
    if ($BackupProfile -and (Test-Path $profilePath)) {
        $backupFile = "$env:TEMP\OutlookProfile_Backup_$(Get-Date -Format 'yyyyMMdd_HHmmss').reg"
        Write-Log "Erstelle Backup: $backupFile"
        reg export "HKCU\Software\Microsoft\Office\$officeVersion\Outlook\Profiles" $backupFile /y 2>$null
        Write-Log "Backup erstellt" "SUCCESS"
    }

    # 3. Outlook-Profile aus Registry löschen
    Write-Log "Lösche Outlook-Profile aus Registry..."
    if (Test-Path $profilePath) {
        Remove-Item -Path $profilePath -Recurse -Force
        Write-Log "Profile gelöscht" "SUCCESS"
    } else {
        Write-Log "Keine Profile gefunden" "WARN"
    }

    # 4. OST-Dateien löschen
    Write-Log "Lösche OST-Dateien..."
    $ostPath = "$env:LOCALAPPDATA\Microsoft\Outlook"
    $ostFiles = Get-ChildItem -Path $ostPath -Filter "*.ost" -ErrorAction SilentlyContinue
    if ($ostFiles) {
        $ostFiles | ForEach-Object {
            Remove-Item -Path $_.FullName -Force -ErrorAction SilentlyContinue
            Write-Log "Gelöscht: $($_.Name)"
        }
        Write-Log "OST-Dateien gelöscht" "SUCCESS"
    } else {
        Write-Log "Keine OST-Dateien gefunden"
    }

    # 5. Credentials löschen
    Write-Log "Lösche gespeicherte Credentials..."
    $credList = cmdkey /list 2>&1
    $deletedCreds = 0
    foreach ($line in $credList) {
        if ($line -match "Target:\s*(.*(Microsoft|Outlook|Office|Exchange).*)") {
            $target = $matches[1].Trim()
            cmdkey /delete:$target 2>$null
            Write-Log "Credential gelöscht: $target"
            $deletedCreds++
        }
    }
    if ($deletedCreds -gt 0) {
        Write-Log "$deletedCreds Credentials gelöscht" "SUCCESS"
    } else {
        Write-Log "Keine relevanten Credentials gefunden"
    }

    # 6. Outlook neu starten (mit PRF-Datei falls angegeben)
    if (-not $NoRestart) {
        Write-Log "Starte Outlook neu..."
        Start-Sleep -Seconds 2

        # Outlook-Pfad finden
        $outlookPath = @(
            "${env:ProgramFiles}\Microsoft Office\root\Office16\OUTLOOK.EXE",
            "${env:ProgramFiles(x86)}\Microsoft Office\root\Office16\OUTLOOK.EXE",
            "${env:ProgramFiles}\Microsoft Office\Office16\OUTLOOK.EXE"
        ) | Where-Object { Test-Path $_ } | Select-Object -First 1

        if (-not $outlookPath) {
            $outlookPath = "outlook.exe"
        }

        # Mit PRF-Datei starten falls angegeben
        if ($PrfFile -and (Test-Path $PrfFile)) {
            Write-Log "Starte Outlook mit PRF-Profil: $PrfFile"
            Start-Process $outlookPath -ArgumentList "/importprf `"$PrfFile`""
            Write-Log "Outlook mit PRF-Datei gestartet - Profil wird importiert" "SUCCESS"
        } else {
            Start-Process $outlookPath
            Write-Log "Outlook gestartet - Autodiscover richtet neues Profil ein" "SUCCESS"
        }
    }

    Write-Log "=== Outlook Profil Reset abgeschlossen ===" "SUCCESS"
    Write-Log "Logdatei: $env:TEMP\OutlookProfileReset.log"

} catch {
    Write-Log "Fehler: $($_.Exception.Message)" "ERROR"
    exit 1
}
