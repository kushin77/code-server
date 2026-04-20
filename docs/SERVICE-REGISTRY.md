# Service Registry SSOT

`docker-compose.yml` is the runtime source of truth for compose-managed service topology. This registry mirrors the compose stack and also lists adjacent non-compose runtime services so engineers can see the full service map without grepping multiple files.

## Purpose

- Keep service names, source, exposure, and health contracts in one place.
- Make it easy to diff the deployment surface without reading the full compose file.
- Provide a validation target for CI and local preflight checks.

## Canonical Files

- [docker-compose.yml](../docker-compose.yml)
- [service-registry.yaml](service-registry.yaml)
- [validate-service-registry.sh](../scripts/ci/validate-service-registry.sh)

## Registry Rules

- Every top-level compose service with a `container_name` and `source: compose` must appear in the registry.
- Every registry entry must describe its health contract.
- One-shot jobs are listed explicitly instead of being implied.
- Optional portal services remain in the registry even when hidden behind a compose profile.
- External services such as Kubernetes workloads are listed with `source: kubernetes` and are exempt from compose parity checks.

## Service Map

| Service | Source | Internal DNS | External DNS | Ports | Health contract | Dependencies | Profile | Restart policy | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `code-server` | compose | `code-server` | `ide.kushnir.cloud` | `8080` | HTTP `http://localhost:8080/healthz` | `ollama`, `oauth2-proxy`, `redis` | `base` | `unless-stopped` | Browser IDE runtime |
| `ollama` | compose | `ollama` | n/a | `11434` | Command `ollama list` | n/a | `base` | `unless-stopped` | Local LLM engine |
| `ollama-init` | compose | `ollama-init` | n/a | n/a | One-shot bootstrap loop | `ollama` | `base` | `on-failure` | Model pull bootstrap job |
| `oauth2-proxy` | compose | `oauth2-proxy` | `ide.kushnir.cloud` | `4180` | Command `/bin/oauth2-proxy --version` | `code-server`, `redis` | `base` | `unless-stopped` | Google OIDC gate for IDE access |
| `oauth2-proxy-portal` | compose | `oauth2-proxy-portal` | `kushnir.cloud` | `4181` | Command `/bin/oauth2-proxy --version` | `appsmith`, `redis` | `portal` | `unless-stopped` | Google OIDC gate for the portal |
| `session-broker` | compose | `session-broker` | n/a | `5000` | HTTP `http://localhost:5000/health` | `postgres`, `code-server` | `base` | `unless-stopped` | Per-session container routing |
| `caddy` | compose | `caddy` | `kushnir.cloud`, `ide.kushnir.cloud` | `80`, `443`, `2019` | Command `caddy version` | `oauth2-proxy`, `session-broker` | `base` | `unless-stopped` | Reverse proxy and TLS termination |
| `postgres` | compose | `postgres` | n/a | `5433` | Command `pg_isready -U codeserver -d codeserver` | n/a | `base` | `unless-stopped` | Primary relational database |
| `pgbouncer` | compose | `pgbouncer` | n/a | `6432` | Command `psql -U codeserver -h localhost -p 6432 -d codeserver -c 'SELECT 1'` | `postgres` | `base` | `unless-stopped` | PostgreSQL connection pooler |
| `redis` | compose | `redis` | n/a | `6379` | Command `redis-cli ping` | n/a | `base` | `unless-stopped` | Cache and session store |
| `code-server-profile-backup` | compose | `code-server-profile-backup` | n/a | n/a | One-shot archive loop | `code-server` | `base` | `unless-stopped` | Periodic profile backup job |
| `prometheus` | compose | `prometheus` | `192.168.168.31:9090` | `9090` | HTTP `http://localhost:9090/-/ready` | n/a | `base` | `unless-stopped` | Metrics collection |
| `grafana` | compose | `grafana` | `192.168.168.31:3000` | `3000` | HTTP `http://localhost:3000/api/health` | `prometheus` | `base` | `unless-stopped` | Dashboard UI |
| `alertmanager` | compose | `alertmanager` | `192.168.168.31:9093` | `9093` | HTTP `http://localhost:9093/-/ready` | n/a | `base` | `unless-stopped` | Alert routing and silencing |
| `jaeger` | compose | `jaeger` | `192.168.168.31:16686` | `16686` | HTTP `http://localhost:16686/` | n/a | `base` | `unless-stopped` | Distributed tracing backend |
| `appsmith` | compose | `appsmith` | `kushnir.cloud` | `80` | HTTP `http://localhost/api/v1/health` | n/a | `portal` | `unless-stopped` | Admin portal |
| `token-microservice` | kubernetes | `token-microservice.default.svc.cluster.local` | n/a | `8888`, `9090` | HTTP `http://token-microservice.default.svc.cluster.local:8888/health` | `vault`, `oidc issuer` | `k8s` | `Deployment` | JWT issuer and validation service |

## Validation Expectations

- CI must fail if the compose service list and registry diverge.
- CI must fail if any registry entry is missing a health contract.
- Local preflight should report the registry before deployment.
- Registry health validation should probe HTTP endpoints and execute command-based health checks where the runtime is available.