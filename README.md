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
| [ubuntu-hardening](linux/installer-scripts/ubuntu-hardening/) | Ubuntu Server Hardening v1.3 (LXC/VM/Cloud compatible, dry-run mode) |

```bash
sudo bash linux/installer-scripts/authentik/install-authentik.sh
sudo bash linux/installer-scripts/bunkerweb/install-bunkerweb.sh
sudo bash linux/installer-scripts/docker-ce/install-docker.sh
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
│       └── ubuntu-hardening/
└── windows/
    ├── mailstore-docs/
    │   ├── MailStore-Documentation.ps1
    │   └── README.md
    └── outlook-profile-reset/
        ├── README.md
        ├── Reset-OutlookProfile.ps1
        ├── Reset-OutlookProfile.bat
        ├── Deploy-OutlookReset.ps1
        ├── Outlook-Reparatur.bat
        └── Outlook-AutoConfig.prf
```

## License

MIT License — see [LICENSE](LICENSE) for details.
