#!/usr/bin/env python3
"""
Automatically inject ERR and EXIT trap handlers into bash scripts.
Safe and robust implementation that preserves script formatting.
"""

import os
import re
import sys
from pathlib import Path

def has_trap_handlers(script_path: str) -> bool:
    """Check if script already has trap handlers."""
    with open(script_path, 'r') as f:
        content = f.read()
    return 'trap' in content and ('ERR' in content or 'EXIT' in content)

def find_insertion_point(script_path: str) -> int:
    """Find the line number after which to insert trap handlers."""
    with open(script_path, 'r') as f:
        lines = f.readlines()
    
    insertion_line = 0
    
    # Find after shebang, file header comments, and set -euo pipefail
    for i, line in enumerate(lines):
        # Skip shebang and comments at the top
        if line.startswith('#!') or (line.startswith('#') and i < 20):
            insertion_line = i + 1
            continue
        
        # Find set command
        if 'set -' in line and not line.strip().startswith('#'):
            insertion_line = i + 1
            break
    
    return insertion_line

def inject_trap_handlers(script_path: str) -> bool:
    """Inject trap handlers into a script."""
    
    if not script_path.endswith('.sh'):
        return False
    
    if not os.path.isfile(script_path):
        return False
    
    # Read shebang to verify it's bash
    with open(script_path, 'r') as f:
        first_line = f.readline()
    
    if 'bash' not in first_line and 'sh' not in first_line:
        return False
    
    # Skip if already has trap handlers
    if has_trap_handlers(script_path):
        return False
    
    with open(script_path, 'r') as f:
        lines = f.readlines()
    
    # Find insertion point
    insertion_point = find_insertion_point(script_path)
    
    # Create trap handler block
    trap_block = [
        '\n',
        '# =============================================================================\n',
        '# ERROR HANDLING & CLEANUP\n',
        '# =============================================================================\n',
        'trap \'log_error "Script failed at line $LINENO (exit code: $?)"; exit 1\' ERR\n',
        'trap \'log_info "Performing cleanup..."; rm -f /tmp/*.tmp 2>/dev/null || true\' EXIT\n',
    ]
    
    # Insert trap handlers
    new_lines = lines[:insertion_point] + trap_block + lines[insertion_point:]
    
    # Write back to file
    with open(script_path, 'w') as f:
        f.writelines(new_lines)
    
    return True

def main():
    """Main entry point."""
    repo_root = Path(__file__).parent.parent.parent
    
    updated = 0
    skipped = 0
    failed = 0
    
    # Directories to process
    dirs_to_process = [
        repo_root / 'scripts' / 'ops',
        repo_root / 'scripts' / 'ci',
        repo_root / 'scripts' / 'edge-agent',
    ]
    
    for directory in dirs_to_process:
        if not directory.exists():
            continue
        
        print(f"Processing {directory}...")
        
        for script_path in sorted(directory.glob('*.sh')):
            try:
                if inject_trap_handlers(str(script_path)):
                    print(f"✓ Updated: {script_path.name}")
                    updated += 1
                else:
                    skipped += 1
            except Exception as e:
                print(f"✗ Failed: {script_path.name} - {e}")
                failed += 1
    
    print(f"\n✓ Updated: {updated}")
    print(f"⊘ Skipped: {skipped}")
    print(f"✗ Failed: {failed}")
    
    return 0 if failed == 0 else 1

if __name__ == '__main__':
    sys.exit(main())
