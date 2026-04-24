#!/usr/bin/env bash
# @file        scripts/ci/test-deterministic-e2e-rerun.sh
# @module      ci/e2e
# @description Validate deterministic E2E flake classification and rerun behavior.
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../_common/init.sh"

require_command python3

temp_dir="$(mktemp -d)"
trap 'rm -rf "$temp_dir"' EXIT

signatures_file="$temp_dir/signatures.json"
wrapper_output="$temp_dir/output"
mkdir -p "$wrapper_output"

cp "$SCRIPT_DIR/../../config/test-flake-signatures.json" "$signatures_file"

cat > "$temp_dir/flaky-runner.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
state_file="${1:?state file required}"
if [[ ! -f "$state_file" ]]; then
  printf 'Error: browserType.launch: Target closed while starting test\n' >&2
  printf 'flaky attempt 1\n' >> "$state_file"
  exit 1
fi
printf 'flaky attempt 2\n'
exit 0
EOF
chmod +x "$temp_dir/flaky-runner.sh"

cat > "$temp_dir/non-flaky-runner.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'AssertionError: expected dashboard banner to be visible\n' >&2
exit 1
EOF
chmod +x "$temp_dir/non-flaky-runner.sh"

if ! "$SCRIPT_DIR/run-deterministic-e2e-suite.sh" \
  --suite-name flaky-suite \
  --output-dir "$wrapper_output" \
  --signatures-file "$signatures_file" \
  -- "$temp_dir/flaky-runner.sh" "$temp_dir/flaky.state"; then
  log_fatal "Expected flaky suite to pass after deterministic rerun"
fi

python3 - "$wrapper_output/flaky-suite-flake-report.json" <<'PY'
import json
import sys
from pathlib import Path

report = json.loads(Path(sys.argv[1]).read_text(encoding='utf-8'))
assert report['finalStatus'] == 'passed', report
assert len(report['attempts']) == 2, report
assert report['attempts'][0]['classification'] == 'flake', report
assert report['attempts'][1]['exitCode'] == 0, report
PY

if "$SCRIPT_DIR/run-deterministic-e2e-suite.sh" \
  --suite-name non-flaky-suite \
  --output-dir "$wrapper_output" \
  --signatures-file "$signatures_file" \
  -- "$temp_dir/non-flaky-runner.sh"; then
  log_fatal "Expected non-flaky suite to fail without deterministic rerun"
fi

python3 - "$wrapper_output/non-flaky-suite-flake-report.json" <<'PY'
import json
import sys
from pathlib import Path

report = json.loads(Path(sys.argv[1]).read_text(encoding='utf-8'))
assert report['finalClassification'] == 'non_flake', report
assert len(report['attempts']) == 1, report
PY

log_info "Deterministic E2E rerun policy validation passed"