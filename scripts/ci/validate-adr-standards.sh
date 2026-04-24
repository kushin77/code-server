#!/usr/bin/env bash
# @file        scripts/ci/validate-adr-standards.sh
# @module      ci/governance
# @description Validate ADR bridge aliases, template naming, and contribution guidance
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../_common/init.sh"

ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

require_command "python3" "python3 is required for ADR validation"
require_file "$ROOT_DIR/docs/adr/README.md"
require_file "$ROOT_DIR/docs/adr/TEMPLATE.md"
require_file "$ROOT_DIR/docs/adr/ADR-0000-template.md"
require_file "$ROOT_DIR/.github/CONTRIBUTING.md"

python3 - "$ROOT_DIR" <<'PY'
from pathlib import Path
import sys

root = Path(sys.argv[1])
adr_dir = root / 'docs' / 'adr'
readme = (adr_dir / 'README.md').read_text(encoding='utf-8')
contributing = (root / '.github' / 'CONTRIBUTING.md').read_text(encoding='utf-8')

errors = []

def require(condition: bool, message: str) -> None:
    if not condition:
        errors.append(message)

require('ADR-0000-template.md' in readme, 'docs/adr/README.md must list ADR-0000-template.md')
require('ADR-0008-portal-platform-appsmith-vs-backstage.md' in readme, 'docs/adr/README.md must list the numbered backfill aliases')
require('docs/adr/ADR-0000-template.md' in contributing, '.github/CONTRIBUTING.md must point at the numbered ADR template')
require('issue #881' in contributing, '.github/CONTRIBUTING.md must explain the ADR backfill bridge files')

for index in range(1, 9):
    pattern = f'ADR-{index:04d}-'
    matches = sorted(path for path in adr_dir.glob(f'{pattern}*.md'))
    require(bool(matches), f'missing bridge alias for {pattern}*.md')

if errors:
    for error in errors:
        print(f'ERROR: {error}')
    raise SystemExit(1)

print('ADR standards validation passed')
PY
