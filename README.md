# General Scripts

A collection of general-purpose utility scripts — converters, automation tools, and helpers.

## Scripts

### [docmost-to-obsidian](docmost-to-obsidian/)

**Docmost Space Export → Obsidian Vault Converter**

Two-phase tool that converts Docmost space exports into clean Obsidian vaults:
- **Phase 1** (Analyze): Scans spaces, generates a detailed report of pages, links, attachments, and special content
- **Phase 2** (Convert): Copies files, rewrites attachment links, deduplicates filenames, preserves metadata

**Features:**
- Rewrites `files/UUID/name` attachment paths to `_attachments/name`
- Detects Mermaid, Draw.io, Excalidraw, and KaTeX content
- Identifies broken links and empty/title-only pages
- Handles duplicate attachment filenames with UUID prefixes
- Windows console encoding fix included

**Quick Start:**
```bash
cd docmost-to-obsidian
python docmost_to_obsidian.py              # Phase 1: Analyze
python docmost_to_obsidian.py --convert    # Phase 2: Convert
```

---

## Structure

Each script lives in its own directory with its own documentation:

```
general-scripts/
├── README.md
├── LICENSE
├── docmost-to-obsidian/
│   ├── docmost_to_obsidian.py
│   └── README.md
└── ...                        # More scripts coming soon
```

## License

MIT License — see [LICENSE](LICENSE) for details.
