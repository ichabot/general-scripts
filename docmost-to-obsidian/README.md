# Docmost Space Export → Obsidian Vault Converter

Converts [Docmost](https://docmost.com/) space exports into clean [Obsidian](https://obsidian.md/) vaults with proper attachment handling and link rewriting.

## Features

- **Two-phase approach**: Analyze first, convert after review
- Rewrites attachment links from `files/UUID/name` to `_attachments/name`
- Detects special content: Mermaid diagrams, Draw.io, Excalidraw, KaTeX
- Identifies broken links and empty/title-only pages
- Handles duplicate attachment filenames with UUID prefix deduplication
- Preserves folder structure and `docmost-metadata.json`
- Generates a detailed conversion report
- Windows console encoding fix included (handles non-UTF-8 terminals)

## Requirements

- Python 3.10+ (uses `match` statement syntax for type hints)
- No external dependencies (stdlib only)

## Configuration

Edit the top of `docmost_to_obsidian.py`:

```python
SOURCE_DIR = Path(r"E:\Save\ClaudProjects\Docmost")      # Docmost export folder
OUTPUT_DIR = Path(r"E:\Save\ClaudProjects\ObsidianVault") # Output Obsidian vault
ATTACHMENTS_FOLDER = "_attachments"                        # Attachment folder name
```

## Usage

### Phase 1: Analyze (safe, read-only)

```bash
python docmost_to_obsidian.py
```

This scans all spaces and generates `conversion_report.md` with:
- Summary table (pages, attachments, links, broken links, empty files)
- Link type breakdown
- Special content detection (Mermaid, Draw.io, Excalidraw, KaTeX)
- Per-space details with file lists
- Planned conversion actions

Review the report before proceeding.

### Phase 2: Convert

```bash
python docmost_to_obsidian.py --convert
```

This executes the conversion:
1. Copies all markdown files preserving folder structure
2. Moves attachments from `files/UUID/` to `_attachments/`
3. Rewrites attachment links in all markdown files
4. Preserves `docmost-metadata.json` per space
5. Generates final report with conversion log

## Output Structure

```
ObsidianVault/
├── conversion_report.md
├── Space-A/
│   ├── _attachments/
│   │   ├── image1.png
│   │   └── document.pdf
│   ├── docmost-metadata.json
│   ├── Page-1.md
│   └── Subfolder/
│       └── Page-2.md
└── Space-B/
    └── ...
```

## How It Works

### Link Rewriting

Original Docmost format:
```markdown
![Screenshot](files/abc123-def456/screenshot.png)
[Document](files/789xyz-012abc/report.pdf)
```

Converted to Obsidian format:
```markdown
![Screenshot](_attachments/screenshot.png)
[Document](_attachments/report.pdf)
```

For files in subdirectories, relative paths are computed automatically:
```markdown
<!-- In Subfolder/Page.md -->
![Image](../_attachments/screenshot.png)
```

### Duplicate Handling

If multiple attachments share the same filename, a UUID prefix is added:
```
screenshot.png          → screenshot.png
screenshot.png (dupe)   → screenshot_abc123de.png
```

## License

MIT
