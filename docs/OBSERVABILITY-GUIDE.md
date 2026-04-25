# Observability Guide

This repository already ships the core observability stack in `docker-compose.yml`:
Prometheus, Grafana, Alertmanager, Loki, OpenTelemetry Collector, and Tempo.

This guide covers the overlay and configuration that complete the logging and GPU
monitoring path for Issue #1532.

## Stack Layout

- `docker-compose.yml`: base observability services
- `docker-compose.observability.yml`: overlay for Promtail and DCGM exporter
- `config/promtail.yaml`: Docker log shipping to Loki
- `config/prometheus.yml`: scrape jobs for Alertmanager, Promtail, and GPU metrics
- `monitoring/alerts/alert-rules.yml`: unified alert rules
- `monitoring/alertmanager.yml`: severity-based routing

## Run It

```bash
docker compose -f docker-compose.yml -f docker-compose.observability.yml --profile observability up -d
```

For GPU workloads, include the AI profile too:

```bash
docker compose -f docker-compose.yml -f docker-compose.observability.yml --profile observability --profile ai up -d
```

## Data Flow

1. Docker container logs are discovered by Promtail from the local Docker daemon.
2. Promtail forwards JSON-parsed logs to Loki.
3. Prometheus scrapes Alertmanager, Promtail, OTel Collector, Tempo, and GPU metrics.
4. Alertmanager routes alerts by severity.
5. Grafana correlates logs, metrics, and traces through the shared datasources.

## Validation Queries

### Logs

```logql
{compose_service="caddy"}
{severity="error"}
```

### Metrics

```promql
up{job="promtail"}
up{job="dcgm-exporter"}
avg_over_time(DCGM_FI_DEV_GPU_UTIL[5m])
```

### Alerts

```promql
up{job="loki"} == 0
up{job="alertmanager"} == 0
increase(DCGM_FI_DEV_ECC_DBE_VOL_TOTAL[15m]) > 0
```

## Notes

- Promtail needs access to `/var/lib/docker/containers` and `/var/run/docker.sock`.
- DCGM exporter requires an NVIDIA-enabled host.
- The current Alertmanager transport endpoints are scaffolded for severity routing and
  should be replaced with deployment-specific relay endpoints or secret-backed providers.
