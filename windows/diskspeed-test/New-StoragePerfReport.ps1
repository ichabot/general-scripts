<#
.SYNOPSIS
    Generiert einen HTML-Report aus einem Invoke-StoragePerfTest Ergebnis-Ordner.

.DESCRIPTION
    Liest _SystemInfo.json, _Summary.csv und _Warnings.txt und baut einen
    eigenstaendigen HTML-Report (alles inline - CSS, SVG-Charts, keine Dependencies).

.PARAMETER ResultsDir
    Pfad zum Ergebnis-Ordner (z.B. C:\StoragePerf\Results_20260416_094240)

.PARAMETER Title
    Titel fuer den Report (Default: Hostname + Datum)

.PARAMETER OpenAfter
    Oeffnet den Report nach Erstellung im Default-Browser

.EXAMPLE
    .\New-StoragePerfReport.ps1 -ResultsDir C:\StoragePerf\Results_20260416_094240 -OpenAfter
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$ResultsDir,
    [string]$Title = "",
    [switch]$OpenAfter
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path $ResultsDir)) { throw "ResultsDir nicht gefunden: $ResultsDir" }

# --- Daten laden ---
$csvPath  = Join-Path $ResultsDir "_Summary.csv"
$jsonPath = Join-Path $ResultsDir "_SystemInfo.json"
$warnPath = Join-Path $ResultsDir "_Warnings.txt"

if (-not (Test-Path $csvPath))  { throw "_Summary.csv nicht gefunden in $ResultsDir" }
if (-not (Test-Path $jsonPath)) { throw "_SystemInfo.json nicht gefunden in $ResultsDir" }

$results  = Import-Csv $csvPath
$sysInfo  = Get-Content $jsonPath -Raw | ConvertFrom-Json
$warnings = if (Test-Path $warnPath) { Get-Content $warnPath } else { @() }

if (-not $Title) {
    $Title = "Storage Performance Report - $($sysInfo.Hostname) - $($sysInfo.Timestamp)"
}

# --- SVG-Chart-Helper ---
function Format-ChartValue {
    param($value, [string]$unit)
    switch ($unit) {
        'ms'   { return ("{0:N2} {1}" -f [double]$value, $unit) }
        'MB/s' {
            if ([double]$value -lt 10) { return ("{0:N1} {1}" -f [double]$value, $unit) }
            return ("{0:N0} {1}" -f [double]$value, $unit)
        }
        default { return ("{0:N0} {1}" -f [double]$value, $unit) }
    }
}

function New-BarChart {
    param(
        [string]$Heading,
        [array]$Data,        # Array of PSCustomObject with Label/Value/Unit
        [string]$BarColor = '#3b82f6',
        [int]$Width = 760,
        [int]$BarHeight = 28,
        [int]$BarGap = 8,
        [int]$LabelWidth = 220,
        [int]$ValueSpace = 100   # Reserve rechts fuer Werte die nicht in Balken passen
    )
    if (-not $Data -or $Data.Count -eq 0) { return "" }
    $max = 0.0
    foreach ($d in $Data) { if ($d.Value -gt $max) { $max = [double]$d.Value } }
    if ($max -eq 0) { $max = 1 }

    $chartWidth = $Width - $LabelWidth - $ValueSpace
    $height = ($BarHeight + $BarGap) * $Data.Count + 20

    $svg = "<svg class=""chart"" viewBox=""0 0 $Width $height"" xmlns=""http://www.w3.org/2000/svg"" role=""img"" aria-label=""$Heading"">`n"
    $y = 10
    foreach ($d in $Data) {
        $val = [double]$d.Value
        $barWidth = if ($max -gt 0) { [math]::Round(($val / $max) * $chartWidth, 0) } else { 0 }
        # Minimum-Breite damit auch Null-Werte/kleine Werte sichtbar sind
        if ($val -gt 0 -and $barWidth -lt 2) { $barWidth = 2 }

        $valText = Format-ChartValue $val $d.Unit
        $textY   = $y + ($BarHeight / 2) + 4
        # Geschaetzte Textbreite (~6.5 px pro Zeichen bei 11px monospace)
        $textEstWidth = $valText.Length * 6.5
        # Entscheidung: Text in Balken wenn er reinpasst (mit 12px Padding), sonst rechts daneben
        $textInside = $barWidth -ge ($textEstWidth + 12)

        $svg += "  <text x=""$($LabelWidth - 8)"" y=""$textY"" text-anchor=""end"" class=""chart-label"">$($d.Label)</text>`n"
        $svg += "  <rect x=""$LabelWidth"" y=""$y"" width=""$barWidth"" height=""$BarHeight"" rx=""3"" fill=""$BarColor"" opacity=""0.9""/>`n"
        if ($textInside) {
            $textX = $LabelWidth + $barWidth - 6
            $svg += "  <text x=""$textX"" y=""$textY"" text-anchor=""end"" class=""chart-value-inside"">$valText</text>`n"
        } else {
            $textX = $LabelWidth + $barWidth + 6
            $svg += "  <text x=""$textX"" y=""$textY"" class=""chart-value"">$valText</text>`n"
        }
        $y += ($BarHeight + $BarGap)
    }
    $svg += "</svg>"
    return $svg
}

# --- Daten fuer Charts aufbereiten ---
# WICHTIG: PSCustomObject, nicht Hashtable - sonst klappt Measure-Object -Property nicht
$iopsData = @($results | Where-Object { $_.Test -match '^(4K|8K)' } | ForEach-Object {
    [PSCustomObject]@{ Label = $_.Test; Value = [double]$_.Total_IOPS; Unit = "IOPS" }
})

$tputData = @($results | ForEach-Object {
    [PSCustomObject]@{ Label = $_.Test; Value = [double]$_.Total_MBps; Unit = "MB/s" }
})

$latData = @($results | ForEach-Object {
    [PSCustomObject]@{ Label = $_.Test; Value = [double]$_.P99_ms; Unit = "ms" }
})

# KPIs berechnen - robust gegen leere Arrays UND deutsche Dezimalzahlen in CSV
# Measure-Object parst String-Properties mit Invariant Culture (",") -> falsch bei "3027,5"
# Daher manuelle Schleife mit [double]-Cast (culture-aware)
function Get-Max {
    param($items, [string]$prop)
    $max = 0.0
    foreach ($item in $items) {
        $raw = $item.$prop
        if ($null -eq $raw -or "$raw" -eq '') { continue }
        try {
            $val = [double]$raw
            if ($val -gt $max) { $max = $val }
        } catch { }
    }
    return $max
}

$peakReadIOPS  = Get-Max $results 'Read_IOPS'
$peakWriteIOPS = Get-Max $results 'Write_IOPS'
$peakReadMBps  = Get-Max $results 'Read_MBps'
$peakWriteMBps = Get-Max $results 'Write_MBps'

# --- HTML zusammenbauen ---
$chartIOPS = New-BarChart -Heading "Random IOPS" -Data $iopsData -BarColor '#3b82f6'
$chartTput = New-BarChart -Heading "Throughput (MB/s)" -Data $tputData -BarColor '#10b981'
$chartLat  = New-BarChart -Heading "Latency P99 (ms)" -Data $latData  -BarColor '#f59e0b'

# System-Info-Tabelle
$sysRows = ""
$sysInfo.PSObject.Properties | ForEach-Object {
    $sysRows += "      <tr><th>$($_.Name)</th><td>$($_.Value)</td></tr>`n"
}

# Warnungs-Block
$warnBlock = ""
if ($warnings.Count -gt 0) {
    $warnItems = ($warnings | ForEach-Object { "        <li>$_</li>" }) -join "`n"
    $warnBlock = @"
  <div class="warnings">
    <h3>Pre-Flight Warnungen</h3>
    <ul>
$warnItems
    </ul>
  </div>
"@
}

# Results-Tabelle
$resultRows = ""
foreach ($r in $results) {
    $resultRows += @"
      <tr>
        <td class="test-name">$($r.Test)</td>
        <td>$([int]$r.Total_IOPS)</td>
        <td>$([int]$r.Read_IOPS)</td>
        <td>$([int]$r.Write_IOPS)</td>
        <td>$($r.Total_MBps)</td>
        <td>$($r.Read_MBps)</td>
        <td>$($r.Write_MBps)</td>
        <td>$($r.P50_ms)</td>
        <td>$($r.P95_ms)</td>
        <td>$($r.P99_ms)</td>
        <td>$($r.P999_ms)</td>
      </tr>

"@
}

$generated = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'

$html = @"
<!DOCTYPE html>
<html lang="de">
<head>
<meta charset="UTF-8">
<title>$Title</title>
<style>
  :root {
    --bg: #0f172a;
    --bg-card: #1e293b;
    --bg-row: #334155;
    --fg: #e2e8f0;
    --fg-dim: #94a3b8;
    --border: #334155;
    --accent: #3b82f6;
    --accent-green: #10b981;
    --accent-amber: #f59e0b;
    --warn: #ef4444;
  }
  * { box-sizing: border-box; }
  body {
    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif;
    background: var(--bg);
    color: var(--fg);
    margin: 0;
    padding: 0;
    line-height: 1.5;
  }
  .container { max-width: 1200px; margin: 0 auto; padding: 32px 24px; }
  h1 { font-size: 26px; margin: 0 0 4px 0; font-weight: 600; }
  h2 { font-size: 18px; margin: 32px 0 16px 0; font-weight: 600; color: var(--fg); border-bottom: 1px solid var(--border); padding-bottom: 8px; }
  h3 { font-size: 15px; margin: 0 0 12px 0; font-weight: 600; }
  .subtitle { color: var(--fg-dim); font-size: 14px; margin-bottom: 24px; }
  .kpis { display: grid; grid-template-columns: repeat(auto-fit, minmax(220px, 1fr)); gap: 12px; margin: 24px 0; }
  .kpi {
    background: var(--bg-card);
    border-radius: 8px;
    padding: 16px 18px;
    border-left: 4px solid var(--accent);
  }
  .kpi.write { border-left-color: var(--accent-green); }
  .kpi-label { font-size: 12px; color: var(--fg-dim); text-transform: uppercase; letter-spacing: 0.5px; }
  .kpi-value { font-size: 24px; font-weight: 600; margin-top: 4px; }
  .kpi-unit { font-size: 13px; color: var(--fg-dim); margin-left: 4px; }
  .card {
    background: var(--bg-card);
    border-radius: 8px;
    padding: 20px 24px;
    margin-bottom: 16px;
  }
  .chart-grid { display: grid; grid-template-columns: 1fr; gap: 16px; }
  .chart { width: 100%; height: auto; }
  .chart-label { fill: var(--fg); font-size: 12px; font-family: monospace; }
  .chart-value { fill: var(--fg-dim); font-size: 11px; font-family: monospace; }
  .chart-value-inside { fill: #ffffff; font-size: 11px; font-family: monospace; font-weight: 600; }
  table { width: 100%; border-collapse: collapse; font-size: 13px; }
  th, td { padding: 8px 10px; text-align: right; border-bottom: 1px solid var(--border); }
  th { background: var(--bg-row); color: var(--fg-dim); font-weight: 500; text-transform: uppercase; font-size: 11px; letter-spacing: 0.5px; }
  th:first-child, td:first-child { text-align: left; }
  td.test-name { font-family: monospace; color: var(--accent); }
  .sys-table th { width: 30%; text-align: left; font-family: inherit; text-transform: none; letter-spacing: 0; }
  .sys-table td { text-align: left; font-family: monospace; font-size: 12px; }
  .warnings {
    background: rgba(239, 68, 68, 0.1);
    border-left: 4px solid var(--warn);
    padding: 16px 20px;
    border-radius: 6px;
    margin: 16px 0 24px 0;
  }
  .warnings h3 { color: var(--warn); margin-bottom: 8px; }
  .warnings ul { margin: 0; padding-left: 20px; }
  .warnings li { margin: 4px 0; font-size: 14px; }
  footer { margin-top: 48px; color: var(--fg-dim); font-size: 12px; text-align: center; border-top: 1px solid var(--border); padding-top: 16px; }
  @media print {
    body { background: white; color: black; }
    .card, .kpi { background: #f8f9fa; border-color: #dee2e6; }
    .chart-label { fill: black; }
    .chart-value { fill: #555; }
  }
</style>
</head>
<body>
<div class="container">

  <h1>$Title</h1>
  <div class="subtitle">$($sysInfo.Hostname) &mdash; $($sysInfo.Hypervisor) &mdash; $($sysInfo.RAM_GB) GB RAM &mdash; $($sysInfo.CPU_LogicalCores) logical cores</div>

$warnBlock

  <div class="kpis">
    <div class="kpi">
      <div class="kpi-label">Peak Read IOPS</div>
      <div class="kpi-value">$([string]::Format('{0:N0}', [int]$peakReadIOPS))<span class="kpi-unit">IOPS</span></div>
    </div>
    <div class="kpi write">
      <div class="kpi-label">Peak Write IOPS</div>
      <div class="kpi-value">$([string]::Format('{0:N0}', [int]$peakWriteIOPS))<span class="kpi-unit">IOPS</span></div>
    </div>
    <div class="kpi">
      <div class="kpi-label">Peak Read Throughput</div>
      <div class="kpi-value">$([string]::Format('{0:N0}', [double]$peakReadMBps))<span class="kpi-unit">MB/s</span></div>
    </div>
    <div class="kpi write">
      <div class="kpi-label">Peak Write Throughput</div>
      <div class="kpi-value">$([string]::Format('{0:N0}', [double]$peakWriteMBps))<span class="kpi-unit">MB/s</span></div>
    </div>
  </div>

  <h2>Random IOPS (4K / 8K Tests)</h2>
  <div class="card">
    $chartIOPS
  </div>

  <h2>Throughput</h2>
  <div class="card">
    $chartTput
  </div>

  <h2>Latency P99</h2>
  <div class="card">
    $chartLat
  </div>

  <h2>Detailed Results</h2>
  <div class="card">
    <table>
      <thead>
        <tr>
          <th>Test</th>
          <th>Total IOPS</th>
          <th>Read IOPS</th>
          <th>Write IOPS</th>
          <th>Total MB/s</th>
          <th>Read MB/s</th>
          <th>Write MB/s</th>
          <th>P50 (ms)</th>
          <th>P95 (ms)</th>
          <th>P99 (ms)</th>
          <th>P99.9 (ms)</th>
        </tr>
      </thead>
      <tbody>
$resultRows      </tbody>
    </table>
  </div>

  <h2>System Info</h2>
  <div class="card">
    <table class="sys-table">
      <tbody>
$sysRows      </tbody>
    </table>
  </div>

  <footer>
    Generiert am $generated &middot; DiskSpd $($sysInfo.DiskSpdVersion) &middot; $($results.Count) Tests
  </footer>

</div>
</body>
</html>
"@

$reportPath = Join-Path $ResultsDir "_Report.html"
$html | Set-Content -Path $reportPath -Encoding UTF8

Write-Host "Report erstellt: $reportPath" -ForegroundColor Green

if ($OpenAfter) {
    Start-Process $reportPath
}
