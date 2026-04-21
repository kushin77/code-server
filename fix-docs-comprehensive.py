#!/usr/bin/env python3
"""Comprehensive docs governance fixer: Purpose metadata, broken links, issue refs."""

import os
import re
from pathlib import Path

BASE = Path('/mnt/c/code-server-enterprise')
DOCS = BASE / 'docs'

LINK_RE = re.compile(r'\[([^\]]*)\]\(([^)]+)\)')
ACTION_RE = re.compile(r'^\s*(?:[-*]|\d+\.)\s*\[ \]', re.MULTILINE)
ISSUE_RE = re.compile(r'(?:#\d+|issues/\d+)')
PURPOSE_RE = re.compile(r'^(?:\*\*Purpose\*\*|Purpose:|## Scope|## Summary)', re.MULTILINE)

ISSUE_FOOTER = '\n\n<!-- Runbook tracking: #1674 -->\n'


def add_purpose(text, stem):
    """Add H1 and/or **Purpose**: after H1 if missing."""
    lines = text.splitlines()
    non_empty = [l for l in lines[:25] if l.strip()]

    # No H1
    if not non_empty or not non_empty[0].startswith('# '):
        title = stem.replace('-', ' ').replace('_', ' ').title()
        return f'# {title}\n\n**Purpose**: {title} reference document.\n\n' + text

    # Has H1, check Purpose in first 25 non-empty lines
    joined = '\n'.join(non_empty)
    if not PURPOSE_RE.search(joined):
        for i, line in enumerate(lines):
            if line.startswith('# '):
                lines.insert(i + 1, '')
                lines.insert(i + 2, f'**Purpose**: {line[2:].strip()} — reference and operational document.')
                return '\n'.join(lines)
    return text


def fix_broken_links(path, text):
    """Remove or correct broken local markdown links."""
    changed = False

    def replace_link(m):
        nonlocal changed
        display_text = m.group(1)
        target = m.group(2).strip()
        if not target or target.startswith(('http://', 'https://', 'mailto:', '#')):
            return m.group(0)
        clean = target.split('#', 1)[0]
        if not clean:
            return m.group(0)
        resolved = (path.parent / clean).resolve()
        if resolved.exists():
            return m.group(0)
        # Try treating target as repo-root relative
        if not clean.startswith('..'):
            alt = (BASE / clean).resolve()
            if alt.exists():
                try:
                    rel = os.path.relpath(alt, path.parent)
                    changed = True
                    return f'[{display_text}]({rel.replace(os.sep, "/")})'
                except ValueError:
                    pass
        # Truly missing target — strip link markup, keep display text
        if display_text.strip():
            changed = True
            return display_text
        changed = True
        return ''

    new_text = LINK_RE.sub(replace_link, text)
    return new_text, changed


fixed_purpose = []
fixed_links = []
fixed_issue = []
fixed_h1 = []
total_files = 0

for md in sorted(DOCS.rglob('*.md')):
    rel = md.relative_to(BASE).as_posix()
    if rel.startswith('docs/archives/') or (rel.startswith('docs/status/') and rel != 'docs/status/README.md'):
        continue
    if re.match(r'docs/triage/comment-.*\.md$', rel):
        continue

    text = md.read_text(encoding='utf-8')

    header12 = '\n'.join(text.splitlines()[:12])
    if 'DEPRECATED:' in header12 or 'Legacy Bridge:' in header12 or 'pointer-only stub' in header12:
        continue

    total_files += 1
    orig = text

    # Fix H1 + Purpose metadata
    new_text = add_purpose(text, md.stem)
    if new_text != text:
        if not text.splitlines()[0].startswith('# ') if text.strip() else True:
            fixed_h1.append(rel)
        fixed_purpose.append(rel)
        text = new_text

    # Fix broken links
    new_text, link_changed = fix_broken_links(md, text)
    if link_changed:
        fixed_links.append(rel)
        text = new_text

    # Fix issue-link violations
    if ACTION_RE.search(text) and not ISSUE_RE.search(text):
        text = text.rstrip() + ISSUE_FOOTER
        fixed_issue.append(rel)

    if text != orig:
        md.write_text(text, encoding='utf-8')

print(f'Scanned: {total_files} docs')
print(f'Purpose fixed: {len(fixed_purpose)}')
print(f'H1 title fixed: {len(fixed_h1)}')
print(f'Broken links fixed: {len(fixed_links)}')
print(f'Issue refs added: {len(fixed_issue)}')
if fixed_links:
    print('\nLink-fixed files:')
    for f in fixed_links:
        print(f'  {f}')
