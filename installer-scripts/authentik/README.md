# Authentik Install Script

Interactive Bash installer for [Authentik](https://goauthentik.io/) using Docker Compose.

Based on the official documentation:
- [Docker Compose Installation](https://docs.goauthentik.io/install-config/install/docker-compose/)
- [Email Configuration](https://docs.goauthentik.io/install-config/email/)

## What It Does

1. Prompts for configuration (domain, ports, SMTP settings)
2. Checks prerequisites (Docker, Docker Compose v2, openssl)
3. Creates directory structure under `/opt/authentik`
4. Downloads the official `docker-compose.yml`
5. Generates secure passwords (PostgreSQL + Secret Key)
6. Writes `.env` file with all configuration
7. Saves credentials to `credentials.txt` (chmod 600)
8. Optionally starts the containers immediately
9. Optionally sends a test email

## Requirements

- Linux with root access
- Docker + Docker Compose v2 (plugin)
- `openssl` and `wget`

## Usage

```bash
sudo bash install-authentik.sh
```

The script will interactively ask for:

| Setting | Default |
|---------|---------|
| Domain / Hostname | *(required)* |
| HTTP Port | `80` |
| HTTPS Port | `443` |
| SMTP Host | `localhost` |
| SMTP Port | `587` |
| SMTP From | `authentik@<domain>` |
| SMTP Username | *(required)* |
| SMTP Password | *(hidden input)* |
| StartTLS | `yes` |
| Error Reporting | `no` |

## Output

After installation:

```
/opt/authentik/
├── .env                    # Environment variables
├── credentials.txt         # Generated passwords (chmod 600)
├── docker-compose.yml      # Official Authentik compose file
├── media/                  # Media storage
├── certs/                  # Certificates
├── templates/              # Templates
└── custom-templates/       # Custom templates
```

## Initial Setup

After the containers are running, open:
```
https://<your-domain>/if/flow/initial-setup/
```

**Important:** The trailing slash is required!

## License

MIT
