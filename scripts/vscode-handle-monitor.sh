#!/usr/bin/env bash
# @file        scripts/vscode-handle-monitor.sh
# @module      vscode-stability
# @description vscode handle monitor — on-prem code-server
# @owner       platform
# @status      active
# ═══════════════════════════════════════════════════════════════════════════
# VSCode Process & Handle Health Monitor
# Purpose: Real-time snapshot of VSCode/terminal process health
# Issue:   P1 #448 Memory Budget Guard
# Run:     bash scripts/vscode-handle-monitor.sh
# ═══════════════════════════════════════════════════════════════════════════
set -euo pipefail

RED='\033[0;31m'; YELLOW='\033[1;33m'; GREEN='\033[0;32m'; NC='\033[0m'
BOLD='\033[1m'

echo ""
echo -e "${BOLD}╔═════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║   VSCode Process & Handle Health Monitor            ║${NC}"
echo -e "${BOLD}║   $(date '+%Y-%m-%d %H:%M:%S')                              ║${NC}"
echo -e "${BOLD}╚═════════════════════════════════════════════════════╝${NC}"
echo ""

# ─── Terminal/Shell process counts ──────────────────────────────────────────
echo -e "${BOLD}[1] Terminal & Shell Process Counts${NC}"
echo "─────────────────────────────────────────────────────"

count_proc() {
  pgrep -c "$1" 2>/dev/null || echo 0
}

bash_count=$(count_proc bash)
sh_count=$(count_proc "^sh$")
pwsh_count=$(count_proc pwsh)
node_count=$(count_proc node)
total_shells=$((bash_count + sh_count + pwsh_count))

echo -e "  bash:     ${bash_count}"
echo -e "  sh:       ${sh_count}"
echo -e "  pwsh:     ${pwsh_count}"
echo -e "  node:     ${node_count}"
echo ""

# Budget check: warn if > 4 shells active
if [ "$total_shells" -gt 8 ]; then
  echo -e "  ${RED}⚠ CRITICAL: ${total_shells} shells active (budget: 4). Kill excess.${NC}"
elif [ "$total_shells" -gt 4 ]; then
  echo -e "  ${YELLOW}⚠ WARNING: ${total_shells} shells active (budget: 4). Consider pruning.${NC}"
else
  echo -e "  ${GREEN}✓ Shell count within budget (${total_shells}/4)${NC}"
fi
echo ""

# ─── VSCode extension host processes ────────────────────────────────────────
echo -e "${BOLD}[2] VSCode Extension Host Processes${NC}"
echo "─────────────────────────────────────────────────────"

ext_count=$(pgrep -f "extensionHost" 2>/dev/null | wc -l || echo 0)
renderer_count=$(pgrep -f "renderer" 2>/dev/null | wc -l || echo 0)

echo -e "  Extension hosts: ${ext_count}"
echo -e "  Renderer procs:  ${renderer_count}"

if [ "$ext_count" -gt 3 ]; then
  echo -e "  ${YELLOW}⚠ Multiple extension hosts detected — may indicate leak${NC}"
else
  echo -e "  ${GREEN}✓ Extension host count normal${NC}"
fi
echo ""

# ─── Memory usage top processes ─────────────────────────────────────────────
echo -e "${BOLD}[3] Top 5 Processes by RSS Memory${NC}"
echo "─────────────────────────────────────────────────────"

if command -v ps &>/dev/null; then
  ps aux --sort=-%mem 2>/dev/null | awk 'NR==1 || NR<=6 {printf "  %-10s %-8s %-8s %s\n", $1, $3"%", $4"%", substr($0, index($0,$11), 30)}' 2>/dev/null || \
  echo "  (ps command not available in this environment)"
fi
echo ""

# ─── Open file descriptor count ─────────────────────────────────────────────
echo -e "${BOLD}[4] Open File Descriptors${NC}"
echo "─────────────────────────────────────────────────────"

if [ -f /proc/sys/fs/file-nr ]; then
  read -r open _ max < /proc/sys/fs/file-nr
  pct=$(( open * 100 / max ))
  echo -e "  Open FDs: ${open} / ${max} (${pct}%)"
  if [ "$pct" -gt 80 ]; then
    echo -e "  ${RED}⚠ High FD usage — risk of 'too many open files'${NC}"
  else
    echo -e "  ${GREEN}✓ FD usage normal${NC}"
  fi
else
  echo "  (not available outside Linux)"
fi
echo ""

# ─── Load average ───────────────────────────────────────────────────────────
echo -e "${BOLD}[5] System Load${NC}"
echo "─────────────────────────────────────────────────────"

if [ -f /proc/loadavg ]; then
  read -r l1 l5 l15 _ < /proc/loadavg
  echo -e "  Load avg: ${l1} (1m) / ${l5} (5m) / ${l15} (15m)"
else
  echo "  (not available outside Linux)"
fi
echo ""

# ─── Recommendations ────────────────────────────────────────────────────────
echo -e "${BOLD}[6] Budget Summary${NC}"
echo "─────────────────────────────────────────────────────"
echo -e "  Max terminals (budget):   4"
echo -e "  Max extension hosts:      3"
echo -e "  Max memory/process:       1024 MB (enforced via launch flag)"
echo ""
echo -e "  ${BOLD}To kill excess terminals:${NC}"
echo -e "  $ pkill -f 'bash.*vscode' 2>/dev/null"
echo -e "  $ kill \$(pgrep -f extensionHost | tail -n +4) 2>/dev/null"
echo ""
echo "═════════════════════════════════════════════════════"
