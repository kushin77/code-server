# Enterprise code-server Deployment

This repository runs a production-style code-server stack behind oauth2-proxy and Caddy.

## Runtime Architecture

- code-server runs inside Docker and is not directly exposed to the internet.
- oauth2-proxy handles Google OIDC authentication.
- Caddy terminates TLS and proxies authenticated traffic.
- Runtime orchestration is managed by Docker Compose.
- Terraform is used for metadata, validation, and outputs.

## Quick Start

1. Create and populate `.env` (domain, OAuth credentials, DNS challenge token, code-server password).
2. Deploy and verify runtime:

```powershell
pwsh -NoProfile -File .\scripts\mandatory-redeploy.ps1
```

3. Validate functional readiness:

```powershell
pwsh -NoProfile -File .\scripts\smoke-check.ps1
```

4. Access the IDE at your domain:

```text
https://<your-domain>
```

## Day-2 Operations

- Full apply flow (Terraform outputs + runtime rollout + smoke checks):

```powershell
make apply
```

- Runtime-only rollout:

```powershell
make redeploy
```

- Runtime-only validation:

```powershell
make smoke
```

- Service status:

```powershell
make status
```

## Security Notes

- Do not store production secrets in `terraform.tfvars`.
- Keep runtime secrets in `.env` or your secret manager workflow.
- Use `/reset-browser-state` only when stale browser cache/storage causes client issues.
- Do not clear site data on every request; this can force re-auth loops.
