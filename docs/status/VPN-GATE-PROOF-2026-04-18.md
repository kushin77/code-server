# VPN Gate Proof — 2026-04-18

Purpose:
- Capture proof that the VPN-only E2E gate is implemented as a portable, idempotent script and wired into CI via a self-hosted workflow.

Artifacts:
- [scripts/ci/check-vpn-gate.sh](../../scripts/ci/check-vpn-gate.sh)
- [.github/workflows/vpn-e2e-gate.yml](../../.github/workflows/vpn-e2e-gate.yml)

Verified script behavior:
1. Explicit override success path
   - `VPN_LOCAL_IP=10.0.0.5 bash scripts/ci/check-vpn-gate.sh`
   - Result: PASS inside allowed VPN CIDR range

2. Default operator path
   - `bash scripts/ci/check-vpn-gate.sh --warn-only`
   - Result: PASS in this workspace using the detected private network address

Implementation notes:
- The gate now uses a fallback chain for local IP detection:
  - `VPN_LOCAL_IP` override
  - `ip route get`
  - `hostname -I`
  - `ifconfig`
- The gate remains fail-fast by default and only downgrades to warning mode when explicitly requested.
- The workflow is self-hosted so the gate runs in the same operational environment as the production E2E path.

Evidence summary:
- Gate logic is immutable and self-contained.
- Detection is portable across host/container environments.
- CI integration exists as a dedicated workflow for main and pull-request changes.

Operational note:
- This is gate evidence, not a full production E2E run. The gate should still be paired with operator validation on the self-hosted runner.