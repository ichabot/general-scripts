# Projekt-Instruction: ERPNext v16 Anpassungen

Du arbeitest an einer ERPNext v16 Installation auf Ubuntu 24.04 im
Production-Modus (nginx + supervisor, developer_mode aktiv). Alle
Anpassungen laufen über eine dedizierte Custom App. Ziel ist ein
jederzeit reproduzierbares, update-sicheres Grundgerüst-Template.

Plattform-Details:
- Python 3.14 (uv-managed, im Home des frappe-Users)
- Node.js 24 (nvm-managed)
- frappe-bench installiert via `uv tool install`
- Bench-Verzeichnis: /home/frappe/frappe-bench
- bench-Binary: /home/frappe/.local/bin/bench

## HARTE REGELN — nicht verhandelbar

### 1. Niemals Core-Code oder fremde Apps editieren
NIEMALS Änderungen vornehmen in:
- `apps/frappe/**`
- `apps/erpnext/**`
- `apps/hrms/**`
- `apps/payments/**`
- `apps/erpnext_germany/**`, `apps/erpnext_datev/**`,
  `apps/eu_einvoice/**`, `apps/pdf_on_submit/**`
- Jede andere nicht von uns geschriebene App

Das gilt für Python-Dateien, JS-Dateien, JSON-DocType-Definitionen, Print
Formats, alles. `bench update` zieht bei diesen Apps neue Versionen und
überschreibt ALLES, was du dort hineingeschrieben hast. Ergebnis: Arbeit
weg, oder schlimmer, Merge-Konflikte die Updates blockieren.

Wenn du einen Change dort machen willst: STOPP. Finde den richtigen
Extension-Punkt (siehe unten) und mach es von außen.

### 2. Bestehende Felder nie verändern
Bestehende Felder aus ERPNext und anderen Apps (z.B. `customer_name`,
`grand_total`, `tax_id`) werden NIEMALS umbenannt, gelöscht, im Typ
geändert, oder in ihrer Kern-Property geändert. Nur diese Änderungen an
bestehenden Feldern sind erlaubt — und nur via Property Setter, nie via
direkter DocType-Edit:
- Label ändern (z.B. für DE-Übersetzung)
- Pflichtfeld-Status ändern (reqd 0/1)
- Sichtbarkeit ändern (hidden 0/1)
- Read-only ändern
- depends_on / mandatory_depends_on setzen
- Default-Wert ändern
- In Listenansicht anzeigen (in_list_view)

Alles andere (Feldtyp, Optionen, fieldname, Löschen) ist verboten.

### 3. Neue Felder nur als Custom Fields
Zusätzliche Felder an bestehenden DocTypes werden IMMER als Custom Field
angelegt, nie durch Editieren der DocType-JSON-Datei. Die fieldname der
Custom Fields haben ein einheitliches Präfix (z.B. `custom_` oder ein
Kürzel des Projekts), damit sie beim Export als Fixture klar
identifizierbar sind und nicht mit Core-Feldern kollidieren.

### 4. Alles was du änderst, muss ein Fixture oder Code werden
Jede Änderung muss reproduzierbar sein. Nach UI-Anpassungen immer:
    bench export-fixtures --app <custom_app>
Und die resultierenden JSON-Dateien committen. Wenn du etwas in der UI
änderst und NICHT als Fixture exportierst, ist es verloren bei der
nächsten frischen Installation.

Manche Dinge lassen sich schlecht als Fixture abbilden (z.B. Single
DocTypes wie "Selling Settings"). Für die schreibst du ein Patch-Script
unter `<custom_app>/patches/` und trägst es in `patches.txt` ein.
Patches laufen einmalig beim `bench migrate`.

### 5. Verzeichnis-Struktur der Custom App respektieren
Alles was wir bauen, landet ausschließlich in der Custom App. Struktur:

    apps/<custom_app>/
      <custom_app>/
        hooks.py                 # Zentrale Extension-Registrierung
        fixtures/                # Auto-generierte DB-Exports
          custom_field.json
          property_setter.json
          client_script.json
          ...
        patches/                 # Einmalige Migrations-Scripts
          v1_0/
            set_default_settings.py
        public/                  # Statische Assets (CSS, JS, Bilder)
        templates/               # Jinja-Templates
        <modul>/
          doctype/               # EIGENE DocTypes (nicht ERPNext-DocTypes)
        api/                     # Eigene Python-Logik, von Hooks aufgerufen
          __init__.py
          invoice.py
          customer.py
      patches.txt
      requirements.txt
      README.md

Eigene DocTypes, die wir neu erstellen, gehören NATÜRLICH in diese App
und werden dort als Files committet (nicht als Fixture exportiert).

## Wie man ERPNext von außen erweitert — Entscheidungsbaum

| Was willst du ändern?                              | Richtiger Weg                                                |
|----------------------------------------------------|--------------------------------------------------------------|
| Feld zu bestehendem DocType hinzufügen             | Custom Field (via UI oder `make_custom_field`), Fixture      |
| Eigenschaft eines bestehenden Felds ändern         | Property Setter, Fixture                                     |
| Verhalten bei Save/Submit/Cancel hinzufügen        | `doc_events` in `hooks.py` → Python-Funktion in `api/`       |
| JS-Verhalten in einer bestehenden Form             | Client Script (UI) oder `doctype_js` in `hooks.py`           |
| Python-Methode einer DocType-Klasse ersetzen       | `override_doctype_class` in `hooks.py`                       |
| Whitelist-Funktion ersetzen                        | `override_whitelisted_methods` in `hooks.py`                 |
| Report-Query / Standard-Filter von Listen          | `permission_query_conditions`, `has_permission` in hooks.py  |
| Neue Funktion, die per Cron läuft                  | `scheduler_events` in `hooks.py`                             |
| Neues DocType / Modul / Formular                   | `bench new-doctype` innerhalb der Custom App                 |
| Einstellungen in "Selling Settings" etc. setzen    | Patch-Script unter `patches/`                                |
| Neuen Report                                       | Script Report oder Query Report in der Custom App            |
| Print Format                                       | In UI anlegen + Fixture ODER als File in `print_format/`     |
| Kontenrahmen / Steuervorlagen / Territories        | NICHT anfassen — das macht Company-Setup bzw. erpnext_germany |

## Fixtures — was exportiert wird

Die `fixtures`-Liste in `hooks.py` der Custom App definiert, was beim
Export/Install mitgenommen wird. Typische Defaults (am Projektanfang
einmal setzen, dann werden künftige Änderungen automatisch miterfasst):

```python
fixtures = [
    # Strukturelle Anpassungen an bestehenden DocTypes
    {"dt": "Custom Field",    "filters": [["name", "like", "%-custom_%"]]},
    {"dt": "Property Setter", "filters": [["module", "=", "<Modulname>"]]},

    # Code-artige Anpassungen
    {"dt": "Client Script",   "filters": [["module", "=", "<Modulname>"]]},
    {"dt": "Server Script",   "filters": [["module", "=", "<Modulname>"]]},

    # Workflows, Rollen, Berechtigungen
    {"dt": "Workflow",        "filters": [["name", "in", []]]},  # namen eintragen
    {"dt": "Workflow State"},
    {"dt": "Workflow Action Master"},
    {"dt": "Role",            "filters": [["name", "in", []]]},  # eigene Rollen

    # Präsentation
    {"dt": "Print Format",    "filters": [["name", "in", []]]},
    {"dt": "Letter Head"},
    {"dt": "Email Template"},
    {"dt": "Notification"},
    {"dt": "Dashboard"},
    {"dt": "Dashboard Chart"},
    {"dt": "Number Card"},
    {"dt": "Report",          "filters": [["is_standard", "=", "No"]]},
]
```

Die Filter werden projektspezifisch eingetragen, sobald der Modulname
und die Präfix-Konvention feststehen.

## Workflow für jede Änderung

1. Änderung machen — entweder via UI (einfache Sachen) oder als Code in
   der Custom App (komplexe Logik).
2. Nach UI-Änderungen: `bench export-fixtures --app <custom_app>`
3. Nach Code-Änderungen an DocType-Definitionen: `bench migrate`
4. Nach Python-Änderungen: `sudo -u frappe bash -c 'cd ~/frappe-bench && bench restart'`
5. Nach JS/CSS-Änderungen: `bench build --app <custom_app>` und ggf.
   Browser-Cache-Hardreload.
6. Git commit mit klarer Message: was geändert, warum, welche Fixtures
   betroffen.
7. Vor dem Push: `git diff` lesen und sicherstellen, dass keine
   ungewollten Fixture-Änderungen drin sind (z.B. versehentlich
   mit-exportierte Dinge aus anderen Modulen).

## Ganz generelle Arbeitsweise

- Vor jeder Code-Änderung: prüfen, ob es den richtigen Extension-Punkt
  gibt. Erst wenn keiner existiert, weiter überlegen. NIEMALS "einfach
  schnell" im Core-Code ändern, auch nicht für Debugging.
- Bei Unsicherheit, welcher Extension-Punkt passt: nachfragen, nicht
  raten.
- Alle neuen Python-Dateien kriegen Docstrings. Öffentliche Funktionen
  werden mit Typ-Hints versehen.
- Whitelisted API-Endpoints brauchen immer eine explizite
  Permissions-Prüfung (`frappe.has_permission(...)`), nie blind auf den
  Caller vertrauen.
- Bei DB-Updates innerhalb von Hooks: `frappe.db.set_value` statt
  `doc.save()` wenn du keine Validierungen auslösen willst, sonst
  Endlosschleifen-Gefahr in `validate`/`on_update`-Hooks.
- Bei Fehlern/Bugs: erst verstehen, was passiert, dann fixen. Nicht
  raten. `bench --site <site> console` ist dein Freund für
  Live-Debugging.

## Was du machen darfst ohne Rückfrage

- Custom Fields anlegen (mit Präfix)
- Property Setter anlegen (Label, Sichtbarkeit, reqd etc.)
- Client Scripts / Server Scripts schreiben
- Eigene DocTypes in der Custom App anlegen
- Hooks in `hooks.py` eintragen
- Print Formats erstellen
- Email Templates, Notifications, Dashboards erstellen
- Fixtures exportieren
- Patch-Scripts schreiben

## Was Rückfrage erfordert

- Rollen-/Berechtigungsänderungen an bestehenden Rollen
- Workflows, die bestehende Geschäftsprozesse ändern
- Änderungen an Naming Series
- Alles, was irreversibel ist oder laufende Daten betrifft
- Neue pip-Dependencies in `requirements.txt`
- Neue npm-Dependencies
- Änderungen an Backup- oder Scheduler-Konfiguration
- Alles, was sudo/root-Rechte braucht

## Befehle, die du wissen musst

- bench liegt unter /home/frappe/.local/bin/bench (uv tool install)
- Wenn du sudo brauchst: `sudo env "PATH=/home/frappe/.local/bin:$PATH" bench ...`
- Site-Name: aus Installation, fragen falls unklar
- Bench-Restart nach Python-Änderungen: `bench restart` (Production) oder
  automatisch via File-Watcher (Dev mit `bench start`)

## Am Anfang jeder Session

Wenn du nicht sicher bist, in welchem Zustand die Installation ist:
    bench --site <site> list-apps
    cd apps/<custom_app> && git status && git log --oneline -10
Und frag nach dem Ziel der Session, bevor du loslegst.
