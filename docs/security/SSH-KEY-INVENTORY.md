# SSH Key Inventory

This document records the canonical SSH identities used for on-prem deployment and maintenance. It is the single source of truth for ownership, rotation, and storage expectations.

## Inventory

| Key | Owner | Purpose | Used By | Storage | Rotation | Status | Notes |
|---|---|---|---|---|---|---|---|
| `~/.ssh/id_rsa_onprem` | `akushnir` | On-prem deployment SSH access to `192.168.168.31` and `192.168.168.42` | `scripts/ops/setup-passwordless-sudo.sh`, deployment and redeploy helpers | Local operator workstation; never committed to git | 90 days | Active | Canonical deployment identity referenced by bootstrap scripts |

## Rotation Procedure

1. Generate a replacement SSH key pair on the operator workstation.
2. Add the public key to the target hosts using the approved IaC or bootstrap path.
3. Update local automation to reference the new private key path if required.
4. Verify passwordless sudo and a no-op SSH command on both replicas.
5. Archive the retired fingerprint in the deployment evidence record.

## Verification Commands

```bash
ssh -i ~/.ssh/id_rsa_onprem akushnir@192.168.168.31 'sudo -n true'
ssh -i ~/.ssh/id_rsa_onprem akushnir@192.168.168.42 'sudo -n true'
```

## Notes

- The inventory should be updated whenever a deployment key is rotated, retired, or replaced.
- Do not store SSH private keys in git, artifacts, or shared logs.