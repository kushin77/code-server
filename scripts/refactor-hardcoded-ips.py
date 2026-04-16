#!/usr/bin/env python3
################################################################################
# refactor-hardcoded-ips.py
#
# Systematically refactor hardcoded IPs to inventory-loader functions
# Part of #362 Phase 6 (Script Refactoring)
#
# Usage:
#   python3 scripts/refactor-hardcoded-ips.py --scan          # Find violations
#   python3 scripts/refactor-hardcoded-ips.py --refactor      # Auto-refactor
#   python3 scripts/refactor-hardcoded-ips.py --verify        # Check results
#
################################################################################

import os
import re
import sys
import argparse
import subprocess
from pathlib import Path
from typing import List, Dict, Tuple

# =============================================================================
# CONFIGURATION
# =============================================================================

# IP patterns to replace
IP_MAPPINGS = {
    r'192\.168\.168\.31': '$(get_host_ip primary)',
    r'192\.168\.168\.42': '$(get_host_ip replica)',
    r'192\.168\.168\.30': '$(get_vip_ip)',
    r'primary\.prod\.internal': '$(get_host_fqdn primary)',
    r'replica\.prod\.internal': '$(get_host_fqdn replica)',
    r'prod\.internal': '$(get_vip_fqdn)',
}

# Context to insert after shebang
INVENTORY_IMPORT = '''

# Load inventory (replaces hardcoded IPs with vars)
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
source "$PROJECT_DIR/scripts/lib/inventory-loader.sh"
inventory_load_production
export_inventory_vars

'''

# Paths to scan
SCAN_PATHS = [
    'scripts/',
    'terraform/',
    'config/',
]

SKIP_PATTERNS = [
    '.git/',
    '.archived/',
    'node_modules/',
    '__pycache__/',
    '*.backup',
]

# =============================================================================
# SCANNING
# =============================================================================

def should_skip(path: str) -> bool:
    """Check if path should be skipped"""
    for pattern in SKIP_PATTERNS:
        if pattern.replace('*', '') in path or path.endswith(pattern.replace('*', '')):
            return True
    return False

def find_violations(start_path: str = '.') -> Dict[str, List[Tuple[int, str]]]:
    """Scan for hardcoded IPs"""
    violations = {}
    
    for root, dirs, files in os.walk(start_path):
        # Skip directories
        dirs[:] = [d for d in dirs if not should_skip(d)]
        
        for file in files:
            if not (file.endswith('.sh') or file.endswith('.tf') or 
                   file.endswith('.yml') or file.endswith('.yaml')):
                continue
            
            file_path = os.path.join(root, file)
            if should_skip(file_path):
                continue
            
            try:
                with open(file_path, 'r', encoding='utf-8', errors='ignore') as f:
                    lines = f.readlines()
                
                file_violations = []
                for line_no, line in enumerate(lines, 1):
                    # Skip comment lines
                    if line.strip().startswith('#'):
                        continue
                    
                    # Check each IP pattern
                    for ip_pattern in IP_MAPPINGS.keys():
                        if re.search(ip_pattern, line):
                            # Skip terraform descriptions and comments
                            if file.endswith('.tf') and any(x in line.lower() for x in ['description', 'default', 'comment']):
                                continue
                            file_violations.append((line_no, line.strip()))
                
                if file_violations:
                    violations[file_path] = file_violations
            
            except (UnicodeDecodeError, IOError) as e:
                print(f"⚠️  Cannot read {file_path}: {e}")
    
    return violations

def print_violations(violations: Dict[str, List[Tuple[int, str]]]):
    """Print violation report"""
    total_violations = sum(len(v) for v in violations.values())
    
    print(f"\n📊 Found {total_violations} hardcoded IP references in {len(violations)} files:\n")
    
    for file_path, file_violations in sorted(violations.items()):
        print(f"  {file_path} ({len(file_violations)} violations)")
        for line_no, line_content in file_violations[:3]:  # Show first 3
            print(f"    Line {line_no}: {line_content[:70]}...")
        if len(file_violations) > 3:
            print(f"    ... and {len(file_violations) - 3} more")

# =============================================================================
# REFACTORING
# =============================================================================

def refactor_file(file_path: str) -> bool:
    """Refactor a single file"""
    try:
        with open(file_path, 'r', encoding='utf-8', errors='ignore') as f:
            content = f.read()
        
        original_content = content
        
        # Add inventory import if not present (for .sh files)
        if file_path.endswith('.sh'):
            # Check if inventory import already exists
            if 'inventory-loader' not in content and 'source "$PROJECT_DIR/scripts/lib' not in content:
                # Find shebang
                lines = content.split('\n')
                if lines[0].startswith('#!'):
                    # Insert after shebang
                    lines.insert(1, INVENTORY_IMPORT)
                    content = '\n'.join(lines)
        
        # Replace IP patterns
        for ip_pattern, replacement in IP_MAPPINGS.items():
            # Skip replacements in comments
            def replace_func(match):
                line_start = match.start() - match.start() % 200  # Context
                # Don't replace in comments
                if match.string[max(0, match.start() - 50):match.start()].lstrip().startswith('#'):
                    return match.group()
                return replacement
            
            content = re.sub(ip_pattern, replacement, content)
        
        # Only write if changed
        if content != original_content:
            with open(file_path, 'w', encoding='utf-8') as f:
                f.write(content)
            return True
        
        return False
    
    except (UnicodeDecodeError, IOError) as e:
        print(f"⚠️  Cannot refactor {file_path}: {e}")
        return False

def refactor_all(violations: Dict[str, List]) -> Tuple[int, int]:
    """Refactor all files with violations"""
    success_count = 0
    failed_count = 0
    
    print("\n🔄 Refactoring...")
    for file_path in sorted(violations.keys()):
        if refactor_file(file_path):
            print(f"  ✓ {file_path}")
            success_count += 1
        else:
            print(f"  ✗ {file_path}")
            failed_count += 1
    
    return success_count, failed_count

# =============================================================================
# MAIN
# =============================================================================

def main():
    parser = argparse.ArgumentParser(description='Refactor hardcoded IPs to inventory variables')
    parser.add_argument('--scan', action='store_true', help='Scan for violations only')
    parser.add_argument('--refactor', action='store_true', help='Auto-refactor files')
    parser.add_argument('--verify', action='store_true', help='Verify after refactoring')
    parser.add_argument('--path', default='.', help='Start path for scanning')
    
    args = parser.parse_args()
    
    # Default to scan if no action specified
    if not (args.scan or args.refactor or args.verify):
        args.scan = True
    
    os.chdir(os.path.dirname(os.path.abspath(__file__)) + '/../..')
    
    # Scan for violations
    print("🔍 Scanning for hardcoded IPs...")
    violations = find_violations(args.path)
    
    if not violations:
        print("✅ No hardcoded IPs found!")
        return 0
    
    print_violations(violations)
    
    if args.scan:
        print(f"\n  Total: {sum(len(v) for v in violations.values())} violations")
        print("  Run with --refactor to auto-fix")
        return 0
    
    if args.refactor:
        success, failed = refactor_all(violations)
        print(f"\n✅ Refactored: {success} files")
        if failed:
            print(f"⚠️  Failed: {failed} files")
        
        # Re-scan to verify
        print("\n🔍 Re-scanning after refactoring...")
        new_violations = find_violations(args.path)
        if new_violations:
            print(f"⚠️  Still found {sum(len(v) for v in new_violations.values())} violations:")
            print_violations(new_violations)
            return 1
        else:
            print("✅ All violations fixed!")
            return 0
    
    return 0

if __name__ == '__main__':
    sys.exit(main())
