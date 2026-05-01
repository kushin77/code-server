#!/usr/bin/env python3
"""
scripts/ops/anomaly-detector.py
---------------------------------
Statistical anomaly detection for code-server platform metrics.
Queries Prometheus, applies Z-score + IQR outlier detection, writes
alert events to a JSON log file. Exits non-zero when anomalies found.

Usage:
  python3 scripts/ops/anomaly-detector.py [--window-hours N] [--dry-run]
"""

import argparse
import json
import math
import sys
import time
import urllib.request
import urllib.parse
from datetime import datetime, timezone


def parse_args():
    p = argparse.ArgumentParser(description="Anomaly detector for code-server metrics")
    p.add_argument("--window-hours", type=int, default=6,
                   help="Analysis window in hours (default: 6)")
    p.add_argument("--prometheus-url", default="http://localhost:9090",
                   help="Prometheus base URL")
    p.add_argument("--output",
                   default="artifacts/anomaly-report.json",
                   help="Output report path (- = stdout)")
    p.add_argument("--dry-run", action="store_true",
                   help="Use synthetic data instead of live queries")
    p.add_argument("--zscore-threshold", type=float, default=3.0,
                   help="Z-score threshold for anomaly classification (default: 3.0)")
    return p.parse_args()


def fetch_metric(prom_url: str, query: str, window_hours: int) -> list[float]:
    """Fetch a Prometheus range query and return scalar values."""
    now = int(time.time())
    start = now - window_hours * 3600
    step = 60  # 1-minute resolution

    params = urllib.parse.urlencode({
        "query": query, "start": start, "end": now, "step": step,
    })
    url = f"{prom_url}/api/v1/query_range?{params}"
    try:
        with urllib.request.urlopen(url, timeout=10) as resp:
            data = json.load(resp)
        results = data["data"]["result"]
        if not results:
            return []
        return [float(v[1]) for v in results[0]["values"]]
    except Exception as exc:
        print(f"  WARN: fetch failed for query ({exc})", file=sys.stderr)
        return []


def synthetic_series(n: int = 360, anomaly_at: int = 300) -> list[float]:
    """Normal series with a synthetic spike near the end."""
    import random
    rng = random.Random(42)
    series = [50.0 + rng.gauss(0, 2) for _ in range(n)]
    series[anomaly_at] = 95.0  # inject anomaly
    return series


def mean_std(values: list[float]) -> tuple[float, float]:
    n = len(values)
    if n == 0:
        return 0.0, 0.0
    mu = sum(values) / n
    var = sum((v - mu) ** 2 for v in values) / n
    return mu, math.sqrt(var)


def iqr_bounds(values: list[float]) -> tuple[float, float]:
    """Returns (lower, upper) IQR fences."""
    if len(values) < 4:
        return float("-inf"), float("inf")
    s = sorted(values)
    n = len(s)
    q1 = s[n // 4]
    q3 = s[3 * n // 4]
    iqr = q3 - q1
    return q1 - 1.5 * iqr, q3 + 1.5 * iqr


def detect_anomalies(values: list[float], z_thresh: float) -> list[dict]:
    """Return list of anomalous data points with scores."""
    if len(values) < 10:
        return []
    mu, sigma = mean_std(values)
    low, high = iqr_bounds(values)
    anomalies = []
    for i, v in enumerate(values):
        z = abs((v - mu) / sigma) if sigma > 0 else 0.0
        iqr_outlier = v < low or v > high
        if z > z_thresh or iqr_outlier:
            anomalies.append({
                "index": i,
                "value": round(v, 4),
                "z_score": round(z, 3),
                "iqr_outlier": iqr_outlier,
                "severity": "critical" if z > z_thresh * 1.5 else "warning",
            })
    return anomalies


# Metric definitions: (name, prom_query, unit, direction)
METRICS = [
    ("cpu_usage_pct",
     '100 - (avg(rate(container_cpu_usage_seconds_total{name=~"code-server-.*"}[2m])) * 100)',
     "%", "high"),
    ("memory_usage_pct",
     'avg(container_memory_usage_bytes{name=~"code-server-.*"}) / avg(container_spec_memory_limit_bytes{name=~"code-server-.*"}) * 100',
     "%", "high"),
    ("http_error_rate",
     'sum(rate(http_requests_total{job="code-server",status=~"5.."}[2m])) / sum(rate(http_requests_total{job="code-server"}[2m])) * 100',
     "%", "high"),
    ("p95_latency_ms",
     'histogram_quantile(0.95, sum(rate(http_request_duration_seconds_bucket{job="code-server"}[2m])) by (le)) * 1000',
     "ms", "high"),
    ("active_connections",
     'pg_stat_activity_count{datname="code_server"}',
     "count", "high"),
]


def main():
    args = parse_args()
    now_iso = datetime.now(timezone.utc).isoformat()

    print(f"Anomaly Detector — window={args.window_hours}h "
          f"dry-run={args.dry_run}", file=sys.stderr)

    report = {
        "generated_at": now_iso,
        "window_hours": args.window_hours,
        "z_threshold": args.zscore_threshold,
        "metrics": [],
        "total_anomalies": 0,
        "critical_count": 0,
    }

    exit_code = 0

    for name, query, unit, direction in METRICS:
        if args.dry_run:
            values = synthetic_series(360, anomaly_at=300) if name == "cpu_usage_pct" \
                else synthetic_series(360, anomaly_at=-1)
        else:
            values = fetch_metric(args.prometheus_url, query, args.window_hours)

        if not values:
            print(f"  SKIP {name}: no data", file=sys.stderr)
            report["metrics"].append({"name": name, "unit": unit, "data_points": 0, "anomalies": []})
            continue

        anomalies = detect_anomalies(values, args.zscore_threshold)
        mu, sigma = mean_std(values)
        critical = [a for a in anomalies if a["severity"] == "critical"]

        report["metrics"].append({
            "name": name,
            "unit": unit,
            "data_points": len(values),
            "mean": round(mu, 3),
            "stddev": round(sigma, 3),
            "anomalies": anomalies,
        })
        report["total_anomalies"] += len(anomalies)
        report["critical_count"] += len(critical)

        if critical:
            print(f"  🚨 CRITICAL {name}: {len(critical)} critical anomalies "
                  f"(mean={mu:.2f}{unit})", file=sys.stderr)
            exit_code = 1
        elif anomalies:
            print(f"  ⚠️  WARNING {name}: {len(anomalies)} anomalies "
                  f"(mean={mu:.2f}{unit})", file=sys.stderr)
        else:
            print(f"  ✅ OK {name}: {len(values)} points, mean={mu:.2f}{unit}",
                  file=sys.stderr)

    output_str = json.dumps(report, indent=2)

    if args.output == "-":
        print(output_str)
    else:
        import os
        os.makedirs(os.path.dirname(args.output) or ".", exist_ok=True)
        with open(args.output, "w") as f:
            f.write(output_str)
        print(f"  Report written to {args.output}", file=sys.stderr)

    sys.exit(exit_code)


if __name__ == "__main__":
    main()
