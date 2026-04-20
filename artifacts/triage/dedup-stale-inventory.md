# Dedup And Stale Inventory

Generated at (UTC): 2026-04-20 00:18:27
Duplicate groups: 6
Stale components: 32

## Duplicate Groups

- sha256=1e2e3688e192f26720bf0a15b05b452de4efc4c1feffefa43e2cc16ca34d6d85 files=2 size=6075
  - docs\operations\session-history\historical\2026\ops-record-apr16-phase-status-s3.md
  - docs\status\SESSION-3-FINAL-STATUS.md
- sha256=2cfb619277c6449fbaa7b51ab892141349452eddb071485e9920d1301293cbe2 files=2 size=13014
  - docs\operations\session-history\historical\2026\ops-record-apr17-phase2-p2418-s5.md
  - docs\status\SESSION-5-PHASE-2-COMPLETE-AND-P2-418-STARTED.md
- sha256=2f5ca93b0b5556ba53a9a128824aeac1db547023b20c0b54798a61cdfdbd70ee files=2 size=12260
  - docs\operations\session-history\historical\2026\ops-record-apr17-phase21-deploy-s4.md
  - docs\status\SESSION-4-PHASE-2-1-DEPLOYMENT-COMPLETE.md
- sha256=43a491ec716310201bc12685c5bf22e3a1032185f0e19bb7f866cadf9ae1e797 files=2 size=6200
  - docs\operations\session-history\historical\2026\ops-record-apr16-remediation-s3.md
  - docs\status\SESSION-3-REMEDIATION-SUMMARY.md
- sha256=9c3afc8f72d4b2e0a4f2f00680d29ddef52f044b34aef59ba37a6b7a60d4844a files=2 size=5184
  - docs\archives\legacy-archive\gpu-attempts\GPU-UPGRADE-ACTION-NEEDED.txt
  - docs\configs\GPU-UPGRADE-ACTION-NEEDED.txt
- sha256=b47add0a3dfba1b2f2f0052012ea5d055fbecc99f68b450dbb45ab2285c32350 files=2 size=11341
  - docs\operations\session-history\historical\2026\ops-record-apr16-phase-overview-s2.md
  - docs\status\SESSION-2-APRIL-16-2026-SUMMARY.md

## Stale Components

- .github\workflows\shell-lint.yml | reason=marker:deprecated | disposition=remove_or_migrate | owner=Platform Engineering
- .github\workflows\validate-linux-only.yml | reason=marker:deprecated | disposition=remove_or_migrate | owner=Platform Engineering
- .github\workflows\workflow-lint.yml | reason=marker:deprecated | disposition=remove_or_migrate | owner=Platform Engineering
- config\systemd\terminal-output-optimizer.service | reason=marker:do not use | disposition=remove_or_migrate | owner=Platform Engineering
- docs\adr\TEMPLATE.md | reason=marker:deprecated | disposition=remove_or_migrate | owner=Platform Engineering
- docs\archives\legacy-archive\phase-summaries\phase-1\PHASE-1-IMPLEMENTATION-TRACKING.md | reason=marker:deprecated | disposition=remove_or_migrate | owner=Platform Engineering
- docs\archives\legacy-archive\phase-summaries\phase-14\PHASE-14-PREFLIGHT-VERIFICATION.md | reason=marker:deprecated | disposition=remove_or_migrate | owner=Platform Engineering
- docs\archives\legacy-archive\README.md | reason=marker:obsolete | disposition=remove_or_migrate | owner=Platform Engineering
- docs\governance\elite-best-practices\deep\INDEXING-AND-META.md | reason=marker:deprecated | disposition=remove_or_migrate | owner=Platform Engineering
- docs\governance\elite-best-practices\meta\META-DOCUMENT-STANDARDS.md | reason=marker:deprecated | disposition=remove_or_migrate | owner=Platform Engineering
- docs\governance\elite-best-practices\shared\SHARED-LIBRARIES.md | reason=marker:deprecated | disposition=remove_or_migrate | owner=Platform Engineering
- docs\SHARED-LIBRARIES.md | reason=marker:deprecated | disposition=remove_or_migrate | owner=Platform Engineering
- docs\status\AUTONOMOUS-OPEN-ISSUE-STATUS-2026-04-18.md | reason=marker:do not use | disposition=remove_or_migrate | owner=Platform Engineering
- docs\status\CODE-QUALITY-CI-AUDIT-APRIL-19-2026.md | reason=marker:deprecated | disposition=remove_or_migrate | owner=Platform Engineering
- docs\status\DEDUPLICATION-AND-EFFICIENCY-ANALYSIS.md | reason=marker:deprecated | disposition=remove_or_migrate | owner=Platform Engineering
- docs\status\DEPRECATED-REFERENCE-RETIREMENT-APRIL-19-2026.md | reason=marker:deprecated | disposition=remove_or_migrate | owner=Platform Engineering
- docs\status\PROGRAM-TRACKER-INDEX-APRIL-19-2026.md | reason=marker:deprecated | disposition=remove_or_migrate | owner=Platform Engineering
- docs\status\README.md | reason=marker:deprecated | disposition=remove_or_migrate | owner=Platform Engineering
- docs\status\REPO-FUNCTIONALITY-REVIEW.md | reason=marker:deprecated | disposition=remove_or_migrate | owner=Platform Engineering
- docs\status\SESSION-APRIL-17-PHASE2-COMPLETION.md | reason=marker:deprecated | disposition=remove_or_migrate | owner=Platform Engineering
- docs\status\SURVIVABILITY-REVIEW-APRIL-19-2026.md | reason=marker:deprecated | disposition=remove_or_migrate | owner=Platform Engineering
- docs\status\TRIAGE-COMPLETION-REPORT-2026-04-18.md | reason=marker:legacy shim | disposition=remove_or_migrate | owner=Platform Engineering
- scripts\ci\check-root-hygiene.sh | reason=marker:deprecated | disposition=remove_or_migrate | owner=Platform Engineering
- scripts\ci\test-auth-conformance.sh | reason=marker:deprecated | disposition=remove_or_migrate | owner=Platform Engineering
- scripts\code-server-entrypoint.sh | reason=marker:deprecated | disposition=remove_or_migrate | owner=Platform Engineering
- scripts\common-functions.sh | reason=marker:deprecated | disposition=remove_or_migrate | owner=Platform Engineering
- scripts\dev\refactor-phase2-task1.sh | reason=marker:deprecated | disposition=remove_or_migrate | owner=Platform Engineering
- scripts\docker-compose.yml | reason=marker:do not use | disposition=remove_or_migrate | owner=Platform Engineering
- scripts\git-credential-gsm | reason=marker:deprecated | disposition=remove_or_migrate | owner=Platform Engineering
- scripts\logging.sh | reason=marker:deprecated | disposition=remove_or_migrate | owner=Platform Engineering
- scripts\MANIFEST.toml | reason=marker:deprecated | disposition=remove_or_migrate | owner=Platform Engineering
- scripts\ops\drift-detect.sh | reason=marker:deprecated | disposition=remove_or_migrate | owner=Platform Engineering

Machine-readable artifact: artifacts/triage/dedup-stale-inventory.json
