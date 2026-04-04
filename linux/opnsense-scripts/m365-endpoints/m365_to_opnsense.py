#!/usr/bin/env python3
"""
Microsoft 365 Endpoints to OPNsense Lists Converter

Fetches Microsoft 365 endpoint data and converts it into OPNsense-compatible
firewall alias lists (IPv4, IPv6, and URL lists).

Author: Generated with Claude Code
License: MIT
"""

import json
import uuid
from datetime import datetime
from pathlib import Path
from typing import Dict, List, Set, Tuple
import requests

# ============================================================================
# CONFIGURATION
# ============================================================================
OUTPUT_DIR = Path("/var/www/html/m365-lists")  # Output directory
SELECTED_CATEGORY = 'default'  # Category filter: 'optimize', 'allow', 'default', 'all'

# API Configuration
API_URL = "https://endpoints.office.com/endpoints/worldwide"
API_TIMEOUT = 30  # seconds

# Service Definitions
SERVICES = {
    # Individual Services
    'exchange': {
        'name': 'EXCHANGE',
        'description': 'Exchange Online (Mail, Calendar, Contacts)',
        'service_areas': ['Exchange'],
        'ports': 'TCP 443, 587, 993, 995, 25 (SMTP)'
    },
    'sharepoint': {
        'name': 'SHAREPOINT',
        'description': 'SharePoint Online and OneDrive for Business',
        'service_areas': ['SharePoint'],
        'ports': 'TCP 443, 80'
    },
    'teams': {
        'name': 'TEAMS',
        'description': 'Microsoft Teams (Chat, Meetings, Calling)',
        'service_areas': ['Skype'],  # Note: Teams uses Skype category
        'ports': 'TCP 443, UDP 3478-3481, TCP/UDP 50000-50059'
    },
    'common': {
        'name': 'COMMON',
        'description': 'Common and Office Online (Shared Services)',
        'service_areas': ['Common'],
        'ports': 'TCP 443, 80'
    },
    # Combined Services
    'exchange_teams': {
        'name': 'EXCHANGE + TEAMS',
        'description': 'Exchange Online and Microsoft Teams Combined',
        'service_areas': ['Exchange', 'Skype'],
        'ports': 'TCP 443, 587, 993, 995, 25, UDP 3478-3481'
    },
    'office_core': {
        'name': 'OFFICE CORE',
        'description': 'Exchange, SharePoint, and Common Services',
        'service_areas': ['Exchange', 'SharePoint', 'Common'],
        'ports': 'TCP 443, 587, 993, 995, 25, 80'
    },
    'collaboration': {
        'name': 'COLLABORATION',
        'description': 'Teams and SharePoint Combined',
        'service_areas': ['Skype', 'SharePoint'],
        'ports': 'TCP 443, 80, UDP 3478-3481, TCP/UDP 50000-50059'
    },
    'all': {
        'name': 'ALL SERVICES',
        'description': 'All Microsoft 365 Services Combined',
        'service_areas': ['Exchange', 'SharePoint', 'Skype', 'Common'],
        'ports': 'All ports listed above'
    }
}

# Category Filters
CATEGORY_FILTERS = {
    'optimize': ['Optimize'],
    'allow': ['Allow'],
    'default': ['Optimize', 'Allow', 'Default'],
    'all': ['Optimize', 'Allow', 'Default']
}


# ============================================================================
# CORE FUNCTIONS
# ============================================================================

def fetch_endpoints() -> Tuple[List[Dict], str]:
    """
    Fetch endpoint data from Microsoft's official API.

    Returns:
        Tuple of (endpoint data list, request ID)

    Raises:
        SystemExit: On API request failure
    """
    client_request_id = str(uuid.uuid4())

    try:
        print(f"Fetching endpoints from Microsoft...")
        print(f"Request ID: {client_request_id}")

        response = requests.get(
            API_URL,
            params={'clientrequestid': client_request_id},
            timeout=API_TIMEOUT
        )

        response.raise_for_status()
        data = response.json()

        print(f"Received {len(data)} total endpoints from Microsoft")
        return data, client_request_id

    except requests.exceptions.Timeout:
        print(f"ERROR: Request timed out after {API_TIMEOUT} seconds")
        exit(1)
    except requests.exceptions.RequestException as e:
        print(f"ERROR: Failed to fetch endpoints from Microsoft API")
        print(f"Error: {e}")
        if hasattr(e, 'response') and e.response is not None:
            print(f"HTTP Status: {e.response.status_code}")
            print(f"Response: {e.response.text}")
        exit(1)
    except json.JSONDecodeError as e:
        print(f"ERROR: Failed to parse JSON response")
        print(f"Error: {e}")
        exit(1)


def matches_service_filter(item: Dict, service_areas: List[str]) -> bool:
    """
    Check if an endpoint item matches the specified service areas.

    Args:
        item: Endpoint data item from API
        service_areas: List of service area names to match

    Returns:
        True if item matches any of the service areas
    """
    item_service = item.get('serviceArea', '')
    return item_service in service_areas


def extract_ips_and_urls(
    data: List[Dict],
    service_areas: List[str],
    categories: List[str]
) -> Tuple[Set[str], Set[str], Set[str]]:
    """
    Extract and categorize IPs and URLs from endpoint data.

    Args:
        data: List of endpoint items from API
        service_areas: Service areas to filter by
        categories: Categories to include (Optimize, Allow, Default)

    Returns:
        Tuple of (IPv4 set, IPv6 set, URLs set)
    """
    ipv4_set = set()
    ipv6_set = set()
    urls_set = set()

    for item in data:
        # Check if item matches service and category filters
        if not matches_service_filter(item, service_areas):
            continue

        item_category = item.get('category')
        if item_category not in categories:
            continue

        # Extract IPv4 and IPv6 addresses
        if 'ips' in item:
            for ip in item['ips']:
                if ':' in ip:
                    ipv6_set.add(ip)
                else:
                    ipv4_set.add(ip)

        # Extract URLs/domains
        if 'urls' in item:
            for url in item['urls']:
                urls_set.add(url)

    return ipv4_set, ipv6_set, urls_set


def write_list_file(filepath: Path, items: Set[str], header_info: Dict) -> int:
    """
    Write a list file with header comments and sorted entries.

    Args:
        filepath: Path to output file
        items: Set of items to write
        header_info: Dictionary with header information

    Returns:
        Number of entries written
    """
    sorted_items = sorted(items)

    with open(filepath, 'w', encoding='utf-8') as f:
        # Write header comments
        f.write(f"# Microsoft 365 {header_info['service_name']} - {header_info['list_type']}\n")
        f.write(f"# {header_info['description']}\n")
        f.write(f"# Generated: {header_info['timestamp']}\n")
        f.write(f"# Category Filter: {header_info['category_filter']}\n")
        f.write(f"# Categories included: {header_info['categories_list']}\n")
        f.write(f"# Total entries: {len(sorted_items)}\n")
        f.write(f"# Source: Microsoft 365 Endpoints API\n")
        f.write("#\n")

        if sorted_items:
            for item in sorted_items:
                f.write(f"{item}\n")
        else:
            f.write("# No entries for this category\n")

    return len(sorted_items)


def create_index_html(output_dir: Path, stats: Dict):
    """
    Create an HTML index page with service links and statistics.

    Args:
        output_dir: Directory where files are located
        stats: Dictionary with statistics for each service
    """
    timestamp = datetime.now().strftime('%Y-%m-%d %H:%M:%S')

    html_content = f"""<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Microsoft 365 Endpoints for OPNsense</title>
    <style>
        * {{
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }}

        body {{
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            line-height: 1.6;
            color: #333;
            background: #f5f5f5;
            padding: 20px;
        }}

        .container {{
            max-width: 1200px;
            margin: 0 auto;
            background: white;
            padding: 30px;
            border-radius: 8px;
            box-shadow: 0 2px 10px rgba(0,0,0,0.1);
        }}

        h1 {{
            color: #0078d4;
            margin-bottom: 10px;
            font-size: 2em;
        }}

        h2 {{
            color: #0078d4;
            margin: 30px 0 15px 0;
            padding-bottom: 10px;
            border-bottom: 2px solid #0078d4;
        }}

        h3 {{
            color: #005a9e;
            margin: 20px 0 10px 0;
        }}

        .subtitle {{
            color: #666;
            margin-bottom: 30px;
            font-size: 1.1em;
        }}

        .info-box {{
            background: #e1f0ff;
            border-left: 4px solid #0078d4;
            padding: 15px;
            margin: 20px 0;
            border-radius: 4px;
        }}

        .warning-box {{
            background: #fff4ce;
            border-left: 4px solid #f59f00;
            padding: 15px;
            margin: 20px 0;
            border-radius: 4px;
        }}

        table {{
            width: 100%;
            border-collapse: collapse;
            margin: 20px 0;
        }}

        th, td {{
            padding: 12px;
            text-align: left;
            border-bottom: 1px solid #ddd;
        }}

        th {{
            background: #0078d4;
            color: white;
            font-weight: 600;
        }}

        tr:hover {{
            background: #f5f5f5;
        }}

        .badge {{
            display: inline-block;
            padding: 4px 8px;
            border-radius: 4px;
            font-size: 0.85em;
            font-weight: 600;
            margin: 0 2px;
        }}

        .badge-ipv4 {{
            background: #e1f5e1;
            color: #2d662d;
        }}

        .badge-ipv6 {{
            background: #e1f0ff;
            color: #005a9e;
        }}

        .badge-urls {{
            background: #fff4ce;
            color: #8b6914;
        }}

        a {{
            color: #0078d4;
            text-decoration: none;
        }}

        a:hover {{
            text-decoration: underline;
        }}

        .file-link {{
            display: inline-block;
            padding: 6px 12px;
            background: #0078d4;
            color: white;
            border-radius: 4px;
            margin: 2px;
            font-size: 0.9em;
        }}

        .file-link:hover {{
            background: #005a9e;
            text-decoration: none;
        }}

        code {{
            background: #f4f4f4;
            padding: 2px 6px;
            border-radius: 3px;
            font-family: 'Courier New', monospace;
            font-size: 0.9em;
        }}

        pre {{
            background: #f4f4f4;
            padding: 15px;
            border-radius: 4px;
            overflow-x: auto;
            margin: 10px 0;
        }}

        ul, ol {{
            margin: 10px 0 10px 30px;
        }}

        li {{
            margin: 5px 0;
        }}

        .section-group {{
            margin: 30px 0;
        }}

        .timestamp {{
            color: #666;
            font-size: 0.9em;
            margin-top: 30px;
            text-align: center;
            padding-top: 20px;
            border-top: 1px solid #ddd;
        }}
    </style>
</head>
<body>
    <div class="container">
        <h1>Microsoft 365 Endpoints for OPNsense</h1>
        <p class="subtitle">Firewall alias lists for Microsoft 365 services</p>

        <div class="info-box">
            <strong>About:</strong> These lists contain Microsoft 365 endpoint data converted to OPNsense-compatible
            firewall alias formats. Use these to create allow rules for Microsoft 365 services.
        </div>

        <div class="warning-box">
            <strong>Important:</strong>
            <ul>
                <li>Microsoft updates these endpoints regularly - refresh daily via cron job</li>
                <li>Do NOT block IPv6 traffic - Microsoft 365 requires IPv6 connectivity</li>
                <li>Ensure required ports are open (see port requirements below)</li>
                <li>Wildcards (*.domain.com) are supported in OPNsense URL Table aliases</li>
                <li>Current category filter: <strong>{SELECTED_CATEGORY.upper()}</strong> (includes: {', '.join(CATEGORY_FILTERS[SELECTED_CATEGORY])})</li>
            </ul>
        </div>

        <h2>Available Services</h2>

        <div class="section-group">
            <h3>Individual Services</h3>
            <table>
                <thead>
                    <tr>
                        <th>Service</th>
                        <th>Description</th>
                        <th>Statistics</th>
                        <th>Files</th>
                    </tr>
                </thead>
                <tbody>
"""

    # Individual services
    for service_key in ['exchange', 'sharepoint', 'teams', 'common']:
        if service_key in stats:
            service_stats = stats[service_key]
            service_info = SERVICES[service_key]
            html_content += f"""                    <tr>
                        <td><strong>{service_info['name']}</strong></td>
                        <td>{service_info['description']}</td>
                        <td>
                            <span class="badge badge-ipv4">IPv4: {service_stats['ipv4']}</span>
                            <span class="badge badge-ipv6">IPv6: {service_stats['ipv6']}</span>
                            <span class="badge badge-urls">URLs: {service_stats['urls']}</span>
                        </td>
                        <td>
                            <a href="m365_{service_key}_ipv4.txt" class="file-link">IPv4</a>
                            <a href="m365_{service_key}_ipv6.txt" class="file-link">IPv6</a>
                            <a href="m365_{service_key}_urls.txt" class="file-link">URLs</a>
                        </td>
                    </tr>
"""

    html_content += """                </tbody>
            </table>
        </div>

        <div class="section-group">
            <h3>Combined Services</h3>
            <table>
                <thead>
                    <tr>
                        <th>Service</th>
                        <th>Description</th>
                        <th>Statistics</th>
                        <th>Files</th>
                    </tr>
                </thead>
                <tbody>
"""

    # Combined services
    for service_key in ['exchange_teams', 'office_core', 'collaboration', 'all']:
        if service_key in stats:
            service_stats = stats[service_key]
            service_info = SERVICES[service_key]
            html_content += f"""                    <tr>
                        <td><strong>{service_info['name']}</strong></td>
                        <td>{service_info['description']}</td>
                        <td>
                            <span class="badge badge-ipv4">IPv4: {service_stats['ipv4']}</span>
                            <span class="badge badge-ipv6">IPv6: {service_stats['ipv6']}</span>
                            <span class="badge badge-urls">URLs: {service_stats['urls']}</span>
                        </td>
                        <td>
                            <a href="m365_{service_key}_ipv4.txt" class="file-link">IPv4</a>
                            <a href="m365_{service_key}_ipv6.txt" class="file-link">IPv6</a>
                            <a href="m365_{service_key}_urls.txt" class="file-link">URLs</a>
                        </td>
                    </tr>
"""

    html_content += """                </tbody>
            </table>
        </div>

        <h2>OPNsense Integration</h2>

        <h3>Step 1: Create URL Table Aliases</h3>
        <ol>
            <li>Log into OPNsense web interface</li>
            <li>Navigate to <strong>Firewall &rarr; Aliases</strong></li>
            <li>Click <strong>+</strong> to add a new alias</li>
            <li>Configure the alias:
                <ul>
                    <li><strong>Enabled:</strong> &#10003; (checked)</li>
                    <li><strong>Name:</strong> M365_Exchange_IPv4 (example)</li>
                    <li><strong>Type:</strong> URL Table (IPs) or URL Table (URLs)</li>
                    <li><strong>Refresh Frequency:</strong> 1 day</li>
                    <li><strong>Content:</strong> Full URL to the txt file (e.g., https://your-server/m365-lists/m365_exchange_ipv4.txt)</li>
                </ul>
            </li>
            <li>Click <strong>Save</strong> and repeat for other services</li>
        </ol>

        <h3>Step 2: Create Firewall Rules</h3>
        <ol>
            <li>Navigate to <strong>Firewall &rarr; Rules &rarr; [Your Interface]</strong></li>
            <li>Add rules to allow traffic to your M365 aliases</li>
            <li>Example rule:
                <ul>
                    <li><strong>Action:</strong> Pass</li>
                    <li><strong>Interface:</strong> LAN</li>
                    <li><strong>Protocol:</strong> TCP/UDP</li>
                    <li><strong>Source:</strong> LAN net</li>
                    <li><strong>Destination:</strong> M365_Exchange_IPv4 (your alias)</li>
                    <li><strong>Destination Port:</strong> 443, 587, 993, 995 (see port requirements)</li>
                </ul>
            </li>
        </ol>

        <h3>Step 3: Apply Changes</h3>
        <p>Click <strong>Apply Changes</strong> to activate the new rules.</p>

        <h2>Port Requirements</h2>

        <table>
            <thead>
                <tr>
                    <th>Service</th>
                    <th>Required Ports</th>
                </tr>
            </thead>
            <tbody>
"""

    for service_key, service_info in SERVICES.items():
        html_content += f"""                <tr>
                    <td><strong>{service_info['name']}</strong></td>
                    <td>{service_info['ports']}</td>
                </tr>
"""

    html_content += f"""            </tbody>
        </table>

        <h2>Automation with Cron</h2>

        <p>Set up automatic updates by adding this to your crontab:</p>

        <pre><code># Update Microsoft 365 lists daily at 2 AM
0 2 * * * /usr/bin/python3 /path/to/m365_to_opnsense.py</code></pre>

        <h2>Additional Resources</h2>

        <ul>
            <li><a href="https://learn.microsoft.com/en-us/microsoft-365/enterprise/urls-and-ip-address-ranges" target="_blank">Microsoft 365 URLs and IP address ranges (Official)</a></li>
            <li><a href="https://docs.opnsense.org/manual/aliases.html" target="_blank">OPNsense Aliases Documentation</a></li>
            <li><a href="https://learn.microsoft.com/en-us/microsoft-365/enterprise/microsoft-365-ip-web-service" target="_blank">Microsoft 365 IP Address and URL Web Service</a></li>
            <li><a href="README.md">Local README.md Documentation</a></li>
        </ul>

        <div class="timestamp">
            Generated: {timestamp}<br>
            Category Filter: {SELECTED_CATEGORY.upper()} (includes: {', '.join(CATEGORY_FILTERS[SELECTED_CATEGORY])})
        </div>
    </div>
</body>
</html>
"""

    index_path = output_dir / "index.html"
    with open(index_path, 'w', encoding='utf-8') as f:
        f.write(html_content)

    print(f"Created: {index_path}")


def create_readme(output_dir: Path):
    """
    Create a comprehensive README.md file.

    Args:
        output_dir: Directory where README will be created
    """
    readme_content = f"""# Microsoft 365 Endpoints for OPNsense

Automated conversion of Microsoft 365 endpoint data into OPNsense-compatible firewall alias lists.

## Overview

This directory contains automatically generated lists of Microsoft 365 IP addresses and URLs, formatted for use as OPNsense URL Table aliases. These lists help you create firewall rules that allow Microsoft 365 services while maintaining security.

## Available Services

### Individual Services

- **Exchange**: Exchange Online (Mail, Calendar, Contacts)
- **SharePoint**: SharePoint Online and OneDrive for Business
- **Teams**: Microsoft Teams (Chat, Meetings, Calling)
- **Common**: Common and Office Online (Shared Services)

### Combined Services

- **Exchange + Teams**: Exchange Online and Microsoft Teams combined
- **Office Core**: Exchange, SharePoint, and Common Services
- **Collaboration**: Teams and SharePoint combined
- **All Services**: All Microsoft 365 services combined

## File Format

Each service has three files:
- `m365_[service]_ipv4.txt` - IPv4 addresses in CIDR notation
- `m365_[service]_ipv6.txt` - IPv6 addresses in CIDR notation
- `m365_[service]_urls.txt` - Domain names (including wildcards)

## Category Filters

Microsoft categorizes endpoints into three types:

- **Optimize**: Critical, latency-sensitive endpoints (mostly IPs)
- **Allow**: Required for Microsoft 365 functionality (IPs + URLs)
- **Default**: Additional optional endpoints (mostly URLs)

Current filter setting: **{SELECTED_CATEGORY.upper()}**
Categories included: **{', '.join(CATEGORY_FILTERS[SELECTED_CATEGORY])}**

### Recommended Setting

Microsoft recommends using the 'default' filter (all categories) to ensure both IPs and URLs are included for complete functionality.

## OPNsense Integration

### Step 1: Create URL Table Aliases

1. Log into your OPNsense web interface
2. Navigate to **Firewall -> Aliases**
3. Click the **+** button to add a new alias
4. Configure the alias:
   - **Enabled**: checked
   - **Name**: `M365_Exchange_IPv4` (example - use descriptive names)
   - **Type**:
     - `URL Table (IPs)` for IPv4/IPv6 files
     - `URL Table (URLs)` for domain files
   - **Refresh Frequency**: `1 day` (recommended)
   - **Content**: Full URL to the txt file
     - Example: `https://your-server.com/m365-lists/m365_exchange_ipv4.txt`
   - **Description**: Brief description of the alias
5. Click **Save**
6. Repeat for each service and list type you need

### Step 2: Create Firewall Rules

1. Navigate to **Firewall -> Rules -> [Your Interface]** (e.g., LAN)
2. Click **+** to add a new rule
3. Configure the rule:
   - **Action**: Pass
   - **Interface**: LAN (or your internal interface)
   - **Protocol**: TCP/UDP (depending on service requirements)
   - **Source**: LAN net (or specific source)
   - **Destination**: Select your M365 alias (e.g., M365_Exchange_IPv4)
   - **Destination Port**: See port requirements below
   - **Description**: Descriptive name for the rule
4. Click **Save**
5. Create additional rules for IPv6 and URL aliases

### Step 3: Apply Changes

Click **Apply Changes** to activate the new aliases and rules.

## Port Requirements

Different Microsoft 365 services require different ports:

### Exchange Online
- **TCP 443**: HTTPS (Outlook on the web, EWS, Autodiscover)
- **TCP 587**: SMTP submission (authenticated)
- **TCP 993**: IMAP over SSL
- **TCP 995**: POP3 over SSL
- **TCP 25**: SMTP relay (optional)

### SharePoint Online & OneDrive
- **TCP 443**: HTTPS
- **TCP 80**: HTTP (redirects to HTTPS)

### Microsoft Teams
- **TCP 443**: HTTPS (signaling)
- **UDP 3478-3481**: Media (STUN/TURN)
- **TCP/UDP 50000-50059**: Media (fallback)

### Common Services
- **TCP 443**: HTTPS
- **TCP 80**: HTTP

## Important Notes

### Regular Updates Required

Microsoft updates their endpoint lists frequently. It's critical to:

- Refresh aliases at least **daily** (configured in OPNsense alias settings)
- Monitor OPNsense logs for blocked legitimate traffic
- Review Microsoft's change notifications

### IPv6 Support

**Do NOT block IPv6 traffic!** Microsoft 365 increasingly relies on IPv6:

- Create aliases for both IPv4 AND IPv6 lists
- Ensure your firewall rules allow IPv6
- Test connectivity for both protocol versions

### Wildcard Domain Support

URL lists contain wildcard domains (e.g., `*.office365.com`):

- OPNsense URL Table aliases support wildcards natively
- No special configuration needed
- Wildcards match all subdomains

### Testing Your Configuration

After setup:

1. Test each Microsoft 365 service (Exchange, Teams, SharePoint)
2. Check OPNsense firewall logs for blocks
3. Use Microsoft's connectivity tests:
   - Exchange: [Microsoft Remote Connectivity Analyzer](https://testconnectivity.microsoft.com/)
   - Teams: Built-in network test in Teams client
   - General: [Microsoft 365 network connectivity test](https://connectivity.office.com/)

## Automation

### Automatic List Updates

Set up a cron job to regenerate lists daily:

```bash
# Edit crontab
crontab -e

# Add this line to update lists daily at 2 AM
0 2 * * * /usr/bin/python3 /path/to/m365_to_opnsense.py
```

### OPNsense Alias Refresh

OPNsense automatically refreshes URL Table aliases based on the configured frequency. You can also manually refresh:

1. Navigate to **Firewall -> Aliases**
2. Click the refresh icon next to the alias
3. Check the alias content to verify the update

## Troubleshooting

### Aliases Not Updating

- Check cron job execution: `grep CRON /var/log/syslog`
- Verify file permissions on generated lists
- Check OPNsense can reach the URL (test with curl from OPNsense shell)

### Services Not Working

- Review firewall logs: **Firewall -> Log Files -> Live View**
- Ensure both IPv4 and IPv6 rules are in place
- Verify port requirements are met
- Check if blocked traffic matches Microsoft IP ranges

### Empty or Missing Lists

- Verify script execution completed successfully
- Check API connectivity to Microsoft endpoints
- Review script output for error messages

## Additional Resources

- [Microsoft 365 URLs and IP address ranges (Official)](https://learn.microsoft.com/en-us/microsoft-365/enterprise/urls-and-ip-address-ranges)
- [OPNsense Aliases Documentation](https://docs.opnsense.org/manual/aliases.html)
- [Microsoft 365 IP Address and URL Web Service](https://learn.microsoft.com/en-us/microsoft-365/enterprise/microsoft-365-ip-web-service)
- [Microsoft 365 Network Connectivity Principles](https://learn.microsoft.com/en-us/microsoft-365/enterprise/microsoft-365-network-connectivity-principles)

## License

MIT License - See LICENSE file for details

## Support

For issues with:
- **This script**: Open an issue on the repository
- **Microsoft 365 endpoints**: Contact Microsoft Support
- **OPNsense configuration**: Consult OPNsense documentation or forums

---

Generated: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}
Category Filter: {SELECTED_CATEGORY.upper()} (includes: {', '.join(CATEGORY_FILTERS[SELECTED_CATEGORY])})
"""

    readme_path = output_dir / "README.md"
    with open(readme_path, 'w', encoding='utf-8') as f:
        f.write(readme_content)

    print(f"Created: {readme_path}")


def print_statistics(stats: Dict):
    """
    Print formatted statistics table.

    Args:
        stats: Dictionary with statistics for each service
    """
    print("\n" + "=" * 70)
    print("Statistics:")
    print("=" * 70)

    for service_key in ['exchange', 'sharepoint', 'teams', 'common',
                        'exchange_teams', 'office_core', 'collaboration', 'all']:
        if service_key in stats:
            s = stats[service_key]
            total = s['total']
            ipv4 = s['ipv4']
            ipv6 = s['ipv6']
            urls = s['urls']
            print(f"{service_key:20s}: {total:4d} entries "
                  f"(IPv4: {ipv4:3d}, IPv6: {ipv6:3d}, URLs: {urls:3d})")

    print("=" * 70)


def main():
    """Main execution flow."""

    # Print header
    print("=" * 70)
    print("Microsoft 365 Endpoints to OPNsense Lists Converter")
    print("=" * 70)
    print(f"Category Filter: {SELECTED_CATEGORY.upper()}")
    print(f"Categories included: {', '.join(CATEGORY_FILTERS[SELECTED_CATEGORY])}")
    print(f"Output Directory: {OUTPUT_DIR}")
    print("=" * 70)

    # Validate category filter
    if SELECTED_CATEGORY not in CATEGORY_FILTERS:
        print(f"ERROR: Invalid category filter '{SELECTED_CATEGORY}'")
        print(f"Valid options: {', '.join(CATEGORY_FILTERS.keys())}")
        exit(1)

    # Create output directory
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

    # Fetch endpoint data
    data, request_id = fetch_endpoints()

    # Get categories to include
    categories = CATEGORY_FILTERS[SELECTED_CATEGORY]
    timestamp = datetime.now().strftime('%Y-%m-%d %H:%M:%S')
    categories_list = ', '.join(categories)

    # Process each service
    stats = {}

    for service_key, service_info in SERVICES.items():
        print(f"\nProcessing: {service_info['name']}")
        print(f"Description: {service_info['description']}")

        # Extract IPs and URLs for this service
        ipv4_set, ipv6_set, urls_set = extract_ips_and_urls(
            data,
            service_info['service_areas'],
            categories
        )

        # Prepare header info
        header_info = {
            'service_name': service_info['name'],
            'description': service_info['description'],
            'timestamp': timestamp,
            'category_filter': SELECTED_CATEGORY.upper(),
            'categories_list': categories_list
        }

        # Write IPv4 file
        header_info['list_type'] = 'IPv4 Addresses'
        ipv4_file = OUTPUT_DIR / f"m365_{service_key}_ipv4.txt"
        ipv4_count = write_list_file(ipv4_file, ipv4_set, header_info)
        print(f"Created: m365_{service_key}_ipv4.txt ({ipv4_count} entries)")

        # Write IPv6 file
        header_info['list_type'] = 'IPv6 Addresses'
        ipv6_file = OUTPUT_DIR / f"m365_{service_key}_ipv6.txt"
        ipv6_count = write_list_file(ipv6_file, ipv6_set, header_info)
        print(f"Created: m365_{service_key}_ipv6.txt ({ipv6_count} entries)")

        # Write URLs file
        header_info['list_type'] = 'URLs/Domains'
        urls_file = OUTPUT_DIR / f"m365_{service_key}_urls.txt"
        urls_count = write_list_file(urls_file, urls_set, header_info)
        print(f"Created: m365_{service_key}_urls.txt ({urls_count} entries)")

        # Store statistics
        total_count = ipv4_count + ipv6_count + urls_count
        stats[service_key] = {
            'total': total_count,
            'ipv4': ipv4_count,
            'ipv6': ipv6_count,
            'urls': urls_count
        }

        print(f"Total: {total_count} entries")

    # Create documentation
    print("\n" + "=" * 70)
    print("Creating documentation...")
    print("=" * 70)
    create_index_html(OUTPUT_DIR, stats)
    create_readme(OUTPUT_DIR)

    # Print completion message
    print("\n" + "=" * 70)
    print("CONVERSION COMPLETED SUCCESSFULLY!")
    print("=" * 70)
    print(f"Files location: {OUTPUT_DIR}")
    print(f"Open in browser: {OUTPUT_DIR}/index.html")
    print(f"Documentation: {OUTPUT_DIR}/README.md")

    # Print statistics
    print_statistics(stats)


if __name__ == "__main__":
    main()
