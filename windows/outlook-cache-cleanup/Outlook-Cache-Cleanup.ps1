<#
.SYNOPSIS
    Outlook AutoComplete Cache Cleanup Script - NinjaRMM Optimiert

.DESCRIPTION
    Löscht Outlook AutoComplete-Cache (NK2), Stream_AutoComplete Dateien
    und optional weitere Outlook-Caches. Speziell optimiert für NinjaRMM.
    Funktioniert mit allen Outlook-Versionen 2010-365.

.NOTES
    Version: 1.1 - NinjaRMM Edition
    Autor: IT-Admin
    Kompatibel mit: Outlook 2010, 2013, 2016, 2019, 2021, 365
    NinjaRMM: Deploy als "Run as logged-on user"
    
.PARAMETER RestartOutlook
    Startet Outlook nach Cleanup automatisch neu
    
.PARAMETER ClearAllCaches
    Löscht auch zusätzliche Caches (OST-Backups, AutoDiscover)
    
.PARAMETER WhatIf
    Test-Modus: Zeigt nur an, was gemacht würde
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [switch]$RestartOutlook = $false,
    
    [Parameter(Mandatory=$false)]
    [switch]$ClearAllCaches = $false,
    
    [Parameter(Mandatory=$false)]
    [switch]$WhatIf = $false
)

#Requires -Version 5.1

# NinjaRMM Custom Fields (optional - für Reporting)
# Uncomment wenn du Custom Fields nutzen möchtest
# $NinjaOutlookCacheCleanupResult = ""
# $NinjaOutlookCacheCleanupDate = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

# Logging-Konfiguration für NinjaRMM
$LogPath = "$env:ProgramData\NinjaRMMAgent\Logs\OutlookCacheCleanup_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
$MaxLogAge = 30 # Logs älter als 30 Tage löschen

# Stelle sicher, dass Log-Verzeichnis existiert
$LogDir = Split-Path -Path $LogPath -Parent
if (-not (Test-Path $LogDir)) {
    New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
}

# Alte Logs aufräumen
Get-ChildItem -Path (Split-Path $LogPath) -Filter "OutlookCacheCleanup_*.log" -ErrorAction SilentlyContinue | 
    Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-$MaxLogAge) } | 
    Remove-Item -Force -ErrorAction SilentlyContinue

# Globale Zähler für Reporting
$script:TotalFilesDeleted = 0
$script:TotalErrorsEncountered = 0
$script:OutlookWasRunning = $false

# Logging-Funktion mit NinjaRMM-Output
function Write-Log {
    param(
        [string]$Message,
        [ValidateSet('Info','Warning','Error','Success')]
        [string]$Level = 'Info'
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Level] $Message"
    
    # Console-Ausgabe (wird von NinjaRMM erfasst)
    switch ($Level) {
        'Info'    { Write-Host $logMessage }
        'Warning' { Write-Warning $Message }
        'Error'   { Write-Error $Message; $script:TotalErrorsEncountered++ }
        'Success' { Write-Host "[SUCCESS] $Message" }
    }
    
    # Log-Datei
    try {
        Add-Content -Path $LogPath -Value $logMessage -ErrorAction Stop
    }
    catch {
        Write-Warning "Konnte nicht ins Log schreiben: $_"
    }
}

# Funktion: Prüfe ob Script als User läuft (nicht als SYSTEM)
function Test-RunningAsUser {
    $currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    
    if ($currentUser.Name -like "*SYSTEM*" -or $currentUser.Name -like "*LOCAL SERVICE*") {
        Write-Log "FEHLER: Script läuft als SYSTEM/SERVICE. Muss als User laufen!" -Level Error
        Write-Log "NinjaRMM-Einstellung: 'Run as logged-on user' aktivieren" -Level Error
        return $false
    }
    
    Write-Log "Script läuft als Benutzer: $($currentUser.Name)" -Level Info
    return $true
}

# Funktion: Outlook-Prozesse beenden
function Stop-OutlookProcesses {
    Write-Log "Prüfe auf laufende Outlook-Prozesse..."
    
    $outlookProcesses = Get-Process -Name "OUTLOOK" -ErrorAction SilentlyContinue
    
    if ($outlookProcesses) {
        $script:OutlookWasRunning = $true
        Write-Log "Outlook läuft. Beende $($outlookProcesses.Count) Prozess(e)..." -Level Warning
        
        if ($WhatIf) {
            Write-Log "[WHATIF] Würde Outlook-Prozesse beenden" -Level Info
            return $true
        }
        
        try {
            # Versuche zuerst graceful shutdown
            $outlookProcesses | ForEach-Object { 
                $_.CloseMainWindow() | Out-Null
            }
            Start-Sleep -Seconds 3
            
            # Force kill falls noch läuft
            $stillRunning = Get-Process -Name "OUTLOOK" -ErrorAction SilentlyContinue
            if ($stillRunning) {
                $stillRunning | Stop-Process -Force -ErrorAction Stop
                Start-Sleep -Seconds 2
            }
            
            # Final check
            $remainingProcesses = Get-Process -Name "OUTLOOK" -ErrorAction SilentlyContinue
            if ($remainingProcesses) {
                Write-Log "WARNUNG: Outlook konnte nicht vollständig beendet werden" -Level Warning
                return $false
            }
            
            Write-Log "Outlook erfolgreich beendet" -Level Success
            return $true
        }
        catch {
            Write-Log "FEHLER beim Beenden von Outlook: $_" -Level Error
            return $false
        }
    }
    else {
        Write-Log "Outlook läuft nicht" -Level Info
        return $false
    }
}

# Funktion: Outlook-Version und Installation prüfen
function Get-OutlookInfo {
    Write-Log "Erkenne Outlook-Installation..."
    
    # Prüfe verschiedene Registry-Pfade
    $outlookPaths = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\OUTLOOK.EXE",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\App Paths\OUTLOOK.EXE"
    )
    
    foreach ($path in $outlookPaths) {
        $outlookReg = Get-ItemProperty -Path $path -ErrorAction SilentlyContinue
        if ($outlookReg) {
            $exePath = $outlookReg.'(default)'
            if (Test-Path $exePath) {
                $version = (Get-Item $exePath).VersionInfo.ProductVersion
                Write-Log "Outlook gefunden: Version $version" -Level Success
                Write-Log "Pfad: $exePath" -Level Info
                return @{
                    Installed = $true
                    Version = $version
                    Path = $exePath
                }
            }
        }
    }
    
    Write-Log "Outlook nicht installiert oder nicht gefunden" -Level Warning
    return @{
        Installed = $false
        Version = $null
        Path = $null
    }
}

# Funktion: NK2-Dateien löschen (Outlook 2010 und älter)
function Remove-NK2Files {
    Write-Log "Suche nach NK2-Dateien (Outlook 2010 AutoComplete)..."
    
    $nk2Paths = @(
        "$env:APPDATA\Microsoft\Outlook",
        "$env:LOCALAPPDATA\Microsoft\Outlook"
    )
    
    $deletedCount = 0
    
    foreach ($basePath in $nk2Paths) {
        if (-not (Test-Path $basePath)) { continue }
        
        $files = Get-ChildItem -Path $basePath -Filter "*.nk2" -ErrorAction SilentlyContinue
        
        foreach ($file in $files) {
            if ($WhatIf) {
                Write-Log "[WHATIF] Würde löschen: $($file.Name)" -Level Info
            }
            else {
                try {
                    Remove-Item -Path $file.FullName -Force -ErrorAction Stop
                    Write-Log "✓ Gelöscht: $($file.Name) ($([math]::Round($file.Length/1KB, 2)) KB)" -Level Success
                    $deletedCount++
                    $script:TotalFilesDeleted++
                }
                catch {
                    Write-Log "Fehler beim Löschen von $($file.Name): $_" -Level Error
                }
            }
        }
    }
    
    if ($deletedCount -eq 0) {
        Write-Log "Keine NK2-Dateien gefunden" -Level Info
    }
    else {
        Write-Log "NK2-Dateien gelöscht: $deletedCount" -Level Success
    }
    
    return $deletedCount
}

# Funktion: Stream_AutoComplete Dateien löschen (Outlook 2013+)
function Remove-StreamAutoCompleteFiles {
    Write-Log "Suche nach AutoComplete-Stream-Dateien (Outlook 2013+)..."
    
    $roamCachePath = "$env:LOCALAPPDATA\Microsoft\Outlook\RoamCache"
    
    if (-not (Test-Path $roamCachePath)) {
        Write-Log "RoamCache-Ordner nicht vorhanden" -Level Info
        return 0
    }
    
    $autoCompleteFiles = Get-ChildItem -Path $roamCachePath -Filter "Stream_AutoComplete_*.dat" -ErrorAction SilentlyContinue
    
    $deletedCount = 0
    $totalSize = 0
    
    foreach ($file in $autoCompleteFiles) {
        $totalSize += $file.Length
        
        if ($WhatIf) {
            Write-Log "[WHATIF] Würde löschen: $($file.Name)" -Level Info
        }
        else {
            try {
                Remove-Item -Path $file.FullName -Force -ErrorAction Stop
                Write-Log "✓ Gelöscht: $($file.Name) ($([math]::Round($file.Length/1KB, 2)) KB)" -Level Success
                $deletedCount++
                $script:TotalFilesDeleted++
            }
            catch {
                Write-Log "Fehler beim Löschen von $($file.Name): $_" -Level Error
            }
        }
    }
    
    if ($deletedCount -eq 0) {
        Write-Log "Keine AutoComplete-Stream-Dateien gefunden" -Level Info
    }
    else {
        Write-Log "AutoComplete-Dateien gelöscht: $deletedCount (Gesamt: $([math]::Round($totalSize/1KB, 2)) KB)" -Level Success
    }
    
    return $deletedCount
}

# Funktion: Registry AutoDiscover-Cache löschen
function Clear-RegistryAutoComplete {
    Write-Log "Lösche Registry AutoDiscover-Cache..."
    
    $outlookVersions = @("16.0", "15.0", "14.0", "12.0")
    $clearedCount = 0
    
    foreach ($version in $outlookVersions) {
        $regPath = "HKCU:\Software\Microsoft\Office\$version\Outlook\AutoDiscover"
        
        if (Test-Path $regPath) {
            if ($WhatIf) {
                Write-Log "[WHATIF] Würde Registry-Pfad leeren: Outlook $version" -Level Info
            }
            else {
                try {
                    Remove-Item -Path $regPath -Recurse -Force -ErrorAction Stop
                    Write-Log "✓ Registry geleert: Outlook Version $version" -Level Success
                    $clearedCount++
                }
                catch {
                    Write-Log "Fehler beim Leeren der Registry (Version $version): $_" -Level Error
                }
            }
        }
    }
    
    return $clearedCount
}

# Funktion: Zusätzliche Caches löschen
function Remove-AdditionalCaches {
    Write-Log "Lösche zusätzliche Outlook-Caches..."
    
    $cachePaths = @(
        @{Path="$env:LOCALAPPDATA\Microsoft\Outlook\*.ost.tmp"; Desc="OST Temp-Dateien"},
        @{Path="$env:LOCALAPPDATA\Microsoft\Outlook\*.ost.bak"; Desc="OST Backup-Dateien"},
        @{Path="$env:TEMP\Outlook Logging\*.log"; Desc="Outlook Logging"},
        @{Path="$env:LOCALAPPDATA\Microsoft\Outlook\*.xml.tmp"; Desc="XML Temp-Dateien"}
    )
    
    $deletedCount = 0
    
    foreach ($cache in $cachePaths) {
        $files = Get-ChildItem -Path $cache.Path -ErrorAction SilentlyContinue
        
        if ($files) {
            Write-Log "Gefunden: $($files.Count) $($cache.Desc)" -Level Info
            
            foreach ($file in $files) {
                if ($WhatIf) {
                    Write-Log "[WHATIF] Würde löschen: $($file.Name)" -Level Info
                }
                else {
                    try {
                        Remove-Item -Path $file.FullName -Force -ErrorAction Stop
                        Write-Log "✓ Gelöscht: $($file.Name)" -Level Success
                        $deletedCount++
                        $script:TotalFilesDeleted++
                    }
                    catch {
                        Write-Log "Fehler beim Löschen: $_" -Level Error
                    }
                }
            }
        }
    }
    
    return $deletedCount
}

# Funktion: Outlook neu starten
function Start-OutlookProcess {
    param([string]$OutlookPath)
    
    Write-Log "Starte Outlook neu..."
    
    if (-not $OutlookPath -or -not (Test-Path $OutlookPath)) {
        Write-Log "Outlook-Pfad ungültig" -Level Warning
        return $false
    }
    
    if ($WhatIf) {
        Write-Log "[WHATIF] Würde Outlook starten: $OutlookPath" -Level Info
        return $true
    }
    
    try {
        Start-Process -FilePath $OutlookPath -ErrorAction Stop
        Start-Sleep -Seconds 2
        
        # Verifiziere dass Outlook läuft
        $process = Get-Process -Name "OUTLOOK" -ErrorAction SilentlyContinue
        if ($process) {
            Write-Log "✓ Outlook erfolgreich gestartet (PID: $($process.Id))" -Level Success
            return $true
        }
        else {
            Write-Log "Outlook gestartet, aber Prozess nicht gefunden" -Level Warning
            return $false
        }
    }
    catch {
        Write-Log "Fehler beim Starten von Outlook: $_" -Level Error
        return $false
    }
}

# === HAUPTSKRIPT ===

$startTime = Get-Date

Write-Log "========================================" -Level Info
Write-Log "Outlook Cache Cleanup - NinjaRMM" -Level Info
Write-Log "========================================" -Level Info
Write-Log "Startzeit: $($startTime.ToString('yyyy-MM-dd HH:mm:ss'))" -Level Info
Write-Log "Computername: $env:COMPUTERNAME" -Level Info
Write-Log "Benutzername: $env:USERNAME" -Level Info

if ($WhatIf) {
    Write-Log "" -Level Info
    Write-Log "!!! WHATIF-MODUS AKTIV !!!" -Level Warning
    Write-Log "Es werden keine Änderungen vorgenommen" -Level Warning
    Write-Log "" -Level Info
}

# 1. Prüfe ob als User ausgeführt
if (-not (Test-RunningAsUser)) {
    Write-Log "Script wird beendet - falsche Ausführungskontext" -Level Error
    exit 1
}

# 2. Outlook-Installation prüfen
$outlookInfo = Get-OutlookInfo

if (-not $outlookInfo.Installed) {
    Write-Log "Outlook nicht installiert - Script wird beendet" -Level Warning
    Write-Log "Exit Code: 0 (kein Fehler, nichts zu tun)" -Level Info
    exit 0
}

# 3. Outlook beenden
$wasRunning = Stop-OutlookProcesses

# Sicherheitscheck
if ((Get-Process -Name "OUTLOOK" -ErrorAction SilentlyContinue) -and -not $WhatIf) {
    Write-Log "KRITISCH: Outlook läuft noch. Abbruch aus Sicherheitsgründen!" -Level Error
    exit 1
}

Write-Log "" -Level Info
Write-Log "--- Starte Cache-Bereinigung ---" -Level Info

# 4. Caches löschen
$nk2Count = Remove-NK2Files
$streamCount = Remove-StreamAutoCompleteFiles

if ($ClearAllCaches) {
    Write-Log "" -Level Info
    Write-Log "--- Erweiterte Bereinigung (ClearAllCaches aktiv) ---" -Level Info
    $additionalCount = Remove-AdditionalCaches
    $registryCount = Clear-RegistryAutoComplete
}

# 5. Zusammenfassung
Write-Log "" -Level Info
Write-Log "========================================" -Level Info
Write-Log "Cleanup abgeschlossen" -Level Success
Write-Log "========================================" -Level Info

$duration = (Get-Date) - $startTime
Write-Log "Dauer: $([math]::Round($duration.TotalSeconds, 2)) Sekunden" -Level Info
Write-Log "Gelöschte Dateien: $script:TotalFilesDeleted" -Level Info
Write-Log "Fehler: $script:TotalErrorsEncountered" -Level Info

if (-not $WhatIf) {
    Write-Log "Detailliertes Log: $LogPath" -Level Info
}

# 6. Outlook neu starten (optional)
if ($RestartOutlook -and $script:OutlookWasRunning -and $outlookInfo.Path -and -not $WhatIf) {
    Write-Log "" -Level Info
    Start-Sleep -Seconds 2
    Start-OutlookProcess -OutlookPath $outlookInfo.Path
}

Write-Log "========================================" -Level Info

# NinjaRMM Custom Field Output (optional)
# Ninja-Property-Set outlookCacheCleanupResult "$script:TotalFilesDeleted files deleted, $script:TotalErrorsEncountered errors"
# Ninja-Property-Set outlookCacheCleanupDate "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"

# Exit-Codes für NinjaRMM-Monitoring
if ($script:TotalErrorsEncountered -gt 0) {
    Write-Log "Exit Code: 2 (mit Fehlern abgeschlossen)" -Level Warning
    exit 2
}
elseif ($script:TotalFilesDeleted -gt 0 -or $WhatIf) {
    Write-Log "Exit Code: 0 (erfolgreich)" -Level Success
    exit 0
}
else {
    Write-Log "Exit Code: 0 (nichts zu löschen)" -Level Info
    exit 0
}
