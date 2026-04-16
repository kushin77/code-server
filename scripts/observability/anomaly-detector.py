#!/usr/bin/env python3
"""
Phase 23-C: Anomaly Detector
─────────────────────────────────────────────────────────────────────────────
Queries Prometheus at regular intervals, computes z-score anomaly scores for
key metrics, and exposes them via a Prometheus-compatible text endpoint (or
pushes them to Pushgateway when available).

Algorithm: sliding-window z-score
  z = (current_value - window_mean) / window_stddev

A z-score > ANOMALY_ZSCORE_THRESHOLD is flagged as an anomaly.

Environment Variables:
  PROMETHEUS_URL           — Prometheus base URL (default: http://prometheus:9090)
  PUSHGATEWAY_URL          — Optional pushgateway for metrics (default: none)
  ANOMALY_CHECK_INTERVAL   — Seconds between checks (default: 300)
  ANOMALY_WINDOW_MINUTES   — Lookback window for baseline (default: 30)
  ANOMALY_ZSCORE_THRESHOLD — z-score above which anomaly fires (default: 3.0)
  LOG_LEVEL                — Logging level (default: INFO)
─────────────────────────────────────────────────────────────────────────────
"""

import os
import sys
import time
import math
import logging
import requests
from datetime import datetime, timedelta
from http.server import HTTPServer, BaseHTTPRequestHandler
from threading import Thread

# ── Configuration ──────────────────────────────────────────────────────────
PROMETHEUS_URL       = os.getenv("PROMETHEUS_URL", "http://prometheus:9090")
PUSHGATEWAY_URL      = os.getenv("PUSHGATEWAY_URL", "")
CHECK_INTERVAL_SEC   = int(os.getenv("ANOMALY_CHECK_INTERVAL", "300"))
WINDOW_MINUTES       = int(os.getenv("ANOMALY_WINDOW_MINUTES", "30"))
ZSCORE_THRESHOLD     = float(os.getenv("ANOMALY_ZSCORE_THRESHOLD", "3.0"))
LOG_LEVEL            = os.getenv("LOG_LEVEL", "INFO")
METRICS_PORT         = int(os.getenv("METRICS_PORT", "9095"))

logging.basicConfig(
    level=getattr(logging, LOG_LEVEL.upper(), logging.INFO),
    format="%(asctime)s %(levelname)s [anomaly-detector] %(message)s",
)
log = logging.getLogger(__name__)

# ── Metric definitions ──────────────────────────────────────────────────────
# Each entry: (metric_name, promql_expression, description)
MONITORED_METRICS = [
    (
        "http_request_rate",
        "sum(rate(http_requests_total[5m]))",
        "Aggregate HTTP request rate (req/s)",
    ),
    (
        "http_error_rate",
        "sum(rate(http_requests_total{status=~'5..'}[5m])) or vector(0)",
        "HTTP 5xx error rate (req/s)",
    ),
    (
        "latency_p99",
        "histogram_quantile(0.99, sum(rate(http_request_duration_seconds_bucket[5m])) by (le))",
        "p99 HTTP response latency (seconds)",
    ),
    (
        "cpu_usage",
        "sum(rate(process_cpu_seconds_total[5m]))",
        "Total CPU usage across all monitored processes",
    ),
    (
        "ollama_inference_rate",
        "sum(rate(ollama_inference_requests_total[5m])) or vector(0)",
        "Ollama inference request rate (req/s)",
    ),
]

# ── In-memory state ─────────────────────────────────────────────────────────
# { metric_name: {"last_score": float, "last_value": float, "last_check": datetime} }
_state: dict = {m[0]: {"last_score": 0.0, "last_value": 0.0, "last_check": None}
                for m in MONITORED_METRICS}

_prometheus_text = "# anomaly detector starting\n"


# ── Prometheus query helpers ─────────────────────────────────────────────────

def query_instant(promql: str) -> float | None:
    """Query a single scalar value from Prometheus."""
    try:
        resp = requests.get(
            f"{PROMETHEUS_URL}/api/v1/query",
            params={"query": promql},
            timeout=10,
        )
        resp.raise_for_status()
        result = resp.json().get("data", {}).get("result", [])
        if result:
            return float(result[0]["value"][1])
    except Exception as exc:  # noqa: BLE001
        log.debug("Prometheus query failed for '%s': %s", promql, exc)
    return None


def query_range(promql: str, minutes: int) -> list[float]:
    """Query a range of values and return them as a list."""
    end   = datetime.utcnow()
    start = end - timedelta(minutes=minutes)
    try:
        resp = requests.get(
            f"{PROMETHEUS_URL}/api/v1/query_range",
            params={
                "query": promql,
                "start": start.timestamp(),
                "end":   end.timestamp(),
                "step":  "60s",
            },
            timeout=15,
        )
        resp.raise_for_status()
        result = resp.json().get("data", {}).get("result", [])
        if result:
            return [float(v[1]) for v in result[0]["values"]]
    except Exception as exc:  # noqa: BLE001
        log.debug("Prometheus range query failed for '%s': %s", promql, exc)
    return []


# ── Anomaly computation ──────────────────────────────────────────────────────

def _mean(values: list[float]) -> float:
    return sum(values) / len(values) if values else 0.0


def _stddev(values: list[float], mean: float) -> float:
    if len(values) < 2:
        return 0.0
    variance = sum((v - mean) ** 2 for v in values) / (len(values) - 1)
    return math.sqrt(variance)


def compute_zscore(metric_name: str, promql: str) -> tuple[float, float, float]:
    """
    Returns (current_value, z_score, baseline_mean) for a metric.
    z_score = (current - mean(window)) / stddev(window)
    """
    current = query_instant(promql)
    if current is None:
        return 0.0, 0.0, 0.0

    history = query_range(promql, WINDOW_MINUTES)
    if len(history) < 3:
        return current, 0.0, current

    mean    = _mean(history)
    stddev  = _stddev(history, mean)
    zscore  = (current - mean) / stddev if stddev > 1e-10 else 0.0

    return current, zscore, mean


# ── Metrics exposition ───────────────────────────────────────────────────────

def build_prometheus_output() -> str:
    lines = []
    timestamp_ms = int(time.time() * 1000)

    lines.append("# HELP anomaly_zscore Z-score deviation from baseline (|z|>3 = anomaly)")
    lines.append("# TYPE anomaly_zscore gauge")

    lines.append("# HELP anomaly_current_value Current metric value at last check")
    lines.append("# TYPE anomaly_current_value gauge")

    lines.append("# HELP anomaly_baseline_mean Baseline mean over the lookback window")
    lines.append("# TYPE anomaly_baseline_mean gauge")

    lines.append("# HELP anomaly_flagged 1 if metric is currently anomalous, 0 otherwise")
    lines.append("# TYPE anomaly_flagged gauge")

    for metric_name, _, _ in MONITORED_METRICS:
        s = _state[metric_name]
        label = f'{{metric="{metric_name}"}}'
        flagged = 1 if abs(s["last_score"]) >= ZSCORE_THRESHOLD else 0
        lines.append(f'anomaly_zscore{label} {s["last_score"]:.4f}')
        lines.append(f'anomaly_current_value{label} {s["last_value"]:.6f}')
        lines.append(f'anomaly_flagged{label} {flagged}')

    lines.append("")
    return "\n".join(lines)


class MetricsHandler(BaseHTTPRequestHandler):
    def do_GET(self):  # noqa: N802
        if self.path in ("/metrics", "/"):
            body = _prometheus_text.encode()
            self.send_response(200)
            self.send_header("Content-Type", "text/plain; version=0.0.4")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
        else:
            self.send_response(404)
            self.end_headers()

    def log_message(self, fmt, *args):  # suppress default access logs
        pass


# ── Main loop ────────────────────────────────────────────────────────────────

def run_checks():
    global _prometheus_text
    log.info(
        "Starting anomaly detector (window=%dm, threshold=%.1fσ, interval=%ds)",
        WINDOW_MINUTES, ZSCORE_THRESHOLD, CHECK_INTERVAL_SEC,
    )
    while True:
        anomalies_found = 0
        for metric_name, promql, description in MONITORED_METRICS:
            current, zscore, baseline = compute_zscore(metric_name, promql)
            _state[metric_name].update(
                last_score=zscore, last_value=current, last_check=datetime.utcnow()
            )
            if abs(zscore) >= ZSCORE_THRESHOLD:
                anomalies_found += 1
                direction = "above" if zscore > 0 else "below"
                log.warning(
                    "ANOMALY %s z=%.2f (current=%.4f, baseline=%.4f) %s threshold %.1f",
                    metric_name, zscore, current, baseline, direction, ZSCORE_THRESHOLD,
                )
            else:
                log.debug(
                    "OK %s z=%.2f (current=%.4f, baseline=%.4f)",
                    metric_name, zscore, current, baseline,
                )

        _prometheus_text = build_prometheus_output()

        if anomalies_found:
            log.info("Check complete: %d anomaly(ies) detected", anomalies_found)
        else:
            log.debug("Check complete: all metrics within normal range")

        time.sleep(CHECK_INTERVAL_SEC)


def main():
    # Start HTTP server for Prometheus scraping in background thread
    server = HTTPServer(("0.0.0.0", METRICS_PORT), MetricsHandler)
    server_thread = Thread(target=server.serve_forever, daemon=True)
    server_thread.start()
    log.info("Metrics endpoint: http://0.0.0.0:%d/metrics", METRICS_PORT)

    # Wait for Prometheus to be reachable before starting checks
    for attempt in range(12):
        try:
            requests.get(f"{PROMETHEUS_URL}/-/ready", timeout=5).raise_for_status()
            break
        except Exception:  # noqa: BLE001
            log.info("Waiting for Prometheus (%d/12)…", attempt + 1)
            time.sleep(10)
    else:
        log.error("Prometheus not reachable after 2 minutes, proceeding anyway")

    run_checks()


if __name__ == "__main__":
    main()
