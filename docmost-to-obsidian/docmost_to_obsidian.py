#!/usr/bin/env python3
"""
Docmost Space Export → Obsidian Vault Converter

Two-phase approach:
  Phase 1: Analyze and generate report (always runs)
  Phase 2: Convert after user confirmation

Usage:
  python docmost_to_obsidian.py                  # Phase 1: Analyze only
  python docmost_to_obsidian.py --convert        # Phase 2: Run conversion
"""

import io
import json
import os
import re
import shutil
import sys
import urllib.parse

# Fix console encoding on Windows
if sys.stdout.encoding and sys.stdout.encoding.lower() != "utf-8":
    sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")
    sys.stderr = io.TextIOWrapper(sys.stderr.buffer, encoding="utf-8", errors="replace")
from dataclasses import dataclass, field
from pathlib import Path
from typing import Optional

# --- Configuration ---
SOURCE_DIR = Path(r"E:\Save\ClaudProjects\Docmost")
OUTPUT_DIR = Path(r"E:\Save\ClaudProjects\ObsidianVault")
REPORT_NAME = "conversion_report.md"
ATTACHMENTS_FOLDER = "_attachments"

# --- Data Classes ---

@dataclass
class LinkInfo:
    file: str
    line_num: int
    link_type: str  # 'attachment', 'image', 'external', 'anchor', 'internal', 'broken'
    original: str
    target: str
    resolved: Optional[str] = None


@dataclass
class SpaceAnalysis:
    name: str
    total_pages: int = 0
    md_files: list = field(default_factory=list)
    links: list = field(default_factory=list)
    broken_links: list = field(default_factory=list)
    attachment_files: list = field(default_factory=list)
    empty_files: list = field(default_factory=list)
    metadata: dict = field(default_factory=dict)
    mermaid_blocks: int = 0
    drawio_refs: int = 0
    excalidraw_refs: int = 0
    katex_blocks: int = 0
    has_metadata_json: bool = False


# --- Phase 1: Analysis ---

def discover_spaces(source: Path) -> list[str]:
    """Find all space directories (contain docmost-metadata.json or .md files)."""
    spaces = []
    for entry in sorted(source.iterdir()):
        if entry.is_dir():
            has_md = any(entry.rglob("*.md"))
            has_meta = (entry / "docmost-metadata.json").exists()
            if has_md or has_meta:
                spaces.append(entry.name)
    return spaces


def load_metadata(space_path: Path) -> dict:
    """Load docmost-metadata.json for a space."""
    meta_file = space_path / "docmost-metadata.json"
    if meta_file.exists():
        with open(meta_file, "r", encoding="utf-8") as f:
            return json.load(f)
    return {}


def build_page_lookup(metadata: dict) -> dict:
    """Build lookup from pageId/slugId to filename from metadata."""
    lookup = {}
    pages = metadata.get("pages", {})
    for encoded_filename, info in pages.items():
        filename = urllib.parse.unquote(encoded_filename)
        page_id = info.get("pageId", "")
        slug_id = info.get("slugId", "")
        if page_id:
            lookup[page_id] = filename
        if slug_id:
            lookup[slug_id] = filename
        # Also map the bare filename without .md
        stem = filename.rsplit(".", 1)[0] if filename.endswith(".md") else filename
        lookup[stem] = filename
    return lookup


def analyze_file_links(filepath: Path, space_path: Path) -> tuple[list[LinkInfo], int, int, int, int]:
    """Analyze all links and special content in a markdown file."""
    links = []
    mermaid = drawio = excalidraw = katex = 0
    rel_path = str(filepath.relative_to(space_path))

    try:
        content = filepath.read_text(encoding="utf-8")
    except (UnicodeDecodeError, OSError):
        return links, 0, 0, 0, 0

    lines = content.split("\n")
    in_code_block = False
    code_lang = ""

    for line_num, line in enumerate(lines, 1):
        # Track code blocks
        if line.strip().startswith("```"):
            if in_code_block:
                in_code_block = False
                code_lang = ""
            else:
                in_code_block = True
                code_lang = line.strip().lstrip("`").strip().lower()
                if code_lang == "mermaid":
                    mermaid += 1

        if in_code_block:
            continue

        # KaTeX: $$ blocks or inline $...$
        if "$$" in line:
            katex += line.count("$$") // 2
        elif re.search(r'(?<!\$)\$[^$\n]+\$(?!\$)', line):
            katex += 1

        # Draw.io / Excalidraw
        if re.search(r'drawio|draw\.io', line, re.IGNORECASE):
            drawio += 1
        if re.search(r'excalidraw', line, re.IGNORECASE):
            excalidraw += 1

        # Find markdown links: [text](url) and ![alt](url)
        for match in re.finditer(r'(!?\[([^\]]*)\]\(([^)]+)\))', line):
            full_match = match.group(1)
            _text = match.group(2)
            target = match.group(3)
            is_image = full_match.startswith("!")

            if target.startswith("#"):
                link_type = "anchor"
            elif target.startswith(("http://", "https://", "mailto:")):
                link_type = "external_image" if is_image else "external"
            elif target.startswith("files/"):
                link_type = "attachment_image" if is_image else "attachment"
            elif target.startswith("/api/files/"):
                link_type = "api_file"
            else:
                link_type = "internal"

            info = LinkInfo(
                file=rel_path,
                line_num=line_num,
                link_type=link_type,
                original=full_match,
                target=target,
            )

            # Check if attachment file exists
            if link_type in ("attachment", "attachment_image", "api_file"):
                resolved = space_path / filepath.parent.relative_to(space_path) / target
                if not resolved.exists():
                    # Try from space root
                    resolved = space_path / target
                info.resolved = str(resolved) if resolved.exists() else None
                if not resolved.exists():
                    info.link_type = "broken_" + link_type

            links.append(info)

    return links, mermaid, drawio, excalidraw, katex


def is_empty_or_metadata_only(filepath: Path) -> bool:
    """Check if a file is essentially empty or only has a title."""
    try:
        content = filepath.read_text(encoding="utf-8").strip()
    except (UnicodeDecodeError, OSError):
        return True

    if not content:
        return True

    # Only a heading with no real content
    lines = [l.strip() for l in content.split("\n") if l.strip()]
    if len(lines) <= 1 and all(l.startswith("#") for l in lines):
        return True

    return False


def analyze_space(space_name: str) -> SpaceAnalysis:
    """Full analysis of a single space."""
    space_path = SOURCE_DIR / space_name
    analysis = SpaceAnalysis(name=space_name)

    # Load metadata
    meta = load_metadata(space_path)
    analysis.metadata = meta
    analysis.has_metadata_json = (space_path / "docmost-metadata.json").exists()

    # Find all markdown files
    md_files = sorted(space_path.rglob("*.md"))
    analysis.md_files = [str(f.relative_to(space_path)) for f in md_files]
    analysis.total_pages = len(md_files)

    # Find all attachment files (in files/ subdirs)
    for f in space_path.rglob("*"):
        if f.is_file() and "files/" in str(f.relative_to(space_path)).replace("\\", "/"):
            analysis.attachment_files.append(str(f.relative_to(space_path)))

    # Analyze each file
    for md_file in md_files:
        links, mermaid, drawio, excalidraw, katex = analyze_file_links(md_file, space_path)
        analysis.links.extend(links)
        analysis.mermaid_blocks += mermaid
        analysis.drawio_refs += drawio
        analysis.excalidraw_refs += excalidraw
        analysis.katex_blocks += katex

        if is_empty_or_metadata_only(md_file):
            analysis.empty_files.append(str(md_file.relative_to(space_path)))

    analysis.broken_links = [l for l in analysis.links if l.link_type.startswith("broken_")]

    return analysis


def generate_report(analyses: list[SpaceAnalysis]) -> str:
    """Generate the full analysis report as markdown."""
    lines = []
    lines.append("# Docmost → Obsidian Conversion Report\n")
    lines.append(f"**Source:** `{SOURCE_DIR}`  ")
    lines.append(f"**Target:** `{OUTPUT_DIR}`  ")
    lines.append(f"**Spaces found:** {len(analyses)}\n")

    # Summary table
    lines.append("## Summary\n")
    lines.append("| Space | Pages | Attachments | Links | Broken Links | Empty Files |")
    lines.append("|-------|-------|-------------|-------|-------------|-------------|")
    total_pages = total_attach = total_links = total_broken = total_empty = 0
    for a in analyses:
        broken = len(a.broken_links)
        lines.append(f"| {a.name} | {a.total_pages} | {len(a.attachment_files)} | {len(a.links)} | {broken} | {len(a.empty_files)} |")
        total_pages += a.total_pages
        total_attach += len(a.attachment_files)
        total_links += len(a.links)
        total_broken += broken
        total_empty += len(a.empty_files)
    lines.append(f"| **Total** | **{total_pages}** | **{total_attach}** | **{total_links}** | **{total_broken}** | **{total_empty}** |")
    lines.append("")

    # Link type breakdown
    lines.append("## Link Types Found\n")
    link_types = {}
    for a in analyses:
        for l in a.links:
            lt = l.link_type.replace("broken_", "broken: ")
            link_types[lt] = link_types.get(lt, 0) + 1
    if link_types:
        lines.append("| Type | Count |")
        lines.append("|------|-------|")
        for lt, count in sorted(link_types.items()):
            lines.append(f"| {lt} | {count} |")
    else:
        lines.append("*No links found.*")
    lines.append("")

    # Special content
    has_special = any(a.mermaid_blocks or a.drawio_refs or a.excalidraw_refs or a.katex_blocks for a in analyses)
    if has_special:
        lines.append("## Special Content\n")
        lines.append("| Space | Mermaid | Draw.io | Excalidraw | KaTeX |")
        lines.append("|-------|---------|---------|------------|-------|")
        for a in analyses:
            if a.mermaid_blocks or a.drawio_refs or a.excalidraw_refs or a.katex_blocks:
                lines.append(f"| {a.name} | {a.mermaid_blocks} | {a.drawio_refs} | {a.excalidraw_refs} | {a.katex_blocks} |")
    else:
        lines.append("## Special Content\n")
        lines.append("*No Mermaid, Draw.io, Excalidraw, or KaTeX content found.*\n")

    # Per-space details
    for a in analyses:
        lines.append(f"\n---\n\n## Space: {a.name}\n")
        lines.append(f"**Pages:** {a.total_pages}  ")
        lines.append(f"**Metadata JSON:** {'Yes' if a.has_metadata_json else 'No'}  ")
        lines.append(f"**Docmost version:** {a.metadata.get('version', 'unknown')}  ")
        lines.append(f"**Exported at:** {a.metadata.get('exportedAt', 'unknown')}\n")

        # File list
        lines.append("### Pages\n")
        for f in a.md_files:
            marker = " *(empty/title-only)*" if f in a.empty_files else ""
            lines.append(f"- `{f}`{marker}")
        lines.append("")

        # Attachments
        if a.attachment_files:
            lines.append("### Attachments\n")
            for f in a.attachment_files:
                lines.append(f"- `{f}`")
            lines.append("")

        # Broken links
        if a.broken_links:
            lines.append("### Broken Links\n")
            for l in a.broken_links:
                lines.append(f"- **{l.file}** (line {l.line_num}): `{l.target}`")
            lines.append("")

        # Empty files
        if a.empty_files:
            lines.append("### Empty / Title-Only Files\n")
            for f in a.empty_files:
                lines.append(f"- `{f}`")
            lines.append("")

    # Planned conversions
    lines.append("\n---\n\n## Planned Conversion Actions\n")
    lines.append("1. **Copy** all markdown files preserving folder structure")
    lines.append("2. **Move attachments** from `files/UUID/` to `_attachments/` per space")
    lines.append("3. **Rewrite attachment links** from `files/UUID/filename` to `_attachments/filename`")
    lines.append("   - Handle duplicate filenames by prepending UUID prefix")
    lines.append("4. **Preserve** `docmost-metadata.json` in each space (not linked in vault)")
    lines.append("5. **Flag** empty/title-only files in report")
    lines.append("6. **Generate** this report as `conversion_report.md` in vault root\n")
    lines.append("Run with `--convert` to execute the conversion.\n")

    return "\n".join(lines)


# --- Phase 2: Conversion ---

def build_attachment_map(space_path: Path) -> dict[str, Path]:
    """Map original files/UUID/name paths to unique _attachments/name paths.

    Returns dict: original_relative_path -> new_filename (just the name, goes in _attachments/)
    """
    att_map = {}
    seen_names = {}  # filename -> count for dedup

    for f in sorted(space_path.rglob("*")):
        if not f.is_file():
            continue
        rel = f.relative_to(space_path)
        rel_posix = rel.as_posix()
        if not rel_posix.startswith("files/"):
            continue

        name = f.name
        if name in seen_names:
            seen_names[name] += 1
            stem = f.stem
            suffix = f.suffix
            # Extract UUID from path for dedup
            parts = rel_posix.split("/")
            uuid_part = parts[1][:8] if len(parts) > 1 else str(seen_names[name])
            name = f"{stem}_{uuid_part}{suffix}"
        else:
            seen_names[name] = 1

        att_map[rel_posix] = name

    return att_map


def rewrite_links(content: str, att_map: dict[str, str], md_rel_dir: str) -> tuple[str, list[str]]:
    """Rewrite attachment links in markdown content.

    Args:
        content: Markdown file content
        att_map: Mapping from original files/UUID/name to new filename in _attachments
        md_rel_dir: Relative directory of the .md file within the space (for computing relative paths)

    Returns:
        (new_content, list_of_changes)
    """
    changes = []

    def replace_link(match):
        prefix = match.group(1)  # '!' or ''
        text = match.group(2)
        target = match.group(3)

        # Normalize target path
        target_normalized = target.replace("\\", "/")

        # Check if this is an attachment link
        if target_normalized.startswith("files/"):
            # Find in attachment map
            if target_normalized in att_map:
                new_name = att_map[target_normalized]
                # Compute relative path from md file to _attachments/
                depth = len(Path(md_rel_dir).parts) if md_rel_dir and md_rel_dir != "." else 0
                up = "../" * depth
                new_target = f"{up}{ATTACHMENTS_FOLDER}/{new_name}"
                changes.append(f"  Link: `{target}` -> `{new_target}`")
                return f"{prefix}[{text}]({new_target})"
            else:
                # Attachment file missing - keep original, noted as broken
                changes.append(f"  BROKEN: `{target}` (file not found)")
                return match.group(0)

        return match.group(0)

    new_content = re.sub(r'(!?)\[([^\]]*)\]\(([^)]+)\)', replace_link, content)
    return new_content, changes


def convert_spaces(analyses: list[SpaceAnalysis]) -> str:
    """Execute the conversion. Returns conversion log."""
    log_lines = []

    # Clean output dir
    if OUTPUT_DIR.exists():
        shutil.rmtree(OUTPUT_DIR)
    OUTPUT_DIR.mkdir(parents=True)

    for analysis in analyses:
        space_name = analysis.name
        space_src = SOURCE_DIR / space_name
        space_dst = OUTPUT_DIR / space_name

        log_lines.append(f"\n## Space: {space_name}\n")

        # Build attachment map
        att_map = build_attachment_map(space_src)

        # Copy and rewrite markdown files
        md_count = 0
        for md_file in space_src.rglob("*.md"):
            rel = md_file.relative_to(space_src)
            rel_posix = rel.as_posix()

            # Skip files inside files/ directories (not actual pages)
            if rel_posix.startswith("files/"):
                continue

            dst_file = space_dst / rel
            dst_file.parent.mkdir(parents=True, exist_ok=True)

            try:
                content = md_file.read_text(encoding="utf-8")
            except (UnicodeDecodeError, OSError) as e:
                log_lines.append(f"- SKIP `{rel_posix}`: {e}")
                continue

            md_rel_dir = str(rel.parent) if str(rel.parent) != "." else ""
            new_content, changes = rewrite_links(content, att_map, md_rel_dir)

            dst_file.write_text(new_content, encoding="utf-8")
            md_count += 1

            if changes:
                log_lines.append(f"- `{rel_posix}` - {len(changes)} link(s) rewritten:")
                log_lines.extend(changes)

        log_lines.append(f"\n**{md_count} pages copied.**")

        # Copy attachments to _attachments/
        if att_map:
            att_dst = space_dst / ATTACHMENTS_FOLDER
            att_dst.mkdir(parents=True, exist_ok=True)
            att_count = 0
            for orig_path, new_name in att_map.items():
                src_file = space_src / orig_path
                if src_file.exists():
                    shutil.copy2(src_file, att_dst / new_name)
                    att_count += 1
            log_lines.append(f"**{att_count} attachments copied to `{ATTACHMENTS_FOLDER}/`.**")

        # Copy metadata JSON (preserve but don't integrate)
        meta_src = space_src / "docmost-metadata.json"
        if meta_src.exists():
            shutil.copy2(meta_src, space_dst / "docmost-metadata.json")
            log_lines.append("**docmost-metadata.json preserved.**")

    return "\n".join(log_lines)


# --- Main ---

def main():
    do_convert = "--convert" in sys.argv

    print(f"Scanning spaces in: {SOURCE_DIR}\n")

    spaces = discover_spaces(SOURCE_DIR)
    if not spaces:
        print("No spaces found!")
        sys.exit(1)

    print(f"Found {len(spaces)} space(s): {', '.join(spaces)}\n")

    # Phase 1: Analysis
    analyses = [analyze_space(s) for s in spaces]
    report = generate_report(analyses)

    # Always write report to source dir first (for review)
    preview_report = SOURCE_DIR / REPORT_NAME
    preview_report.write_text(report, encoding="utf-8")
    print(f"Analysis report written to: {preview_report}\n")

    if not do_convert:
        print("=" * 60)
        try:
            print(report)
        except UnicodeEncodeError:
            # Fallback for consoles that can't handle unicode
            print(report.encode("ascii", errors="replace").decode("ascii"))
        print("=" * 60)
        print(f"\nTo proceed with conversion, run:")
        print(f"  python {sys.argv[0]} --convert")
        return

    # Phase 2: Conversion
    print("Starting conversion...\n")
    conversion_log = convert_spaces(analyses)

    # Write final report with conversion log appended
    final_report = report + "\n\n---\n\n# Conversion Log\n" + conversion_log
    report_dst = OUTPUT_DIR / REPORT_NAME
    report_dst.write_text(final_report, encoding="utf-8")

    # Also copy preview report location
    preview_report.write_text(final_report, encoding="utf-8")

    print(conversion_log)
    print(f"\nConversion complete!")
    print(f"  Vault: {OUTPUT_DIR}")
    print(f"  Report: {report_dst}")


if __name__ == "__main__":
    main()
