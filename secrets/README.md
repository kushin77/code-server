# secrets/ — SOPS-encrypted production secrets
# =============================================
# This directory contains encrypted secrets managed by SOPS + age.
# Never commit plaintext secrets here.
#
# File naming convention:
#   <service>.enc.yaml    — YAML format, SOPS-encrypted
#   <service>.enc.env     — dotenv format, SOPS-encrypted
#
# Encrypt a new secret file:
#   sops -e secrets/database.yaml > secrets/database.enc.yaml
#   rm secrets/database.yaml
#
# Decrypt for local use (never commit decrypted output):
#   sops -d secrets/database.enc.yaml
#
# Edit in-place (re-encrypts automatically on save):
#   sops secrets/database.enc.yaml
#
# Setup:
#   See .sops.yaml for age public key configuration.
#   See scripts/deploy-phase-8-secrets-management.sh for full setup.
#
# Contents:
#   database.enc.yaml   — PostgreSQL credentials
#   redis.enc.yaml      — Redis auth credentials
#   oauth.enc.yaml      — OAuth2 client credentials
#   vrrp.enc.yaml       — Keepalived VRRP auth password
