#!/usr/bin/env bash
# =============================================================================
# Authentik Install Script
# Basiert auf: https://docs.goauthentik.io/install-config/install/docker-compose/
#              https://docs.goauthentik.io/install-config/email/
#
# Installiert Authentik unter /opt/authentik
# Generiert sichere Passwörter und speichert sie in /opt/authentik/credentials.txt
# =============================================================================

set -euo pipefail

# --- Farben -------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# --- Hilfsfunktionen ----------------------------------------------------------
info()    { echo -e "${CYAN}[INFO]${NC}  $*"; }
success() { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; }
die()     { error "$*"; exit 1; }

ask() {
    # ask <Variablenname> <Prompt> [Standardwert]
    local varname="$1"
    local prompt="$2"
    local default="${3:-}"
    local input

    if [[ -n "$default" ]]; then
        read -rp "$(echo -e "${BOLD}${prompt}${NC} [${default}]: ")" input
        input="${input:-$default}"
    else
        while true; do
            read -rp "$(echo -e "${BOLD}${prompt}${NC}: ")" input
            [[ -n "$input" ]] && break
            warn "Eingabe darf nicht leer sein."
        done
    fi
    printf -v "$varname" '%s' "$input"
}

ask_secret() {
    # ask_secret <Variablenname> <Prompt>  (Eingabe wird nicht angezeigt)
    local varname="$1"
    local prompt="$2"
    local input
    read -rsp "$(echo -e "${BOLD}${prompt}${NC} (leer = kein Auth): ")" input
    echo
    printf -v "$varname" '%s' "$input"
}

ask_yesno() {
    # ask_yesno <Prompt> [y|n]  → gibt 0 (ja) oder 1 (nein) zurück
    local prompt="$1"
    local default="${2:-n}"
    local input
    read -rp "$(echo -e "${BOLD}${prompt}${NC} [y/n, Standard: ${default}]: ")" input
    input="${input:-$default}"
    [[ "${input,,}" =~ ^(y|yes|ja|j)$ ]] && return 0 || return 1
}

# --- Root-Check ---------------------------------------------------------------
[[ "$EUID" -eq 0 ]] || die "Dieses Script muss als root ausgeführt werden."

# =============================================================================
# BANNER
# =============================================================================
echo -e "${BOLD}"
echo "============================================================"
echo "   Authentik Install Script – Docker Compose"
echo "   Installationspfad: /opt/authentik"
echo "============================================================"
echo -e "${NC}"

# =============================================================================
# SCHRITT 1 – PARAMETER ABFRAGEN
# =============================================================================
echo -e "\n${BOLD}=== 1/6  Grundkonfiguration ===${NC}\n"

ask AUTHENTIK_DOMAIN   "Öffentliche Domain / Hostname (z.B. auth.example.com)" ""
ask COMPOSE_PORT_HTTP  "HTTP-Port für Authentik"  "80"
ask COMPOSE_PORT_HTTPS "HTTPS-Port für Authentik" "443"

echo -e "\n${BOLD}=== 2/6  E-Mail / SMTP-Konfiguration ===${NC}\n"
warn "SMTP-Einstellungen können auch später in der .env angepasst werden."
echo

ask  SMTP_HOST     "SMTP-Host"                      "localhost"
ask  SMTP_PORT     "SMTP-Port"                       "587"
ask  SMTP_FROM     "Absender-Adresse (FROM)"         "authentik@${AUTHENTIK_DOMAIN}"
ask  SMTP_USERNAME "SMTP-Benutzername"               ""
ask_secret SMTP_PASSWORD "SMTP-Passwort"

# TLS / SSL – gegenseitig ausschließend
SMTP_USE_TLS="false"
SMTP_USE_SSL="false"

if ask_yesno "StartTLS verwenden? (empfohlen für Port 587)" "y"; then
    SMTP_USE_TLS="true"
elif ask_yesno "SSL/TLS verwenden? (Port 465)" "n"; then
    SMTP_USE_SSL="true"
fi

ask SMTP_TIMEOUT "SMTP Timeout (Sekunden)" "10"

echo -e "\n${BOLD}=== 3/6  Optionen ===${NC}\n"

ENABLE_ERROR_REPORTING="false"
if ask_yesno "Fehlerberichte an Authentik senden (Error Reporting)?" "n"; then
    ENABLE_ERROR_REPORTING="true"
fi

# =============================================================================
# SCHRITT 2 – VORAUSSETZUNGEN PRÜFEN
# =============================================================================
echo -e "\n${BOLD}=== 4/6  Voraussetzungen prüfen ===${NC}\n"

command -v docker      &>/dev/null || die "Docker ist nicht installiert."
command -v openssl     &>/dev/null || die "openssl ist nicht installiert."

# Docker Compose v2 prüfen
if docker compose version &>/dev/null; then
    success "Docker Compose v2 gefunden: $(docker compose version --short)"
else
    die "Docker Compose v2 nicht gefunden. Bitte 'docker-compose-plugin' installieren."
fi

# =============================================================================
# SCHRITT 3 – VERZEICHNIS ANLEGEN
# =============================================================================
echo -e "\n${BOLD}=== 5/6  Verzeichnisstruktur anlegen ===${NC}\n"

INSTALL_DIR="/opt/authentik"
mkdir -p "${INSTALL_DIR}"/{media,certs,templates,custom-templates}
chmod 750 "${INSTALL_DIR}"

success "Verzeichnis ${INSTALL_DIR} erstellt."

cd "${INSTALL_DIR}"

# =============================================================================
# SCHRITT 4 – DOCKER-COMPOSE.YML HERUNTERLADEN
# =============================================================================
info "Lade docker-compose.yml herunter..."
wget -q -O docker-compose.yml https://docs.goauthentik.io/compose.yml \
    || die "Download von docker-compose.yml fehlgeschlagen. Netzwerk prüfen."
success "docker-compose.yml heruntergeladen."

# =============================================================================
# SCHRITT 5 – PASSWÖRTER GENERIEREN
# =============================================================================
echo -e "\n${BOLD}=== 6/6  Passwörter generieren & .env schreiben ===${NC}\n"

# PostgreSQL-Passwort: max. 99 Zeichen laut Doku, base64 ~48 Zeichen nach trim
PG_PASS="$(openssl rand -base64 36 | tr -d '\n')"
# Secret Key: 60 Byte base64
AUTHENTIK_SECRET_KEY="$(openssl rand -base64 60 | tr -d '\n')"

success "PG_PASS generiert        (${#PG_PASS} Zeichen)"
success "AUTHENTIK_SECRET_KEY generiert (${#AUTHENTIK_SECRET_KEY} Zeichen)"

# =============================================================================
# SCHRITT 6 – .ENV DATEI SCHREIBEN
# =============================================================================
ENV_FILE="${INSTALL_DIR}/.env"

cat > "${ENV_FILE}" <<EOF
# ==============================================================
# Authentik – Umgebungsvariablen
# Generiert am: $(date '+%Y-%m-%d %H:%M:%S')
# Dokumentation: https://docs.goauthentik.io/install-config/
# ==============================================================

# --- Datenbank -----------------------------------------------
PG_PASS=${PG_PASS}

# --- Authentik Core ------------------------------------------
AUTHENTIK_SECRET_KEY=${AUTHENTIK_SECRET_KEY}
AUTHENTIK_ERROR_REPORTING__ENABLED=${ENABLE_ERROR_REPORTING}

# --- Ports ---------------------------------------------------
COMPOSE_PORT_HTTP=${COMPOSE_PORT_HTTP}
COMPOSE_PORT_HTTPS=${COMPOSE_PORT_HTTPS}

# --- E-Mail / SMTP -------------------------------------------
AUTHENTIK_EMAIL__HOST=${SMTP_HOST}
AUTHENTIK_EMAIL__PORT=${SMTP_PORT}
AUTHENTIK_EMAIL__USERNAME=${SMTP_USERNAME}
AUTHENTIK_EMAIL__PASSWORD=${SMTP_PASSWORD}
AUTHENTIK_EMAIL__USE_TLS=${SMTP_USE_TLS}
AUTHENTIK_EMAIL__USE_SSL=${SMTP_USE_SSL}
AUTHENTIK_EMAIL__TIMEOUT=${SMTP_TIMEOUT}
AUTHENTIK_EMAIL__FROM=${SMTP_FROM}
EOF

chmod 640 "${ENV_FILE}"
success ".env Datei geschrieben: ${ENV_FILE}"

# =============================================================================
# CREDENTIALS-DATEI SICHERN
# =============================================================================
CRED_FILE="${INSTALL_DIR}/credentials.txt"

cat > "${CRED_FILE}" <<EOF
============================================================
  Authentik – Zugangsdaten (VERTRAULICH)
  Generiert am: $(date '+%Y-%m-%d %H:%M:%S')
============================================================

Installationspfad : ${INSTALL_DIR}
Öffentliche Domain: ${AUTHENTIK_DOMAIN}

PostgreSQL Passwort (PG_PASS):
  ${PG_PASS}

Authentik Secret Key (AUTHENTIK_SECRET_KEY):
  ${AUTHENTIK_SECRET_KEY}

SMTP Benutzername : ${SMTP_USERNAME}
SMTP Passwort     : ${SMTP_PASSWORD}

------------------------------------------------------------
Initial-Setup URL:
  http://${AUTHENTIK_DOMAIN}:${COMPOSE_PORT_HTTP}/if/flow/initial-setup/
  https://${AUTHENTIK_DOMAIN}:${COMPOSE_PORT_HTTPS}/if/flow/initial-setup/

Hinweis: Trailing-Slash am Ende der URL ist erforderlich!
============================================================
EOF

chmod 600 "${CRED_FILE}"
success "Credentials gespeichert: ${CRED_FILE}  (chmod 600)"

# =============================================================================
# DOCKER COMPOSE STARTEN
# =============================================================================
echo ""
if ask_yesno "Authentik jetzt starten? (docker compose pull && docker compose up -d)" "y"; then
    info "Lade Docker-Images herunter (kann einige Minuten dauern)..."
    docker compose pull

    info "Starte Authentik..."
    docker compose up -d

    echo ""
    success "============================================================"
    success " Authentik läuft!"
    success ""
    success " Initial-Setup:"
    success "   http://${AUTHENTIK_DOMAIN}:${COMPOSE_PORT_HTTP}/if/flow/initial-setup/"
    success "   https://${AUTHENTIK_DOMAIN}:${COMPOSE_PORT_HTTPS}/if/flow/initial-setup/"
    success ""
    success " Zugangsdaten: ${CRED_FILE}"
    success "============================================================"
else
    info "Authentik wurde NICHT gestartet."
    info "Manuell starten:"
    info "  cd ${INSTALL_DIR} && docker compose pull && docker compose up -d"
fi

# =============================================================================
# SMTP TEST ANBIETEN
# =============================================================================
echo ""
if ask_yesno "E-Mail-Konfiguration testen? (benötigt laufende Container)" "n"; then
    ask TEST_EMAIL_ADDR "Ziel-E-Mail-Adresse für den Test" ""
    info "Sende Test-E-Mail an ${TEST_EMAIL_ADDR}..."
    docker compose exec worker ak test_email "${TEST_EMAIL_ADDR}" \
        && success "Test-E-Mail gesendet!" \
        || warn "Test-E-Mail konnte nicht gesendet werden – SMTP-Einstellungen in ${ENV_FILE} prüfen."
fi

echo ""
info "Fertig. Alle Dateien liegen unter ${INSTALL_DIR}/"
echo ""
