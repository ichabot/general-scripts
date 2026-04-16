<#
.SYNOPSIS
    Storage-Benchmark fuer Windows Server VM auf VMware mit FC-SSD-SAN (z.B. Dell ME5024).

.DESCRIPTION
    DiskSpd-Testbatterie:
      - 4K random read/write (IOPS + Latenz, QD-Scan)
      - 8K 70/30 mixed (OLTP)
      - 64K sequential read/write (Throughput)
      - 1M sequential read/write (Backup / Large-Block)
    Ergebnisse als XML + CSV-Summary.

.PARAMETER TargetPath
    Pfad auf dem zu testenden Volume (z.B. E:\diskspd\test.dat).

.PARAMETER FileSizeGB
    Groesse der Testdatei. Sollte groesser als SAN-Cache UND groesser als VM-RAM sein.

.PARAMETER Duration
    Testdauer pro Run in Sekunden.

.PARAMETER Threads
    Worker-Threads. Default = logische CPUs der VM.

.PARAMETER OutputDir
    Zielverzeichnis fuer Reports.

.PARAMETER DiskSpdPath
    Optionaler expliziter Pfad zu diskspd.exe.

.EXAMPLE
    .\Invoke-StoragePerfTest.ps1 -TargetPath "E:\diskspd\test.dat" -FileSizeGB 50 -Duration 60

.NOTES
    DiskSpd-Suche (in dieser Reihenfolge):
      1. -DiskSpdPath Parameter
      2. Script-Verzeichnis und Unterordner amd64
      3. C:\Tools\diskspd\amd64\diskspd.exe
      4. PATH
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

    [string]$DiskSpdPath = ""
)

$ErrorActionPreference = 'Stop'

# --- DiskSpd lokalisieren ---
function Find-DiskSpd {
    param([string]$Explicit)

    if ($Explicit -and (Test-Path $Explicit)) { return (Resolve-Path $Explicit).Path }

    $scriptDir = $PSScriptRoot
    if (-not $scriptDir) { $scriptDir = Split-Path -Parent $MyInvocation.PSCommandPath }
    if (-not $scriptDir) { $scriptDir = (Get-Location).Path }

    $candidates = @(
        (Join-Path $scriptDir 'diskspd.exe'),
        (Join-Path $scriptDir 'amd64\diskspd.exe'),
        'C:\Tools\diskspd\amd64\diskspd.exe'
    )

    foreach ($c in $candidates) {
        if (Test-Path $c) { return (Resolve-Path $c).Path }
    }

    $cmd = Get-Command diskspd.exe -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }

    return $null
}

$DiskSpd = Find-DiskSpd -Explicit $DiskSpdPath
if (-not $DiskSpd) {
    throw "diskspd.exe nicht gefunden. Neben das Script legen oder mit -DiskSpdPath angeben. Download: https://github.com/microsoft/diskspd/releases"
}

# --- Output-Verzeichnis ---
if (-not (Test-Path $OutputDir)) {
    New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
}

$targetDir = Split-Path $TargetPath -Parent
if ($targetDir -and -not (Test-Path $targetDir)) {
    New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
}

Write-Host "=== Storage Performance Test ===" -ForegroundColor Cyan
Write-Host "Target:    $TargetPath"
Write-Host "FileSize:  $FileSizeGB GB"
Write-Host "Duration:  $Duration s (Warmup $Warmup s)"
Write-Host "Threads:   $Threads"
Write-Host "Output:    $OutputDir"
Write-Host "DiskSpd:   $DiskSpd"
Write-Host ""

# --- Pre-Flight: VM-Konfiguration pruefen und loggen ---
Write-Host "=== System-Info ===" -ForegroundColor Cyan

$cs        = Get-CimInstance Win32_ComputerSystem
$os        = Get-CimInstance Win32_OperatingSystem
$cpu       = Get-CimInstance Win32_Processor | Select-Object -First 1
$bios      = Get-CimInstance Win32_BIOS
$ramGB     = [math]::Round($cs.TotalPhysicalMemory / 1GB, 1)
$logCPUs   = [Environment]::ProcessorCount
$physCPUs  = $cs.NumberOfProcessors
$coresTot  = $cs.NumberOfLogicalProcessors
$isVM      = $cs.Model -match 'VMware|Virtual|KVM|Hyper-V|Xen'
$hypervisor = if ($cs.Model -match 'VMware') { 'VMware' }
              elseif ($cs.Model -match 'Virtual') { 'Hyper-V' }
              elseif ($bios.Manufacturer -match 'Xen') { 'Xen' }
              elseif ($cs.Model -match 'KVM') { 'KVM' }
              else { 'Physical/Unknown' }

# Ziellaufwerk
$targetRoot = (Split-Path $TargetPath -Qualifier)
if (-not $targetRoot) { $targetRoot = (Split-Path (Resolve-Path -LiteralPath (Split-Path $TargetPath -Parent)).Path -Qualifier) }
$vol = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='$targetRoot'"
$volFreeGB  = if ($vol) { [math]::Round($vol.FreeSpace / 1GB, 1) } else { 0 }
$volTotalGB = if ($vol) { [math]::Round($vol.Size / 1GB, 1) } else { 0 }

# Storage-Controller (VMware PVSCSI erkennen)
$scsiCtrl = Get-CimInstance Win32_SCSIController | Select-Object -ExpandProperty Name
$pvscsi   = $scsiCtrl | Where-Object { $_ -match 'VMware PVSCSI|Paravirtual' }

# VMware Tools
$vmtools = Get-Service -Name 'VMTools' -ErrorAction SilentlyContinue

$sysInfo = [ordered]@{
    Hostname        = $env:COMPUTERNAME
    OS              = $os.Caption
    Model           = $cs.Model
    Manufacturer    = $cs.Manufacturer
    Hypervisor      = $hypervisor
    CPU             = $cpu.Name.Trim()
    CPU_Sockets     = $physCPUs
    CPU_LogicalCores = $coresTot
    RAM_GB          = $ramGB
    Volume          = $targetRoot
    Volume_Total_GB = $volTotalGB
    Volume_Free_GB  = $volFreeGB
    SCSIController  = ($scsiCtrl -join '; ')
    VMwareTools     = if ($vmtools) { $vmtools.Status } else { 'not installed' }
    DiskSpdPath     = $DiskSpd
    TestFile        = $TargetPath
    TestFileSize_GB = $FileSizeGB
    Threads         = $Threads
    Duration_s      = $Duration
    Warmup_s        = $Warmup
    Timestamp       = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
}

$sysInfo.GetEnumerator() | ForEach-Object {
    Write-Host ("  {0,-18}: {1}" -f $_.Key, $_.Value)
}
Write-Host ""

# --- Warnungen ---
$warnings = @()

if ($Threads -lt 4) {
    $warnings += "Nur $Threads vCPU(s) - Bench wird CPU-bound bevor das SAN ausgelastet ist. Empfehlung: 8+ vCPUs fuer Storage-Tests."
}
if ($FileSizeGB -lt ($ramGB * 2)) {
    $warnings += "Testfile ($FileSizeGB GB) ist kleiner als 2x RAM ($ramGB GB) - Caching kann Ergebnisse verfaelschen. Empfehlung: mindestens $([math]::Ceiling($ramGB * 2)) GB."
}
if ($FileSizeGB -lt 32) {
    $warnings += "Testfile < 32 GB - typischer SAN-Controller-Cache (ME5024: 8 GB/Ctrl) kann Ergebnisse verfaelschen."
}
if ($volFreeGB -gt 0 -and ($volFreeGB - $FileSizeGB) -lt 5) {
    $warnings += "Freier Speicher auf $targetRoot nur $volFreeGB GB - nach Testfile-Erstellung < 5 GB frei."
}
if ($isVM -and $hypervisor -eq 'VMware' -and -not $pvscsi) {
    $warnings += "Kein VMware PVSCSI-Controller erkannt. LSI Logic SAS ist deutlich langsamer bei 4K random I/O. Empfehlung: Test-VMDK an PVSCSI-Controller haengen."
}
if ($isVM -and $hypervisor -eq 'VMware' -and $vmtools -and $vmtools.Status -ne 'Running') {
    $warnings += "VMware Tools nicht 'Running' - Treiber/Timer koennen Messung beeinflussen."
}
if (-not $isVM) {
    $warnings += "System sieht nicht nach VM aus (Model: $($cs.Model)). Script war fuer VMware-VM gedacht."
}

if ($warnings.Count -gt 0) {
    Write-Host "=== WARNUNGEN ===" -ForegroundColor Yellow
    foreach ($w in $warnings) { Write-Host "  ! $w" -ForegroundColor Yellow }
    Write-Host ""
    $resp = Read-Host "Trotzdem fortfahren? (j/N)"
    if ($resp -notmatch '^[jJyY]') {
        Write-Host "Abgebrochen." -ForegroundColor Red
        exit 1
    }
    Write-Host ""
}

# System-Info fuer Summary speichern
$sysInfoPath = Join-Path $OutputDir "_SystemInfo.json"
$sysInfo | ConvertTo-Json | Set-Content -Path $sysInfoPath -Encoding UTF8

$warnPath = Join-Path $OutputDir "_Warnings.txt"
if ($warnings.Count -gt 0) {
    $warnings | Set-Content -Path $warnPath -Encoding UTF8
}

# --- Testmatrix ---
$tests = @(
    @{ Name = "4K_RandRead_QD1";     Args = "-b4K  -r -w0   -o1  -t$Threads -d$Duration -W$Warmup -Sh -L" }
    @{ Name = "4K_RandRead_QD8";     Args = "-b4K  -r -w0   -o8  -t$Threads -d$Duration -W$Warmup -Sh -L" }
    @{ Name = "4K_RandRead_QD32";    Args = "-b4K  -r -w0   -o32 -t$Threads -d$Duration -W$Warmup -Sh -L" }
    @{ Name = "4K_RandWrite_QD1";    Args = "-b4K  -r -w100 -o1  -t$Threads -d$Duration -W$Warmup -Sh -L" }
    @{ Name = "4K_RandWrite_QD32";   Args = "-b4K  -r -w100 -o32 -t$Threads -d$Duration -W$Warmup -Sh -L" }
    @{ Name = "8K_OLTP_70R30W_QD16"; Args = "-b8K  -r -w30  -o16 -t$Threads -d$Duration -W$Warmup -Sh -L" }
    @{ Name = "64K_SeqRead_QD8";     Args = "-b64K -si64K -w0   -o8  -t$Threads -d$Duration -W$Warmup -Sh -L" }
    @{ Name = "64K_SeqWrite_QD8";    Args = "-b64K -si64K -w100 -o8  -t$Threads -d$Duration -W$Warmup -Sh -L" }
    @{ Name = "1M_SeqRead_QD4";      Args = "-b1M  -si1M -w0   -o4  -t$Threads -d$Duration -W$Warmup -Sh -L" }
    @{ Name = "1M_SeqWrite_QD4";     Args = "-b1M  -si1M -w100 -o4  -t$Threads -d$Duration -W$Warmup -Sh -L" }
)

# --- Testdatei vorbereiten ---
$needed = [int64]$FileSizeGB * 1GB

if (Test-Path $TargetPath) {
    $existing = (Get-Item $TargetPath).Length
    if ($existing -eq $needed) {
        Write-Host "Testdatei existiert bereits mit korrekter Groesse ($FileSizeGB GB)." -ForegroundColor Green
    } else {
        Write-Host "Testdatei existiert mit falscher Groesse, wird neu erstellt..." -ForegroundColor Yellow
        Remove-Item $TargetPath -Force
    }
}

if (-not (Test-Path $TargetPath)) {
    Write-Host "Erstelle Testdatei ($FileSizeGB GB) via fsutil..." -ForegroundColor Yellow
    # fsutil ist robuster als diskspd -c, gerade bei -Sh
    $fsutilOutput = & fsutil file createnew $TargetPath $needed 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Host $fsutilOutput -ForegroundColor Red
        throw "fsutil konnte Testdatei nicht erstellen. Pfad pruefen, als Admin ausfuehren, Laufwerk-Space pruefen."
    }
    # Optional: mit Zufallsdaten beschreiben, damit Dedup/Compression auf SAN nicht reinpfuschen
    Write-Host "Fuelle Testdatei mit Daten (damit SAN-Dedup/Compression neutralisiert)..." -ForegroundColor Yellow
    $fillArgs = @("-d30", "-b1M", "-w100", "-t2", "-o4", $TargetPath)
    $fillOut = & $DiskSpd $fillArgs 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Host $fillOut -ForegroundColor Red
        throw "Fill-Step fehlgeschlagen."
    }
}

if (-not (Test-Path $TargetPath)) {
    throw "Testdatei nach Erstellung nicht vorhanden: $TargetPath"
}
Write-Host "Testdatei bereit: $TargetPath ($([math]::Round((Get-Item $TargetPath).Length/1GB,1)) GB)" -ForegroundColor Green
Write-Host ""

# --- Testdurchlauf ---
$summary = @()
$i = 0
foreach ($test in $tests) {
    $i++
    $name   = $test.Name
    $xmlOut = Join-Path $OutputDir "$name.xml"
    $txtOut = Join-Path $OutputDir "$name.txt"

    Write-Host "[$i/$($tests.Count)] $name" -ForegroundColor Cyan

    $xmlArgs = "$($test.Args) -Rxml `"$TargetPath`""
    $proc = Start-Process -FilePath $DiskSpd -ArgumentList $xmlArgs `
            -RedirectStandardOutput $xmlOut -NoNewWindow -Wait -PassThru

    $txtArgs = "$($test.Args) `"$TargetPath`""
    Start-Process -FilePath $DiskSpd -ArgumentList $txtArgs `
            -RedirectStandardOutput $txtOut -NoNewWindow -Wait | Out-Null

    if ($proc.ExitCode -ne 0) {
        Write-Warning "  ExitCode $($proc.ExitCode)"
        continue
    }

    try {
        [xml]$xml = Get-Content $xmlOut -Raw
        $ts       = $xml.Results.TimeSpan
        $sec      = [double]$ts.TestTimeSeconds

        $readBps  = [int64]0; $writeBps = [int64]0
        $readIO   = [int64]0; $writeIO  = [int64]0
        foreach ($t in $ts.Thread) {
            foreach ($tg in $t.Target) {
                $readBps  += [int64]$tg.ReadBytes
                $writeBps += [int64]$tg.WriteBytes
                $readIO   += [int64]$tg.ReadCount
                $writeIO  += [int64]$tg.WriteCount
            }
        }

        function Get-Pct($pct) {
            $b = $xml.Results.Latency.Bucket | Where-Object { $_.Percentile -eq $pct } | Select-Object -First 1
            if ($b) { return [math]::Round([double]$b.ReadMilliseconds, 3) } else { return 0 }
        }

        $row = [PSCustomObject]@{
            Test       = $name
            Duration_s = [math]::Round($sec, 1)
            Read_IOPS  = if ($sec -gt 0) { [math]::Round($readIO  / $sec, 0) } else { 0 }
            Write_IOPS = if ($sec -gt 0) { [math]::Round($writeIO / $sec, 0) } else { 0 }
            Total_IOPS = if ($sec -gt 0) { [math]::Round(($readIO + $writeIO) / $sec, 0) } else { 0 }
            Read_MBps  = if ($sec -gt 0) { [math]::Round($readBps  / 1MB / $sec, 1) } else { 0 }
            Write_MBps = if ($sec -gt 0) { [math]::Round($writeBps / 1MB / $sec, 1) } else { 0 }
            Total_MBps = if ($sec -gt 0) { [math]::Round(($readBps + $writeBps) / 1MB / $sec, 1) } else { 0 }
            AvgLat_ms  = [math]::Round([double]$xml.Results.Latency.AverageMilliseconds, 3)
            P50_ms     = Get-Pct '50'
            P95_ms     = Get-Pct '95'
            P99_ms     = Get-Pct '99'
            P999_ms    = Get-Pct '99.9'
        }
        $summary += $row

        Write-Host ("  -> {0} IOPS | {1} MB/s | avg {2} ms | p99 {3} ms" -f `
            $row.Total_IOPS, $row.Total_MBps, $row.AvgLat_ms, $row.P99_ms) -ForegroundColor Green
    }
    catch {
        Write-Warning "  XML-Parsing fehlgeschlagen: $_"
    }
    Write-Host ""
}

# --- Summary ---
$csvPath = Join-Path $OutputDir "_Summary.csv"
$summary | Export-Csv -Path $csvPath -NoTypeInformation -Encoding UTF8

Write-Host "=== Summary ===" -ForegroundColor Cyan
$summary | Format-Table -AutoSize

Write-Host ""
Write-Host "Reports: $OutputDir" -ForegroundColor Green
Write-Host "CSV:     $csvPath" -ForegroundColor Green
