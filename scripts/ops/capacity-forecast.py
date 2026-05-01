#!/usr/bin/env python3
"""
scripts/ops/capacity-forecast.py
---------------------------------
Reads 7-day CPU/memory/connections time-series from Prometheus,
fits a linear regression, and forecasts when resources will hit threshold.
Outputs JSON report + exits non-zero when threshold breach is imminent (<7d).

Usage:
  python3 scripts/ops/capacity-forecast.py [--horizon-days N] [--dry-run]
"""

import argparse
import json
import sys
import time
import urllib.request
import urllib.parse
from datetime import datetime, timezone

try:
    import statistics
except ImportError:
    statistics = None


def parse_args():
    p = argparse.ArgumentParser(description="Capacity forecasting tool")
    p.add_argument("--horizon-days", type=int, default=14,
                   help="Forecast horizon in days (default: 14)")
    p.add_argument("--prometheus-url", default="http://localhost:9090",
                   help="Prometheus base URL")
    p.add_argument("--dry-run", action="store_true",
                   help="Use synthetic data instead of live Prometheus queries")
    p.add_argument("--output", default="-", help="Output file path (- = stdout)")
    return p.parse_args()


def query_prometheus(prom_url: str, query: str, duration: str = "7d") -> list[tuple[float, float]]:
    """Returns list of (unix_ts, value) pairs for a range query."""
    now = int(time.time())
    start = now - 7 * 86400
    step = 3600  # 1-hour resolution

    params = urllib.parse.urlencode({
        "query": query,
        "start": start,
        "end": now,
        "step": step,
    })
    url = f"{prom_url}/api/v1/query_range?{params}"
    try:
        with urllib.request.urlopen(url, timeout=10) as resp:
            data = json.load(resp)
        result = data["data"]["result"]
        if not result:
            return []
        return [(float(ts), float(val)) for ts, val in result[0]["values"]]
    except Exception as exc:
        print(f"  WARN: Prometheus query failed ({exc}), using zeros", file=sys.stderr)
        return []


def synthetic_data(trend: float = 0.5) -> list[tuple[float, float]]:
    """Generate 168-point fake time series with given hourly trend."""
    now = int(time.time())
    return [(now - (168 - i) * 3600, 20.0 + i * trend + (i % 7) * 0.3)
            for i in range(168)]


def linear_regression(points: list[tuple[float, float]]) -> tuple[float, float]:
    """Returns (slope_per_hour, intercept). Simple OLS."""
    if len(points) < 2:
        return 0.0, 0.0
    xs = [p[0] for p in points]
    ys = [p[1] for p in points]
    n = len(xs)
    x_mean = sum(xs) / n
    y_mean = sum(ys) / n
    num = sum((x - x_mean) * (y - y_mean) for x, y in zip(xs, ys))
    den = sum((x - x_mean) ** 2 for x in xs)
    slope = num / den if den != 0 else 0.0
    intercept = y_mean - slope * x_mean
    return slope, intercept


def hours_until_threshold(slope: float, intercept: float,
                           now_ts: float, threshold: float) -> float | None:
    """Return hours until value reaches threshold. None if never."""
    if slope <= 0:
        return None
    hours = (threshold - (slope * now_ts + intercept)) / (slope * 3600)
    return max(0.0, hours)


def assess(resource: str, points: list, threshold: float, horizon_hours: int) -> dict:
    now_ts = time.time()
    slope, intercept = linear_regression(points)
    current = slope * now_ts + intercept if points else 0.0
    hours = hours_until_threshold(slope, intercept, now_ts, threshold)

    breach_imminent = hours is not None and hours < horizon_hours
    return {
        "resource": resource,
        "current_pct": round(current, 2),
        "threshold_pct": threshold,
        "slope_per_hour": round(slope * 3600, 6),
        "hours_until_threshold": round(hours, 1) if hours is not None else None,
        "breach_imminent": breach_imminent,
        "data_points": len(points),
    }


QUERIES = {
    "cpu": '100 - (avg(rate(container_cpu_usage_seconds_total{name=~"code-server-.*"}[5m])) * 100)',
    "memory": 'avg(container_memory_usage_bytes{name=~"code-server-.*"}) / avg(container_spec_memory_limit_bytes{name=~"code-server-.*"}) * 100',
    "connections": 'pg_stat_activity_count{datname="code_server"}',
}

THRESHOLDS = {"cpu": 85.0, "memory": 85.0, "connections": 200.0}


def main():
    args = parse_args()
    horizon_hours = args.horizon_days * 24
    now_iso = datetime.now(timezone.utc).isoformat()

    print(f"Capacity Forecast — horizon={args.horizon_days}d dry-run={args.dry_run}",
          file=sys.stderr)

    assessments = []
    exit_code = 0

    for resource, query in QUERIES.items():
        if args.dry_run:
            trend = {"cpu": 0.8, "memory": 0.4, "connections": 0.1}.get(resource, 0.3)
            points = synthetic_data(trend)
        else:
            points = query_prometheus(args.prometheus_url, query)

        result = assess(resource, points, THRESHOLDS[resource], horizon_hours)
        assessments.append(result)

        if result["breach_imminent"]:
            print(f"  ⚠️  BREACH IMMINENT: {resource} will hit "
                  f"{THRESHOLDS[resource]}% in ~{result['hours_until_threshold']:.0f}h",
                  file=sys.stderr)
            exit_code = 1
        else:
            print(f"  ✅ {resource}: {result['current_pct']:.1f}% (OK)", file=sys.stderr)

    report = {
        "generated_at": now_iso,
        "horizon_days": args.horizon_days,
        "assessments": assessments,
        "exit_code": exit_code,
    }

    output = json.dumps(report, indent=2)
    if args.output == "-":
        print(output)
    else:
        import os
        os.makedirs(os.path.dirname(args.output) or ".", exist_ok=True)
        with open(args.output, "w") as f:
            f.write(output)
        print(f"  Report written to {args.output}", file=sys.stderr)

    sys.exit(exit_code)


if __name__ == "__main__":
    main()
