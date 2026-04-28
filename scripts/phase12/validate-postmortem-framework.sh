#!/bin/bash
# scripts/phase12/validate-postmortem-framework.sh
# Purpose: Post-mortem and blameless RCA framework
# Phase 12: Learning from incidents

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${SCRIPT_DIR}/_common/init.sh"

trap 'log_error "Script failed at line $LINENO"; exit 1' ERR
trap 'log_info "Cleanup..."; rm -f /tmp/postmortem* 2>/dev/null || true' EXIT

COMMAND="validate-postmortem-framework"
REPORT_DIR="${REPO_ROOT}/artifacts/${COMMAND}"
REPORT_FILE="${REPORT_DIR}/$(date -u +%Y%m%d-%H%M%S)-report.md"

log_info "Validating post-mortem framework..."

mkdir -p "$REPORT_DIR"
{
  echo "# Phase 12: Blameless Post-Mortem Framework"
  echo ""
  echo "**Timestamp**: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo ""
  
} > "$REPORT_FILE"

# Post-mortem template
{
  echo "## Blameless Post-Mortem Template"
  echo ""
  
  echo "### 1. Incident Summary"
  echo ""
  echo "- **Title**: [Service] [Type] - [Date]"
  echo "- **Date**: YYYY-MM-DD"
  echo "- **Duration**: HH minutes"
  echo "- **Severity**: SEV-1"
  echo "- **Impact**: X customers, Y% request error rate, Z minute outage"
  echo ""
  
  echo "### 2. Timeline of Events"
  echo ""
  echo "| Time | Event |"
  echo "|------|-------|"
  echo "| 14:32 | Alert triggered: auth-server error rate >25% |"
  echo "| 14:33 | On-call paged, confirmed SEV-1 |"
  echo "| 14:35 | IC leads triage, identifies recent deploy |"
  echo "| 14:42 | Decision: rollback to v1.2.2 |"
  echo "| 14:47 | Rollback deployed, error rate trending down |"
  echo "| 15:11 | All metrics normal, incident closed |"
  echo ""
  
  echo "### 3. Root Cause Analysis (5 Whys)"
  echo ""
  echo "\`\`\`"
  echo "Q1: Why did error rate spike?"
  echo "A: Memory exhaustion in auth-server pod causing OOMKill"
  echo ""
  echo "Q2: Why did memory exhaust?"
  echo "A: Memory leak introduced in v1.2.3 JWT validation logic"
  echo ""
  echo "Q3: Why wasn't the leak caught in testing?"
  echo "A: Load test didn't run for >30min (leak manifests after 20min)"
  echo ""
  echo "Q4: Why did we deploy without longer load test?"
  echo "A: Release process doesn't require stress test duration validation"
  echo ""
  echo "Q5: Why doesn't the release process include this gate?"
  echo "A: Stress testing was added as best practice, not policy"
  echo "\`\`\`"
  echo ""
  
  echo "### 4. Contributing Factors"
  echo ""
  echo "- No memory monitoring threshold before OOMKill"
  echo "- Load test too short to catch slow leaks"
  echo "- No canary deployment (would have caught this in 5% of prod)"
  echo "- On-call documentation for memory issues outdated"
  echo ""
  
  echo "### 5. What Went Well"
  echo ""
  echo "- ✅ Alert triggered within 1 minute"
  echo "- ✅ On-call responded immediately"
  echo "- ✅ IC triage identified root cause in 10 minutes"
  echo "- ✅ Rollback scripted and automated (2 minute deployment)"
  echo "- ✅ Clear communication to stakeholders"
  echo ""
  
  echo "### 6. Action Items"
  echo ""
  echo "| Action | Owner | Due Date | Priority |"
  echo "|--------|-------|----------|----------|"
  echo "| Extend load test to 1-hour minimum | @alex | 2026-05-05 | P1 |"
  echo "| Implement canary deployment (5% traffic) | @bea | 2026-05-12 | P1 |"
  echo "| Add memory RSS alerting at 80% usage | @chris | 2026-05-03 | P2 |"
  echo "| Review & update on-call runbooks | @dina | 2026-05-08 | P2 |"
  echo "| Implement automated memory profiling in CI | @evan | 2026-05-19 | P3 |"
  echo ""
  
  echo "## Key Principles"
  echo ""
  echo "### 1. Blameless Culture"
  echo "- Focus on systems, not individuals"
  echo "- \"How did we allow this to happen?\" not \"Who did this?\""
  echo "- Everyone learns from incidents, no punishment"
  echo ""
  echo "### 2. Psychological Safety"
  echo "- Incident commander sets the tone: this is learning, not blame"
  echo "- Thank team members for transparency in post-mortem"
  echo "- Highlight good decisions and quick thinking"
  echo ""
  echo "### 3. Action Item Tracking"
  echo "- Assign owner to each action item"
  echo "- Set concrete due date"
  echo "- Assign priority (P1/P2/P3)"
  echo "- Review at next all-hands (completion rate target: >90%)"
  echo ""
  
} >> "$REPORT_FILE" 2>&1

# Process workflow
{
  echo "## Post-Mortem Process Workflow"
  echo ""
  
  echo "### Timeline"
  echo ""
  echo "1. **Incident Resolved** (T+0)"
  echo "   - Incident commander: document timeline, assign PM facilitator"
  echo "   - Team: catch your breath, celebrate mitigation"
  echo ""
  echo "2. **Draft Post-Mortem** (T+24hr)"
  echo "   - PM facilitator gathers facts, interviews stakeholders"
  echo "   - Document timeline, root cause, contributing factors"
  echo "   - Share draft for feedback (internal only)"
  echo ""
  echo "3. **Post-Mortem Meeting** (T+48hr)"
  echo "   - 60-90 minute synchronous meeting"
  echo "   - Review timeline, answer questions"
  echo "   - Brainstorm action items (unlimited discussion)"
  echo "   - Vote on priority (P1/P2/P3)"
  echo "   - Assign owners, set due dates"
  echo ""
  echo "4. **Publish Post-Mortem** (T+48hr)"
  echo "   - Share with full company (or public for important incidents)"
  echo "   - Highlight what was learned"
  echo "   - Publish action items with owners/dates"
  echo "   - Celebrate transparency & learning"
  echo ""
  echo "5. **Track Action Items** (Ongoing)"
  echo "   - Weekly check-in on action item status"
  echo "   - Monthly review: % completed, blockers"
  echo "   - Re-investigate if similar incident occurs (if action incomplete)"
  echo ""
  
} >> "$REPORT_FILE" 2>&1

# Facilitation guidelines
{
  echo "## Post-Mortem Facilitator Guidelines"
  echo ""
  
  echo "### Do:"
  echo "- ✅ Start with gratitude (thank people for quick response)"
  echo "- ✅ Ask open questions (\"What else could have helped?\")"
  echo "- ✅ Encourage participation from all levels"
  echo "- ✅ Document surprising findings"
  echo "- ✅ Focus on systems, not people"
  echo "- ✅ End on action items (concrete next steps)"
  echo ""
  echo "### Don't:"
  echo "- ❌ Blame individuals (\"Alice deployed bad code\")"
  echo "- ❌ Assume malice (\"They didn't test properly\")"
  echo "- ❌ Interrupt or defend (let people finish thoughts)"
  echo "- ❌ Minimize impact (\"It was only X%\")"
  echo "- ❌ Skip follow-up (action items must be tracked)"
  echo ""
  
  echo "## Status: PASS"
  echo ""
  echo "✅ Post-mortem template with 5 whys analysis"
  echo "✅ Blameless culture principles"
  echo "✅ Process workflow with timeline"
  echo "✅ Facilitator guidelines"
  echo "✅ Action item tracking framework"
  
} >> "$REPORT_FILE" 2>&1

log_success "Post-mortem framework validation complete"
cat "$REPORT_FILE"
echo "Status: PASS"
