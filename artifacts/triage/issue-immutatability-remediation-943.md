## Summary
CI immutability evidence found an unpinned Dockerfile base image in docker/haproxy/Dockerfile (line 1), which currently fails the immutability gate.

## Evidence
- Artifact: artifacts/triage/image-immutability-report.log
- Summary artifact: artifacts/triage/image-immutability-report-summary.log
- Current finding: unpinned Dockerfile base image: haproxy:2.8-alpine

## Required Remediation
1. Pin docker/haproxy/Dockerfile base image to immutable digest (keep semantic tag + digest).
2. Re-run scripts/ci/check-image-immutability.sh and attach passing output.
3. Ensure PR/CI path enforces this gate on future Dockerfile changes.

## Definition of Done
- [ ] docker/haproxy/Dockerfile uses digest-pinned base image
- [ ] scripts/ci/check-image-immutability.sh passes
- [ ] Evidence artifact linked in issue comments
- [ ] Parent issue #928 updated with closure link

Fixes #928 (sub-remediation)
