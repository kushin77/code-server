#!/usr/bin/env bash
# @file        scripts/ci/detect-duplicate-compose-keys.sh
# @module      governance/deduplication
# @description Detect duplicate docker-compose service fragments and environment-key sets for consolidation candidates.
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
source "${REPO_ROOT}/scripts/_common/init.sh"

cd "${REPO_ROOT}"

mapfile -t compose_files < <(find . -maxdepth 2 -type f \( -name 'docker-compose*.yml' -o -name '*compose*.yaml' \) | sed 's#^./##' | sort)

if [[ ${#compose_files[@]} -eq 0 ]]; then
  log_info "No compose files found; duplicate compose key detection skipped"
  exit 0
fi

log_info "Scanning compose files for duplicate fragments"

tmp_files="$(mktemp)"
trap 'rm -f "$tmp_files"' EXIT
printf '%s\n' "${compose_files[@]}" > "$tmp_files"

python3 - "$tmp_files" <<'PY'
import hashlib
import re
import sys

files = [line.strip() for line in open(sys.argv[1], encoding='utf-8') if line.strip()]

service_blocks = {}
env_key_sets = {}


def flush_service(path, service_name, block_lines, env_keys):
    if not service_name:
        return

    normalized = []
    for raw in block_lines:
        line = re.sub(r'\s+#.*$', '', raw).rstrip()
        if not line.strip():
            continue
        normalized.append(re.sub(r'\s+', ' ', line.strip()))

    payload = '\n'.join(normalized)
    if payload:
        digest = hashlib.sha1(payload.encode('utf-8')).hexdigest()
        service_blocks.setdefault(digest, []).append((path, service_name))

    if env_keys:
        sig = tuple(sorted(set(env_keys)))
        env_key_sets.setdefault(sig, []).append((path, service_name))


for path in files:
    lines = open(path, encoding='utf-8').read().splitlines()

    in_services = False
    current_service = None
    current_block = []
    in_env = False
    env_keys = []

    for line in lines:
        if re.match(r'^services:\s*$', line):
            in_services = True
            continue

        if in_services and re.match(r'^[^\s].*:\s*$', line):
            flush_service(path, current_service, current_block, env_keys)
            in_services = False
            current_service = None
            current_block = []
            in_env = False
            env_keys = []
            continue

        if not in_services:
            continue

        m_service = re.match(r'^  ([A-Za-z0-9_-]+):\s*$', line)
        if m_service:
            flush_service(path, current_service, current_block, env_keys)
            current_service = m_service.group(1)
            current_block = []
            in_env = False
            env_keys = []
            continue

        if not current_service:
            continue

        current_block.append(line)

        if re.match(r'^    environment:\s*$', line):
            in_env = True
            continue

        if in_env:
            if re.match(r'^    [A-Za-z0-9_-]+:\s*$', line):
                in_env = False
                continue
            m_list = re.match(r'^      -\s*([A-Za-z_][A-Za-z0-9_]*)=', line)
            if m_list:
                env_keys.append(m_list.group(1))
                continue
            m_map = re.match(r'^      ([A-Za-z_][A-Za-z0-9_]*):', line)
            if m_map:
                env_keys.append(m_map.group(1))
                continue

    flush_service(path, current_service, current_block, env_keys)

print('=== Duplicate Compose Fragment Candidates ===')
fragment_hits = 0
for digest, refs in service_blocks.items():
    if len(refs) < 2:
        continue
    fragment_hits += 1
    print(f'fragment={digest[:10]} refs=' + ', '.join([f'{p}:{s}' for p, s in refs]))
if fragment_hits == 0:
    print('none')

print('')
print('=== Duplicate Environment-Key Set Candidates ===')
env_hits = 0
for keyset, refs in env_key_sets.items():
    if len(refs) < 2 or len(keyset) < 2:
        continue
    env_hits += 1
    keys = ','.join(keyset)
    print(f'env_keys=[{keys}] refs=' + ', '.join([f'{p}:{s}' for p, s in refs]))
if env_hits == 0:
    print('none')

print('')
print(f'summary: fragments={fragment_hits} env_sets={env_hits}')
PY

log_info "Duplicate compose key detection completed (advisory only)"
exit 0
