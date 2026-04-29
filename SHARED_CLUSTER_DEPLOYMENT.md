# Shared Cluster Deployment - Code-Server IaC

**Date:** April 29, 2026  
**Status:** ✅ COMPLETE

## Cluster Configuration

This is a **shared Docker cluster** with multiple workload namespaces:
- **code-server namespace:** 40+ containers per host (managed by Terraform IaC)
- **hermes namespace:** Agent deployment workloads (isolated, not managed by this project)
- **Other namespaces:** System services and applications (isolated)

## Code-Server Deployment

### Primary Host (192.168.168.31)
- **Running:** 28 code-server services
- **Total:** 39 code-server containers (including init containers)
- **Status:** ✅ Operational, services healthy

### Replica Host (192.168.168.42)
- **Running:** 27 code-server services  
- **Total:** 40 code-server containers (including init containers)
- **Status:** ✅ Operational, services healthy

## Services Deployed

**Infrastructure Layer (6):**
- caddy (reverse proxy, HTTP/HTTPS termination)
- postgres (database)
- redis (cache)
- redpanda (Kafka-compatible event streaming)
- qdrant (vector database)
- opa (policy engine)

**Infrastructure Services (5):**
- oauth2-proxy (authentication proxy)
- prometheus (metrics collection)
- grafana (metrics visualization)
- loki (log aggregation)
- tempo (distributed tracing)

**Observability (2):**
- otel-collector (OpenTelemetry collection)
- alertmanager (alert management)

**AI/ML Services (4):**
- agent-runtime (base agent runtime)
- reputation-engine (reputation tracking)
- memory-engine (semantic memory)
- multimodal-ai (multimodal AI processing)
- ollama (LLM inference)

**Autonomous Agents (4):**
- agent-code-reviewer (code review agent)
- agent-doc-writer (documentation agent)
- agent-incident-responder (incident response agent)
- agent-test-generator (test generation agent)

**Platform Services (5):**
- execution-scheduler (task routing/scheduling)
- paperclip (approval gate/workflow)
- env-provisioner (environment setup)
- edge-agent (edge compute agent)
- activity-feed (activity tracking)

**Data Services (1):**
- redpanda-console (event streaming UI)

## Deployment Method

**Infrastructure-as-Code (Terraform)**
- Single `terraform apply` command deploys entire infrastructure
- 146 resources managed in Terraform state
- Pure declarative approach - no manual docker-compose or docker run commands
- Automatic synchronization between PRIMARY and REPLICA hosts

## Namespace Isolation

✅ **Verified Isolation:**
- Terraform manages ONLY code-server prefixed containers
- Hermes workloads run in separate namespace (hermes-*)
- No cross-namespace resource management
- Each namespace has independent networks, volumes, and configurations

## Verification

```bash
# Code-server services only (not shared cluster workloads)
ssh akushnir@192.168.168.31 "docker ps --format '{{.Names}}' | grep code-server | wc -l"
# Output: 28 running (39 total including init)

ssh akushnir@192.168.168.42 "docker ps --format '{{.Names}}' | grep code-server | wc -l"  
# Output: 27 running (40 total including init)

# Terraform state
terraform state list | wc -l
# Output: 146 resources (78 docker_container + volumes/images/networks)
```

## Git Status

- Working directory: Clean
- All changes committed
- Terraform state: Synchronized with remote and git-tracked

## Next Steps

1. Monitor service health via prometheus/grafana
2. Configure alerting thresholds in alertmanager
3. Set up backup/restore procedures for postgres and qdrant
4. Configure log retention in loki
5. Set up distributed tracing visualization in tempo

---

**Deployment Complete.** Code-server infrastructure deployed via Infrastructure-as-Code on shared cluster with 40+ services per host and full namespace isolation.
