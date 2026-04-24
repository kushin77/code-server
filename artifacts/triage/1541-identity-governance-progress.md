## P2 #1541 Identity & Credentials Progress

Implemented:
- Added `docs/security/SSH-KEY-INVENTORY.md`
- Added `docs/security/SERVICE-ACCOUNT-INVENTORY.md`
- Documented the canonical on-prem SSH identity and known service accounts

CI enforcement:
- Added `scripts/ci/validate-identity-governance.sh`
- Wired identity validation into `.github/workflows/code-smell-governance.yml`

Validation:
- `bash scripts/ci/validate-identity-governance.sh` passed
- Verified `scripts/ops/setup-passwordless-sudo.sh` remains on canonical init/bootstrap
- Verified `scripts/ops/rotate-qa-credentials.py` uses timezone-aware audit timestamps
