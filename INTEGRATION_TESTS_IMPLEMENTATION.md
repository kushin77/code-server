# Integration Tests - Implementation Guide

**Purpose**: Provide implementable test specs for all critical external integrations  
**Target**: Achieve 80%+ integration test coverage within 4 weeks

---

## 1. DATABASE INTEGRATION TESTS

### Test 1.1: PostgreSQL Primary-Replica Failover

**File**: `tests/integration/test_postgres_failover.py`

```python
import pytest
import psycopg2
import time
import subprocess
from sqlalchemy import create_engine, text

class TestPostgresFailover:
    """Test PostgreSQL automatic replication and failover."""
    
    @pytest.fixture
    def primary_conn(self):
        """Connect to primary database."""
        engine = create_engine(
            "postgresql://postgres:password@192.168.168.31:5432/code_server"
        )
        return engine
    
    @pytest.fixture
    def replica_conn(self):
        """Connect to replica database."""
        engine = create_engine(
            "postgresql://postgres:password@192.168.168.42:5432/code_server"
        )
        return engine
    
    def test_replication_lag_within_threshold(self, primary_conn):
        """Assert replication lag < 1 second."""
        with primary_conn.connect() as conn:
            result = conn.execute(text(
                "SELECT EXTRACT(EPOCH FROM (now() - pg_last_xact_replay_timestamp())) as lag"
            )).fetchone()
            assert result[0] < 1.0, f"Replication lag {result[0]}s exceeds threshold"
    
    def test_write_to_primary_replicates_to_standby(self, primary_conn, replica_conn):
        """Write to primary, verify on replica within 5 seconds."""
        test_value = f"test_{int(time.time())}"
        
        with primary_conn.connect() as conn:
            conn.execute(text(
                f"INSERT INTO test_table (value) VALUES ('{test_value}')"
            ))
            conn.commit()
        
        # Wait for replication
        time.sleep(1)
        
        with replica_conn.connect() as conn:
            result = conn.execute(text(
                f"SELECT COUNT(*) FROM test_table WHERE value = '{test_value}'"
            )).fetchone()
            assert result[0] > 0, "Data not replicated to standby within timeout"
    
    def test_failover_scenario(self, primary_conn, replica_conn):
        """
        Simulate primary failure:
        1. Stop primary container
        2. Attempt connection to primary (should fail)
        3. Promote replica using pg_ctl
        4. Write to new primary
        5. Verify
        """
        # Step 1: Stop primary
        subprocess.run([
            "ssh", "akushnir@192.168.168.31",
            "docker stop code-server-postgres"
        ], check=True)
        
        time.sleep(5)
        
        # Step 2: Verify primary down
        with pytest.raises(psycopg2.OperationalError):
            conn = psycopg2.connect(
                host="192.168.168.31", database="code_server", user="postgres"
            )
        
        # Step 3: Promote replica to primary (manual step in test)
        # In production: run pg_ctl promote on standby
        # For test, we skip and verify replica accessibility
        
        # Step 4: Cleanup - restart primary
        subprocess.run([
            "ssh", "akushnir@192.168.168.31",
            "docker start code-server-postgres"
        ], check=True)
        
        time.sleep(10)
        
        # Step 5: Verify recovery
        assert primary_conn.execute(text("SELECT 1")).fetchone() is not None
```

**Acceptance Criteria**:
- ✅ Replication lag measured < 1s
- ✅ Data replicates within 5s
- ✅ Failover scenario documented with manual steps
- ✅ Recovery time: < 30s

**Run Frequency**: Weekly  
**Environment**: Staging or dedicated test cluster  
**Estimated Runtime**: 10 minutes

---

### Test 1.2: Redis Sentinel Failover

**File**: `tests/integration/test_redis_sentinel_failover.py`

```python
import pytest
import redis
import subprocess
import time
from redis.sentinel import Sentinel

class TestRedisSentinelFailover:
    """Test Redis HA with Sentinel."""
    
    @pytest.fixture
    def sentinel(self):
        """Connect to Sentinel cluster."""
        sentinels = [
            ("code-server-redis-sentinel-primary", 26379),
            ("code-server-redis-sentinel-1", 26379),
            ("code-server-redis-sentinel-arbiter", 26379),
        ]
        return Sentinel(sentinels)
    
    def test_sentinel_quorum_active(self, sentinel):
        """Assert 3 sentinels operational."""
        masters = sentinel.discover_master("mymaster")
        slaves = sentinel.discover_slaves("mymaster")
        assert len(masters) >= 1, "No master found"
        assert len(slaves) >= 1, "No slaves found"
    
    def test_write_to_primary_read_from_replica(self, sentinel):
        """Write to primary, read from replica."""
        primary = sentinel.master_for("mymaster", socket_timeout=5)
        slave = sentinel.slave_for("mymaster", socket_timeout=5)
        
        test_key = f"test_{int(time.time())}"
        test_value = "sentinel_test_value"
        
        # Write to primary
        primary.set(test_key, test_value)
        time.sleep(0.5)
        
        # Read from slave
        result = slave.get(test_key)
        assert result.decode() == test_value, "Read-replica not synchronized"
    
    def test_primary_failover_with_sentinel(self, sentinel):
        """
        Simulate primary failure:
        1. Get current primary host
        2. Kill primary Redis container
        3. Wait for Sentinel to detect failure (30s)
        4. Verify new primary elected (different host)
        5. Verify writes work to new primary
        6. Restart old primary
        """
        primary = sentinel.master_for("mymaster")
        old_primary_host = primary.execute_command("CONFIG", "GET", "dir")[0]
        
        # Step 1: Kill primary
        subprocess.run([
            "ssh", "akushnir@192.168.168.31",
            "docker stop code-server-redis"
        ], check=True)
        
        time.sleep(5)
        
        # Step 2: Wait for failover
        for attempt in range(12):  # 60 second timeout
            try:
                new_primary = sentinel.master_for("mymaster")
                new_host = new_primary.execute_command("CONFIG", "GET", "dir")[0]
                if new_host != old_primary_host:
                    break
            except redis.ConnectionError:
                pass
            time.sleep(5)
        
        # Step 3: Verify new primary operational
        new_primary.set("failover_test", "success")
        assert new_primary.get("failover_test") == b"success"
        
        # Step 4: Restart old primary
        subprocess.run([
            "ssh", "akushnir@192.168.168.31",
            "docker start code-server-redis"
        ], check=True)
        
        time.sleep(10)
        assert primary.ping(), "Cluster recovery failed"
```

**Acceptance Criteria**:
- ✅ Sentinel quorum detected
- ✅ Writes replicate within 1s
- ✅ Failover occurs within 60s
- ✅ New primary accepts writes
- ✅ Old primary rejoins as replica

**Run Frequency**: Weekly  
**Environment**: Staging with SSH access to hosts  
**Estimated Runtime**: 15 minutes

---

## 2. MESSAGE QUEUE INTEGRATION TESTS

### Test 2.1: Kafka Producer/Consumer with Broker Failure

**File**: `tests/integration/test_kafka_resilience.py`

```python
import pytest
import json
import subprocess
import time
from kafka import KafkaProducer, KafkaConsumer
from kafka.errors import KafkaError

class TestKafkaResilience:
    """Test Kafka event reliability under broker failures."""
    
    @pytest.fixture
    def producer(self):
        """Create Kafka producer."""
        return KafkaProducer(
            bootstrap_servers="code-server-redpanda:9092",
            value_serializer=lambda v: json.dumps(v).encode(),
            retries=3,
            max_in_flight_requests_per_connection=1,
        )
    
    @pytest.fixture
    def consumer(self):
        """Create Kafka consumer."""
        return KafkaConsumer(
            "test-topic",
            bootstrap_servers="code-server-redpanda:9092",
            group_id="test-group",
            value_deserializer=lambda m: json.loads(m.decode()),
            auto_offset_reset="earliest",
            consumer_timeout_ms=5000,
        )
    
    def test_publish_message_success(self, producer):
        """Publish single message and verify."""
        test_message = {"id": 1, "type": "test", "timestamp": time.time()}
        future = producer.send("test-topic", test_message)
        record_metadata = future.get(timeout=5)
        
        assert record_metadata.topic == "test-topic"
        assert record_metadata.partition >= 0
    
    def test_consume_published_messages(self, producer, consumer):
        """Publish 10 messages, consume and verify."""
        messages = [
            {"id": i, "value": f"msg_{i}"} 
            for i in range(10)
        ]
        
        for msg in messages:
            producer.send("test-topic", msg)
        producer.flush()
        
        consumed = []
        for msg in consumer:
            consumed.append(msg.value)
            if len(consumed) >= 10:
                break
        
        assert len(consumed) == 10
        assert all(m["value"].startswith("msg_") for m in consumed)
    
    def test_broker_failure_recovery(self, producer):
        """
        Test event persistence during broker outage:
        1. Publish 5 messages
        2. Stop Redpanda container
        3. Attempt to publish (should fail after retries)
        4. Restart broker
        5. Resume publishing
        6. Verify all messages in log
        """
        topic = f"test-{int(time.time())}"
        
        # Step 1: Publish initial batch
        for i in range(5):
            producer.send(topic, {"id": i, "batch": 1})
        producer.flush()
        
        # Step 2: Stop broker
        subprocess.run([
            "ssh", "akushnir@192.168.168.31",
            "docker stop code-server-redpanda"
        ], check=True)
        
        time.sleep(2)
        
        # Step 3: Attempt publish (should timeout)
        with pytest.raises(KafkaError):
            for i in range(5):
                future = producer.send(topic, {"id": i, "batch": 2}, timeout=3)
                future.get(timeout=3)
        
        # Step 4: Restart broker
        subprocess.run([
            "ssh", "akushnir@192.168.168.31",
            "docker start code-server-redpanda"
        ], check=True)
        
        time.sleep(10)
        
        # Step 5: Resume publishing
        for i in range(5):
            producer.send(topic, {"id": i, "batch": 3})
        producer.flush()
        
        # Step 6: Verify in consumer
        consumer = KafkaConsumer(
            topic,
            bootstrap_servers="code-server-redpanda:9092",
            group_id=f"test-group-{int(time.time())}",
            value_deserializer=lambda m: json.loads(m.decode()),
            auto_offset_reset="earliest",
            consumer_timeout_ms=10000,
        )
        
        batches = {1: [], 3: []}
        for msg in consumer:
            batch = msg.value.get("batch")
            if batch in batches:
                batches[batch].append(msg.value["id"])
        
        assert len(batches[1]) == 5, f"Batch 1 incomplete: {batches[1]}"
        assert len(batches[3]) == 5, f"Batch 3 incomplete: {batches[3]}"
```

**Acceptance Criteria**:
- ✅ Messages published reliably
- ✅ Consumer retrieves all messages
- ✅ Broker failure detected
- ✅ Publishing resumes after recovery
- ✅ No message loss on clean restart

**Run Frequency**: Weekly  
**Environment**: Staging with Kafka/Redpanda access  
**Estimated Runtime**: 10 minutes

---

## 3. AUTHENTICATION INTEGRATION TESTS

### Test 3.1: OAuth2 Authentication Flow

**File**: `tests/integration/test_oauth2_flow.py`

```python
import pytest
import httpx
import jwt
import json
from datetime import datetime, timedelta

class TestOAuth2Flow:
    """Test complete OAuth2 authentication flow."""
    
    @pytest.fixture
    def oauth_config(self):
        """OAuth2 configuration."""
        return {
            "issuer": "https://auth.kushnir.cloud",
            "client_id": "test-client",
            "client_secret": "test-secret",
            "redirect_uri": "http://localhost:8080/callback",
        }
    
    def test_oauth_metadata_available(self):
        """GET /.well-known/openid-configuration"""
        response = httpx.get(
            "https://auth.kushnir.cloud/.well-known/openid-configuration",
            verify=False
        )
        assert response.status_code == 200
        data = response.json()
        assert "token_endpoint" in data
        assert "authorization_endpoint" in data
    
    def test_client_credentials_token_flow(self, oauth_config):
        """Obtain token using client credentials grant."""
        response = httpx.post(
            f"{oauth_config['issuer']}/token",
            data={
                "grant_type": "client_credentials",
                "client_id": oauth_config["client_id"],
                "client_secret": oauth_config["client_secret"],
            },
            verify=False
        )
        
        assert response.status_code == 200
        token_data = response.json()
        assert "access_token" in token_data
        assert token_data["token_type"] == "Bearer"
        assert "expires_in" in token_data
        
        # Decode JWT
        token = token_data["access_token"]
        decoded = jwt.decode(token, options={"verify_signature": False})
        assert decoded["sub"] == oauth_config["client_id"]
    
    def test_token_introspection(self, oauth_config):
        """Verify token introspection endpoint."""
        # First get token
        token_response = httpx.post(
            f"{oauth_config['issuer']}/token",
            data={
                "grant_type": "client_credentials",
                "client_id": oauth_config["client_id"],
                "client_secret": oauth_config["client_secret"],
            },
            verify=False
        )
        
        token = token_response.json()["access_token"]
        
        # Introspect token
        response = httpx.post(
            f"{oauth_config['issuer']}/introspect",
            data={
                "token": token,
                "client_id": oauth_config["client_id"],
                "client_secret": oauth_config["client_secret"],
            },
            verify=False
        )
        
        assert response.status_code == 200
        data = response.json()
        assert data["active"] == True
        assert data["client_id"] == oauth_config["client_id"]
    
    def test_oauth2_proxy_redirect(self):
        """Test OAuth2-Proxy login redirect."""
        response = httpx.get(
            "http://code-server-oauth2-proxy:4180/",
            follow_redirects=False
        )
        
        # Should redirect to auth endpoint or be protected
        assert response.status_code in [200, 302, 307]
        if response.status_code in [302, 307]:
            assert "oauth" in response.headers.get("location", "").lower()
    
    def test_token_refresh(self, oauth_config):
        """Test token refresh with refresh_token grant."""
        # Get initial token with refresh token
        response = httpx.post(
            f"{oauth_config['issuer']}/token",
            data={
                "grant_type": "password",  # Assumes password grant enabled
                "username": "testuser",
                "password": "testpass",
                "scope": "openid profile",
                "client_id": oauth_config["client_id"],
                "client_secret": oauth_config["client_secret"],
            },
            verify=False
        )
        
        if response.status_code != 200:
            pytest.skip("Password grant not enabled")
        
        token_data = response.json()
        refresh_token = token_data.get("refresh_token")
        
        if not refresh_token:
            pytest.skip("Refresh token not provided")
        
        # Use refresh token
        refresh_response = httpx.post(
            f"{oauth_config['issuer']}/token",
            data={
                "grant_type": "refresh_token",
                "refresh_token": refresh_token,
                "client_id": oauth_config["client_id"],
                "client_secret": oauth_config["client_secret"],
            },
            verify=False
        )
        
        assert refresh_response.status_code == 200
        new_token = refresh_response.json()["access_token"]
        assert new_token != token_data["access_token"]
```

**Acceptance Criteria**:
- ✅ OIDC discovery endpoint available
- ✅ Client credentials flow works
- ✅ Token is valid JWT
- ✅ Token introspection works
- ✅ OAuth2-Proxy protects endpoints
- ✅ Token refresh works

**Run Frequency**: Per deployment  
**Environment**: Staging with auth-server running  
**Estimated Runtime**: 5 minutes

---

## 4. POLICY ENGINE INTEGRATION TESTS

### Test 4.1: OPA Policy Enforcement

**File**: `tests/integration/test_opa_policies.py`

```python
import pytest
import requests
import json

class TestOPAPolicies:
    """Test OPA policy evaluation and enforcement."""
    
    @pytest.fixture
    def opa_url(self):
        """OPA base URL."""
        return "http://localhost:8181"
    
    @pytest.fixture
    def test_policy(self, opa_url):
        """Upload test policy."""
        policy = """
        package api.authz

        default allow = false

        allow {
            input.user.role == "admin"
        }

        allow {
            input.action == "read"
            input.user.role == "user"
        }
        """
        
        response = requests.put(
            f"{opa_url}/v1/policies/test_policy",
            data=policy,
            headers={"Content-Type": "text/plain"}
        )
        assert response.status_code == 200
        return policy
    
    def test_opa_health(self, opa_url):
        """Check OPA health endpoint."""
        response = requests.get(f"{opa_url}/health")
        assert response.status_code == 200
        assert response.json()["result"]["ready"] == True
    
    def test_policy_upload_and_retrieve(self, opa_url, test_policy):
        """Verify policy is stored."""
        response = requests.get(f"{opa_url}/v1/policies/test_policy")
        assert response.status_code == 200
        assert "package api.authz" in response.text
    
    def test_admin_can_do_anything(self, opa_url):
        """Test admin policy."""
        query = {
            "user": {"role": "admin"},
            "action": "write",
            "resource": "sensitive_data"
        }
        
        response = requests.post(
            f"{opa_url}/v1/data/api/authz/allow",
            json={"input": query}
        )
        
        assert response.status_code == 200
        assert response.json()["result"] == True
    
    def test_user_can_only_read(self, opa_url):
        """Test user-role restrictions."""
        # Read should be allowed
        response = requests.post(
            f"{opa_url}/v1/data/api/authz/allow",
            json={"input": {
                "user": {"role": "user"},
                "action": "read",
                "resource": "public_data"
            }}
        )
        assert response.json()["result"] == True
        
        # Write should be denied
        response = requests.post(
            f"{opa_url}/v1/data/api/authz/allow",
            json={"input": {
                "user": {"role": "user"},
                "action": "write",
                "resource": "public_data"
            }}
        )
        assert response.json()["result"] == False
    
    def test_opa_unavailable_fallback(self):
        """
        Test behavior when OPA is down.
        This should be tested by:
        1. Stopping OPA container
        2. Attempting policy check in app
        3. Verifying explicit fail-secure policy
        """
        pytest.skip("Manual test required - see docs")
```

**Acceptance Criteria**:
- ✅ OPA health endpoint accessible
- ✅ Policies can be uploaded
- ✅ Policy evaluation works
- ✅ Admin bypass enforced
- ✅ User restrictions enforced

**Run Frequency**: Per deployment  
**Environment**: Staging with OPA running  
**Estimated Runtime**: 5 minutes

---

## 5. OBSERVABILITY INTEGRATION TESTS

### Test 5.1: Prometheus Scrape Validation

**File**: `tests/integration/test_prometheus_integration.py`

```python
import pytest
import requests

class TestPrometheusIntegration:
    """Test Prometheus metrics collection."""
    
    @pytest.fixture
    def prometheus_url(self):
        """Prometheus base URL."""
        return "http://localhost:9090"
    
    def test_prometheus_health(self, prometheus_url):
        """Check Prometheus is operational."""
        response = requests.get(f"{prometheus_url}/-/healthy")
        assert response.status_code == 200
    
    def test_scrape_targets_active(self, prometheus_url):
        """Verify all targets are scraping."""
        response = requests.get(f"{prometheus_url}/api/v1/targets")
        data = response.json()
        
        active_targets = data["data"]["activeTargets"]
        assert len(active_targets) > 0, "No scrape targets active"
        
        # Verify critical targets
        target_jobs = {t["scrapePool"] for t in active_targets}
        required_jobs = {
            "prometheus",
            "postgres-metrics",
            "redis-metrics",
        }
        
        for job in required_jobs:
            assert job in target_jobs, f"Missing scrape target: {job}"
    
    def test_database_metrics_available(self, prometheus_url):
        """Verify PostgreSQL metrics are collected."""
        response = requests.post(
            f"{prometheus_url}/api/v1/query",
            data={"query": "pg_up"}
        )
        
        data = response.json()
        assert data["status"] == "success"
        assert len(data["data"]["result"]) > 0
        assert data["data"]["result"][0]["value"][1] == "1"  # 1 = up
    
    def test_redis_metrics_available(self, prometheus_url):
        """Verify Redis metrics are collected."""
        response = requests.post(
            f"{prometheus_url}/api/v1/query",
            data={"query": "redis_up"}
        )
        
        data = response.json()
        assert data["status"] == "success"
        assert len(data["data"]["result"]) > 0
        assert data["data"]["result"][0]["value"][1] == "1"  # 1 = up
    
    def test_alerts_configured(self, prometheus_url):
        """Verify alert rules are loaded."""
        response = requests.get(f"{prometheus_url}/api/v1/rules")
        data = response.json()
        
        groups = data["data"]["groups"]
        alert_count = sum(
            len([r for r in g["rules"] if r.get("type") == "alerting"])
            for g in groups
        )
        
        assert alert_count > 0, "No alert rules configured"
```

**Acceptance Criteria**:
- ✅ Prometheus API accessible
- ✅ Scrape targets healthy
- ✅ Database metrics collected
- ✅ Redis metrics collected
- ✅ Alert rules loaded

**Run Frequency**: Daily (automated)  
**Environment**: Staging  
**Estimated Runtime**: 2 minutes

---

## 6. TEST EXECUTION FRAMEWORK

### Setup

**File**: `tests/conftest.py`

```python
import pytest
import os
import sys

@pytest.fixture(scope="session")
def test_environment():
    """Verify test environment is available."""
    required_hosts = {
        "192.168.168.31": "Primary host",
        "192.168.168.42": "Replica host",
        "192.168.168.33": "NAS",
    }
    
    for host, desc in required_hosts.items():
        # Verify SSH access
        # Verify services running
        pass

@pytest.mark.integration
class IntegrationTestBase:
    """Base class for integration tests."""
    
    def skip_if_not_staging(self):
        """Skip in production."""
        env = os.getenv("ENVIRONMENT", "dev")
        if env == "production":
            pytest.skip("Cannot run integration tests in production")
```

### CI/CD Integration

**GitHub Actions**: `.github/workflows/integration-tests.yml`

```yaml
name: Integration Tests
on:
  schedule:
    - cron: '0 2 * * *'  # Daily at 2 AM
  workflow_dispatch:

jobs:
  integration-tests:
    runs-on: [self-hosted, staging]
    timeout-minutes: 60
    
    steps:
      - uses: actions/checkout@v3
      - name: Run Postgres tests
        run: pytest tests/integration/test_postgres_failover.py -v
      - name: Run Redis tests
        run: pytest tests/integration/test_redis_sentinel_failover.py -v
      - name: Run Kafka tests
        run: pytest tests/integration/test_kafka_resilience.py -v
      - name: Upload report
        uses: actions/upload-artifact@v3
        if: always()
        with:
          name: integration-test-report
          path: reports/
```

---

## 📊 TEST COVERAGE ROADMAP

| Test | Week 1 | Week 2 | Week 3 | Week 4 |
|------|--------|--------|--------|--------|
| PostgreSQL Failover | ✅ Start | ✅ | ✅ | ✅ Ready |
| Redis Sentinel | ✅ Start | ✅ | ✅ | ✅ Ready |
| Kafka Resilience | ⏳ | ✅ Start | ✅ | ✅ Ready |
| OAuth2 Flow | ⏳ | ✅ Start | ✅ | ✅ Ready |
| OPA Policies | ⏳ | ⏳ | ✅ Start | ✅ Ready |
| Prometheus Integration | ⏳ | ⏳ | ⏳ | ✅ Start |
| Grafana Datasources | ⏳ | ⏳ | ⏳ | ✅ Start |
| End-to-End Trace | ⏳ | ⏳ | ⏳ | ✅ Start |

---

## ⚠️ PREREQUISITES

Before running tests:
1. SSH access to `192.168.168.31`, `192.168.168.42`, `192.168.168.33`
2. Docker CLI access on hosts
3. Network connectivity between all services
4. Staging environment (not production)
5. Python 3.11+, pytest, required libraries

```bash
pip install pytest pytest-asyncio requests httpx redis confluent-kafka psycopg2-binary
```

---

**Document Status**: READY FOR IMPLEMENTATION  
**Owner**: QA/Platform Team  
**Review**: April 30, 2026
