# ERPNext v16 Installer für Ubuntu 24.04

Interaktives Bash-Script zur Installation von ERPNext v16 auf einem
frischen Ubuntu 24.04 LTS Server. Wählbar zwischen Production-Setup
(nginx + supervisor) und Development-Setup (`bench start`), mit
modularer App-Auswahl inklusive der gängigen DACH-Lokalisierungs-Apps
von [alyf-de](https://github.com/alyf-de).

Basiert auf der [offiziellen Frappe-Forum-Anleitung für v16](https://discuss.frappe.io/t/guide-how-to-install-erpnext-v16-on-linux-ubuntu-24-04-step-by-step-instructions/159255).

## Was das Script macht

- System-Update und Installation aller Basispakete
- Anlegen eines dedizierten Linux-Users für Frappe (default: `frappe`)
- MariaDB-Installation, Härtung und utf8mb4-Konfiguration
- Installation von **wkhtmltopdf 0.12.6.1-2 mit patched Qt** (das
  Ubuntu-24.04-Repo-Paket funktioniert nicht mit Frappe)
- **uv** (Astral Python Manager) für Userspace-Python 3.14
- **Python 3.14** via uv (kein deadsnakes/PPA, läuft sauber neben
  System-Python 3.12)
- **Node.js 24** via nvm
- **frappe-bench** via `uv tool install`
- `bench init` mit Frappe v16
- Anlegen einer ERPNext-Site mit gewünschtem Namen
- Pre-flight Branch-Check per `git ls-remote` für jede gewählte App
- Installation der gewählten Apps
- Optional: `bench setup production` mit nginx + supervisor + ansible
- Generierung sicherer Passwörter, Speicherung in
  `/root/erpnext-install-info.txt` (chmod 600)
- Temporäres NOPASSWD-sudoers während Installation (trap-cleanup,
  wird in jedem Fall am Ende entfernt)

## Voraussetzungen

- **Ubuntu 24.04 LTS** (frische Installation empfohlen)
- **Mindestens 4 GB RAM** (8 GB empfohlen — der Node-Build während
  `bench init` ist RAM-hungrig)
- **40 GB freier Festplattenspeicher**
- **Root- bzw. sudo-Rechte**
- **Internet-Zugang** für Paket-Downloads und git clones

## Nutzung

```bash
wget https://raw.githubusercontent.com/<user>/<repo>/main/install-erpnext-v16.sh
chmod +x install-erpnext-v16.sh
sudo ./install-erpnext-v16.sh
```

Das Script führt dich durch alle Konfigurationsschritte. Nach der
finalen Bestätigung läuft alles automatisch durch (~15-30 Minuten,
je nach VM-Performance und gewählten Apps).

## Interaktive Konfiguration

Beim Ausführen wirst du nach Folgendem gefragt:

| Frage | Default | Beschreibung |
|---|---|---|
| Setup-Modus | Production | `1` = nginx + supervisor + Autostart, `2` = `bench start` im Terminal |
| developer_mode | an | DocType-Editing via UI, kein Asset-Caching |
| Linux-User | `frappe` | Name des dedizierten Frappe-Users |
| Linux-Passwort | generiert | Vorschlag annehmen oder eigenes setzen |
| MariaDB root-Passwort | generiert | Vorschlag annehmen oder eigenes setzen |
| Site-Name | `site1.local` | Name der ERPNext-Site (am besten FQDN) |
| Admin-Passwort | generiert | Passwort für den ERPNext-Administrator-Account |
| App-Auswahl | siehe unten | Pro App ein y/n Prompt |

### Verfügbare Apps

| App | Default | Beschreibung |
|---|---|---|
| `payments` | y | Payment-Gateway-Integration (Stripe, PayPal, ...), offiziell von Frappe |
| `hrms` | y | HR & Payroll Modul, offiziell von Frappe (enthält Zeiterfassung via Employee Checkin + Timesheet) |
| `erpnext_germany` | y | DE-Lokalisierung von alyf-de, Basis für `erpnext_datev` |
| `eu_einvoice` | y | E-Rechnung EU / XRechnung / ZUGFeRD (alyf-de) |
| `pdf_on_submit` | y | Generiert automatisch PDF beim Submit eines Belegs (alyf-de) |
| `erpnext_datev` | n | DATEV-Export für Steuerberater (alyf-de) |

`erpnext_datev` setzt `erpnext_germany` voraus — wird bei Bedarf
automatisch mit installiert.

## Zugangsdaten

Nach erfolgreicher Installation liegen alle Passwörter und Zugangsdaten
in **`/root/erpnext-install-info.txt`** (`chmod 600`, nur für root
lesbar). Die Datei enthält auch:

- URLs für lokalen Zugriff und über Reverse Proxy
- Pfade zu nginx- und Supervisor-Configs
- Restart-Befehle
- Hinweise zum nächsten Schritt (Custom App anlegen)
- Troubleshooting-Sektion (Redis, Supervisor, sudo-PATH)

**Nach dem Übertragen in einen Passwort-Manager sollte die Datei
gelöscht werden:**

```bash
shred -u /root/erpnext-install-info.txt
```

## Fixes und Besonderheiten gegenüber Standard-Anleitungen

### uv statt pip + deadsnakes

ERPNext v16 fordert Python 3.14, Ubuntu 24.04 hat aber nur 3.12. Statt
über deadsnakes-PPA Python 3.14 als System-Paket zu installieren (was
mit anderen Python-Paketen kollidieren kann), nutzt das Script
[uv von Astral](https://github.com/astral-sh/uv). uv installiert
Python 3.14 als Userspace-Tool ins Home des frappe-Users. Ist die
offiziell von Frappe empfohlene Methode für v16.

### Node.js 24 via nvm

v16 fordert Node 24 (gegenüber Node 18/20 in v15). Wird via nvm im
Home des frappe-Users installiert, parallel zu beliebigen Node-Versionen
des System.

### wkhtmltopdf vom GitHub-Release statt aus dem Repo

Das `wkhtmltopdf`-Paket aus dem Ubuntu-24.04-Repo wurde gegen ein
unpatched Qt gebaut und produziert in Frappe fehlerhafte PDFs (kaputtes
Page-Layout, fehlende Fonts, Header/Footer-Probleme bei Rechnungen).
Das Script installiert stattdessen das offizielle
`0.12.6.1-2.jammy_amd64.deb` direkt vom
[wkhtmltopdf-GitHub-Repo](https://github.com/wkhtmltopdf/packaging/releases/tag/0.12.6.1-2).

### MariaDB utf8mb4-Konfiguration in eigener Conf-Datei

Statt direkt in `/etc/mysql/my.cnf` zu schreiben, legt das Script eine
saubere Drop-in-Config unter
`/etc/mysql/mariadb.conf.d/99-frappe.cnf` an. Damit überleben die
Charset-Settings ein MariaDB-Update ohne Konflikt.

### sudo PATH-Erhalt für bench

`uv tool install` legt `bench` unter `~/.local/bin` ab. Beim
Production-Setup muss bench mit Root-Rechten laufen, sudo strippt aber
per Default die Umgebungsvariablen. Das Script ruft daher
`sudo env "PATH=..." bench setup production` mit explizitem PATH-Erhalt
auf.

### Pre-flight Branch-Check

Vor dem eigentlichen Install prüft das Script per `git ls-remote` für
jede ausgewählte externe App, ob der `version-16`-Branch existiert.
Bricht ab bzw. warnt sofort, statt erst nach 20 Minuten Build mit einem
kryptischen Fehler zu sterben.

### Temporäres NOPASSWD-sudoers

Während Installation werden mehrere `sudo`-Aufrufe aus dem frappe-User
heraus gemacht (supervisor, nginx etc). Das Script legt für die
Install-Dauer ein NOPASSWD-sudoers-Snippet an und entfernt es per
trap-Handler garantiert wieder — auch bei Ctrl+C oder Crash.

## Setup-Modi im Vergleich

### Production (default)

`bench setup production` legt nginx- und Supervisor-Configs an. ERPNext
startet automatisch nach Reboot, nginx liefert statische Assets aus,
alle Frappe-Prozesse (Web, Worker, Scheduler, Realtime) laufen unter
Supervisor-Aufsicht.

- ✅ Autostart, kein Terminal nötig
- ✅ Verhalten identisch zu echter Live-Installation
- ⚠️  Code-Änderungen brauchen `bench restart`

### Development

`bench start` läuft im Vordergrund und startet alle Frappe-Prozesse
über das Procfile. Beim Beenden des Terminals ist ERPNext weg.

- ✅ Auto-Reload bei Code-Änderungen (File-Watcher)
- ✅ Logs aller Prozesse in einem Terminal-Fenster
- ⚠️  Kein Autostart, läuft nur solange das Terminal offen ist

Du kannst von Dev nach Production später umstellen, ohne neu zu
installieren:

```bash
sudo env "PATH=/home/frappe/.local/bin:$PATH" bench setup production frappe --yes
```

## Reverse-Proxy-Hinweis

Im Production-Modus bindet nginx auf Port 80. Wenn ein dedizierter
Reverse Proxy davor läuft, **muss der Proxy den Host-Header der Site
durchreichen**, sonst antwortet Frappe mit 404. Der Site-Name (z.B.
`erp.example.com`) muss im Host-Header stehen.

nginx-Beispiel:

```nginx
location / {
    proxy_pass http://internal-erpnext-ip;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
}
```

Für zusätzliche Hostnamen auf derselben Site:

```bash
sudo -u frappe bash -c 'cd ~/frappe-bench && bench --site site1.local add-domain weiterer.host'
```

## Nach der Installation

### Custom App für eigene Anpassungen

**Bestehende Apps (erpnext, hrms, alyf-Apps) niemals direkt editieren** —
das überlebt das nächste `bench update` nicht. Alle eigenen Anpassungen
gehören in eine dedizierte Custom App:

```bash
su - frappe
cd ~/frappe-bench
bench new-app meine_app
bench --site site1.local install-app meine_app
```

Anpassungen wie Custom Fields, Property Setter, Client/Server Scripts,
Print Formats und Workflows werden über `fixtures` in der Custom App
versioniert (Konfiguration in `hooks.py`) und sind damit reproduzierbar
auf neuen Installationen.

### Apps nachträglich verwalten

```bash
# App hinzufügen
sudo -u frappe bash -c 'cd ~/frappe-bench && bench get-app --branch version-16 <git-url>'
sudo -u frappe bash -c 'cd ~/frappe-bench && bench --site site1.local install-app <app-name>'

# App entfernen
sudo -u frappe bash -c 'cd ~/frappe-bench && bench --site site1.local uninstall-app <app-name> --no-backup --force'
```

### Updates

```bash
# Alle Apps updaten
sudo -u frappe bash -c 'cd ~/frappe-bench && bench update'

# Nur eine App
sudo -u frappe bash -c 'cd ~/frappe-bench && bench update --apps erpnext'
```

`bench update` macht automatisch Backup, git pull, pip/yarn install,
DB-Migrate, Asset-Build und Restart in einem atomaren Schritt.

### Backups

```bash
sudo -u frappe bash -c 'cd ~/frappe-bench && bench --site site1.local backup --with-files'
```

Backups landen in `~frappe/frappe-bench/sites/site1.local/private/backups/`.

### Restart nach Code-Änderungen (Production)

```bash
sudo -u frappe bash -c 'cd ~/frappe-bench && bench restart'
```

## Troubleshooting

### `bench init` schlägt fehl mit out-of-memory

Der Node-Build während `bench init` braucht spürbar RAM. Auf VMs mit
weniger als 4 GB RAM ein Swapfile anlegen:

```bash
sudo fallocate -l 4G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile
```

### Redis-Errors während oder nach der Installation

```bash
sudo -u frappe bash -c 'cd ~/frappe-bench && bench setup socketio'
sudo -u frappe bash -c 'cd ~/frappe-bench && bench setup supervisor'
sudo -u frappe bash -c 'cd ~/frappe-bench && bench setup redis'
sudo supervisorctl reload
```

### Supervisor zeigt "no such group: frappe"

Das passiert wenn die supervisor-Config nach `bench setup production`
nicht automatisch verlinkt wurde. Manueller Fix:

```bash
sudo ln -sf /home/frappe/frappe-bench/config/supervisor.conf \
    /etc/supervisor/conf.d/frappe-bench.conf
sudo supervisorctl reread
sudo supervisorctl update
sudo supervisorctl restart all
sudo supervisorctl status
```

### nginx zeigt "Welcome to nginx" statt ERPNext

Default-Site wird vom Script eigentlich entfernt — falls trotzdem
sichtbar:

```bash
sudo rm -f /etc/nginx/sites-enabled/default
sudo systemctl reload nginx
```

### 404 von Frappe trotz erreichbarem nginx

Der Host-Header passt nicht zum Site-Namen. Entweder den Site-Namen
beim Setup als FQDN setzen, oder nachträglich mit `bench add-domain`
einen weiteren Hostnamen registrieren.

### `bench` Befehl nicht gefunden in sudo

`bench` liegt unter `~/.local/bin` des frappe-Users (uv tool install).
sudo strippt PATH per Default. Lösung:

```bash
sudo env "PATH=/home/frappe/.local/bin:$PATH" bench <command>
```

## Wichtige Hinweise

### Eine ERPNext-Version pro Server

**Niemals verschiedene ERPNext-Versionen auf demselben Server installieren.**
v15 und v16 nutzen unterschiedliche Python-Versionen, Node-Versionen,
Redis-Ports und Supervisor-Strukturen. Für Tests immer separate VMs oder
Container verwenden.

### Drittanbieter-Apps auf v16

Apps die nicht von Frappe selbst entwickelt wurden, sind auf v16 noch
nicht vollständig getestet. Vor `bench update` immer Backup machen. Die
in diesem Script enthaltenen alyf-de-Apps haben offizielle
`version-16`-Branches und werden aktiv gepflegt.

## Lizenz

MIT

## Disclaimer

Dieses Script wird ohne Garantie zur Verfügung gestellt. Vor Einsatz
auf produktiven Systemen testen. Installation auf bestehenden Systemen
mit Daten wird nicht empfohlen — frische VM verwenden.

Kein offizielles Frappe/ERPNext-Tool. ERPNext und Frappe sind
Markenzeichen von Frappe Technologies Pvt. Ltd.
