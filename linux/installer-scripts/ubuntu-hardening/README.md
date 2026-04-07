# Ubuntu Server Hardening Script

Comprehensive server hardening script for Ubuntu 22.04 / 24.04 LTS. Supports LXC containers, Proxmox VMs, Cloud VMs (Hetzner, AWS, etc.), and bare metal.

**Version:** 1.3 — LXC/VM/Cloud compatible

## What It Does

1. **Environment detection** — auto-detects LXC, Cloud VM, or Proxmox VM/Bare Metal
2. **System update** — full apt upgrade
3. **Timezone & Locale** — Europe/Berlin, de_DE.UTF-8
4. **Chrony NTP** — replaces systemd-timesyncd with chrony (EU NTP pools)
5. **Swap** — configurable swap file with btrfs/ZFS fallback (skipped in LXC)
6. **SSH Hardening** — disables root login, limits auth tries, banner, idle timeout
7. **Fail2Ban** — SSH brute-force protection with auto-ban
8. **UFW Firewall** — deny incoming, allow SSH + configurable extra ports
9. **Unattended Upgrades** — automatic security updates with optional auto-reboot
10. **Kernel/Sysctl Hardening** — SYN flood protection, IP spoofing, configurable IPv6 (skipped in LXC)
11. **Service Cleanup** — disables bluetooth, cups, avahi-daemon
12. **Base Tools** — curl, wget, bpytop, tmux
13. **Auditd** — Wazuh backend (skipped in LXC)
14. **QEMU Guest Agent** — Proxmox integration (skipped in LXC and Cloud VMs)
15. **Bash History** — timestamps, 10000 entries, tmux auto-attach
16. **MOTD** — system info on login

## Features

- **Dry-run mode** (`--check`) — shows what would be done without making changes
- **Logging** — all output saved to `/var/log/hardening_*.log`
- **Idempotent** — safe to re-run (UFW rules, fstab, bash.bashrc checked for duplicates)
- **Cloud-aware** — detects Hetzner/cloud-init, prevents SSH lockout on root-only VMs
- **Configurable IPv6** — disable completely or harden while keeping active
- **Configurable auto-reboot** — optional automatic reboot after kernel security updates

## Environment Detection

| Environment | sysctl | auditd | QEMU GA | Swap | SSH Root |
|-------------|--------|--------|---------|------|----------|
| LXC         | skip   | skip   | skip    | skip | normal   |
| Cloud VM    | ✓      | ✓      | skip    | ✓    | prohibit-password* |
| Proxmox VM  | ✓      | ✓      | ✓       | ✓    | no       |

*On Cloud VMs where only root exists, root login stays enabled (key-only) to prevent lockout.

## Requirements

- Ubuntu 22.04 or 24.04 LTS
- Root access (sudo)

## Configuration

Edit the variables at the top of the script:

```bash
TIMEZONE="Europe/Berlin"
LOCALE="de_DE.UTF-8"
SSH_PORT=22
SSH_ALLOW_USERS=""        # ONLY set if user exists! Empty = all users
SWAPPINESS=10
SWAP_SIZE="2G"            # "0" = no swap

DISABLE_IPV6=true         # true = disable IPv6, false = harden only
AUTO_REBOOT=false         # true = auto-reboot after kernel updates
AUTO_REBOOT_TIME="03:30"  # reboot time (only if AUTO_REBOOT=true)

EXTRA_PORTS=(
    "80/tcp:HTTP"
    "443/tcp:HTTPS"
)
```

## Usage

**One-liner** — download and run directly:

```bash
# Dry-run (no changes)
bash -c "$(wget -qLO - https://raw.githubusercontent.com/ichabot/general-scripts/main/linux/installer-scripts/ubuntu-hardening/ubuntu_hardening.sh)" -- --check

# Execute hardening
bash -c "$(wget -qLO - https://raw.githubusercontent.com/ichabot/general-scripts/main/linux/installer-scripts/ubuntu-hardening/ubuntu_hardening.sh)"
```

Or with curl:

```bash
curl -fsSL https://raw.githubusercontent.com/ichabot/general-scripts/main/linux/installer-scripts/ubuntu-hardening/ubuntu_hardening.sh | sudo bash
```

Or clone and run locally:

```bash
git clone https://github.com/ichabot/general-scripts.git
sudo bash general-scripts/linux/installer-scripts/ubuntu-hardening/ubuntu_hardening.sh --check  # Dry-run
sudo bash general-scripts/linux/installer-scripts/ubuntu-hardening/ubuntu_hardening.sh          # Execute
```

## After Installation

1. Create a regular user: `adduser sysadmin`
2. Add SSH key for the user
3. Set `PermitRootLogin no` in `/etc/ssh/sshd_config.d/99-hardening.conf`
4. Uncomment `PasswordAuthentication no` once keys are set up
5. Whitelist your IPs in `/etc/fail2ban/jail.local`
6. Review the log file: `/var/log/hardening_*.log`
7. Reboot

## Tested On

- ✅ Ubuntu 24.04 LTS — Hetzner Cloud VM (cx23)
- ✅ Ubuntu 22.04 / 24.04 LTS — Proxmox VM
- ✅ Ubuntu 22.04 / 24.04 LTS — Proxmox LXC

## Changelog

### v1.3
- Added `--check` / `--dry-run` mode
- Added logging to `/var/log/hardening_*.log`
- Added `DISABLE_IPV6` config option (disable vs. harden)
- Added `AUTO_REBOOT` / `AUTO_REBOOT_TIME` config options
- Swap: `fallocate` fallback to `dd` for btrfs/ZFS compatibility
- UFW: idempotent rules (no duplicates on re-run)
- fstab: check before appending swap entry
- SSH: `LoginGraceTime` increased from 30 to 60 seconds

### v1.2
- Cloud VM detection (Hetzner, cloud-init)
- SSH lockout prevention (validates AllowUsers, keeps root on cloud VMs)
- sshd-ddos filter availability check
- Service disable section shows skip messages
- Bash history block idempotent

### v1.1
- LXC/VM environment detection
- Proxmox-specific sections (QEMU GA, sysctl skip in LXC)

## License

MIT
