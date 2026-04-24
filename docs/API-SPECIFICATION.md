# API Specification SSOT

Purpose: canonical inventory of checked-in API contracts and the enforcement path for internal HTTP surfaces.

## Current Status

- `apps/session-broker` now has a checked-in OpenAPI 3.1 spec in [docs/api/session-broker.openapi.yaml](api/session-broker.openapi.yaml).
- `services/token-microservice` now has a checked-in OpenAPI 3.1 spec in [docs/api/token-microservice.openapi.yaml](api/token-microservice.openapi.yaml).
- `services/git-proxy-server.py` now has a checked-in OpenAPI 3.1 spec in [docs/api/git-proxy-server.openapi.yaml](api/git-proxy-server.openapi.yaml).
- `apps/backend` does not currently expose a checked-in HTTP API entrypoint in the repo, so there is no spec file for it yet.

## Scope

This SSOT covers internal and external HTTP APIs that are part of the repository runtime surface.

## Canonical Spec Files

| Service | Spec | Notes |
| --- | --- | --- |
| session-broker | [docs/api/session-broker.openapi.yaml](api/session-broker.openapi.yaml) | Session lifecycle, oauth callback/logout, health |
| token-microservice | [docs/api/token-microservice.openapi.yaml](api/token-microservice.openapi.yaml) | JWT issue/validate/revoke/jwks/health |
| git-proxy-server | [docs/api/git-proxy-server.openapi.yaml](api/git-proxy-server.openapi.yaml) | Credential proxy and git operation API |

## Current Gaps

- `apps/backend` still needs an actual HTTP entrypoint before an OpenAPI file can be checked in for that service.
- Runtime request validation is now implemented for the session broker and token microservice, but response-side enforcement and deeper spec-driven middleware are still pending.
- Spec diff enforcement is pending until the CI validator is wired into all relevant workflows.

## Enforcement

- `scripts/ci/validate-api-specification.sh` verifies the spec files exist and advertise OpenAPI 3.1.
- `.github/workflows/ci-validate.yml` runs the API spec validation gate on every push and pull request.

## Change Rule

When a route changes, update the matching OpenAPI file in the same change. If a service gains a new route and its spec is not updated, the change is incomplete.