/**
 * @file terraform/environments/private/deployment.tf
 * @description MIGRATED — null_resource bash scripts removed.
 *
 * PREVIOUS APPROACH (WRONG):
 *   null_resource + local-exec bash scripts — Terraform could not track or plan container state.
 *   `terraform plan` showed nothing meaningful about the 80 containers across both hosts.
 *
 * CURRENT APPROACH (CORRECT):
 *   kreuzwerker/docker provider with SSH host aliases.
 *   Every container is a docker_container Terraform resource.
 *
 *   terraform plan   → shows all 80 container diffs (primary + replica)
 *   terraform apply  → creates/updates/destroys containers declaratively, idempotently
 *
 * Resources are organized in:
 *   modules/stack/networks.tf            — 3 Docker networks per host
 *   modules/stack/volumes.tf             — 12 named volumes per host
 *   modules/stack/images.tf              — Image pulls for all services
 *   modules/stack/containers-init.tf     — 11 init containers per host (run-once)
 *   modules/stack/containers-data.tf     — postgres, redis, redpanda, qdrant
 *   modules/stack/containers-observability.tf — prometheus, grafana, loki, alertmanager, otel, tempo
 *   modules/stack/containers-infrastructure.tf — caddy, opa, oauth2-proxy, ollama
 *   modules/stack/containers-ai.tf       — memory-engine, multimodal-ai, reputation-engine, agent-runtime
 *   modules/stack/containers-agents.tf   — 4 AI agent containers
 *   modules/stack/containers-platform.tf — paperclip, execution-scheduler, env-provisioner, activity-feed, edge-agent
 *
 * Called from main.tf as:
 *   module "primary" { ... providers = { docker = docker.primary } }
 *   module "replica"  { ... providers = { docker = docker.replica  } }
 */
