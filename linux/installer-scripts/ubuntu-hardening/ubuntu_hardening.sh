#!/bin/bash
# =============================================================================
# Ubuntu Server Hardening Script
# MSP Setup - Patrick
# Version 1.3 - LXC/VM/Cloud kompatibel (Proxmox, Hetzner, etc.)
# =============================================================================
# Getestet auf: Ubuntu 22.04 / 24.04 LTS (Proxmox VM/LXC, Hetzner Cloud)
# Ausfuehren als root: sudo bash ubuntu_hardening.sh
# Dry-Run Modus:       sudo bash ubuntu_hardening.sh --check
# =============================================================================

set -euo pipefail

# --- Farben ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

log()     { echo -e "${GREEN}[OK]${NC} $1"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
skip()    { echo -e "${CYAN}[SKIP]${NC} $1"; }
error()   { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }
section() { echo -e "\n${BLUE}========================================${NC}"; echo -e "${BLUE} $1${NC}"; echo -e "${BLUE}========================================${NC}"; }

# --- Root-Check ---
if [[ $EUID -ne 0 ]]; then
   error "Bitte als root ausfuehren: sudo bash $0"
fi

# =============================================================================
# LOGGING - Alles in Datei und Terminal ausgeben
# =============================================================================
LOG_FILE="/var/log/hardening_$(date +%Y%m%d_%H%M%S).log"
exec > >(tee -a "$LOG_FILE") 2>&1
info "Log-Datei: $LOG_FILE"

# =============================================================================
# DRY-RUN MODUS
# =============================================================================
DRY_RUN=false
if [[ "${1:-}" == "--check" || "${1:-}" == "--dry-run" ]]; then
    DRY_RUN=true
    echo -e "${YELLOW}${BOLD}"
    echo "============================================================"
    echo "  DRY-RUN MODUS - Es werden KEINE Aenderungen vorgenommen!"
    echo "  Das Script zeigt nur was es tun WUERDE."
    echo "============================================================"
    echo -e "${NC}"
fi

# =============================================================================
# UMGEBUNGSERKENNUNG - LXC, Cloud-VM oder Proxmox-VM/Bare Metal
# =============================================================================
section "Umgebungserkennung"

IS_LXC=false
IS_CLOUD_VM=false

# --- LXC Erkennung ---
# Methode 1: /proc/1/environ auslesen
if grep -qa 'container=lxc' /proc/1/environ 2>/dev/null; then
    IS_LXC=true
fi

# Methode 2: systemd-detect-virt
if ! $IS_LXC && command -v systemd-detect-virt &>/dev/null; then
    VIRT_TYPE=$(systemd-detect-virt 2>/dev/null || true)
    if [[ "$VIRT_TYPE" == "lxc" || "$VIRT_TYPE" == "lxc-libvirt" ]]; then
        IS_LXC=true
    fi
fi

# Methode 3: /proc/self/cgroup (Fallback)
if ! $IS_LXC && grep -qa 'lxc' /proc/self/cgroup 2>/dev/null; then
    IS_LXC=true
fi

# --- Cloud-VM Erkennung (Hetzner, AWS, GCP, Azure, etc.) ---
# Wichtig: Proxmox VMs koennen auch cloud-init haben (fuer IP/User-Konfiguration).
# Deshalb pruefen wir zuerst ob es eine Proxmox/QEMU VM ist und schliessen diese aus.
IS_PROXMOX_VM=false
if ! $IS_LXC; then
    # Proxmox-VM Erkennung: QEMU product_name oder Proxmox-spezifische Merkmale
    if [[ -f /sys/class/dmi/id/product_name ]]; then
        PRODUCT_NAME=$(cat /sys/class/dmi/id/product_name 2>/dev/null || true)
        case "$PRODUCT_NAME" in
            *"QEMU"*|*"Standard PC"*|*"KVM"*) IS_PROXMOX_VM=true ;;
        esac
    fi
    # Zusaetzlich: systemd-detect-virt meldet "kvm" fuer QEMU/Proxmox
    if ! $IS_PROXMOX_VM && command -v systemd-detect-virt &>/dev/null; then
        VIRT_TYPE=$(systemd-detect-virt 2>/dev/null || true)
        if [[ "$VIRT_TYPE" == "kvm" ]] && [[ -f /sys/class/dmi/id/sys_vendor ]]; then
            SYS_VENDOR=$(cat /sys/class/dmi/id/sys_vendor 2>/dev/null || true)
            case "$SYS_VENDOR" in
                *"QEMU"*|*"Proxmox"*) IS_PROXMOX_VM=true ;;
            esac
        fi
    fi

    # Cloud-VM nur wenn es KEINE Proxmox-VM ist
    if ! $IS_PROXMOX_VM; then
        # Hetzner Cloud: DMI product_name oder Hetzner-spezifische Dateien
        if [[ -f /sys/class/dmi/id/product_name ]]; then
            PRODUCT_NAME=$(cat /sys/class/dmi/id/product_name 2>/dev/null || true)
            case "$PRODUCT_NAME" in
                *"Hetzner"*|*"hc-host"*) IS_CLOUD_VM=true ;;
            esac
        fi
        # cloud-init marker (Hetzner, AWS, GCP, etc.)
        # Nur wenn kein Proxmox — Proxmox nutzt cloud-init fuer VM-Templates
        if [[ -f /etc/cloud/cloud.cfg ]] && ! $IS_CLOUD_VM; then
            IS_CLOUD_VM=true
        fi
    fi
fi

if $IS_LXC; then
    echo -e "${CYAN}Umgebung erkannt: LXC Container${NC}"
    echo -e "${CYAN}  -> sysctl Kernel-Hardening wird uebersprungen${NC}"
    echo -e "${CYAN}  -> auditd wird uebersprungen (kein Kernel-Zugriff)${NC}"
    echo -e "${CYAN}  -> QEMU Guest Agent wird uebersprungen (nur fuer VMs)${NC}"
elif $IS_CLOUD_VM; then
    echo -e "${GREEN}Umgebung erkannt: Cloud VM (z.B. Hetzner)${NC}"
    echo -e "${GREEN}  -> QEMU Guest Agent wird uebersprungen (Cloud-Hypervisor)${NC}"
    echo -e "${GREEN}  -> Alle anderen Sektionen werden ausgefuehrt${NC}"
elif $IS_PROXMOX_VM; then
    echo -e "${GREEN}Umgebung erkannt: Proxmox / QEMU VM${NC}"
    echo -e "${GREEN}  -> Alle Sektionen werden ausgefuehrt (inkl. QEMU Guest Agent)${NC}"
else
    echo -e "${GREEN}Umgebung erkannt: VM / Bare Metal${NC}"
    echo -e "${GREEN}  -> Alle Sektionen werden ausgefuehrt${NC}"
fi

# =============================================================================
# KONFIGURATION - Hier anpassen
# =============================================================================

TIMEZONE="Europe/Berlin"
LOCALE="de_DE.UTF-8"
SSH_PORT=22                          # SSH Port aendern wenn gewuenscht z.B. 2222
SSH_ALLOW_USERS=""                   # Leer = alle User erlaubt, z.B. "sysadmin admin"
                                     # ACHTUNG: Nur setzen wenn der User existiert!
                                     # Auf Hetzner-VMs ist nur "root" vorhanden!
SWAPPINESS=10                        # Standard Ubuntu = 60, fuer Server besser 10
SWAP_SIZE="2G"                       # Swap Groesse | 0 = kein Swap
                                     # 4GB  RAM  -> "4G"  (gleich wie RAM)
                                     # 8GB  RAM  -> "4G"  (Haelfte des RAM reicht)
                                     # 16GB RAM  -> "4G"  (fixer Wert genuegt)
                                     # 32GB RAM  -> "4G"  (mehr als 4G selten sinnvoll)
                                     # In LXC: Swap wird vom Host verwaltet -> wird ignoriert

# IPv6 Konfiguration
DISABLE_IPV6=true                    # true  = IPv6 komplett deaktivieren (sysctl)
                                     # false = IPv6 aktiv lassen, nur haerten
                                     # Hinweis: Hetzner/Cloud-Provider vergeben IPv6 -
                                     # bei false bleibt IPv6 nutzbar, wird aber per
                                     # sysctl gehaertet (keine Redirects, kein Source Routing)

# Automatischer Reboot nach Kernel-Security-Updates
AUTO_REBOOT=false                    # true  = automatisch um AUTO_REBOOT_TIME rebooten
                                     # false = kein automatischer Reboot (manuell noetig)
AUTO_REBOOT_TIME="03:30"            # Uhrzeit fuer automatischen Reboot (nur wenn AUTO_REBOOT=true)

# Zusaetzliche UFW Ports (optional) - Format: "PORT/PROTOKOLL:BESCHREIBUNG"
# Leer lassen wenn nicht benoetigt
EXTRA_PORTS=(
     "80/tcp:HTTP"
     "443/tcp:HTTPS"
    # "8080/tcp:HTTP-Alt"
    # "3306/tcp:MySQL"
    # "5432/tcp:PostgreSQL"
)

# =============================================================================
# 1. SYSTEM UPDATE
# =============================================================================
section "1. System Update"

if $DRY_RUN; then
    info "[DRY-RUN] apt-get update && apt-get upgrade"
else
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq && apt-get upgrade -y -qq
    log "System aktualisiert"
fi

# =============================================================================
# 2. ZEITZONE & LOCALE
# =============================================================================
section "2. Zeitzone & Locale"

if $DRY_RUN; then
    info "[DRY-RUN] Zeitzone: $TIMEZONE | Locale: $LOCALE"
else
    timedatectl set-timezone "$TIMEZONE"
    log "Zeitzone gesetzt: $TIMEZONE"

    apt-get install -y -qq locales
    locale-gen "$LOCALE"
    update-locale LANG="$LOCALE" LC_ALL="$LOCALE"
    log "Locale gesetzt: $LOCALE"
fi

# =============================================================================
# 3. CHRONY (NTP)
# =============================================================================
section "3. Chrony NTP einrichten"

if $DRY_RUN; then
    info "[DRY-RUN] Chrony NTP installieren (de.pool.ntp.org, europe.pool.ntp.org)"
else
    # systemd-timesyncd deaktivieren
    systemctl disable systemd-timesyncd --now 2>/dev/null || true

    apt-get install -y -qq chrony

    cat > /etc/chrony/chrony.conf << EOF
# MSP Hardening - Chrony Konfiguration
# Generiert: $(date)

# EU/DE NTP Pool
pool de.pool.ntp.org iburst maxsources 4
pool europe.pool.ntp.org iburst maxsources 2

# Fallback
pool ntp.ubuntu.com iburst maxsources 2

# Drift Datei
driftfile /var/lib/chrony/drift

# Makestep: wenn Abweichung > 1s beim Start korrigieren
makestep 1.0 3

# RTC sync (nur in VMs/Bare Metal sinnvoll, in LXC ignoriert)
rtcsync

# Nur lokale Clients erlauben (auskommentieren wenn nicht benoetigt)
# allow 192.168.0.0/16

# Logging
logdir /var/log/chrony
EOF

    systemctl enable chrony --now
    log "Chrony installiert und konfiguriert"

    sleep 2
    if chronyc tracking &>/dev/null; then
        log "Chrony laeuft und synchronisiert"
    else
        warn "Chrony laeuft, aber Synchronisation noch ausstehend (normal beim ersten Start)"
    fi
fi

# =============================================================================
# 4. SWAP
# =============================================================================
section "4. Swap einrichten"

if $DRY_RUN; then
    if $IS_LXC; then
        info "[DRY-RUN] LXC: Swap wird uebersprungen"
    else
        info "[DRY-RUN] Swappiness=$SWAPPINESS, Swap-Datei=$SWAP_SIZE"
    fi
    SWAP_INFO="DRY-RUN"
elif $IS_LXC; then
    skip "LXC: Swappiness wird vom Proxmox-Host verwaltet - wird uebersprungen"
    skip "LXC: Swap-Einrichtung wird uebersprungen (Host zustaendig)"
    SWAP_INFO="LXC - vom Proxmox-Host verwaltet"
else
    echo "vm.swappiness=$SWAPPINESS" > /etc/sysctl.d/99-swappiness.conf
    sysctl -p /etc/sysctl.d/99-swappiness.conf -q
    log "Swappiness gesetzt: $SWAPPINESS"

    EXISTING_SWAP=$(swapon --show=SIZE --noheadings 2>/dev/null | head -1 | tr -d ' ')

    if [[ -n "$EXISTING_SWAP" ]]; then
        SWAP_TOTAL=$(free -h | awk '/^Swap:/ {print $2}')
        log "Swap bereits vorhanden: $SWAP_TOTAL - wird nicht veraendert"
        SWAP_INFO="Vorhanden: $SWAP_TOTAL"
    elif [[ "$SWAP_SIZE" == "0" ]]; then
        info "Kein Swap gewuenscht (SWAP_SIZE=0)"
        SWAP_INFO="Nicht eingerichtet"
    else
        # fallocate mit dd-Fallback (fuer btrfs/ZFS Kompatibilitaet)
        fallocate -l "$SWAP_SIZE" /swapfile 2>/dev/null \
            || dd if=/dev/zero of=/swapfile bs=1M count=$((${SWAP_SIZE%G} * 1024)) status=none
        chmod 600 /swapfile
        mkswap /swapfile -q
        swapon /swapfile
        # Nur eintragen wenn noch nicht in fstab (Idempotenz bei Re-Run)
        grep -q '/swapfile' /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab
        log "Swapfile neu angelegt: $SWAP_SIZE"
        SWAP_INFO="Neu angelegt: $SWAP_SIZE"
    fi
fi

# =============================================================================
# 5. SSH HARDENING
# =============================================================================
section "5. SSH Hardening"

if $DRY_RUN; then
    info "[DRY-RUN] SSH Hardening: Port=$SSH_PORT, PermitRootLogin=no, MaxAuthTries=3, LoginGraceTime=60"
    if [[ -n "$SSH_ALLOW_USERS" ]]; then
        info "[DRY-RUN] AllowUsers: $SSH_ALLOW_USERS"
    fi
else
    cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak.$(date +%Y%m%d)
    log "SSH Konfig Backup erstellt"

    cat > /etc/ssh/sshd_config.d/99-hardening.conf << EOF
# MSP SSH Hardening
# Generiert: $(date)

# Port
Port $SSH_PORT

# Root Login deaktivieren
PermitRootLogin no

# Nur Key-Authentifizierung (Passwort deaktivieren nach Key-Setup!)
# ACHTUNG: Erst aktivieren wenn SSH-Key hinterlegt ist!
# PasswordAuthentication no
# PubkeyAuthentication yes

# Leere Passwoerter verbieten
PermitEmptyPasswords no

# X11 Forwarding deaktivieren
X11Forwarding no

# Maximale Login-Versuche
MaxAuthTries 3

# Idle Timeout: 15 Minuten
ClientAliveInterval 300
ClientAliveCountMax 3

# Login Grace Time (60s fuer langsame Verbindungen / 2FA)
LoginGraceTime 60

# TCP Forwarding einschraenken
AllowTcpForwarding no
AllowAgentForwarding no

# SFTP erlauben
Subsystem sftp /usr/lib/openssh/sftp-server

# Banner
Banner /etc/ssh/banner
EOF

    cat > /etc/ssh/banner << 'EOF'
***************************************************************************
                    AUTHORIZED ACCESS ONLY
    Unauthorized access to this system is prohibited and will be
    prosecuted to the fullest extent of the law.
    All activities on this system are monitored and recorded.
***************************************************************************
EOF

    # SSH_ALLOW_USERS: Nur setzen wenn konfiguriert UND alle User existieren
    if [[ -n "$SSH_ALLOW_USERS" ]]; then
        ALL_USERS_EXIST=true
        for username in $SSH_ALLOW_USERS; do
            if ! id "$username" &>/dev/null; then
                warn "SSH AllowUsers: User '$username' existiert nicht auf diesem System!"
                ALL_USERS_EXIST=false
            fi
        done

        if $ALL_USERS_EXIST; then
            echo "AllowUsers $SSH_ALLOW_USERS" >> /etc/ssh/sshd_config.d/99-hardening.conf
            log "SSH User-Einschraenkung gesetzt: $SSH_ALLOW_USERS"
        else
            warn "SSH AllowUsers wird NICHT gesetzt - fehlende User wuerden Zugang blockieren!"
            warn "Erst User anlegen, dann manuell in /etc/ssh/sshd_config.d/99-hardening.conf eintragen."
        fi
    fi

    # PermitRootLogin: Auf Cloud-VMs wo nur root existiert, nicht sofort deaktivieren
    if $IS_CLOUD_VM; then
        NON_ROOT_USERS=$(awk -F: '$3 >= 1000 && $1 != "nobody" {print $1}' /etc/passwd)
        if [[ -z "$NON_ROOT_USERS" ]]; then
            # Kein normaler User vorhanden -> Root-Login erlaubt lassen (nur mit Key)
            sed -i 's/^PermitRootLogin no$/PermitRootLogin prohibit-password/' \
                /etc/ssh/sshd_config.d/99-hardening.conf
            warn "Cloud-VM: Kein regulaerer User vorhanden!"
            warn "Root-Login bleibt erlaubt (nur Key-Auth, kein Passwort)."
            warn "Empfehlung: User anlegen, dann 'PermitRootLogin no' setzen."
        fi
    fi

    systemctl restart ssh
    log "SSH gehaertet (Port: $SSH_PORT)"
    warn "Passwort-Auth noch aktiv - erst deaktivieren wenn SSH-Key hinterlegt!"
fi

# =============================================================================
# 6. FAIL2BAN
# =============================================================================
section "6. Fail2Ban einrichten"

if $DRY_RUN; then
    info "[DRY-RUN] Fail2Ban installieren (SSH maxretry=3, bantime=86400)"
else
    apt-get install -y -qq fail2ban

    # Pruefen ob sshd-ddos Filter existiert (nicht in allen Versionen vorhanden)
    SSHD_DDOS_BLOCK=""
    if [[ -f /etc/fail2ban/filter.d/sshd-ddos.conf ]]; then
        SSHD_DDOS_BLOCK="
[sshd-ddos]
enabled  = true
port     = $SSH_PORT
filter   = sshd-ddos
maxretry = 10
bantime  = 3600"
        log "sshd-ddos Filter gefunden - wird aktiviert"
    else
        info "sshd-ddos Filter nicht vorhanden (normal bei neueren Versionen) - wird uebersprungen"
    fi

    cat > /etc/fail2ban/jail.local << EOF
[DEFAULT]
# Basis-Einstellungen
bantime  = 3600
findtime = 600
maxretry = 5
backend  = systemd

# Whitelist (eigene IPs eintragen)
# ignoreip = 127.0.0.1/8 192.168.1.0/24

[sshd]
enabled  = true
port     = $SSH_PORT
filter   = sshd
maxretry = 3
bantime  = 86400
${SSHD_DDOS_BLOCK}
EOF

    systemctl enable fail2ban --now
    systemctl restart fail2ban
    log "Fail2Ban installiert und konfiguriert"
fi

# =============================================================================
# 7. UFW FIREWALL
# =============================================================================
section "7. UFW Basis-Firewall"

if $DRY_RUN; then
    info "[DRY-RUN] UFW: deny incoming, allow outgoing, allow SSH $SSH_PORT/tcp"
    for entry in "${EXTRA_PORTS[@]}"; do
        PORT=$(echo "$entry" | cut -d: -f1)
        DESC=$(echo "$entry" | cut -d: -f2)
        info "[DRY-RUN] UFW allow $PORT ($DESC)"
    done
else
    apt-get install -y -qq ufw

    ufw default deny incoming
    ufw default allow outgoing

    # Nur hinzufuegen wenn Regel noch nicht existiert (Idempotenz bei Re-Run)
    ufw status | grep -q "$SSH_PORT/tcp.*ALLOW" || ufw allow "$SSH_PORT"/tcp comment "SSH"

    if [[ ${#EXTRA_PORTS[@]} -gt 0 ]]; then
        for entry in "${EXTRA_PORTS[@]}"; do
            PORT=$(echo "$entry" | cut -d: -f1)
            DESC=$(echo "$entry" | cut -d: -f2)
            if ufw status | grep -q "${PORT}.*ALLOW"; then
                skip "UFW Regel existiert bereits: $PORT ($DESC)"
            else
                ufw allow "$PORT" comment "$DESC"
                log "UFW Port freigegeben: $PORT ($DESC)"
            fi
        done
    fi

    # UFW aktivieren oder neu laden (Idempotenz bei Re-Run)
    if ufw status | grep -q "Status: active"; then
        ufw reload >/dev/null
        log "UFW neu geladen"
    else
        echo "y" | ufw enable
    fi
    log "UFW aktiviert - SSH Port $SSH_PORT eingehend erlaubt"
fi

# =============================================================================
# 8. UNATTENDED UPGRADES
# =============================================================================
section "8. Automatische Sicherheitsupdates"

if $DRY_RUN; then
    info "[DRY-RUN] Unattended-Upgrades installieren (Security-Updates, Auto-Reboot=$AUTO_REBOOT)"
else
    apt-get install -y -qq unattended-upgrades apt-listchanges

    # AUTO_REBOOT Variable fuer apt-Konfiguration aufbereiten
    if [[ "$AUTO_REBOOT" == "true" ]]; then
        APT_AUTO_REBOOT="true"
    else
        APT_AUTO_REBOOT="false"
    fi

    cat > /etc/apt/apt.conf.d/50unattended-upgrades << EOF
Unattended-Upgrade::Allowed-Origins {
    "\${distro_id}:\${distro_codename}";
    "\${distro_id}:\${distro_codename}-security";
    "\${distro_id}ESMApps:\${distro_codename}-apps-security";
    "\${distro_id}ESM:\${distro_codename}-infra-security";
};

Unattended-Upgrade::Package-Blacklist {
};

// Automatischer Reboot bei Kernel-Updates
Unattended-Upgrade::Automatic-Reboot "${APT_AUTO_REBOOT}";
Unattended-Upgrade::Automatic-Reboot-Time "${AUTO_REBOOT_TIME}";

// Logging
Unattended-Upgrade::SyslogEnable "true";
EOF

    cat > /etc/apt/apt.conf.d/20auto-upgrades << 'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Download-Upgradeable-Packages "1";
APT::Periodic::AutocleanInterval "7";
APT::Periodic::Unattended-Upgrade "1";
EOF

    systemctl enable unattended-upgrades --now
    log "Automatische Sicherheitsupdates aktiviert"
    if [[ "$AUTO_REBOOT" == "true" ]]; then
        log "Automatischer Reboot aktiviert um $AUTO_REBOOT_TIME bei Kernel-Updates"
    else
        info "Automatischer Reboot deaktiviert - Kernel-Updates erfordern manuellen Reboot"
    fi
fi

# =============================================================================
# 9. KERNEL / SYSCTL HARDENING
# =============================================================================
section "9. Kernel / Sysctl Hardening"

if $DRY_RUN; then
    info "[DRY-RUN] Sysctl Hardening (SYN-Flood, Spoofing, ICMP)"
    if $DISABLE_IPV6; then
        info "[DRY-RUN] IPv6 wird deaktiviert"
    else
        info "[DRY-RUN] IPv6 bleibt aktiv (nur Hardening)"
    fi
elif $IS_LXC; then
    skip "LXC: Kernel-Parameter werden vom Proxmox-Host verwaltet"
    skip "LXC: sysctl Hardening wird uebersprungen (kein Schreibzugriff auf Kernel-Parameter)"
    info "Tipp: sysctl-Haertung auf dem Proxmox-Host in /etc/sysctl.d/ konfigurieren"
else
    cat > /etc/sysctl.d/99-hardening.conf << 'EOF'
# MSP Server Hardening - Sysctl
# Generiert automatisch

# IP Spoofing Schutz
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1

# ICMP Redirects ignorieren
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0

# Source Routing deaktivieren
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0

# SYN Flood Schutz
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_max_syn_backlog = 2048
net.ipv4.tcp_synack_retries = 2

# ICMP Broadcast ignorieren
net.ipv4.icmp_echo_ignore_broadcasts = 1

# Bogus ICMP Fehler ignorieren
net.ipv4.icmp_ignore_bogus_error_responses = 1

# Swappiness
vm.swappiness = 10
EOF

    sysctl -p /etc/sysctl.d/99-hardening.conf -q

    # IPv6: deaktivieren oder haerten (je nach Konfiguration)
    if $DISABLE_IPV6; then
        cat > /etc/sysctl.d/99-ipv6.conf << 'EOF'
# IPv6 komplett deaktiviert
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
EOF
        sysctl -p /etc/sysctl.d/99-ipv6.conf -q
        log "IPv6 deaktiviert"
    else
        cat > /etc/sysctl.d/99-ipv6.conf << 'EOF'
# IPv6 Hardening (IPv6 bleibt aktiv)
net.ipv6.conf.all.accept_redirects = 0
net.ipv6.conf.default.accept_redirects = 0
net.ipv6.conf.all.accept_source_route = 0
net.ipv6.conf.default.accept_source_route = 0
net.ipv6.conf.all.accept_ra = 0
net.ipv6.conf.default.accept_ra = 0
EOF
        sysctl -p /etc/sysctl.d/99-ipv6.conf -q
        log "IPv6 gehaertet (bleibt aktiv)"
    fi

    log "Kernel-Parameter gehaertet"
fi

# =============================================================================
# 10. LOGROTATE KONFIGURIEREN
# =============================================================================
section "10. Logrotate"

if $DRY_RUN; then
    info "[DRY-RUN] Logrotate konfigurieren (14 Tage Daily)"
else
    apt-get install -y -qq logrotate

    cat > /etc/logrotate.d/msp-server << 'EOF'
# MSP Server - Logrotate Konfiguration
/var/log/syslog
/var/log/auth.log
/var/log/kern.log
/var/log/dpkg.log
/var/log/fail2ban.log
{
    daily
    rotate 14
    compress
    delaycompress
    missingok
    notifempty
    sharedscripts
}

/var/log/chrony/*.log
{
    weekly
    rotate 4
    compress
    delaycompress
    missingok
    notifempty
}
EOF

    systemctl enable logrotate.timer --now 2>/dev/null || true
    log "Logrotate konfiguriert (14 Tage Daily, komprimiert)"
fi

# =============================================================================
# 11. NUTZLOSE DIENSTE DEAKTIVIEREN
# =============================================================================
section "11. Unnoetige Dienste deaktivieren"

if $DRY_RUN; then
    info "[DRY-RUN] Deaktiviere: bluetooth, cups, avahi-daemon (falls vorhanden)"
else
    SERVICES_TO_DISABLE=(
        "bluetooth"
        "cups"
        "avahi-daemon"
    )

    DISABLED_COUNT=0
    for service in "${SERVICES_TO_DISABLE[@]}"; do
        if systemctl list-unit-files "${service}.service" 2>/dev/null | grep -q "$service"; then
            systemctl disable "$service" --now 2>/dev/null || true
            log "Deaktiviert: $service"
            ((DISABLED_COUNT++)) || true
        else
            skip "$service nicht installiert"
        fi
    done

    if [[ $DISABLED_COUNT -eq 0 ]]; then
        info "Keine unnoetigten Dienste gefunden (minimales Image)"
    fi
fi

# =============================================================================
# 12. BASIS-TOOLS
# =============================================================================
section "12. Basis-Tools installieren"

if $DRY_RUN; then
    info "[DRY-RUN] Installiere: curl, wget, bpytop, tmux"
else
    apt-get install -y -qq curl wget bpytop tmux
    log "Tools installiert: curl, wget, bpytop, tmux"
fi

# =============================================================================
# 13. AUDITD (Wazuh Backend)
# =============================================================================
section "13. Auditd installieren (Wazuh Backend)"

if $DRY_RUN; then
    if $IS_LXC; then
        info "[DRY-RUN] LXC: auditd wird uebersprungen"
    else
        info "[DRY-RUN] Auditd installieren"
    fi
elif $IS_LXC; then
    skip "LXC: auditd benoetigt direkten Kernel-Zugriff - wird uebersprungen"
    skip "LXC: Wazuh-Agent kann im LXC ohne auditd betrieben werden (syslog-Modus)"
    info "Tipp: Wazuh im 'no-audit' Modus konfigurieren fuer LXC"
else
    apt-get install -y -qq auditd audispd-plugins
    systemctl enable auditd --now
    log "Auditd installiert und aktiv (Konfiguration uebernimmt Wazuh-Agent)"
fi

# =============================================================================
# 14. QEMU GUEST AGENT (Proxmox) - nur fuer Proxmox-VMs
# =============================================================================
section "14. QEMU Guest Agent"

if $DRY_RUN; then
    if $IS_LXC; then
        info "[DRY-RUN] LXC: QEMU Guest Agent wird uebersprungen"
    elif $IS_CLOUD_VM; then
        info "[DRY-RUN] Cloud-VM: QEMU Guest Agent wird uebersprungen"
    else
        info "[DRY-RUN] QEMU Guest Agent installieren"
    fi
elif $IS_LXC; then
    skip "LXC: QEMU Guest Agent ist nur fuer VMs relevant - wird uebersprungen"
    info "LXC Container kommunizieren direkt ueber den Proxmox-Host-Kernel"
elif $IS_CLOUD_VM; then
    skip "Cloud-VM: QEMU Guest Agent wird vom Cloud-Anbieter verwaltet"
    info "Hetzner/AWS/GCP stellen den Guest Agent bereits bereit"
else
    apt-get install -y -qq qemu-guest-agent
    systemctl enable qemu-guest-agent --now 2>/dev/null || true
    # qemu-guest-agent hat kein WantedBy= in der Unit, daher ist die
    # "not meant to be enabled" Warnung von systemctl normal und harmlos.
    # Der Agent wird trotzdem durch udev/socket-Activation gestartet.
    log "QEMU Guest Agent installiert - Proxmox Snapshot/Shutdown funktioniert korrekt"
fi

# =============================================================================
# 15. BASH HISTORY MIT TIMESTAMPS
# =============================================================================
section "15. Bash History Hardening"

if $DRY_RUN; then
    info "[DRY-RUN] Bash History Timestamps + tmux Auto-Attach konfigurieren"
else
    # Pruefen ob bereits konfiguriert (bei erneutem Lauf nicht doppelt einfuegen)
    if ! grep -q "MSP Hardening - Bash History" /etc/bash.bashrc 2>/dev/null; then
        cat >> /etc/bash.bashrc << 'EOF'

# MSP Hardening - Bash History
HISTTIMEFORMAT="%d/%m/%y %T "
HISTSIZE=10000
HISTFILESIZE=20000
HISTCONTROL=ignoredups
# History sofort schreiben (nicht nur beim Logout)
PROMPT_COMMAND="history -a; $PROMPT_COMMAND"
export HISTTIMEFORMAT HISTSIZE HISTFILESIZE HISTCONTROL PROMPT_COMMAND

# MSP Hardening - tmux Auto-Attach
# Automatisch tmux Session starten oder reconnecten beim Login
# Verhindert Session-Verlust beim Schliessen des Konsolenfensters
# Umgehen mit: TMUX=skip bash
if command -v tmux &>/dev/null && [ -z "$TMUX" ]; then
    tmux attach -t main 2>/dev/null || tmux new -s main
fi
EOF
        log "Bash History konfiguriert (Timestamps, 10000 Eintraege)"
        log "tmux Auto-Attach konfiguriert (Session: 'main')"
    else
        skip "Bash History bereits konfiguriert (uebersprungen)"
    fi
fi
warn "tmux wird beim naechsten Login automatisch gestartet - Umgehen mit: TMUX=skip bash"

# =============================================================================
# 16. MOTD (Login Info)
# =============================================================================
section "16. MOTD einrichten"

if $DRY_RUN; then
    info "[DRY-RUN] MOTD mit Systeminfo konfigurieren"
else
    apt-get install -y -qq landscape-common 2>/dev/null || true

    cat > /etc/update-motd.d/99-msp-info << 'MOTD'
#!/bin/bash
echo ""
echo "=============================================="
echo "  Hostname:  $(hostname)"
echo "  OS:        $(lsb_release -ds 2>/dev/null || cat /etc/os-release 2>/dev/null | grep PRETTY_NAME | cut -d= -f2 | tr -d '\"')"
echo "  Kernel:    $(uname -r)"
echo "  Uptime:    $(uptime -p)"
echo "  Datum:     $(date)"
echo "----------------------------------------------"
echo "  CPU Load:  $(cut -d' ' -f1-3 /proc/loadavg)"
echo "  RAM:       $(free -h | awk '/^Mem:/ {print $3 " / " $2}')"
echo "  Disk /:    $(df -h / | awk 'NR==2 {print $3 " / " $2 " (" $5 " belegt)"}')"
echo "  IP:        $(hostname -I | awk '{print $1}')"
echo "----------------------------------------------"
UPDATES=$(apt-get -s upgrade 2>/dev/null | grep ^Inst | wc -l)
echo "  Updates:   $UPDATES verfuegbar"
FAIL2BAN=$(fail2ban-client status sshd 2>/dev/null | grep 'Currently banned' | awk '{print $NF}' || echo "n/a")
echo "  F2B Bans:  $FAIL2BAN (SSH)"
TMUX_SESSIONS=$(tmux list-sessions 2>/dev/null | wc -l || echo "0")
echo "  tmux:      $TMUX_SESSIONS Session(s) aktiv"
echo "=============================================="
echo ""
MOTD

    chmod +x /etc/update-motd.d/99-msp-info
    log "MOTD konfiguriert (Systeminfo beim Login)"
fi

# =============================================================================
# ZUSAMMENFASSUNG
# =============================================================================
section "Zusammenfassung"

# Umgebungs-Label fuer Zusammenfassung
if $IS_LXC; then
    ENV_LABEL="LXC Container (Proxmox)"
elif $IS_CLOUD_VM; then
    ENV_LABEL="Cloud VM (Hetzner / Cloud-Provider)"
else
    ENV_LABEL="VM / Bare Metal (z.B. Proxmox)"
fi

echo ""
echo -e "${GREEN}Umgebung: $ENV_LABEL${NC}"
echo ""
echo -e "${GREEN}Folgendes wurde konfiguriert:${NC}"
echo "  ✓ System aktualisiert"
echo "  ✓ Zeitzone: $TIMEZONE"
echo "  ✓ Locale: $LOCALE"
echo "  ✓ Chrony NTP (de.pool.ntp.org)"
if $IS_LXC; then
    echo "  ✓ Swap: LXC - vom Host verwaltet"
else
    echo "  ✓ Swap: ${SWAP_INFO:-n/a}"
fi
echo "  ✓ SSH gehaertet (Port: $SSH_PORT)"
echo "  ✓ Fail2Ban aktiv"
echo "  ✓ UFW Firewall aktiv"
echo "  ✓ Basis-Tools: curl, wget, bpytop, tmux"
echo "  ✓ Automatische Sicherheitsupdates (Auto-Reboot: $AUTO_REBOOT)"
echo "  ✓ Logrotate konfiguriert (14 Tage, komprimiert)"
echo "  ✓ Bash History mit Timestamps"
echo "  ✓ tmux installiert + Auto-Attach beim Login (Session: 'main')"
echo "  ✓ MOTD Systeminfo"

if $IS_LXC; then
    echo ""
    echo -e "${CYAN}LXC-spezifisch uebersprungen:${NC}"
    echo "  ~ sysctl / Kernel Hardening (Host zustaendig)"
    echo "  ~ Swap Einrichtung (Host zustaendig)"
    echo "  ~ auditd (kein Kernel-Zugriff in LXC)"
    echo "  ~ QEMU Guest Agent (nur fuer VMs)"
elif $IS_CLOUD_VM; then
    echo "  ✓ Kernel/Sysctl Hardening"
    if $DISABLE_IPV6; then
        echo "  ✓ IPv6 deaktiviert"
    else
        echo "  ✓ IPv6 gehaertet (bleibt aktiv)"
    fi
    echo "  ✓ Auditd installiert (Wazuh-Backend)"
    echo ""
    echo -e "${CYAN}Cloud-VM-spezifisch uebersprungen:${NC}"
    echo "  ~ QEMU Guest Agent (vom Cloud-Anbieter verwaltet)"
else
    echo "  ✓ Kernel/Sysctl Hardening"
    if $DISABLE_IPV6; then
        echo "  ✓ IPv6 deaktiviert"
    else
        echo "  ✓ IPv6 gehaertet (bleibt aktiv)"
    fi
    echo "  ✓ Auditd installiert (Wazuh-Backend)"
    echo "  ✓ QEMU Guest Agent (Proxmox)"
fi

echo ""
echo -e "${YELLOW}WICHTIGE NACHARBEITEN:${NC}"
echo "  ! SSH Key hinterlegen, dann PasswordAuthentication in"
echo "    /etc/ssh/sshd_config.d/99-hardening.conf deaktivieren"
if $IS_CLOUD_VM && ! $DRY_RUN; then
    NON_ROOT_USERS=$(awk -F: '$3 >= 1000 && $1 != "nobody" {print $1}' /etc/passwd)
    if [[ -z "$NON_ROOT_USERS" ]]; then
        echo "  ! Regulaeren User anlegen (adduser), SSH-Key hinterlegen,"
        echo "    dann PermitRootLogin auf 'no' setzen in 99-hardening.conf"
    fi
fi
echo "  ! UFW: Weitere benoetigte Ports freigeben (z.B. ufw allow 443/tcp)"
echo "  ! Fail2Ban: Eigene IPs in /etc/fail2ban/jail.local whitelisten"
echo "  ! Chrony Status pruefen: chronyc tracking"

if $IS_LXC; then
    echo ""
    echo -e "${CYAN}LXC Nacharbeiten:${NC}"
    echo "  ! sysctl Haertung auf dem Proxmox-HOST konfigurieren"
    echo "    -> /etc/sysctl.d/99-hardening.conf auf dem Host anlegen"
    echo "  ! Falls Wazuh benoetigt: Agent im syslog-Modus konfigurieren"
fi

if $DRY_RUN; then
    echo ""
    echo -e "${YELLOW}DRY-RUN abgeschlossen - keine Aenderungen vorgenommen.${NC}"
    echo -e "${YELLOW}Ohne --check ausfuehren um die Haertung durchzufuehren.${NC}"
fi

echo ""
echo -e "${GREEN}Neustart empfohlen!${NC}"
echo ""
info "Log-Datei: $LOG_FILE"
