# Runbooks

## Copilot / GitHub auth inside the IDE

**Why there are two logins:**
- **Login 1 — Google (oauth2-proxy):** Protects access to the IDE URL itself. You log in once with your Google account (`akushnir@bioenergystrategies.com`). This is the guard at the door.
- **Login 2 — GitHub (inside the IDE):** Copilot extensions need a GitHub account to verify your Copilot subscription. This is separate from Google.

These two authentications are for different systems and cannot be merged, but the GitHub one can be **pre-seeded via `GITHUB_TOKEN`** so you never see the interactive prompt.

**Fix: set GITHUB_TOKEN in `.env`**
1. Go to https://github.com/settings/tokens/new (Classic PAT)
2. Give it a name, expiry, and scopes: `read:user` + `user:email`
3. Copy the token value
4. In `.env`: `GITHUB_TOKEN=ghp_xxxxxxxxxxxxxxxxxxxx`
5. Restart code-server: `docker compose restart code-server`

With `GITHUB_TOKEN` set, VS Code's `github-authentication` extension uses it directly — Copilot and Copilot Chat both get tokens without an interactive browser OAuth flow.

**If Copilot Chat still shows "Sign in":**
The IDE may have a cached denied state. Clear it:
1. Visit `https://ide.kushnir.cloud/reset-browser-state` once
2. Reload the IDE
3. The sign-in prompt should resolve automatically using the token from the env var

---

## CI pipeline failure

## Terraform apply failure / state recovery

## Secrets compromise response

## Service outage and escalation path
