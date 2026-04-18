# FreePBX 17 Installer for Debian 12

Modified version of the [IN1CLICK](https://github.com/20telecom/heqet/blob/beta/IN1CLICK) installer script (v1.3.2) by [20tele.com](https://20tele.com).

## What this script does

Automated pre-flight checks and installation of **FreePBX 17** with **Asterisk 22** on a fresh **Debian 12 (bookworm)** system.

### Pre-flight checks
- OS verification (Debian 12 only)
- Disk space (min. 10 GB)
- Memory check (min. 1 GB RAM recommended)
- Architecture (x86_64 only)
- Hostname validation
- APT sources cleanup (fixes provider mirrors, prevents Debian 13 trixie upgrades)
- Checks for existing FreePBX/Asterisk/MariaDB installations
- Mirror and repository availability checks
- Network connectivity verification

### Installation
- Downloads and runs the [official Sangoma FreePBX installer](https://github.com/FreePBX/sng_freepbx_debian_install)
- Upgrades all FreePBX modules
- Configures Apache with redirect to `/admin/`
- Verifies GUI is accessible
- Cleans up logs and temporary files

## What was changed (vs. original IN1CLICK v1.3.2)

### Mirror Check Fix (main change)

The original script uses `in1.click/mirrors/cli.sh` to check FreePBX mirror health. This external script calls `in1.click/mirrors/api.php` for each mirror — and the APT repository check alone can take **5+ minutes** (observed: 278 seconds). The script requires 3 consecutive successful checks (3x 5+ min = 15+ minutes minimum), and if any fail, enters an interactive retry loop or exits in non-interactive mode.

**Our fix:**
- Attempts the in1.click check with a **60-second timeout** (instead of unlimited)
- On timeout/failure, falls back to **direct mirror checks** with 15-20s timeouts per endpoint:
  - `mirror.freepbx.org`, `mirror1.freepbx.org`, `mirror2.freepbx.org` (HTTPS reachability)
  - `deb.freepbx.org` APT repository (HTTP 200 check on `Packages.gz`)
  - GitHub installer availability
- Only requires **2/3 mirrors + APT repo** (instead of 3/3 three times)
- In non-interactive mode: **warns and continues** instead of aborting
- Default interactive choice changed to **"carry on anyway"** (option 3) instead of "check again" (option 1)
- Total mirror check time: **under 30 seconds** (vs. 15+ minutes original)

## What the in1.click mirrors check

The `in1.click/mirrors` status page monitors the official **Sangoma FreePBX infrastructure**:

| Endpoint | Purpose |
|----------|---------|
| `mirror.freepbx.org` | Primary FreePBX module mirror — serves module XML feeds and tarballs |
| `mirror1.freepbx.org` | Secondary module mirror (failover/load balancing) |
| `mirror2.freepbx.org` | Tertiary module mirror |
| `deb.freepbx.org` | Sangoma's APT package repository for FreePBX 17 Debian packages |

The mirrors serve:
- **FreePBX module metadata** (XML feeds for v17.0 and v16.0) — standard and extended module lists
- **FreePBX module packages** (tarballs downloaded by `fwconsole ma install`)
- **Debian packages** (`deb.freepbx.org`) — the `freepbx17`, `asterisk22`, `sangoma-pbx17`, `ioncube-loader-82`, and related `.deb` packages installed via APT

The in1.click checker runs DNS resolution, TCP handshake, SSL certificate, XML validity, and APT `Packages.gz` validation tests against each endpoint via a server-side API in London (UK).

## Usage

```bash
# Download and run directly
curl -o install-freepbx17.sh https://raw.githubusercontent.com/ichabot/general-scripts/main/linux/installer-scripts/freepbx17/install-freepbx17.sh
chmod +x install-freepbx17.sh
sudo bash install-freepbx17.sh

# Or pipe (non-interactive mode)
curl https://raw.githubusercontent.com/ichabot/general-scripts/main/linux/installer-scripts/freepbx17/install-freepbx17.sh | sudo bash
```

## Requirements

- **OS:** Debian 12 (bookworm), fresh minimal install, no desktop environment
- **Architecture:** x86_64 (64-bit)
- **Disk:** Minimum 10 GB free space
- **RAM:** Minimum 1 GB (2+ GB recommended)
- **Network:** Outbound internet access required
- **Root:** Must run as root

## Credits

- Original script: [IN1CLICK v1.3.2](https://github.com/20telecom/heqet/blob/beta/IN1CLICK) by [20tele.com](https://20tele.com)
- Official FreePBX installer: [FreePBX/sng_freepbx_debian_install](https://github.com/FreePBX/sng_freepbx_debian_install)
- License: GNU General Public License v3.0
