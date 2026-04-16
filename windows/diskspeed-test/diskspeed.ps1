<#
.SYNOPSIS
    Storage-Benchmark für Windows Server VM auf VMware mit FC-angebundener SSD-SAN (z.B. Dell ME5024).

.DESCRIPTION
    Führt eine vollständige DiskSpd-Testbatterie durch:
      - 4K random read/write (IOPS + Latenz, QD-Scan)
      - 8K 70/30 mixed (OLTP-Profil)
      - 64K sequential read/write (Throughput)
      - 1M sequential read/write (Backup / Large-Block)
    Ergebnisse werden als XML + CSV-Zusammenfassung abgelegt.

.PARAMETER TargetPath
    Pfad auf dem zu testenden Volume (z.B. E:\diskspd\test.dat). Testfile wird automatisch erstellt.

.PARAMETER FileSizeGB
    Größe der Testdatei. Sollte > SAN-Cache und > VM-RAM sein, damit Ergebnisse nicht gecached werden.
    Faustregel: 2x RAM der VM, mindestens 32 GB.

.PARAMETER Duration
    Testdauer pro Run in Sekunden. 60s ist ein guter Kompromiss, 120s für Steady-State-Messungen.

.PARAMETER Threads
    Anzahl Worker-Threads. Default = Anzahl logischer CPUs der VM.

.PARAMETER OutputDir
    Zielverzeichnis für XML-Reports und CSV-Summary.

.EXAMPLE
    .\Invoke-StoragePerfTest.ps1 -TargetPath "E:\diskspd\test.dat" -FileSizeGB 50 -Duration 60

.NOTES
    - DiskSpd muss installiert sein (https://github.com/microsoft/diskspd/releases).
      Script prüft C:\Tools\diskspd\amd64\diskspd.exe und PATH.
    - VMware-Hinweise für aussagekräftige Ergebnisse:
        * VMXNET3 / PVSCSI Controller verwenden
        * VM-Tools aktuell
        * Testdisk als eigene VMDK auf eigenem Datastore (keine Shared-Workloads parallel)
        * Snapshots entfernen, Thin Provisioning deaktivieren für Benchmark-VMDK
        * Bei VAAI prüfen ob ATS/XCOPY aktiv ist
    - Dell ME5024: Firmware aktuell halten, Controller-Balance prüfen (beide Controller aktiv),
      FC-Multipathing (RR mit IOPS=1) im ESXi für ME5-Family empfohlen.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$TargetPath,

    [int]$FileSizeGB = 50,

    [int]$Duration = 60,

    [int]$Warmup = 15,

    [int]$Threads = [Environment]::ProcessorCount,

    [string]$OutputDir = "C:\StoragePerf\Results_$(Get-Date -Format 'yyyyMMdd_HHmmss')",

    [string]$DiskSpdPath = "C:\Tools\diskspd\amd64\diskspd.exe"
)

#region --- Vorbereitung ---
$ErrorActionPreference = 'Stop'

# DiskSpd lokalisieren
if (-not (Test-Path $DiskSpdPath)) {
    $inPath = Get-Command diskspd.exe -ErrorAction SilentlyContinue
    if ($inPath) { $DiskSpdPath = $inPath.Source }
    else {
        throw "DiskSpd nicht gefunden. Download: https://github.com/microsoft/diskspd/releases – Pfad via -DiskSpdPath angeben."
    }
}

# Outputverzeichnis
if (-not (Test-Path $OutputDir)) {
    New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
}

# Testdatei-Ordner sicherstellen
$targetDir = Split-Path $TargetPath -Parent
if (-not (Test-Path $targetDir)) {
    New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
}

Write-Host "=== Storage Performance Test ===" -ForegroundColor Cyan
Write-Host "Target:        $TargetPath"
Write-Host "File Size:     ${FileSizeGB} GB"
Write-Host "Duration:      ${Duration}s (Warmup ${Warmup}s)"
Write-Host "Threads:       $Threads"
Write-Host "Output:        $OutputDir"
Write-Host "DiskSpd:       $DiskSpdPath"
Write-Host ""
#endregion

#region --- Testmatrix ---
# Flags:
#   -Sh   : Software + Hardware Caching aus (direct I/O, kein Write-Buffering)
#   -L    : Latenzmessung
#   -r    : Random I/O
#   -w    : Write-Prozentsatz (0 = reine Reads)
#   -b    : Blockgröße
#   -t    : Threads pro File
#   -o    : Outstanding I/Os (Queue Depth) pro Thread
#   -d    : Duration
#   -W    : Warmup
#   -c    : Create file of size
#   -Rxml : Report als XML
#
# Effektive QD = -t * -o

$tests = @(
    # --- 4K Random Read: QD-Scan für IOPS/Latenz-Kurve ---
    @{ Name = "4K_RandRead_QD1";   Args = "-b4K  -r -w0   -o1  -t$Threads -d$Duration -W$Warmup -Sh -L" }
    @{ Name = "4K_RandRead_QD8";   Args = "-b4K  -r -w0   -o8  -t$Threads -d$Duration -W$Warmup -Sh -L" }
    @{ Name = "4K_RandRead_QD32";  Args = "-b4K  -r -w0   -o32 -t$Threads -d$Duration -W$Warmup -Sh -L" }

    # --- 4K Random Write: IOPS-Peak + Schreib-Latenz ---
    @{ Name = "4K_RandWrite_QD1";  Args = "-b4K  -r -w100 -o1  -t$Threads -d$Duration -W$Warmup -Sh -L" }
    @{ Name = "4K_RandWrite_QD32"; Args = "-b4K  -r -w100 -o32 -t$Threads -d$Duration -W$Warmup -Sh -L" }

    # --- 8K 70/30 Mixed: OLTP/SQL-typisch ---
    @{ Name = "8K_OLTP_70R30W_QD16"; Args = "-b8K  -r -w30  -o16 -t$Threads -d$Duration -W$Warmup -Sh -L" }

    # --- 64K Sequential: VMware-typischer I/O-Size, Throughput ---
    @{ Name = "64K_SeqRead_QD8";   Args = "-b64K -si64K -w0   -o8  -t$Threads -d$Duration -W$Warmup -Sh -L" }
    @{ Name = "64K_SeqWrite_QD8";  Args = "-b64K -si64K -w100 -o8  -t$Threads -d$Duration -W$Warmup -Sh -L" }

    # --- 1M Sequential: Backup / Large-Block Throughput ---
    @{ Name = "1M_SeqRead_QD4";    Args = "-b1M  -si1M -w0   -o4  -t$Threads -d$Duration -W$Warmup -Sh -L" }
    @{ Name = "1M_SeqWrite_QD4";   Args = "-b1M  -si1M -w100 -o4  -t$Threads -d$Duration -W$Warmup -Sh -L" }
)
#endregion

#region --- Testdatei vorbereiten ---
Write-Host "Erstelle/verwende Testdatei (${FileSizeGB} GB)..." -ForegroundColor Yellow
$createArgs = "-c${FileSizeGB}G `"$TargetPath`" -d1 -W0 -b1M -w100 -Sh"
Start-Process -FilePath $DiskSpdPath -ArgumentList $createArgs -Wait -NoNewWindow | Out-Null
Write-Host "Testdatei bereit." -ForegroundColor Green
Write-Host ""
#endregion

#region --- Testdurchlauf ---
$summary = @()

foreach ($test in $tests) {
    $name    = $test.Name
    $xmlOut  = Join-Path $OutputDir "$name.xml"
    $txtOut  = Join-Path $OutputDir "$name.txt"
    $argLine = "$($test.Args) -Rxml `"$TargetPath`""

    Write-Host "[$($tests.IndexOf($test)+1)/$($tests.Count)] $name" -ForegroundColor Cyan
    Write-Host "  $argLine" -ForegroundColor DarkGray

    # XML-Report
    $proc = Start-Process -FilePath $DiskSpdPath -ArgumentList $argLine `
            -RedirectStandardOutput $xmlOut -NoNewWindow -Wait -PassThru

    # Zusätzlich Text-Report (lesbar)
    $txtArgs = ($test.Args) + " `"$TargetPath`""
    Start-Process -FilePath $DiskSpdPath -ArgumentList $txtArgs `
            -RedirectStandardOutput $txtOut -NoNewWindow -Wait | Out-Null

    if ($proc.ExitCode -ne 0) {
        Write-Warning "  ExitCode $($proc.ExitCode) – Test u.U. fehlgeschlagen."
        continue
    }

    # XML parsen
    try {
        [xml]$xml = Get-Content $xmlOut -Raw
        $thread   = $xml.Results.TimeSpan
        $readBps  = [int64]($thread.Thread.Target.ReadBytes      | Measure-Object -Sum).Sum
        $writeBps = [int64]($thread.Thread.Target.WriteBytes     | Measure-Object -Sum).Sum
        $readIO   = [int64]($thread.Thread.Target.ReadCount      | Measure-Object -Sum).Sum
        $writeIO  = [int64]($thread.Thread.Target.WriteCount     | Measure-Object -Sum).Sum
        $sec      = [double]$thread.TestTimeSeconds

        $summary += [PSCustomObject]@{
            Test        = $name
            Duration_s  = [math]::Round($sec, 1)
            Read_IOPS   = if ($sec -gt 0) { [math]::Round($readIO  / $sec, 0) } else { 0 }
            Write_IOPS  = if ($sec -gt 0) { [math]::Round($writeIO / $sec, 0) } else { 0 }
            Total_IOPS  = if ($sec -gt 0) { [math]::Round(($readIO + $writeIO) / $sec, 0) } else { 0 }
            Read_MBps   = if ($sec -gt 0) { [math]::Round($readBps  / 1MB / $sec, 1) } else { 0 }
            Write_MBps  = if ($sec -gt 0) { [math]::Round($writeBps / 1MB / $sec, 1) } else { 0 }
            Total_MBps  = if ($sec -gt 0) { [math]::Round(($readBps + $writeBps) / 1MB / $sec, 1) } else { 0 }
            AvgLat_ms   = [math]::Round([double]$xml.Results.Latency.AverageMilliseconds, 3)
            P50_ms      = [math]::Round(([double]($xml.Results.Latency.Bucket | Where-Object { $_.Percentile -eq '50' } | Select-Object -First 1).ReadMilliseconds), 3)
            P95_ms      = [math]::Round(([double]($xml.Results.Latency.Bucket | Where-Object { $_.Percentile -eq '95' } | Select-Object -First 1).ReadMilliseconds), 3)
            P99_ms      = [math]::Round(([double]($xml.Results.Latency.Bucket | Where-Object { $_.Percentile -eq '99' } | Select-Object -First 1).ReadMilliseconds), 3)
            P999_ms     = [math]::Round(([double]($xml.Results.Latency.Bucket | Where-Object { $_.Percentile -eq '99.9' } | Select-Object -First 1).ReadMilliseconds), 3)
        }

        $last = $summary[-1]
        Write-Host ("  -> {0} IOPS | {1} MB/s | avg {2} ms | p99 {3} ms" -f `
            $last.Total_IOPS, $last.Total_MBps, $last.AvgLat_ms, $last.P99_ms) -ForegroundColor Green
    }
    catch {
        Write-Warning "  XML-Parsing fehlgeschlagen: $_"
    }

    Write-Host ""
}
#endregion

#region --- Zusammenfassung ---
$csvPath = Join-Path $OutputDir "_Summary.csv"
$summary | Export-Csv -Path $csvPath -NoTypeInformation -Encoding UTF8

Write-Host "=== Zusammenfassung ===" -ForegroundColor Cyan
$summary | Format-Table -AutoSize

Write-Host ""
Write-Host "Alle Ergebnisse: $OutputDir" -ForegroundColor Green
Write-Host "CSV-Summary:     $csvPath" -ForegroundColor Green

# Testdatei aufräumen? (auskommentiert – für Wiederholungsläufe lassen)
# Remove-Item $TargetPath -Force
#endregion
