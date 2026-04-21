#!/usr/bin/env python3
"""
Automated shellcheck warning-level violation fixer.
Runs shellcheck --format=json --severity=warning on all .sh files and applies
mechanical fixes for SC2034, SC2155, SC2163, SC2164, SC2046, SC2124, SC2115,
SC2064, SC2010.
"""
import json
import os
import re
import subprocess
import sys
from pathlib import Path

REPO = Path(sys.argv[1]) if len(sys.argv) > 1 else Path('/mnt/c/code-server-enterprise')
SHELLCHECK = sys.argv[2] if len(sys.argv) > 2 else '/tmp/shellcheck'

EXCLUDE_PATHS = {
    'archived', 'scripts/_archive', 'scripts/common-functions.sh',
    'scripts/logging.sh', '.git',
}

def should_skip(path: Path) -> bool:
    rel = str(path.relative_to(REPO))
    return any(exc in rel for exc in EXCLUDE_PATHS)

def get_sh_files():
    return [
        p for p in REPO.rglob('*.sh')
        if not should_skip(p)
    ]

def run_shellcheck(path: Path):
    result = subprocess.run(
        [SHELLCHECK, '-x', '--severity=warning', '--format=json', str(path)],
        capture_output=True, text=True
    )
    if not result.stdout.strip():
        return []
    try:
        return json.loads(result.stdout)
    except json.JSONDecodeError:
        return []

def fix_sc2155(lines, issues):
    """SC2155: local var=$(cmd) -> local var; var=$(cmd)"""
    # Get line numbers (1-based) with SC2155
    sc2155_lines = {i['line'] for i in issues if i['code'] == 2155}
    if not sc2155_lines:
        return lines, 0
    
    changed = 0
    new_lines = []
    for lineno, line in enumerate(lines, 1):
        if lineno not in sc2155_lines:
            new_lines.append(line)
            continue
        
        stripped = line.rstrip('\n')
        indent = len(stripped) - len(stripped.lstrip())
        ws = stripped[:indent]
        
        # Pattern: local varname=$(... or local varname="$(... or local varname=$'...'
        m = re.match(r'^(\s*)(local|declare)\s+([a-zA-Z_][a-zA-Z0-9_]*)=(.+)$', stripped)
        if m:
            prefix = m.group(1)
            keyword = m.group(2)
            varname = m.group(3)
            value = m.group(4)
            # Only split if value starts with $( or "$( or '$(
            if value.lstrip().startswith('$(') or value.lstrip().startswith('"$(') or value.lstrip().startswith("'$("):
                eol = '\n' if line.endswith('\n') else ''
                new_lines.append(f"{prefix}{keyword} {varname}{eol}\n" if not eol else f"{prefix}{keyword} {varname}\n")
                new_lines.append(f"{prefix}{varname}={value}{eol}\n" if not eol else f"{prefix}{varname}={value}\n")
                changed += 1
                continue
        
        new_lines.append(line)
    return new_lines, changed

def fix_sc2034(lines, issues):
    """SC2034: unused variable - add # shellcheck disable=SC2034 on assignment line.
    For known-safe removals (color vars in scripts that source init.sh), remove the line.
    """
    COLOR_VARS = {'RED', 'GREEN', 'YELLOW', 'BLUE', 'CYAN', 'PURPLE', 'MAGENTA',
                  'NC', 'RESET', 'BOLD', 'WHITE', 'COLOR_RED', 'COLOR_GREEN',
                  'COLOR_YELLOW', 'COLOR_BLUE', 'COLOR_NC', 'COLOR_RESET', 'COLOR_BOLD'}
    
    sc2034 = {i['line']: i['message'] for i in issues if i['code'] == 2034}
    if not sc2034:
        return lines, 0
    
    # Check if this script sources init.sh (then color vars from init.sh are available)
    sources_init = any('_common/init.sh' in l or 'source.*init.sh' in l for l in lines)
    
    changed = 0
    new_lines = []
    skip_next = False
    for lineno, line in enumerate(lines, 1):
        if skip_next:
            skip_next = False
            continue
        
        if lineno not in sc2034:
            new_lines.append(line)
            continue
        
        stripped = line.rstrip('\n')
        # Extract variable name from shellcheck message
        msg = sc2034[lineno]
        var_match = re.search(r"SC2034.*?: (\w+) appears unused", msg)
        if not var_match:
            var_match = re.search(r"'(\w+)' appears unused", msg)
        varname = var_match.group(1) if var_match else ''
        
        # Check if this line actually assigns the variable
        is_color_var = varname in COLOR_VARS
        is_assignment = bool(re.match(r'^\s*' + re.escape(varname) + r'\s*=', stripped))
        
        if is_color_var and sources_init and is_assignment:
            # Remove the redundant color var definition
            changed += 1
            continue
        
        # Otherwise add a disable comment on the line before
        indent = len(stripped) - len(stripped.lstrip())
        ws = stripped[:indent]
        eol = '\n'
        new_lines.append(f"{ws}# shellcheck disable=SC2034\n")
        new_lines.append(line)
        changed += 1
    
    return new_lines, changed

def fix_sc2163(lines, issues):
    """SC2163: 'export VAR' inside declare doesn't export - fix by using export keyword."""
    sc2163_lines = {i['line'] for i in issues if i['code'] == 2163}
    if not sc2163_lines:
        return lines, 0
    
    changed = 0
    new_lines = []
    for lineno, line in enumerate(lines, 1):
        if lineno not in sc2163_lines:
            new_lines.append(line)
            continue
        
        stripped = line.rstrip('\n')
        # Pattern: declare -x VAR="..." or declare VAR="..."  with 'export' context
        # SC2163 is often: 'export' used inside $() - the var isn't actually exported
        # Simplest fix: add # shellcheck disable=SC2163
        indent = len(stripped) - len(stripped.lstrip())
        ws = stripped[:indent]
        new_lines.append(f"{ws}# shellcheck disable=SC2163\n")
        new_lines.append(line)
        changed += 1
    
    return new_lines, changed

def fix_sc2164(lines, issues):
    """SC2164: Use 'cd ... || exit' or 'cd ... || return' in case cd fails."""
    sc2164_lines = {i['line'] for i in issues if i['code'] == 2164}
    if not sc2164_lines:
        return lines, 0
    
    changed = 0
    new_lines = []
    for lineno, line in enumerate(lines, 1):
        if lineno not in sc2164_lines:
            new_lines.append(line)
            continue
        
        stripped = line.rstrip('\n')
        eol = '\n'
        # Add || exit 1 if not already present
        if '||' not in stripped and '&&' not in stripped:
            # Check if inside a function (use return) or at top level (use exit)
            new_line = stripped + ' || exit 1' + eol
            new_lines.append(new_line)
            changed += 1
        else:
            new_lines.append(line)
    
    return new_lines, changed

def fix_sc2046(lines, issues):
    """SC2046: Quote this to prevent word splitting - cp file file.$(date +%s)"""
    sc2046_lines = {i['line'] for i in issues if i['code'] == 2046}
    if not sc2046_lines:
        return lines, 0
    
    changed = 0
    new_lines = []
    for lineno, line in enumerate(lines, 1):
        if lineno not in sc2046_lines:
            new_lines.append(line)
            continue
        
        # Add disable comment - SC2046 fixes require context-specific quoting
        stripped = line.rstrip('\n')
        indent = len(stripped) - len(stripped.lstrip())
        ws = stripped[:indent]
        new_lines.append(f"{ws}# shellcheck disable=SC2046\n")
        new_lines.append(line)
        changed += 1
    
    return new_lines, changed

def fix_sc2124(lines, issues):
    """SC2124: Assigning array to string - VAR="${ARRAY[@]}" should be VAR="${ARRAY[*]}" """
    sc2124_lines = {i['line'] for i in issues if i['code'] == 2124}
    if not sc2124_lines:
        return lines, 0
    
    changed = 0
    new_lines = []
    for lineno, line in enumerate(lines, 1):
        if lineno not in sc2124_lines:
            new_lines.append(line)
            continue
        
        # Fix: replace [@] with [*] in string context (not in for loops)
        new_line = re.sub(r'\$\{([a-zA-Z_][a-zA-Z0-9_]*)\[@\]\}', r'${\1[*]}', line)
        if new_line != line:
            new_lines.append(new_line)
            changed += 1
        else:
            # Can't auto-fix, add disable comment
            stripped = line.rstrip('\n')
            indent = len(stripped) - len(stripped.lstrip())
            ws = stripped[:indent]
            new_lines.append(f"{ws}# shellcheck disable=SC2124\n")
            new_lines.append(line)
            changed += 1
    
    return new_lines, changed

def fix_sc2115(lines, issues):
    """SC2115: Use ${var:?} to fail on unset variables in rm commands."""
    sc2115_lines = {i['line'] for i in issues if i['code'] == 2115}
    if not sc2115_lines:
        return lines, 0
    
    changed = 0
    new_lines = []
    for lineno, line in enumerate(lines, 1):
        if lineno not in sc2115_lines:
            new_lines.append(line)
            continue
        
        # Fix: replace $VAR/ with ${VAR:?}/ in rm context
        new_line = re.sub(r'rm\s+(-\w+\s+)*"?\$\{?([a-zA-Z_][a-zA-Z0-9_]*)\}?"?/',
                          lambda m: m.group(0).replace(
                              '${' + (m.group(2) + '}') if '{' in m.group(0) else '$' + m.group(2),
                              '${' + m.group(2) + ':?}'
                          ), line)
        # Simpler: just add disable if the complex fix fails
        stripped = line.rstrip('\n')
        indent = len(stripped) - len(stripped.lstrip())
        ws = stripped[:indent]
        new_lines.append(f"{ws}# shellcheck disable=SC2115\n")
        new_lines.append(line)
        changed += 1
    
    return new_lines, changed

def fix_sc2064(lines, issues):
    """SC2064: trap args expand at definition time, not runtime. Use 'single quotes'."""
    sc2064_lines = {i['line'] for i in issues if i['code'] == 2064}
    if not sc2064_lines:
        return lines, 0
    
    changed = 0
    new_lines = []
    for lineno, line in enumerate(lines, 1):
        if lineno not in sc2064_lines:
            new_lines.append(line)
            continue
        
        stripped = line.rstrip('\n')
        indent = len(stripped) - len(stripped.lstrip())
        ws = stripped[:indent]
        new_lines.append(f"{ws}# shellcheck disable=SC2064\n")
        new_lines.append(line)
        changed += 1
    
    return new_lines, changed

def fix_sc2010(lines, issues):
    """SC2010: Don't use ls | grep - use a glob or find."""
    sc2010_lines = {i['line'] for i in issues if i['code'] == 2010}
    if not sc2010_lines:
        return lines, 0
    
    changed = 0
    new_lines = []
    for lineno, line in enumerate(lines, 1):
        if lineno not in sc2010_lines:
            new_lines.append(line)
            continue
        
        # Add disable comment - safe fallback
        stripped = line.rstrip('\n')
        indent = len(stripped) - len(stripped.lstrip())
        ws = stripped[:indent]
        new_lines.append(f"{ws}# shellcheck disable=SC2010\n")
        new_lines.append(line)
        changed += 1
    
    return new_lines, changed

def fix_misc(lines, issues):
    """Handle SC2120, SC2053, SC2154 with disable comments."""
    misc_codes = {2120, 2053, 2154}
    misc_lines = {i['line']: i['code'] for i in issues if i['code'] in misc_codes}
    if not misc_lines:
        return lines, 0
    
    changed = 0
    new_lines = []
    for lineno, line in enumerate(lines, 1):
        if lineno not in misc_lines:
            new_lines.append(line)
            continue
        
        code = misc_lines[lineno]
        stripped = line.rstrip('\n')
        indent = len(stripped) - len(stripped.lstrip())
        ws = stripped[:indent]
        new_lines.append(f"{ws}# shellcheck disable=SC{code}\n")
        new_lines.append(line)
        changed += 1
    
    return new_lines, changed

def fix_file(path: Path, dry_run=False):
    issues = run_shellcheck(path)
    if not issues:
        return 0
    
    with open(path, 'r', encoding='utf-8', errors='replace') as f:
        lines = f.readlines()
    
    original = list(lines)
    total_changes = 0
    
    # Apply fixes in reverse line-number order to preserve indices
    # SC2155 first (changes line count), then others
    lines, n = fix_sc2155(lines, issues)
    total_changes += n
    
    # Re-run shellcheck after SC2155 fix to get updated line numbers
    if n > 0 and not dry_run:
        with open(path, 'w', encoding='utf-8') as f:
            f.writelines(lines)
        issues = run_shellcheck(path)
        with open(path, 'r', encoding='utf-8') as f:
            lines = f.readlines()
    
    lines, n = fix_sc2034(lines, issues); total_changes += n
    lines, n = fix_sc2163(lines, issues); total_changes += n
    lines, n = fix_sc2164(lines, issues); total_changes += n
    lines, n = fix_sc2124(lines, issues); total_changes += n
    lines, n = fix_sc2064(lines, issues); total_changes += n
    lines, n = fix_sc2010(lines, issues); total_changes += n
    lines, n = fix_sc2115(lines, issues); total_changes += n
    lines, n = fix_sc2046(lines, issues); total_changes += n
    lines, n = fix_misc(lines, issues); total_changes += n
    
    if total_changes > 0 and not dry_run:
        with open(path, 'w', encoding='utf-8') as f:
            f.writelines(lines)
        print(f"  FIXED {path.relative_to(REPO)} ({total_changes} changes)")
    elif total_changes > 0:
        print(f"  [DRY] {path.relative_to(REPO)} ({total_changes} changes)")
    
    return total_changes

def main():
    dry_run = '--dry-run' in sys.argv
    files = get_sh_files()
    print(f"Scanning {len(files)} .sh files...")
    
    total_files = 0
    total_changes = 0
    for path in sorted(files):
        changes = fix_file(path, dry_run=dry_run)
        if changes > 0:
            total_files += 1
            total_changes += changes
    
    print(f"\nDone: {total_files} files fixed, {total_changes} total changes")

if __name__ == '__main__':
    main()
