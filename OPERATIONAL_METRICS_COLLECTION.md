# Hermes Agent Portal - Operational Metrics Collection & Analysis

**Date:** April 30, 2026  
**Purpose:** Track and analyze system health metrics for operations  
**Frequency:** Collect hourly, analyze daily/weekly  

---

## Metrics to Collect

### 1. Service Availability Metrics

```bash
# Script: collect-availability.sh

# Daily uptime
UPTIME_START=$(date +%s)

# Check service status every hour
while true; do
    TIMESTAMP=$(date +'%Y-%m-%d %H:%M:%S')
    
    # Check if all services are healthy
    SERVICES_HEALTHY=$(docker-compose -f docker-compose.enterprise.yml ps | grep -c "Up (healthy)")
    
    # Log result
    echo "$TIMESTAMP: $SERVICES_HEALTHY/5 services healthy" >> uptime.log
    
    sleep 3600  # Every hour
done

# Calculate daily uptime
TOTAL_CHECKS=$(wc -l < uptime.log)
HEALTHY_CHECKS=$(grep -c "5/5 services healthy" uptime.log)
UPTIME_PERCENT=$((HEALTHY_CHECKS * 100 / TOTAL_CHECKS))
echo "Daily Uptime: ${UPTIME_PERCENT}%"
```

### 2. Performance Metrics

```bash
# Script: collect-performance.sh

# Collect every 5 minutes
while true; do
    TIMESTAMP=$(date +'%Y-%m-%d %H:%M:%S')
    
    # CPU usage
    CPU_API=$(docker stats --no-stream --filter "name=hermes-integration" --format "{{.CPUPerc}}" | sed 's/%//')
    CPU_APP=$(docker stats --no-stream --filter "name=appsmith" --format "{{.CPUPerc}}" | sed 's/%//')
    CPU_DB=$(docker stats --no-stream --filter "name=code-server-postgres" --format "{{.CPUPerc}}" | sed 's/%//')
    
    # Memory usage (in MB)
    MEM_API=$(docker stats --no-stream --filter "name=hermes-integration" --format "{{.MemUsage}}" | awk '{print $1}')
    MEM_APP=$(docker stats --no-stream --filter "name=appsmith" --format "{{.MemUsage}}" | awk '{print $1}')
    MEM_DB=$(docker stats --no-stream --filter "name=code-server-postgres" --format "{{.MemUsage}}" | awk '{print $1}')
    
    # API response time (milliseconds)
    RESPONSE_TIME=$(curl -s -k -w "%{time_total}" -o /dev/null https://kushnir.cloud/api/hermes/health | awk '{print $1 * 1000}')
    
    # Log metrics
    echo "$TIMESTAMP,${CPU_API},${CPU_APP},${CPU_DB},${MEM_API},${MEM_APP},${MEM_DB},${RESPONSE_TIME}" >> performance.csv
    
    sleep 300  # Every 5 minutes
done
```

### 3. Resource Utilization Metrics

```
Metric              Unit      Target    Warning   Critical
─────────────────────────────────────────────────────────
CPU Usage (API)     %         < 30%     > 50%     > 80%
CPU Usage (App)     %         < 20%     > 40%     > 70%
CPU Usage (DB)      %         < 40%     > 60%     > 80%
Memory (API)        MB        < 500     > 800     > 1000
Memory (App)        MB        < 600     > 900     > 1200
Memory (DB)         MB        < 400     > 600     > 800
Disk Usage          %         < 70%     > 80%     > 90%
API Response Time   ms        < 500     > 1000    > 2000
Database Conn       count     < 50      > 100     > 200
```

### 4. Error Rate Metrics

```bash
# Script: collect-errors.sh

# Collect errors every hour
while true; do
    TIMESTAMP=$(date +'%Y-%m-%d %H:%M:%S')
    
    # Count errors in logs
    API_ERRORS=$(docker logs --since 1h hermes-integration 2>/dev/null | grep -i "error" | wc -l)
    APP_ERRORS=$(docker logs --since 1h appsmith 2>/dev/null | grep -i "error" | wc -l)
    DB_ERRORS=$(docker logs --since 1h code-server-postgres 2>/dev/null | grep -i "error" | wc -l)
    
    TOTAL_ERRORS=$((API_ERRORS + APP_ERRORS + DB_ERRORS))
    
    echo "$TIMESTAMP: API=$API_ERRORS, App=$APP_ERRORS, DB=$DB_ERRORS, Total=$TOTAL_ERRORS" >> error_log.txt
    
    sleep 3600  # Every hour
done
```

### 5. User Activity Metrics

```bash
# Script: collect-activity.sh

# Collect API request counts every hour
while true; do
    TIMESTAMP=$(date +'%Y-%m-%d %H:%M:%S')
    
    # Count API requests from logs
    API_REQUESTS=$(docker logs --since 1h hermes-integration 2>/dev/null | grep "GET\|POST\|PUT\|DELETE" | wc -l)
    
    # Count successful requests (200-299)
    SUCCESSFUL=$(docker logs --since 1h hermes-integration 2>/dev/null | grep " 2[0-9][0-9] " | wc -l)
    
    # Count errors (400-599)
    ERRORS=$(docker logs --since 1h hermes-integration 2>/dev/null | grep " [45][0-9][0-9] " | wc -l)
    
    SUCCESS_RATE=$((SUCCESSFUL * 100 / (SUCCESSFUL + ERRORS)))
    
    echo "$TIMESTAMP: Requests=$API_REQUESTS, Success=$SUCCESSFUL, Errors=$ERRORS, SuccessRate=${SUCCESS_RATE}%" >> activity.log
    
    sleep 3600  # Every hour
done
```

---

## Automated Metrics Collection

### Hourly Collection Script

```bash
#!/bin/bash
# metrics-hourly.sh - Run this from cron every hour

METRICS_DIR="metrics"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

mkdir -p "$METRICS_DIR/hourly"

# Collect service status
docker-compose -f docker-compose.enterprise.yml ps > "$METRICS_DIR/hourly/services_${TIMESTAMP}.txt"

# Collect resource usage
docker stats --no-stream > "$METRICS_DIR/hourly/resources_${TIMESTAMP}.txt"

# Collect disk usage
df -h /home >> "$METRICS_DIR/hourly/disk_${TIMESTAMP}.txt"

# Collect API response time
curl -s -k -w "@-" -o /dev/null https://kushnir.cloud/api/hermes/health > "$METRICS_DIR/hourly/api_response_${TIMESTAMP}.txt" <<< '
    Response Time: %{time_total}s\n
    HTTP Status: %{http_code}\n
'

# Collect error count
docker-compose -f docker-compose.enterprise.yml logs --since 1h | grep -c "ERROR\|FATAL" >> "$METRICS_DIR/hourly/error_count_${TIMESTAMP}.txt" || echo "0" >> "$METRICS_DIR/hourly/error_count_${TIMESTAMP}.txt"

echo "[OK] Hourly metrics collected: $METRICS_DIR/hourly/"
```

### Cron Schedule

```bash
# Add to crontab: crontab -e

# Collect metrics hourly
0 * * * * /home/akushnir/code-server/metrics-hourly.sh

# Daily analysis at 8 AM
0 8 * * * /home/akushnir/code-server/metrics-daily-analysis.sh

# Weekly report at Monday 9 AM
0 9 * * 1 /home/akushnir/code-server/metrics-weekly-report.sh

# Monthly report on 1st at 9 AM
0 9 1 * * /home/akushnir/code-server/metrics-monthly-report.sh
```

---

## Daily Analysis

### Morning Review (8 AM)

```bash
# Check yesterday's metrics
echo "=== Yesterday's Performance Summary ==="

# Average CPU usage
docker stats --no-stream --format "{{.Container}}\t{{.CPUPerc}}" yesterday_*.txt

# Peak memory usage
echo "Peak Memory:"
grep "MemUsage" yesterday_*.txt | sort -k3 -h | tail -5

# Error count
echo "Errors in last 24h:"
docker-compose -f docker-compose.enterprise.yml logs --since 24h | grep -i "ERROR\|FATAL" | wc -l

# System availability
echo "Service Uptime:"
grep "5/5 services healthy" yesterday_*.txt | wc -l
```

---

## Weekly Analysis

### Friday End-of-Week Report

```
Metric                    Min     Max     Avg     Target  Status
────────────────────────────────────────────────────────────────
CPU Usage (API)          10%     65%     32%     < 30%   ✓ Good
CPU Usage (App)          15%     48%     25%     < 20%   ⚠ Monitor
CPU Usage (DB)           20%     72%     35%     < 40%   ✓ Good
Memory (API)             250MB   850MB   520MB   < 500MB ⚠ Alert
Memory (App)             300MB   950MB   600MB   < 600MB ✓ Good
Memory (DB)              200MB   450MB   350MB   < 400MB ✓ Good
API Response Time        150ms   2300ms  540ms   < 500ms ⚠ Alert
Success Rate             98.5%   99.9%   99.2%   > 99%   ✓ Good
Availability             99.2%   100%    99.8%   > 99.5% ✓ Good
Error Count              0       45      12      < 50    ✓ Good

Actions Needed:
  1. Optimize memory usage for Appsmith (950MB peak)
  2. Investigate API slow response times (up to 2300ms)
  3. Continue monitoring CPU usage trends

Recommendations:
  1. Run: ./optimize-performance.sh optimize
  2. Review: docker logs appsmith | grep -i "memory\|gc"
  3. Schedule: Database maintenance for next Monday
```

---

## Monthly Analysis

### End-of-Month Trends

```
Trend Analysis - April 2026

1. AVAILABILITY TREND
   Week 1: 99.95%
   Week 2: 99.87%
   Week 3: 99.92%
   Week 4: 99.98%
   ✓ Stable, slight improvement

2. PERFORMANCE TREND
   Week 1: Avg response 480ms
   Week 2: Avg response 520ms
   Week 3: Avg response 650ms (memory optimization done)
   Week 4: Avg response 540ms
   ✓ Stable after optimization

3. ERROR TREND
   Week 1: 5 errors
   Week 2: 12 errors
   Week 3: 8 errors
   Week 4: 2 errors
   ✓ Improving

4. RESOURCE TREND
   CPU: Stable (20-35% average)
   Memory: Slight increase (320 → 380MB average)
   Disk: Normal growth (5% week over week)
   ✓ Normal growth pattern

SUMMARY:
- System is stable and performant
- Performance optimization successfully improved response times
- Error rate trending down
- No critical issues
- Monthly status: ✓ HEALTHY
```

---

## Alerting Thresholds

### Auto-Alert Triggers

```bash
# CPU > 80% for 5 consecutive minutes
# Memory > 1200MB for 10 consecutive minutes
# Disk > 90% usage
# API response > 2000ms
# Error rate > 5 per hour
# Service down > 2 minutes

# Send alerts to:
# - Slack webhook: https://hooks.slack.com/services/...
# - Email: ops-team@company.com
# - PagerDuty: incident creation
```

---

## Metrics Retention Policy

```
Granularity    Retention      Location
─────────────────────────────────────────
5-minute data  7 days         $METRICS_DIR/5min/
Hourly data    30 days        $METRICS_DIR/hourly/
Daily summary  1 year         $METRICS_DIR/daily/
Weekly report  2 years        $METRICS_DIR/weekly/
Monthly report Indefinite     $METRICS_DIR/monthly/

Archive old data:
tar -czf metrics_archive_$(date +%Y%m).tar.gz metrics/5min metrics/hourly
```

---

## Tools & Scripts

**Included Scripts:**
- `monitor-health.sh` - Real-time monitoring
- `validate-deployment.sh` - Full validation with metrics
- `optimize-performance.sh` - Performance analysis
- `metrics-hourly.sh` - Hourly collection (create)
- `metrics-daily-analysis.sh` - Daily analysis (create)
- `metrics-weekly-report.sh` - Weekly report (create)

---

## Dashboard Integration

**For visual monitoring, can integrate with:**
- Prometheus + Grafana
- ELK Stack (Elasticsearch, Logstash, Kibana)
- Datadog
- New Relic
- CloudWatch

**Basic Grafana example:**
```
Data Source: Prometheus (scrapes metrics from /metrics endpoint)
Dashboards:
  - System Resources
  - API Performance
  - Error Rates
  - Service Availability
  - Database Performance
```

---

**These metrics provide comprehensive operational visibility. Regular review ensures proactive issue detection and system optimization.**
