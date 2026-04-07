#!/usr/bin/env bash
# =============================================================================
#  ERPNext v16 Installer für Ubuntu 24.04 LTS
# -----------------------------------------------------------------------------
#  Basiert auf:  https://discuss.frappe.io/t/guide-how-to-install-erpnext-v16-
#                on-linux-ubuntu-24-04-step-by-step-instructions/159255
#
#  Architektur:
#    - Python 3.14 via uv (Userspace, kein deadsnakes/PPA)
#    - Node 24 via nvm
#    - frappe-bench via uv tool install
#    - MariaDB Ubuntu-Default (10.11) - laut Frappe-Guide reicht das in der
#      Praxis, obwohl v16 offiziell 11.8+ fordert
#    - wkhtmltopdf 0.12.6.1-2 (jammy_amd64.deb mit patched Qt)
#    - Production-Setup via supervisor + nginx, mit Ansible
#
#  Features:
#    - Interaktive App-Auswahl (ERPNext + HRMS + payments + alyf-de DACH-Apps)
#    - Pre-flight Branch-Check per git ls-remote für jede ausgewählte App
#    - Dev- oder Production-Modus
#    - Passwort-Generierung mit Vorschlägen
#    - Zugangsdaten in /root/erpnext-install-info.txt (chmod 600)
#    - Temporäres NOPASSWD-sudoers während Install (trap-cleanup)
#
#  Nutzung:
#    chmod +x install-erpnext-v16.sh
#    sudo ./install-erpnext-v16.sh
# =============================================================================

set -euo pipefail

# ---------- Farben ----------
readonly C_RESET='\033[0m'
readonly C_BOLD='\033[1m'
readonly C_RED='\033[0;31m'
readonly C_GREEN='\033[0;32m'
readonly C_YELLOW='\033[0;33m'
readonly C_BLUE='\033[0;34m'

log()   { echo -e "${C_BLUE}[*]${C_RESET} $*"; }
ok()    { echo -e "${C_GREEN}[+]${C_RESET} $*"; }
warn()  { echo -e "${C_YELLOW}[!]${C_RESET} $*"; }
die()   { echo -e "${C_RED}[x]${C_RESET} $*" >&2; exit 1; }
step()  { echo; echo -e "${C_BOLD}${C_BLUE}==> $*${C_RESET}"; }

# ---------- Cleanup (sudoers-Snippet immer entfernen) ----------
SUDOERS_SNIPPET=""
cleanup() {
    if [[ -n "$SUDOERS_SNIPPET" && -f "$SUDOERS_SNIPPET" ]]; then
        rm -f "$SUDOERS_SNIPPET"
    fi
}
trap cleanup EXIT INT TERM

# ---------- Passwort-Generator ----------
gen_password() {
    openssl rand -base64 32 | tr -d '/+=\n' | cut -c1-24
}

prompt_password() {
    local label="$1"
    local suggested
    suggested="$(gen_password)"
    echo >&2
    echo -e "${C_BOLD}${label}${C_RESET}" >&2
    echo -e "  Vorschlag: ${C_GREEN}${suggested}${C_RESET}" >&2
    local input input2
    while true; do
        read -rp "  Übernehmen (Enter) oder eigenes Passwort eingeben: " input
        if [[ -z "$input" ]]; then
            echo "$suggested"
            return
        fi
        read -rp "  Passwort wiederholen: " input2
        if [[ "$input" == "$input2" ]]; then
            echo "$input"
            return
        fi
        warn "Passwörter stimmen nicht überein. Nochmal."
    done
}

# ---------- Pre-Flight ----------
[[ $EUID -eq 0 ]] || die "Bitte mit sudo / als root ausführen."

if ! grep -q '24\.04' /etc/os-release; then
    warn "Dies ist nicht Ubuntu 24.04 - Script ist nur dafür getestet."
    read -rp "Trotzdem fortfahren? [y/N] " _cont
    [[ "${_cont,,}" == "y" ]] || exit 1
fi

command -v openssl &>/dev/null || apt-get install -y openssl
command -v git &>/dev/null || apt-get install -y git

step "ERPNext v16 Installer - interaktive Konfiguration"

# ---------- Setup-Modus ----------
echo
echo "Setup-Modus wählen:"
echo "  1) Production  - nginx + supervisor, Autostart, gleiches Verhalten wie Live"
echo "  2) Development - 'bench start' im Terminal, File-Watcher, kein Autostart"
echo
read -rp "Modus [1/2] (1): " _mode
_mode=${_mode:-1}
if [[ "$_mode" == "2" ]]; then
    SETUP_MODE="dev"
else
    SETUP_MODE="prod"
fi

read -rp "developer_mode aktivieren (für Anpassungen via UI)? [Y/n]: " _dev
DEV_MODE=1
[[ "${_dev,,}" == "n" ]] && DEV_MODE=0

# ---------- Linux-User ----------
read -rp "Linux-User für Frappe [frappe]: " FRAPPE_USER
FRAPPE_USER=${FRAPPE_USER:-frappe}

FRAPPE_PW="$(prompt_password "Passwort für Linux-User '${FRAPPE_USER}'")"
MYSQL_ROOT_PW="$(prompt_password "MariaDB root-Passwort")"

# ---------- Site ----------
echo
read -rp "Site-Name (FQDN oder lokal) [site1.local]: " SITE_NAME
SITE_NAME=${SITE_NAME:-site1.local}

ADMIN_PW="$(prompt_password "Administrator-Passwort für Site '${SITE_NAME}'")"

# ---------- App-Katalog ----------
# Format: name | git-url | app-name | branch | description | default
declare -A APPS_URL APPS_NAME APPS_BRANCH APPS_DESC APPS_DEFAULT
APP_ORDER=(payments hrms helpdesk lms builder crm drive insights gameplan wiki print_designer erpnext_germany eu_einvoice pdf_on_submit erpnext_datev banking)

# Offizielle Frappe-Apps (Kurzname als URL ist ok für 'bench get-app')
APPS_URL[payments]="payments"
APPS_NAME[payments]="payments"
APPS_BRANCH[payments]="version-16"
APPS_DESC[payments]="Payments (Stripe/PayPal/... Integration, offiziell Frappe)"
APPS_DEFAULT[payments]="y"

APPS_URL[hrms]="hrms"
APPS_NAME[hrms]="hrms"
APPS_BRANCH[hrms]="version-16"
APPS_DESC[hrms]="HR & Payroll Modul (offiziell Frappe, ersetzt time_capture)"
APPS_DEFAULT[hrms]="y"

APPS_URL[helpdesk]="helpdesk"
APPS_NAME[helpdesk]="helpdesk"
APPS_BRANCH[helpdesk]="version-16"
APPS_DESC[helpdesk]="Ticketsystem / Customer Support (offiziell Frappe)"
APPS_DEFAULT[helpdesk]="y"

APPS_URL[lms]="lms"
APPS_NAME[lms]="lms"
APPS_BRANCH[lms]="main"
APPS_DESC[lms]="Learning Management System (offiziell Frappe)"
APPS_DEFAULT[lms]="n"

APPS_URL[builder]="builder"
APPS_NAME[builder]="builder"
APPS_BRANCH[builder]="main"
APPS_DESC[builder]="Visueller Website-Builder (offiziell Frappe)"
APPS_DEFAULT[builder]="n"

APPS_URL[crm]="crm"
APPS_NAME[crm]="crm"
APPS_BRANCH[crm]="main"
APPS_DESC[crm]="Vollwertiges Sales-CRM mit Leads, Deals, Pipeline (offiziell Frappe)"
APPS_DEFAULT[crm]="n"

APPS_URL[drive]="drive"
APPS_NAME[drive]="drive"
APPS_BRANCH[drive]="main"
APPS_DESC[drive]="Self-hosted Datei-Sharing wie Google Drive (offiziell Frappe)"
APPS_DEFAULT[drive]="n"

APPS_URL[insights]="insights"
APPS_NAME[insights]="insights"
APPS_BRANCH[insights]="main"
APPS_DESC[insights]="BI-Tool mit Dashboards und Charts (offiziell Frappe)"
APPS_DEFAULT[insights]="y"

APPS_URL[gameplan]="gameplan"
APPS_NAME[gameplan]="gameplan"
APPS_BRANCH[gameplan]="main"
APPS_DESC[gameplan]="Team-Kollaboration / Diskussionen wie Basecamp (offiziell Frappe)"
APPS_DEFAULT[gameplan]="n"

APPS_URL[wiki]="wiki"
APPS_NAME[wiki]="wiki"
APPS_BRANCH[wiki]="master"
APPS_DESC[wiki]="Internes Wiki (offiziell Frappe)"
APPS_DEFAULT[wiki]="n"

APPS_URL[print_designer]="print_designer"
APPS_NAME[print_designer]="print_designer"
APPS_BRANCH[print_designer]="main"
APPS_DESC[print_designer]="Drag-and-Drop Print-Format-Builder (offiziell Frappe)"
APPS_DEFAULT[print_designer]="y"

# alyf-de DACH-Apps
APPS_URL[erpnext_germany]="https://github.com/alyf-de/erpnext_germany"
APPS_NAME[erpnext_germany]="erpnext_germany"
APPS_BRANCH[erpnext_germany]="version-16"
APPS_DESC[erpnext_germany]="DE-Lokalisierung (alyf.de) - Basis für datev/einvoice"
APPS_DEFAULT[erpnext_germany]="y"

APPS_URL[eu_einvoice]="https://github.com/alyf-de/eu_einvoice"
APPS_NAME[eu_einvoice]="eu_einvoice"
APPS_BRANCH[eu_einvoice]="version-16"
APPS_DESC[eu_einvoice]="E-Rechnung EU / XRechnung / ZUGFeRD (alyf.de)"
APPS_DEFAULT[eu_einvoice]="y"

APPS_URL[pdf_on_submit]="https://github.com/alyf-de/pdf_on_submit"
APPS_NAME[pdf_on_submit]="pdf_on_submit"
APPS_BRANCH[pdf_on_submit]="version-16"
APPS_DESC[pdf_on_submit]="PDF beim Submit automatisch erzeugen + anhängen (alyf.de)"
APPS_DEFAULT[pdf_on_submit]="y"

APPS_URL[erpnext_datev]="https://github.com/alyf-de/erpnext_datev"
APPS_NAME[erpnext_datev]="erpnext_datev"
APPS_BRANCH[erpnext_datev]="version-16"
APPS_DESC[erpnext_datev]="DATEV-Export für Steuerberater (alyf.de, braucht erpnext_germany)"
APPS_DEFAULT[erpnext_datev]="y"

APPS_URL[banking]="https://github.com/alyf-de/banking"
APPS_NAME[banking]="banking"
APPS_BRANCH[banking]="version-16"
APPS_DESC[banking]="Bank-Import / EBICS / Reconciliation (alyf.de)"
APPS_DEFAULT[banking]="y"

# ---------- App-Auswahl ----------
echo
step "Apps auswählen"
echo "Basis wird immer installiert: frappe + erpnext"
echo

declare -A APP_SELECTED
for k in "${APP_ORDER[@]}"; do
    def="${APPS_DEFAULT[$k]}"
    prompt="[${def^^}/$([ "$def" = "y" ] && echo n || echo y)]"
    read -rp "  ${k} - ${APPS_DESC[$k]} ${prompt}: " ans
    ans=${ans:-$def}
    if [[ "${ans,,}" == "y" ]]; then
        APP_SELECTED[$k]=1
    else
        APP_SELECTED[$k]=0
    fi
done

# Abhängigkeiten: erpnext_datev braucht erpnext_germany
if [[ ${APP_SELECTED[erpnext_datev]:-0} -eq 1 && ${APP_SELECTED[erpnext_germany]:-0} -eq 0 ]]; then
    warn "erpnext_datev ausgewählt -> ziehe erpnext_germany als Abhängigkeit mit rein."
    APP_SELECTED[erpnext_germany]=1
fi

# ---------- Pre-flight: Branch-Check für externe Repos ----------
echo
step "Pre-flight: Branch-Verfügbarkeit prüfen"
BRANCH_CHECK_FAILED=0
for k in "${APP_ORDER[@]}"; do
    [[ ${APP_SELECTED[$k]:-0} -eq 1 ]] || continue
    url="${APPS_URL[$k]}"
    branch="${APPS_BRANCH[$k]}"

    # Frappe-Default-Apps mit Kurznamen überspringen (kein git-check möglich)
    if [[ "$url" != http* ]]; then
        log "${k}: Frappe-Default-App, Branch ${branch} (kein remote check)"
        continue
    fi

    log "${k}: prüfe ${url} branch ${branch}..."
    if git ls-remote --heads "$url" "$branch" 2>/dev/null | grep -q "refs/heads/${branch}"; then
        ok "  ${k} branch ${branch} verfügbar"
    else
        warn "  ${k} branch ${branch} NICHT GEFUNDEN auf ${url}"
        BRANCH_CHECK_FAILED=1
    fi
done

if [[ $BRANCH_CHECK_FAILED -eq 1 ]]; then
    echo
    warn "Mindestens ein Branch wurde nicht gefunden."
    read -rp "Trotzdem fortfahren? [y/N]: " _cont
    [[ "${_cont,,}" == "y" ]] || die "Abgebrochen."
fi

# ---------- Zusammenfassung ----------
echo
step "Zusammenfassung"
SELECTED_APPS_LIST="frappe, erpnext"
for k in "${APP_ORDER[@]}"; do
    [[ ${APP_SELECTED[$k]:-0} -eq 1 ]] && SELECTED_APPS_LIST+=", ${APPS_NAME[$k]}"
done

cat <<EOF
  Setup-Modus     : ${SETUP_MODE}  ($([ "$SETUP_MODE" = "prod" ] && echo "nginx + supervisor" || echo "bench start"))
  developer_mode  : $([ "$DEV_MODE" = "1" ] && echo "an" || echo "aus")
  Linux-User      : ${FRAPPE_USER}
  Site            : ${SITE_NAME}
  Frappe-Version  : version-16
  Python          : 3.14 (via uv)
  Node.js         : 24 (via nvm)
  Apps            : ${SELECTED_APPS_LIST}

  Passwörter sind gesetzt (werden nach Install in /root/erpnext-install-info.txt
  gesichert, chmod 600).
EOF
echo
read -rp "So durchziehen? [Y/n]: " _go
[[ "${_go,,}" == "n" ]] && die "Abgebrochen."

# =============================================================================
# SCHRITT 1 : System-Pakete
# =============================================================================
step "1/9  System-Update und Basispakete"
export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a

# MariaDB-Prompts unterdrücken (root-User-Abfrage etc.)
echo "mariadb-server mariadb-server/root_password password" | debconf-set-selections
echo "mariadb-server mariadb-server/root_password_again password" | debconf-set-selections
echo "mariadb-server mariadb-server/feedback boolean false" | debconf-set-selections

apt-get update -y
apt-get upgrade -y

BASE_PKGS=(
    git curl wget sudo
    software-properties-common
    python3-dev python3-setuptools python3-pip python3-venv
    xvfb libfontconfig1 libxrender1 libjpeg-turbo8 xfonts-75dpi xfonts-base
    libmysqlclient-dev pkg-config
    redis-server
    mariadb-server mariadb-client
    build-essential
    cron
)
if [[ "$SETUP_MODE" == "prod" ]]; then
    BASE_PKGS+=(nginx supervisor ansible)
fi
apt-get install -y "${BASE_PKGS[@]}"
ok "Basispakete installiert."

# =============================================================================
# SCHRITT 2 : Frappe-User
# =============================================================================
step "2/9  Linux-User '${FRAPPE_USER}' anlegen"
if id "$FRAPPE_USER" &>/dev/null; then
    warn "User ${FRAPPE_USER} existiert bereits - Passwort wird aktualisiert."
    echo "${FRAPPE_USER}:${FRAPPE_PW}" | chpasswd
else
    adduser --disabled-password --gecos "" "$FRAPPE_USER"
    echo "${FRAPPE_USER}:${FRAPPE_PW}" | chpasswd
    usermod -aG sudo "$FRAPPE_USER"
    ok "User ${FRAPPE_USER} angelegt und in sudo-Gruppe."
fi
chmod -R o+rx "/home/${FRAPPE_USER}"

# Temporäres NOPASSWD-sudoers während Installation - bench setup ruft intern
# 'sudo supervisorctl' und ähnliches auf und würde sonst interaktiv blockieren.
# Die Datei wird per trap am Ende des Scripts wieder entfernt.
SUDOERS_SNIPPET="/etc/sudoers.d/99-${FRAPPE_USER}-install"
echo "${FRAPPE_USER} ALL=(ALL) NOPASSWD:ALL" > "$SUDOERS_SNIPPET"
chmod 440 "$SUDOERS_SNIPPET"
visudo -cf "$SUDOERS_SNIPPET" >/dev/null || die "sudoers-Snippet ungültig."
ok "Temporäres NOPASSWD-sudoers für ${FRAPPE_USER} aktiv."

# =============================================================================
# SCHRITT 3 : MariaDB konfigurieren
# =============================================================================
step "3/9  MariaDB absichern und konfigurieren"
systemctl enable --now mariadb

mysql --protocol=socket -uroot <<SQL || warn "root-Passwort evtl. bereits gesetzt."
ALTER USER 'root'@'localhost' IDENTIFIED BY '${MYSQL_ROOT_PW}';
DELETE FROM mysql.user WHERE User='';
DELETE FROM mysql.global_priv WHERE User='';
DROP DATABASE IF EXISTS test;
FLUSH PRIVILEGES;
SQL

MARIADB_CONF="/etc/mysql/mariadb.conf.d/99-frappe.cnf"
cat > "$MARIADB_CONF" <<'EOF'
[mysqld]
character-set-client-handshake = FALSE
character-set-server = utf8mb4
collation-server = utf8mb4_unicode_ci

[mysql]
default-character-set = utf8mb4
EOF
systemctl restart mariadb
ok "MariaDB konfiguriert (utf8mb4)."

# =============================================================================
# SCHRITT 4 : wkhtmltopdf (gepatchte Version von GitHub)
# =============================================================================
step "4/9  wkhtmltopdf 0.12.6.1-2 (patched Qt)"
if ! command -v wkhtmltopdf &>/dev/null || ! wkhtmltopdf --version 2>&1 | grep -q 'with patched qt'; then
    WKHTML_DEB="/tmp/wkhtmltox.deb"
    WKHTML_URL="https://github.com/wkhtmltopdf/packaging/releases/download/0.12.6.1-2/wkhtmltox_0.12.6.1-2.jammy_amd64.deb"
    wget -qO "$WKHTML_DEB" "$WKHTML_URL"
    apt-get install -y "$WKHTML_DEB" || apt-get install -yf
    rm -f "$WKHTML_DEB"
    ok "wkhtmltopdf installiert: $(wkhtmltopdf --version)"
else
    ok "wkhtmltopdf bereits mit patched Qt vorhanden."
fi

# =============================================================================
# SCHRITT 5+ : Frappe-User-Setup (uv, python 3.14, node 24, bench, site, apps)
# =============================================================================
step "5/9  Frappe-User-Setup als '${FRAPPE_USER}' (uv + Python 3.14 + Node 24 + bench)"

FRAPPE_SCRIPT="/tmp/_frappe_setup_${FRAPPE_USER}.sh"
cat > "$FRAPPE_SCRIPT" <<FRAPPE_EOF
#!/usr/bin/env bash
set -euo pipefail

MYSQL_ROOT_PW='${MYSQL_ROOT_PW}'
SITE_NAME='${SITE_NAME}'
ADMIN_PW='${ADMIN_PW}'
DEV_MODE='${DEV_MODE}'
SETUP_MODE='${SETUP_MODE}'
FRAPPE_USER='${FRAPPE_USER}'

cd "\$HOME"

# ---------- uv installieren ----------
if [[ ! -x "\$HOME/.local/bin/uv" ]]; then
    curl -LsSf https://astral.sh/uv/install.sh | sh
fi
export PATH="\$HOME/.local/bin:\$PATH"
echo 'export PATH="\$HOME/.local/bin:\$PATH"' >> "\$HOME/.bashrc"

# ---------- Python 3.14 via uv ----------
uv python install 3.14 --default
uv python pin 3.14 || true

# ---------- nvm + Node 24 ----------
if [[ ! -d "\$HOME/.nvm" ]]; then
    curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash
fi
export NVM_DIR="\$HOME/.nvm"
# shellcheck disable=SC1091
source "\$NVM_DIR/nvm.sh"

nvm install 24
nvm alias default 24
nvm use 24

# ---------- yarn ----------
if ! command -v yarn &>/dev/null; then
    npm install -g yarn
fi

# ---------- frappe-bench via uv ----------
if ! command -v bench &>/dev/null; then
    uv tool install frappe-bench
fi

# ---------- bench init ----------
if [[ ! -d "\$HOME/frappe-bench" ]]; then
    bench init --frappe-branch version-16 frappe-bench
fi
cd "\$HOME/frappe-bench"

# ---------- Site anlegen ----------
if [[ ! -d "sites/\${SITE_NAME}" ]]; then
    bench new-site "\${SITE_NAME}" \\
        --mariadb-root-password "\${MYSQL_ROOT_PW}" \\
        --admin-password "\${ADMIN_PW}" \\
        --mariadb-user-host-login-scope='%'
fi

bench use "\${SITE_NAME}"

# ---------- Apps holen (vor Production-Setup, brauchen kein Redis) ----------
get_app() {
    local name="\$1" url="\$2" branch="\$3"
    if [[ -d "apps/\${name}" ]]; then
        echo "[=] app \${name} bereits vorhanden - skip"
        return
    fi
    bench get-app --branch "\$branch" "\$url"
}

get_app erpnext erpnext version-16
FRAPPE_EOF

# gewählte Apps in das Sub-Script einfügen
for k in "${APP_ORDER[@]}"; do
    [[ ${APP_SELECTED[$k]:-0} -eq 1 ]] || continue
    echo "get_app '${APPS_NAME[$k]}' '${APPS_URL[$k]}' '${APPS_BRANCH[$k]}'" >> "$FRAPPE_SCRIPT"
done

cat >> "$FRAPPE_SCRIPT" <<'FRAPPE_EOF'

echo "[+] Frappe-Setup Phase 1 fertig (Site + Apps geholt)."
FRAPPE_EOF

chmod +x "$FRAPPE_SCRIPT"
chown "${FRAPPE_USER}:${FRAPPE_USER}" "$FRAPPE_SCRIPT"

step "6/9  Frappe-Setup Phase 1: bench init, Site, Apps holen (kann 15-30 Min dauern)"
sudo -H -u "$FRAPPE_USER" bash "$FRAPPE_SCRIPT"
rm -f "$FRAPPE_SCRIPT"

# =============================================================================
# SCHRITT 7 : Redis/Supervisor zum Laufen bringen VOR App-Install
# -----------------------------------------------------------------------------
# v16 erwartet Redis auf Ports 11000/12000/13000 (separate Instanzen, nicht
# die System-Redis auf 6379). Diese werden im Production-Modus durch
# Supervisor gestartet, im Dev-Modus durch 'bench start' (honcho).
# Da install-app während after_install Background-Jobs queued, braucht es
# Redis bereits VOR dem App-Install.
# =============================================================================

if [[ "$SETUP_MODE" == "prod" ]]; then
    step "7a/9  Production-Setup (nginx + supervisor) - VOR App-Install"

    rm -f /etc/nginx/sites-enabled/default

    BENCH_DIR="/home/${FRAPPE_USER}/frappe-bench"
    cd "$BENCH_DIR"

    # bench liegt in ~/.local/bin des frappe-Users (uv tool install).
    # sudo strippt PATH per default -> bench wird nicht gefunden.
    NODE_VER="$(sudo -u $FRAPPE_USER bash -c 'source ~/.nvm/nvm.sh && nvm version')"
    FRAPPE_PATH="/home/${FRAPPE_USER}/.local/bin:/home/${FRAPPE_USER}/.nvm/versions/node/${NODE_VER}/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

    sudo env "PATH=${FRAPPE_PATH}" bench setup production "$FRAPPE_USER" --yes

    # Supervisor-Config Symlink falls nicht automatisch
    SUPERVISOR_CONF="/etc/supervisor/conf.d/frappe-bench.conf"
    BENCH_SUPERVISOR_CONF="${BENCH_DIR}/config/supervisor.conf"
    if [[ ! -f "$SUPERVISOR_CONF" && -f "$BENCH_SUPERVISOR_CONF" ]]; then
        warn "Supervisor-Config nicht automatisch verlinkt - hole das nach."
        ln -sf "$BENCH_SUPERVISOR_CONF" "$SUPERVISOR_CONF"
        supervisorctl reread
        supervisorctl update
    fi

    systemctl enable --now supervisor
    systemctl restart supervisor
    systemctl enable --now nginx
    systemctl restart nginx

    # Auf Redis-Ports warten
    log "Warte auf Redis (Ports 11000, 12000, 13000)..."
    for port in 11000 12000 13000; do
        for i in {1..30}; do
            if (echo > /dev/tcp/127.0.0.1/$port) 2>/dev/null; then
                ok "  Redis Port $port ist erreichbar."
                break
            fi
            sleep 1
            if [[ $i -eq 30 ]]; then
                warn "  Redis Port $port nach 30s nicht erreichbar - install-app wird vermutlich fehlschlagen."
            fi
        done
    done

    sleep 2
    log "Supervisor-Status:"
    supervisorctl status || true
    ok "Production-Stack läuft - Redis ist bereit für App-Installation."

else
    step "7a/9  Dev-Modus: Redis im Hintergrund starten (für App-Install)"

    BENCH_DIR="/home/${FRAPPE_USER}/frappe-bench"

    # Im Dev-Modus starten wir nur die drei Redis-Instanzen via honcho aus dem
    # Procfile. Diese laufen im Hintergrund während des App-Installs, nach
    # dem Install bleiben sie aktiv (User kann später bench start nutzen, das
    # benutzt sie weiter oder startet sie neu).
    HONCHO_LOG="/tmp/honcho-redis-install.log"
    sudo -H -u "$FRAPPE_USER" bash -c "
        source ~/.nvm/nvm.sh
        export PATH=\"\$HOME/.local/bin:\$PATH\"
        cd '${BENCH_DIR}'
        nohup honcho start redis_cache redis_queue redis_socketio > '${HONCHO_LOG}' 2>&1 &
        echo \$! > /tmp/honcho-redis.pid
        disown
    " || warn "honcho start fehlgeschlagen - install-app wird vermutlich fehlschlagen."

    # Auf Redis-Ports warten
    log "Warte auf Redis (Ports 11000, 12000, 13000)..."
    for port in 11000 12000 13000; do
        for i in {1..30}; do
            if (echo > /dev/tcp/127.0.0.1/$port) 2>/dev/null; then
                ok "  Redis Port $port ist erreichbar."
                break
            fi
            sleep 1
            if [[ $i -eq 30 ]]; then
                warn "  Redis Port $port nach 30s nicht erreichbar - log: ${HONCHO_LOG}"
            fi
        done
    done
fi

# =============================================================================
# SCHRITT 7b : Apps auf Site installieren (jetzt mit laufendem Redis)
# =============================================================================
step "7b/9  Apps auf Site installieren"

INSTALL_SCRIPT="/tmp/_frappe_install_${FRAPPE_USER}.sh"
cat > "$INSTALL_SCRIPT" <<INSTALL_EOF
#!/usr/bin/env bash
set -euo pipefail

SITE_NAME='${SITE_NAME}'
DEV_MODE='${DEV_MODE}'

export PATH="\$HOME/.local/bin:\$PATH"
export NVM_DIR="\$HOME/.nvm"
# shellcheck disable=SC1091
source "\$NVM_DIR/nvm.sh"
nvm use 24 >/dev/null

cd "\$HOME/frappe-bench"

install_app() {
    local name="\$1"
    if bench --site "\${SITE_NAME}" list-apps 2>/dev/null | grep -qw "\$name"; then
        echo "[=] \${name} bereits auf Site installiert - skip"
        return
    fi
    bench --site "\${SITE_NAME}" install-app "\$name"
}

install_app erpnext
INSTALL_EOF

# Install-Reihenfolge: erpnext_germany zuerst, dann Apps die darauf aufbauen
INSTALL_ORDER=(erpnext_germany banking eu_einvoice erpnext_datev pdf_on_submit hrms helpdesk lms builder crm drive insights gameplan wiki print_designer payments)
for k in "${INSTALL_ORDER[@]}"; do
    [[ ${APP_SELECTED[$k]:-0} -eq 1 ]] || continue
    echo "install_app ${APPS_NAME[$k]}" >> "$INSTALL_SCRIPT"
done

cat >> "$INSTALL_SCRIPT" <<'INSTALL_EOF'

# Finale Settings
bench --site "${SITE_NAME}" set-maintenance-mode off
bench --site "${SITE_NAME}" enable-scheduler

if [[ "${DEV_MODE}" == "1" ]]; then
    bench set-config -g developer_mode 1
    bench --site "${SITE_NAME}" clear-cache
fi

echo "[+] App-Install fertig."
INSTALL_EOF

chmod +x "$INSTALL_SCRIPT"
chown "${FRAPPE_USER}:${FRAPPE_USER}" "$INSTALL_SCRIPT"
sudo -H -u "$FRAPPE_USER" bash "$INSTALL_SCRIPT"
rm -f "$INSTALL_SCRIPT"

# Im Dev-Modus den temporären honcho-redis-Prozess wieder beenden
if [[ "$SETUP_MODE" == "dev" && -f /tmp/honcho-redis.pid ]]; then
    HONCHO_PID="$(cat /tmp/honcho-redis.pid)"
    if kill -0 "$HONCHO_PID" 2>/dev/null; then
        log "Beende temporären honcho-redis (PID $HONCHO_PID)..."
        pkill -P "$HONCHO_PID" 2>/dev/null || true
        kill "$HONCHO_PID" 2>/dev/null || true
    fi
    rm -f /tmp/honcho-redis.pid /tmp/honcho-redis-install.log
fi

# Im Production-Modus alles nochmal sauber durchstarten
if [[ "$SETUP_MODE" == "prod" ]]; then
    step "7c/9  Production-Stack neu starten (nach App-Install)"
    supervisorctl restart all
    sleep 2
    supervisorctl status || true
fi

# =============================================================================
# SCHRITT 8 : Info-Datei schreiben
# =============================================================================
step "8/9  Zugangsdaten sichern"

INFO_FILE="/root/erpnext-install-info.txt"
SERVER_IP="$(hostname -I | awk '{print $1}')"
INSTALL_DATE="$(date '+%Y-%m-%d %H:%M:%S')"

INFO_APPS="frappe, erpnext"
for k in "${APP_ORDER[@]}"; do
    [[ ${APP_SELECTED[$k]:-0} -eq 1 ]] && INFO_APPS+=", ${APPS_NAME[$k]}"
done

cat > "$INFO_FILE" <<EOF
===============================================================================
  ERPNext v16 - Installationsdaten
  Erstellt: ${INSTALL_DATE}
  Host:     $(hostname) (${SERVER_IP})
===============================================================================

!! DIESE DATEI ENTHÄLT KLARTEXT-PASSWÖRTER !!
!! Nach dem Sichern in Passwort-Manager löschen:
!!   shred -u ${INFO_FILE}

-------------------------------------------------------------------------------
 SETUP
-------------------------------------------------------------------------------
  Modus            : ${SETUP_MODE} ($([ "$SETUP_MODE" = "prod" ] && echo "nginx + supervisor" || echo "bench start"))
  developer_mode   : $([ "$DEV_MODE" = "1" ] && echo "an" || echo "aus")
  Frappe-Version   : version-16
  Python           : 3.14 (uv-managed)
  Node.js          : 24 (nvm-managed)
  Bench-Manager    : uv tool
  Installierte Apps: ${INFO_APPS}

-------------------------------------------------------------------------------
 LINUX
-------------------------------------------------------------------------------
  User             : ${FRAPPE_USER}
  Passwort         : ${FRAPPE_PW}
  Home             : /home/${FRAPPE_USER}
  Bench-Verzeichnis: /home/${FRAPPE_USER}/frappe-bench
  uv-Binary        : /home/${FRAPPE_USER}/.local/bin/uv
  bench-Binary     : /home/${FRAPPE_USER}/.local/bin/bench

-------------------------------------------------------------------------------
 MARIADB
-------------------------------------------------------------------------------
  root-Passwort    : ${MYSQL_ROOT_PW}
  Host             : localhost
  Config           : /etc/mysql/mariadb.conf.d/99-frappe.cnf

-------------------------------------------------------------------------------
 ERPNEXT SITE
-------------------------------------------------------------------------------
  Site-Name        : ${SITE_NAME}
  Admin-User       : Administrator
  Admin-Passwort   : ${ADMIN_PW}
EOF

if [[ "$SETUP_MODE" == "prod" ]]; then
cat >> "$INFO_FILE" <<EOF
  URL (intern)     : http://${SERVER_IP}/
  URL (via Proxy)  : http://${SITE_NAME}/

  Reverse-Proxy-Hinweis: Der Proxy MUSS den Host-Header '${SITE_NAME}'
  durchreichen, sonst antwortet Frappe mit 404.
  nginx: proxy_set_header Host \$host;

-------------------------------------------------------------------------------
 PROZESSE (Supervisor)
-------------------------------------------------------------------------------
  Status           : sudo supervisorctl status
  Alles neu starten: sudo supervisorctl restart all
  Bench-Weg        : sudo -u ${FRAPPE_USER} bash -c 'cd ~/frappe-bench && bench restart'

  Supervisor-Config: /etc/supervisor/conf.d/frappe-bench.conf
  nginx-Config     : /etc/nginx/conf.d/frappe-bench.conf
EOF
else
cat >> "$INFO_FILE" <<EOF
  URL              : http://${SERVER_IP}:8000/

-------------------------------------------------------------------------------
 DEV-SERVER STARTEN
-------------------------------------------------------------------------------
  su - ${FRAPPE_USER}
  cd ~/frappe-bench
  bench start
EOF
fi

cat >> "$INFO_FILE" <<EOF

-------------------------------------------------------------------------------
 NÄCHSTE SCHRITTE - CUSTOM APP FÜR EIGENE ANPASSUNGEN
-------------------------------------------------------------------------------
  Bestehende Apps (erpnext, hrms, alyf-Apps) NIE direkt editieren - das
  überlebt 'bench update' nicht. Alle eigenen Anpassungen gehören in eine
  dedizierte Custom App, die als eigenes Git-Repo gepflegt wird.

  Custom App anlegen:
      su - ${FRAPPE_USER}
      cd ~/frappe-bench
      bench new-app meine_app
      bench --site ${SITE_NAME} install-app meine_app

  Anpassungen wie Custom Fields, Property Setter, Client/Server Scripts,
  Print Formats, Workflows etc. werden über 'fixtures' in der Custom App
  versioniert (in hooks.py konfigurieren). Damit ist das Grundgerüst auf
  jedem neuen System reproduzierbar nach 'bench install-app meine_app'.

-------------------------------------------------------------------------------
 APP-MANAGEMENT
-------------------------------------------------------------------------------
  Auflisten        : sudo -u ${FRAPPE_USER} bash -c 'cd ~/frappe-bench && bench --site ${SITE_NAME} list-apps'
  Hinzufügen       : bench get-app <git-url> + bench --site ${SITE_NAME} install-app <name>
  Entfernen        : bench --site ${SITE_NAME} uninstall-app <name> --no-backup --force
  Backup           : bench --site ${SITE_NAME} backup --with-files

-------------------------------------------------------------------------------
 UPDATES
-------------------------------------------------------------------------------
  Alle Apps        : sudo -u ${FRAPPE_USER} bash -c 'cd ~/frappe-bench && bench update'
  Nur eine App     : sudo -u ${FRAPPE_USER} bash -c 'cd ~/frappe-bench && bench update --apps erpnext'

  WICHTIG: NIE verschiedene ERPNext-Versionen auf demselben Server installieren.
  Für v15/v16 Tests immer separate VMs/Container nutzen.

  Apps die nicht von Frappe selbst entwickelt wurden, sind auf v16 noch nicht
  vollständig getestet. Vor Updates immer Backup machen.

-------------------------------------------------------------------------------
 LOGS
-------------------------------------------------------------------------------
  Frappe Logs      : /home/${FRAPPE_USER}/frappe-bench/logs/
  MariaDB          : /var/log/mysql/
  nginx            : /var/log/nginx/  (nur Production)
  Supervisor       : /var/log/supervisor/  (nur Production)

-------------------------------------------------------------------------------
 TROUBLESHOOTING
-------------------------------------------------------------------------------
  Redis-Fehler ('Error 111 connecting to 127.0.0.1:11000'):
      sudo -u ${FRAPPE_USER} bash -c 'cd ~/frappe-bench && bench setup socketio'
      sudo -u ${FRAPPE_USER} bash -c 'cd ~/frappe-bench && bench setup supervisor'
      sudo -u ${FRAPPE_USER} bash -c 'cd ~/frappe-bench && bench setup redis'
      sudo supervisorctl reload

  Supervisor zeigt 'no such group':
      ls -l /etc/supervisor/conf.d/   # frappe-bench.conf da?
      sudo ln -sf /home/${FRAPPE_USER}/frappe-bench/config/supervisor.conf \\
          /etc/supervisor/conf.d/frappe-bench.conf
      sudo supervisorctl reread
      sudo supervisorctl update
      sudo supervisorctl restart all

  bench-Befehl nicht gefunden in sudo:
      sudo env "PATH=/home/${FRAPPE_USER}/.local/bin:\$PATH" bench ...

===============================================================================
EOF

chmod 600 "$INFO_FILE"
ok "Zugangsdaten gespeichert in ${INFO_FILE} (chmod 600)."

# Temporäres sudoers-Snippet entfernen (trap fängt Fehlerfälle zusätzlich ab)
if [[ -f "$SUDOERS_SNIPPET" ]]; then
    rm -f "$SUDOERS_SNIPPET"
    SUDOERS_SNIPPET=""
    ok "Temporäres NOPASSWD-sudoers entfernt."
fi

# =============================================================================
# SCHRITT 9 : FERTIG
# =============================================================================
step "9/9  Fertig!"

if [[ "$SETUP_MODE" == "prod" ]]; then
    echo
    echo -e "${C_GREEN}ERPNext v16 läuft im Production-Modus.${C_RESET}"
    echo
    echo "  URL:       http://${SERVER_IP}/   (über Proxy: http://${SITE_NAME}/)"
    echo "  Admin:     Administrator"
    echo "  Passwort:  siehe ${INFO_FILE}"
    echo
    echo -e "${C_BOLD}Wichtig:${C_RESET}"
    echo "  Dein Reverse-Proxy muss den Host-Header '${SITE_NAME}' durchreichen,"
    echo "  sonst bekommst du 404. Für zusätzliche Hostnamen:"
    echo "    sudo -u ${FRAPPE_USER} bash -c 'cd ~/frappe-bench && bench --site ${SITE_NAME} add-domain <hostname>'"
    echo
    echo "  Bench-Restart nach Code-Änderungen:"
    echo "    sudo -u ${FRAPPE_USER} bash -c 'cd ~/frappe-bench && bench restart'"
    echo
else
    echo
    echo -e "${C_GREEN}ERPNext v16 ist installiert (Dev-Modus).${C_RESET}"
    echo
    echo "  Dev-Server starten:"
    echo "    su - ${FRAPPE_USER}"
    echo "    cd ~/frappe-bench"
    echo "    bench start"
    echo
    echo "  URL: http://${SERVER_IP}:8000/"
    echo
fi

echo -e "${C_YELLOW}Zugangsdaten liegen in ${INFO_FILE} (chmod 600, nur root).${C_RESET}"
echo -e "${C_YELLOW}Bitte in Passwort-Manager übertragen und Datei danach löschen:${C_RESET}"
echo -e "${C_YELLOW}  shred -u ${INFO_FILE}${C_RESET}"
echo
