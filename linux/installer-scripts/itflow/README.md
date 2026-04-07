# ITFlow LXC Installer (Proxmox)

Automated Proxmox LXC container creation and [ITFlow](https://github.com/itflow-org/itflow) installation script. Uses the [Proxmox Community Scripts](https://github.com/community-scripts/ProxmoxVE) framework and the [official ITFlow install script](https://github.com/itflow-org/itflow-install-script).

## What It Does

1. **Creates an LXC container** with optimized defaults:
   - 2 CPU cores, 4 GB RAM, 20 GB disk
   - Debian 12 (Bookworm), unprivileged

2. **Installs the full stack**:
   - Apache2 web server
   - MariaDB database
   - PHP with all required extensions (including `php-imap` and `php-mailparse` for email-to-ticket parsing)
   - Self-signed SSL certificate

3. **Runs the official ITFlow installer** unattended:
   - Clones from [itflow-org/itflow](https://github.com/itflow-org/itflow) (master branch)
   - Sets up the database with auto-generated secure passwords
   - Configures cron jobs (ticket email parser, mail queue, domain/cert refreshers)
   - Creates `config.php`

4. **Includes an update function** for later maintenance

## Usage

Run on the Proxmox host:

```bash
bash -c "$(wget -qLO - https://raw.githubusercontent.com/DEIN-REPO/itflow-install.sh)"
```

Or copy the script to the host and run it directly:

```bash
bash itflow-install.sh
```

## After Installation

1. Navigate to `https://<IP>.nip.io` (accept the SSL warning)
2. Complete the setup wizard to create your admin account
3. Configure email for tickets and invoices
4. Set up backups (especially the **master encryption key**!)

## Domain & SSL

By default the script uses `<container-IP>.nip.io` for immediate access with a self-signed certificate. For production use:

- Point a real domain to the container IP
- Run `certbot --apache -d yourdomain.com` for Let's Encrypt SSL
- Update `config_base_url` in `/var/www/<domain>/config.php`

## Container Defaults

| Parameter | Value |
|-----------|-------|
| OS | Debian 12 (Bookworm) |
| CPU | 2 cores |
| RAM | 4 GB |
| Disk | 20 GB |
| Type | Unprivileged |
| SSL | Self-signed |
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
