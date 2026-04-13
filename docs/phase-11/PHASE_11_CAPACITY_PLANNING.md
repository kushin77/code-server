# Phase 11: Capacity Planning & Right-Sizing

**Document**: ML-driven capacity planning and forecasting  
**Date**: April 13, 2026

## Overview

Phase 11 capacity planning uses historical metrics to forecast growth and recommend optimizations:

- **Trend Analysis**: 6-month historical data
- **Growth Forecasting**: 12-month predictions
- **Right-Sizing**: Recommendations for each component
- **Cost Optimization**: Cloud waste detection
- **Headroom Planning**: Ensure 30% capacity buffer

## Metrics Collection

### Data Points Tracked

```
# Application Layer
- Request throughput (req/s)
- Response latency (p50, p95, p99)
- Error rate (%)
- Active sessions

# Database Layer
- Query throughput (queries/s)
- Query latency (p99)
- Replication lag (bytes/ms)
- Connection count
- WAL generation rate (MB/min)
- Disk usage (GB)

# Cache Layer
- Cache hit ratio (%)
- Eviction rate (keys/min)
- Memory usage (GB)
- Read throughput (ops/s)
- Write throughput (ops/s)

# Infrastructure
- CPU utilization (%)
- Memory utilization (%)
- Disk I/O throughput (IOPS)
- Network bandwidth (Mbps)
- Pod restart count

# Business Metrics
- Active users
- Transactions processed
- Data volume growth
- Cost per request (USD)
```

### Collection Configuration

```python
# Prometheus scrape configuration for long-term storage

# Remote storage (1-year retention)
remote_write:
  - url: http://prometheus-longterm-storage:9009/write
    write_relabel_configs:
    - source_labels: [__name__]
      regex: 'container_memory_usage_bytes|container_cpu_usage_seconds|http_requests_duration_seconds|db_.*'
      action: keep

# Query examples
query:
  - instance:node_cpu:rate5m
  - instance:node_memory_utilization:ratio
  - instance:requests:rate1m
```

## Forecasting Model

### Seasonal Decomposition

Every metric is decomposed into:
```
Observed = Trend + Seasonal + Residual

Example: Request throughput
├─ Observed: 1000 req/s
├─ Trend: 950 req/s (underlying growth)
├─ Seasonal: +50 req/s (time-of-day effect)
└─ Residual: ±10 req/s (noise/anomalies)
```

### Growth Rate Calculation

```python
import numpy as np
from scipy import stats

def calculate_growth_rate(metrics_history):
    """
    Calculate exponential growth rate
    
    Args:
        metrics_history: Array of measurements over time
    
    Returns:
        Growth rate (% per month)
    """
    
    # Remove outliers (2 std dev)
    mean = np.mean(metrics_history)
    std = np.std(metrics_history)
    filtered = metrics_history[
        (metrics_history > mean - 2*std) & 
        (metrics_history < mean + 2*std)
    ]
    
    # Exponential fit: y = a * e^(bx)
    x = np.arange(len(filtered))
    slope, intercept, r_value, _, _ = stats.linregress(x, np.log(filtered + 1))
    
    # Monthly growth rate
    monthly_growth = (np.exp(slope * 30) - 1) * 100
    
    return monthly_growth, r_value**2  # r-squared for confidence
```

### Forecast Generation

```python
def forecast_12_months(current_value, monthly_growth_rate):
    """
    Generate 12-month forecast
    
    Args:
        current_value: Current metric value
        monthly_growth_rate: Growth % per month
    
    Returns:
        12-month projection with confidence intervals
    """
    
    forecast = []
    for month in range(1, 13):
        value = current_value * (1 + monthly_growth_rate/100) ** month
        # 95% confidence interval
        ci_lower = value * 0.9  # -10% confidence bound
        ci_upper = value * 1.1  # +10% confidence bound
        
        forecast.append({
            'month': month,
            'value': value,
            'ci_lower': ci_lower,
            'ci_upper': ci_upper,
        })
    
    return forecast
```

## Capacity Report

### Example: PostgreSQL CPU Projection

```
Current State (April 2026):
├─ CPU: 40% utilization
├─ 6-month trend: +8% per month
├─ Confidence: 92% (r² = 0.845)

12-Month Forecast:
├─ Month 1 (May): 43% (+4% buffer)
├─ Month 3 (July): 50% (target max)
├─ Month 6 (October): 62% (EXCEEDS CAPACITY)
├─ Month 12 (April 2027): 92% (CRITICAL)

Action Items:
├─ Right-size: Increase vCPU from 4 to 8 vCPU (month 5)
├─ Cost: $500/month additional → $50/req
└─ Timeline: Order in month 3 for month 5 installation
```

### Dashboard Forecast

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: capacity-forecast-dashboard
data:
  dashboard.json: |
    {
      "dashboard": {
        "title": "Capacity Forecast",
        "panels": [
          {
            "title": "PostgreSQL CPU Forecast",
            "targets": [
              {
                "expr": "predict_linear(node_cpu_usage[6h], 3600*24*30*12)"
              }
            ]
          },
          {
            "title": "Memory Utilization Forecast",
            "targets": [
              {
                "expr": "predict_linear(container_memory_usage_bytes[6h], 3600*24*30*12)"
              }
            ]
          },
          {
            "title": "Disk Space Forecast",
            "targets": [
              {
                "expr": "predict_linear(node_filesystem_avail_bytes[30d], 3600*24*30*12)"
              }
            ]
          }
        ]
      }
    }
```

## Right-Sizing Recommendations

### PostgreSQL Sizing

| Scenario | Current | Recommended | Cost Impact | Timeline |
|----------|---------|-------------|-------------|----------|
| 50 GB database | 8 vCPU | 12 vCPU (+50%) | +$800/mo | Month 5 |
| 1000 conn/min | 32GB RAM | 48GB (+50%) | +$400/mo | Month 4 |
| 500MB WAL/min | 100GB SSD | 300GB (+200%) | +$200/mo | Month 3 |

### Redis Cache Sizing

| Scenario | Current | Recommended | Cost Impact | Timeline |
|----------|---------|-------------|-------------|----------|
| Hot dataset | 60GB | 100GB (+67%) | +$300/mo | Month 6 |
| 100k QPS | 6 nodes | 9 nodes (+50%) | +$600/mo | Month 7 |
| Eviction rate | 5% | <1% | +$250/mo | Month 8 |

### Application Tier Sizing

| Scenario | Current | Recommended | Cost Impact | Timeline |
|----------|---------|-------------|-------------|----------|
| Peak load | 3 nodes | 5 nodes (+67%) | +$400/mo | Month 4 |
| Memory per pod | 2GB | 4GB (+100%) | +$200/mo | Month 3 |
| CPU reservation | 1 core | 2 cores (+100%) | +$300/mo | Month 5 |

## Cost Attribution

### Cost Breakdown

```
Monthly Infrastructure Cost: $10,000

Breakdown by Service:
├─ PostgreSQL: $4,500 (45%)
│   ├─ Compute: 60%
│   ├─ Storage: 30%
│   └─ Replication: 10%
├─ Redis: $2,000 (20%)
│   ├─ Memory: 70%
│   ├─ Network: 20%
│   └─ Backup: 10%
├─ Application: $2,000 (20%)
│   ├─ Compute: 80%
│   └─ Network: 20%
└─ Infrastructure: $1,500 (15%)
    ├─ Load balancer: 40%
    ├─ VPC/NAT: 30%
    └─ Monitoring: 30%

Cost Per Request (avg):
├─ Request throughput: 100k req/day
├─ Daily cost: $333
└─ Cost per request: $0.00333
```

### Optimization Opportunities

```price
Identified Waste:
├─ Unused reserved capacity (20%): Save $2,000/mo
├─ Overprovisioned cache (15%): Save $300/mo
├─ Data egress charges: Save $400/mo (optimize queries)
├─ Unused snapshots: Save $150/mo
└─ Total potential savings: $2,850/mo (28.5%)

Implementation Plan:
├─ Week 1: Right-size cache (save $300/mo, 2h effort)
├─ Week 2: Optimize data egress (save $400/mo, 8h effort)
├─ Week 3: Clean up snapshots (save $150/mo, 1h effort)
└─ Month 2: Implement reserved capacity (save $2,000/mo, on contract renewal)
```

## Metrics Dashboard

### SQL Queries for Reporting

```sql
-- Capacity forecast report
SELECT 
  DATE_TRUNC('month', timestamp) as month,
  'cpu' as metric,
  AVG(cpu_utilization) as current,
  PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY cpu_utilization) as p95,
  CASE 
    WHEN AVG(cpu_utilization) > 80 THEN 'CRITICAL'
    WHEN AVG(cpu_utilization) > 70 THEN 'HIGH'
    WHEN AVG(cpu_utilization) > 50 THEN 'MEDIUM'
    ELSE 'LOW'
  END as capacity_status
FROM system_metrics
WHERE component = 'postgresql'
GROUP BY DATE_TRUNC('month', timestamp)
ORDER BY month DESC;

-- Growth rate analysis
WITH monthly_averages AS (
  SELECT
    DATE_TRUNC('month', timestamp) as month,
    AVG(request_throughput) as throughput
  FROM metrics
  WHERE name = 'http_requests_total'
  GROUP BY month
)
SELECT
  month,
  throughput,
  LAG(throughput) OVER (ORDER BY month) as prev_month,
  ROUND(100 * (throughput - LAG(throughput) OVER (ORDER BY month)) / 
        LAG(throughput) OVER (ORDER BY month), 2) as growth_percent
FROM monthly_averages
ORDER BY month DESC;

-- Cost per request
SELECT
  DATE_TRUNC('hour', timestamp) as hour,
  COUNT(*) as requests,
  SUM(infrastructure_cost) as hourly_cost,
  ROUND(SUM(infrastructure_cost) / COUNT(*), 6) as cost_per_request
FROM events
WHERE timestamp > NOW() - INTERVAL '30 days'
GROUP BY hour
ORDER BY hour DESC;
```

## Scheduling Recommendations

### Scaling Timeline

```
Current (April 13, 2026):
└─ Resource Utilization: 40-50%
   └─ Budget: $10,000/month
   └─ Headroom: 50-60% (excess capacity)

April (Month 0) - Establish Baseline
└─ Collect 30 days of metrics
└─ Validate forecasting model
└─ Identify growth drivers

May-June (Months 1-2) - Planning Phase
├─ Refine forecasts with 60 days of data
├─ Identify right-sizing opportunities
├─ Start cost optimization
└─ Budget: $10,500/month (+5%)

July-August (Months 3-4) - First Wave of Scaling
├─ CPU scaling: 4 → 8 vCPU  
├─ Memory scaling: 32GB → 48GB
├─ Add cache replicas (6 → 9 nodes)
└─ Budget: $12,000/month (+20%)

September-December (Months 5-8) - Optimization
├─ Monitor actual vs. forecast
├─ Optimize based on real utilization
├─ Reserve capacity on favorable terms
└─ Budget: $12,500/month (stable)

January 2027+ (Year 2)
└─ Capacity review every quarter
└─ Rolling forecast model
└─ Annual contract optimization
```

---

**Status**: Complete  
**Last Updated**: April 13, 2026
