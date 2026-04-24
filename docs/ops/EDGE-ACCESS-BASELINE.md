# Edge Access Baseline

This document defines the canonical zero-trust edge and administrative access model for the on-prem platform.

## Scope

- Primary production host: `192.168.168.31`
- Replica host: `192.168.168.42`
- Services covered: host administration, SSH transport, Cloudflare Tunnel, and SSH proxy access

## Baseline

1. External access must flow through Cloudflare Tunnel and Cloudflare Access.
2. SSH must remain available for VS Code and admin workflows, but direct public exposure on port `22` must be blocked.
3. SSH-based developer access should prefer the dedicated SSH proxy on port `2222` or another explicitly approved private path.
4. Host SSH hardening must remain fail-closed: root login disabled, password authentication disabled, and key-based access only.
5. Any exception for break-glass access must be time-bounded, reviewed, and recorded in the issue tracker.

## Compensating Controls

- Cloudflare Tunnel bootstrap: [../../scripts/setup-cloudflare-tunnel.sh](../../scripts/setup-cloudflare-tunnel.sh)
- SSH proxy contract: [../../config/ssh-proxy.conf](../../config/ssh-proxy.conf)
- Security audit gate: [../../scripts/security-audit.sh](../../scripts/security-audit.sh)
- Host hardening playbook: [../../ansible/site-hardening.yml](../../ansible/site-hardening.yml)

## Verification

The baseline is considered healthy only when all of the following are true:

- `cloudflared` is running.
- The SSH proxy is running on `2222`.
- `sshd` is hardened to reject password and root logins.
- Port `22` is not publicly exposed from the host network path.
- SSH remains reachable only through an approved private, tunneled, or proxied path.

## Operational Notes

- This document is the SSOT for edge/access posture; ad hoc access instructions should not redefine the baseline.
- Any new access path must be added here before it is deployed.