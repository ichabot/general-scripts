<#
.SYNOPSIS
    Storage-Benchmark fuer Windows Server VM auf VMware mit FC-SSD-SAN (Dell ME5024 o.ae.).

.DESCRIPTION
    DiskSpd-Wrapper nach offizieller Microsoft-Doku:
      https://github.com/Microsoft/diskspd/wiki/Command-line-and-parameters
      https://github.com/Microsoft/diskspd/wiki/Customizing-tests
      https://github.com/Microsoft/diskspd/wiki/Sample-command-lines
      https://github.com/Microsoft/diskspd/wiki/Analyzing-test-results

    Testmatrix:
      4K random  read/write (QD-Scan)   - IOPS + Latenz
      8K random  70R/30W                - OLTP/SQL-Profil
      64K sequential read/write         - VM-I/O-typisch
      1M sequential read/write          - Backup/Large-Block

    Pflicht-Flags (nach MS-Doku):
      -Z1M  : 1 MB Random-Buffer fuer Writes -> anti Dedup/Compression
      -Sh   : Software- + Hardware-Write-Cache aus
      -L    : Latenz-Percentile
      -Rxml : XML-Output
    Target-Pfad ist IMMER das letzte Argument.

    PowerShell-Problem mit native command stderr: umgangen via Start-Process
    mit RedirectStandardOutput/Error. Kein '2>&1'.

.PARAMETER TargetPath
    Pfad zur Testdatei (z.B. E:\bench\test.dat).

.PARAMETER FileSizeGB
    Groesse der Testdatei. Muss > SAN-Cache UND > VM-RAM sein.

.PARAMETER Duration
    Testdauer pro Run in Sekunden.

.PARAMETER Warmup
    Warmup pro Run in Sekunden (nicht gemessen).

.PARAMETER Threads
    Worker-Threads pro Test.

.PARAMETER OutputDir
    Zielverzeichnis fuer Reports.

.PARAMETER DiskSpdPath
    Expliziter Pfad zu diskspd.exe (sonst Auto-Discovery).

.EXAMPLE
    .\Invoke-StoragePerfTest.ps1 -TargetPath E:\bench\test.dat -FileSizeGB 64 -Duration 60
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$TargetPath,
    [int]$FileSizeGB = 64,
    [int]$Duration   = 60,
    [int]$Warmup     = 15,
    [int]$Threads    = [Environment]::ProcessorCount,
    [string]$OutputDir   = "C:\StoragePerf\Results_$(Get-Date -Format 'yyyyMMdd_HHmmss')",
    [string]$DiskSpdPath = ""
)

$ErrorActionPreference = 'Stop'

#==============================================================================
# 1) DiskSpd lokalisieren
#==============================================================================
function Find-DiskSpd {
    param([string]$Explicit)
    if ($Explicit -and (Test-Path $Explicit)) { return (Resolve-Path $Explicit).Path }
    $scriptDir = $PSScriptRoot
    if (-not $scriptDir) { $scriptDir = Split-Path -Parent $MyInvocation.PSCommandPath }
    if (-not $scriptDir) { $scriptDir = (Get-Location).Path }
    foreach ($c in @(
        (Join-Path $scriptDir 'diskspd.exe'),
        (Join-Path $scriptDir 'amd64\diskspd.exe'),
        'C:\Tools\diskspd\amd64\diskspd.exe'
    )) {
        if (Test-Path $c) { return (Resolve-Path $c).Path }
    }
    $cmd = Get-Command diskspd.exe -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    return $null
}

$DiskSpd = Find-DiskSpd -Explicit $DiskSpdPath
if (-not $DiskSpd) {
    throw "diskspd.exe nicht gefunden. Neben das Script legen oder -DiskSpdPath angeben. Download: https://github.com/microsoft/diskspd/releases"
}

#==============================================================================
# 2) Helper: DiskSpd sauber aufrufen (stdout/stderr getrennt, keine PS-Fehler durch WARNINGs)
#==============================================================================
function Invoke-DiskSpd {
    param(
        [Parameter(Mandatory)][string[]]$Arguments,
        [string]$StdoutFile,
        [string]$StderrFile
    )
    # Argumente fuer Start-Process: Leerzeichen-Pfade quoten
    $quoted = $Arguments | ForEach-Object {
        if ($_ -match '\s' -and $_ -notmatch '^".*"$') { "`"$_`"" } else { $_ }
    }
    $splat = @{
        FilePath     = $DiskSpd
        ArgumentList = $quoted
        Wait         = $true
        NoNewWindow  = $true
        PassThru     = $true
    }
    if ($StdoutFile) { $splat.RedirectStandardOutput = $StdoutFile }
    if ($StderrFile) { $splat.RedirectStandardError  = $StderrFile }
    $proc = Start-Process @splat
    return $proc.ExitCode
}

#==============================================================================
# 3) Vorbereitung
#==============================================================================
if (-not (Test-Path $OutputDir)) { New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null }
$targetDir = Split-Path $TargetPath -Parent
if ($targetDir -and -not (Test-Path $targetDir)) {
    New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
}

Write-Host "=== Storage Performance Test (DiskSpd) ===" -ForegroundColor Cyan
Write-Host "Target:    $TargetPath"
Write-Host "FileSize:  $FileSizeGB GB"
Write-Host "Duration:  $Duration s (Warmup $Warmup s)"
Write-Host "Threads:   $Threads"
Write-Host "Output:    $OutputDir"
Write-Host "DiskSpd:   $DiskSpd"
Write-Host ""

#==============================================================================
# 4) System-Info + Pre-Flight-Checks
#==============================================================================
Write-Host "=== System-Info ===" -ForegroundColor Cyan

$cs    = Get-CimInstance Win32_ComputerSystem
$os    = Get-CimInstance Win32_OperatingSystem
$cpuInfo = Get-CimInstance Win32_Processor | Select-Object -First 1
$ramGB = [math]::Round($cs.TotalPhysicalMemory / 1GB, 1)

$hypervisor = if     ($cs.Model -match 'VMware')         { 'VMware' }
              elseif ($cs.Model -match 'Virtual Machine'){ 'Hyper-V' }
              elseif ($cs.Manufacturer -match 'Xen')     { 'Xen' }
              elseif ($cs.Model -match 'KVM')            { 'KVM' }
              else                                       { 'Physical/Unknown' }

$targetRoot = Split-Path $TargetPath -Qualifier
$vol = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='$targetRoot'" -ErrorAction SilentlyContinue
$volFreeGB  = if ($vol) { [math]::Round($vol.FreeSpace / 1GB, 1) } else { 0 }
$volTotalGB = if ($vol) { [math]::Round($vol.Size     / 1GB, 1) } else { 0 }

$scsiCtrl = (Get-CimInstance Win32_SCSIController | Select-Object -ExpandProperty Name) -join '; '
$pvscsi   = $scsiCtrl -match 'VMware PVSCSI|Paravirtual'
$vmtools  = Get-Service -Name 'VMTools' -ErrorAction SilentlyContinue

$sysInfo = [ordered]@{
    Hostname         = $env:COMPUTERNAME
    OS               = $os.Caption
    Model            = $cs.Model
    Hypervisor       = $hypervisor
    CPU              = $cpuInfo.Name.Trim()
    CPU_Sockets      = $cs.NumberOfProcessors
    CPU_LogicalCores = $cs.NumberOfLogicalProcessors
    RAM_GB           = $ramGB
    Volume           = $targetRoot
    Volume_Total_GB  = $volTotalGB
    Volume_Free_GB   = $volFreeGB
    SCSIController   = $scsiCtrl
    VMwareTools      = if ($vmtools) { $vmtools.Status.ToString() } else { 'not installed' }
    DiskSpdVersion   = (Get-Item $DiskSpd).VersionInfo.FileVersion
    TestFile         = $TargetPath
    TestFileSize_GB  = $FileSizeGB
    Threads          = $Threads
    Duration_s       = $Duration
    Warmup_s         = $Warmup
    Timestamp        = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
}
$sysInfo.GetEnumerator() | ForEach-Object { Write-Host ("  {0,-18}: {1}" -f $_.Key, $_.Value) }
Write-Host ""

$warnings = @()
if ($Threads -lt 4)               { $warnings += "Nur $Threads vCPU(s) - Bench wird CPU-bound bevor SAN ausgelastet ist. Empfehlung: 8+ vCPUs." }
if ($FileSizeGB -lt ($ramGB * 2)) { $warnings += "Testfile ($FileSizeGB GB) < 2x RAM ($ramGB GB) - Caching-Risiko. Empfehlung: min. $([math]::Ceiling($ramGB * 2)) GB." }
if ($FileSizeGB -lt 32)           { $warnings += "Testfile < 32 GB - SAN-Cache (ME5024: 8 GB pro Controller) kann Ergebnisse verfaelschen." }
if ($volFreeGB -gt 0 -and ($volFreeGB - $FileSizeGB) -lt 5) {
    $warnings += "Nach Testfile-Erstellung < 5 GB frei auf $targetRoot."
}
if ($hypervisor -eq 'VMware' -and -not $pvscsi) {
    $warnings += "Kein PVSCSI-Controller erkannt - LSI Logic SAS deutlich langsamer bei 4K random. Test-VMDK an PVSCSI-Controller haengen."
}
if ($hypervisor -eq 'VMware' -and $vmtools -and $vmtools.Status -ne 'Running') {
    $warnings += "VMware Tools Service nicht 'Running'."
}

if ($warnings.Count -gt 0) {
    Write-Host "=== WARNUNGEN ===" -ForegroundColor Yellow
    $warnings | ForEach-Object { Write-Host "  ! $_" -ForegroundColor Yellow }
    Write-Host ""
    $resp = Read-Host "Trotzdem fortfahren? (j/N)"
    if ($resp -notmatch '^[jJyY]') { Write-Host "Abgebrochen." -ForegroundColor Red; exit 1 }
    Write-Host ""
    $warnings | Set-Content -Path (Join-Path $OutputDir "_Warnings.txt") -Encoding UTF8
}

$sysInfo | ConvertTo-Json | Set-Content -Path (Join-Path $OutputDir "_SystemInfo.json") -Encoding UTF8

#==============================================================================
# 5) Testdatei erstellen (diskspd -c + Random-Fill via -Z)
#     Doku: Customizing-tests + Sample-command-lines
#==============================================================================
$needed = [int64]$FileSizeGB * 1GB

if ((Test-Path $TargetPath) -and ((Get-Item $TargetPath).Length -eq $needed)) {
    Write-Host "Testdatei existiert bereits mit korrekter Groesse." -ForegroundColor Green
} else {
    if (Test-Path $TargetPath) {
        Write-Host "Testdatei mit falscher Groesse - loesche..." -ForegroundColor Yellow
        Remove-Item $TargetPath -Force
    }

    # Create + Random-Fill in einem Aufruf:
    #   -c<size>G   : Datei dieser Groesse anlegen und beschreiben
    #   -b1M        : 1 MB Bloecke
    #   -w100       : reine Writes
    #   -Z1M        : 1 MB Random-Buffer (anti Dedup/Compression auf SAN)
    #   -d<sec>     : Dauer - muss reichen um komplette Datei zu fuellen
    #   -t1 -o8     : 1 Thread, 8 outstanding I/Os (gute seq. Write-Performance)
    # Target IMMER zuletzt.
    $fillSec = [math]::Max(180, [math]::Ceiling($FileSizeGB * 3))
    Write-Host "Erstelle Testdatei ($FileSizeGB GB) via diskspd -c (Random-Fill, max $fillSec s)..." -ForegroundColor Yellow

    $createArgs = @(
        "-c$($FileSizeGB)G",
        "-b1M",
        "-w100",
        "-Z1M",
        "-d$fillSec",
        "-t1",
        "-o8",
        $TargetPath
    )
    $stdoutFile = Join-Path $OutputDir "_create.stdout.txt"
    $stderrFile = Join-Path $OutputDir "_create.stderr.txt"
    $exit = Invoke-DiskSpd -Arguments $createArgs -StdoutFile $stdoutFile -StderrFile $stderrFile

    if ($exit -ne 0) {
        Write-Host "---stdout---" -ForegroundColor Red
        Get-Content $stdoutFile -ErrorAction SilentlyContinue | Write-Host -ForegroundColor Red
        Write-Host "---stderr---" -ForegroundColor Red
        Get-Content $stderrFile -ErrorAction SilentlyContinue | Write-Host -ForegroundColor Red
        throw "diskspd create fehlgeschlagen (ExitCode $exit)"
    }
    if (-not (Test-Path $TargetPath)) { throw "Testdatei nach create nicht vorhanden: $TargetPath" }
}

$actualGB = [math]::Round((Get-Item $TargetPath).Length / 1GB, 1)
Write-Host "Testdatei bereit: $TargetPath ($actualGB GB)" -ForegroundColor Green
Write-Host ""

#==============================================================================
# 6) Testmatrix
#    Doku: Sample-command-lines
#==============================================================================
# Gemeinsame Flags fuer ALLE Tests
$common = @("-t$Threads", "-d$Duration", "-W$Warmup", "-Sh", "-L", "-Z1M")

$tests = @(
    # --- 4K Random Read: QD-Scan fuer IOPS-/Latenz-Kurve ---
    @{ Name = "4K_RandRead_QD1";     Args = @("-b4K",  "-r", "-w0",   "-o1")  + $common }
    @{ Name = "4K_RandRead_QD8";     Args = @("-b4K",  "-r", "-w0",   "-o8")  + $common }
    @{ Name = "4K_RandRead_QD32";    Args = @("-b4K",  "-r", "-w0",   "-o32") + $common }
    # --- 4K Random Write ---
    @{ Name = "4K_RandWrite_QD1";    Args = @("-b4K",  "-r", "-w100", "-o1")  + $common }
    @{ Name = "4K_RandWrite_QD32";   Args = @("-b4K",  "-r", "-w100", "-o32") + $common }
    # --- 8K 70/30 Mixed: OLTP-Profil ---
    @{ Name = "8K_OLTP_70R30W_QD16"; Args = @("-b8K",  "-r", "-w30",  "-o16") + $common }
    # --- 64K Sequential: VMware-typisch ---
    # -si<size> = interlocked sequential (shared offset, Threads kooperieren)
    @{ Name = "64K_SeqRead_QD8";     Args = @("-b64K", "-si64K", "-w0",   "-o8") + $common }
    @{ Name = "64K_SeqWrite_QD8";    Args = @("-b64K", "-si64K", "-w100", "-o8") + $common }
    # --- 1M Sequential: Backup/Large-Block ---
    @{ Name = "1M_SeqRead_QD4";      Args = @("-b1M",  "-si1M",  "-w0",   "-o4") + $common }
    @{ Name = "1M_SeqWrite_QD4";     Args = @("-b1M",  "-si1M",  "-w100", "-o4") + $common }
)

#==============================================================================
# 7) Testdurchlauf
#==============================================================================
$summary = @()
$i = 0
foreach ($test in $tests) {
    $i++
    $name   = $test.Name
    $xmlOut = Join-Path $OutputDir "$name.xml"
    $txtOut = Join-Path $OutputDir "$name.txt"
    $errOut = Join-Path $OutputDir "$name.stderr.txt"

    Write-Host "[$i/$($tests.Count)] $name" -ForegroundColor Cyan

    # XML-Run: -Rxml + Target als letztes Argument
    $xmlArgs = @($test.Args) + @("-Rxml", $TargetPath)
    $exit = Invoke-DiskSpd -Arguments $xmlArgs -StdoutFile $xmlOut -StderrFile $errOut

    # Zusaetzlich Text-Run (lesbarer Report)
    $txtArgs = @($test.Args) + @($TargetPath)
    $null = Invoke-DiskSpd -Arguments $txtArgs -StdoutFile $txtOut

    if ($exit -ne 0) {
        Write-Warning "  ExitCode $exit - siehe $errOut"
        continue
    }

    # XML parsen
    # WICHTIG: korrekter Pfad laut MS-Doku = Results.TimeSpan.*
    try {
        [xml]$xml = Get-Content $xmlOut -Raw
        $ts  = $xml.Results.TimeSpan
        $sec = [double]$ts.TestTimeSeconds

        $readBps = $writeBps = $readIO = $writeIO = [int64]0
        foreach ($t in @($ts.Thread)) {
            foreach ($tg in @($t.Target)) {
                $readBps  += [int64]$tg.ReadBytes
                $writeBps += [int64]$tg.WriteBytes
                $readIO   += [int64]$tg.ReadCount
                $writeIO  += [int64]$tg.WriteCount
            }
        }

        # Latenz-Buckets: TimeSpan.Latency.Bucket[] mit Percentile als String
        function Get-Pct {
            param($latency, [string]$pct)
            if (-not $latency -or -not $latency.Bucket) { return 0 }
            $b = $latency.Bucket | Where-Object { $_.Percentile -eq $pct } | Select-Object -First 1
            if (-not $b) { return 0 }
            # Je nach Test Read/Write/Total. Wir nehmen Total wenn vorhanden, sonst Read oder Write.
            $val = if     ($b.TotalMilliseconds) { $b.TotalMilliseconds }
                   elseif ($b.ReadMilliseconds)  { $b.ReadMilliseconds }
                   elseif ($b.WriteMilliseconds) { $b.WriteMilliseconds }
                   else { 0 }
            return [math]::Round([double]$val, 3)
        }

        $lat = $ts.Latency

        $row = [PSCustomObject]@{
            Test       = $name
            Duration_s = [math]::Round($sec, 1)
            Read_IOPS  = if ($sec -gt 0) { [math]::Round($readIO  / $sec, 0) } else { 0 }
            Write_IOPS = if ($sec -gt 0) { [math]::Round($writeIO / $sec, 0) } else { 0 }
            Total_IOPS = if ($sec -gt 0) { [math]::Round(($readIO + $writeIO) / $sec, 0) } else { 0 }
            Read_MBps  = if ($sec -gt 0) { [math]::Round($readBps  / 1MB / $sec, 1) } else { 0 }
            Write_MBps = if ($sec -gt 0) { [math]::Round($writeBps / 1MB / $sec, 1) } else { 0 }
            Total_MBps = if ($sec -gt 0) { [math]::Round(($readBps + $writeBps) / 1MB / $sec, 1) } else { 0 }
            AvgLat_ms  = if ($lat.AverageMilliseconds) { [math]::Round([double]$lat.AverageMilliseconds, 3) } else { 0 }
            P50_ms     = Get-Pct $lat '50'
            P90_ms     = Get-Pct $lat '90'
            P95_ms     = Get-Pct $lat '95'
            P99_ms     = Get-Pct $lat '99'
            P999_ms    = Get-Pct $lat '99.9'
            P9999_ms   = Get-Pct $lat '99.99'
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

#==============================================================================
# 8) Summary
#==============================================================================
$csvPath = Join-Path $OutputDir "_Summary.csv"
$summary | Export-Csv -Path $csvPath -NoTypeInformation -Encoding UTF8

Write-Host "=== Summary ===" -ForegroundColor Cyan
$summary | Format-Table -AutoSize

Write-Host ""
Write-Host "Reports: $OutputDir" -ForegroundColor Green
Write-Host "CSV:     $csvPath"   -ForegroundColor Green
