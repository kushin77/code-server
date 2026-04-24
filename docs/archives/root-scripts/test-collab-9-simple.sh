#!/bin/bash
# Simple staging validation test

TARGET_HOST="${1:-192.168.168.31}"
TARGET_USER="${2:-akushnir}"

echo "=== Collab-9 Staging Validation Test ==="
echo "Target: $TARGET_HOST"
echo ""

# Test 1: code-server HTTP
echo "Test 1: code-server HTTP endpoint..."
response=$(ssh "$TARGET_USER@$TARGET_HOST" "curl -s -o /dev/null -w '%{http_code}' http://localhost:8080/" || echo "000")
if [ "$response" = "302" ]; then
  echo "  ✓ code-server responding with HTTP 302"
else
  echo "  ✗ Expected 302, got $response"
fi

# Test 2: Port connectivity
echo "Test 2: Port 8080 connectivity..."
if ssh "$TARGET_USER@$TARGET_HOST" "timeout 2 nc -zv localhost 8080 2>&1 | grep -q succeeded" 2>/dev/null; then
  echo "  ✓ Port 8080 accepting connections"
else
  echo "  ✗ Port 8080 not responding"
fi

# Test 3: Container status
echo "Test 3: Container health..."
ssh "$TARGET_USER@$TARGET_HOST" "cd code-server-enterprise && docker-compose ps | tail -5"

# Test 4: WebSocket broadcaster code
echo "Test 4: WebSocket broadcaster code..."
if ssh "$TARGET_USER@$TARGET_HOST" "cd code-server-enterprise && [ -f apps/backend/src/services/github-task-sync/websocket-broadcast.ts ]"; then
  echo "  ✓ WebSocket broadcaster present"
else
  echo "  ✗ WebSocket broadcaster missing"
fi

echo ""
echo "=== Staging Validation Complete ==="
