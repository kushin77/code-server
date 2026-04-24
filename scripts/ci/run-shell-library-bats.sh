#!/usr/bin/env bash
# @file        scripts/ci/run-shell-library-bats.sh
# @module      ci/testing
# @description Run bats-core tests for shared shell libraries and optionally generate coverage artifacts.
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../_common/init.sh"

TEST_ROOT="${TEST_ROOT:-$PROJECT_ROOT/tests/unit}"
COVERAGE_ROOT="${COVERAGE_ROOT:-$PROJECT_ROOT/coverage/bats}"
RUN_COVERAGE=0
COVERAGE_THRESHOLD="${COVERAGE_THRESHOLD:-90}"

while (($#)); do
    case "$1" in
        --coverage)
            RUN_COVERAGE=1
            shift
            ;;
        --test-root)
            TEST_ROOT="${2:-}"
            shift 2
            ;;
        --coverage-root)
            COVERAGE_ROOT="${2:-}"
            shift 2
            ;;
        *)
            log_fatal "Unknown argument: $1"
            ;;
    esac
done

require_command bats
require_dir "$TEST_ROOT"

mapfile -t test_files < <(find "$TEST_ROOT" -type f -name '*.bats' | sort)

if [[ ${#test_files[@]} -eq 0 ]]; then
    log_fatal "No bats tests found under $TEST_ROOT"
fi

if [[ "$RUN_COVERAGE" -eq 1 ]]; then
    require_command kcov
    require_command python3
    rm -rf "$COVERAGE_ROOT"
    mkdir -p "$COVERAGE_ROOT"

    for test_file in "${test_files[@]}"; do
        test_name="$(basename "${test_file%.bats}")"
        log_info "Running bats coverage for $test_name"
        kcov \
            --clean \
            --bash-method=TEST_FILE \
            --include-pattern="$PROJECT_ROOT/scripts" \
            --cobertura-only \
            "$COVERAGE_ROOT/$test_name" \
            bats "$test_file"
    done

    log_info "Evaluating coverage threshold for shared libraries (minimum ${COVERAGE_THRESHOLD}%)"
    python3 - "$COVERAGE_ROOT" "$PROJECT_ROOT" "$COVERAGE_THRESHOLD" <<'PY'
import glob
import os
import sys
import xml.etree.ElementTree as ET

coverage_root = sys.argv[1]
project_root = os.path.realpath(sys.argv[2])
threshold = float(sys.argv[3])

target_dirs = {
    "scripts/_common": {"covered": 0, "valid": 0},
    "scripts/lib": {"covered": 0, "valid": 0},
}

def normalize_filename(filename: str) -> str:
    if not filename:
        return ""
    real = os.path.realpath(filename)
    if real.startswith(project_root + os.sep):
        rel = os.path.relpath(real, project_root)
    else:
        rel = filename
    rel = rel.replace("\\", "/")
    if rel.startswith("./"):
        rel = rel[2:]
    return rel

xml_reports = glob.glob(os.path.join(coverage_root, "**", "cobertura.xml"), recursive=True)
if not xml_reports:
    print(f"ERROR: No cobertura.xml reports found under {coverage_root}", file=sys.stderr)
    sys.exit(1)

for report in xml_reports:
    root = ET.parse(report).getroot()
    for class_node in root.findall(".//class"):
        filename = normalize_filename(class_node.attrib.get("filename", ""))
        if not filename:
            continue

        matching_key = None
        for key in target_dirs:
            if filename.startswith(key + "/"):
                matching_key = key
                break
        if not matching_key:
            continue

        lines_valid = class_node.attrib.get("lines-valid")
        lines_covered = class_node.attrib.get("lines-covered")
        if lines_valid is not None and lines_covered is not None:
            valid = int(lines_valid)
            covered = int(lines_covered)
        else:
            valid = 0
            covered = 0
            for line_node in class_node.findall("./lines/line"):
                valid += 1
                if int(line_node.attrib.get("hits", "0")) > 0:
                    covered += 1

        target_dirs[matching_key]["valid"] += valid
        target_dirs[matching_key]["covered"] += covered

failed = False
for key, data in target_dirs.items():
    valid = data["valid"]
    covered = data["covered"]
    if valid == 0:
        print(f"ERROR: No measurable lines were reported for {key}", file=sys.stderr)
        failed = True
        continue

    percent = (covered / valid) * 100.0
    print(f"Coverage {key}: {covered}/{valid} lines ({percent:.2f}%)")
    if percent < threshold:
        print(
            f"ERROR: Coverage for {key} is below threshold ({percent:.2f}% < {threshold:.2f}%)",
            file=sys.stderr,
        )
        failed = True

if failed:
    sys.exit(1)
PY

    log_info "Coverage artifacts written to $COVERAGE_ROOT"
else
    bats "${test_files[@]}"
fi
