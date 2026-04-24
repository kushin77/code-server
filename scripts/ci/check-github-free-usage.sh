#!/usr/bin/env bash
# @file        scripts/ci/check-github-free-usage.sh
# @module      ci/finops
# @description Inventory GitHub Actions usage and publish a GitHub Free optimization baseline.
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../_common/init.sh"

REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
WORKFLOW_DIR="${WORKFLOW_DIR:-$REPO_ROOT/.github/workflows}"
REPORT_DIR="${REPORT_DIR:-$REPO_ROOT/artifacts/triage}"
REPORT_JSON="${REPORT_JSON:-$REPORT_DIR/github-free-maximization-report.json}"
REPORT_MD="${REPORT_MD:-$REPORT_DIR/github-free-maximization-report.md}"
RUN_HISTORY_FILE="${RUN_HISTORY_FILE:-$REPO_ROOT/artifacts/metrics/gh-runs-raw.json}"
STRICT_MODE="${STRICT_MODE:-1}"

require_command python3
mkdir -p "$REPORT_DIR"

python3 - "$WORKFLOW_DIR" "$REPORT_JSON" "$REPORT_MD" "$RUN_HISTORY_FILE" "$STRICT_MODE" <<'PY'
import json
import re
import sys
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path

workflow_dir = Path(sys.argv[1])
report_json = Path(sys.argv[2])
report_md = Path(sys.argv[3])
run_history_file = Path(sys.argv[4])
strict_mode = sys.argv[5] == "1"

uses_pattern = re.compile(r"uses:\s*([^\s#]+)")
runner_pattern = re.compile(r"runs-on:\s*(.+)$")
retention_pattern = re.compile(r"retention-days:\s*(\d+)")

workflow_files = sorted(list(workflow_dir.glob("*.yml")) + list(workflow_dir.glob("*.yaml")))

workflow_rows = []
unpinned_actions = []
retention_values = []
scheduled_workflows = 0
cache_uses = 0
artifact_uses = 0
api_usage_hits = 0
github_hosted_mentions = 0
self_hosted_mentions = 0
external_actions_pinned = 0

for workflow_path in workflow_files:
    text = workflow_path.read_text(encoding="utf-8", errors="replace")
    lines = text.splitlines()
    row = {
        "file": workflow_path.name,
        "usesCount": 0,
        "externalActionsPinned": 0,
        "externalActionsUnpinned": 0,
        "cacheUses": 0,
        "artifactUses": 0,
        "scheduled": False,
        "runnerCounts": {},
        "retentionDays": [],
        "ghApiUsageHits": 0,
    }
    runner_counts = Counter()

    for line in lines:
        stripped = line.strip()
        if not stripped:
            continue

        if "cron:" in stripped:
            row["scheduled"] = True

        if "gh issue" in stripped or "github-script" in stripped or "gh api" in stripped:
            row["ghApiUsageHits"] += 1

        if "actions/cache@" in stripped:
            row["cacheUses"] += 1

        if "actions/upload-artifact@" in stripped:
            row["artifactUses"] += 1

        runner_match = runner_pattern.search(stripped)
        if runner_match:
            runner_value = runner_match.group(1).strip().strip("'\"")
            runner_counts[runner_value] += 1

        retention_match = retention_pattern.search(stripped)
        if retention_match:
            retention_days = int(retention_match.group(1))
            row["retentionDays"].append(retention_days)
            retention_values.append(retention_days)

        uses_match = uses_pattern.search(stripped)
        if uses_match:
            row["usesCount"] += 1
            action_ref = uses_match.group(1)
            if action_ref.startswith("./") or action_ref.startswith("docker://"):
                continue

            if "@" not in action_ref:
                row["externalActionsUnpinned"] += 1
                unpinned_actions.append({"workflow": workflow_path.name, "action": action_ref, "ref": "missing"})
                continue

            action_name, ref = action_ref.rsplit("@", 1)
            if re.fullmatch(r"[0-9a-f]{40,64}", ref):
                row["externalActionsPinned"] += 1
                external_actions_pinned += 1
            else:
                row["externalActionsUnpinned"] += 1
                unpinned_actions.append({"workflow": workflow_path.name, "action": action_name, "ref": ref})

    row["runnerCounts"] = dict(runner_counts)
    if row["scheduled"]:
        scheduled_workflows += 1
    cache_uses += row["cacheUses"]
    artifact_uses += row["artifactUses"]
    api_usage_hits += row["ghApiUsageHits"]
    github_hosted_mentions += sum(count for runner, count in runner_counts.items() if any(token in runner for token in ["ubuntu-latest", "macos-latest", "windows-latest"]))
    self_hosted_mentions += sum(count for runner, count in runner_counts.items() if "self-hosted" in runner)
    workflow_rows.append(row)

run_history = []
if run_history_file.exists():
    try:
        run_history = json.loads(run_history_file.read_text(encoding="utf-8"))
    except Exception:
        run_history = []

conclusion_counts = Counter()
workflow_history_counts = Counter()
for entry in run_history if isinstance(run_history, list) else []:
    conclusion_counts[str(entry.get("conclusion") or "unknown")] += 1
    workflow_history_counts[str(entry.get("workflowName") or "unknown")] += 1

total_runs = sum(conclusion_counts.values())
success_runs = conclusion_counts.get("success", 0)
failure_runs = conclusion_counts.get("failure", 0)
skipped_runs = conclusion_counts.get("skipped", 0)
skip_ratio = (skipped_runs / total_runs) if total_runs else 0.0

policy_notes = [
    "Pinned external actions are the baseline; keep them immutable so supply-chain drift stays low.",
    "Artifact retention should remain capped at 90 days.",
    "Cache-backed installs and generated reports are preferred to repeated raw re-downloads.",
    "Scheduled workflows should exist only where they produce a measurable operational signal.",
    "Skip-heavy gating workflows indicate avoided waste when they intentionally short-circuit no-op paths.",
]

optimization_plan = [
    "Keep GitHub-hosted runners only where native GitHub integration is required.",
    "Keep artifact retention at or below 90 days.",
    "Re-use pinned first-party actions and shared scripts instead of duplicating workflow logic.",
    "Prefer cache-backed dependency installs over cold fetches on every run.",
    "Review run-history trend monthly so skip ratio and workflow count stay visible.",
]

result = {
    "generatedAt": datetime.now(timezone.utc).isoformat(timespec="seconds"),
    "workflowsScanned": len(workflow_files),
    "scheduledWorkflows": scheduled_workflows,
    "githubHostedRunnerMentions": github_hosted_mentions,
    "selfHostedRunnerMentions": self_hosted_mentions,
    "externalActionsPinned": external_actions_pinned,
    "externalActionsUnpinned": len(unpinned_actions),
    "cacheUses": cache_uses,
    "artifactUses": artifact_uses,
    "maxArtifactRetentionDays": max(retention_values) if retention_values else 0,
    "ghApiUsageHits": api_usage_hits,
    "workflowInventory": workflow_rows,
    "workflowRunHistory": {
        "file": str(run_history_file),
        "totalRuns": total_runs,
        "successRuns": success_runs,
        "failureRuns": failure_runs,
        "skippedRuns": skipped_runs,
        "skipRatio": round(skip_ratio, 4),
        "topWorkflows": [{"workflowName": name, "runs": count} for name, count in workflow_history_counts.most_common(8)],
    },
    "policyNotes": policy_notes,
    "optimizationPlan": optimization_plan,
    "violations": {
        "unpinnedActions": unpinned_actions,
        "artifactRetentionOver90": [value for value in retention_values if value > 90],
    },
}

report_json.write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")

lines = []
lines.append("# GitHub Free Maximization Report")
lines.append("")
lines.append(f"- Generated: {result['generatedAt']}")
lines.append(f"- Workflows scanned: {result['workflowsScanned']}")
lines.append(f"- Scheduled workflows: {result['scheduledWorkflows']}")
lines.append(f"- GitHub-hosted runner mentions: {result['githubHostedRunnerMentions']}")
lines.append(f"- Self-hosted runner mentions: {result['selfHostedRunnerMentions']}")
lines.append(f"- External actions pinned: {result['externalActionsPinned']}")
lines.append(f"- External actions unpinned: {result['externalActionsUnpinned']}")
lines.append(f"- Cache uses: {result['cacheUses']}")
lines.append(f"- Artifact uses: {result['artifactUses']}")
lines.append(f"- Max artifact retention days: {result['maxArtifactRetentionDays']}")
lines.append(f"- GH API usage hits in workflows: {result['ghApiUsageHits']}")
lines.append("")
lines.append("## Run History Baseline")
lines.append("")
lines.append(f"- Total runs in `artifacts/metrics/gh-runs-raw.json`: {total_runs}")
lines.append(f"- Success: {success_runs}")
lines.append(f"- Failure: {failure_runs}")
lines.append(f"- Skipped: {skipped_runs}")
lines.append(f"- Skip ratio: {skip_ratio:.2%}")
lines.append("")
lines.append("## Policy Notes")
for note in policy_notes:
    lines.append(f"- {note}")
lines.append("")
lines.append("## Optimization Plan")
for item in optimization_plan:
    lines.append(f"- {item}")
lines.append("")
lines.append("## Workflow Inventory")
lines.append("")
lines.append("| Workflow | uses | pinned external | unpinned external | cache uses | artifact uses | runners | retention-days | scheduled |")
lines.append("|---|---:|---:|---:|---:|---:|---|---|---|")
for row in workflow_rows:
    runner_summary = ", ".join(f"{runner}: {count}" for runner, count in row["runnerCounts"].items()) or "n/a"
    retention_summary = ", ".join(str(value) for value in row["retentionDays"]) or "n/a"
    lines.append(
        f"| {row['file']} | {row['usesCount']} | {row['externalActionsPinned']} | {row['externalActionsUnpinned']} | {row['cacheUses']} | {row['artifactUses']} | {runner_summary} | {retention_summary} | {'yes' if row['scheduled'] else 'no'} |"
    )
lines.append("")
lines.append("## Validation Status")
lines.append("")
lines.append(f"- Strict mode: {'PASS' if strict_mode and not result['violations']['unpinnedActions'] and not result['violations']['artifactRetentionOver90'] else 'FAIL'}")
lines.append(f"- Violations: {len(result['violations']['unpinnedActions'])} unpinned actions, {len(result['violations']['artifactRetentionOver90'])} retention overruns")
lines.append("")
lines.append("## Actionable Next Step")
lines.append("")
lines.append("- Keep the current workflow inventory under review and maintain the 90-day artifact ceiling while reusing pinned actions and cache-backed installs.")

report_md.write_text("\n".join(lines) + "\n", encoding="utf-8")

if strict_mode and result["violations"]["unpinnedActions"]:
    for violation in result["violations"]["unpinnedActions"]:
        print(f"unpinned action: {violation['workflow']} -> {violation['action']}@{violation['ref']}", file=sys.stderr)
    raise SystemExit(1)

if strict_mode and result["violations"]["artifactRetentionOver90"]:
    print("artifact retention exceeds 90 days", file=sys.stderr)
    raise SystemExit(1)

print(f"GitHub Free maximization baseline written to {report_md}")
PY
#!/usr/bin/env bash
# @file        scripts/ci/check-github-free-usage.sh
# @module      ci/finops
# @description Inventory GitHub Actions usage and publish a GitHub Free optimization baseline.
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../_common/init.sh"

REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
WORKFLOW_DIR="${WORKFLOW_DIR:-$REPO_ROOT/.github/workflows}"
REPORT_DIR="${REPORT_DIR:-$REPO_ROOT/artifacts/triage}"
REPORT_JSON="${REPORT_JSON:-$REPORT_DIR/github-free-maximization-report.json}"
REPORT_MD="${REPORT_MD:-$REPORT_DIR/github-free-maximization-report.md}"
RUN_HISTORY_FILE="${RUN_HISTORY_FILE:-$REPO_ROOT/artifacts/metrics/gh-runs-raw.json}"
STRICT_MODE="${STRICT_MODE:-1}"

require_command python3
mkdir -p "$REPORT_DIR"

python3 - "$WORKFLOW_DIR" "$REPORT_JSON" "$REPORT_MD" "$RUN_HISTORY_FILE" "$STRICT_MODE" <<'PY'
import json
import re
import sys
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path

workflow_dir = Path(sys.argv[1])
report_json = Path(sys.argv[2])
report_md = Path(sys.argv[3])
run_history_file = Path(sys.argv[4])
strict_mode = sys.argv[5] == "1"

uses_pattern = re.compile(r"uses:\s*([^\s#]+)")
runner_pattern = re.compile(r"runs-on:\s*(.+)$")
retention_pattern = re.compile(r"retention-days:\s*(\d+)")

workflow_files = sorted(list(workflow_dir.glob("*.yml")) + list(workflow_dir.glob("*.yaml")))

workflow_rows = []
unpinned_actions = []
retention_values = []
scheduled_workflows = 0
cache_uses = 0
artifact_uses = 0
api_usage_hits = 0
github_hosted_mentions = 0
self_hosted_mentions = 0
external_actions_pinned = 0

for workflow_path in workflow_files:
    text = workflow_path.read_text(encoding="utf-8", errors="replace")
    lines = text.splitlines()
    row = {
        "file": workflow_path.name,
        "usesCount": 0,
        "externalActionsPinned": 0,
        "externalActionsUnpinned": 0,
        "cacheUses": 0,
        "artifactUses": 0,
        "scheduled": False,
        "runnerCounts": {},
        "retentionDays": [],
        "ghApiUsageHits": 0,
    }
    runner_counts = Counter()

    for line in lines:
        stripped = line.strip()
        if not stripped:
            continue

        if "cron:" in stripped:
            row["scheduled"] = True

        if "gh issue" in stripped or "github-script" in stripped or "gh api" in stripped:
            row["ghApiUsageHits"] += 1

        if "actions/cache@" in stripped:
            row["cacheUses"] += 1

        if "actions/upload-artifact@" in stripped:
            row["artifactUses"] += 1

        runner_match = runner_pattern.search(stripped)
        if runner_match:
            runner_value = runner_match.group(1).strip().strip("'\"")
            runner_counts[runner_value] += 1

        retention_match = retention_pattern.search(stripped)
        if retention_match:
            retention_days = int(retention_match.group(1))
            row["retentionDays"].append(retention_days)
            retention_values.append(retention_days)

        uses_match = uses_pattern.search(stripped)
        if uses_match:
            row["usesCount"] += 1
            action_ref = uses_match.group(1)
            if action_ref.startswith("./") or action_ref.startswith("docker://"):
                continue

            if "@" not in action_ref:
                row["externalActionsUnpinned"] += 1
                unpinned_actions.append({"workflow": workflow_path.name, "action": action_ref, "ref": "missing"})
                continue

            action_name, ref = action_ref.rsplit("@", 1)
            if re.fullmatch(r"[0-9a-f]{40,64}", ref):
                row["externalActionsPinned"] += 1
                external_actions_pinned += 1
            else:
                row["externalActionsUnpinned"] += 1
                unpinned_actions.append({"workflow": workflow_path.name, "action": action_name, "ref": ref})

    row["runnerCounts"] = dict(runner_counts)
    if row["scheduled"]:
        scheduled_workflows += 1
    cache_uses += row["cacheUses"]
    artifact_uses += row["artifactUses"]
    api_usage_hits += row["ghApiUsageHits"]
    github_hosted_mentions += sum(count for runner, count in runner_counts.items() if any(token in runner for token in ["ubuntu-latest", "macos-latest", "windows-latest"]))
    self_hosted_mentions += sum(count for runner, count in runner_counts.items() if "self-hosted" in runner)
    workflow_rows.append(row)

run_history = []
if run_history_file.exists():
    try:
        run_history = json.loads(run_history_file.read_text(encoding="utf-8"))
    except Exception:
        run_history = []

conclusion_counts = Counter()
workflow_history_counts = Counter()
for entry in run_history if isinstance(run_history, list) else []:
    conclusion_counts[str(entry.get("conclusion") or "unknown")] += 1
    workflow_history_counts[str(entry.get("workflowName") or "unknown")] += 1

total_runs = sum(conclusion_counts.values())
success_runs = conclusion_counts.get("success", 0)
failure_runs = conclusion_counts.get("failure", 0)
skipped_runs = conclusion_counts.get("skipped", 0)
skip_ratio = (skipped_runs / total_runs) if total_runs else 0.0

policy_notes = [
    "Pinned external actions are the baseline; keep them immutable so supply-chain drift stays low.",
    "Artifact retention should remain capped at 90 days.",
    "Cache-backed installs and generated reports are preferred to repeated raw re-downloads.",
    "Scheduled workflows should exist only where they produce a measurable operational signal.",
    "Skip-heavy gating workflows indicate avoided waste when they intentionally short-circuit no-op paths.",
]

optimization_plan = [
    "Keep GitHub-hosted runners only where native GitHub integration is required.",
    "Keep artifact retention at or below 90 days.",
    "Re-use pinned first-party actions and shared scripts instead of duplicating workflow logic.",
    "Prefer cache-backed dependency installs over cold fetches on every run.",
    "Review run-history trend monthly so skip ratio and workflow count stay visible.",
]

result = {
    "generatedAt": datetime.now(timezone.utc).isoformat(timespec="seconds"),
    "workflowsScanned": len(workflow_files),
    "scheduledWorkflows": scheduled_workflows,
    "githubHostedRunnerMentions": github_hosted_mentions,
    "selfHostedRunnerMentions": self_hosted_mentions,
    "externalActionsPinned": external_actions_pinned,
    "externalActionsUnpinned": len(unpinned_actions),
    "cacheUses": cache_uses,
    "artifactUses": artifact_uses,
    "maxArtifactRetentionDays": max(retention_values) if retention_values else 0,
    "ghApiUsageHits": api_usage_hits,
    "workflowInventory": workflow_rows,
    "workflowRunHistory": {
        "file": str(run_history_file),
        "totalRuns": total_runs,
        "successRuns": success_runs,
        "failureRuns": failure_runs,
        "skippedRuns": skipped_runs,
        "skipRatio": round(skip_ratio, 4),
        "topWorkflows": [{"workflowName": name, "runs": count} for name, count in workflow_history_counts.most_common(8)],
    },
    "policyNotes": policy_notes,
    "optimizationPlan": optimization_plan,
    "violations": {
        "unpinnedActions": unpinned_actions,
        "artifactRetentionOver90": [value for value in retention_values if value > 90],
    },
}

report_json.write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")

lines = []
lines.append("# GitHub Free Maximization Report")
lines.append("")
lines.append(f"- Generated: {result['generatedAt']}")
lines.append(f"- Workflows scanned: {result['workflowsScanned']}")
lines.append(f"- Scheduled workflows: {result['scheduledWorkflows']}")
lines.append(f"- GitHub-hosted runner mentions: {result['githubHostedRunnerMentions']}")
lines.append(f"- Self-hosted runner mentions: {result['selfHostedRunnerMentions']}")
lines.append(f"- External actions pinned: {result['externalActionsPinned']}")
lines.append(f"- External actions unpinned: {result['externalActionsUnpinned']}")
lines.append(f"- Cache uses: {result['cacheUses']}")
lines.append(f"- Artifact uses: {result['artifactUses']}")
lines.append(f"- Max artifact retention days: {result['maxArtifactRetentionDays']}")
lines.append(f"- GH API usage hits in workflows: {result['ghApiUsageHits']}")
lines.append("")
lines.append("## Run History Baseline")
lines.append("")
lines.append(f"- Total runs in `artifacts/metrics/gh-runs-raw.json`: {total_runs}")
lines.append(f"- Success: {success_runs}")
lines.append(f"- Failure: {failure_runs}")
lines.append(f"- Skipped: {skipped_runs}")
lines.append(f"- Skip ratio: {skip_ratio:.2%}")
lines.append("")
lines.append("## Policy Notes")
for note in policy_notes:
    lines.append(f"- {note}")
lines.append("")
lines.append("## Optimization Plan")
for item in optimization_plan:
    lines.append(f"- {item}")
lines.append("")
lines.append("## Workflow Inventory")
lines.append("")
lines.append("| Workflow | uses | pinned external | unpinned external | cache uses | artifact uses | runners | retention-days | scheduled |")
lines.append("|---|---:|---:|---:|---:|---:|---|---|---|")
for row in workflow_rows:
    runner_summary = ", ".join(f"{runner}: {count}" for runner, count in row["runnerCounts"].items()) or "n/a"
    retention_summary = ", ".join(str(value) for value in row["retentionDays"]) or "n/a"
    lines.append(
        f"| {row['file']} | {row['usesCount']} | {row['externalActionsPinned']} | {row['externalActionsUnpinned']} | {row['cacheUses']} | {row['artifactUses']} | {runner_summary} | {retention_summary} | {'yes' if row['scheduled'] else 'no'} |"
    )
lines.append("")
lines.append("## Validation Status")
lines.append("")
lines.append(f"- Strict mode: {'PASS' if strict_mode and not result['violations']['unpinnedActions'] and not result['violations']['artifactRetentionOver90'] else 'FAIL'}")
lines.append(f"- Violations: {len(result['violations']['unpinnedActions'])} unpinned actions, {len(result['violations']['artifactRetentionOver90'])} retention overruns")
lines.append("")
lines.append("## Actionable Next Step")
lines.append("")
lines.append("- Keep the current workflow inventory under review and maintain the 90-day artifact ceiling while reusing pinned actions and cache-backed installs.")

report_md.write_text("\n".join(lines) + "\n", encoding="utf-8")

if strict_mode and result["violations"]["unpinnedActions"]:
    for violation in result["violations"]["unpinnedActions"]:
        print(f"unpinned action: {violation['workflow']} -> {violation['action']}@{violation['ref']}", file=sys.stderr)
    raise SystemExit(1)

if strict_mode and result["violations"]["artifactRetentionOver90"]:
    print("artifact retention exceeds 90 days", file=sys.stderr)
    raise SystemExit(1)

print(f"GitHub Free maximization baseline written to {report_md}")
PY
