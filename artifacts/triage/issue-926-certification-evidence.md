# Issue 926 Failover/Failback Certification Evidence

Generated (UTC): 2026-04-20 00:22:47
Issue: #926

## Certification Summary

- Controlled failover drill: PASS
- Controlled failback to primary: PASS
- Deterministic active host markers after failover/failback: PASS (42 -> 31)
- Unauthenticated continuity check across failover window: PASS (Playwright 1/1)
- Auth smoke path: PASS (9 passed, 5 skipped)

## Deterministic Artifact Manifest (sha256)

| Artifact | sha256 |
|---|---|
| artifacts/triage/failover-continuity-20260419.md | 6490dbbc8c3d4a01e6cd04c070928a40cfd4e98243c77838fe89bb9839a63707 |
| artifacts/triage/resilience-campaign-failover-continuity.log | 91926085d39d8d10b8f9c4d9156b5c7a54cabb5fd8e73277a5fa17b10de960fb |
| artifacts/triage/resilience-campaign-authenticated-smoke.log | 1064c84a26bd75f73dc19ae4bd75da4175f52008403e3a26dd6d75704586198a |
| artifacts/triage/primary-restart-2026-04-19.log | 7c91a8348feb530254fef343d0c650892d3fbd479e8d4dfa9b7a2798bcc17370 |
| artifacts/triage/secondary-restart-2026-04-19.log | bf7e97279f2f6b31584dd28d7ae2392046d0d0acb4c76b370a045c85e4885cd8 |
| artifacts/triage/live-surface-baseline.md | 69e846675431d7db7a0263cc5fb7dbcb2fe9e9de5f3bcad49c9e3c51fe376714 |

## Key Evidence Excerpts

- failover-continuity-20260419.md confirms failover to 192.168.168.42 and successful failback to 192.168.168.31.
- resilience-campaign-failover-continuity.log reports Playwright continuity suite passing (1 passed).
- resilience-campaign-authenticated-smoke.log reports login/auth smoke passing (9 passed, 5 skipped).
- primary/secondary restart logs capture health snapshots during transition windows.

## Notes

- This bundle is deterministic via pinned artifact paths and SHA256 manifest.
- Recurring CI entrypoint exists in .github/workflows/e2e-authenticated-failover-continuity.yml.
