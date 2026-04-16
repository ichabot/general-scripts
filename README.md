# General Scripts

A collection of general-purpose utility scripts — converters, automation tools, installers, and helpers.

Organized by platform:

- **[linux/](linux/)** — Bash scripts, Python tools, server installers
- **[windows/](windows/)** — PowerShell scripts, Batch files, Windows tooling

---

## Linux

### [docmost-to-obsidian](linux/docmost-to-obsidian/)

**Docmost Space Export → Obsidian Vault Converter**

Two-phase tool that converts Docmost space exports into clean Obsidian vaults. Analyzes first, converts after review. Rewrites attachment links, detects special content (Mermaid, Draw.io, KaTeX), handles duplicate filenames.

```bash
cd linux/docmost-to-obsidian
python docmost_to_obsidian.py              # Analyze
python docmost_to_obsidian.py --convert    # Convert
```

---

### [opnsense-scripts](linux/opnsense-scripts/)

**OPNsense Firewall Management Scripts**

| Script | Description |
|--------|-------------|
| [m365-endpoints](linux/opnsense-scripts/m365-endpoints/) | Microsoft 365 endpoints → OPNsense alias lists (IPv4, IPv6, URLs) |

```bash
cd linux/opnsense-scripts/m365-endpoints
pip install -r requirements.txt
python m365_to_opnsense.py
```

---

### [installer-scripts](linux/installer-scripts/)

**Interactive Installation Scripts for Self-Hosted Services**

| Script | Description |
|--------|-------------|
| [authentik](linux/installer-scripts/authentik/) | Authentik identity provider (Docker Compose) |
| [bunkerweb](linux/installer-scripts/bunkerweb/) | BunkerWeb WAF All-in-One (Docker Compose + UFW + systemd) |
| [docker-ce](linux/installer-scripts/docker-ce/) | Docker CE for Ubuntu LTS (official repo + hardened daemon.json) |
| [itflow](linux/installer-scripts/itflow/) | ITFlow PSA in Proxmox LXC (Apache + MariaDB + PHP + SSL, unattended) |
| [ubuntu-hardening](linux/installer-scripts/ubuntu-hardening/) | Ubuntu Server Hardening v1.3 (LXC/VM/Cloud compatible, dry-run mode) |

```bash
sudo bash linux/installer-scripts/authentik/install-authentik.sh
sudo bash linux/installer-scripts/bunkerweb/install-bunkerweb.sh
sudo bash linux/installer-scripts/docker-ce/install-docker.sh
bash linux/installer-scripts/itflow/itflow-install.sh                           # Proxmox LXC
sudo bash linux/installer-scripts/ubuntu-hardening/ubuntu_hardening.sh          # Execute
sudo bash linux/installer-scripts/ubuntu-hardening/ubuntu_hardening.sh --check  # Dry-run
```

---

## Windows

### [mailstore-docs](windows/mailstore-docs/)

**MailStore Server Documentation Script (v2.1)**

PowerShell script that generates comprehensive HTML documentation of a MailStore Server installation — with optional API integration. Documents system info, license, archive stores, users, profiles, and jobs.

```powershell
cd windows\mailstore-docs
.\MailStore-Documentation.ps1
```

---

### [outlook-cache-cleanup](windows/outlook-cache-cleanup/)

**Outlook AutoComplete Cache Cleanup (NinjaRMM)**

PowerShell script to clean Outlook AutoComplete cache (NK2 + Stream_AutoComplete). Supports all Outlook versions 2010–365. Features WhatIf mode, detailed logging, and RMM-compatible exit codes.

```powershell
.\Outlook-Cache-Cleanup.ps1                              # Standard cleanup
.\Outlook-Cache-Cleanup.ps1 -ClearAllCaches -RestartOutlook  # Full cleanup + restart
.\Outlook-Cache-Cleanup.ps1 -WhatIf                      # Test mode
```

---

### [rom-duplicate-cleanup](windows/rom-duplicate-cleanup/)

**ROM Duplicate Cleanup Script**

PowerShell script that automatically deduplicates ROM collections. Scores ROMs by region priority and quality tags (good dumps, hacks, bad dumps, etc.) and keeps only the best version of each game.

```powershell
.\rom-cleanup-simple.ps1 -RomPath "C:\Your\ROM\Collection"
```

---

### [diskspeed-test](windows/diskspeed-test/)

**Storage Performance Benchmark Toolkit**

DiskSpd-based storage benchmark for Windows Server VMs on SAN/SSD infrastructure. Runs a full I/O test matrix (4K random, 8K OLTP, 64K sequential, 1M large-block) with queue-depth sweeps. Generates a standalone dark-themed HTML report with inline SVG charts, KPI cards, and latency percentiles.

```powershell
# Run benchmark
.\Invoke-StoragePerfTest.ps1 -TargetPath E:\bench\test.dat -FileSizeGB 64

# Generate HTML report
.\New-StoragePerfReport.ps1 -ResultsDir C:\StoragePerf\Results_20260416_094240 -OpenAfter
```

---

### [outlook-profile-reset](windows/outlook-profile-reset/)

**Outlook Profile Reset Toolkit**

Scripts for automated deletion and re-creation of Outlook profiles via Autodiscover. Includes local execution, batch versions for end users, remote deployment, and a PRF auto-config file.

| File | Description |
|------|-------------|
| `Reset-OutlookProfile.ps1` | PowerShell script for local execution (backup, cleanup, restart) |
| `Reset-OutlookProfile.bat` | Simple batch version for single users |
| `Outlook-Reparatur.bat` | End-user friendly starter script (network share deployment) |
| `Deploy-OutlookReset.ps1` | Remote deployment on multiple clients (GPO/SCCM compatible) |
| `Outlook-AutoConfig.prf` | PRF file for automatic profile configuration via Autodiscover |

```powershell
# Local reset (PowerShell)
.\Reset-OutlookProfile.ps1

# With backup, no restart
.\Reset-OutlookProfile.ps1 -NoRestart -BackupProfile

# Remote deployment
.\Deploy-OutlookReset.ps1 -ComputerName "PC001", "PC002"
```

---

## Structure

```
general-scripts/
├── README.md
├── LICENSE
├── linux/
│   ├── docmost-to-obsidian/
│   │   ├── docmost_to_obsidian.py
│   │   └── README.md
│   ├── opnsense-scripts/
│   │   ├── README.md
│   │   └── m365-endpoints/
│   │       ├── m365_to_opnsense.py
│   │       ├── requirements.txt
│   │       └── README.md
│   └── installer-scripts/
    │       ├── README.md
    │       ├── authentik/
    │       ├── bunkerweb/
    │       ├── docker-ce/
    │       ├── erp-next/
    │       ├── itflow/
    │       └── ubuntu-hardening/
└── windows/
    ├── diskspeed-test/
    │   ├── Invoke-StoragePerfTest.ps1
    │   ├── New-StoragePerfReport.ps1
    │   ├── diskspd-2.2.zip
    │   └── README.md
    ├── mailstore-docs/
    │   ├── MailStore-Documentation.ps1
    │   └── README.md
    ├── outlook-cache-cleanup/
    │   ├── Outlook-Cache-Cleanup.ps1
    │   └── README.md
    ├── rom-duplicate-cleanup/
    │   ├── rom-cleanup-simple.ps1
    │   └── README.md
    └── outlook-profile-reset/
        ├── README.md
        ├── Reset-OutlookProfile.ps1
        ├── Reset-OutlookProfile.bat
        ├── Deploy-OutlookReset.ps1
        ├── Outlook-Reparatur.bat
        └── Outlook-AutoConfig.prf
```

## ⚠️ Disclaimer

This project was developed with AI assistance ("vibe coding") and uses third-party open-source dependencies that have **not been independently audited**. The software is provided "as is" under the MIT License, without warranty of any kind.

**Please note:**
- These scripts modify system configurations, install packages, and change security settings — **always review before running**
- Use the `--check` / `--dry-run` flags where available to preview changes
- The installer scripts (hardening, Docker, Authentik, etc.) are designed for **fresh server setups** — running on existing production systems may cause conflicts
- PowerShell scripts modify Windows Registry and Outlook profiles — **back up before use**
- External dependencies and APIs (Microsoft 365 Endpoints, Docker repos, etc.) are maintained by their respective projects — changes on their end may break functionality
- This is a personal/MSP toolbox, not certified enterprise software

> **Short version:** Read the scripts before running them, test on non-production systems first, keep backups. Don't blindly run hardening scripts on live servers.

---

## License

MIT License — see [LICENSE](LICENSE) for details.
