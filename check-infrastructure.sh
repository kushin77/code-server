#!/bin/bash

# Error handling
trap 'echo "[ERROR] Script failed at line $LINENO"; exit 1' ERR
trap 'echo "[INFO] Cleanup completed"; rm -f /tmp/infra_check_*.tmp 2>/dev/null || true' EXIT

export PRIMARY_HOST=192.168.168.31
export SECONDARY_HOST=192.168.168.42

echo "[INFO] Checking infrastructure..."

# Check DB Replication
echo "[INFO] Checking database replication..."
ssh -o ConnectTimeout=5 akushnir@$PRIMARY_HOST "docker exec purebliss-postgres-instance psql -U purebliss_user -d purebliss_db -c \"SELECT * FROM pg_stat_replication;\"" || echo "[WARN] DB replication check failed"

# Check API Health
echo "[INFO] Checking API health..."
curl -s -m 5 http://192.168.168.31:8080/health | jq . || echo "[WARN] API health check failed"

# Check Container Statuses
echo "[INFO] Checking container statuses..."
ssh -o ConnectTimeout=5 akushnir@$PRIMARY_HOST "docker ps --format \"{{.Names}}: {{.Status}}\"" || echo "[WARN] Container status check failed"

echo "[OK] Infrastructure check completed"
