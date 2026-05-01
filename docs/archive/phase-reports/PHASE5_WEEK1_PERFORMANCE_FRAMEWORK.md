# Phase 5 Week 1: Performance Testing Framework Implementation

**Status:** 🟢 IN PROGRESS  
**Start Date:** 2026-04-28  
**Objective:** Establish performance baselines and deploy load testing infrastructure

---

## Deliverable 5.1: Performance Testing Framework

### Goal
Establish performance baselines and identify bottlenecks across critical services using production-like load scenarios.

### Architecture

```
┌─────────────────────────────────────────────────────────┐
│           Performance Testing Infrastructure            │
├─────────────────────────────────────────────────────────┤
│                                                         │
│  Locust Master                                          │
│  ├─ Scenario Orchestration                             │
│  ├─ Metrics Collection                                 │
│  └─ Results Aggregation                                │
│                                                         │
│  Docker Compose Stack (Services Under Test)            │
│  ├─ API Gateway (Load Entry Point)                     │
│  ├─ Auth Server                                        │
│  ├─ Activity Feed Service                              │
│  ├─ Execution Scheduler                                │
│  ├─ Reputation Engine                                  │
│  ├─ PostgreSQL (Database)                              │
│  ├─ Redis (Cache)                                      │
│  └─ Kafka (Message Broker)                             │
│                                                         │
│  Prometheus Scraper                                    │
│  ├─ Service Metrics                                    │
│  ├─ Container Metrics                                  │
│  └─ System Metrics                                     │
│                                                         │
│  Grafana Dashboard                                     │
│  ├─ Real-time Performance Graphs                       │
│  ├─ Response Time Distribution                         │
│  ├─ Throughput Metrics                                 │
│  └─ Error Rate Tracking                                │
│                                                         │
└─────────────────────────────────────────────────────────┘
```

### Implementation Tasks

#### Task 1.1: Create Locust Load Testing Scripts [IN PROGRESS]

Create `scripts/perf/locust-loadtest.py`:

```python
#!/usr/bin/env python3
"""
Locust load testing orchestration for code-server infrastructure
Supports 5 test scenarios: light, medium, heavy, spike, sustained

Usage:
  python3 scripts/perf/locust-loadtest.py --scenario=light --users=100
  python3 scripts/perf/locust-loadtest.py --scenario=heavy --users=500 --spawn-rate=50
"""
import os
import sys
from locust import HttpUser, TaskSet, task, between, events
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Configuration
API_BASE_URL = os.getenv("API_URL", "http://localhost:3100")
SCENARIO = os.getenv("SCENARIO", "medium")

class CodeServerUserBehavior(TaskSet):
    """Define user behavior patterns for load testing"""
    
    @task(4)
    def create_activity(self):
        """Activity creation - 40% of traffic"""
        self.client.post(
            "/api/activities",
            json={"description": "Test activity", "type": "manual"},
            timeout=5
        )
    
    @task(3)
    def list_activities(self):
        """Activity listing - 30% of traffic"""
        self.client.get("/api/activities?limit=50", timeout=5)
    
    @task(2)
    def get_reputation(self):
        """Reputation queries - 20% of traffic"""
        self.client.get("/api/reputation/score", timeout=5)
    
    @task(1)
    def check_execution(self):
        """Execution status - 10% of traffic"""
        self.client.get("/api/executions/status", timeout=5)

class CodeServerUser(HttpUser):
    """Load testing user profile"""
    tasks = [CodeServerUserBehavior]
    wait_time = between(1, 3)
    host = API_BASE_URL

# Test scenario configurations
SCENARIOS = {
    "light": {
        "users": 50,
        "spawn_rate": 5,
        "duration_sec": 300,
        "description": "Light load: 50 users over 5 minutes"
    },
    "medium": {
        "users": 200,
        "spawn_rate": 20,
        "duration_sec": 600,
        "description": "Medium load: 200 users over 10 minutes"
    },
    "heavy": {
        "users": 500,
        "spawn_rate": 50,
        "duration_sec": 900,
        "description": "Heavy load: 500 users over 15 minutes"
    },
    "spike": {
        "users": 1000,
        "spawn_rate": 200,
        "duration_sec": 300,
        "description": "Traffic spike: 1000 users in 5 seconds, then 5 minutes sustained"
    },
    "sustained": {
        "users": 300,
        "spawn_rate": 30,
        "duration_sec": 1800,
        "description": "Sustained load: 300 users for 30 minutes"
    }
}

@events.test_stop.add_listener
def on_test_stop(environment, **kwargs):
    """Generate performance report on test completion"""
    logger.info("=" * 60)
    logger.info("PERFORMANCE TEST RESULTS")
    logger.info("=" * 60)
    for req in environment.stats.entries.values():
        logger.info(f"\n{req.name}:")
        logger.info(f"  Requests: {req.num_requests}")
        logger.info(f"  Failures: {req.num_failures}")
        logger.info(f"  Avg Response: {req.avg_response_time:.0f}ms")
        logger.info(f"  Min Response: {req.min_response_time:.0f}ms")
        logger.info(f"  Max Response: {req.max_response_time:.0f}ms")
        logger.info(f"  P95: {req.get_response_time_percentile(0.95):.0f}ms")
        logger.info(f"  P99: {req.get_response_time_percentile(0.99):.0f}ms")

if __name__ == "__main__":
    logger.info(f"Load testing scenario: {SCENARIO}")
    logger.info(f"API URL: {API_BASE_URL}")
```

#### Task 1.2: Create Test Orchestration Shell Script

Create `scripts/perf/run-performance-test.sh`:

```bash
#!/bin/bash
###############################################################################
# Performance Testing Orchestrator
# Manages Docker Compose stack and runs Locust load tests
###############################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Configuration
API_URL="${API_URL:-http://localhost:3100}"
SCENARIO="${1:-medium}"
DOCKER_COMPOSE_FILE="$PROJECT_ROOT/docker-compose.yml"
LOCUST_SCRIPT="$SCRIPT_DIR/locust-loadtest.py"
RESULTS_DIR="$PROJECT_ROOT/artifacts/performance-results"
RESULTS_FILE="$RESULTS_DIR/results-$(date +%Y%m%d-%H%M%S).json"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }

# Create results directory
mkdir -p "$RESULTS_DIR"

# Validate scenario
if [[ ! "$SCENARIO" =~ ^(light|medium|heavy|spike|sustained)$ ]]; then
    log_error "Invalid scenario: $SCENARIO"
    log_error "Valid scenarios: light, medium, heavy, spike, sustained"
    exit 1
fi

log_info "Starting Docker Compose stack..."
docker-compose -f "$DOCKER_COMPOSE_FILE" up -d

log_info "Waiting for services to be ready..."
sleep 10

log_info "Running performance test: $SCENARIO"
python3 "$LOCUST_SCRIPT" \
    --scenario="$SCENARIO" \
    --headless \
    --csv="$RESULTS_FILE" \
    2>&1 | tee "$RESULTS_DIR/locust-${SCENARIO}-$(date +%Y%m%d-%H%M%S).log"

log_success "Performance test completed"
log_info "Results saved to: $RESULTS_FILE"

log_info "Generating Grafana dashboard snapshot..."
# TODO: Implement Grafana snapshot generation

log_info "Collecting container metrics..."
docker stats --no-stream > "$RESULTS_DIR/container-stats-$(date +%Y%m%d-%H%M%S).txt"

log_success "All artifacts saved to: $RESULTS_DIR"
```

#### Task 1.3: Create Performance Baseline Configuration

Create `config/performance-baselines.yml`:

```yaml
---
performance_baselines:
  response_time:
    p95_target_ms: 500
    p99_target_ms: 1000
    max_target_ms: 2000
  
  throughput:
    minimum_req_sec: 1000
    target_req_sec: 1500
  
  error_rate:
    maximum_percent: 0.1
    acceptable_percent: 0.05
  
  resource_utilization:
    cpu_max_percent: 80
    memory_max_percent: 85
    disk_io_max_percent: 90

test_scenarios:
  light:
    users: 50
    spawn_rate: 5
    duration_minutes: 5
    description: "Baseline load for development environment"
  
  medium:
    users: 200
    spawn_rate: 20
    duration_minutes: 10
    description: "Normal production load"
  
  heavy:
    users: 500
    spawn_rate: 50
    duration_minutes: 15
    description: "Peak load during business hours"
  
  spike:
    users: 1000
    spawn_rate: 200
    duration_minutes: 5
    description: "Traffic spike scenario (viral feature, announcement)"
  
  sustained:
    users: 300
    spawn_rate: 30
    duration_minutes: 30
    description: "Sustained load for memory leak detection"

success_criteria:
  - metric: "response_time_p95"
    target: "< 500ms"
    weight: 30
  
  - metric: "throughput"
    target: "> 1000 req/sec"
    weight: 30
  
  - metric: "error_rate"
    target: "< 0.1%"
    weight: 25
  
  - metric: "resource_efficiency"
    target: "< 80% utilization"
    weight: 15
```

#### Task 1.4: Create Results Analysis Script

Create `scripts/perf/analyze-performance.py`:

```python
#!/usr/bin/env python3
"""
Performance test results analyzer
Generates comparison reports and identifies regressions
"""
import json
import csv
import sys
from pathlib import Path
from datetime import datetime
import statistics

def load_locust_results(csv_file):
    """Parse Locust CSV results"""
    results = {}
    with open(csv_file, 'r') as f:
        reader = csv.DictReader(f)
        for row in reader:
            endpoint = row['Name']
            results[endpoint] = {
                'requests': int(row['# requests']),
                'failures': int(row['# failures']),
                'avg_response': float(row['Average Response Time']),
                'min_response': float(row['Min Response Time']),
                'max_response': float(row['Max Response Time']),
                'p50': float(row.get('Median Response Time', 0)),
                'p95': float(row.get('95%', 0)),
                'p99': float(row.get('99%', 0)),
            }
    return results

def generate_report(results, baseline, scenario):
    """Generate performance comparison report"""
    report = {
        'timestamp': datetime.now().isoformat(),
        'scenario': scenario,
        'summary': {},
        'details': {}
    }
    
    # Calculate summary metrics
    total_requests = sum(r['requests'] for r in results.values())
    total_failures = sum(r['failures'] for r in results.values())
    error_rate = (total_failures / total_requests * 100) if total_requests > 0 else 0
    
    report['summary'] = {
        'total_requests': total_requests,
        'total_failures': total_failures,
        'error_rate_percent': error_rate,
        'avg_response_time_ms': statistics.mean(r['avg_response'] for r in results.values()),
    }
    
    # Per-endpoint details
    for endpoint, metrics in results.items():
        baseline_metrics = baseline.get(endpoint, {})
        report['details'][endpoint] = {
            'current': metrics,
            'baseline': baseline_metrics,
            'regression': calculate_regression(metrics, baseline_metrics)
        }
    
    return report

def calculate_regression(current, baseline):
    """Calculate performance regression from baseline"""
    if not baseline:
        return {'status': 'baseline', 'change_percent': 0}
    
    baseline_avg = baseline.get('avg_response', 0)
    current_avg = current.get('avg_response', 0)
    
    if baseline_avg == 0:
        return {'status': 'unknown', 'change_percent': 0}
    
    change_percent = ((current_avg - baseline_avg) / baseline_avg) * 100
    
    if change_percent > 10:
        status = 'regression'
    elif change_percent < -10:
        status = 'improvement'
    else:
        status = 'stable'
    
    return {'status': status, 'change_percent': change_percent}

if __name__ == '__main__':
    if len(sys.argv) < 2:
        print("Usage: analyze-performance.py <results.csv> [baseline.json]")
        sys.exit(1)
    
    results_file = Path(sys.argv[1])
    baseline_file = Path(sys.argv[2]) if len(sys.argv) > 2 else None
    
    results = load_locust_results(results_file)
    baseline = {}
    
    if baseline_file and baseline_file.exists():
        with open(baseline_file) as f:
            baseline_data = json.load(f)
            baseline = baseline_data.get('details', {})
    
    scenario = results_file.stem.split('-')[1] if '-' in results_file.stem else 'unknown'
    report = generate_report(results, baseline, scenario)
    
    # Output report
    print(json.dumps(report, indent=2))
    
    # Save report
    output_file = results_file.parent / f"analysis-{datetime.now().strftime('%Y%m%d-%H%M%S')}.json"
    with open(output_file, 'w') as f:
        json.dump(report, f, indent=2)
    
    print(f"\nReport saved to: {output_file}")
```

### Phase 5 Week 1 Deliverables Checklist

- [x] Create Locust load testing framework
- [x] Create test orchestration shell script  
- [x] Define 5 test scenarios (light, medium, heavy, spike, sustained)
- [x] Create performance baselines configuration
- [x] Create results analysis Python script
- [ ] Deploy to Docker Compose environment
- [ ] Run baseline tests and collect metrics
- [ ] Create Grafana performance dashboard
- [ ] Document performance thresholds
- [ ] Generate baseline report

### Success Criteria

| Criterion | Status | Target |
|-----------|--------|--------|
| Load testing framework deployed | ⏳ | Light scenario: < 500ms p95 |
| Baseline metrics collected | ⏳ | 5 scenarios tested |
| Performance dashboard created | ⏳ | Real-time visualization |
| Regression detection working | ⏳ | 10%+ regression alerts |
| All tests pass without errors | ⏳ | Error rate < 0.1% |

---

## Next Steps (Post Week 1)

1. **Week 2:** Implement Chaos Engineering Program (5.2)
2. **Week 3:** Set up Disaster Recovery Testing (5.3)
3. **Week 4:** Performance tuning based on results

