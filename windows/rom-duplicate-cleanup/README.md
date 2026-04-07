# ROM Duplicate Cleanup Script

PowerShell script for automatic cleanup of ROM collections by intelligently detecting and removing duplicates.

## What It Does

The script analyzes ROM collections and **automatically keeps only the best version** of each game:

- **Finds duplicates** based on game name (ignores region/version tags)
- **Rates quality** using ROM naming conventions
- **Deletes inferior versions** automatically
- **Saves disk space** and keeps your collection clean

## Quick Start

```powershell
# Run the script (WARNING: deletes immediately!)
.\rom-cleanup-simple.ps1 -RomPath "C:\Your\ROM\Collection"
```

## Priority System

The script uses an intelligent scoring system:

### Regions (lowest score = best)

| Tag | Region | Priority |
|-----|--------|----------|
| `(JUE)` | Japan/USA/Europe (Multi-Region) | ★★★ |
| `(UE)` | USA/Europe | ★★ |
| `(U)` | USA | ★ |
| `(E)` | Europe | — |
| `(J)` | Japan | — |

### Quality Tags

| Tag | Meaning | Rating |
|-----|---------|--------|
| `[!]` | Good Dump (verified) | Best ✅ |
| `[f]` | Fixed version | Good |
| `[p]` | Patched version | Good |
| `[o]` | Overdump | Neutral |
| `[h]` | Hack/Modification | Poor ⚠️ |
| `[t]` | Trainer (cheats) | Poor ⚠️ |
| `[a]` | Alternative version | Poor ⚠️ |
| `[c]` | Cracked version | Poor ⚠️ |
| `[b]` | Bad Dump (broken) | Worst ❌ |

### Special Handling

- `REV 01/02` — Higher revisions are preferred
- `prototype` — Prototypes scored higher
- `Beta` — Beta versions scored lower

## Example

**Before:**

```
Sonic the Hedgehog (JUE) [!].zip          ← BEST (kept)
Sonic the Hedgehog (JUE) [p1][!].zip      ← Patched (deleted)
Sonic the Hedgehog (JUE) [h1].zip         ← Hack (deleted)
Sonic the Hedgehog (E) [b1].zip           ← Bad Dump (deleted)
```

**After:**

```
Sonic the Hedgehog (JUE) [!].zip          ← Only the best version remains!
```

## Important Notes

### Safety

- ⚠️ **Create a backup** before first run!
- ⚠️ **Script deletes immediately** without confirmation
- ⚠️ **Deleted files are permanently removed**

### Requirements

- Windows PowerShell 5.1 or higher
- Write permissions in the ROM directory
- If issues occur: **Run as Administrator**

## Troubleshooting

**Execution Policy error:**
```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

**"File not found" errors:**
```powershell
# Run PowerShell as Administrator
# Right-click PowerShell → "Run as Administrator"
```

## Compatibility

Works with **all ROM formats** using standard naming conventions:

- Sega Genesis / Mega Drive
- Super Nintendo (SNES)
- Nintendo Entertainment System (NES)
- Game Boy / Game Boy Color / Game Boy Advance
- Atari, Commodore 64, etc.
