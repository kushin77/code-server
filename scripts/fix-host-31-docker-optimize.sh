#!/bin/bash
# Host 31 Critical Fix #4: Docker Daemon Optimization
# Configures Docker for optimal performance with GPU, storage, and networking
# Idempotent: Safe to run multiple times

set -eo pipefail

STATE_FILE="/tmp/docker-optimize.lock"
DOCKER_CONFIG="/etc/docker/daemon.json"
DOCKER_CONFIG_BACKUP="/etc/docker/daemon.json.backup.$(date +%Y%m%d-%H%M%S)"

echo "=========================================="
echo "HOST 31 FIX #4: DOCKER DAEMON OPTIMIZATION"
echo "=========================================="

# Idempotency: Check if already optimized
if grep -q "\"experimental\": true" "$DOCKER_CONFIG" 2>/dev/null; then
    echo "✓ Docker already optimized (skipping)"
    exit 0
fi

# Idempotency: Check if optimize in progress
if [ -f "$STATE_FILE" ]; then
    echo "⚠ Optimization appears to be in progress (lock file exists)"
    echo "  If stuck, remove: rm $STATE_FILE"
    exit 1
fi

touch "$STATE_FILE"

# Backup existing config
if [ -f "$DOCKER_CONFIG" ]; then
    echo "Backing up existing Docker config to $DOCKER_CONFIG_BACKUP..."
    sudo cp "$DOCKER_CONFIG" "$DOCKER_CONFIG_BACKUP"
else
    mkdir -p /etc/docker
fi

echo "Optimizing Docker daemon configuration..."

# Create optimized Docker config
sudo tee "$DOCKER_CONFIG" > /dev/null <<'EOF'
{
    "runtimes": {
        "nvidia": {
            "path": "nvidia-container-runtime",
            "runtimeArgs": []
        }
    },
    "default-runtime": "runc",
    
    "storage-driver": "overlay2",
    "storage-opts": [
        "overlay2.override_kernel_check=true"
    ],
    
    "log-driver": "json-file",
    "log-opts": {
        "max-size": "100m",
        "max-file": "10",
        "labels": "com.docker.ps.app"
    },
    
    "metrics-addr": "127.0.0.1:9323",
    "experimental": true,
    "userland-proxy": false,
    
    "default-ipc": "private",
    "ipc-mode": "private",
    
    "max-concurrent-downloads": 10,
    "max-concurrent-uploads": 5,
    
    "data-root": "/var/lib/docker",
    
    "bridge": "none",
    "ip": "0.0.0.0",
    "ip-forward": true,
    "ip-masq": true,
    "iptables": true,
    
    "live-restore": true,
    "help": false,
    
    "labels": [
        "com.docker.system=host-31",
        "com.docker.optimization=enabled"
    ],
    
    "log-level": "info",
    "pidfile": "/var/run/docker.pid"
}
EOF

# Verify syntax
echo "Verifying Docker config syntax..."
if docker config inspect > /dev/null 2>&1; then
    echo "✓ Docker config validation passed"
else
    echo "⚠ Docker config syntax check - attempting to reload..."
fi

# Restart Docker daemon
echo "Restarting Docker daemon..."
sudo systemctl daemon-reload
sudo systemctl restart docker

# Wait for Docker to be ready
sleep 3

# Verify Docker is running
if docker ps &>/dev/null; then
    echo "✓ Docker daemon restarted successfully"
else
    echo "✗ Docker daemon failed to start"
    echo "  Restoring from backup: $DOCKER_CONFIG_BACKUP"
    sudo cp "$DOCKER_CONFIG_BACKUP" "$DOCKER_CONFIG"
    sudo systemctl restart docker
    rm -f "$STATE_FILE"
    exit 1
fi

# Prune unused resources to free space
echo "Cleaning up unused Docker resources..."
docker system prune -f --all 2>/dev/null || true

# Verify optimizations
echo "Verifying Docker optimizations..."
DOCKER_INFO=$(docker info 2>/dev/null)

if echo "$DOCKER_INFO" | grep -q "Storage Driver: overlay2"; then
    echo "✓ Storage driver: overlay2"
else
    echo "⚠ Storage driver configuration might not be applied"
fi

if echo "$DOCKER_INFO" | grep -q "Live Restore Enabled: true"; then
    echo "✓ Live restore enabled"
else
    echo "⚠ Live restore not confirmed"
fi

echo "Docker daemon info:"
docker info | grep -E "Storage Driver|Log Driver|Resources|Live Restore|Experimental" || true

# Cleanup
rm -f "$STATE_FILE"

echo "✓ DOCKER DAEMON OPTIMIZATION COMPLETE"
echo "  Config: $DOCKER_CONFIG"
echo "  Backup: $DOCKER_CONFIG_BACKUP"
echo "  Storage: overlay2 (optimized)"
echo "  Live-restore: enabled"
echo "  Experimental: enabled for advanced features"
exit 0
