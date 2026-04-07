# Outlook AutoComplete Cache Cleanup

PowerShell script to clean the Outlook AutoComplete cache. Optimized for NinjaRMM deployment.

## Features

- Clear AutoComplete cache (NK2 files + Stream_AutoComplete)
- Automatically close Outlook and optionally restart it
- Supports all Outlook versions (2010–365)
- Detailed logging with timestamps
- WhatIf mode for dry-run testing
- Exit codes for RMM monitoring

## Usage

**Standard deployment** (AutoComplete only):
```powershell
.\Outlook-Cache-Cleanup.ps1
```

**With Outlook restart:**
```powershell
.\Outlook-Cache-Cleanup.ps1 -RestartOutlook
```

**Clear all caches** (comprehensive):
```powershell
.\Outlook-Cache-Cleanup.ps1 -ClearAllCaches
```

**Dry-run mode** (no changes):
```powershell
.\Outlook-Cache-Cleanup.ps1 -WhatIf
```

**Combined:**
```powershell
.\Outlook-Cache-Cleanup.ps1 -ClearAllCaches -RestartOutlook
```

## RMM Deployment

> **Important:** The script must run in the **user context**, not as SYSTEM, since Outlook profiles are user-specific.

| RMM Tool | Setting |
|----------|---------|
| NinjaRMM | "Run as logged-on user" |
| Datto RMM | Enable User Context |
| Atera | Run as User |
| Kaseya/Connectwise | Deploy as User |

**Silent deployment** (no window):
```powershell
powershell.exe -ExecutionPolicy Bypass -WindowStyle Hidden -File "\\server\scripts\Outlook-Cache-Cleanup.ps1" -ClearAllCaches
```

**Log file to central location:**
```powershell
.\Outlook-Cache-Cleanup.ps1 -LogPath "\\fileserver\logs\$env:COMPUTERNAME-outlook-cleanup.log"
```

## Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Success / nothing to clean |
| 1 | Error (wrong context, Outlook could not be stopped) |
| 2 | Completed with errors |

## Log Files

Logs are stored under `%ProgramData%\NinjaRMMAgent\Logs\`. Logs older than 30 days are automatically cleaned up.
