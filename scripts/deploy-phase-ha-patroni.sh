#!/bin/bash
# scripts/deploy-phase-ha-patroni.sh
# P2 #422: Primary/Replica HA - Patroni Cluster Setup
# Purpose: Deploy PostgreSQL HA orchestration with automatic failover

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
TERRAFORM_DIR="${PROJECT_ROOT}/terraform"

# Configuration
PRIMARY_HOST="${PRIMARY_HOST:-192.168.168.31}"
REPLICA_HOST="${REPLICA_HOST:-192.168.168.42}"
PATRONI_VERSION="${PATRONI_VERSION:-3.0.1}"
ETCD_VERSION="${ETCD_VERSION:-3.5.10}"

echo "════════════════════════════════════════════════════════════"
echo "PHASE: HA CLUSTER DEPLOYMENT - Patroni (PostgreSQL HA)"
echo "════════════════════════════════════════════════════════════"
echo ""
echo "Primary Host: ${PRIMARY_HOST}"
echo "Replica Host: ${REPLICA_HOST}"
echo ""

# Step 1: Deploy etcd cluster (Patroni needs a DCS)
echo "Step 1: Setup etcd distributed consensus store..."
cat > "${PROJECT_ROOT}/docker-compose.ha.yml" << 'EOF'
version: '3.8'

services:
  # etcd - Distributed consensus store for Patroni leader election
  etcd-primary:
    image: quay.io/coreos/etcd:v3.5.10
    container_name: etcd-primary
    environment:
      - ETCD_LISTEN_CLIENT_URLS=http://0.0.0.0:2379
      - ETCD_ADVERTISE_CLIENT_URLS=http://etcd-primary:2379
      - ETCD_LISTEN_PEER_URLS=http://0.0.0.0:2380
      - ETCD_INITIAL_ADVERTISE_PEER_URLS=http://etcd-primary:2380
      - ETCD_INITIAL_CLUSTER=etcd-primary=http://etcd-primary:2380,etcd-replica=http://etcd-replica:2380
      - ETCD_INITIAL_CLUSTER_STATE=new
      - ETCD_INITIAL_CLUSTER_TOKEN=patroni-cluster
      - ETCD_NAME=etcd-primary
    ports:
      - "2379:2379"
      - "2380:2380"
    volumes:
      - etcd-data-primary:/etcd-data
    healthcheck:
      test: ["CMD", "etcdctl", "--endpoints=http://localhost:2379", "endpoint", "health"]
      interval: 10s
      timeout: 5s
      retries: 3

  # Patroni - PostgreSQL HA manager
  patroni-primary:
    image: patroni:3.0.1
    container_name: patroni-primary
    depends_on:
      - etcd-primary
    environment:
      - PATRONI_SCOPE=codeserver
      - PATRONI_POSTGRESQL_DATA_DIR=/var/lib/postgresql/data
      - PATRONI_POSTGRESQL_PGPASS=/tmp/.pgpass
      - PATRONI_POSTGRESQL_PARAMETERS=max_wal_senders=10,max_replication_slots=10,wal_level=replica
      - PATRONI_RESTAPI_LISTEN=0.0.0.0:8008
      - PATRONI_ETCD_HOST=etcd-primary:2379
      - PATRONI_POSTGRESQL_INITDB_ARGS=-c shared_preload_libraries=pg_stat_statements
      - PATRONI_POSTGRESQL_LISTEN=0.0.0.0:5432
    ports:
      - "5432:5432"
      - "8008:8008"
    volumes:
      - postgres-data-primary:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD", "patronictl", "-c", "/etc/patroni/patroni.yml", "list"]
      interval: 10s
      timeout: 5s
      retries: 3

volumes:
  etcd-data-primary:
  postgres-data-primary:

networks:
  default:
    name: ha-cluster
EOF

# Step 2: Create docker-compose override for HA mode
echo "Step 2: Configuring docker-compose for HA services..."

cat >> "${PROJECT_ROOT}/docker-compose.yml" << 'EOF'

  # Redis Sentinel - Redis HA cluster manager
  redis-sentinel-1:
    image: redis:7-alpine
    container_name: redis-sentinel-1
    command: redis-sentinel /etc/sentinel/sentinel.conf
    ports:
      - "26379:26379"
    volumes:
      - ./config/redis-sentinel-1.conf:/etc/sentinel/sentinel.conf:ro
      - sentinel-data-1:/data
    depends_on:
      - redis
    healthcheck:
      test: ["CMD", "redis-cli", "-p", "26379", "ping"]
      interval: 10s
      timeout: 5s
      retries: 3

  redis-sentinel-2:
    image: redis:7-alpine
    container_name: redis-sentinel-2
    command: redis-sentinel /etc/sentinel/sentinel.conf
    ports:
      - "26380:26379"
    volumes:
      - ./config/redis-sentinel-2.conf:/etc/sentinel/sentinel.conf:ro
      - sentinel-data-2:/data
    depends_on:
      - redis
    healthcheck:
      test: ["CMD", "redis-cli", "-p", "26379", "ping"]
      interval: 10s
      timeout: 5s
      retries: 3

volumes:
  sentinel-data-1:
  sentinel-data-2:
EOF

echo "✓ docker-compose.ha.yml created with etcd + Patroni"

# Step 3: Create Redis Sentinel configuration files
echo "Step 3: Creating Redis Sentinel configuration..."

cat > "${PROJECT_ROOT}/config/redis-sentinel-1.conf" << 'EOF'
# Redis Sentinel configuration - Instance 1
port 26379
dir /data
logfile ""

# Monitor Redis with quorum=2 (need 2 Sentinels to agree on failover)
sentinel monitor mymaster redis 6379 2
sentinel down-after-milliseconds mymaster 5000
sentinel parallel-syncs mymaster 1
sentinel failover-timeout mymaster 10000

# Enable auth if Redis has password
# sentinel auth-pass mymaster PASSWORD

# Logging
sentinel loglevel notice
EOF

cat > "${PROJECT_ROOT}/config/redis-sentinel-2.conf" << 'EOF'
# Redis Sentinel configuration - Instance 2
port 26379
dir /data
logfile ""

# Monitor Redis with quorum=2
sentinel monitor mymaster redis 6379 2
sentinel down-after-milliseconds mymaster 5000
sentinel parallel-syncs mymaster 1
sentinel failover-timeout mymaster 10000

sentinel loglevel notice
EOF

echo "✓ Redis Sentinel configs created"

# Step 4: Create HAProxy configuration for VIP
echo "Step 4: Creating HAProxy load balancer configuration..."

cat > "${PROJECT_ROOT}/config/haproxy.cfg" << 'EOF'
global
  log stdout local0
  log stdout local1 notice
  chroot /var/lib/haproxy
  stats socket /run/haproxy/admin.sock mode 660 level admin
  stats timeout 30s
  user haproxy
  group haproxy
  daemon
  maxconn 4096

defaults
  log     global
  mode    tcp
  timeout connect 5s
  timeout client  30s
  timeout server  30s

# PostgreSQL Primary (automatic failover via Patroni)
listen postgresql-primary
  bind 0.0.0.0:5432
  mode tcp
  balance roundrobin
  option tcplog
  default_backend pg-primary

backend pg-primary
  mode tcp
  balance roundrobin
  # Patroni automatically updates master via Consul/etcd
  server pg-node1 192.168.168.31:5432 check port 8008 inter 3s fastinter 1s downinter 5s rise 3 fall 3
  server pg-node2 192.168.168.42:5432 check port 8008 inter 3s fastinter 1s downinter 5s rise 3 fall 3 backup

# Redis - Primary with Sentinel failover
listen redis-primary
  bind 0.0.0.0:6379
  mode tcp
  balance roundrobin
  timeout connect 5s
  timeout server  30s
  default_backend redis-primary

backend redis-primary
  mode tcp
  # Sentinel monitors this backend, updates via Redis Sentinel API
  server redis-node1 192.168.168.31:6379 check inter 3s fall 3
  server redis-node2 192.168.168.42:6379 check inter 3s fall 3 backup

# HAProxy stats
listen stats
  bind 0.0.0.0:8404
  stats enable
  stats uri /stats
  stats refresh 30s
EOF

echo "✓ HAProxy configuration created"

# Step 5: Create Patroni configuration template
echo "Step 5: Creating Patroni configuration..."

cat > "${PROJECT_ROOT}/config/patroni.yml" << 'EOF'
scope: codeserver
namespace: /codeserver/

restapi:
  listen: 0.0.0.0:8008
  connect_address: HOSTNAME:8008

etcd:
  host: etcd-primary:2379

postgresql:
  data_dir: /var/lib/postgresql/data
  parameters:
    max_wal_senders: 10
    max_replication_slots: 10
    wal_level: replica
    hot_standby: on
    wal_keep_size: 1GB
  use_pg_rewind: true
  use_slots: true
  recovery_conf:
    restore_command: 'cp /var/lib/postgresql/wal_archive/%f %p'

initdb:
  - encoding: UTF8
  - locale: en_US.UTF-8
  - data-checksums

pg_hba:
  - local    all             postgres                peer
  - local    all             all                     peer
  - host     all             all      127.0.0.1/32  md5
  - host     all             all      ::1/128       md5
  - host     replication     postgres 192.168.168.0/24 md5

# Bootstrap settings (first initialization only)
bootstrap:
  method: initdb
  dcs:
    ttl: 30
    loop_wait: 10
    retry_timeout: 10
    maximum_lag_on_failover: 1048576
    primary_start_timeout: 300

  initdb:
    - encoding: UTF8
    - locale: en_US.UTF-8

tags:
  nofailover: false
  noloadbalance: false
  clonefrom: false
  nosync: false
EOF

echo "✓ Patroni configuration created"

# Step 6: Deployment instructions
echo ""
echo "════════════════════════════════════════════════════════════"
echo "DEPLOYMENT STEPS"
echo "════════════════════════════════════════════════════════════"
echo ""
echo "ON PRIMARY (192.168.168.31):"
echo "  1. docker-compose -f docker-compose.ha.yml up -d"
echo "  2. Wait for etcd + Patroni to start (30 seconds)"
echo "  3. docker-compose exec patroni-primary psql -U postgres -c \"SELECT version();\""
echo ""
echo "ON REPLICA (192.168.168.42):"
echo "  1. Copy docker-compose.ha.yml to replica"
echo "  2. Update ETCD_INITIAL_CLUSTER: etcd-replica=http://etcd-replica:2380"
echo "  3. docker-compose -f docker-compose.ha.yml up -d"
echo ""
echo "VERIFY HA CLUSTER:"
echo "  # Check Patroni status"
echo "  docker-compose exec patroni-primary patronictl -c /etc/patroni/patroni.yml list"
echo ""
echo "  # Check Redis Sentinel"
echo "  redis-cli -p 26379 sentinel masters"
echo ""
echo "  # Test automatic failover (stop primary)"
echo "  docker-compose kill patroni-primary"
echo "  # Observe: Patroni elects replica as new primary within 10s"
echo ""
echo "════════════════════════════════════════════════════════════"
echo "✓ HA CLUSTER CONFIGURATION READY FOR DEPLOYMENT"
echo "════════════════════════════════════════════════════════════"
