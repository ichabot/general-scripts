# General Scripts

A collection of general-purpose utility scripts — converters, automation tools, and helpers.

## Scripts

### [docmost-to-obsidian](docmost-to-obsidian/)

**Docmost Space Export → Obsidian Vault Converter**

Two-phase tool that converts Docmost space exports into clean Obsidian vaults:
- **Phase 1** (Analyze): Scans spaces, generates a detailed report of pages, links, attachments, and special content
- **Phase 2** (Convert): Copies files, rewrites attachment links, deduplicates filenames, preserves metadata

**Features:**
- Rewrites `files/UUID/name` attachment paths to `_attachments/name`
- Detects Mermaid, Draw.io, Excalidraw, and KaTeX content
- Identifies broken links and empty/title-only pages
- Handles duplicate attachment filenames with UUID prefixes
- Windows console encoding fix included

**Quick Start:**
```bash
cd docmost-to-obsidian
python docmost_to_obsidian.py              # Phase 1: Analyze
python docmost_to_obsidian.py --convert    # Phase 2: Convert
```

---

### [mailstore-docs](mailstore-docs/)

**MailStore Server Documentation Script (v2.1)**

PowerShell script that generates comprehensive HTML documentation of a MailStore Server installation — with optional API integration.

**Features:**
- Generates structured HTML documentation
- MailStore PowerShell API integration (optional)
- Documents system info, license, archive stores, users, profiles, jobs
- Performance data collection (optional)
- Visual warnings for expired licenses, low disk space, etc.

**Quick Start:**
```powershell
cd mailstore-docs
.\MailStore-Documentation.ps1
```

See the [mailstore-docs README](mailstore-docs/README.md) for parameters and detailed usage.

---

### [installer-scripts](installer-scripts/)

**Interactive Installation Scripts for Self-Hosted Services**

Collection of Bash installers that guide you through setting up self-hosted services.

Currently available:
- **[Authentik](installer-scripts/authentik/)** — Identity provider / SSO via Docker Compose. Interactive setup with SMTP config, secure password generation, and credential storage.
- **[BunkerWeb](installer-scripts/bunkerweb/)** — BunkerWeb WAF All-in-One via Docker Compose. Includes UFW firewall config, systemd service, and setup wizard instructions.
- **[Docker CE](installer-scripts/docker-ce/)** — Docker CE for Ubuntu LTS. Official repo, hardened daemon.json, Compose v2 plugin.

```bash
sudo bash installer-scripts/authentik/install-authentik.sh
sudo bash installer-scripts/bunkerweb/install-bunkerweb.sh
sudo bash installer-scripts/docker-ce/install-docker.sh
```

---

## Structure

Each script lives in its own directory with its own documentation:

```
general-scripts/
├── README.md
├── LICENSE
├── docmost-to-obsidian/            # Docmost → Obsidian converter
│   ├── docmost_to_obsidian.py
│   └── README.md
├── mailstore-docs/                 # MailStore Server documentation
│   ├── MailStore-Documentation.ps1
│   └── README.md
├── installer-scripts/              # Self-hosted service installers
│   ├── README.md
│   ├── authentik/
│   │   ├── install-authentik.sh
│   │   └── README.md
│   ├── bunkerweb/
│   │   ├── install-bunkerweb.sh
│   │   └── README.md
│   └── docker-ce/
│       ├── install-docker.sh
│       └── README.md
└── ...                             # More scripts coming soon
```

## License

MIT License — see [LICENSE](LICENSE) for details.
