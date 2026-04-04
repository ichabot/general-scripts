#!/bin/bash
# ============================================================
#  Docker CE – Install Script for Ubuntu LTS
#  Getestet auf: Ubuntu 22.04 / 24.04 LTS
# ============================================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()    { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

# Root-Check
if [ "$EUID" -ne 0 ]; then
  error "Bitte als root oder mit sudo ausführen."
fi

# OS-Check
if ! grep -qi ubuntu /etc/os-release; then
  error "Dieses Script ist nur für Ubuntu ausgelegt."
fi

# --------------------------------------------------------
# 1. Konflikt-Pakete entfernen
# --------------------------------------------------------
info "Entferne konfliktbehaftete Pakete..."

CONFLICT_PKGS=$(dpkg --get-selections \
  docker.io docker-compose docker-compose-v2 \
  docker-doc podman-docker containerd runc 2>/dev/null \
  | awk '{print $1}')

if [ -n "$CONFLICT_PKGS" ]; then
  apt remove -y $CONFLICT_PKGS
  info "Pakete entfernt: $CONFLICT_PKGS"
else
  info "Keine konfliktbehafteten Pakete gefunden."
fi

# --------------------------------------------------------
# 2. Abhängigkeiten & GPG-Key
# --------------------------------------------------------
info "Installiere Abhängigkeiten und GPG-Key..."

apt update -y
apt install -y ca-certificates curl

install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
  -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc

# --------------------------------------------------------
# 3. APT Repository einrichten
# --------------------------------------------------------
info "Richte Docker APT-Repository ein..."

. /etc/os-release
CODENAME="${UBUNTU_CODENAME:-$VERSION_CODENAME}"

if [ -z "$CODENAME" ]; then
  error "Ubuntu-Codename konnte nicht ermittelt werden."
fi

tee /etc/apt/sources.list.d/docker.sources > /dev/null <<EOF
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: ${CODENAME}
Components: stable
Signed-By: /etc/apt/keyrings/docker.asc
EOF

info "Repository für Ubuntu '${CODENAME}' eingerichtet."
apt update -y

# --------------------------------------------------------
# 4. Docker CE installieren
# --------------------------------------------------------
info "Installiere Docker CE und Plugins..."

apt install -y \
  docker-ce \
  docker-ce-cli \
  containerd.io \
  docker-buildx-plugin \
  docker-compose-plugin

# --------------------------------------------------------
# 5. daemon.json konfigurieren
# --------------------------------------------------------
info "Schreibe /etc/docker/daemon.json..."

mkdir -p /etc/docker

cat > /etc/docker/daemon.json <<'EOF'
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  },
  "live-restore": true,
  "userland-proxy": false
}
EOF

# Hinweis zu no-new-privileges:
# Nicht global gesetzt, da es setuid-basierte Binaries in Containern bricht
# (su, sudo, ältere DB-Images etc.).
# Pro Container aktivierbar via:
#   security_opt:
#     - no-new-privileges:true

# --------------------------------------------------------
# 6. Docker-Dienst aktivieren & starten
# --------------------------------------------------------
info "Aktiviere und starte Docker-Dienst..."
systemctl enable docker
systemctl restart docker

# --------------------------------------------------------
# 7. Optionale Gruppe für den aktuellen Sudo-User
# --------------------------------------------------------
SUDO_USER_NAME="${SUDO_USER:-}"
if [ -n "$SUDO_USER_NAME" ]; then
  info "Füge '${SUDO_USER_NAME}' zur Gruppe 'docker' hinzu..."
  usermod -aG docker "$SUDO_USER_NAME"
  warn "Bitte neu einloggen, damit die Gruppenänderung wirksam wird."
fi

# --------------------------------------------------------
# 8. Versionen und Konfiguration ausgeben
# --------------------------------------------------------
info "Installation abgeschlossen!"
echo ""
echo "  Docker Version:         $(docker --version)"
echo "  Docker Compose Version: $(docker compose version)"
echo ""
echo "  daemon.json Konfiguration:"
echo "  |- log-driver:      json-file (max 10m, 3 Dateien)"
echo "  |- live-restore:    true  -> Container laufen bei Daemon-Neustart weiter"
echo "  '- userland-proxy:  false -> iptables DNAT statt docker-proxy Prozesse"
echo ""
warn "no-new-privileges ist NICHT global gesetzt."
warn "Bei Bedarf pro Container setzen:  security_opt: [no-new-privileges:true]"
echo ""
info "Test: docker run --rm hello-world"
