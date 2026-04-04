# Microsoft 365 Endpoints to OPNsense Lists Converter

Fetches Microsoft 365 endpoint data from the [official Microsoft API](https://endpoints.office.com/endpoints/worldwide) and converts it into OPNsense-compatible firewall alias lists.

## Features

- Fetches live data from Microsoft's official endpoint API
- Generates separate **IPv4**, **IPv6**, and **domain/URL** lists per service
- Supports all M365 services: Exchange, SharePoint, Teams, Common
- Creates combined lists (Exchange+Teams, Office Core, Collaboration, All)
- Generates an **HTML index page** with statistics and OPNsense instructions
- Generates a detailed **README.md** in the output directory
- Configurable category filters (Optimize, Allow, Default)
- Ready for cron job automation

## Requirements

- Python 3.8+
- `requests` library

## Installation

```bash
pip install -r requirements.txt
```

## Configuration

Edit the top of `m365_to_opnsense.py`:

```python
OUTPUT_DIR = Path("/var/www/html/m365-lists")  # Where to write output files
SELECTED_CATEGORY = 'default'                   # Category filter (see below)
```

### Category Filters

| Filter     | Includes                         | Use Case                           |
|------------|----------------------------------|------------------------------------|
| `optimize` | Optimize only                    | Minimal — critical latency-sensitive endpoints |
| `allow`    | Allow only                       | Required for functionality         |
| `default`  | Optimize + Allow + Default       | **Recommended** — complete coverage |
| `all`      | Optimize + Allow + Default       | Same as default                    |

## Usage

```bash
python m365_to_opnsense.py
```

### Output

The script creates these files for each service in the output directory:

- `m365_{service}_ipv4.txt` — IPv4 addresses in CIDR notation
- `m365_{service}_ipv6.txt` — IPv6 addresses in CIDR notation
- `m365_{service}_urls.txt` — Domain names (including wildcards)
- `index.html` — HTML page with statistics and integration guide
- `README.md` — Markdown documentation

### Services

| Key              | Service                                    |
|------------------|--------------------------------------------|
| `exchange`       | Exchange Online (Mail, Calendar, Contacts) |
| `sharepoint`     | SharePoint Online and OneDrive             |
| `teams`          | Microsoft Teams                            |
| `common`         | Common/Office Online shared services       |
| `exchange_teams` | Exchange + Teams combined                  |
| `office_core`    | Exchange + SharePoint + Common             |
| `collaboration`  | Teams + SharePoint                         |
| `all`            | All services combined                      |

## Automation

Add a daily cron job to keep lists current:

```bash
# Update Microsoft 365 lists daily at 2 AM
0 2 * * * /usr/bin/python3 /path/to/m365_to_opnsense.py
```

## OPNsense Integration

1. Host the generated files on a web server accessible to your OPNsense firewall
2. In OPNsense, go to **Firewall → Aliases**
3. Create aliases of type **URL Table (IPs)** or **URL Table (URLs)**
4. Point them at the hosted `.txt` files
5. Set refresh frequency to **1 day**
6. Create firewall rules using these aliases

See the generated `index.html` for detailed step-by-step instructions.

## License

MIT
