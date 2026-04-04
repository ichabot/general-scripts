# BunkerWeb All-in-One Install Script

Bash installer for [BunkerWeb](https://www.bunkerweb.io/) WAF using the Docker All-in-One (AIO) image.

Based on the official documentation:
- [Docker Compose Installation](https://docs.bunkerweb.io/latest/integrations/#all-in-one-aio-image)

## What It Does

1. Checks prerequisites (Docker, Docker Compose v2)
2. Configures UFW firewall (SSH, HTTP, HTTPS, optional UI port 7000)
3. Creates directory structure under `/opt/bunkerweb`
4. Generates `docker-compose.yml` for the BunkerWeb AIO image
5. Sets up a systemd service for automatic startup on boot
6. Pulls images and starts the container
7. Displays setup wizard URL and next steps

## Requirements

- Linux with root access
- Docker + Docker Compose v2 (plugin)
- Server hardening already completed (the script assumes this)

## Configuration

Edit the variables at the top of `install-bunkerweb.sh`:

```bash
BW_VERSION="1.6.8"          # BunkerWeb version
INSTALL_DIR="/opt/bunkerweb" # Installation directory
SSH_PORT="22"                # Your SSH port (match your hardening)
MGMT_IP=""                   # IP/subnet for direct UI access (port 7000)
ALLOW_PUBLIC_HTTP="yes"      # Allow public HTTP/HTTPS traffic
BW_SERVICES_NETWORK="bw-services"  # Docker network for backend services
```

### Port 7000 (Web UI)

- By default, port 7000 is **not exposed** (recommended for production)
- Set `MGMT_IP` to allow direct UI access from a specific IP/subnet
- After initial setup, access the UI exclusively via HTTPS (port 443)

## Usage

```bash
sudo bash install-bunkerweb.sh
```

## What Gets Created

```
/opt/bunkerweb/
├── docker-compose.yml      # BunkerWeb AIO compose file

/etc/systemd/system/
└── bunkerweb.service       # Systemd service for autostart
```

Plus a Docker volume `bw-storage` for persistent data.

## After Installation

1. Open the Setup Wizard: `https://<server-ip>/setup`
2. Create admin account (username + password)
3. Set your domain for the Web UI
4. Enable Let's Encrypt (automatic SSL)
5. Add your first service / reverse proxy

**Important:** Complete the setup wizard immediately — it is unauthenticated until finished!

## Service Management

```bash
systemctl start bunkerweb    # Start
systemctl stop bunkerweb     # Stop
systemctl restart bunkerweb  # Restart
docker logs -f bunkerweb-aio # View logs
```

## Adding Backend Services

Backend services that BunkerWeb should protect need to join the `bw-services` Docker network. Example:

```yaml
services:
  myapp:
    image: your-app:latest
    networks:
      - bw-services

networks:
  bw-services:
    external: true
```

Then configure the reverse proxy in the BunkerWeb UI.

## License

MIT
