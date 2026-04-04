#Requires -Version 5.1
<#
.SYNOPSIS
    Deployment-Script für Remote-Ausführung auf mehreren Clients.

.DESCRIPTION
    Führt den Outlook-Profile-Reset auf mehreren Computern remote aus.
    Kann per GPO, SCCM oder manuell verwendet werden.

.PARAMETER ComputerName
    Ein oder mehrere Computernamen.

.PARAMETER InputFile
    Textdatei mit Computernamen (einer pro Zeile).

.PARAMETER Credential
    Anmeldedaten für Remote-Zugriff.

.EXAMPLE
    .\Deploy-OutlookReset.ps1 -ComputerName "PC001", "PC002"

.EXAMPLE
    .\Deploy-OutlookReset.ps1 -InputFile "C:\computers.txt"
#>

[CmdletBinding()]
param(
    [Parameter(ParameterSetName="Direct")]
    [string[]]$ComputerName,

    [Parameter(ParameterSetName="File")]
    [string]$InputFile,

    [PSCredential]$Credential
)

$ErrorActionPreference = "Continue"

# Script-Block für Remote-Ausführung
$resetScript = {
    param([string]$Username)

    $result = @{
        Computer = $env:COMPUTERNAME
        Success = $false
        Message = ""
        User = $Username
    }

    try {
        # Registry-Pfad für den angemeldeten User
        $officeVersion = "16.0"
        $profilePath = "HKCU:\Software\Microsoft\Office\$officeVersion\Outlook\Profiles"

        # Outlook beenden
        Get-Process Outlook -ErrorAction SilentlyContinue | Stop-Process -Force
        Start-Sleep -Seconds 2

        # Profile löschen
        if (Test-Path $profilePath) {
            Remove-Item -Path $profilePath -Recurse -Force
        }

        # OST löschen
        $ostPath = "$env:LOCALAPPDATA\Microsoft\Outlook"
        Get-ChildItem -Path $ostPath -Filter "*.ost" -ErrorAction SilentlyContinue |
            Remove-Item -Force -ErrorAction SilentlyContinue

        # Credentials löschen
        $credList = cmdkey /list 2>&1
        foreach ($line in $credList) {
            if ($line -match "Target:\s*(.*(Microsoft|Outlook|Office|Exchange).*)") {
                cmdkey /delete:$matches[1].Trim() 2>$null
            }
        }

        $result.Success = $true
        $result.Message = "Reset erfolgreich"
    }
    catch {
        $result.Message = $_.Exception.Message
    }

    return $result
}

# Computerliste erstellen
$computers = @()
if ($ComputerName) {
    $computers = $ComputerName
}
elseif ($InputFile) {
    if (Test-Path $InputFile) {
        $computers = Get-Content $InputFile | Where-Object { $_ -and $_ -notmatch "^\s*#" }
    } else {
        Write-Error "Datei nicht gefunden: $InputFile"
        exit 1
    }
}
else {
    Write-Host "Verwendung:" -ForegroundColor Yellow
    Write-Host "  .\Deploy-OutlookReset.ps1 -ComputerName PC001, PC002"
    Write-Host "  .\Deploy-OutlookReset.ps1 -InputFile computers.txt"
    exit 0
}

Write-Host "`n=== Outlook Profil Reset - Remote Deployment ===" -ForegroundColor Cyan
Write-Host "Ziel-Computer: $($computers.Count)`n"

# Remote-Ausführung
$results = @()
foreach ($computer in $computers) {
    Write-Host "[$computer] " -NoNewline

    $params = @{
        ComputerName = $computer
        ScriptBlock = $resetScript
        ErrorAction = "Stop"
    }

    if ($Credential) {
        $params.Credential = $Credential
    }

    try {
        # Erreichbarkeit testen
        if (-not (Test-Connection -ComputerName $computer -Count 1 -Quiet)) {
            Write-Host "OFFLINE" -ForegroundColor Red
            $results += [PSCustomObject]@{
                Computer = $computer
                Success = $false
                Message = "Nicht erreichbar"
            }
            continue
        }

        # Script remote ausführen
        $result = Invoke-Command @params
        $results += $result

        if ($result.Success) {
            Write-Host "OK" -ForegroundColor Green
        } else {
            Write-Host "FEHLER: $($result.Message)" -ForegroundColor Red
        }
    }
    catch {
        Write-Host "FEHLER: $($_.Exception.Message)" -ForegroundColor Red
        $results += [PSCustomObject]@{
            Computer = $computer
            Success = $false
            Message = $_.Exception.Message
        }
    }
}

# Zusammenfassung
Write-Host "`n=== Zusammenfassung ===" -ForegroundColor Cyan
$success = ($results | Where-Object { $_.Success }).Count
$failed = ($results | Where-Object { -not $_.Success }).Count
Write-Host "Erfolgreich: $success" -ForegroundColor Green
Write-Host "Fehlgeschlagen: $failed" -ForegroundColor $(if($failed -gt 0){"Red"}else{"Green"})

# Ergebnis exportieren
$reportPath = "$PSScriptRoot\OutlookReset_Report_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"
$results | Export-Csv -Path $reportPath -NoTypeInformation -Encoding UTF8
Write-Host "`nBericht gespeichert: $reportPath"
