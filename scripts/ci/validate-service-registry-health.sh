#!/usr/bin/env bash
# @file        scripts/ci/validate-service-registry-health.sh
# @module      ci/governance
# @description validate service registry health contracts against runtime endpoints
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../_common/init.sh"

REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
REGISTRY_FILE="$REPO_ROOT/docs/service-registry.yaml"
BASE_URL="${HEALTH_CHECK_BASE_URL:-}"
COMPOSE_PROJECT="${COMPOSE_PROJECT_NAME:-enterprise}"

if [[ ! -f "$REGISTRY_FILE" ]]; then
  log_fatal "Missing service registry: $REGISTRY_FILE"
fi

export REGISTRY_FILE BASE_URL COMPOSE_PROJECT

python3 - <<'PY'
import json
import os
import subprocess
import sys
from pathlib import Path

registry_path = Path(os.environ["REGISTRY_FILE"])
base_url = os.environ.get("BASE_URL", "").rstrip("/")
compose_project = os.environ.get("COMPOSE_PROJECT", "enterprise")

registry = json.loads(registry_path.read_text(encoding="utf-8"))
services = registry.get("services", [])
if not services:
    print(f"::error file={registry_path}::Registry has no services")
    sys.exit(1)

def run_command(service_name: str, command: str) -> None:
    compose_cmd = ["docker", "compose", "-p", compose_project, "exec", "-T", service_name, "sh", "-lc", command]
    result = subprocess.run(compose_cmd, capture_output=True, text=True)
    if result.returncode != 0:
        print(f"::error file={registry_path}::Command health check failed for {service_name}: {command}")
        if result.stdout:
            print(result.stdout)
        if result.stderr:
            print(result.stderr, file=sys.stderr)
        sys.exit(result.returncode)

def run_http(url: str, service_name: str) -> None:
    curl_cmd = ["curl", "-fsS", "--max-time", "10", url]
    result = subprocess.run(curl_cmd, capture_output=True, text=True)
    if result.returncode != 0:
        print(f"::error file={registry_path}::HTTP health check failed for {service_name}: {url}")
        if result.stdout:
            print(result.stdout)
        if result.stderr:
            print(result.stderr, file=sys.stderr)
        sys.exit(result.returncode)

for entry in services:
    name = entry["name"]
    source = entry.get("source", "compose")
    health = entry.get("healthcheck", {})
    health_type = health.get("type")
    target = health.get("target")
    print(f"Checking {name} ({source})...")

    if health_type == "http":
        if not target:
            print(f"::error file={registry_path}::Missing HTTP target for {name}")
            sys.exit(1)
        url = target
        if url.startswith("/"):
            if not base_url:
                print(f"::error file={registry_path}::Service {name} has a relative health target but HEALTH_CHECK_BASE_URL is unset")
                sys.exit(1)
            url = f"{base_url}{url}"
        run_http(url, name)
    elif health_type == "command":
        if not target:
            print(f"::error file={registry_path}::Missing command target for {name}")
            sys.exit(1)
        run_command(name, target)
    elif health_type == "one-shot":
        print(f"- skipping one-shot job health probe for {name}")
    else:
        print(f"::error file={registry_path}::Unsupported healthcheck type for {name}: {health_type}")
        sys.exit(1)

print(f"Validated health contracts for {len(services)} services")
PY

log_info "Service registry health validation passed"