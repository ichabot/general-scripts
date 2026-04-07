# ERPNext v15 Installer für Ubuntu 24.04

Interaktives Bash-Script zur Installation von ERPNext v15 auf einem
frischen Ubuntu 24.04 LTS Server. Wählbar zwischen Production-Setup
(nginx + supervisor) und Development-Setup (`bench start`), mit
modularer App-Auswahl inklusive der gängigen DACH-Lokalisierungs-Apps
von [alyf-de](https://github.com/alyf-de).

Basiert auf der [Frappe-Forum-Anleitung](https://discuss.frappe.io/t/install-erpnext-version-15-in-ubuntu-24-04/143643)
mit zusätzlichen Fixes für bekannte Stolperfallen.

## Was das Script macht

- System-Update und Installation aller Basispakete
- Anlegen eines dedizierten Linux-Users für Frappe (default: `frappe`)
- MariaDB-Installation, Härtung und utf8mb4-Konfiguration
- Installation von **wkhtmltopdf 0.12.6.1-3 mit patched Qt** (das
  Ubuntu-24.04-Repo-Paket funktioniert nicht mit Frappe)
- nvm + Node.js 18 *und* 20 (Frappe braucht beide), yarn
- frappe-bench CLI
- `bench init` mit Frappe v15
- Anlegen einer ERPNext-Site mit gewünschtem Namen
- Installation der gewählten Apps
- Optional: `bench setup production` (nginx + supervisor)
- Generierung sicherer Passwörter, Speicherung in
  `/root/erpnext-install-info.txt` (chmod 600)

## Voraussetzungen

- **Ubuntu 24.04 LTS** (frische Installation empfohlen)
- **Mindestens 4 GB RAM** (8 GB empfohlen — der `bench init` Schritt
  läuft sonst Gefahr, beim Node-Build out-of-memory zu gehen)
- **40 GB freier Festplattenspeicher**
- **Root- bzw. sudo-Rechte**
- **Internet-Zugang** für Paket-Downloads und git clones

## Nutzung

```bash
wget https://raw.githubusercontent.com/<user>/<repo>/main/install-erpnext-v15.sh
chmod +x install-erpnext-v15.sh
sudo ./install-erpnext-v15.sh
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
| `hrms` | y | HR & Payroll Modul, offiziell von Frappe |
| `erpnext_germany` | y | DE-Lokalisierung, Basis für die anderen alyf-Apps |
| `banking` | n | Bank-Import / Kontoauszüge (alyf-de) |
| `erpnext_datev` | n | DATEV-Export für Steuerberater (alyf-de) |
| `erpnext_druckformate` | y | Deutsche Druckformate für Rechnungen etc. (alyf-de) |
| `eu_einvoice` | y | E-Rechnung EU / XRechnung / ZUGFeRD (alyf-de) |
| `time_capture` | n | Zeiterfassung (alyf-de) |

`banking`, `erpnext_datev` und `eu_einvoice` setzen `erpnext_germany`
voraus — wird bei Bedarf automatisch mit installiert.

## Zugangsdaten

Nach erfolgreicher Installation liegen alle Passwörter und Zugangsdaten
in **`/root/erpnext-install-info.txt`** (`chmod 600`, nur für root
lesbar). Die Datei enthält auch:

- URLs für lokalen Zugriff und über Reverse Proxy
- Pfade zu nginx- und Supervisor-Configs
- Restart-Befehle
- Hinweise zum nächsten Schritt (Custom App anlegen)

**Nach dem Übertragen in einen Passwort-Manager sollte die Datei
gelöscht werden:**

```bash
shred -u /root/erpnext-install-info.txt
```

## Fixes gegenüber der Original-Anleitung

Das Script weicht an drei Stellen von der verlinkten Forum-Anleitung
ab, weil diese Stellen auf Ubuntu 24.04 nicht mehr funktionieren oder
zu Problemen führen:

### Node.js 18 + 20 statt nur 18

Aktuelle Frappe-v15-Builds brauchen Node 20 für Teile des Asset-Builds,
während andere Komponenten noch auf 18 referenzieren. Das Script
installiert beide via nvm und setzt 20 als Default.

### wkhtmltopdf vom GitHub-Release statt aus dem Repo

Das `wkhtmltopdf`-Paket aus dem Ubuntu-24.04-Repo wurde gegen ein
unpatched Qt gebaut und produziert in Frappe fehlerhafte PDFs (kaputtes
Page-Layout, fehlende Fonts, Header/Footer-Probleme bei Rechnungen).
Das Script installiert stattdessen das offizielle
`0.12.6.1-3.jammy_amd64.deb` direkt vom
[wkhtmltopdf-GitHub-Repo](https://github.com/wkhtmltopdf/packaging/releases/tag/0.12.6.1-3).

### MariaDB utf8mb4-Konfiguration in eigener Conf-Datei

Statt direkt in `/etc/mysql/my.cnf` zu schreiben, legt das Script eine
saubere Drop-in-Config unter
`/etc/mysql/mariadb.conf.d/99-frappe.cnf` an. Damit überleben die
Charset-Settings ein MariaDB-Update ohne Konflikt.

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
sudo bench setup production frappe --yes
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

### Apps nachträglich verwalten

```bash
# App hinzufügen
sudo -u frappe bash -c 'cd ~/frappe-bench && bench get-app <git-url>'
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

## Custom App für eigene Anpassungen

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
versioniert und sind damit reproduzierbar auf neuen Installationen.

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

### `redis` Connection-Errors während `bench init`

Sicherstellen, dass redis läuft:

```bash
sudo systemctl status redis-server
sudo systemctl restart redis-server
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

## Lizenz

MIT

## Disclaimer

Dieses Script wird ohne Garantie zur Verfügung gestellt. Vor Einsatz
auf produktiven Systemen testen. Installation auf bestehenden Systemen
mit Daten wird nicht empfohlen — frische VM verwenden.

Kein offizielles Frappe/ERPNext-Tool. ERPNext und Frappe sind
Markenzeichen von Frappe Technologies Pvt. Ltd.
