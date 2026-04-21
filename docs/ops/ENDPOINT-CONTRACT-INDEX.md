# Endpoint Contract Index

Purpose: canonical SSOT for external, internal, auth, and health endpoints used by the on-prem code-server stack.

## Canonical Surfaces

| Surface | Endpoint | Owner | Auth | Backend / Target | Expected Behavior |
|---|---|---|---|---|---|
| Portal root | `https://kushnir.cloud/` | Platform Engineering | OAuth2-protected | Caddy -> oauth2-proxy -> portal app | Redirects unauthenticated users to login |
| IDE root | `https://ide.kushnir.cloud/` | Platform Engineering | OAuth2-protected | Caddy -> oauth2-proxy -> code-server | Redirects unauthenticated users to login |
| OAuth start | `/oauth2/start` | Identity / Platform | Auth gateway | oauth2-proxy | Begins OIDC handshake |
| OAuth auth | `/oauth2/auth` | Identity / Platform | Auth gateway | oauth2-proxy | Returns 202/401 auth decision |
| OAuth callback | `/oauth2/callback` | Identity / Platform | Auth gateway | oauth2-proxy | Completes provider callback |
| OAuth sign-in | `/oauth2/sign_in` | Identity / Platform | Auth gateway | oauth2-proxy | Initiates sign-in helper flow |
| OAuth sign-out | `/oauth2/sign_out` | Identity / Platform | Auth gateway | oauth2-proxy | Clears session and redirects |
| Code-server health | `/healthz` | Platform Engineering | Internal / unauthenticated health | code-server | Returns 200 when service is healthy |
| Caddy health | `/healthz` | Platform Engineering | Internal | Caddy | Returns 200 when ingress is healthy |
| OAuth proxy health | `/ping` | Identity / Platform | Internal / unauthenticated health | oauth2-proxy | Returns 200 when auth gateway is healthy |
| Prometheus health | `/-/healthy` | Platform Engineering | Internal | Prometheus | Returns 200 when metrics backend is healthy |
| Grafana health | `/api/health` | Platform Engineering | Internal | Grafana | Returns 200 when visualization backend is healthy |
| Alertmanager health | `/-/healthy` | Platform Engineering | Internal | Alertmanager | Returns 200 when alert routing backend is healthy |
| Monitoring | `/metrics` | Platform Engineering | Internal / service-specific | Prometheus, Grafana, Alertmanager, exporters | Returns metrics for observability stack |

## Auth and Routing Rules

1. OAuth-sensitive routes must remain defined in one place per surface and cannot diverge across Compose, Terraform, and docs.
2. `kushnir.cloud` and `ide.kushnir.cloud` must preserve distinct redirect and cookie behavior where the deployment requires it.
3. Health endpoints are for automated validation and should fail closed if a service is degraded.
4. Any new public route must be added here before it is considered production-ready.

## Contract Sources

- [docs/adr/002-oauth2-authentication.md](../adr/002-oauth2-authentication.md)
- docs/adr/ADR-002-UNIFIED-IDENTITY-ARCHITECTURE.md
- [docs/ops/OPERATIONS-INDEX.md](OPERATIONS-INDEX.md)
- [scripts/ci/validate-oidc-issuer-contract.sh](../../scripts/ci/validate-oidc-issuer-contract.sh)
- [scripts/e2e-test-suite.sh](../../scripts/e2e-test-suite.sh)
- [docs/status/OAUTH2-RESOLUTION-SUMMARY.md](../status/OAUTH2-RESOLUTION-SUMMARY.md)

## Evidence Notes

- Canonical endpoint and auth contracts are validated by the OIDC issuer contract check and the authenticated E2E suite.
- Endpoint drift should be treated as a release blocker until the index and runtime behavior match.
