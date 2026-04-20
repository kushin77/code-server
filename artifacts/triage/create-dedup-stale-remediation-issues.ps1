$ErrorActionPreference = 'Stop'
Set-Location 'C:\code-server-enterprise'

$payload = Get-Content 'artifacts/triage/dedup-stale-findings-clustered.json' -Raw | ConvertFrom-Json
$created = @()

foreach ($f in $payload.findings) {
  $evidenceLines = ($f.evidence | ForEach-Object { "- $_" }) -join "`n"
  $body = @"
Parent: #928

## Finding
Category: $($f.category)
Owner: $($f.owner)
Decision: $($f.decision)

## Evidence
$evidenceLines

## Expected remediation
- Apply keep/remove/archive decision for all listed surfaces.
- Add regression guard in CI to prevent reintroduction.
- Post before/after scan evidence linked to #928.

## Acceptance criteria
- [ ] Decision implemented for all evidence items
- [ ] CI guard added or updated to enforce decision
- [ ] #928 updated with remediation evidence and metric delta
"@

  $url = gh issue create --repo kushin77/code-server --label P1 --title "$($f.title)" --body $body
  $created += [PSCustomObject]@{
    key = $f.key
    title = $f.title
    url = $url.Trim()
  }
}

$created | ConvertTo-Json -Depth 5 | Set-Content -Encoding UTF8 'artifacts/triage/dedup-stale-remediation-issues.json'
$created | ForEach-Object { "[$($_.key)] $($_.url)" }
