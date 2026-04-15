#!/usr/bin/env python3
"""
Locust load testing scenarios for code-server production
Phase 6c: Load Testing & Capacity Planning
"""

from locust import HttpUser, task, between, events
import json
import random
import logging
from datetime import datetime

# Logging setup
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


class CodeServerUser(HttpUser):
    """Realistic code-server user behavior model"""
    
    wait_time = between(1, 3)  # Wait 1-3 seconds between tasks
    
    def on_start(self):
        """Initialize user session"""
        self.token = None
        self.files = []
        self.workspace_id = f"workspace_{random.randint(1000, 9999)}"
        logger.info(f"User {self.client_pool} started with workspace {self.workspace_id}")
    
    @task(30)  # 30% of requests
    def oauth_login(self):
        """Simulate OAuth login flow"""
        with self.client.get("/oauth/sign_in", catch_response=True) as response:
            if response.status_code == 200:
                response.success()
            else:
                response.failure(f"OAuth redirect failed: {response.status_code}")
    
    @task(20)  # 20% of requests
    def create_file(self):
        """Create new file in workspace"""
        filename = f"file_{random.randint(1, 100000)}.txt"
        payload = {
            "workspace_id": self.workspace_id,
            "filename": filename,
            "content": f"Generated file content at {datetime.now()}"
        }
        
        with self.client.post(
            "/api/v1/files",
            json=payload,
            catch_response=True
        ) as response:
            if response.status_code in [200, 201]:
                response.success()
                self.files.append(filename)
            else:
                response.failure(f"File creation failed: {response.status_code}")
    
    @task(25)  # 25% of requests
    def read_file(self):
        """Read existing file from workspace"""
        if self.files:
            filename = random.choice(self.files)
        else:
            filename = f"file_{random.randint(1, 100000)}.txt"
        
        with self.client.get(
            f"/api/v1/files/{filename}",
            catch_response=True
        ) as response:
            if response.status_code == 200:
                response.success()
            else:
                response.failure(f"File read failed: {response.status_code}")
    
    @task(15)  # 15% of requests
    def update_file(self):
        """Update existing file content"""
        if self.files:
            filename = random.choice(self.files)
            payload = {
                "content": f"Updated content at {datetime.now()}"
            }
            
            with self.client.put(
                f"/api/v1/files/{filename}",
                json=payload,
                catch_response=True
            ) as response:
                if response.status_code == 200:
                    response.success()
                else:
                    response.failure(f"File update failed: {response.status_code}")
    
    @task(5)  # 5% of requests
    def search_files(self):
        """Search for files in workspace"""
        search_term = f"file_{random.randint(1, 100)}"
        
        with self.client.get(
            f"/api/v1/search?q={search_term}",
            catch_response=True
        ) as response:
            if response.status_code == 200:
                response.success()
            else:
                response.failure(f"Search failed: {response.status_code}")
    
    @task(5)  # 5% of requests
    def list_workspace(self):
        """List files in workspace"""
        with self.client.get(
            f"/api/v1/workspaces/{self.workspace_id}/files",
            catch_response=True
        ) as response:
            if response.status_code == 200:
                response.success()
            else:
                response.failure(f"List workspace failed: {response.status_code}")


@events.test_start.add_listener
def on_test_start(environment, **kwargs):
    """Called when test starts"""
    logger.info("=" * 60)
    logger.info("LOAD TEST STARTED")
    logger.info(f"Target: {environment.host}")
    logger.info(f"Users: {len(environment.runner.clients)}")
    logger.info("=" * 60)


@events.test_stop.add_listener
def on_test_stop(environment, **kwargs):
    """Called when test stops"""
    logger.info("=" * 60)
    logger.info("LOAD TEST COMPLETED")
    logger.info("Summary:")
    logger.info(f"  Total requests: {environment.stats.total.num_requests}")
    logger.info(f"  Total failures: {environment.stats.total.num_failures}")
    logger.info(f"  Average latency: {environment.stats.total.avg_response_time}ms")
    logger.info(f"  p99 latency: {environment.stats.total.response_times_percentile(0.99)}ms")
    logger.info("=" * 60)


@events.request.add_listener
def on_request(request_type, name, response_time, response_length, response,
               context, exception, **kwargs):
    """Log each request for monitoring"""
    if exception:
        logger.warning(f"Failed: {request_type} {name} ({exception})")
    elif response_time > 1000:
        logger.warning(f"Slow: {request_type} {name} ({response_time}ms)")
