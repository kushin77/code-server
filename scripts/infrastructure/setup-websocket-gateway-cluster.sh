#!/usr/bin/env bash
# @file        scripts/infrastructure/setup-websocket-gateway-cluster.sh
# @module      infrastructure/websocket
# @description Setup 3-node WebSocket relay cluster with HAProxy and Redis Pub/Sub

set -euo pipefail

echo "=========================================="
echo "P1 #1313: WebSocket Gateway Cluster Setup"
echo "=========================================="
echo ""

WEBSOCKET_CONFIG="/etc/websocket-gateway"
HAPROXY_CONFIG="${WEBSOCKET_CONFIG}/haproxy.cfg"
REDIS_CONFIG="${WEBSOCKET_CONFIG}/redis-pubsub.conf"
LOG_DIR="/var/log/websocket-gateway"

setup_websocket_infrastructure() {
    echo "Setting up WebSocket gateway infrastructure..."
    
    mkdir -p "${WEBSOCKET_CONFIG}"
    mkdir -p "${LOG_DIR}"
    
    chmod 0755 "${WEBSOCKET_CONFIG}"
    chmod 0755 "${LOG_DIR}"
    
    echo "✓ Infrastructure directories created"
}

create_haproxy_config() {
    echo "Creating HAProxy configuration for consistent hash routing..."
    
    cat > "${HAPROXY_CONFIG}" << 'EOF'
# HAProxy Configuration for WebSocket Gateway Cluster
# 3-node relay with consistent hash routing based on session_id

global
    log         127.0.0.1 local2
    chroot      /var/lib/haproxy
    pidfile     /run/haproxy.pid
    maxconn     4096
    user        haproxy
    group       haproxy
    daemon
    stats socket /run/haproxy/admin.sock mode 660 level admin
    stats timeout 30s
    
    # Enable HTTP/2 and compression
    tune.ssl.default-dh-param 2048
    tune.http.maxcon 10000

defaults
    log     global
    mode    http
    option  httplog
    option  dontlognull
    timeout connect 5000
    timeout client  50000
    timeout server  50000
    
    # Error pages
    errorfile 400 /etc/haproxy/errors/400.http
    errorfile 403 /etc/haproxy/errors/403.http
    errorfile 408 /etc/haproxy/errors/408.http
    errorfile 500 /etc/haproxy/errors/500.http
    errorfile 502 /etc/haproxy/errors/502.http
    errorfile 503 /etc/haproxy/errors/503.http
    errorfile 504 /etc/haproxy/errors/504.http

# WebSocket Frontend
frontend websocket_frontend
    bind *:8080
    bind *:8443 ssl crt /etc/haproxy/certs/server.pem
    
    mode http
    option httpclose
    option forwardfor except 127.0.0.1
    
    # Upgrade to WebSocket
    http-request add-header Upgrade websocket
    http-request add-header Connection Upgrade
    
    # Extract session_id from query string or cookie for consistent hashing
    stick-table type string len 64 size 100k expire 30m
    stick on cookie(session_id) if !{ req.cook(session_id) -m found }
    stick on query(session_id) if { query(session_id) -m found }
    
    # Route to backend based on consistent hash
    default_backend websocket_backend

# WebSocket Backend - 3-node cluster
backend websocket_backend
    mode http
    balance source  # Consistent hash based on source IP (alternative to sticky sessions)
    
    option httpclose
    option forwardfor
    option http-server-close
    
    # Health check configuration
    option httpchk GET /health HTTP/1.1\r\nHost:\ gateway\r\n
    
    # 3-node WebSocket relay cluster
    server ws-relay-1 192.168.168.31:3001 check inter 2000 rise 2 fall 3 weight 100
    server ws-relay-2 192.168.168.31:3002 check inter 2000 rise 2 fall 3 weight 100
    server ws-relay-3 192.168.168.31:3003 check inter 2000 rise 2 fall 3 weight 100
    
    # Backup server (optional)
    # server ws-relay-backup 192.168.168.42:3001 check backup

# Stats page
listen stats
    bind *:8404
    stats enable
    stats uri /stats
    stats refresh 30s
    stats show-legends
    stats show-node
    stats admin if TRUE
EOF
    
    echo "✓ HAProxy configuration created: ${HAPROXY_CONFIG}"
}

create_websocket_relay_service() {
    echo "Creating WebSocket relay service configuration..."
    
    cat > "${WEBSOCKET_CONFIG}/websocket-relay.js" << 'EOF'
#!/usr/bin/env node
/**
 * WebSocket Relay Service
 * Forwards connections to workspace sessions via Redis Pub/Sub
 */

const express = require('express');
const http = require('http');
const WebSocket = require('ws');
const redis = require('redis');

const PORT = process.env.PORT || 3001;
const REDIS_URL = process.env.REDIS_URL || 'redis://localhost:6379';
const NODE_ID = process.env.NODE_ID || 'ws-relay-1';

// Initialize Express and WebSocket server
const app = express();
const server = http.createServer(app);
const wss = new WebSocket.Server({ server });

// Redis clients for Pub/Sub
const redisPublisher = redis.createClient(REDIS_URL);
const redisSubscriber = redis.createClient(REDIS_URL);

// Session store (session_id → connection mapping)
const sessionConnections = new Map();

// Health check endpoint
app.get('/health', (req, res) => {
    res.json({
        status: 'healthy',
        node: NODE_ID,
        sessions: sessionConnections.size,
        uptime: process.uptime()
    });
});

// WebSocket connection handler
wss.on('connection', (ws, req) => {
    const sessionId = req.url.split('session_id=')[1] || 'unknown';
    
    console.log(`[${NODE_ID}] New connection: ${sessionId}`);
    
    // Track this connection
    if (!sessionConnections.has(sessionId)) {
        sessionConnections.set(sessionId, []);
    }
    sessionConnections.get(sessionId).push(ws);
    
    // Subscribe to session channel for incoming messages
    const sessionChannel = `workspace:${sessionId}:messages`;
    redisSubscriber.subscribe(sessionChannel, (err) => {
        if (err) console.error(`Failed to subscribe: ${err}`);
    });
    
    // Handle messages from client
    ws.on('message', (data) => {
        try {
            const message = JSON.parse(data);
            
            // Publish to other workspace processes
            const broadcastChannel = `workspace:${sessionId}:incoming`;
            redisPublisher.publish(broadcastChannel, JSON.stringify({
                from: NODE_ID,
                timestamp: Date.now(),
                payload: message
            }));
        } catch (err) {
            console.error(`Message parse error: ${err}`);
        }
    });
    
    // Handle client disconnect
    ws.on('close', () => {
        console.log(`[${NODE_ID}] Connection closed: ${sessionId}`);
        
        const connections = sessionConnections.get(sessionId);
        if (connections) {
            const idx = connections.indexOf(ws);
            if (idx > -1) connections.splice(idx, 1);
            
            if (connections.length === 0) {
                sessionConnections.delete(sessionId);
                redisSubscriber.unsubscribe(`workspace:${sessionId}:messages`);
            }
        }
    });
    
    ws.on('error', (err) => {
        console.error(`[${NODE_ID}] WebSocket error: ${err}`);
    });
});

// Subscribe to Redis for outgoing messages
redisSubscriber.on('message', (channel, message) => {
    try {
        const data = JSON.parse(message);
        const sessionId = channel.split(':')[1];
        const connections = sessionConnections.get(sessionId);
        
        if (connections) {
            connections.forEach(ws => {
                if (ws.readyState === WebSocket.OPEN) {
                    ws.send(JSON.stringify(data));
                }
            });
        }
    } catch (err) {
        console.error(`Redis message error: ${err}`);
    }
});

// Graceful shutdown
process.on('SIGTERM', () => {
    console.log(`[${NODE_ID}] Shutting down...`);
    
    // Close all WebSocket connections
    wss.clients.forEach(client => {
        client.close();
    });
    
    // Close Redis connections
    redisPublisher.quit();
    redisSubscriber.quit();
    
    server.close(() => {
        process.exit(0);
    });
});

// Start server
server.listen(PORT, '0.0.0.0', () => {
    console.log(`[${NODE_ID}] WebSocket relay listening on port ${PORT}`);
    console.log(`[${NODE_ID}] Redis URL: ${REDIS_URL}`);
});
EOF
    
    chmod +x "${WEBSOCKET_CONFIG}/websocket-relay.js"
    echo "✓ WebSocket relay service created"
}

create_redis_pubsub_config() {
    echo "Creating Redis Pub/Sub configuration..."
    
    cat > "${REDIS_CONFIG}" << 'EOF'
# Redis configuration for WebSocket Pub/Sub fan-out
# This enables message broadcasting between WebSocket relay nodes and workspace services

# Server configuration
port 6379
bind 0.0.0.0
tcp-backlog 511
timeout 0
tcp-keepalive 300

# Memory management
maxmemory 2gb
maxmemory-policy allkeys-lru

# Persistence (optional - adjust for your needs)
save 900 1
save 300 10
save 60 10000

# Logging
loglevel notice
logfile "/var/log/redis/redis-pubsub.log"

# Pub/Sub optimization
pubsub-hardrefcount 31

# Channels we'll use:
# - workspace:{session_id}:messages - Outgoing messages to clients
# - workspace:{session_id}:incoming - Incoming messages from clients
# - gateway:cluster:status - Cluster status updates
# - gateway:metrics - Performance metrics

# Keys will have no expiration (Pub/Sub is ephemeral)
# Use separate Redis instance for caching with TTL

# Replication (if using Redis Sentinel for HA)
# slaveof 192.168.168.31 6379
# masterauth your_password

# Security
requirepass your_redis_password_here

# ACL configuration (Redis 6+)
# user default on >your_password_here ~* &* +@all
# user pubsub on >pubsub_password_here ~* &* +publish|+subscribe
EOF
    
    echo "✓ Redis Pub/Sub configuration created: ${REDIS_CONFIG}"
}

create_systemd_service() {
    echo "Creating systemd services for WebSocket relay nodes..."
    
    # Service template
    cat > "${WEBSOCKET_CONFIG}/websocket-relay@.service" << 'EOF'
[Unit]
Description=WebSocket Relay Node %i
After=network.target redis.service
Requires=redis.service

[Service]
Type=simple
User=websocket-relay
Group=websocket-relay
WorkingDirectory=/opt/websocket-gateway
Environment="NODE_ID=ws-relay-%i"
Environment="PORT=300%i"
Environment="REDIS_URL=redis://localhost:6379"
ExecStart=/usr/bin/node /etc/websocket-gateway/websocket-relay.js
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal
SyslogIdentifier=ws-relay-%i

# Resource limits
MemoryLimit=512M
CPUQuota=50%

[Install]
WantedBy=multi-user.target
EOF
    
    echo "✓ Systemd service template created"
}

main() {
    echo ""
    setup_websocket_infrastructure
    echo ""
    
    create_haproxy_config
    echo ""
    
    create_websocket_relay_service
    echo ""
    
    create_redis_pubsub_config
    echo ""
    
    create_systemd_service
    echo ""
    
    echo "=========================================="
    echo "WebSocket Gateway Cluster Configuration"
    echo "=========================================="
    echo ""
    echo "Configuration files created:"
    echo "  - HAProxy: ${HAPROXY_CONFIG}"
    echo "  - WebSocket Relay: ${WEBSOCKET_CONFIG}/websocket-relay.js"
    echo "  - Redis Pub/Sub: ${REDIS_CONFIG}"
    echo "  - Systemd Services: ${WEBSOCKET_CONFIG}/websocket-relay@.service"
    echo ""
    echo "Cluster Architecture:"
    echo "  Frontend: HAProxy (port 8080, 8443)"
    echo "  Backend: 3-node WebSocket relay cluster (ports 3001-3003)"
    echo "  Message Bus: Redis Pub/Sub (port 6379)"
    echo ""
    echo "Next Steps:"
    echo "  1. Install HAProxy: apt-get install haproxy"
    echo "  2. Install Redis: apt-get install redis-server"
    echo "  3. Install Node.js dependencies: npm install ws redis express"
    echo "  4. Copy systemd services to /etc/systemd/system/"
    echo "  5. Enable services: systemctl enable websocket-relay@{1,2,3}"
    echo "  6. Start cluster: systemctl start websocket-relay@{1,2,3}"
    echo ""
}

main
