# Installer Scripts

Collection of interactive installation scripts for self-hosted services.

## Available Installers

| Script | Description |
|--------|-------------|
| [authentik](authentik/) | Authentik identity provider (Docker Compose) |
| [bunkerweb](bunkerweb/) | BunkerWeb WAF All-in-One (Docker Compose + UFW + systemd) |
| [docker-ce](docker-ce/) | Docker CE for Ubuntu LTS (official repo + hardened daemon.json) |

## General Notes

- All scripts are interactive and prompt for configuration
- Designed for Linux servers with root access
- Generated credentials are saved securely with restricted permissions
- Scripts check prerequisites before starting installation
