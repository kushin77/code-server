#!/bin/bash
# P2 #422 - PRIMARY/REPLICA HA CLUSTER DEPLOYMENT
# Patroni + etcd + Redis Sentinel + HAProxy
# Deployment automation script for production

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/ha-deployment-$(date +%Y%m%d-%H%M%S).log"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Logging functions
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $*" | tee -a "$LOG_FILE"
}

error() {
    echo -e "${RED}[ERROR]${NC} $*" | tee -a "$LOG_FILE" >&2
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $*" | tee -a "$LOG_FILE"
}

# ============================================================================
# CREATE REDIS SENTINEL CONFIGURATION
# ============================================================================
create_redis_sentinel_configs() {
    log "Creating Redis Sentinel configurations..."
    
    mkdir -p config/redis-sentinel
    
    # Redis Primary Configuration
    cat > config/redis-sentinel/redis-primary.conf <<'EOF'
# Redis Primary Configuration
port 6379
bind 0.0.0.0
protected-mode no
daemonize no
pidfile /var/run/redis/redis-server.pid
loglevel notice
logfile ""
databases 16
save 900 1
save 300 10
save 60 10000
rdbcompression yes
dbfilename dump.rdb
dir /data
replica-serve-stale-data yes
replica-read-only yes
repl-diskless-sync no
repl-diskless-sync-delay 5
repl-disable-tcp-nodelay no
replica-priority 100
lazyfree-lazy-eviction no
lazyfree-lazy-expire no
lazyfree-lazy-server-del no
replica-lazy-flush no
appendonly yes
appendfilename "appendonly.aof"
appendfsync everysec
no-appendfsync-on-rewrite no
auto-aof-rewrite-percentage 100
auto-aof-rewrite-min-size 64mb
aof-load-truncated yes
aof-use-rdb-preamble yes
lua-time-limit 5000
slowlog-log-slower-than 10000
slowlog-max-len 128
latency-monitor-threshold 0
notify-keyspace-events ""
hash-max-ziplist-entries 512
hash-max-ziplist-value 64
list-max-ziplist-size -2
list-compress-depth 0
set-max-intset-entries 512
zset-max-ziplist-entries 128
zset-max-ziplist-value 64
hll-sparse-max-bytes 3000
stream-node-max-bytes 4096
stream-node-max-entries 100
activerehashing yes
client-output-buffer-limit normal 0 0 0
client-output-buffer-limit replica 256mb 64mb 60
client-output-buffer-limit pubsub 32mb 8mb 60
hz 10
dynamic-hz yes
aof-rewrite-incremental-fsync yes
EOF
    
    # Sentinel 1 Configuration
    cat > config/redis-sentinel/sentinel-1.conf <<'EOF'
port 26379
bind 0.0.0.0
protected-mode no
daemonize no
pidfile /var/run/redis-sentinel.pid
loglevel notice
logfile ""

sentinel monitor redis-primary redis-primary 6379 2
sentinel down-after-milliseconds redis-primary 5000
sentinel parallel-syncs redis-primary 1
sentinel failover-timeout redis-primary 10000

sentinel deny-scripts-reconfig yes
EOF
    
    # Sentinel 2 Configuration
    cat > config/redis-sentinel/sentinel-2.conf <<'EOF'
port 26379
bind 0.0.0.0
protected-mode no
daemonize no
pidfile /var/run/redis-sentinel.pid
loglevel notice
logfile ""

sentinel monitor redis-primary redis-primary 6379 2
sentinel down-after-milliseconds redis-primary 5000
sentinel parallel-syncs redis-primary 1
sentinel failover-timeout redis-primary 10000

sentinel deny-scripts-reconfig yes
EOF
    
    log "✓ Redis Sentinel configurations created"
}

# ============================================================================
# CREATE HAPROXY CONFIGURATION
# ============================================================================
create_haproxy_config() {
    log "Creating HAProxy configuration..."
    
    mkdir -p config/haproxy
    
    cat > config/haproxy/haproxy.cfg <<'EOF'
global
    log stdout local0
    log stdout local1 notice
    chroot /var/lib/haproxy
    pidfile /var/run/haproxy.pid
    maxconn 4096
    daemon

    # TLS defaults
    ssl-default-bind-ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256
    ssl-default-bind-options ssl-min-ver TLSv1.2 no-tls-tickets

defaults
    log     global
    mode    tcp
    option  tcplog
    option  dontlognull
    timeout connect 5000
    timeout client  50000
    timeout server  50000
    errorfile 400 /usr/local/etc/haproxy/errors/400.http
    errorfile 403 /usr/local/etc/haproxy/errors/403.http
    errorfile 408 /usr/local/etc/haproxy/errors/408.http
    errorfile 500 /usr/local/etc/haproxy/errors/500.http
    errorfile 502 /usr/local/etc/haproxy/errors/502.http
    errorfile 503 /usr/local/etc/haproxy/errors/503.http
    errorfile 504 /usr/local/etc/haproxy/errors/504.http

# ============================================================================
# STATISTICS
# ============================================================================
listen statistics
    bind :8404
    stats enable
    stats uri /stats
    stats refresh 30s
    stats show-legends
    stats show-node
    stats admin if TRUE

# ============================================================================
# PostgreSQL LOAD BALANCER (Patroni Primary Detection)
# ============================================================================
listen pgsql-lb
    bind :5432
    mode tcp
    balance roundrobin
    timeout connect 3000
    timeout client  600000
    timeout server  600000
    
    # Primary backend with health check via Patroni REST API (port 8008)
    server patroni-primary patroni-primary:5432 check port 8008 inter 10s fastinter 3s fall 3 rise 2
    
    # Replica backup (auto-promoted on primary failure)
    # server patroni-replica patroni-replica:5432 check port 8008 inter 10s backup
    
    # Monitor options
    option httpchk GET /health
    http-check expect status 200

# ============================================================================
# Redis LOAD BALANCER (Sentinel-Managed)
# ============================================================================
listen redis-lb
    bind :6379
    mode tcp
    balance roundrobin
    timeout connect 3000
    timeout client  600000
    timeout server  600000
    
    # Primary Redis with health check
    server redis-primary redis-primary:6379 check inter 10s fastinter 3s fall 3 rise 2
EOF
    
    log "✓ HAProxy configuration created"
}

# ============================================================================
# CREATE PATRONI CONFIGURATION
# ============================================================================
create_patroni_config() {
    log "Creating Patroni configuration..."
    
    mkdir -p config/patroni
    
    # pgpass for replication credentials
    cat > config/patroni/pgpass <<'EOF'
# PostgreSQL Password File
*:*:*:postgres:${POSTGRES_PASSWORD}
*:*:*:repuser:${REPLICATION_PASSWORD}
EOF
    chmod 600 config/patroni/pgpass
    
    log "✓ Patroni configuration created (pgpass with env vars)"
}

# ============================================================================
# DEPLOY HA CLUSTER
# ============================================================================
deploy_ha_cluster() {
    log "Deploying HA cluster services..."
    
    # Check if docker-compose.ha.yml exists
    if [ ! -f "docker-compose.ha.yml" ]; then
        error "docker-compose.ha.yml not found!"
        exit 1
    fi
    
    log "Starting etcd cluster..."
    docker-compose -f docker-compose.ha.yml up -d etcd-primary
    sleep 10
    
    # Verify etcd health
    if docker-compose -f docker-compose.ha.yml exec -T etcd-primary etcdctl --endpoints=http://localhost:2379 endpoint health > /dev/null 2>&1; then
        log "✓ etcd cluster healthy"
    else
        error "etcd health check failed"
        exit 1
    fi
    
    log "Starting Patroni PostgreSQL cluster..."
    docker-compose -f docker-compose.ha.yml up -d patroni-primary
    sleep 15
    
    # Verify Patroni health
    if docker-compose -f docker-compose.ha.yml exec -T patroni-primary curl -sf http://localhost:8008/health > /dev/null 2>&1; then
        log "✓ Patroni primary healthy"
    else
        error "Patroni health check failed"
        exit 1
    fi
    
    log "Starting Redis cluster and Sentinels..."
    docker-compose -f docker-compose.ha.yml up -d redis-primary redis-sentinel-1 redis-sentinel-2
    sleep 10
    
    # Verify Redis health
    if docker-compose -f docker-compose.ha.yml exec -T redis-primary redis-cli ping | grep -q PONG; then
        log "✓ Redis primary healthy"
    else
        error "Redis health check failed"
        exit 1
    fi
    
    # Verify Sentinel health
    if docker-compose -f docker-compose.ha.yml exec -T redis-sentinel-1 redis-cli -p 26379 ping | grep -q PONG; then
        log "✓ Redis Sentinel 1 healthy"
    else
        error "Redis Sentinel 1 health check failed"
        exit 1
    fi
    
    log "Starting HAProxy load balancer..."
    docker-compose -f docker-compose.ha.yml up -d haproxy
    sleep 5
    
    # Verify HAProxy health
    if docker-compose -f docker-compose.ha.yml exec -T haproxy wget -q -O - http://localhost:8404/stats > /dev/null 2>&1; then
        log "✓ HAProxy healthy"
    else
        error "HAProxy health check failed"
        exit 1
    fi
    
    log "✓ All HA services deployed successfully"
}

# ============================================================================
# VERIFY CLUSTER STATUS
# ============================================================================
verify_cluster() {
    log "Verifying HA cluster status..."
    
    echo ""
    log "=== etcd Cluster Status ==="
    docker-compose -f docker-compose.ha.yml exec -T etcd-primary etcdctl --endpoints=http://localhost:2379 member list || warn "Failed to get etcd members"
    
    echo ""
    log "=== Patroni Cluster Status ==="
    docker-compose -f docker-compose.ha.yml exec -T patroni-primary patronictl -c /var/lib/patroni/patroni.yml list || warn "Failed to get Patroni status"
    
    echo ""
    log "=== PostgreSQL Replication Status ==="
    docker-compose -f docker-compose.ha.yml exec -T patroni-primary psql -U postgres -d postgres -c "SELECT slot_name, slot_type, active FROM pg_replication_slots;" || warn "Failed to get replication slots"
    
    echo ""
    log "=== Redis Status ==="
    docker-compose -f docker-compose.ha.yml exec -T redis-primary redis-cli info replication | grep -E "(role|connected)" || warn "Failed to get Redis status"
    
    echo ""
    log "=== Redis Sentinel Status ==="
    docker-compose -f docker-compose.ha.yml exec -T redis-sentinel-1 redis-cli -p 26379 sentinel masters || warn "Failed to get Sentinel status"
    
    echo ""
    log "=== HAProxy Statistics ==="
    docker-compose -f docker-compose.ha.yml exec -T haproxy wget -q -O - http://localhost:8404/stats 2>/dev/null | head -30 || warn "Failed to get HAProxy stats"
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================
main() {
    log "Starting P2 #422 HA Cluster Deployment"
    log "=========================================="
    
    # Create all configurations
    create_redis_sentinel_configs
    create_haproxy_config
    create_patroni_config
    
    # Deploy services
    deploy_ha_cluster
    
    # Verify everything
    verify_cluster
    
    log "=========================================="
    log "✓ P2 #422 HA Cluster Deployment COMPLETE"
    log ""
    log "Endpoints:"
    log "  PostgreSQL (via HAProxy): localhost:5432"
    log "  Redis (via HAProxy):      localhost:6379"
    log "  Patroni REST API:         http://localhost:8008"
    log "  Redis Sentinel 1:         localhost:26379"
    log "  Redis Sentinel 2:         localhost:26380"
    log "  HAProxy Stats:            http://localhost:8404/stats"
    log ""
    log "Next steps:"
    log "  1. Test failover: Kill patroni-primary container and verify replica promotion"
    log "  2. Monitor logs: docker-compose -f docker-compose.ha.yml logs -f"
    log "  3. Configure replica: Deploy docker-compose.ha.yml on 192.168.168.42 with updated etcd cluster config"
}

main "$@"
