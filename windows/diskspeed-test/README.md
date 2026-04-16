# DiskSpeed Test — Storage Performance Benchmark Toolkit

DiskSpd-based storage benchmark for Windows Server VMs (VMware, Hyper-V, KVM). Two PowerShell scripts: one runs the full test matrix, the other generates a standalone HTML report with inline SVG charts.

Built for SAN/SSD benchmarking on virtualized infrastructure (Dell ME5024, Pure, NetApp, etc.).

## Scripts

| File | Description |
|------|-------------|
| `Invoke-StoragePerfTest.ps1` | DiskSpd wrapper — runs full I/O test matrix, collects IOPS/throughput/latency |
| `New-StoragePerfReport.ps1` | HTML report generator — reads results and builds a dark-themed standalone report |
| `diskspd-2.2.zip` / `.tar.gz` / `DiskSpd.ZIP` | Bundled DiskSpd binaries and original Source Code in case Microsoft kills the Project (Microsoft, v2.2) |

## Test Matrix

| Test | Block Size | Pattern | Queue Depth | Measures |
|------|-----------|---------|-------------|----------|
| 4K Random Read | 4K | Random | QD 1 / 8 / 32 | IOPS + Latency |
| 4K Random Write | 4K | Random | QD 1 / 32 | IOPS + Latency |
| 8K Mixed 70R/30W | 8K | Random | QD 16 | OLTP/SQL profile |
| 64K Sequential R/W | 64K | Sequential | QD 8 | VM-typical I/O |
| 1M Sequential R/W | 1M | Sequential | QD 4 | Backup/large-block |

All tests use mandatory flags per Microsoft documentation:
- `-Z1M` — 1 MB random write buffer (defeats dedup/compression)
- `-Sh` — disables software + hardware write cache
- `-L` — captures latency percentiles (P50–P99.99)

## Usage

### Run Benchmark

```powershell
# Basic — 64 GB test file, 60s per test
.\Invoke-StoragePerfTest.ps1 -TargetPath E:\bench\test.dat

# Custom parameters
.\Invoke-StoragePerfTest.ps1 -TargetPath E:\bench\test.dat -FileSizeGB 128 -Duration 120 -Warmup 30

# Explicit DiskSpd path
.\Invoke-StoragePerfTest.ps1 -TargetPath E:\bench\test.dat -DiskSpdPath C:\Tools\diskspd.exe
```

### Generate HTML Report

```powershell
# From results directory
.\New-StoragePerfReport.ps1 -ResultsDir C:\StoragePerf\Results_20260416_094240

# Open in browser after generation
.\New-StoragePerfReport.ps1 -ResultsDir C:\StoragePerf\Results_20260416_094240 -OpenAfter

# Custom title
.\New-StoragePerfReport.ps1 -ResultsDir C:\StoragePerf\Results_20260416_094240 -Title "Production SAN Benchmark Q2/2026"
```

## Parameters

### Invoke-StoragePerfTest.ps1

| Parameter | Default | Description |
|-----------|---------|-------------|
| `-TargetPath` | *(required)* | Path to test file (e.g. `E:\bench\test.dat`) |
| `-FileSizeGB` | `64` | Test file size — should exceed SAN cache AND VM RAM |
| `-Duration` | `60` | Test duration per run (seconds) |
| `-Warmup` | `15` | Warmup per run, not measured (seconds) |
| `-Threads` | CPU count | Worker threads per test |
| `-OutputDir` | `C:\StoragePerf\Results_<timestamp>` | Output directory for results |
| `-DiskSpdPath` | Auto-discovery | Explicit path to `diskspd.exe` |

### New-StoragePerfReport.ps1

| Parameter | Default | Description |
|-----------|---------|-------------|
| `-ResultsDir` | *(required)* | Path to results folder |
| `-Title` | Hostname + timestamp | Report title |
| `-OpenAfter` | `$false` | Open report in default browser |

## Features

- **Auto-discovery** — finds `diskspd.exe` next to script, in `amd64\` subfolder, `C:\Tools\diskspd\`, or PATH
- **System info collection** — hostname, hypervisor, CPU, RAM, SCSI controller, VMware Tools status
- **Pre-flight checks** — warns about insufficient vCPUs, test file too small vs. RAM/SAN cache, missing PVSCSI controller
- **Culture-safe parsing** — handles German/European decimal separators in CSV output
- **Standalone HTML report** — dark-themed, inline CSS + SVG charts, no external dependencies, print-friendly
- **KPI cards** — peak read/write IOPS and throughput at a glance
- **Three chart types** — Random IOPS, Throughput (MB/s), Latency P99 (ms)
- **Detailed results table** — all metrics including P50, P95, P99, P99.9 latency

## Output

Results saved to `C:\StoragePerf\Results_<timestamp>\`:

```
Results_20260416_094240/
├── _SystemInfo.json          # Host/VM/storage metadata
├── _Summary.csv              # All results as CSV
├── _Warnings.txt             # Pre-flight warnings (if any)
├── _Report.html              # Standalone HTML report
├── 4K_RandRead_QD1.xml       # Raw DiskSpd XML per test
├── 4K_RandRead_QD1.txt       # Human-readable DiskSpd output
├── ...
└── 1M_SeqWrite_QD4.xml
```

## Requirements

- Windows Server 2016+ or Windows 10/11
- PowerShell 5.1+
- DiskSpd 2.x (bundled or [download from Microsoft](https://github.com/microsoft/diskspd/releases))
- Admin rights recommended (for `-Sh` cache bypass)
- Test file size should be ≥ 2× VM RAM and ≥ 32 GB to avoid SAN cache artifacts

## Tips

- **VMware**: use PVSCSI controller for the test VMDK — LSI Logic SAS is significantly slower at 4K random
- **Test file sizing**: for a VM with 32 GB RAM on a Dell ME5024 (8 GB cache per controller), use at least 64 GB
- **Multiple runs**: compare results across different times of day to catch shared SAN contention
- **Baseline**: run once after provisioning, save the report, compare after changes
