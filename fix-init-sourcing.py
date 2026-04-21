#!/usr/bin/env python3
import re, os

BASE = "/mnt/c/code-server-enterprise"

# Scripts where SCRIPT_DIR = repo root (need REPO_ROOT variable added)
repo_root_scripts = [
    "scripts/ci/audit-dependencies.sh",
    "scripts/ci/check-docs-broken-links.sh",
    "scripts/ci/check-docs-duplicates.sh",
    "scripts/ci/check-docs-metadata.sh",
    "scripts/ci/check-no-hardcoded-lb-cookie-secret.sh",
    "scripts/ci/check-nonroot-containers.sh",
    "scripts/ci/check-observability-alerts.sh",
    "scripts/ci/check-phase-2-jwt-readiness.sh",
    "scripts/ci/check-redis-authentication.sh",
    "scripts/ci/run-phase-3-rbac-tests.sh",
    "scripts/ci/run-playwright-rbac-e2e.sh",
    "scripts/ci/validate-oauth-runbook.sh",
    "scripts/ci/verify-nonroot-containers.sh",
]

# Scripts where SCRIPT_DIR = ci dir already (just need source added/fixed)
ci_dir_scripts = [
    "scripts/ci/check-jwt-integration-readiness.sh",
    "scripts/ci/check-no-powershell.sh",
    "scripts/ci/run-jwt-e2e-tests.sh",
]

OLD_SCRIPT_DIR = 'SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"'
NEW_SCRIPT_DIR = 'SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"\nREPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"'
CANONICAL_SOURCE = 'source "$SCRIPT_DIR/../_common/init.sh"'

def fix_repo_root_script(path):
    full = os.path.join(BASE, path)
    with open(full) as f:
        content = f.read()

    if OLD_SCRIPT_DIR not in content:
        print(f"SKIP (no old SCRIPT_DIR pattern): {path}")
        return

    # 1. Replace SCRIPT_DIR=repo root with SCRIPT_DIR=script dir + REPO_ROOT
    content = content.replace(OLD_SCRIPT_DIR, NEW_SCRIPT_DIR, 1)

    # 2. Remove old source lines that use /scripts/_common/ path
    content = re.sub(r'source\s+"\$\{?SCRIPT_DIR\}?/scripts/_common/init\.sh"[^\n]*\n', '', content)

    # 3. Add canonical source after REPO_ROOT line (if not already present)
    repo_root_line = 'REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"'
    if CANONICAL_SOURCE not in content:
        content = content.replace(repo_root_line, repo_root_line + '\n' + CANONICAL_SOURCE, 1)

    # 4. Replace $SCRIPT_DIR paths (line-by-line, skip definition/source lines)
    lines = content.split('\n')
    new_lines = []
    for line in lines:
        stripped = line.strip()
        if (stripped.startswith('SCRIPT_DIR=') or stripped.startswith('REPO_ROOT=')
                or stripped.startswith('source ') or stripped.startswith('#')):
            new_lines.append(line)
        else:
            line = line.replace('${SCRIPT_DIR}/', '${REPO_ROOT}/')
            line = re.sub(r'\$SCRIPT_DIR/', '$REPO_ROOT/', line)
            new_lines.append(line)
    content = '\n'.join(new_lines)

    with open(full, 'w') as f:
        f.write(content)
    print(f"FIXED (repo-root): {path}")


def fix_ci_dir_script(path):
    full = os.path.join(BASE, path)
    with open(full) as f:
        content = f.read()

    # Remove any broken source with braces or 2>/dev/null fallback
    content = re.sub(r'source\s+"\$\{SCRIPT_DIR\}/../_common/init\.sh"[^\n]*\n', '', content)
    content = re.sub(r'source\s+"\$SCRIPT_DIR/../_common/init\.sh" 2>/dev/null[^\n]*\n', '', content)
    # Multi-line fallback block starting with the source call
    content = re.sub(
        r'source\s+"\$\{?SCRIPT_DIR\}?/../_common/init\.sh"[^\n]* \|\|\s*\{[^}]*\}\n',
        '', content, flags=re.DOTALL
    )

    # Add canonical source after SCRIPT_DIR definition if not present
    if CANONICAL_SOURCE not in content:
        content = re.sub(
            r'(SCRIPT_DIR="[^"]*"\n)',
            r'\1' + CANONICAL_SOURCE + '\n',
            content, count=1
        )

    with open(full, 'w') as f:
        f.write(content)
    print(f"FIXED (ci-dir): {path}")


for s in repo_root_scripts:
    try:
        fix_repo_root_script(s)
    except Exception as e:
        print(f"ERROR {s}: {e}")

for s in ci_dir_scripts:
    try:
        fix_ci_dir_script(s)
    except Exception as e:
        print(f"ERROR {s}: {e}")

print("Done.")
