#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/build.func)

# Copyright (c) 2025 ITFlow Community
# License: MIT
# Source: https://itflow.org

APP="ITFlow"
var_tags="psa;msp;ticketing;billing;documentation"
var_cpu="2"
var_ram="4096"
var_disk="20"
var_os="debian"
var_version="12"
var_unprivileged="1"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  msg_info "Updating base system"
  $STD apt-get update
  $STD apt-get -y upgrade
  msg_ok "Base system updated"

  msg_info "Updating ITFlow"
  DOMAIN=$(grep 'config_base_url' /var/www/*/config.php 2>/dev/null | cut -d "'" -f 4 | head -n1)
  if [ -z "$DOMAIN" ]; then
    msg_error "Could not determine ITFlow installation path"
    exit 1
  fi
  
  INSTALL_PATH="/var/www/${DOMAIN}"
  if [ -d "$INSTALL_PATH" ]; then
    cd "$INSTALL_PATH"
    $STD git fetch
    $STD git pull
    chown -R www-data:www-data "$INSTALL_PATH"
    $STD systemctl reload apache2
    msg_ok "ITFlow updated"
  else
    msg_error "ITFlow installation not found at $INSTALL_PATH"
    exit 1
  fi

  msg_info "Cleaning up"
  $STD apt-get -y autoremove
  $STD apt-get -y autoclean
  msg_ok "Cleaned up"

  msg_ok "Update complete"
  exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
msg_info "ITFlow Setup"
msg_info "The ITFlow installation will now begin..."
msg_info "This process may take several minutes..."

msg_info "Preparing system"
$STD apt-get update
$STD apt-get -y upgrade

msg_info "Installing required packages"
export DEBIAN_FRONTEND=noninteractive
$STD apt-get install -y apache2 mariadb-server \
  php libapache2-mod-php php-intl php-mysqli php-gd \
  php-curl php-imap php-mailparse php-mbstring php-zip php-xml libapache2-mod-md \
  certbot python3-certbot-apache git sudo whois cron dnsutils openssl wget
msg_ok "Packages installed"

msg_info "Configuring PHP"
PHP_VERSION=$(php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;')
PHP_INI_PATH="/etc/php/${PHP_VERSION}/apache2/php.ini"
sed -i 's/^;\?upload_max_filesize =.*/upload_max_filesize = 500M/' "$PHP_INI_PATH"
sed -i 's/^;\?post_max_size =.*/post_max_size = 500M/' "$PHP_INI_PATH"
sed -i 's/^;\?max_execution_time =.*/max_execution_time = 300/' "$PHP_INI_PATH"
msg_ok "PHP configured"

msg_info "Downloading ITFlow installation script"
cd /tmp
wget -q https://github.com/itflow-org/itflow-install-script/raw/main/itflow_install.sh -O itflow_install.sh
chmod +x itflow_install.sh
msg_ok "Installation script downloaded"

msg_info "Starting ITFlow installation"
IP=$(hostname -I | awk '{print $1}')
DOMAIN="${IP}.nip.io"

msg_info "Running ITFlow installer with domain: $DOMAIN"
msg_info "Using master branch with self-signed SSL"

# Run unattended installation
/tmp/itflow_install.sh \
  --domain "$DOMAIN" \
  --timezone "UTC" \
  --branch "master" \
  --ssl "selfsigned" \
  --unattended

msg_ok "ITFlow Installation Complete"

msg_info "Getting installation details"
IP=$(hostname -I | awk '{print $1}')
DOMAIN="${IP}.nip.io"

# Get database password from config.php
if [ -f "/var/www/${DOMAIN}/config.php" ]; then
  DBPASS=$(grep 'dbpassword' /var/www/${DOMAIN}/config.php | cut -d "'" -f 4)
else
  DBPASS="Check /var/www/${DOMAIN}/config.php"
fi

msg_info "\n"
msg_info "═══════════════════════════════════════════════════════════════"
msg_info "  ITFlow has been successfully installed!"
msg_info "═══════════════════════════════════════════════════════════════"
msg_info ""
msg_info "  🌐 Web Access:"
msg_info "     HTTPS: https://${DOMAIN}"
msg_info "     HTTP:  http://${DOMAIN}"
msg_info ""
msg_info "  📝 Setup Required:"
msg_info "     Navigate to the URL above to complete initial setup"
msg_info "     You will create your admin account during setup"
msg_info ""
msg_info "  🗄️  Database Details:"
msg_info "     Database: itflow"
msg_info "     User:     itflow"
msg_info "     Password: ${DBPASS}"
msg_info "     (Stored in: /var/www/${DOMAIN}/config.php)"
msg_info ""
msg_info "  🔧 System Configuration:"
msg_info "     Installation Path: /var/www/${DOMAIN}"
msg_info "     Apache Config:     /etc/apache2/sites-available/${DOMAIN}.conf"
msg_info "     PHP Config:        ${PHP_INI_PATH}"
msg_info "     Cron Jobs:         /etc/cron.d/itflow"
msg_info ""
msg_info "  🔐 SSL Certificate:"
msg_info "     Type: Self-signed"
msg_info "     Note: Browser will show security warning"
msg_info "     For production: Configure Let's Encrypt with a real domain"
msg_info ""
msg_info "  📚 Essential Next Steps:"
msg_info "     1. Complete web setup at https://${DOMAIN}"
msg_info "     2. Configure backups (especially master encryption key!)"
msg_info "     3. Set up email configuration for tickets/invoices"
msg_info "     4. Configure email-to-ticket parsing"
msg_info "     5. Review documentation at https://docs.itflow.org"
msg_info ""
msg_info "  ⚠️  Security Notes:"
msg_info "     - Using self-signed SSL (browser warnings expected)"
msg_info "     - For production: use real domain + Let's Encrypt"
msg_info "     - Backup your master encryption key regularly!"
msg_info "     - Configure firewall rules for ports 80/443"
msg_info ""
msg_info "  📖 Documentation:"
msg_info "     https://docs.itflow.org"
msg_info ""
msg_info "  💬 Community:"
msg_info "     Forum:  https://forum.itflow.org"
msg_info "     GitHub: https://github.com/itflow-org/itflow"
msg_info ""
msg_info "═══════════════════════════════════════════════════════════════"
msg_info "\n"
