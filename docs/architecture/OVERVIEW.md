# Architecture Overview
## Enterprise Code-Server Infrastructure (Q3 2026)

**Status**: PRODUCTION READY ✅  
**Version**: 1.12.0 (Phase 4 Continuation)  
**Governance**: [GOV-002](../../scripts/ops/infrastructure-health-check.sh)

---

## Executive Summary

The Code-Server Enterprise infrastructure is a high-availability, multi-node deployment designed for maximum security, observability, and scalability. It leverages a dual-host topology (Primary/Replica) with a NAS-connected state management layer, orchestrated via Docker Compose and Terraform.

---

## System Topology

The deployment follows a **Dual-Node HA Pattern** (verified May 1, 2026):

| Node | IP Address | Role | Components |
|---|---|---|---|
| **Primary** | `192.168.168.31` | Master | Active API, Frontend, 38 Services |
| **Replica** | `192.168.168.42` | Hot-Standby | Mirrored stack, Failover Target |
| **NAS** | `192.168.168.56` | State | PostgreSQL Data, MinIO, Backups |

### Networking & Ingress
- **Edge Proxy**: [Caddy](../../Caddyfile) provides SSL termination (TLS 1.3) and automatic Let's Encrypt certificates.
- **Internal DNS**: [Service Discovery](../architecture/DNS-SERVICE-DISCOVERY.md) enables non-static service communication.
- **Load Balancing**: Managed via Caddy's active health checks and manual failover orchestration.

---

## Deployment Architecture

### 1. Infrastructure as Code (IaC)
Infrastructure is managed with **Terraform 1.7+**, featuring:
- [Unified Tagging](../architecture/Q3-PHASE-5-INFRASTRUCTURE-COMPLETE.md): All 50+ containers carry `Environment`, `ManagedBy`, and `CostCenter` tags.
- [Provider Pinning](../../terraform/providers.tf): Strict versioning for AWS, Local, and Docker providers.
- [Idempotent Initialization](../../scripts/ops/idempotency-enforcer.sh): Init containers ensure filesystem ownership before service start.

### 2. Microservices Stack
The platform consists of 26 core services including:
- **Compute**: API, Auth, Agent-Runtime, Execution-Scheduler.
- **Storage**: PostgreSQL (HA), Redis, MinIO (S3-compatible).
- **Eventing**: Redpanda (Kafka-compatible).
- **Observability**: Prometheus, Grafana, Loki, Tempo.

---

## Security Architecture

### Zero-Trust Principles
- **Non-Root Execution**: 100% of services run as non-root users (UID 65534 or 1000).
- **Resource Limits**: Strict CPU/Memory capping per service in [docker-compose.yml](../../docker-compose.yml).
- **Secrets Management**: Vault-integrated injection (verified in Phase 5).
- **Network Policies**: OPA-enforced traffic rules between namespaces.

---

## Observability & Logging (SLOG)

Standardized Logging (SLOG) provides unified visibility across all components:
- [Logging Module](../../scripts/_common/init.sh): Centralized bash/python logging.
- **Metrics**: Prometheus scraping with 45-day retention.
- **Traces**: Distributed tracing via OpenTelemetry (Tempo).

---

## Disaster Recovery & Failover

- **RTO**: < 5 minutes (Manual failover to Replica).
- **RPO**: < 60 seconds (NAS-level replication).
- **Validation**: `bash scripts/ops/full-deployment-test.sh` validates all recovery paths.

---

## Future Roadmap: Kubernetes Migration

As detailed in the [Kubernetes Migration Plan](../architecture/KUBERNETES-MIGRATION-PHASE-4.md), the infrastructure is transitioning to a **Helm-managed EKS/K8s** environment to support 100+ node scaling.

---

*This document is the current source of truth for repository architecture as of May 2, 2026.*
