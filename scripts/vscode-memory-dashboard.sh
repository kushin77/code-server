#!/usr/bin/env bash
# @file        scripts/vscode-memory-dashboard.sh
# @module      vscode-stability
# @description vscode memory dashboard — on-prem code-server
# @owner       platform
# @status      active
# ═══════════════════════════════════════════════════════════════════════════
# VSCode Memory Dashboard
# Purpose: Display memory usage breakdown across all VSCode processes
# Issue:   P1 #448 Memory Budget Guard
# Run:     bash scripts/vscode-memory-dashboard.sh
# Budget:  Max 1024 MB per extension host (enforced via --max-old-space-size)
# ═══════════════════════════════════════════════════════════════════════════
set -euo pipefail

RED='\033[0;31m'; YELLOW='\033[1;33m'; GREEN='\033[0;32m'; CYAN='\033[0;36m'; NC='\033[0m'
BOLD='\033[1m'
BUDGET_MB=1024

echo ""
echo -e "${BOLD}╔═════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║   VSCode Memory Budget Dashboard                            ║${NC}"
echo -e "${BOLD}║   Budget: ${BUDGET_MB}MB per process  |  $(date '+%Y-%m-%d %H:%M:%S')      ║${NC}"
echo -e "${BOLD}╚═════════════════════════════════════════════════════════════╝${NC}"
echo ""

# ─── System memory overview ──────────────────────────────────────────────────
echo -e "${BOLD}[1] System Memory Overview${NC}"
echo "─────────────────────────────────────────────────────────────"

if command -v free &>/dev/null; then
  free -h | awk '
    NR==1 { print "  " $0 }
    NR==2 { 
      total=$2; used=$3; avail=$7
      printf "  %-10s %8s %8s %8s\n", "Mem:", total, used, avail
    }
    NR==3 { printf "  %-10s %8s %8s\n", "Swap:", $2, $3 }
  '
else
  # Windows fallback
  powershell.exe -NoProfile -Command \
    "Get-CimInstance Win32_OperatingSystem | Select-Object @{N='TotalGB';E={[math]::Round(\$_.TotalVisibleMemorySize/1MB,1)}},@{N='FreeGB';E={[math]::Round(\$_.FreePhysicalMemory/1MB,1)}} | Format-Table" \
    2>/dev/null || echo "  (memory info unavailable)"
fi
echo ""

# ─── VSCode process memory breakdown ─────────────────────────────────────────
echo -e "${BOLD}[2] VSCode Process Memory (RSS)${NC}"
echo "─────────────────────────────────────────────────────────────"
echo -e "  ${CYAN}PID        RSS(MB)   Process${NC}"
echo "  ─────────────────────────────────────────────────────"

total_vscode_mb=0
budget_exceeded=0

if command -v ps &>/dev/null; then
  while IFS= read -r line; do
    pid=$(echo "$line" | awk '{print $1}')
    rss_kb=$(echo "$line" | awk '{print $2}')
    cmd=$(echo "$line" | awk '{for(i=3;i<=NF;i++) printf "%s ", $i; print ""}' | cut -c1-55)
    rss_mb=$(( rss_kb / 1024 ))
    total_vscode_mb=$(( total_vscode_mb + rss_mb ))

    if [ "$rss_mb" -gt "$BUDGET_MB" ]; then
      echo -e "  ${RED}${pid}   ${rss_mb}MB   ${cmd}${NC}"
      budget_exceeded=$(( budget_exceeded + 1 ))
    elif [ "$rss_mb" -gt $(( BUDGET_MB * 80 / 100 )) ]; then
      echo -e "  ${YELLOW}${pid}   ${rss_mb}MB   ${cmd}${NC}"
    else
      echo -e "  ${GREEN}${pid}   ${rss_mb}MB   ${cmd}${NC}"
    fi
  done < <(ps aux 2>/dev/null | awk '/[Cc]ode[- ][Ss]erver|extensionHost|[Vv][Ss][Cc]ode|code-server/ && !/awk/ {print $2, $6, $11, $12, $13}' 2>/dev/null || true)
else
  echo "  (ps not available — running outside Linux)"
fi

echo ""
echo -e "  Total VSCode RSS: ${BOLD}${total_vscode_mb} MB${NC}"

if [ "$budget_exceeded" -gt 0 ]; then
  echo -e "  ${RED}⚠ ${budget_exceeded} process(es) exceed ${BUDGET_MB}MB budget${NC}"
else
  echo -e "  ${GREEN}✓ All processes within ${BUDGET_MB}MB budget${NC}"
fi
echo ""

# ─── Extension host memory detail ────────────────────────────────────────────
echo -e "${BOLD}[3] Extension Host Processes${NC}"
echo "─────────────────────────────────────────────────────────────"

ext_pids=$(pgrep -f extensionHost 2>/dev/null || true)
if [ -n "$ext_pids" ]; then
  ext_count=$(echo "$ext_pids" | wc -l)
  echo -e "  Active extension hosts: ${ext_count}"
  for pid in $ext_pids; do
    if [ -f "/proc/${pid}/status" ]; then
      rss_kb=$(awk '/VmRSS/{print $2}' "/proc/${pid}/status" 2>/dev/null || echo 0)
      rss_mb=$(( rss_kb / 1024 ))
      echo -e "  PID ${pid}: ${rss_mb}MB"
    fi
  done
else
  echo -e "  ${GREEN}No extension host processes found${NC}"
fi
echo ""

# ─── Budget enforcement reminder ─────────────────────────────────────────────
echo -e "${BOLD}[4] Budget Enforcement${NC}"
echo "─────────────────────────────────────────────────────────────"
echo -e "  tasks.json terminal-process-guard: polls every 30s, beeps at >4 shells"
echo -e "  Launch flag enforcement:            --max-old-space-size=${BUDGET_MB}"
echo ""
echo -e "  ${BOLD}Remediation commands:${NC}"
echo -e "  Kill excess extension hosts:"
echo -e "  $ kill \$(pgrep -f extensionHost | tail -n +4) 2>/dev/null"
echo ""
echo -e "  Force VSCode garbage collection:"
echo -e "  $ kill -USR2 \$(pgrep -f extensionHost | head -1) 2>/dev/null"
echo ""

# ─── Docker container memory ─────────────────────────────────────────────────
echo -e "${BOLD}[5] Docker Container Memory (if Docker running)${NC}"
echo "─────────────────────────────────────────────────────────────"

if command -v docker &>/dev/null && docker info &>/dev/null 2>&1; then
  docker stats --no-stream --format "  {{.Name}}\t{{.MemUsage}}\t{{.MemPerc}}" 2>/dev/null || \
    echo "  (Docker running but no containers active)"
else
  echo "  (Docker not running locally — deploy via SSH to ${DEPLOY_HOST})"
fi
echo ""
echo "═════════════════════════════════════════════════════════════"
