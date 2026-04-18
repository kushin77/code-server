# Security Triage Issue Drafts (April 18, 2026)

## Blocker
GitHub API returned HTTP 403 secondary content-creation rate limit while attempting to create or comment on issues.

- Message: You have exceeded a secondary rate limit and have been temporarily blocked from content creation.
- Scope affected: issue creation and issue comments.

## Draft Issue 1
Title: P0 Security hardening rollout: JWT/OAuth/network/token handling (implemented)
Labels: security, triage, high-priority

Body:
Security triage and implementation executed on April 18, 2026.

Scope:
Cloudflare/DNS/edge -> reverse proxy/auth -> runtime/container -> token validation code.

Implemented now:
- [x] Enforce cryptographic JWT validation in lib/jwt_validator.py
  - RS256 algorithm pinning
  - JWKS-derived key verification
  - required claims (exp, iat, aud)
  - optional issuer enforcement via TOKEN_EXPECTED_ISSUER
- [x] Harden OAuth2 defaults in oauth2-proxy.cfg
  - remove wildcard email domain
  - enforce managed domain + explicit allowed emails file
  - set cookie-samesite=strict
- [x] Harden compose auth policy in docker-compose.base.yml
  - enforce OAUTH2_PROXY_EMAIL_DOMAINS
  - enforce OAUTH2_PROXY_AUTHENTICATED_EMAILS_FILE
  - set OAUTH2_PROXY_COOKIE_SAMESITE=strict
- [x] Reduce exposure of Ollama API in docker-compose.base.yml
  - replace host port publish with internal expose
- [x] Minimize production host attack surface in docker-compose.production.yml
  - Caddy admin API bound to localhost
  - observability/data/service ports bound to localhost only
- [x] Harden cloudflared setup in scripts/setup-cloudflare-tunnel.sh
  - avoid token in process args
  - move token into root-owned env file
  - enable strict shell mode and safer curl flags
  - optional checksum validation for binary install
- [x] Remove ExternalDNS token from process args in terraform/modules/dns/main.tf
  - switch to CF_API_TOKEN env var
  - remove invalid --cloudflare-api-key usage

Validation run:
- python3 -m py_compile lib/jwt_validator.py
- bash -n scripts/setup-cloudflare-tunnel.sh
- editor diagnostics on touched files showed no errors
- terraform fmt could not run in this environment (terraform binary unavailable)

Risk notes:
- This issue tracks code/config hardening only.
- Cloudflare account-side controls and runtime architecture debt are tracked in follow-up issues.

## Draft Issue 2
Title: P1 Cloudflare edge and DNS enterprise hardening backlog
Labels: security, cloudflare, dns, triage

Body:
Follow-up from security triage: Cloudflare/DNS controls requiring account-side or infra-level rollout.

Priority:
P1

Required controls:
- [ ] Enable Cloudflare SSL mode: Full (strict)
- [ ] Enable Authenticated Origin Pulls
- [ ] Enforce WAF managed rules + custom rules for oauth2 callback abuse and scanner traffic
- [ ] Enable bot management and adaptive rate limits for auth/websocket paths
- [ ] Verify/lock DNSSEC at registrar and Cloudflare; add CAA records and registrar lock
- [ ] Alerting for zone changes and access policy changes
- [ ] Restrict Cloudflare API token scopes to least privilege

Acceptance criteria:
- Documented runbook for each control
- Evidence artifacts (screenshots/export or CLI output)
- Security sign-off from platform owner

## Draft Issue 3
Title: P1 Runtime security debt: Vault mode, privilege boundaries, and CI policy gates
Labels: security, terraform, runtime, triage

Body:
Follow-up from security triage for architecture/runtime debt not fully remediated in this pass.

Priority:
P1

Findings to remediate:
- [ ] terraform/modules/security/main.tf uses Vault dev token mode (VAULT_DEV_ROOT_TOKEN_ID)
- [ ] terraform/modules/security/main.tf Falco runs with privileged + host network/pid (needs hardening review and compensating controls)
- [ ] Caddyfile.production references/import behavior should be validated against active deployment path
- [ ] Add CI policy checks to block:
  - token/secret in process args
  - wildcard identity allowlists
  - broad 0.0.0.0 service exposure

Acceptance criteria:
- Production-safe Vault deployment mode documented and implemented
- Runtime privilege model reduced or formally justified with threat model
- Caddy production config passes caddy validate in CI with canonical includes
- New security policy checks enforced in CI pipeline
