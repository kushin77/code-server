$ErrorActionPreference = 'Stop'
Set-Location 'C:\code-server-enterprise'

$findings = @(
  [PSCustomObject]@{
    key = 'dup-session-history-status-mirrors'
    title = 'P1: Remove duplicated session status mirrors between docs/status and docs/operations/session-history'
    category = 'duplicate'
    owner = 'Platform Engineering'
    decision = 'keep canonical status docs; replace historical mirrors with links'
    evidence = @(
      'docs/operations/session-history/historical/2026/ops-record-apr16-phase-status-s3.md == docs/status/SESSION-3-FINAL-STATUS.md',
      'docs/operations/session-history/historical/2026/ops-record-apr17-phase2-p2418-s5.md == docs/status/SESSION-5-PHASE-2-COMPLETE-AND-P2-418-STARTED.md',
      'docs/operations/session-history/historical/2026/ops-record-apr17-phase21-deploy-s4.md == docs/status/SESSION-4-PHASE-2-1-DEPLOYMENT-COMPLETE.md',
      'docs/operations/session-history/historical/2026/ops-record-apr16-remediation-s3.md == docs/status/SESSION-3-REMEDIATION-SUMMARY.md',
      'docs/operations/session-history/historical/2026/ops-record-apr16-phase-overview-s2.md == docs/status/SESSION-2-APRIL-16-2026-SUMMARY.md'
    )
  },
  [PSCustomObject]@{
    key = 'dup-gpu-upgrade-note'
    title = 'P1: Deduplicate GPU upgrade action note across archive and configs paths'
    category = 'duplicate'
    owner = 'Platform Engineering'
    decision = 'keep config-facing location and replace archive copy with pointer'
    evidence = @(
      'docs/archives/legacy-archive/gpu-attempts/GPU-UPGRADE-ACTION-NEEDED.txt == docs/configs/GPU-UPGRADE-ACTION-NEEDED.txt'
    )
  },
  [PSCustomObject]@{
    key = 'stale-shim-scripts'
    title = 'P1: Retire deprecated script shims and enforce _common canonical imports'
    category = 'stale'
    owner = 'Platform Engineering'
    decision = 'remove deprecated shims after migration + add CI guard'
    evidence = @(
      'scripts/common-functions.sh',
      'scripts/logging.sh',
      'scripts/code-server-entrypoint.sh',
      'scripts/git-credential-gsm',
      'scripts/ops/drift-detect.sh'
    )
  },
  [PSCustomObject]@{
    key = 'stale-workflow-rules'
    title = 'P1: Remove deprecated workflow definitions and migrate checks to active templates'
    category = 'stale'
    owner = 'Platform Engineering'
    decision = 'remove or archive deprecated workflows; keep active template-based gates only'
    evidence = @(
      '.github/workflows/shell-lint.yml',
      '.github/workflows/validate-linux-only.yml',
      '.github/workflows/workflow-lint.yml'
    )
  },
  [PSCustomObject]@{
    key = 'stale-governance-doc-copies'
    title = 'P1: Clean deprecated governance/status document copies and keep single canonical references'
    category = 'stale'
    owner = 'Platform Engineering'
    decision = 'replace deprecated docs with redirects/index links to SSOT'
    evidence = @(
      'docs/governance/elite-best-practices/shared/SHARED-LIBRARIES.md',
      'docs/governance/elite-best-practices/meta/META-DOCUMENT-STANDARDS.md',
      'docs/governance/elite-best-practices/deep/INDEXING-AND-META.md',
      'docs/status/PROGRAM-TRACKER-INDEX-APRIL-19-2026.md',
      'docs/status/REPO-FUNCTIONALITY-REVIEW.md'
    )
  },
  [PSCustomObject]@{
    key = 'stale-do-not-use-configs'
    title = 'P1: Eliminate do-not-use config surfaces from active scan paths'
    category = 'stale'
    owner = 'Platform Engineering'
    decision = 'archive and exclude from active ops paths with explicit replacement pointers'
    evidence = @(
      'scripts/docker-compose.yml',
      'config/systemd/terminal-output-optimizer.service',
      'docs/status/AUTONOMOUS-OPEN-ISSUE-STATUS-2026-04-18.md'
    )
  }
)

$out = [PSCustomObject]@{
  generatedAtUtc = (Get-Date).ToUniversalTime().ToString('o')
  parentIssue = 928
  findings = $findings
  findingCount = $findings.Count
}

$out | ConvertTo-Json -Depth 8 | Set-Content -Encoding UTF8 'artifacts/triage/dedup-stale-findings-clustered.json'

$md = @(
  '# Dedup/Stale Findings (Clustered)',
  '',
  ('Generated at (UTC): ' + (Get-Date).ToUniversalTime().ToString('yyyy-MM-dd HH:mm:ss')),
  'Parent issue: #928',
  ('Finding count: ' + $findings.Count),
  ''
)

foreach ($f in $findings) {
  $md += ('## ' + $f.title)
  $md += ('- key: ' + $f.key)
  $md += ('- category: ' + $f.category)
  $md += ('- owner: ' + $f.owner)
  $md += ('- decision: ' + $f.decision)
  $md += '- evidence:'
  foreach ($e in $f.evidence) {
    $md += ('  - ' + $e)
  }
  $md += ''
}

$md | Set-Content -Encoding UTF8 'artifacts/triage/dedup-stale-findings-clustered.md'
Write-Output ('clustered_findings=' + $findings.Count)
