# Ubuntu Server Hardening Script

Comprehensive server hardening script for Ubuntu 22.04 / 24.04 LTS. Supports LXC containers, Proxmox VMs, Cloud VMs (Hetzner, AWS, etc.), and bare metal.

**Version:** 1.2 — LXC/VM/Cloud compatible

## What It Does

1. **Environment detection** — auto-detects LXC, Cloud VM, or Proxmox VM/Bare Metal
2. **System update** — full apt upgrade
3. **Timezone & Locale** — Europe/Berlin, de_DE.UTF-8
4. **Chrony NTP** — replaces systemd-timesyncd with chrony (EU NTP pools)
5. **Swap** — configurable swap file (skipped in LXC)
6. **SSH Hardening** — disables root login, limits auth tries, banner, idle timeout
7. **Fail2Ban** — SSH brute-force protection with auto-ban
8. **UFW Firewall** — deny incoming, allow SSH + configurable extra ports
9. **Unattended Upgrades** — automatic security updates
10. **Kernel/Sysctl Hardening** — SYN flood protection, IP spoofing, IPv6 disable (skipped in LXC)
11. **Service Cleanup** — disables bluetooth, cups, avahi-daemon
12. **Base Tools** — curl, wget, bpytop, tmux
13. **Auditd** — Wazuh backend (skipped in LXC)
14. **QEMU Guest Agent** — Proxmox integration (skipped in LXC and Cloud VMs)
15. **Bash History** — timestamps, 10000 entries, tmux auto-attach
16. **MOTD** — system info on login

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
SSH_ALLOW_USERS=""     # ONLY set if user exists! Empty = all users
SWAPPINESS=10
SWAP_SIZE="2G"         # "0" = no swap

EXTRA_PORTS=(
    "80/tcp:HTTP"
    "443/tcp:HTTPS"
)
```

### SSH_ALLOW_USERS Safety

The script validates that all users in `SSH_ALLOW_USERS` actually exist before applying the restriction. If a user doesn't exist, the setting is skipped with a warning to prevent lockout.

## Usage

```bash
sudo bash ubuntu_hardening.sh
```

## After Installation

1. Create a regular user: `adduser sysadmin`
2. Add SSH key for the user
3. Set `PermitRootLogin no` in `/etc/ssh/sshd_config.d/99-hardening.conf`
4. Uncomment `PasswordAuthentication no` once keys are set up
5. Whitelist your IPs in `/etc/fail2ban/jail.local`
6. Reboot

## Tested On

- ✅ Ubuntu 24.04 LTS — Hetzner Cloud VM (cx23)
- ✅ Ubuntu 22.04 / 24.04 LTS — Proxmox VM
- ✅ Ubuntu 22.04 / 24.04 LTS — Proxmox LXC

## License

MIT
