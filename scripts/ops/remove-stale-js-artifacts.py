#!/usr/bin/env python3
# @file        scripts/ops/remove-stale-js-artifacts.py
# @module      maintenance/cleanup
# @description Remove stale .js files that have .ts counterparts (Issue #1707 fix)

import os
import pathlib
import sys

def find_stale_js_files(root_dir):
    """Find all .js files that have corresponding .ts versions."""
    stale_files = []
    
    for js_file in pathlib.Path(root_dir).rglob('*.test.js'):
        ts_file = js_file.with_suffix('.ts')
        if ts_file.exists():
            stale_files.append((str(js_file), str(ts_file)))
    
    return stale_files

def remove_stale_files(stale_files):
    """Remove identified stale .js files."""
    removed = 0
    for js_path, ts_path in stale_files:
        try:
            os.remove(js_path)
            print(f"✓ Removed: {js_path}")
            removed += 1
        except Exception as e:
            print(f"✗ Error removing {js_path}: {e}")
    return removed

if __name__ == '__main__':
    root = os.getcwd()
    print(f"Scanning {root} for stale .js test artifacts...")
    
    stale = find_stale_js_files(root)
    print(f"\nFound {len(stale)} stale .js files with .ts counterparts:")
    
    for js_file, ts_file in stale:
        print(f"  {js_file}")
    
    if stale:
        print(f"\nRemoving {len(stale)} stale files...")
        removed = remove_stale_files(stale)
        print(f"\n✅ Removed {removed} stale .js files")
        sys.exit(0)
    else:
        print("\n✅ No stale .js files found")
        sys.exit(0)
