#!/usr/bin/env python3
"""
Phase 23-E: Root Cause Analysis (RCA) Engine
─────────────────────────────────────────────────────────────────────────────
Queries Prometheus for correlated signals when an alert fires and produces
a ranked hypothesis report identifying the most likely root cause.

Designed to run as a one-shot CLI tool (triggered by AlertManager webhook)
or continuously as a daemon polling for active alerts.

Usage:
  # One-shot analysis for a specific alert
  python rca-engine.py --alert HighLatency

  # Daemon mode: analyze all FIRING alerts every 60s
  python rca-engine.py --daemon

Environment Variables:
  PROMETHEUS_URL   — Prometheus base URL (default: http://prometheus:9090)
  ALERTMANAGER_URL — AlertManager base URL (default: http://alertmanager:9093)
  RCA_OUTPUT_DIR   — Directory for RCA report files (default: /tmp/rca)
  LOG_LEVEL        — Logging level (default: INFO)
─────────────────────────────────────────────────────────────────────────────
"""

import os
import sys
import json
import time
import logging
import argparse
import requests
from datetime import datetime, timedelta
from pathlib import Path
from typing import Optional

# ── Configuration ────────────────────────────────────────────────────────────
PROMETHEUS_URL   = os.getenv("PROMETHEUS_URL",   "http://prometheus:9090")
ALERTMANAGER_URL = os.getenv("ALERTMANAGER_URL", "http://alertmanager:9093")
RCA_OUTPUT_DIR   = Path(os.getenv("RCA_OUTPUT_DIR", "/tmp/rca"))
LOG_LEVEL        = os.getenv("LOG_LEVEL", "INFO")

logging.basicConfig(
    level=getattr(logging, LOG_LEVEL.upper(), logging.INFO),
    format="%(asctime)s %(levelname)s [rca-engine] %(message)s",
)
log = logging.getLogger(__name__)


# ── Prometheus helpers ───────────────────────────────────────────────────────

def query(promql: str, lookback: str = "5m") -> Optional[float]:
    try:
        resp = requests.get(
            f"{PROMETHEUS_URL}/api/v1/query",
            params={"query": promql},
            timeout=10,
        )
        resp.raise_for_status()
        result = resp.json()["data"]["result"]
        return float(result[0]["value"][1]) if result else None
    except Exception as exc:  # noqa: BLE001
        log.debug("Query failed '%s': %s", promql, exc)
        return None


def query_active_alerts() -> list[dict]:
    try:
        resp = requests.get(f"{ALERTMANAGER_URL}/api/v2/alerts", timeout=10)
        resp.raise_for_status()
        return [a for a in resp.json() if a["status"]["state"] == "active"]
    except Exception as exc:  # noqa: BLE001
        log.debug("AlertManager query failed: %s", exc)
        return []


# ── Evidence collection ──────────────────────────────────────────────────────

def collect_evidence() -> dict:
    """Snapshot all diagnostic signals from Prometheus."""
    return {
        "timestamp": datetime.utcnow().isoformat(),
        "http_request_rate":     query("sum(rate(http_requests_total[5m]))"),
        "http_error_rate":       query("sum(rate(http_requests_total{status=~'5..'}[5m])) or vector(0)"),
        "latency_p99":           query("histogram_quantile(0.99, sum(rate(http_request_duration_seconds_bucket[5m])) by (le))"),
        "latency_p50":           query("histogram_quantile(0.50, sum(rate(http_request_duration_seconds_bucket[5m])) by (le))"),
        "cpu_usage":             query("sum(rate(process_cpu_seconds_total[5m]))"),
        "memory_usage_ratio":    query("process_resident_memory_bytes / on() node_memory_MemTotal_bytes"),
        "disk_io_util":          query("rate(node_disk_io_time_seconds_total[5m])"),
        "active_connections":    query("sum(http_server_active_connections) or vector(0)"),
        "ollama_inference_rate": query("sum(rate(ollama_inference_requests_total[5m])) or vector(0)"),
        "db_connections":        query("pg_stat_activity_count or vector(0)"),
        "redis_hit_ratio":       query("rate(redis_keyspace_hits_total[5m]) / (rate(redis_keyspace_hits_total[5m]) + rate(redis_keyspace_misses_total[5m]) + 0.001) or vector(1)"),
        "anomaly_zscore_latency": query("anomaly_zscore{metric='latency_p99'} or vector(0)"),
        "anomaly_zscore_errors":  query("anomaly_zscore{metric='http_error_rate'} or vector(0)"),
        "slo_burn_rate_1h":      query("slo:availability:burn_rate_1h or vector(0)"),
    }


# ── Hypothesis engine ────────────────────────────────────────────────────────

class Hypothesis:
    def __init__(self, name: str, likelihood: float, evidence: list[str], remediation: list[str]):
        self.name        = name
        self.likelihood  = likelihood  # 0.0–1.0
        self.evidence    = evidence
        self.remediation = remediation

    def to_dict(self) -> dict:
        return {
            "hypothesis":   self.name,
            "likelihood":   f"{self.likelihood:.0%}",
            "evidence":     self.evidence,
            "remediation":  self.remediation,
        }


def analyze(alert_name: str, ev: dict) -> list[Hypothesis]:
    """
    Score hypotheses for a given alert based on collected evidence.
    Returns hypotheses sorted by likelihood (highest first).
    """
    hypotheses: list[Hypothesis] = []

    latency     = ev.get("latency_p99") or 0.0
    error_rate  = ev.get("http_error_rate") or 0.0
    cpu         = ev.get("cpu_usage") or 0.0
    memory      = ev.get("memory_usage_ratio") or 0.0
    req_rate    = ev.get("http_request_rate") or 0.0
    db_conns    = ev.get("db_connections") or 0.0
    burn_rate   = ev.get("slo_burn_rate_1h") or 0.0
    inf_rate    = ev.get("ollama_inference_rate") or 0.0
    error_z     = ev.get("anomaly_zscore_errors") or 0.0
    latency_z   = ev.get("anomaly_zscore_latency") or 0.0

    # ── H1: CPU-bound workload
    cpu_score = 0.0
    cpu_evidence = []
    if cpu > 0.8:
        cpu_score += 0.5
        cpu_evidence.append(f"CPU utilization critical: {cpu:.1%}")
    if latency > 0.2 and cpu > 0.6:
        cpu_score += 0.3
        cpu_evidence.append(f"High latency ({latency:.3f}s) co-occurring with high CPU")
    if inf_rate > 5:
        cpu_score += 0.2
        cpu_evidence.append(f"Ollama inference rate elevated ({inf_rate:.1f}/s) — likely CPU consumer")
    if cpu_score > 0:
        hypotheses.append(Hypothesis(
            "CPU-bound workload causing latency",
            min(cpu_score, 1.0),
            cpu_evidence,
            [
                "Check cpu-intensive processes: docker stats",
                "Profile the code-server process: docker exec code-server top",
                "Reduce Ollama model concurrency: OLLAMA_NUM_PARALLEL=1",
                "Consider horizontal scaling if sustained",
            ],
        ))

    # ── H2: Memory pressure / GC pauses
    mem_score = 0.0
    mem_evidence = []
    if memory and memory > 0.85:
        mem_score += 0.5
        mem_evidence.append(f"Memory usage critical: {memory:.1%}")
    if latency > 0.3 and (memory or 0) > 0.7:
        mem_score += 0.3
        mem_evidence.append("Latency spike pattern consistent with GC pause")
    if mem_score > 0:
        hypotheses.append(Hypothesis(
            "Memory pressure / GC pause",
            min(mem_score, 1.0),
            mem_evidence,
            [
                "Inspect container memory: docker stats",
                "Check for memory leaks: docker exec code-server cat /proc/meminfo",
                "Increase container memory limit in docker-compose.yml",
                "Restart code-server container if OOM imminent",
            ],
        ))

    # ── H3: Traffic surge / overload
    traffic_score = 0.0
    traffic_evidence = []
    if req_rate > 100:
        traffic_score += 0.4
        traffic_evidence.append(f"Request rate elevated: {req_rate:.0f} req/s")
    if burn_rate > 6:
        traffic_score += 0.3
        traffic_evidence.append(f"SLO burn rate: {burn_rate:.1f}× (budget exhausting rapidly)")
    if latency > 0.1 and req_rate > 50:
        traffic_score += 0.3
        traffic_evidence.append("Traffic-latency correlation active")
    if traffic_score > 0:
        hypotheses.append(Hypothesis(
            "Traffic surge / service overload",
            min(traffic_score, 1.0),
            traffic_evidence,
            [
                "Enable rate limiting in Caddyfile: rate_limit {zone static 10r/s}",
                "Check upstream routing for DDoS / bot traffic",
                "Scale code-server replicas if applicable",
                "Enable Caddy's request queuing or circuit breaker",
            ],
        ))

    # ── H4: Database connection exhaustion
    db_score = 0.0
    db_evidence = []
    if db_conns > 50:
        db_score += 0.4
        db_evidence.append(f"High DB connection count: {db_conns:.0f}")
    if error_rate > 0 and db_conns > 40:
        db_score += 0.4
        db_evidence.append("Error rate + high DB connections — likely pool exhaustion")
    if db_score > 0:
        hypotheses.append(Hypothesis(
            "Database connection pool exhaustion",
            min(db_score, 1.0),
            db_evidence,
            [
                "Check PostgreSQL max_connections: docker exec postgres psql -c 'SHOW max_connections'",
                "Inspect active queries: SELECT * FROM pg_stat_activity WHERE state != 'idle'",
                "Kill long-running queries if present",
                "Tune connection pool size in application config",
            ],
        ))

    # ── H5: Deployment / rollout regression
    rollout_score = 0.0
    rollout_evidence = []
    if error_z > 4.0:
        rollout_score += 0.5
        rollout_evidence.append(f"Error rate anomaly z-score: {error_z:.1f}σ (sudden onset)")
    if latency_z > 3.0 and error_z > 3.0:
        rollout_score += 0.3
        rollout_evidence.append("Both latency and error anomaly scores elevated simultaneously — sudden regression pattern")
    if rollout_score > 0:
        hypotheses.append(Hypothesis(
            "Recent deployment / config change regression",
            min(rollout_score, 1.0),
            rollout_evidence,
            [
                "Check recent commits: git log --oneline -10",
                "Check container restart times: docker ps for recent restarts",
                "Roll back last deployment: cd ~/code-server-enterprise && git revert HEAD",
                "Compare config with last known-good version",
            ],
        ))

    # Sort by likelihood, highest first
    hypotheses.sort(key=lambda h: h.likelihood, reverse=True)
    return hypotheses


# ── Report generation ────────────────────────────────────────────────────────

def generate_report(alert_name: str, hypotheses: list[Hypothesis], evidence: dict) -> dict:
    return {
        "rca_report": {
            "alert":           alert_name,
            "generated_at":    datetime.utcnow().isoformat(),
            "evidence":        evidence,
            "top_hypothesis":  hypotheses[0].to_dict() if hypotheses else None,
            "all_hypotheses":  [h.to_dict() for h in hypotheses],
            "confidence":      hypotheses[0].likelihood if hypotheses else 0.0,
            "mttr_target_sec": 180,
        }
    }


def save_report(report: dict, alert_name: str):
    RCA_OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    ts = datetime.utcnow().strftime("%Y%m%dT%H%M%S")
    path = RCA_OUTPUT_DIR / f"rca-{alert_name}-{ts}.json"
    path.write_text(json.dumps(report, indent=2))
    log.info("RCA report saved: %s", path)
    return path


def print_report(report: dict):
    rca = report["rca_report"]
    print(f"\n{'═' * 60}")
    print(f"  RCA REPORT: {rca['alert']}")
    print(f"  Generated:  {rca['generated_at']}")
    print(f"{'═' * 60}")

    top = rca.get("top_hypothesis")
    if top:
        print(f"\n🔍 TOP HYPOTHESIS ({top['likelihood']} confidence):")
        print(f"   {top['hypothesis']}")
        print("\n📊 Supporting evidence:")
        for e in top["evidence"]:
            print(f"   • {e}")
        print("\n🔧 Recommended actions:")
        for i, r in enumerate(top["remediation"], 1):
            print(f"   {i}. {r}")
    else:
        print("\n  No hypothesis generated (insufficient signal data)")

    if len(rca["all_hypotheses"]) > 1:
        print(f"\n🧠 Other hypotheses considered ({len(rca['all_hypotheses']) - 1}):")
        for h in rca["all_hypotheses"][1:]:
            print(f"   • {h['likelihood']:>5} — {h['hypothesis']}")

    print(f"\n{'═' * 60}\n")


# ── Entry points ─────────────────────────────────────────────────────────────

def analyze_alert(alert_name: str, save: bool = True) -> dict:
    log.info("Starting RCA for alert: %s", alert_name)
    evidence    = collect_evidence()
    hypotheses  = analyze(alert_name, evidence)
    report      = generate_report(alert_name, hypotheses, evidence)

    if save:
        save_report(report, alert_name)

    return report


def daemon_loop(interval_sec: int = 60):
    log.info("RCA daemon started (interval=%ds)", interval_sec)
    seen_alerts: set[str] = set()

    while True:
        active = query_active_alerts()
        for alert in active:
            alert_name = alert["labels"].get("alertname", "unknown")
            fingerprint = alert.get("fingerprint", alert_name)
            if fingerprint not in seen_alerts:
                seen_alerts.add(fingerprint)
                report = analyze_alert(alert_name)
                print_report(report)
        # Prune resolved alerts from seen set
        active_fps = {a.get("fingerprint") for a in active}
        seen_alerts &= active_fps
        time.sleep(interval_sec)


def main():
    parser = argparse.ArgumentParser(description="Phase 23 RCA Engine")
    parser.add_argument("--alert", help="Alert name to analyze (one-shot)")
    parser.add_argument("--daemon", action="store_true", help="Run as daemon, analyzing active alerts")
    parser.add_argument("--interval", type=int, default=60, help="Daemon check interval (seconds)")
    parser.add_argument("--no-save", action="store_true", help="Do not save report to disk")
    args = parser.parse_args()

    if args.daemon:
        daemon_loop(args.interval)
    elif args.alert:
        report = analyze_alert(args.alert, save=not args.no_save)
        print_report(report)
    else:
        parser.print_help()
        sys.exit(1)


if __name__ == "__main__":
    main()
