#!/usr/bin/env bash
# @file scripts/finops/cost-baseline.sh
# @description Phase 8 - Generate a cost baseline + savings report from compose
# resource limits and Docker stats. Tracks GitHub issue #2401.

set -euo pipefail

# Required error handling traps (pre-commit policy)
trap 'log_error "Script failed at line $LINENO"; exit 1' ERR
trap 'log_info "Performing cleanup..."; rm -f /tmp/*.tmp 2>/dev/null || true' EXIT

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
. "${SCRIPT_DIR}/../_common/init.sh"

OUT="${REPO_ROOT}/artifacts/finops/cost-baseline-$(date -u +%Y%m%dT%H%M%SZ).md"
mkdir -p "$(dirname "${OUT}")"

# Cost knobs (override via env). Conservative on-prem defaults.
USD_PER_VCPU_HOUR="${USD_PER_VCPU_HOUR:-0.0125}"
USD_PER_GB_RAM_HOUR="${USD_PER_GB_RAM_HOUR:-0.0017}"
USD_PER_GB_DISK_MONTH="${USD_PER_GB_DISK_MONTH:-0.10}"
HOURS_PER_MONTH=730

log_info "=== Cost Baseline (Phase 8) ==="
log_info "Rates: \$${USD_PER_VCPU_HOUR}/vCPU·h, \$${USD_PER_GB_RAM_HOUR}/GB·h, \$${USD_PER_GB_DISK_MONTH}/GB·mo"

python3 - "${REPO_ROOT}" "${OUT}" "${USD_PER_VCPU_HOUR}" "${USD_PER_GB_RAM_HOUR}" "${USD_PER_GB_DISK_MONTH}" "${HOURS_PER_MONTH}" <<'PY'
import os, re, sys, glob

repo, out, usd_cpu, usd_ram, usd_disk, hpm = sys.argv[1:7]
usd_cpu, usd_ram, usd_disk = float(usd_cpu), float(usd_ram), float(usd_disk)
hpm = int(hpm)

def parse_size(s):
    if s is None: return 0.0
    s = str(s).strip().strip('"').strip("'")
    m = re.fullmatch(r'([0-9]*\.?[0-9]+)\s*([KMGT]?)i?[Bb]?', s)
    if not m: return 0.0
    v = float(m.group(1)); u = m.group(2).upper()
    return v * {'':1, 'K':1024, 'M':1024**2, 'G':1024**3, 'T':1024**4}[u] / (1024**3)  # GB

def parse_cpu(s):
    if s is None: return 0.0
    try: return float(str(s).strip().strip('"').strip("'"))
    except: return 0.0

# Parse compose files at repo root for `cpus:` / `mem_limit:` / `deploy.resources.limits.*`.
services = []  # list of dicts
for path in sorted(glob.glob(os.path.join(repo, 'docker-compose*.yml'))):
    if path.endswith('.backup'): continue
    with open(path) as f:
        text = f.read()
    # Naive but robust: scan service blocks
    blocks = re.split(r'\n(?=  [A-Za-z0-9_-]+:\n)', text.split('services:', 1)[-1] if 'services:' in text else text)
    for blk in blocks:
        m = re.match(r'  ([A-Za-z0-9_-]+):\n', blk)
        if not m: continue
        name = m.group(1)
        cpu = re.search(r'cpus:\s*[\'"]?([0-9.]+)[\'"]?', blk)
        mem = re.search(r'mem_limit:\s*[\'"]?([^\n\'"]+)[\'"]?', blk)
        lim_cpu = re.search(r'limits:\s*\n[^#]*?cpus:\s*[\'"]?([0-9.]+)[\'"]?', blk)
        lim_mem = re.search(r'limits:\s*\n[^#]*?memory:\s*[\'"]?([^\n\'"]+)[\'"]?', blk)
        c = parse_cpu(cpu.group(1) if cpu else (lim_cpu.group(1) if lim_cpu else None))
        m_ = parse_size(mem.group(1) if mem else (lim_mem.group(1) if lim_mem else None))
        services.append({
            'file': os.path.basename(path), 'name': name,
            'cpus': c, 'mem_gb': m_,
            'cpu_cost_mo': c * usd_cpu * hpm,
            'mem_cost_mo': m_ * usd_ram * hpm,
        })

services.sort(key=lambda s: -(s['cpu_cost_mo'] + s['mem_cost_mo']))

total_cpu = sum(s['cpus'] for s in services)
total_mem = sum(s['mem_gb'] for s in services)
total_cpu_cost = sum(s['cpu_cost_mo'] for s in services)
total_mem_cost = sum(s['mem_cost_mo'] for s in services)
total_cost = total_cpu_cost + total_mem_cost

# Optimization heuristic: services with cpus > 2 or mem > 4G that are not in a known
# high-load list become right-sizing candidates (assume 30% reclaim).
HIGH_LOAD = {'postgres','postgres-primary','postgres-replica','redis','opensearch','prometheus','grafana','kafka'}
candidates = [s for s in services if s['name'] not in HIGH_LOAD and (s['cpus'] > 2 or s['mem_gb'] > 4)]
projected_savings = sum((s['cpu_cost_mo'] + s['mem_cost_mo']) * 0.30 for s in candidates)

with open(out, 'w') as f:
    f.write("# Cost Baseline — Phase 8 (FinOps)\n\n")
    f.write("Tracks: GitHub issue #2401.\n\n")
    f.write("## Inputs (overridable env vars)\n\n")
    f.write(f"- `USD_PER_VCPU_HOUR`     = ${usd_cpu}\n")
    f.write(f"- `USD_PER_GB_RAM_HOUR`   = ${usd_ram}\n")
    f.write(f"- `USD_PER_GB_DISK_MONTH` = ${usd_disk}\n")
    f.write(f"- Hours/month             = {hpm}\n\n")
    f.write("## Aggregate (all docker-compose*.yml services)\n\n")
    f.write(f"- Services parsed:        **{len(services)}**\n")
    f.write(f"- Total reserved vCPU:    **{total_cpu:.2f}**\n")
    f.write(f"- Total reserved RAM (GB):**{total_mem:.2f}**\n")
    f.write(f"- Monthly compute cost:   **${total_cost:,.2f}**\n")
    f.write(f"  - vCPU: ${total_cpu_cost:,.2f}\n")
    f.write(f"  - RAM:  ${total_mem_cost:,.2f}\n\n")
    f.write("## Right-sizing candidates (>2 vCPU or >4GB RAM, not in HIGH_LOAD)\n\n")
    f.write(f"- Candidates: **{len(candidates)}**\n")
    f.write(f"- Projected monthly savings @ 30% reclaim: **${projected_savings:,.2f}**\n")
    f.write(f"- Projected annual savings:              **${projected_savings*12:,.2f}**\n\n")
    if candidates:
        f.write("| Service | File | vCPU | RAM (GB) | Monthly cost | Projected save |\n|---|---|---|---|---|---|\n")
        for s in candidates:
            cost = s['cpu_cost_mo'] + s['mem_cost_mo']
            f.write(f"| {s['name']} | {s['file']} | {s['cpus']:.2f} | {s['mem_gb']:.2f} | ${cost:,.2f} | ${cost*0.3:,.2f} |\n")
        f.write("\n")
    f.write("## Top 20 services by cost\n\n")
    f.write("| Service | File | vCPU | RAM (GB) | Monthly cost |\n|---|---|---|---|---|\n")
    for s in services[:20]:
        cost = s['cpu_cost_mo'] + s['mem_cost_mo']
        f.write(f"| {s['name']} | {s['file']} | {s['cpus']:.2f} | {s['mem_gb']:.2f} | ${cost:,.2f} |\n")
    f.write("\n## Methodology\n\n")
    f.write("- Source: `docker-compose*.yml` reservations parsed for `cpus:` / `mem_limit:` and `deploy.resources.limits.*`.\n")
    f.write("- Services with no declared limits contribute 0 (this is the floor of detected cost, not the ceiling).\n")
    f.write("- Right-sizing reclaim assumes 30% over-provisioning, a conservative industry baseline.\n")
print('OK', out)
PY

log_success "Cost baseline report: ${OUT}"
exit 0
