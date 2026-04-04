#!/bin/bash
# =============================================================================
#  BunkerWeb All-in-One – Install Script
#  Version: BunkerWeb 1.6.8 | Deployment: Docker AIO
#  Voraussetzungen: Docker bereits installiert, Server-Hardening erfolgt
# =============================================================================

set -euo pipefail

# ─────────────────────────────────────────────────────────────────────────────
# FARBEN & HILFSFUNKTIONEN
# ─────────────────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

info()    { echo -e "${CYAN}[INFO]${NC}  $*"; }
success() { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }
header()  { echo -e "\n${BOLD}${CYAN}══════════════════════════════════════════${NC}"; \
            echo -e "${BOLD}${CYAN}  $*${NC}"; \
            echo -e "${BOLD}${CYAN}══════════════════════════════════════════${NC}\n"; }

# ─────────────────────────────────────────────────────────────────────────────
# KONFIGURATION – hier anpassen!
# ─────────────────────────────────────────────────────────────────────────────

BW_VERSION="1.6.8"
INSTALL_DIR="/opt/bunkerweb"

# SSH-Port (an dein Hardening anpassen!)
SSH_PORT="22"

# Management-IP: Nur diese IP/Dieses Subnetz darf auf Port 7000 (direktes UI)
# zugreifen. Leer lassen = Port 7000 bleibt geschlossen (empfohlen für Produktion)
MGMT_IP=""               # z.B. "10.0.0.5" oder "192.168.1.0/24"

# Erlaube eingehenden HTTP/HTTPS auch ohne IP-Einschränkung (öffentlich)
ALLOW_PUBLIC_HTTP="yes"  # "yes" oder "no"

# Docker-Netzwerk für deine Services (Backends die BW schützen soll)
BW_SERVICES_NETWORK="bw-services"

# ─────────────────────────────────────────────────────────────────────────────
# PRÜFUNGEN
# ─────────────────────────────────────────────────────────────────────────────
header "BunkerWeb AIO – Voraussetzungen prüfen"

[[ $EUID -ne 0 ]] && error "Dieses Script muss als root ausgeführt werden (sudo)."

command -v docker &>/dev/null || error "Docker ist nicht installiert. Abbruch."
success "Docker gefunden: $(docker --version)"

command -v docker compose &>/dev/null \
  || docker compose version &>/dev/null \
  || error "Docker Compose (v2) nicht gefunden. Bitte installieren."
success "Docker Compose gefunden."

# ─────────────────────────────────────────────────────────────────────────────
# UFW KONFIGURATION
# ─────────────────────────────────────────────────────────────────────────────
header "UFW Firewall konfigurieren"

if ! command -v ufw &>/dev/null; then
  warn "UFW nicht gefunden – Installation..."
  apt-get install -y ufw
fi

info "UFW-Regeln setzen..."

# Standard-Policies
ufw default deny incoming  >/dev/null
ufw default allow outgoing >/dev/null

# SSH – immer zuerst, damit keine Sperrung passiert!
ufw allow "${SSH_PORT}/tcp" comment "SSH" >/dev/null
success "SSH (Port ${SSH_PORT}/tcp) erlaubt."

# HTTP (80) – öffentlich für Let's Encrypt & Redirect
if [[ "$ALLOW_PUBLIC_HTTP" == "yes" ]]; then
  ufw allow 80/tcp  comment "BunkerWeb HTTP"  >/dev/null
  success "HTTP  (Port 80/tcp) erlaubt."
fi

# HTTPS (443) TCP + UDP (QUIC/HTTP3)
if [[ "$ALLOW_PUBLIC_HTTP" == "yes" ]]; then
  ufw allow 443/tcp comment "BunkerWeb HTTPS"    >/dev/null
  ufw allow 443/udp comment "BunkerWeb QUIC/H3"  >/dev/null
  success "HTTPS (Port 443 tcp+udp) erlaubt."
fi

# Web UI Port 7000 – NUR wenn MGMT_IP gesetzt, sonst geschlossen lassen
if [[ -n "$MGMT_IP" ]]; then
  ufw allow from "${MGMT_IP}" to any port 7000 proto tcp comment "BunkerWeb UI (direkt)" >/dev/null
  success "Web-UI Port 7000/tcp erlaubt für: ${MGMT_IP}"
  warn "Hinweis: Port 7000 ist das direkte UI OHNE BunkerWeb davor – nur für Einrichtung!"
else
  info "Web-UI Port 7000 bleibt geschlossen (kein direkter Zugriff)."
  info "Der UI-Zugang erfolgt ausschließlich über HTTPS (443) nach dem Setup-Wizard."
fi

# UFW aktivieren (ohne Unterbrechung bestehender Verbindungen)
if ufw status | grep -q "Status: active"; then
  ufw reload >/dev/null
  success "UFW neu geladen."
else
  ufw --force enable >/dev/null
  success "UFW aktiviert."
fi

echo ""
ufw status verbose

# ─────────────────────────────────────────────────────────────────────────────
# VERZEICHNIS ANLEGEN
# ─────────────────────────────────────────────────────────────────────────────
header "Installationsverzeichnis vorbereiten"

mkdir -p "${INSTALL_DIR}"
cd "${INSTALL_DIR}"
success "Verzeichnis: ${INSTALL_DIR}"

# ─────────────────────────────────────────────────────────────────────────────
# DOCKER COMPOSE DATEI ERSTELLEN
# ─────────────────────────────────────────────────────────────────────────────
header "docker-compose.yml erstellen"

# Sicherheitshinweis: AIO-Image enthält BunkerWeb, UI, Scheduler und CrowdSec
# in einem Container. Ideal für Single-Node / MSP-Einstieg.

cat > "${INSTALL_DIR}/docker-compose.yml" <<'EOF'
# =============================================================================
#  BunkerWeb All-in-One – Docker Compose
#  Doku: https://docs.bunkerweb.io/latest/integrations/#all-in-one-aio-image
# =============================================================================

services:

  # ---------------------------------------------------------------------------
  # BunkerWeb All-in-One Container
  # ---------------------------------------------------------------------------
  bunkerweb-aio:
    image: bunkerity/bunkerweb-all-in-one:1.6.8
    container_name: bunkerweb-aio
    restart: unless-stopped
    ports:
      - "80:8080/tcp"       # HTTP
      - "443:8443/tcp"      # HTTPS
      - "443:8443/udp"      # QUIC / HTTP3
      # Port 7000 wird NICHT nach außen gemappt – Zugang nur über UFW-Regel
      # oder explizit für lokale Einrichtung einkommentieren:
      # - "127.0.0.1:7000:7000/tcp"   # UI nur lokal erreichbar (SSH-Tunnel)
    volumes:
      - bw-storage:/data
    # Optionale Umgebungsvariablen – bei Bedarf einkommentieren und hier einfügen:
    #   MULTISITE: "yes"                  # Mehrere Domains
    #   USE_MODSECURITY_GLOBAL_CRS: "yes" # RAM-Effizienz in Produktion empfohlen
    #   USE_CROWDSEC: "yes"               # CrowdSec Integration (im AIO-Image integriert)
    networks:
      - bw-services    # Netzwerk für geschützte Backend-Services

  # ---------------------------------------------------------------------------
  # Beispiel: Einen Backend-Service anbinden (auskommentiert)
  # ---------------------------------------------------------------------------
  # myapp:
  #   image: your-app-image:latest
  #   container_name: myapp
  #   restart: unless-stopped
  #   networks:
  #     - bw-services
  #   # Keine ports: Eintrag nötig – BunkerWeb routed den Traffic

volumes:
  bw-storage:
    driver: local

networks:
  bw-services:
    name: bw-services
    driver: bridge
EOF

success "docker-compose.yml erstellt."

# ─────────────────────────────────────────────────────────────────────────────
# SYSTEMD SERVICE (optional, für Autostart unabhängig von Docker-Autostart)
# ─────────────────────────────────────────────────────────────────────────────
header "Systemd-Service einrichten"

cat > /etc/systemd/system/bunkerweb.service <<EOF
[Unit]
Description=BunkerWeb All-in-One
Requires=docker.service
After=docker.service network-online.target
Wants=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=${INSTALL_DIR}
ExecStart=/usr/bin/docker compose up -d
ExecStop=/usr/bin/docker compose down
TimeoutStartSec=300

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable bunkerweb.service
success "Systemd-Service 'bunkerweb' aktiviert (Autostart beim Booten)."

# ─────────────────────────────────────────────────────────────────────────────
# BUNKERWEB STARTEN
# ─────────────────────────────────────────────────────────────────────────────
header "BunkerWeb starten"

cd "${INSTALL_DIR}"
info "Docker Images werden gezogen und Container gestartet..."
docker compose pull
docker compose up -d

success "BunkerWeb AIO Container gestartet."

# Warte kurz damit der Container hochfahren kann
info "Warte 10 Sekunden auf Container-Initialisierung..."
sleep 10

docker compose ps

# ─────────────────────────────────────────────────────────────────────────────
# ABSCHLUSS & NÄCHSTE SCHRITTE
# ─────────────────────────────────────────────────────────────────────────────
header "Installation abgeschlossen!"

SERVER_IP=$(hostname -I | awk '{print $1}')

echo -e "${GREEN}${BOLD}"
echo "  ✔  BunkerWeb All-in-One läuft!"
echo -e "${NC}"
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e " ${BOLD}Setup-Wizard aufrufen:${NC}"
echo -e "   ${CYAN}https://${SERVER_IP}/setup${NC}  (IP, bei Zertifikat-Warnung bestätigen)"
echo -e "   ${CYAN}https://deine-domain.de/setup${NC}  (sobald DNS gesetzt)"
echo ""
echo -e " ${BOLD}Direkte UI (nur wenn Port 7000 in UFW freigegeben):${NC}"
echo -e "   ${CYAN}http://${SERVER_IP}:7000${NC}"
echo ""
echo -e " ${BOLD}Wichtige Dateien:${NC}"
echo -e "   Compose-File:  ${INSTALL_DIR}/docker-compose.yml"
echo -e "   Daten-Volume:  docker volume inspect bw-storage"
echo ""
echo -e " ${BOLD}Nützliche Befehle:${NC}"
echo -e "   Logs anzeigen:   ${YELLOW}docker logs -f bunkerweb-aio${NC}"
echo -e "   Status:          ${YELLOW}docker compose -f ${INSTALL_DIR}/docker-compose.yml ps${NC}"
echo -e "   Stoppen:         ${YELLOW}systemctl stop bunkerweb${NC}"
echo -e "   Starten:         ${YELLOW}systemctl start bunkerweb${NC}"
echo -e "   Neustart:        ${YELLOW}systemctl restart bunkerweb${NC}"
echo ""
echo -e " ${BOLD}Next Steps im Setup-Wizard:${NC}"
echo -e "   1. Admin-Account erstellen (User + Passwort)"
echo -e "   2. Domain für das Web-UI eingeben"
echo -e "   3. Let's Encrypt aktivieren (automatisches SSL)"
echo -e "   4. Ersten Service/Reverse-Proxy anlegen"
echo -e "${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

echo ""
warn "SICHERHEITSHINWEIS: Rufe den Setup-Wizard so schnell wie möglich auf,"
warn "da die Einrichtung ohne Auth zugänglich ist bis sie abgeschlossen wird!"
echo ""
