# 📄 MailStore Server Dokumentations-Script (v2.1)

Ein leistungsstarkes PowerShell-Script zur automatisierten Erstellung einer vollständigen HTML-Dokumentation einer MailStore Server-Installation – inklusive Systeminformationen, Lizenzdetails, Archive Stores, Benutzerprofilen, Netzwerk-Setup, und mehr. Mit optionaler MailStore API-Integration für erweiterte Datenabfragen.

---

## 🧰 Features

- 📑 Generiert eine strukturierte HTML-Dokumentation
- 🔌 Nutzt die MailStore PowerShell API für tiefgreifende Informationen (optional)
- 🖥️ Erkennt Systemdetails (RAM, CPU, OS, Netzwerke)
- 📦 Dokumentiert Archive Stores, Ordnerstruktur, Benutzer, Profile und Jobs
- 🔐 Zeigt Lizenzinformationen, Supportstatus und kritische Warnungen
- 📊 Optional: Performance-Daten (CPU/RAM-Auslastung)
- 📂 Unterstützt alternative Installationspfade und flexible Konfiguration

---

## 🚀 Erste Schritte

### 📦 Voraussetzungen

- Windows PowerShell 5.x oder PowerShell Core
- MailStore Server (mit aktivierter API, falls gewünscht)
- MailStore PowerShell API Wrapper (`MS.PS.Lib.psd1`)
- Ausreichende Rechte zur Ausführung von PowerShell-Skripten

---

## ▶️ Verwendung

### Standardausführung

```powershell
.\MailStore-Documentation.ps1
```

### Mit Passwort und API Wrapper

```powershell
.\MailStore-Documentation.ps1 -MailStorePassword "MeinPasswort" -APIWrapperPath "C:\Scripts\API-Wrapper\MS.PS.Lib.psd1"
```

### Alle Parameter

| Parameter                  | Beschreibung                                                  |
|---------------------------|---------------------------------------------------------------|
| `-OutputPath`             | Speicherort für HTML-Datei (Standard: `C:\Temp\...`)          |
| `-MailStoreServerPath`    | Installationspfad von MailStore Server                        |
| `-MailStoreServer`        | Servername oder IP-Adresse (Standard: `localhost`)            |
| `-MailStorePort`          | API-Port (Standard: `8463`)                                   |
| `-MailStoreUsername`      | Admin-Benutzername (Standard: `admin`)                         |
| `-MailStorePassword`      | Passwort für die Authentifizierung                            |
| `-APIWrapperPath`         | Pfad zur `MS.PS.Lib.psd1` Datei                               |
| `-IncludePerformanceData` | Optional: Performance-Daten erfassen                          |
| `-UseAPIOnly`             | Script nutzt ausschließlich API-Daten                         |

---

## 📁 Ausgabe

Die erzeugte HTML-Datei enthält:

- ✅ Systeminformationen
- ✅ MailStore-Dienststatus
- ✅ Installationsanalyse
- ✅ API-Verbindungsstatus
- ✅ Lizenzinformationen
- ✅ Archive Stores & Konfiguration
- ✅ Ordnerstrukturen & Benutzer
- ✅ Netzwerk & Festplattenstatus
- ✅ Geplante Jobs, Profile und Retention Policies
- ⚠️ Visuelle Warnungen bei abgelaufenen Lizenzen, Speicherengpässen, etc.

---

## 🔒 Sicherheitshinweis

Wenn du Passwörter über die Kommandozeile übergibst, stelle sicher, dass deine Umgebung geschützt ist. Alternativ kann das Passwort auch sicher während der Ausführung eingegeben werden.

---

## 🛠️ Troubleshooting

- ❌ **API-Verbindung schlägt fehl?**  
  → Stelle sicher, dass der API-Zugriff aktiviert ist, und prüfe Port & Zertifikate.

- ❌ **Execution Policy verhindert Skriptausführung?**  
  → Verwende:
  ```powershell
  Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
  ```

- ⚠️ **"Nicht digital signiert"-Warnung?**  
  → Entsperre Skript-Dateien mit:
  ```powershell
  Get-ChildItem -Recurse | Unblock-File
  ```

---

## 🧑‍💻 Autor

**MailStore Dokumentations-Script v2.1**  
Erstellt von [dein Name oder Organisation einfügen]  
Lizenz: MIT (oder andere, falls gewünscht)

---

## 📬 Kontakt

Fragen oder Verbesserungsvorschläge?  
→ [GitHub Issues](https://github.com/dein-repo/issues) oder Pull Request erstellen.
