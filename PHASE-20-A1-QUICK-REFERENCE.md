# Phase 20, Component A1: Quick Reference Guide
## Global Orchestration Framework - Engineer Handbook

**Purpose**: Quick lookup guide for using the Global Operations Framework  
**Audience**: Platform engineers, SREs, DevOps team  
**Version**: 1.0  

---

## Table of Contents

1. [Getting Started](#getting-started)
2. [Common Tasks](#common-tasks)
3. [API Reference](#api-reference)
4. [Troubleshooting](#troubleshooting)
5. [Runbooks](#runbooks)

---

## Getting Started

### Installation
```bash
# Clone repository
git clone https://github.com/kushin77/eiq-linkedin.git
cd code-server-enterprise

# Install dependencies
pip install -r requirements.txt

# Or manually:
pip install requests numpy prometheus-client
```

### Starting the Engine
```bash
# Start orchestration engine
python scripts/phase_20_global_orchestration.py

# Verify it's running:
curl http://localhost:9205/metrics

# You should see metrics like:
# global_region_health{region="us-east-1"} 1
# global_regional_latency_ms_bucket{region="us-east-1",...} ...
```

### Configuration
```bash
# Set log level (default: INFO)
export LOG_LEVEL=DEBUG  # or WARNING, ERROR

# Set metrics port (default: 9205)
export METRICS_PORT=8888

# Start with custom config
python scripts/phase_20_global_orchestration.py \
  --config /etc/orchestration/config.yaml \
  --log-level DEBUG
```

---

## Common Tasks

### Task 1: Register a Service Globally

**Goal**: Add a new service to global orchestration

```python
from phase_20_global_orchestration import (
    GlobalOrchestrationEngine,
    Region,
    RegionalEndpoint,
    GlobalTrafficPolicy
)

engine = GlobalOrchestrationEngine()

# Define service endpoints
endpoints = [
    RegionalEndpoint(
        region=Region.US_EAST_1,
        service_name="my-service",
        url="http://my-service.us-east-1.internal",
        health_check_path="/health",
        latency_ms=25,
        error_rate=0.001,
        capacity_usage=0.45,
        instance_count=5,
        healthy=True
    ),
    RegionalEndpoint(
        region=Region.EU_WEST_1,
        service_name="my-service",
        url="http://my-service.eu-west-1.internal",
        health_check_path="/health",
        latency_ms=80,
        error_rate=0.002,
        capacity_usage=0.55,
        instance_count=4,
        healthy=True
    ),
]

# Define traffic policy
policy = GlobalTrafficPolicy(
    service="my-service",
    primary_region=Region.US_EAST_1,
    secondary_regions=[Region.EU_WEST_1],
    latency_threshold_ms=150,
    error_rate_threshold=0.01,
    capacity_threshold=0.80,
    failover_decision_threshold=3,
    traffic_distribution={
        Region.US_EAST_1: 0.8,
        Region.EU_WEST_1: 0.2,
    }
)

# Register service
engine.traffic_director.register_service("my-service", endpoints, policy)
print("✓ Service registered")
```

**Validation**:
```bash
# Check metrics
curl http://localhost:9205/metrics | grep "my-service"
```

---

### Task 2: Discover a Service Endpoint

**Goal**: Get the endpoint for a specific service

```python
# Basic discovery (any healthy endpoint)
endpoint = engine.service_discovery.discover_service("api-service")
# Returns: "http://us-east-1.api.example.com" (or EU/APAC)

# Regional discovery
endpoint = engine.service_discovery.discover_service(
    "api-service",
    region=Region.US_EAST_1
)
# Returns: "http://us-east-1.api.example.com"

# With preferred region fallback
endpoint = engine.service_discovery.discover_service(
    "api-service",
    preferred_region=Region.EU_WEST_1
)
# Returns: EU endpoint if available, else any healthy endpoint
```

**In Application Code**:
```python
import requests

def call_api(endpoint_path):
    # Discovery
    service_url = engine.service_discovery.discover_service("api-service")
    
    # Make request
    response = requests.get(f"{service_url}{endpoint_path}")
    return response.json()

# Usage
result = call_api("/users/123")
```

---

### Task 3: Update Global Configuration

**Goal**: Distribute a configuration update to all regions

```python
# Prepare configuration
new_config = {
    "feature_flags": {
        "new_payment_system": True,
        "beta_ui": False,
        "experimental_api": True
    },
    "rate_limits": {
        "api_requests_per_second": 10000,
        "batch_size_limit": 1000
    },
    "cache_ttl_seconds": 3600
}

# Distribute globally (to all regions)
success = engine.config_distribution.update_global_config(
    config_key="application-config",
    value=new_config
)

if success:
    print("✓ Config distributed to all regions")
else:
    print("✗ Config distribution failed")

# Distribute to specific regions only
success = engine.config_distribution.update_global_config(
    config_key="regional-config",
    value={"data_center": "us-east"},
    regions=[Region.US_EAST_1, Region.US_WEST_2]
)
```

**Rollback if Needed**:
```python
# Get previous version
previous_config = engine.config_distribution.get_config_version("application-config", version=n-1)

# Rollback
success = engine.config_distribution.update_global_config(
    config_key="application-config",
    value=previous_config
)
```

---

### Task 4: Monitor Regional Health

**Goal**: Check the health of services across regions

```python
# Run health checks
service = "api-service"
health_status = engine.traffic_director.perform_health_checks(service)

# Results
# {
#   Region.US_EAST_1: True,
#   Region.EU_WEST_1: False,
#   Region.APAC_SOUTHEAST_1: True
# }

# Log results
for region, is_healthy in health_status.items():
    status = "✓ HEALTHY" if is_healthy else "✗ DOWN"
    print(f"{status} - {service} in {region.value}")

# Check specific region
if health_status.get(Region.US_EAST_1):
    print("US-EAST-1 is healthy")
else:
    print("US-EAST-1 is DOWN - may trigger failover")
```

---

### Task 5: Measure Latency to Regions

**Goal**: Get current latency measurements

```python
# Measure latency
service = "api-service"
latency_by_region = engine.traffic_director.measure_regional_latency(service)

# Results
# {
#   Region.US_EAST_1: 25.3,
#   Region.EU_WEST_1: 82.1,
#   Region.APAC_SOUTHEAST_1: 61.5
# }

# Find fastest region
fastest_region = min(latency_by_region, key=latency_by_region.get)
fastest_latency = latency_by_region[fastest_region]
print(f"Fastest region: {fastest_region.value} ({fastest_latency:.1f}ms)")

# Find slowest region
slowest_region = max(latency_by_region, key=latency_by_region.get)
slowest_latency = latency_by_region[slowest_region]
print(f"Slowest region: {slowest_region.value} ({slowest_latency:.1f}ms)")

# Alert if exceeds threshold
if slowest_latency > 150:
    print("⚠️ WARNING: Latency spike detected")
```

---

### Task 6: Check Failover Status

**Goal**: Review recent failover events

```python
# Get failover history
failovers = engine.traffic_director.failover_history

# Latest failover
if failovers:
    latest = failovers[-1]
    print(f"Event: {latest.event_id}")
    print(f"Source: {latest.source_region.value}")
    print(f"Target: {latest.target_region.value}")
    print(f"Reason: {latest.reason.value}")
    print(f"RTO: {latest.rto_seconds:.2f}s")
    print(f"RPO: {latest.rpo_seconds:.2f}s")
    print(f"Success: {'✓' if latest.success else '✗'}")
else:
    print("No failover events")

# Filter by service
api_failovers = [fo for fo in failovers if 'api-service' in fo.services_affected]
print(f"API service failovers: {len(api_failovers)}")
```

---

## API Reference

### GlobalTrafficDirector

```python
class GlobalTrafficDirector:
    def register_service(service_name: str, 
                        endpoints: List[RegionalEndpoint],
                        policy: GlobalTrafficPolicy) -> None
    """Register service with traffic director"""
    
    def perform_health_checks(service: str) -> Dict[Region, bool]
    """Check health of all regional endpoints"""
    # Returns: {Region.US_EAST_1: True, Region.EU_WEST_1: False, ...}
    
    def measure_regional_latency(service: str) -> Dict[Region, float]
    """Measure P99 latency to each region (in milliseconds)"""
    # Returns: {Region.US_EAST_1: 25.3, Region.EU_WEST_1: 82.1, ...}
    
    def decide_failover(service: str) -> Tuple[bool, Optional[Region], FailoverReason]
    """Determine if failover is needed"""
    # Returns: (needs_failover, target_region, reason)
    
    def execute_failover(service: str, target_region: Region, 
                        reason: FailoverReason) -> FailoverEvent
    """Execute failover to target region"""
    # Returns: FailoverEvent with RTO/RPO metrics
```

### GlobalServiceDiscovery

```python
class GlobalServiceDiscovery:
    def register_service_endpoint(service: str, region: Region,
                                 endpoint: str, 
                                 metadata: Dict = None) -> None
    """Register service endpoint in a region"""
    
    def discover_service(service: str, 
                        region: Optional[Region] = None,
                        preferred_region: Optional[Region] = None) -> Optional[str]
    """Discover service endpoint"""
    # Returns: "http://service-url.example.com" or None
    
    def invalidate_cache(service: str = None) -> None
    """Invalidate cache for service"""
```

### GlobalConfigDistribution

```python
class GlobalConfigDistribution:
    def update_global_config(config_key: str, value: Dict,
                           regions: List[Region] = None) -> bool
    """Distribute config globally"""
    # Returns: True if delivered to all regions, False otherwise
    
    def get_config_status(config_key: str) -> Dict[Region, bool]
    """Get distribution status for config"""
    # Returns: {Region.US_EAST_1: True, Region.EU_WEST_1: False, ...}
```

### GlobalMonitoring

```python
class GlobalMonitoring:
    def aggregate_metrics(services: List[str]) -> Dict
    """Aggregate metrics from all regions"""
    # Returns: {
    #     'by_region': {...},
    #     'by_service': {...},
    #     'global': {...}
    # }
```

---

## Troubleshooting

### Problem: Failover not triggering

**Check List**:
1. Is the primary region actually unhealthy?
   ```bash
   curl http://primary.region/health
   ```

2. Is the failover policy configured correctly?
   ```python
   policy = engine.traffic_director.policies['api-service']
   print(f"Threshold: {policy.latency_threshold_ms}ms")
   print(f"Primary: {policy.primary_region.value}")
   ```

3. Are secondary regions healthy?
   ```python
   health = engine.traffic_director.perform_health_checks('api-service')
   print(health)
   ```

### Problem: Service discovery returning wrong endpoint

**Check List**:
1. Is the service registered?
   ```python
   if 'api-service' in engine.service_discovery.service_registry:
       print("✓ Service registered")
   else:
       print("✗ Service NOT registered")
   ```

2. Is the cache stale?
   ```python
   engine.service_discovery.invalidate_cache('api-service')
   endpoint = engine.service_discovery.discover_service('api-service')
   ```

3. Which regions have endpoints?
   ```python
   service_data = engine.service_discovery.service_registry.get('api-service', {})
   for region, data in service_data.items():
       print(f"{region.value}: {data['endpoint']}")
   ```

### Problem: Config not distributing to all regions

**Check List**:
1. Check distribution status
   ```python
   status = engine.config_distribution.distribution_status.get('config-key')
   print(status)
   ```

2. Are all regions reachable?
   ```bash
   # Test regional connectivity
   for region in [US_EAST_1, EU_WEST_1, ...]:
       curl http://{region}/health
   ```

3. Manually push to region
   ```python
   success = engine.config_distribution.update_global_config(
       'test-config',
       {'test': True},
       regions=[Region.US_EAST_1]
   )
   ```

---

## Runbooks

### Runbook 1: Manual Failover (Emergency)

**When to use**: When automatic failover is stuck or failed

```bash
# 1. Verify primary is down
curl http://primary-endpoint/health

# 2. Verify secondary is healthy
curl http://secondary-endpoint/health

# 3. Execute failover in Python
python3 << 'EOF'
from phase_20_global_orchestration import GlobalOrchestrationEngine, Region, FailoverReason

engine = GlobalOrchestrationEngine()
event = engine.traffic_director.execute_failover(
    service='api-service',
    target_region=Region.EU_WEST_1,
    reason=FailoverReason.DELIBERATE
)

print(f"Failover RTO: {event.rto_seconds:.2f}s")
print(f"Status: {'✓ Success' if event.success else '✗ Failed'}")
EOF

# 4. Verify failover
curl http://secondary-endpoint/health

# 5. Monitor: Check dashboard for traffic shift
```

### Runbook 2: Recovery from Failover

**When to use**: After manual failover, when original region is back online

```bash
# 1. Verify original region is healthy
curl http://primary-endpoint/health

# 2. Allow time for data sync (check replication lag)
python3 << 'EOF'
# Monitor lag until < 5 seconds
# Then proceed
EOF

# 3. Execute failback
python3 << 'EOF'
from phase_20_global_orchestration import GlobalOrchestrationEngine, Region, FailoverReason

engine = GlobalOrchestrationEngine()
event = engine.traffic_director.execute_failover(
    service='api-service',
    target_region=Region.US_EAST_1,
    reason=FailoverReason.DELIBERATE
)

print(f"Failback RTO: {event.rto_seconds:.2f}s")
EOF

# 4. Monitor for stability
# Watch metrics for 5 minutes
```

### Runbook 3: Configuration Rollback

**When to use**: Bad configuration was deployed

```bash
# 1. Stop accepting new traffic (if critical)
python3 << 'EOF'
# Set traffic distribution to 0
EOF

# 2. Determine previous version
python3 << 'EOF'
from phase_20_global_orchestration import GlobalOrchestrationEngine

engine = GlobalOrchestrationEngine()
config_key = 'problematic-config'

# Get version history
versions = engine.config_distribution.config_store.keys()
print(f"Known versions: {versions}")
EOF

# 3. Rollback to previous version
python3 << 'EOF'
from phase_20_global_orchestration import GlobalOrchestrationEngine

engine = GlobalOrchestrationEngine()

# Prepare previous config
previous_config = {...}  # Previous good config

# Distribute
success = engine.config_distribution.update_global_config(
    'problematic-config',
    previous_config
)

print(f"Rollback: {'✓ Success' if success else '✗ Failed'}")
EOF

# 4. Resume traffic
python3 << 'EOF'
# Restore normal traffic distribution
EOF

# 5. Incident review
# Document what went wrong
# Update config validation rules
```

---

## Metrics Cheat Sheet

### Prometheus Queries

```promql
# CPU understanding: Global health (right now)
global_region_health{region="us-east-1"}
# Result: 1 (healthy) or 0 (unhealthy)

# Latency to regions
global_regional_latency_ms_bucket{region="us-east-1"}
# Result: Latency histogram buckets

# Error rate per region
global_regional_error_rate{region="us-east-1",service="api"}
# Result: Error rate as decimal (e.g., 0.001 = 0.1%)

# Failovers count
increase(global_failover_events_total[1h])
# Result: Number of failovers in last hour

# Service discovery latency (P99)
histogram_quantile(0.99, global_service_discovery_latency_ms_bucket)
# Result: P99 latency in milliseconds

# Replication lag
global_data_replication_lag_seconds{source_region="us-east-1",target_region="eu-west-1"}
# Result: Lag in seconds
```

---

## Support & Escalation

### Issue: Code bug in orchestration engine
→ File issue: `#component-a1-orchestration`

### Issue: Service won't register
→ Check: Health endpoints reachable? → Ask: DevOps team

### Issue: Failover stuck
→ Escalate: To SRE on-call → Use: Manual failover runbook

### Issue: Data inconsistency across regions
→ Escalate: To Data team → Use: Replication lag metrics

---

## Additional Resources

- [Full Documentation](./PHASE-20-COMPONENT-A1-ORCHESTRATION.md)
- [Strategic Plan](./PHASE-20-STRATEGIC-PLAN.md)
- [Source Code](./scripts/phase_20_global_orchestration.py)
- [Prometheus Docs](https://prometheus.io/)
- [Grafana Dashboard](./monitoring/dashboards/global-operations.json)

---

**Version**: 1.0  
**Last Updated**: 2024-01-27  
**Maintained By**: Enterprise Architecture Team  
**Status**: Ready for Production
