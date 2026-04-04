# Docker CE Install Script for Ubuntu LTS

Automated installer for Docker CE (Community Edition) on Ubuntu 22.04 / 24.04 LTS using the official Docker APT repository.

## What It Does

1. Removes conflicting packages (docker.io, podman-docker, containerd, runc)
2. Installs dependencies and Docker's GPG key
3. Configures the official Docker APT repository (auto-detects Ubuntu codename)
4. Installs Docker CE, CLI, containerd, Buildx, and Compose plugin
5. Writes a hardened `/etc/docker/daemon.json`
6. Enables and starts the Docker service
7. Optionally adds the sudo user to the `docker` group

## Requirements

- Ubuntu 22.04 or 24.04 LTS
- Root access (sudo)
- Internet connection

## Usage

```bash
sudo bash install-docker.sh
```

## daemon.json Configuration

The script configures Docker with sensible production defaults:

```json
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  },
  "live-restore": true,
  "userland-proxy": false
}
```

| Setting | Value | Description |
|---------|-------|-------------|
| `log-driver` | `json-file` | Default log driver with rotation |
| `max-size` | `10m` | Max 10 MB per log file |
| `max-file` | `3` | Keep max 3 rotated log files |
| `live-restore` | `true` | Containers keep running during daemon restart |
| `userland-proxy` | `false` | Use iptables DNAT instead of docker-proxy processes |

### Note on `no-new-privileges`

Not set globally because it breaks setuid-based binaries in containers (su, sudo, older DB images). Enable per container when needed:

```yaml
security_opt:
  - no-new-privileges:true
```

## After Installation

```bash
# Verify installation
docker --version
docker compose version

# Test run
docker run --rm hello-world

# If you were added to the docker group, re-login first:
# logout && login
```

## License

MIT
