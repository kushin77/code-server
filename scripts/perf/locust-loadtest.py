#!/usr/bin/env python3
"""
Locust load testing orchestration for code-server infrastructure
Supports 5 test scenarios: light, medium, heavy, spike, sustained

Usage:
  locust -f scripts/perf/locust-loadtest.py -u 200 -r 20 -t 600s --headless --csv=results
  locust -f scripts/perf/locust-loadtest.py --scenario=heavy --headless

Environment variables:
  API_URL: Base URL for API (default: http://localhost:3100)
  SCENARIO: Test scenario (light|medium|heavy|spike|sustained) (default: medium)
  TEST_DURATION: Duration in seconds (overrides scenario default)
"""

import os
import sys
from locust import HttpUser, TaskSet, task, between, events
import logging
from datetime import datetime

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

# Configuration
API_BASE_URL = os.getenv("API_URL", "http://localhost:3100")
SCENARIO = os.getenv("SCENARIO", "medium")

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

class CodeServerUserBehavior(TaskSet):
    """Define user behavior patterns for load testing"""
    
    @task(4)
    def create_activity(self):
        """Activity creation - 40% of traffic"""
        try:
            self.client.post(
                "/api/v1/activities",
                json={"description": "Test activity", "type": "manual"},
                timeout=5,
                name="/api/v1/activities [POST]"
            )
        except Exception as e:
            logger.warning(f"Activity creation failed: {e}")
    
    @task(3)
    def list_activities(self):
        """Activity listing - 30% of traffic"""
        try:
            self.client.get(
                "/api/v1/activities?limit=50",
                timeout=5,
                name="/api/v1/activities [GET]"
            )
        except Exception as e:
            logger.warning(f"Activity listing failed: {e}")
    
    @task(2)
    def get_reputation(self):
        """Reputation queries - 20% of traffic"""
        try:
            self.client.get(
                "/api/v1/reputation/score",
                timeout=5,
                name="/api/v1/reputation/score [GET]"
            )
        except Exception as e:
            logger.warning(f"Reputation query failed: {e}")
    
    @task(1)
    def check_execution(self):
        """Execution status - 10% of traffic"""
        try:
            self.client.get(
                "/api/v1/executions/status",
                timeout=5,
                name="/api/v1/executions/status [GET]"
            )
        except Exception as e:
            logger.warning(f"Execution status check failed: {e}")
    
    def on_start(self):
        """Execute on user start"""
        logger.debug(f"User started: {self.client.base_url}")

class CodeServerUser(HttpUser):
    """Load testing user profile"""
    tasks = [CodeServerUserBehavior]
    wait_time = between(1, 3)
    host = API_BASE_URL

@events.test_start.add_listener
def on_test_start(environment, **kwargs):
    """Execute on test start"""
    logger.info("=" * 70)
    logger.info("PERFORMANCE TEST STARTED")
    logger.info("=" * 70)
    scenario_config = SCENARIOS.get(SCENARIO, SCENARIOS["medium"])
    logger.info(f"Scenario: {SCENARIO}")
    logger.info(f"Description: {scenario_config['description']}")
    logger.info(f"Target Users: {scenario_config['users']}")
    logger.info(f"Spawn Rate: {scenario_config['spawn_rate']} users/sec")
    logger.info(f"Duration: {scenario_config['duration_sec']} seconds")
    logger.info(f"API Base URL: {API_BASE_URL}")
    logger.info("=" * 70)

@events.test_stop.add_listener
def on_test_stop(environment, **kwargs):
    """Generate performance report on test completion"""
    logger.info("=" * 70)
    logger.info("PERFORMANCE TEST RESULTS")
    logger.info("=" * 70)
    
    total_requests = 0
    total_failures = 0
    
    for req in environment.stats.entries.values():
        total_requests += req.num_requests
        total_failures += req.num_failures
        
        if req.num_requests > 0:
            error_rate = (req.num_failures / req.num_requests * 100)
            logger.info(f"\n{req.name}:")
            logger.info(f"  Requests: {req.num_requests:,}")
            logger.info(f"  Failures: {req.num_failures} ({error_rate:.2f}%)")
            logger.info(f"  Avg Response: {req.avg_response_time:.0f}ms")
            logger.info(f"  Min Response: {req.min_response_time:.0f}ms")
            logger.info(f"  Max Response: {req.max_response_time:.0f}ms")
            logger.info(f"  P50 (Median): {req.get_response_time_percentile(0.50):.0f}ms")
            logger.info(f"  P95: {req.get_response_time_percentile(0.95):.0f}ms")
            logger.info(f"  P99: {req.get_response_time_percentile(0.99):.0f}ms")
    
    logger.info("\n" + "=" * 70)
    logger.info("OVERALL METRICS")
    logger.info("=" * 70)
    logger.info(f"Total Requests: {total_requests:,}")
    logger.info(f"Total Failures: {total_failures:,}")
    if total_requests > 0:
        error_rate = (total_failures / total_requests * 100)
        logger.info(f"Overall Error Rate: {error_rate:.2f}%")
    logger.info(f"Test Completed: {datetime.now().isoformat()}")
    logger.info("=" * 70)

if __name__ == "__main__":
    logger.info(f"Locust load testing initialized")
    logger.info(f"Scenario: {SCENARIO}")
    logger.info(f"API URL: {API_BASE_URL}")
    scenario_config = SCENARIOS.get(SCENARIO)
    if scenario_config:
        logger.info(f"Configuration: {scenario_config}")
