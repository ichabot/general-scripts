#!/usr/bin/env bash
# =============================================================================
#  ERPNext v15 Installer für Ubuntu 24.04 LTS
# -----------------------------------------------------------------------------
#  Basiert auf:  https://discuss.frappe.io/t/install-erpnext-version-15-in-
#                ubuntu-24-04/143643
#  Mit Fixes für die bekannten Stolperfallen:
#    - Node 18 alleine reicht nicht mehr -> Node 18 + 20 via nvm, 20 default
#    - wkhtmltopdf aus Ubuntu 24.04 repo ist für Frappe kaputt
#      (patched-Qt fehlt) -> offizielles 0.12.6.1-3 .deb von GitHub
#    - MariaDB Charset-Config für utf8mb4
#
#  Features:
#    - Interaktive App-Auswahl (ERPNext + HRMS + payments + alyf-de DACH-Apps)
#    - Dev- oder Production-Modus (nginx + supervisor)
#    - Passwörter werden generiert und vorgeschlagen
#    - Zugangsdaten werden in /root/erpnext-install-info.txt gesichert
#
#  Nutzung:
#    chmod +x install-erpnext-v15.sh
#    sudo ./install-erpnext-v15.sh
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
# 24 Zeichen, URL-safe, kein /, +, =
gen_password() {
    openssl rand -base64 32 | tr -d '/+=\n' | cut -c1-24
}

# Prompt: Vorschlag zeigen, User kann übernehmen (Enter) oder eigenes eingeben
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

step "ERPNext v15 Installer - interaktive Konfiguration"

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

# ---------- App-Auswahl ----------
echo
step "Apps auswählen"
echo "Basis wird immer installiert: frappe + erpnext"
echo

declare -A APPS_URL APPS_BRANCH APPS_DESC APPS_DEFAULT
APP_ORDER=(payments hrms erpnext_germany banking erpnext_datev erpnext_druckformate eu_einvoice time_capture)

APPS_URL[payments]="payments"
APPS_BRANCH[payments]=""
APPS_DESC[payments]="Payments (Stripe/PayPal/... Integration, offiziell Frappe)"
APPS_DEFAULT[payments]="y"

APPS_URL[hrms]="hrms"
APPS_BRANCH[hrms]="version-15"
APPS_DESC[hrms]="HR & Payroll Modul (offiziell Frappe)"
APPS_DEFAULT[hrms]="y"

APPS_URL[erpnext_germany]="https://github.com/alyf-de/erpnext_germany"
APPS_BRANCH[erpnext_germany]=""
APPS_DESC[erpnext_germany]="DE-Lokalisierung (alyf.de) - Basis für banking/datev/einvoice"
APPS_DEFAULT[erpnext_germany]="y"

APPS_URL[banking]="https://github.com/alyf-de/banking"
APPS_BRANCH[banking]=""
APPS_DESC[banking]="Bank-Import / Kontoauszüge (alyf.de, braucht erpnext_germany)"
APPS_DEFAULT[banking]="n"

APPS_URL[erpnext_datev]="https://github.com/alyf-de/erpnext_datev"
APPS_BRANCH[erpnext_datev]=""
APPS_DESC[erpnext_datev]="DATEV-Export für Steuerberater (alyf.de, braucht erpnext_germany)"
APPS_DEFAULT[erpnext_datev]="n"

APPS_URL[erpnext_druckformate]="https://github.com/alyf-de/erpnext_druckformate"
APPS_BRANCH[erpnext_druckformate]=""
APPS_DESC[erpnext_druckformate]="Deutsche Druckformate (Rechnungen etc., alyf.de)"
APPS_DEFAULT[erpnext_druckformate]="y"

APPS_URL[eu_einvoice]="https://github.com/alyf-de/eu_einvoice"
APPS_BRANCH[eu_einvoice]=""
APPS_DESC[eu_einvoice]="E-Rechnung EU / XRechnung / ZUGFeRD (alyf.de)"
APPS_DEFAULT[eu_einvoice]="y"

APPS_URL[time_capture]="https://github.com/alyf-de/time_capture"
APPS_BRANCH[time_capture]=""
APPS_DESC[time_capture]="Zeiterfassung (alyf.de)"
APPS_DEFAULT[time_capture]="n"

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

# Abhängigkeits-Autoresolve
for dep_app in banking erpnext_datev eu_einvoice; do
    if [[ ${APP_SELECTED[$dep_app]} -eq 1 && ${APP_SELECTED[erpnext_germany]} -eq 0 ]]; then
        warn "${dep_app} ausgewählt -> ziehe erpnext_germany als Abhängigkeit mit rein."
        APP_SELECTED[erpnext_germany]=1
    fi
done

# ---------- Zusammenfassung ----------
echo
step "Zusammenfassung"
SELECTED_APPS_LIST="frappe, erpnext"
for k in "${APP_ORDER[@]}"; do
    [[ ${APP_SELECTED[$k]} -eq 1 ]] && SELECTED_APPS_LIST+=", ${k}"
done

cat <<EOF
  Setup-Modus     : ${SETUP_MODE}  ($([ "$SETUP_MODE" = "prod" ] && echo "nginx + supervisor" || echo "bench start"))
  developer_mode  : $([ "$DEV_MODE" = "1" ] && echo "an" || echo "aus")
  Linux-User      : ${FRAPPE_USER}
  Site            : ${SITE_NAME}
  Apps            : ${SELECTED_APPS_LIST}

  Passwörter sind gesetzt (werden nach Install in /root/erpnext-install-info.txt
  gesichert, chmod 600).
EOF
echo
read -rp "So durchziehen? [y/N]: " _go
[[ "${_go,,}" == "y" ]] || die "Abgebrochen."

# =============================================================================
# SCHRITT 1 : System-Pakete
# =============================================================================
step "1/8  System-Update und Basispakete"
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get upgrade -y

BASE_PKGS=(
    git curl wget sudo
    software-properties-common
    python3-dev python3-setuptools python3-pip python3.12-venv
    xvfb libfontconfig1 libxrender1 libjpeg-turbo8 xfonts-75dpi xfonts-base
    redis-server
    mariadb-server mariadb-client libmariadb-dev
    build-essential
    cron
)
if [[ "$SETUP_MODE" == "prod" ]]; then
    BASE_PKGS+=(nginx supervisor)
fi
apt-get install -y "${BASE_PKGS[@]}"
ok "Basispakete installiert."

# =============================================================================
# SCHRITT 2 : Frappe-User
# =============================================================================
step "2/8  Linux-User '${FRAPPE_USER}' anlegen"
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

# Temporäres NOPASSWD-sudoers während Installation - bench init ruft intern
# 'sudo supervisorctl' auf und würde sonst interaktiv nach dem Passwort fragen.
# Die Datei wird per trap am Ende des Scripts wieder entfernt.
SUDOERS_SNIPPET="/etc/sudoers.d/99-${FRAPPE_USER}-install"
echo "${FRAPPE_USER} ALL=(ALL) NOPASSWD:ALL" > "$SUDOERS_SNIPPET"
chmod 440 "$SUDOERS_SNIPPET"
visudo -cf "$SUDOERS_SNIPPET" >/dev/null || die "sudoers-Snippet ungültig."
ok "Temporäres NOPASSWD-sudoers für ${FRAPPE_USER} aktiv."

# =============================================================================
# SCHRITT 3 : MariaDB konfigurieren
# =============================================================================
step "3/8  MariaDB absichern und konfigurieren"
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
step "4/8  wkhtmltopdf 0.12.6.1-3 (patched Qt)"
if ! command -v wkhtmltopdf &>/dev/null || ! wkhtmltopdf --version 2>&1 | grep -q 'with patched qt'; then
    WKHTML_DEB="/tmp/wkhtmltox.deb"
    WKHTML_URL="https://github.com/wkhtmltopdf/packaging/releases/download/0.12.6.1-3/wkhtmltox_0.12.6.1-3.jammy_amd64.deb"
    wget -qO "$WKHTML_DEB" "$WKHTML_URL"
    apt-get install -y "$WKHTML_DEB" || apt-get install -yf
    rm -f "$WKHTML_DEB"
    ok "wkhtmltopdf installiert: $(wkhtmltopdf --version)"
else
    ok "wkhtmltopdf bereits mit patched Qt vorhanden."
fi

# =============================================================================
# SCHRITT 5 : frappe-bench CLI
# =============================================================================
step "5/8  frappe-bench CLI installieren"
if ! command -v bench &>/dev/null; then
    pip3 install frappe-bench --break-system-packages
fi
ok "bench $(bench --version)"

# =============================================================================
# SCHRITT 6 : Als frappe-User: nvm, node, bench init, site, apps
# =============================================================================
step "6/8  Frappe-Setup als User '${FRAPPE_USER}'"

FRAPPE_SCRIPT="/tmp/_frappe_setup_${FRAPPE_USER}.sh"
cat > "$FRAPPE_SCRIPT" <<FRAPPE_EOF
#!/usr/bin/env bash
set -euo pipefail

MYSQL_ROOT_PW='${MYSQL_ROOT_PW}'
SITE_NAME='${SITE_NAME}'
ADMIN_PW='${ADMIN_PW}'
DEV_MODE='${DEV_MODE}'

cd "\$HOME"

# ---------- nvm + Node 18 + 20 ----------
if [[ ! -d "\$HOME/.nvm" ]]; then
    curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash
fi
export NVM_DIR="\$HOME/.nvm"
# shellcheck disable=SC1091
source "\$NVM_DIR/nvm.sh"

nvm install 18
nvm install 20
nvm alias default 20
nvm use 20

# ---------- yarn ----------
if ! command -v yarn &>/dev/null; then
    npm install -g yarn
fi

# ---------- bench init ----------
if [[ ! -d "\$HOME/frappe-bench" ]]; then
    bench init frappe-bench \\
        --frappe-branch version-15 \\
        --python python3
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

# ---------- Apps holen ----------
get_app() {
    local name="\$1" url="\$2" branch="\$3"
    if [[ -d "apps/\${name}" ]]; then
        echo "[=] app \${name} bereits vorhanden - skip"
        return
    fi
    if [[ -n "\$branch" ]]; then
        bench get-app --branch "\$branch" "\$url"
    else
        bench get-app "\$url"
    fi
}

get_app erpnext erpnext version-15
FRAPPE_EOF

# gewählte Apps anhängen
for k in "${APP_ORDER[@]}"; do
    [[ ${APP_SELECTED[$k]} -eq 1 ]] || continue
    echo "get_app '${k}' '${APPS_URL[$k]}' '${APPS_BRANCH[$k]}'" >> "$FRAPPE_SCRIPT"
done

cat >> "$FRAPPE_SCRIPT" <<'FRAPPE_EOF'

# ---------- Apps auf Site installieren ----------
install_app() {
    local name="$1"
    if bench --site "${SITE_NAME}" list-apps 2>/dev/null | grep -qw "$name"; then
        echo "[=] ${name} bereits auf Site installiert - skip"
        return
    fi
    bench --site "${SITE_NAME}" install-app "$name"
}

install_app erpnext
FRAPPE_EOF

# Install-Reihenfolge
INSTALL_ORDER=(erpnext_germany erpnext_druckformate banking erpnext_datev eu_einvoice time_capture hrms payments)
for k in "${INSTALL_ORDER[@]}"; do
    [[ ${APP_SELECTED[$k]:-0} -eq 1 ]] || continue
    echo "install_app ${k}" >> "$FRAPPE_SCRIPT"
done

cat >> "$FRAPPE_SCRIPT" <<'FRAPPE_EOF'

# ---------- Finale Settings ----------
bench --site "${SITE_NAME}" set-maintenance-mode off
bench --site "${SITE_NAME}" enable-scheduler

if [[ "${DEV_MODE}" == "1" ]]; then
    bench set-config -g developer_mode 1
    bench --site "${SITE_NAME}" clear-cache
fi

echo "[+] Frappe-User-Setup fertig."
FRAPPE_EOF

chmod +x "$FRAPPE_SCRIPT"
chown "${FRAPPE_USER}:${FRAPPE_USER}" "$FRAPPE_SCRIPT"
sudo -H -u "$FRAPPE_USER" bash "$FRAPPE_SCRIPT"
rm -f "$FRAPPE_SCRIPT"

# =============================================================================
# SCHRITT 7 : Production-Setup (optional)
# =============================================================================
if [[ "$SETUP_MODE" == "prod" ]]; then
    step "7/8  Production-Setup (nginx + supervisor)"

    # Default-nginx-Site entfernen, sonst Port-80-Konflikt
    rm -f /etc/nginx/sites-enabled/default

    BENCH_DIR="/home/${FRAPPE_USER}/frappe-bench"
    cd "$BENCH_DIR"

    # bench setup production muss als root laufen und findet bench-dir via cwd.
    # --yes übergeht Bestätigung zum Überschreiben existierender Configs.
    bench setup production "$FRAPPE_USER" --yes

    # Services neu laden
    systemctl enable --now supervisor
    systemctl restart supervisor
    systemctl enable --now nginx
    systemctl restart nginx

    ok "Production-Stack läuft."
else
    step "7/8  Production-Setup übersprungen (Dev-Mode)"
fi

# =============================================================================
# SCHRITT 8 : Info-Datei schreiben
# =============================================================================
step "8/8  Zugangsdaten sichern"

INFO_FILE="/root/erpnext-install-info.txt"
SERVER_IP="$(hostname -I | awk '{print $1}')"
INSTALL_DATE="$(date '+%Y-%m-%d %H:%M:%S')"

INFO_APPS="frappe, erpnext"
for k in "${APP_ORDER[@]}"; do
    [[ ${APP_SELECTED[$k]} -eq 1 ]] && INFO_APPS+=", ${k}"
done

cat > "$INFO_FILE" <<EOF
===============================================================================
  ERPNext v15 - Installationsdaten
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
  Frappe-Version   : version-15
  Installierte Apps: ${INFO_APPS}

-------------------------------------------------------------------------------
 LINUX
-------------------------------------------------------------------------------
  User             : ${FRAPPE_USER}
  Passwort         : ${FRAPPE_PW}
  Home             : /home/${FRAPPE_USER}
  Bench-Verzeichnis: /home/${FRAPPE_USER}/frappe-bench

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

  Supervisor-Config: /etc/supervisor/conf.d/${FRAPPE_USER}-frappe-bench.conf
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
 NÄCHSTE SCHRITTE
-------------------------------------------------------------------------------
  * Custom-App für eigene Anpassungen anlegen:
      su - ${FRAPPE_USER}
      cd ~/frappe-bench
      bench new-app meine_app    # Name frei wählbar
      bench --site ${SITE_NAME} install-app meine_app

    Die App liegt unter apps/meine_app/ und ist ein eigenes Git-Repo.
    Custom Fields, Scripts, Print Formats etc. über 'fixtures' in der App
    bündeln, damit der Deploy auf Prod über git pull + bench migrate reicht.

  * App nachträglich hinzufügen:
      bench get-app <git-url>
      bench --site ${SITE_NAME} install-app <app-name>

  * App entfernen:
      bench --site ${SITE_NAME} uninstall-app <app-name> --no-backup --force

  * Backup:
      bench --site ${SITE_NAME} backup --with-files

  * Updates (Core + offizielle Apps):
      bench update                       # alles
      bench update --apps erpnext        # nur eine App

  * Logs:
      /home/${FRAPPE_USER}/frappe-bench/logs/
      /var/log/mysql/
      /var/log/nginx/  (nur Production)
      /var/log/supervisor/  (nur Production)

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
# FERTIG
# =============================================================================
step "Fertig!"

if [[ "$SETUP_MODE" == "prod" ]]; then
    cat <<EOF

${C_GREEN}ERPNext v15 läuft im Production-Modus.${C_RESET}

  URL:       http://${SERVER_IP}/   (über Proxy: http://${SITE_NAME}/)
  Admin:     Administrator
  Passwort:  siehe ${INFO_FILE}

${C_BOLD}Wichtig:${C_RESET}
  Dein Reverse-Proxy muss den Host-Header '${SITE_NAME}' durchreichen,
  sonst bekommst du 404. Für zusätzliche Hostnamen:
    sudo -u ${FRAPPE_USER} bash -c 'cd ~/frappe-bench && bench --site ${SITE_NAME} add-domain <hostname>'

  Bench-Restart nach Code-Änderungen:
    sudo -u ${FRAPPE_USER} bash -c 'cd ~/frappe-bench && bench restart'

EOF
else
    cat <<EOF

${C_GREEN}ERPNext v15 ist installiert (Dev-Modus).${C_RESET}

  Dev-Server starten:
    su - ${FRAPPE_USER}
    cd ~/frappe-bench
    bench start

  URL: http://${SERVER_IP}:8000/

EOF
fi

cat <<EOF
${C_YELLOW}Zugangsdaten liegen in ${INFO_FILE} (chmod 600, nur root).
Bitte in Passwort-Manager übertragen und Datei danach löschen:
  shred -u ${INFO_FILE}${C_RESET}

EOF
