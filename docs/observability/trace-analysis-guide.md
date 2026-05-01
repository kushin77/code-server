# Trace Analysis Guide

**Phase**: 13 - Trace Analysis & Insights  
**Audience**: SREs, service owners, and incident responders  
**Scope**: anomaly detection, latency profiling, critical path analysis, and service health insights

The shared trace-analysis modules turn trace data into operator-friendly evidence.
Use them when you need to understand why a service is slow, which dependency is causing
the slowdown, or whether a deployment introduced a new latency pattern.

## Modules

### `apps/shared/trace_analysis.py`
Provides low-level analysis primitives:

- `AnomalyDetector` for latency outliers and baseline tracking
- `LatencyProfiler` for p95 and p99 timing evidence
- `CriticalPathFinder` for the slowest path through a trace graph
- `TraceCorrelationEngine` for user- and tenant-centric correlation

### `apps/shared/trace_insights.py`
Turns analysis output into actionable guidance:

- `TraceInsightsEngine` for SLO calculations and recommendations
- `DependencyAnalyzer` for service-to-service dependency health
- `ServiceHealthScore` for an overall service rating

## Typical Workflow

1. Record trace samples and latencies from the service under investigation.
2. Use `LatencyProfiler` to compute percentile statistics.
3. Run `AnomalyDetector` against the most recent measurements.
4. Identify the critical path if a request is slow but not obviously failing.
5. Feed the stats into `TraceInsightsEngine` to get SLO metrics and next-step recommendations.

## Output To Look For

- Latency spikes beyond the recent baseline
- Critical path spans with the largest aggregate latency
- Service dependencies with high latency or rising error rates
- Recommendations that point to the highest-impact optimization first

## Operator Notes

- The modules are deterministic and safe to run locally.
- They are designed for post-incident analysis as well as routine performance reviews.
- The output is most useful when paired with the request traces and alert history.