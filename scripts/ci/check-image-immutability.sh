#!/usr/bin/env bash
# @file        scripts/ci/check-image-immutability.sh
# @module      ci/containers
# @description Block mutable image references in active deployment manifests
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../_common/init.sh"

python3 - <<'PY'
from pathlib import Path
import re
import subprocess
import sys

repo_root = Path(subprocess.check_output(["git", "rev-parse", "--show-toplevel"], text=True).strip())

dockerfiles = [
  repo_root / "Dockerfile",
  repo_root / "Dockerfile.code-server",
  repo_root / "Dockerfile.caddy",
  repo_root / "Dockerfile.ssh-proxy",
  repo_root / "Dockerfile.token-microservice",
  repo_root / "apps/session-broker/Dockerfile",
  repo_root / "docker/haproxy/Dockerfile",
]

compose_files = [repo_root / "docker-compose.yml", repo_root / "docker-compose.socket-override.yml"]

local_compose_images = {
  "code-server-enterprise:dev",
  "session-broker:latest",
}

errors = []

def check_from_line(path: Path, line: str, lineno: int) -> None:
  stripped = line.strip()
  if not stripped.startswith("FROM "):
    return
  image_part = stripped[5:]
  image_part = image_part.split(" AS ", 1)[0].split(" as ", 1)[0].strip()
  if image_part == "scratch":
    return
  if "@sha256:" in image_part:
    return
  errors.append((path, lineno, f"unpinned Dockerfile base image: {image_part}"))


def check_compose_image(path: Path, line: str, lineno: int) -> None:
  match = re.match(r'^\s*image:\s*([^#]+?)(?:\s+#.*)?$', line)
  if not match:
    return
  image_ref = match.group(1).strip().strip('"').strip("'")
  if image_ref in local_compose_images:
    return
  if "@sha256:" in image_ref:
    return
  errors.append((path, lineno, f"unpinned compose image: {image_ref}"))


for path in dockerfiles:
  if not path.exists():
    continue
  for lineno, line in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
    check_from_line(path, line, lineno)

for path in compose_files:
  if not path.exists():
    continue
  for lineno, line in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
    check_compose_image(path, line, lineno)

if errors:
  for path, lineno, message in errors:
    print(f"::error file={path},line={lineno}::{message}")
  sys.exit(1)

print("Image immutability checks passed")
PY

log_info "Image immutability check passed"
