#!/usr/bin/env python3
"""
Automated logger migration script - updates print() statements to use centralized logger
"""

import re
import sys
from pathlib import Path

# Files to update (relative to repo root)
FILES_TO_UPDATE = [
    "apps/extensions/statusbar-tiles/api-clients.py",
    "apps/extensions/shared-clipboard/storage.py",
    "apps/auth-server/src/config.py",
    "apps/env-provisioner/provisioner.py",
    "apps/activity_feed/consumer.py",
    "apps/event-bus/event_envelope.py",
    "apps/reputation_engine/models.py",
    "apps/execution-scheduler/cost_tracker.py",
    "apps/execution-scheduler/monitors.py",
    "apps/memory-engine/agent_learnings.py",
    "apps/memory-engine/seed.py",
]

REPO_ROOT = Path("/home/akushnir/code-server")

def add_logger_import(content: str) -> str:
    """Add logger import if not already present."""
    if "from apps._shared.python.logging import get_logger" in content:
        return content  # Already imported
    
    # Find the import section and add after other imports
    lines = content.split('\n')
    insert_index = 0
    
    # Find last import line
    for i, line in enumerate(lines):
        if line.startswith('import ') or line.startswith('from '):
            insert_index = i + 1
    
    # Insert logger import and initialization
    insert_lines = [
        "",
        "from apps._shared.python.logging import get_logger",
        "",
        "logger = get_logger(__name__)"
    ]
    
    lines = lines[:insert_index] + insert_lines + lines[insert_index:]
    return '\n'.join(lines)

def replace_print_statements(content: str) -> str:
    """Replace print() statements with logger calls."""
    
    # Replace print(f"Error: ...") with logger.error(...)
    content = re.sub(
        r'print\(f"(Error|ERROR)[:\s]*([^"]+)"\)',
        r'logger.error(f"\2")',
        content
    )
    
    # Replace print(f"Warning: ...") with logger.warning(...)
    content = re.sub(
        r'print\(f"(Warning|WARNING)[:\s]*([^"]+)"\)',
        r'logger.warning(f"\2")',
        content
    )
    
    # Replace print(f"Success: ...") or print(f"✓ ...") with logger.success(...)
    content = re.sub(
        r'print\(f"(✓|Success|SUCCESS)[:\s]*([^"]+)"\)',
        r'logger.success(f"\2")',
        content
    )
    
    # Replace print(f"Debug: ...") with logger.debug(...)
    content = re.sub(
        r'print\(f"(Debug|DEBUG)[:\s]*([^"]+)"\)',
        r'logger.debug(f"\2")',
        content
    )
    
    # Replace remaining print(f"...") with logger.info(...)
    content = re.sub(
        r'print\(f"([^"]+)"\)',
        r'logger.info(f"\1")',
        content
    )
    
    # Replace print(...) (non-f-string) with logger.info(...)
    content = re.sub(
        r'print\(([^)]+)\)',
        r'logger.info(\1)',
        content
    )
    
    return content

def update_file(file_path: Path) -> tuple[bool, int]:
    """Update a single file. Returns (success, print_count)."""
    try:
        content = file_path.read_text()
        
        # Count original print statements
        print_count = len(re.findall(r'print\(', content))
        
        if print_count == 0:
            return True, 0  # No prints to update
        
        # Update content
        content = add_logger_import(content)
        content = replace_print_statements(content)
        
        # Write back
        file_path.write_text(content)
        
        return True, print_count
    except Exception as e:
        print(f"Error updating {file_path}: {e}", file=sys.stderr)
        return False, 0

def main():
    """Main entry point."""
    total_files = 0
    updated_files = 0
    total_prints = 0
    
    for file_rel in FILES_TO_UPDATE:
        file_path = REPO_ROOT / file_rel
        
        if not file_path.exists():
            print(f"⚠  Skipping (not found): {file_rel}")
            continue
        
        success, print_count = update_file(file_path)
        total_files += 1
        
        if success:
            updated_files += 1
            total_prints += print_count
            if print_count > 0:
                print(f"✓  Updated {file_rel} ({print_count} prints)")
            else:
                print(f"⊘  Skipped {file_rel} (no prints)")
        else:
            print(f"✗  Failed to update {file_rel}")
    
    # Summary
    print(f"\n=== Summary ===")
    print(f"Files processed: {total_files}")
    print(f"Files updated: {updated_files}")
    print(f"Total print() statements replaced: {total_prints}")
    
    if updated_files == total_files:
        print("✅ All files updated successfully")
        return 0
    else:
        print(f"⚠  Some files failed or not found")
        return 1

if __name__ == "__main__":
    sys.exit(main())
