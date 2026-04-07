# ITFlow LXC Installer (Proxmox)

Automated Proxmox LXC container creation and [ITFlow](https://github.com/itflow-org/itflow) installation script. Uses the [Proxmox Community Scripts](https://github.com/community-scripts/ProxmoxVE) framework and the [official ITFlow install script](https://github.com/itflow-org/itflow-install-script).

## Prerequisites

Before running this script:

1. **Create a DNS A record** pointing your desired domain (e.g. `itflow.example.com`) to the IP address the LXC container will use
2. **Wait for DNS propagation** — verify with `nslookup itflow.example.com`
3. SSL (Let's Encrypt) requires the domain to resolve correctly before installation

## What It Does

1. **Creates an LXC container** with optimized defaults:
   - 2 CPU cores, 4 GB RAM, 20 GB disk
   - Debian 12 (Bookworm), unprivileged

2. **Installs the full stack**:
   - Apache2 web server
   - MariaDB database
   - PHP with all required extensions (including `php-imap` and `php-mailparse` for email-to-ticket parsing)
   - SSL via Let's Encrypt (or self-signed)

3. **Runs the official ITFlow installer** interactively, prompting for:
   - Domain (FQDN)
   - Timezone
   - Git branch (master/develop)
   - SSL type (letsencrypt/selfsigned/none)

4. **Includes an update function** for later maintenance

## Usage

Run on the Proxmox host:

```bash
bash -c "$(wget -qLO - https://raw.githubusercontent.com/ichabot/general-scripts/main/linux/installer-scripts/itflow/itflow-install.sh)"
```

Or copy the script to the host and run it directly:

```bash
bash itflow-install.sh
```

## After Installation

1. Navigate to `https://your-domain.com`
2. Complete the setup wizard to create your admin account
3. Configure email for tickets and invoices
4. Set up backups (especially the **master encryption key**!)

## Container Defaults

| Parameter | Value |
|-----------|-------|
| OS | Debian 12 (Bookworm) |
| CPU | 2 cores |
| RAM | 4 GB |
| Disk | 20 GB |
| Type | Unprivileged |
| Branch | master |

## ITFlow Features

- **IT Documentation** — Assets, contacts, domains, passwords, files
- **Ticketing System** — Support ticket management with email-to-ticket parsing
- **Billing / Accounting** — Invoices, quotes, expenses, reports
- **Client Portal** — Self-service for customers
- **API** — Integration with RMMs and other tools

## Links

- [ITFlow GitHub](https://github.com/itflow-org/itflow)
- [ITFlow Documentation](https://docs.itflow.org)
- [ITFlow Forum](https://forum.itflow.org)
- [Official Install Script](https://github.com/itflow-org/itflow-install-script)
