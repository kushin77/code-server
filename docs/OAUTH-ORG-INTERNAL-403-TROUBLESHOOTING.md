# Fix org_internal 403

## Summary

Issue #643 was caused by a configuration split between the two OAuth surfaces:

- `oauth2-proxy` for the IDE allowed `email-domains = "*"`
- `oauth2-proxy-portal` for `kushnir.cloud` defaulted to `bioenergystrategies.com`

That portal-side restriction caused Google to reject `kushin77@gmail.com` during the OAuth handshake with `Error 403: org_internal` before `allowed-emails.txt` could be evaluated.

## Root Cause

The intended access model in this repository is:

1. Allow any Google account to complete the OAuth handshake.
2. Enforce actual access with `authenticated-emails-file` and repository-managed policy.

The deployed portal defaults violated that model by using a restrictive `OAUTH2_PROXY_EMAIL_DOMAINS` value. That made Google apply organization-only gating at the identity provider layer.

## Fixed Configuration

The correct baseline is:

- `OAUTH2_PROXY_EMAIL_DOMAINS="*"` for IDE and portal surfaces
- `OAUTH2_PROXY_AUTHENTICATED_EMAILS_FILE=/etc/oauth2-proxy/allowed-emails.txt`
- `OAUTH2_PROXY_PROMPT="select_account"` to keep account selection explicit

This keeps authentication broad enough to avoid `org_internal` failures while preserving explicit authorization in the allowlist and policy bundle.

## Verification

Run these checks from the repository root:

```bash
bash scripts/auth/test-org-internal-access.sh
bash scripts/auth/auth-policy-drift-detection.sh verify
grep -n "OAUTH2_PROXY_EMAIL_DOMAINS" docker-compose.yml docker-compose.production.yml .env.example .env.defaults
```

Expected results:

- both compose surfaces default to `*`
- env templates default to `*`
- drift detection passes
- test suite reports no `org_internal` regression

## Production Validation

On the deployment host:

```bash
docker compose up -d oauth2-proxy oauth2-proxy-portal
docker compose logs oauth2-proxy-portal --tail 100 | grep -Ei "org_internal|403|denied"
```

Then validate in a private browser session:

1. Open `https://kushnir.cloud`
2. Choose the intended Google account
3. Complete the OAuth consent flow
4. Confirm the user reaches the portal instead of a Google `org_internal` 403 page

## If the Error Returns

Check these in order:

1. `docker-compose.yml` and deployed env vars still use `OAUTH2_PROXY_EMAIL_DOMAINS="*"`
2. `allowed-emails.txt` contains the target account
3. Google Cloud Console redirect URIs still include `https://kushnir.cloud/oauth2/callback`
4. No environment override reintroduced `bioenergystrategies.com` or another restrictive domain
5. Alert `AuditOAuth403Detected` has not been firing with new samples

## Rollback

If a deploy introduces unexpected auth behavior, revert the OAuth-related config change and redeploy the affected proxy containers:

```bash
git revert <commit>
docker compose up -d oauth2-proxy oauth2-proxy-portal
```

Do not restore restrictive domain filters unless the allowlist strategy is intentionally being replaced everywhere.