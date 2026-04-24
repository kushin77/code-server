#!/usr/bin/env bash
# @file        scripts/ci/validate-service-registry.sh
# @module      ci/governance
# @description validate service registry against docker-compose topology
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../_common/init.sh"

REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
REGISTRY_FILE="$REPO_ROOT/docs/service-registry.yaml"
COMPOSE_FILE="$REPO_ROOT/docker-compose.yml"

if [[ ! -f "$REGISTRY_FILE" ]]; then
  log_fatal "Missing service registry: $REGISTRY_FILE"
fi

if [[ ! -f "$COMPOSE_FILE" ]]; then
  log_fatal "Missing compose file: $COMPOSE_FILE"
fi

export REPO_ROOT REGISTRY_FILE COMPOSE_FILE

python3 - <<'PY'
import json
import os
import re
import sys
from pathlib import Path

registry_path = Path(os.environ["REGISTRY_FILE"])
compose_path = Path(os.environ["COMPOSE_FILE"])

registry = json.loads(registry_path.read_text(encoding="utf-8"))
services = registry.get("services", [])
if not isinstance(services, list) or not services:
    print(f"::error file={registry_path}::Registry has no services")
    sys.exit(1)

registry_names = []
compose_registry_names = []
for entry in services:
    if not isinstance(entry, dict):
        print(f"::error file={registry_path}::Registry entries must be objects")
        sys.exit(1)
    name = entry.get("name")
    source = entry.get("source", "compose")
    healthcheck = entry.get("healthcheck")
    if not name:
        print(f"::error file={registry_path}::Registry entry missing name: {entry}")
        sys.exit(1)
    registry_names.append(name)
    if source not in {"compose", "kubernetes"}:
        print(f"::error file={registry_path}::Service {name} has invalid source: {source}")
        sys.exit(1)
    if source == "compose":
        compose_registry_names.append(name)
    if not isinstance(healthcheck, dict):
        print(f"::error file={registry_path}::Service {name} is missing a healthcheck block")
        sys.exit(1)
    health_type = healthcheck.get("type")
    target = healthcheck.get("target")
    if health_type not in {"http", "command", "one-shot"}:
        print(f"::error file={registry_path}::Service {name} has invalid healthcheck type: {health_type}")
        sys.exit(1)
    if health_type in {"http", "command"} and not target:
        print(f"::error file={registry_path}::Service {name} is missing a healthcheck target")
        sys.exit(1)
    if health_type == "http" and not re.match(r"^https?://", str(target)):
        print(f"::error file={registry_path}::Service {name} must use an http(s) target")
        sys.exit(1)

compose_lines = compose_path.read_text(encoding="utf-8").splitlines()
compose_names = []
inside_services = False
for line in compose_lines:
    if line.strip() == "services:":
        inside_services = True
        continue
    if inside_services and line and not line.startswith(" ") and line.strip().endswith(":"):
        break
    match = re.match(r"^  ([A-Za-z0-9][A-Za-z0-9._-]*):\s*$", line)
    if match:
        compose_names.append(match.group(1))

compose_set = set(compose_names)
compose_registry_set = set(compose_registry_names)

if len(compose_names) != len(compose_set):
    duplicates = sorted(name for name in compose_set if compose_names.count(name) > 1)
    print(f"::error file={compose_path}::Duplicate compose services detected: {', '.join(duplicates)}")
    sys.exit(1)

missing_in_registry = sorted(compose_set - compose_registry_set)
missing_in_compose = sorted(compose_registry_set - compose_set)

if missing_in_registry:
    print(f"::error file={registry_path}::Registry is missing compose services: {', '.join(missing_in_registry)}")
    sys.exit(1)

if missing_in_compose:
    print(f"::error file={registry_path}::Registry includes unknown compose services: {', '.join(missing_in_compose)}")
    sys.exit(1)

print(f"Validated {len(compose_names)} compose services against the registry")
for name in compose_names:
    entry = next(item for item in services if item["name"] == name)
    ports = entry.get("ports", [])
    source = entry.get("source", "compose")
    profile = entry.get("profile", "n/a")
    print(f"- {name}: {entry.get('purpose', 'n/a')} [{source}/{profile}] ports={ports}")

external_entries = [item for item in services if item.get("source") != "compose"]
for entry in external_entries:
    print(f"- external service: {entry['name']} [{entry.get('source')}] ports={entry.get('ports', [])}")

PY

log_info "Service registry validation passed"