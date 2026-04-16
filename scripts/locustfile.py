"""
Phase 15: Code-Server Load Testing with Locust

Scenarios:
  - Light load: 100 users, 10 req/s
  - Normal load: 300 users, 30 req/s
  - Heavy load: 1000 users, 100 req/s
"""

from locust import HttpUser, task, between, TaskSet, events
import json
from datetime import datetime


class CodeServerLoadTest(TaskSet):
    """Load testing tasks for Code-Server endpoints"""

    @task(3)
    def index(self):
        """Browse the main page (weight: 3)"""
        self.client.get("/", timeout=10)

    @task(2)
    def workspace(self):
        """Access workspace (weight: 2)"""
        self.client.get("/workspace", timeout=10)

    @task(1)
    def api_health(self):
        """Check health endpoint (weight: 1)"""
        self.client.get("/api/health", timeout=10)

    @task(1)
    def api_version(self):
        """Get version info (weight: 1)"""
        self.client.get("/api/v1/version", timeout=10)

    @task(2)
    def api_files(self):
        """List files (simulated API call)"""
        self.client.get("/api/v1/files", timeout=10)

    def on_start(self):
        """Called when a user starts"""
        print(f"[{datetime.now()}] User started from {self.client.base_url}")

    def on_stop(self):
        """Called when a user stops"""
        print(f"[{datetime.now()}] User stopped from {self.client.base_url}")


class CodeServerUser(HttpUser):
    """Simulated Code-Server user"""
    
    tasks = [CodeServerLoadTest]
    wait_time = between(1, 3)  # Wait 1-3 seconds between requests

    def on_start(self):
        """Login or setup"""
        print(f"[{datetime.now()}] New CodeServerUser spawned")

    def on_stop(self):
        """Cleanup"""
        print(f"[{datetime.now()}] CodeServerUser stopped")


# Event handlers for monitoring
@events.test_start.add_listener
def on_test_start(environment, **kwargs):
    print(f"\n{'='*60}")
    print(f"[{datetime.now()}] Phase 15 Load Test STARTED")
    print(f"Target: {environment.host}")
    print(f"Scenario: Phase 15 Advanced Performance Testing")
    print(f"{'='*60}\n")


@events.test_stop.add_listener
def on_test_stop(environment, **kwargs):
    print(f"\n{'='*60}")
    print(f"[{datetime.now()}] Phase 15 Load Test COMPLETE")
    print(f"Total Users: {len(environment.runner.locusts)}")
    print(f"Total Requests: {environment.stats.total.num_requests}")
    print(f"Total Failures: {environment.stats.total.num_failures}")
    print(f"Average Response Time: {environment.stats.total.avg_response_time:.0f}ms")
    print(f"P95 Response Time: {environment.stats.total.get_response_time_percentile(0.95):.0f}ms")
    print(f"P99 Response Time: {environment.stats.total.get_response_time_percentile(0.99):.0f}ms")
    print(f"{'='*60}\n")


@events.request.add_listener
def on_request(request_type, name, response_time, response_length, started_at, **kwargs):
    """Log each request"""
    if response_time > 200:  # Log slow requests (>200ms)
        print(f"[SLOW] {request_type} {name}: {response_time:.0f}ms")
